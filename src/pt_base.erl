%%%-------------------------------------------------------------------
%%% -*- coding: utf-8 -*-
%%% @author Timofey Barmin
%%% @copyright (C) 2015, Eltex, Novosibirsk, Russia
%%% @doc
%%%     Main library parse transformation.
%%%     Replace 'functions' ast/2 and ast_pattern/2 with real erlang expressions and patterns
%%% @end
%%%-------------------------------------------------------------------
-module(pt_base).

-include("pt_error_macro.hrl").
-include("pt_supp.hrl").

-export([parse_transform/2, format_error/1]).

-export([parse_str_debug/1, process_additional_syntax/2]).

%%--------------------------------------------------------------------
%% @doc
%%          parse_transforming of parse_transform script
%% @end
%%--------------------------------------------------------------------
parse_transform(AST, _Options) ->
    try
        ?PT_DBG("AST: ~p", [AST]),

        AST2 = pt_supp:replace_local_call(AST, ast, fun replace_function/2, nothing),
        AST3 = pt_supp:replace_remote_call(AST2, pt_lib, replace, fun replace_function/2, nothing),
        AST4 = pt_supp:replace_remote_call(AST3, pt_lib, replace_fold, fun replace_function/2, nothing),
        AST5 = pt_supp:replace_remote_call(AST4, pt_lib, replace_first, fun replace_function/2, nothing),
        AST6 = pt_supp:replace_remote_call(AST5, pt_lib, match, fun replace_function/2, nothing),
        AST7 = pt_supp:replace_remote_call(AST6, pt_lib, first_clause, fun replace_function/2, nothing),
        AST8 = [replace_ast_patterns(T) || T <- AST7],

        AST9 = pt_supp:replace_remote_call(AST8, pt_lib, is_atom, fun replace_function/2, nothing),
        AST10 = pt_supp:replace_remote_call(AST9, pt_lib, is_list, fun replace_function/2, nothing),
        AST11 = pt_supp:replace_remote_call(AST10, pt_lib, is_variable, fun replace_function/2, nothing),
        AST12 = pt_supp:replace_remote_call(AST11, pt_lib, is_string, fun replace_function/2, nothing),
        AST13 = pt_supp:replace_remote_call(AST12, pt_lib, is_tuple, fun replace_function/2, nothing),
        AST14 = pt_supp:replace_remote_call(AST13, pt_lib, is_function, fun replace_function/2, nothing),
        AST15 = pt_supp:replace_remote_call(AST14, pt_lib, is_fun, fun replace_function/2, nothing),
        ?PT_DBG("NewAST: ~p", [AST15]),
        AST15
    catch
        throw:{parse_error, _} = Error ->
            pt_supp:generate_errors(AST, [Error], []) ++ AST;
        throw:{error, _} = Error ->
            pt_supp:generate_errors(AST, [Error], []) ++ AST;
        throw:{internal_error, _} = Error ->
            pt_supp:generate_errors(AST, [Error], []) ++ AST
    end.

parse_str_debug(Str) ->
    ToAST = fun (Str1) ->
                Line = 0,
                case erl_scan:string(Str1, Line) of
                    {ok, Tokens, _} ->
                        case erl_parse:parse_form(Tokens) of
                            {ok, Abs} -> {ok, [Abs]};
                            {error, ParseFormError} ->
                                case erl_parse:parse_exprs(Tokens) of
                                    {ok, List} -> {ok, List};
                                    {error, ParseExprsError} ->
                                        throw(?mk_error({ParseExprsError, ParseFormError}))
                                end
                        end;
                    {error, ScanErrorInfo, _ScanEndLocation} ->
                        throw(?mk_error(ScanErrorInfo))
                end
            end,
    {ok, A} = ToAST(Str),
    AST = parse_transform([ {attribute, 0, module, mod} | A], []),
    ResAST = case lists:keytake(module, 3, AST) of
                {value, _, R} -> R;
                false -> false
             end,
    {ok, ResStr} = pt_supp:ast2str(ResAST),
    io:format("\""++ResStr++"\"", []).

replace_ast_patterns(AST) ->
    AST1= pt_supp:replace(AST,
        fun(T) ->
            case T of
                {function, Line, Name, Arity, ClauseList} when Arity > 0 ->
                    {NewClauses, Vars} = process_clause_with_pattern(ClauseList),
                    case Vars of
                        [] -> {function, Line, Name, Arity, NewClauses};
                        _ ->
                            throw(?mk_parse_error(Line, {unbound_var, lists:flatten(element(2, lists:unzip(Vars)))}))
                    end;
                {'case', Line, Var, ClauseList} ->
                    {NewClauses, Vars} = process_clause_with_pattern(ClauseList),
                    case Vars of
                        [] ->
                            {'case', Line, Var, NewClauses};
                        _ ->
                            Header = {match, Line, {var, Line, pt_supp:mk_atom("__pt_tmp_case_var_", Line)}, Var},
                            CodeBeforeCase = generate_code_for_each_pattern_in_case(_ListOfClauses_ = Vars, Line),
                            NewNewClauses = remove_tmp_vars_from_main_case_clauses(NewClauses, Vars),
                            % begin
                            %   P' = P, % Header
                            %
                            %   A' = abstract(A)  % CodeBeforeCase
                            %   A_result = case pt_supp:insert_lines(P',0) of
                            %     NewPattern -> true;
                            %     _ -> false
                            %   end
                            %
                            %   case P' of % new "main" case and NewNewClauses
                            %     {... _ ...} when A_result =:= true -> ...
                            %   end
                            % end
                            {block, Line,
                                [Header] ++
                                CodeBeforeCase ++
                                [{'case', Line, {var, Line, pt_supp:mk_atom("__pt_tmp_case_var_", Line)}, NewNewClauses}]}
                    end;
                {'fun', Line, {clauses, ClauseList}} ->
                    {NewClauses, Vars} = process_clause_with_pattern(ClauseList),
                    case Vars of
                        [] -> {'fun', Line, {clauses, NewClauses}};
                        _ ->
                            throw(?mk_parse_error(Line, {unbound_var, lists:flatten(element(2, lists:unzip(Vars)))}))
                    end;
                _ -> T
            end
        end),
    AST2 = pt_supp:replace(AST1,
        fun(T) ->
            case T of
                {match, MLine, LValue, RValue} ->
                    {NewLValue, Vars} = process_ast_pattern(LValue),
                    case Vars of
                        [] -> {match, MLine, NewLValue, RValue};
                        _ ->
                            MainMatch = {match, MLine, {var, MLine, get_var_name_atom("__pt_tmp_match_result_var", Vars)} ,{match, MLine, NewLValue, RValue}},
                            PostMatch = generate_code_to_check_vars_in_match(Vars, MLine),
                            Result = {var, MLine, get_var_name_atom("__pt_tmp_match_result_var", Vars)},
                            % begin
                            %   P' = V, % MainMatch
                            %
                            %   begin % PostMatch
                            %     A'1 = pt_supp:insert_lines(A',0),
                            %     A'2 = pt_supp:abstract(A, 0),
                            %     A'1 = A'2
                            %   end,
                            %
                            %   P' % Result
                            % end
                            {block, MLine, [MainMatch] ++  PostMatch ++ [Result]}
                    end;
                _ -> T
            end
        end),
    AST3 = pt_supp:replace(AST2,
            fun ({call, Line, {atom, _, ast_pattern}, [_, _]} = IICall) ->
                    {RRCall, SVars} = process_ast_pattern(IICall),
                    case SVars of
                        [] -> RRCall;
                        _ ->
                            throw(?mk_parse_error(Line, {unbound_var, lists:flatten(element(2, lists:unzip(SVars)))}))
                        end;
                (XU) -> XU
            end
          ),
    AST3.

generate_code_for_each_pattern_in_case(ListOfClauses, Line) ->
    {_, List} = lists:mapfoldl(
    fun({Pattern, VarsInPattern}, Result) ->

        % generate lines like A' = abstract(A)
        VarMatchAst = lists:map(
            fun (V1) ->
                StrV = atom_to_list(V1),
                Str = "__pt_tmp_var_" ++ StrV ++ " = pt_supp:abstract(" ++ StrV ++ ", 0).",
                case pt_supp:str2ast(Str, Line) of
                    {ok, [Ast]} -> Ast;
                    {error, Reason} ->
                        %?PT_ERROR(pt_supp:format_str2ast_error(Str, Reason), [])
                        throw(?mk_int_error({str2ast, Reason, Str}))
                end
            end,
            VarsInPattern
        ),

        % replace all variables (except  A') with _ to prevent using it before "main" case
        NewPattern = pt_supp:replace(Pattern,
            fun
                ({var, AAALine, VarName}) ->
                    case string:str(atom_to_list(VarName), "__pt_tmp_var_") of
                        1 -> {var, AAALine, VarName};
                        _ -> {var, AAALine, '_'}
                    end;
                (Any) -> Any
            end
        ),

        % generate case for each pattern in "main" case, to check @A variables
        % A_result = case pt_supp:insert_lines(P') of
        %   NewPattern -> true;
        %   _ -> false
        % end
        Case = {match, Line, {var, Line, get_var_name_atom("__pt_tmp_result", VarsInPattern)},
        {'case', Line, {call, Line, {remote, Line, {atom, Line, pt_supp}, {atom, Line, insert_lines}},[ {var, Line, pt_supp:mk_atom("__pt_tmp_case_var_", Line)}, {integer, Line, 0}]}, [
        {clause, Line, NewPattern, [], [{atom, Line, true}]},
        {clause, Line, [{var, Line, '_'}], [], [{atom, Line, false}]}
        ]}},
        {{Pattern, VarsInPattern},  VarMatchAst ++ [ Case | Result]}
    end, [], ListOfClauses),
    List.

remove_tmp_vars_from_main_case_clauses(Clauses, PatternsWithVars) ->
    % {..., A', ...} -> {..., _, ...}
    lists:foldl(
        fun({_Pattern_, Vars}, AccNewClaues1) ->
            lists:foldl(
                fun(Var, AccNewClaues2) ->
                    VarAtom = pt_supp:mk_atom("__pt_tmp_var_", Var),
                    pt_supp:replace(AccNewClaues2,
                    fun(SubTree) ->
                        case SubTree of
                            {var, Line, VarAtom} ->{var, Line, '_'};
                            Any -> Any
                        end
                    end)
                end,
                AccNewClaues1, Vars)
        end,
        Clauses,
        PatternsWithVars).

generate_code_to_check_vars_in_match(Vars, Line) ->
    %   begin % PostMatch
    %     A'1 = pt_supp:insert_lines(A',0),
    %     A'2 = pt_supp:abstract(A, 0),
    %     A'1 = A'2
    %   end,
    lists:map(
        fun (Var) ->
            Match1 = {match, Line,
                {var, Line, pt_supp:mk_atom("__pt_tmp_var_match1_", Var)},
                {call, Line, {remote, Line, {atom, Line, pt_supp}, {atom, Line, insert_lines}}, [{var, Line, pt_supp:mk_atom("__pt_tmp_var_", Var)}, {integer, Line, 0}]}},
            Match2 = {match, Line,
                {var, Line, pt_supp:mk_atom("__pt_tmp_var_match2_", Var)},
                {call, Line, {remote, Line, {atom, Line, pt_supp}, {atom, Line, abstract}}, [{var, Line, Var}, {integer, Line, 0}]}},
            {block, Line, [Match1, Match2, {match, Line, {var, Line, pt_supp:mk_atom("__pt_tmp_var_match1_", Var)}, {var, Line, pt_supp:mk_atom("__pt_tmp_var_match2_", Var) }}]}
        end,
        Vars).

get_var_name_atom(Prefix, Vars) ->
    pt_supp:string2atom(get_var_name_str(Prefix, Vars)).
get_var_name_str(Prefix, Vars) ->
    lists:foldl(
        fun(Var, Acc) ->
            Acc ++ "_" ++ atom_to_list(Var)
        end, Prefix,
        Vars).

process_clause_with_pattern(Clauses) ->
    lists:mapfoldl(
        fun(Clause, VarList) ->
            case Clause of
                {clause, Line, Params, Guards, Expr} ->
                    {NewParams, Vars} = lists:mapfoldl(
                        fun (Param, CurVars) ->
                            {A, V} = process_ast_pattern(Param),
                            {A, V ++ CurVars}
                        end,
                        [],
                        Params
                    ),
                    case Vars of
                        [] -> {{clause, Line, NewParams, Guards, Expr}, VarList};
                        _ ->
                            {_, GuardVarNamePostfix} = lists:mapfoldl(
                                fun(V, AccVarsStr) ->
                                    {V, AccVarsStr ++ "_" ++ atom_to_list(V)}
                                end,
                                "",
                                Vars
                            ),
                            GuardVarName = pt_supp:mk_atom("__pt_tmp_result", GuardVarNamePostfix),
                            {{clause, Line, NewParams, [{op, Line, '=:=', {var, Line, GuardVarName}, {atom, Line, true}} | Guards], Expr}, [{NewParams, Vars} | VarList]}
                    end;
                _ -> {Clause, VarList}
            end
        end,
        [],
        Clauses
    ).


process_ast_pattern(AST) ->
    pt_supp:replace_fold(
        AST,
        fun (Tree, Acc) ->
            {NewTree, Vars} = process_ast_pattern2(Tree),
            case pt_supp:is_term_or_var(NewTree) of
                true ->
                    {NewTree, Acc ++ Vars};
                false ->
                    {Tree, Acc}
            end
        end,
        []).

process_ast_pattern2({match, Line, Call = {call, _, {atom, _, ast_pattern}, _}, RValue}) ->
    {NewCall, VarList1} = erl_syntax:revert(replace_ast_pattern_function(Call, nothing)),
    {NewRValue, VarList2} = process_ast_pattern2(RValue),
    {{match, Line, NewCall, NewRValue}, VarList1 ++ VarList2};
process_ast_pattern2({match, Line, LValue, RValue}) ->
    {NewRValue, VarList} = process_ast_pattern2(RValue),
    {{match, Line, LValue, NewRValue}, VarList};
process_ast_pattern2(Call = {call, _, {atom, _, ast_pattern}, _}) ->
    erl_syntax:revert(replace_ast_pattern_function(Call, nothing));
process_ast_pattern2(T) -> {T, []}.

% ast_pattern("log(Str)", Line) -> {call, Line, {atom, _, log}, [Str]}
replace_ast_pattern_function(_Call = {call, Line, {atom, _, ast_pattern}, [{string, _, Str} | Params ]}, _) ->
    ATree = case pt_supp:str2ast(Str, Line) of
            {ok, [T]} -> T;
            {ok, T} -> T;
            {error, Reason} ->
                throw(?mk_parse_error(Line, {str2ast, Reason, Str}))
          end,
    ASTAST = pt_supp:abstract(ATree, Line),
    ASTAST0 = process_additional_syntax(ASTAST, ast_pattern),
    {ASTAST1, Vars} = process_pattern_variables(ASTAST0),
    ASTAST2 = process_pattern_line_var(ASTAST1, case Params of [] -> {var, 0, '_'}; [L] -> L end),
    {ASTAST2, Vars}.

replace_cons_var_in_list(List, L) ->
    try
        pt_supp:list_foldr(
            fun (E, Line, Acc) ->
                case replace_cons_var(E) of
                    {ok, NewE} when Acc == {nil, L} -> NewE;
                    {ok, NewE} -> {op, Line, '++', NewE, Acc};
                    nochange -> {cons, Line, E, Acc}
                end
            end, {nil, L}, List)
    catch
        throw:{error, {_, _, {bad_param, _}, _}} -> List
    end.

replace_cons_var(
{tuple, _,
 [{atom, _, tuple}, _,
   {cons, _,
      {tuple, _,
          [{atom, _, atom}, _, {atom, _, pt_consvar}]},
        {cons, _,
            {tuple,_,[{atom,_,atom},_,{atom,_,_}]} = Var,
            {nil, _}}}]}
                ) -> {ok, Var};

replace_cons_var(
{tuple, _,
        [{atom,_,bin_element},
         _,
         {tuple,_,
                [{atom,_,tuple},
                 _,
                 {cons,_,
                       {tuple,_,
                              [{atom, _, atom},_,{atom, _, pt_consvar}]},
                       {cons, _, Var, {nil, _}}}]},
         {atom, _,default},
         {atom, _,default}
         ]}
                ) -> {ok, Var};

replace_cons_var(
{tuple, _,
 [{atom, _, record_field}, _,
   {tuple, _,
      [{atom, _, atom}, _,
          {atom, _, '__PT_RECORDFIELD_DOT_VAR_REPLACE'}]},
            Var]}
                ) -> {ok, Var};

replace_cons_var(_V) -> nochange.


process_additional_syntax(AST, Type) ->
    AST0 = pt_supp:replace(AST,
        fun
            ({tuple, FLine1, [
                {atom, FLine2, function},
                FLine3,
                FFunName,
                _,
                {cons, _,
                    {tuple, _, [
                        {atom, _, clause},
                        _,
                        {cons, _,
                            {tuple, _, [
                                {atom, _, atom},
                                _,
                                {atom, _, '__PT_CLAUSE_DOT_VAR_REPLACE'}
                            ]},
                            {nil, _}
                        },
                        {nil, _},
                        {cons, _, Var1, {nil, _}}
                    ]},
                    {nil, _}
                    }
            ]}) ->
                GetArity =
                    fun (V) ->
                        {call,FLine2, {atom, FLine2,length}, [
                            {call, FLine2, {atom, FLine2,element}, [
                                {integer,FLine2,3}, {call, FLine2, {atom,FLine2,hd}, [V]}
                            ]}
                        ]}
                    end,
                GArity =
                    case Type of
                        ast ->
                            GetArity(Var1);
                        ast_pattern -> {var, FLine2, '_'}
                    end,
                {tuple, FLine1, [
                    {atom, FLine2, function}, FLine3, FFunName,
                    GArity,
                    Var1
                ]};

            ({tuple, Line1, [
                {atom, Line2, function}, Line3, {atom, Line4, FunName}, FunArity, Clauses]
            }) ->
                case Type of
                    ast_pattern ->
                        {tuple, Line1, [
                            {atom, Line2, function},
                            Line3,
                            {atom, Line4, FunName},
                            {var, Line4, '_'},
                            Clauses
                        ]};
                    ast ->
                        Res = erl_syntax_lib:fold(
                            fun
                                ({tuple, _, [
                                    {atom, _, clause},
                                    _,
                                    FunParams,
                                    _FunGuards,
                                    _FunExprs]
                                }, Acc) ->
                                    RR = pt_supp:list_fold(
                                        fun
                                            ({tuple, _, [
                                                {atom, _, tuple},
                                                _,
                                                {cons, _,
                                                    {tuple, _, [
                                                        {atom, _, atom}, _, {atom, _, pt_consvar}
                                                    ]},
                                                    {cons, _,
                                                        {tuple, _, [
                                                            {atom, _, atom}, _, {atom, _, VarName}
                                                        ]},
                                                        {nil, _}
                                                    }
                                                }
                                            ]}, _, {NN, VV}) ->
                                                {NN, [VarName|VV]};
                                            (_, _, {NN, VV}) ->
                                                {NN + 1, VV}
                                        end, {0, []}, FunParams),
                                    case RR of
                                        {_, []} -> Acc;
                                        _ -> RR
                                    end;
                                (_, Acc) -> Acc
                            end,
                            notfound,
                            Clauses
                        ),
                        case Res of
                            {NormalPNum, [FirstConsParam | ConsParams]} ->
                                MakeLenCall =
                                    fun
                                        (VVV) ->
                                            {call, Line4, {atom, Line4, 'length'}, [
                                                {tuple, Line4, [
                                                    {atom, Line4, atom},
                                                    {integer, Line4, Line4},
                                                    {atom, Line4, VVV}
                                                ]}
                                            ]}
                                    end,
                                ConsVarLens =
                                    lists:foldl(
                                        fun (NextConsParam, Cur) ->
                                            {op, Line4, '++', MakeLenCall(NextConsParam), Cur}
                                        end, MakeLenCall(FirstConsParam), ConsParams
                                    ),
                                {tuple, Line1, [
                                    {atom, Line2, function},
                                    Line3,
                                    {atom, Line4, FunName},
                                    {op, Line4, '+', ConsVarLens, {integer, Line4, NormalPNum}},
                                    Clauses
                                ]};
                            {ok, VarName} ->
                                {tuple, Line1, [
                                    {atom, Line2, function}, Line3, {atom, Line4, FunName},
                                    {call, Line4, {atom, Line4, 'length'}, [
                                        {tuple, Line4, [
                                            {atom, Line4, atom},
                                            {integer, Line4, Line4},
                                            {atom, Line4, VarName}
                                        ]}
                                    ]},
                                    Clauses
                                ]};
                            notfound ->
                                {tuple, Line1, [
                                    {atom, Line2, function},
                                    Line3,
                                    {atom, Line4, FunName},
                                    FunArity,
                                    Clauses
                                ]}
                            end
                    end;
                (X) -> X
        end
    ),
    AST1 = pt_supp:replace(AST0,
        fun
            ({cons, L, _, _} = List) ->
                replace_cons_var_in_list(List, L);
            (V) ->
                V
        end
    ),
    pt_supp:replace(AST1,
        fun
            ({tuple, FLine1, [
                {atom, FLine2, function},
                FLine3,
                FFunName,
                _,
                {cons, _,
                    {tuple, _, [
                        {atom, _, clause},
                        _,
                        {cons, _,
                            {tuple, _, [{atom, _, atom}, _, {atom, _, '__PT_FUNCTION_DOT_VAR_REPLACE'}]},
                            {nil, _}
                        },
                        {nil, _},
                        {cons, _, Var1, {nil, _}}
                    ]},
                    {cons, _,
                        {tuple, _, [
                            {atom, _, clause},
                            _,
                            {cons, _,
                                {tuple, _, [
                                    {atom, _, atom}, _,
                                    {atom, _, '__PT_FUNCTION_DOT_VAR_REPLACE_ARITY'}
                                ]},
                                {nil, _}
                            },
                            {nil, _},
                            {cons, _, Var2, {nil, _}}
                        ]},
                        {nil, _}
                    }}
                ]}) ->
                    NewVar2 =
                        case Var2 of
                            {tuple, _, [{atom, _, integer}, _, Val2]} ->
                                Val2;
                            _ ->
                                Var2
                        end,
                    {tuple, FLine1, [
                        {atom, FLine2, function},
                        FLine3,
                        FFunName,
                        NewVar2,
                        Var1
                    ]};
            ({cons, _,
                {tuple, _, [
                    {atom, _, clause},
                    _,
                    {cons, _,
                        {tuple, _, [
                            {atom, _, tuple},
                            _,
                            {cons, _,
                                {tuple, _, [{atom, _, atom}, _, {atom, _, 'throw'}]},
                                {cons, _,
                                    {tuple, _, [
                                        {atom, _, atom},
                                        _,
                                        {atom, _, '__PT_CLAUSE_DOT_VAR_REPLACE'}
                                    ]},
                                    {cons, _,
                                        {tuple, _, [{atom, _, var}, _, {atom, _, '_'}]},
                                        {nil, _}
                                    }
                                }
                            }
                        ]},
                        {nil, _}
                    },
                    {nil, _},
                    {cons, _, Var, {nil, _}}
                ]},
                {nil, _}
            }) ->
                Var;

            ({cons, _,
                {tuple, _, [
                    {atom, _, clause},
                    _,
                    {cons, _,
                        {tuple, _, [{atom, _, atom}, _, {atom, _, '__PT_CLAUSE_DOT_VAR_REPLACE'}]},
                        {nil, _}
                    },
                    {nil, _},
                    {cons, _, Var, {nil, _}}
                ]},
                {nil, _}
            }) ->
                Var;

            ({cons, _,
                {tuple, _, [
                    {atom, _, clause},
                    _,
                    {nil, _},
                    {cons, _,
                        {cons, _,
                            {tuple, _, [{atom, _, atom}, _, {atom, _, '__PT_CLAUSE_DOT_VAR_REPLACE'}]},
                            {nil, _}
                        },
                        {nil, _}
                    },
                    {cons, _, Var, {nil, _}}
                ]},
                {nil, _}
            }) ->
                Var;

            ({tuple, BLine1, [
                {atom, BLine2, block},
                BLine3,
                {cons, _,
                    {tuple, _, [
                        {atom, _, tuple},
                        _,
                        {cons, _,
                            {tuple, _, [{atom, _, atom}, _, {atom, _, pt_consvar}]},
                            {cons, _,
                                {tuple, BLine11, [
                                    {atom, BLine12, atom}, BLine13, {atom, BLine14, VarName}
                                ]},
                                {nil, _}
                            }
                        }
                    ]},
                    {nil, _}
                }
            ]}) ->
                {tuple, BLine1, [
                    {atom, BLine2, block},
                    BLine3,
                    {tuple, BLine11, [{atom, BLine12, atom}, BLine13, {atom, BLine14, VarName}]}
                ]};

            ({tuple, PLine1, [
                {atom, PLine2, call},
                PLine3,
                PFunName,
                {cons, _,
                    {tuple, _, [
                        {atom, _,tuple},
                        _,
                        {cons, _,
                            {tuple, _, [{atom, _,atom}, _,{atom, _, pt_consvar}]},
                            {cons, _,
                                {tuple, PLine11, [
                                    {atom, PLine12, atom}, PLine13, {atom, PLine14, VarName}
                                ]},
                                {nil,_}
                            }
                        }
                    ]},
                    {nil,_}
                }
            ]}) ->
                {tuple, PLine1, [
                    {atom, PLine2, call},
                    PLine3,
                    PFunName,
                    {tuple, PLine11, [{atom, PLine12, atom}, PLine13, {atom, PLine14, VarName}]}
                ]};

            ({tuple, Line1, [{atom, Line2, clause}, Line3, ParamsAST, GuardsAST, Exprs]}) ->
                Replace =
                    fun
                        ({cons, _,
                            {tuple, _, [
                                {atom, _, tuple},
                                _,
                                {cons, _,
                                    {tuple, _, [{atom, _, atom}, _, {atom, _, pt_consvar}]},
                                    {cons, _,
                                        {tuple, SLine11, [
                                            {atom, SLine12, atom}, SLine13, {atom, SLine14, VarName}
                                        ]},
                                        {nil, _}
                                    }
                                }
                            ]},
                            {nil, _}
                        }) ->
                            {tuple, SLine11, [
                                {atom, SLine12, atom}, SLine13, {atom, SLine14, VarName}
                            ]};
                        (X) ->
                            X
                end,
                {tuple, Line1, [
                    {atom, Line2, clause}, Line3, Replace(ParamsAST), Replace(GuardsAST), Replace(Exprs)
                ]};
            (X) ->
                X
        end
    ).

% pt_lib:replace -> pt_supp:replace
replace_function(_Call = {call, Line1, {remote, Line2, {atom, Line3, pt_lib}, {atom, Line4, replace}}, [Tree, Pattern, Value]}, P1) ->
    replace_function({call, Line1, {remote, Line2, {atom, Line3, pt_lib}, {atom, Line4, replace}}, [Tree, {cons, Line4, {tuple, Line4, [Pattern, Value]}, {nil, Line4}}]}, P1);
replace_function(_Call = {call, Line1, {remote, Line2, {atom, Line3, pt_lib}, {atom, Line4, replace}}, [Tree, Pattern, Guards, Value]}, P1) ->
    replace_function({call, Line1, {remote, Line2, {atom, Line3, pt_lib}, {atom, Line4, replace}}, [Tree, {cons, Line4, {tuple, Line4, [Pattern, Guards, Value]}, {nil, Line4}}]}, P1);
replace_function(Call = {call, _Line, {remote, _, {atom, _, pt_lib}, {atom, _, replace}}, [_Tree, Fun]}, _) when element(1, Fun) =:= 'fun' ->
    Call;
replace_function(_Call = {call, Line, {remote, _, {atom, _, pt_lib}, {atom, _, replace}}, [Tree, List]}, _) ->
    ClauseGenerator = fun
                        ({cons, _, {tuple, _, [Pattern, Value]}, Tail}, Res, Y) ->
                            Y(Tail, Res ++ [{clause, Line, [Pattern], [], [Value]}], Y);
                        ({cons, _, {tuple, _, [Pattern, Guards, Value]}, Tail}, Res, Y) ->
                            Y(Tail, Res ++ [{clause, Line, [Pattern], [Guards], [Value]}], Y);
                        ({nil, _}, Res, _) -> Res ++ [{clause, Line, [{var, Line, 'PT_TMP_X'}], [], [{var, Line, 'PT_TMP_X'}]}];
                        (L, _Res, _) ->
                            throw(?mk_parse_error(Line, {bad_param, L}))
                      end,
    ReplaceFun =
    {'fun', Line, {clauses, [{clause, Line,
        [{var, Line, '__PT_PT_LIB_REPLACE_FUN_VAR'}],
        [],
        [{'case', Line, {var, Line, '__PT_PT_LIB_REPLACE_FUN_VAR'}, ClauseGenerator(List, [], ClauseGenerator)}]
    }]}},
    ReplacedWith = {call, Line, {remote, Line, {atom, Line, pt_supp}, {atom, Line, replace}}, [Tree, ReplaceFun]},
    ReplacedWith;

replace_function(_Call = {call, Line1, {remote, Line2, {atom, Line3, pt_lib}, {atom, Line4, replace_fold}}, [Tree, Pattern, Value, InitAcc]}, P1) ->
    replace_function({call, Line1, {remote, Line2, {atom, Line3, pt_lib}, {atom, Line4, replace_fold}}, [Tree, {cons, Line4, {tuple, Line4, [Pattern, Value]}, {nil, Line4}}, InitAcc]}, P1);
replace_function(_Call = {call, Line1, {remote, Line2, {atom, Line3, pt_lib}, {atom, Line4, replace_fold}}, [Tree, Pattern, Guards, Value, InitAcc]}, P1) ->
    replace_function({call, Line1, {remote, Line2, {atom, Line3, pt_lib}, {atom, Line4, replace_fold}}, [Tree, {cons, Line4, {tuple, Line4, [Pattern, Guards, Value, InitAcc]}, {nil, Line4}}, InitAcc]}, P1);
replace_function(Call = {call, _Line, {remote, _, {atom, _, pt_lib}, {atom, _, replace_fold}}, [_Tree, Fun, _]}, _) when element(1, Fun) =:= 'fun' ->
    Call;
replace_function(_Call = {call, Line, {remote, _, {atom, _, pt_lib}, {atom, _, replace_fold}}, [Tree, List, InitAcc]}, _) ->
    ClauseGenerator = fun
                        ({cons, _, {tuple, _, [Pattern, Value]}, Tail}, Res, Y) ->
                            Y(Tail, Res ++ [{clause, Line, [Pattern], [], [Value]}], Y);
                        ({cons, _, {tuple, _, [Pattern, Guards, Value]}, Tail}, Res, Y) ->
                            Y(Tail, Res ++ [{clause, Line, [Pattern], [Guards], [Value]}], Y);
                        ({nil, _}, Res, _) -> Res ++ [{clause, Line, [{var, Line, 'PT_TMP_X'}], [], [{var, Line, 'PT_TMP_X'}]}];
                        (L, _Res, _) ->
                            throw(?mk_parse_error(Line, {bad_param, L}))
                      end,
    ReplaceFun =
    {'fun', Line, {clauses, [{clause, Line,
        [{var, Line, '__PT_PT_LIB_REPLACE_FOLD_FUN_VAR)'}, {var, Line, '__PT_PT_LIB_REPLACE_FOLD_ACC_VAR'}],
        [],
        [{'case', Line, {tuple, Line, [{var, Line, '__PT_PT_LIB_REPLACE_FOLD_FUN_VAR)'}, {var, Line, '__PT_PT_LIB_REPLACE_FOLD_ACC_VAR'}]}, ClauseGenerator(List, [], ClauseGenerator)}]
    }]}},
    ReplacedWith = {call, Line, {remote, Line, {atom, Line, pt_supp}, {atom, Line, replace_fold}}, [Tree, ReplaceFun, InitAcc]},
    ReplacedWith;

replace_function(Call = {call, _Line, {remote, _, {atom, _, pt_lib}, {atom, _, replace_first}}, [_Tree, _Fun]}, _) ->
    Call;

% pt_lib:replace_first -> pt_supp:replace_first
replace_function(_Call = {call, Line, {remote, _, {atom, _, pt_lib}, {atom, _, replace_first}}, [Tree, Pattern, Value]}, _) ->
    ReplaceFun = construct_replace_fun(Pattern, Value, Line),
    ReplacedWith = {call, Line, {remote, Line, {atom, Line, pt_supp}, {atom, Line, replace_first}}, [Tree, ReplaceFun]},
    ReplacedWith;

replace_function(_Call = {call, Line, {remote, L1, {atom, L2, pt_lib}, {atom, L3, match}}, [Tree, Pattern]}, P1) ->
    replace_function2({call, Line, {remote, L1, {atom, L2, pt_lib}, {atom, L3, match}}, [Tree, Pattern, []]}, P1);
replace_function(_Call = {call, Line, {remote, L1, {atom, L2, pt_lib}, {atom, L3, match}}, [Tree, Pattern, Guard]}, P1) ->
    replace_function2({call, Line, {remote, L1, {atom, L2, pt_lib}, {atom, L3, match}}, [Tree, Pattern, [Guard]]}, P1);

replace_function(_Call = {call, Line, {remote, L1, {atom, L2, pt_lib}, {atom, L3, first_clause}}, [Tree, Pattern]}, P1) ->
    ReplaceFun =
    {'fun', Line, {clauses, [{clause, Line,
        [{var, Line, '__PT_PT_LIB_MATCH_FUN_VAR)'}],
        [],
        [{'case', Line, {var, Line, '__PT_PT_LIB_MATCH_FUN_VAR)'},
            [
                {clause, Line, [Pattern], [], [{atom, Line, 'true'}]},
                {clause, Line, [{var, Line, '_'}], [], [{atom, Line, 'false'}]}
            ]}]
    }]}},
    ReplaceWith = {call, Line, {remote, Line, {atom, Line, pt_supp}, {atom, Line, first_clause}}, [Tree, ReplaceFun]},
    ReplaceWith;

% ast("log()", Line) -> {call, Line, {atom, Line, log}, []}
replace_function(_Call = {call, Line, {atom, _, ast}, [{string, _, Str}, LineVarAst]}, _) ->
    AST = case pt_supp:str2ast(Str, Line) of
            {ok, [T]} -> T;
            {ok, T} -> T;
            {error, Reason} ->
                throw(?mk_parse_error(Line, {str2ast, Reason, Str}))
          end,

    Export = case AST of {attribute, _, _, _} -> attribute; _ -> false end,
    ASTAST = pt_supp:abstract(AST, Line),
    ASTAST1 = process_additional_syntax(ASTAST, ast),
    ASTAST2 = ASTAST1,
    ASTAST3 = process_variables(ASTAST2, LineVarAst),
    ASTAST4 = process_line_var(ASTAST3, LineVarAst, Export),
    ASTAST4;
replace_function(_Call = {call, Line, {atom, _, ast}, [_]}, _) ->
    throw(?mk_parse_error(Line, {undef, 'ast/1'}));
replace_function({call, Line, {remote, _, {atom, _, pt_lib}, {atom, _, is_atom}}, [Param]}, _) ->
    {op, Line, '=:=', {call, Line, {atom, Line, element}, [{integer, Line, 1}, Param]}, {atom, Line, atom}};

replace_function({call, Line, {remote, _, {atom, _, pt_lib}, {atom, _, is_list}}, [Param]}, _) ->
    {op, Line, 'or',
        {op, Line, '=:=',
            {call, Line, {atom, Line, element}, [{integer, Line, 1}, Param]},
            {atom, Line, cons}},
        {op, Line, '=:=',
            {call, Line, {atom, Line, element}, [{integer, Line, 1}, Param]},
            {atom, Line, nil}}};

replace_function({call, Line, {remote, _, {atom, _, pt_lib}, {atom, _, is_variable}}, [Param]}, _) ->
    {op, Line, '=:=', {call, Line, {atom, Line, element}, [{integer, Line, 1}, Param]}, {atom, Line, var}};

replace_function({call, Line, {remote, _, {atom, _, pt_lib}, {atom, _, is_string}}, [Param]}, _) ->
    {op, Line, '=:=', {call, Line, {atom, Line, element}, [{integer, Line, 1}, Param]}, {atom, Line, string}};

replace_function({call, Line, {remote, _, {atom, _, pt_lib}, {atom, _, is_tuple}}, [Param]}, _) ->
    {op, Line, '=:=', {call, Line, {atom, Line, element}, [{integer, Line, 1}, Param]}, {atom, Line, tuple}};

replace_function({call, Line, {remote, _, {atom, _, pt_lib}, {atom, _, is_function}}, [Param]}, _) ->
    {op, Line, '=:=', {call, Line, {atom, Line, element}, [{integer, Line, 1}, Param]}, {atom, Line, 'function'}};

replace_function({call, Line, {remote, _, {atom, _, pt_lib}, {atom, _, is_fun}}, [Param]}, _) ->
    {op, Line, '=:=', {call, Line, {atom, Line, element}, [{integer, Line, 1}, Param]}, {atom, Line, 'fun'}};

replace_function(Call, _) ->
    throw(?mk_int_error({unhandled_replace_param, Call})).

replace_function2(_Call = {call, Line, {remote, _, {atom, _, pt_lib}, {atom, _, match}}, [Tree, Pattern, Guard]}, _) ->
    ReplaceFun =
    {'fun', Line, {clauses, [{clause, Line,
        [{var, Line, '__PT_PT_LIB_MATCH_FUN_VAR)'}],
        [],
        [{'case', Line, {var, Line, '__PT_PT_LIB_MATCH_FUN_VAR)'},
            [
                {clause, Line, [Pattern], Guard, [{atom, Line, 'true'}]},
                {clause, Line, [{var, Line, '_'}], [], [{atom, Line, 'false'}]}
            ]}]
    }]}},
    ReplaceWith = {call, Line, {remote, Line, {atom, Line, pt_supp}, {atom, Line, match}}, [Tree, ReplaceFun]},
    ReplaceWith.

% processing things like "{String, @Module}"
process_variables(AST, VarLineAst) ->
   erl_syntax_lib:map(
        fun (T) ->
            Tr = erl_syntax:revert(T),
            case Tr of
                {tuple, L1, [{atom, L2, 'fun'}, L3,
                  {tuple, L4,
                   [{atom, L5, function}, FName,
                    Arity]}]} ->

                    ProcessSpec = fun(NameStr) ->
                                    case NameStr of
                                        [ $\\, $@ | FNameStrTail] -> {atom, L5, pt_supp:string2atom([$@ | FNameStrTail])};
                                        [ $\\, $$ | FNameStrTail] -> {atom, L5, pt_supp:string2atom([$@ | FNameStrTail])};
                                        [ $@ | VarStrTail] -> {var, L5, pt_supp:string2atom(VarStrTail)};
                                        [ $$ | VarStrTail] -> {var, L5, pt_supp:string2atom(VarStrTail)};
                                        _ -> {atom, L5, pt_supp:string2atom(NameStr)}
                                    end
                                  end,

                    {NewFName, NewArity} = case FName of
                                {atom, _, FNameAtom} ->
                                    case atom_to_list(FNameAtom) of
                                        "__PT_FUN_NAME_AND_ARITY_" ++ FNAATail ->
                                            Separator = "__PT_SEPARATOR__",
                                            case string:str(FNAATail, Separator) of
                                                0 -> throw(?mk_int_error({bad_param, FName}));
                                                1 -> throw(?mk_int_error({bad_param, FName}));
                                                N ->
                                                    {ProcessSpec(string:substr(FNAATail, 1, N-1)), ProcessSpec(string:substr(FNAATail, N + length(Separator), length(FNAATail)))}
                                            end;
                                        FNameStr ->
                                            {ProcessSpec(FNameStr), Arity}
                                    end;
                                _ -> FName
                               end,

                    {tuple, L1, [{atom, L2, 'fun'}, L3,
                      {tuple, L4,
                       [{atom, L5, function}, NewFName,
                        NewArity]}]};

                {tuple, L1, [{atom, L2, 'fun'}, L3,
                  {tuple, L4,
                   [{atom, L5, function}, FModule, FName,
                    Arity]}]} ->

                    ProcessSpec = fun(NameStr) ->
                                    case NameStr of
                                        [ $\\, $@ | FNameStrTail] -> {atom, L5, pt_supp:string2atom([$@ | FNameStrTail])};
                                        [ $\\, $$ | FNameStrTail] -> {atom, L5, pt_supp:string2atom([$@ | FNameStrTail])};
                                        [ $@ | VarStrTail] -> {var, L5, pt_supp:string2atom(VarStrTail)};
                                        [ $$ | VarStrTail] -> {var, L5, pt_supp:string2atom(VarStrTail)};
                                        _ -> {atom, L5, pt_supp:string2atom(NameStr)}
                                    end
                                  end,

                    {NewFName, NewArity} = case FName of
                                {atom, _, FNameAtom} ->
                                    case atom_to_list(FNameAtom) of
                                        "__PT_FUN_NAME_AND_ARITY_" ++ FNAATail ->
                                            Separator = "__PT_SEPARATOR__",
                                            case string:str(FNAATail, Separator) of
                                                0 -> throw(?mk_int_error({bad_param, FName}));
                                                1 -> throw(?mk_int_error({bad_param, FName}));
                                                N ->
                                                    {ProcessSpec(string:substr(FNAATail, 1, N-1)), ProcessSpec(string:substr(FNAATail, N + length(Separator), length(FNAATail)))}
                                            end;
                                        FNameStr ->
                                            {ProcessSpec(FNameStr), Arity}
                                    end;
                                _ -> FName
                               end,
                    NewFModule = case FModule of
                                    {atom, _, FModuleAtom} ->
                                        ProcessSpec(atom_to_list(FModuleAtom));
                                    _ -> FModule
                                 end,
                    {tuple, L1, [{atom, L2, 'fun'}, L3,
                      {tuple, L4,
                       [{atom, L5, function}, NewFModule, NewFName,
                        NewArity]}]};

                    {tuple, L, [{atom, L2, 'function'}, L3, {atom, L4, FunName}, Arity, Clauses]} ->
                    VarStr = atom_to_list(FunName),
                    case VarStr of
                        [ $\\, $@ | VarStrTail] ->
                            {tuple, L, [{atom, L2, 'function'}, L3, {atom, L4, pt_supp:string2atom([$@ | VarStrTail])}, Arity, Clauses]};
                        [ $\\, $$ | VarStrTail] ->
                            {tuple, L, [{atom, L2, 'function'}, L3, {atom, L4, pt_supp:string2atom([$$ | VarStrTail])}, Arity, Clauses]};
                        [ $@ | VarStrTail] ->
                            {tuple, L, [{atom, L2, 'function'}, L3, {var, L4, pt_supp:string2atom(VarStrTail)}, Arity, Clauses]};
                        [ $$ | VarStrTail] ->
                            {tuple, L, [{atom, L2, 'function'}, L3, {var, L4, pt_supp:string2atom(VarStrTail)}, Arity, Clauses]};
                        _ -> Tr
                    end;
                {tuple, L, [{atom, L2, atom}, {integer, L3, I1}, {atom, L4, Atom}]} ->
                    VarStr = atom_to_list(Atom),
                    case VarStr of
                        [ $\\, $@ | VarStrTail] ->
                            {tuple, L, [{atom, L2, atom}, {integer, L3, I1}, {atom, L4, pt_supp:string2atom([$@ | VarStrTail])}]};
                        [ $\\, $$ | VarStrTail] ->
                            {tuple, L, [{atom, L2, atom}, {integer, L3, I1}, {atom, L4, pt_supp:string2atom([$$ | VarStrTail])}]};
                        [ $@ | VarStrTail] ->
                            {call, L, {remote, L, {atom, L, pt_supp}, {atom, L, abstract} }, [{var, L, pt_supp:string2atom(VarStrTail)}, VarLineAst]};
                        [ $$ | VarStrTail] ->
                            {var, L, pt_supp:string2atom(VarStrTail)};
                        _ ->
                            Tr
                    end;
                {tuple, L, [{atom, L2, 'record'}, {integer, L3, I1}, {atom, L4, Atom}, DD]} ->
                    VarStr = atom_to_list(Atom),
                    case VarStr of
                        [ $\\, $@ | VarStrTail] ->
                            {tuple, L, [{atom, L2, 'record'}, {integer, L3, I1}, {atom, L4, pt_supp:string2atom([$@ | VarStrTail])}, DD]};
                        [ $\\, $$ | VarStrTail] ->
                            {tuple, L, [{atom, L2, 'record'}, {integer, L3, I1}, {atom, L4, pt_supp:string2atom([$$ | VarStrTail])}, DD]};
                        [ $@ | VarStrTail] ->
                            {tuple, L, [{atom, L2, 'record'}, {integer, L3, I1}, {var, L4, pt_supp:string2atom(VarStrTail)}, DD]};
                        [ $$ | VarStrTail] ->
                            {tuple, L, [{atom, L2, 'record'}, {integer, L3, I1}, {var, L4, pt_supp:string2atom(VarStrTail)}, DD]};
                        _ ->
                            Tr
                    end;
                {tuple, L, [{atom, L2, 'record'}, {integer, L3, I1}, Var, Record, DD]} ->
                    NewRecord =
                        case Record of
                            {atom, L4, RecordAtom} ->
                                begin
                                    RecordStr = atom_to_list(RecordAtom),
                                    case RecordStr of
                                        [ $\\, $@ | RecordStrTail] -> {atom, L4, pt_supp:string2atom([$@ | RecordStrTail])};
                                        [ $\\, $$ | RecordStrTail] -> {atom, L4, pt_supp:string2atom([$$ | RecordStrTail])};
                                        [ $@ | RecordStrTail] -> {var, L4, pt_supp:string2atom(RecordStrTail)};
                                        [ $$ | RecordStrTail] -> {var, L4, pt_supp:string2atom(RecordStrTail)};
                                        _ -> Record
                                    end
                                end;
                            _ -> Record
                        end,
                    {tuple, L, [{atom, L2, 'record'}, {integer, L3, I1}, Var, NewRecord, DD]};
                {tuple, L, [{atom, L2, 'record_field'}, {integer, L3, I1}, Var, {atom, L4, Record}, Field]} ->
                    NewRecord =
                        begin
                            RecordStr = atom_to_list(Record),
                            case RecordStr of
                                [ $\\, $@ | RecordStrTail] -> {atom, L4, pt_supp:string2atom([$@ | RecordStrTail])};
                                [ $\\, $$ | RecordStrTail] -> {atom, L4, pt_supp:string2atom([$$ | RecordStrTail])};
                                [ $@ | RecordStrTail] -> {var, L4, pt_supp:string2atom(RecordStrTail)};
                                [ $$ | RecordStrTail] -> {var, L4, pt_supp:string2atom(RecordStrTail)};
                                _ -> {atom, L4, Record}
                            end
                        end,
                    {tuple, L, [{atom, L2, 'record_field'}, {integer, L3, I1}, Var, NewRecord, Field]};
                {tuple, L, [{atom, L2, 'record_index'}, {integer, L3, I1}, {atom, L4, Record}, Field]} ->
                    NewRecord =
                        begin
                            RecordStr = atom_to_list(Record),
                            case RecordStr of
                                [ $\\, $@ | RecordStrTail] -> {atom, L4, pt_supp:string2atom([$@ | RecordStrTail])};
                                [ $\\, $$ | RecordStrTail] -> {atom, L4, pt_supp:string2atom([$$ | RecordStrTail])};
                                [ $@ | RecordStrTail] -> {var, L4, pt_supp:string2atom(RecordStrTail)};
                                [ $$ | RecordStrTail] -> {var, L4, pt_supp:string2atom(RecordStrTail)};
                                _ -> {atom, L4, Record}
                            end
                        end,
                    {tuple, L, [{atom, L2, 'record_index'}, {integer, L3, I1}, NewRecord, Field]};

                Tr -> Tr
            end
        end,
        AST).


% processing things like "{String, @Module}" in ast_pattern
process_pattern_variables(AST) ->
   erl_syntax_lib:mapfold(
        fun (T, Vars) ->
            Tr = erl_syntax:revert(T),
            case Tr of
                {tuple, L, [{atom, L2, 'function'}, L3, {atom, L4, FunName}, Arity, Clauses]} ->
                    VarStr = atom_to_list(FunName),
                    case VarStr of
                        [ $@ | VarStrTail] ->
                            {{tuple, L, [{atom, L2, 'function'}, L3, {var, L4, pt_supp:string2atom(VarStrTail)}, Arity, Clauses]}, Vars};
                        [ $$ | VarStrTail] ->
                            {{tuple, L, [{atom, L2, 'function'}, L3, {var, L4, pt_supp:string2atom(VarStrTail)}, Arity, Clauses]}, Vars};
                        _ -> {Tr, Vars}
                    end;
                {tuple, L, [{atom, _, atom}, {integer, _, _}, {atom, _, Atom}]} ->
                    VarStr = atom_to_list(Atom),
                    case VarStr of
                        [ $@ | VarStrTail] ->
                            {{var, L, pt_supp:mk_atom("__pt_tmp_var_", VarStrTail)}, Vars ++ [pt_supp:string2atom(VarStrTail)]};
                        [ $$ | VarStrTail] ->
                            {{var, L, pt_supp:string2atom(VarStrTail)}, Vars};
                        _ ->
                            {Tr, Vars}
                    end;
                {tuple, L, [{atom, L2, 'record'}, {integer, L3, I1}, {atom, L4, Atom}, DD]} ->
                    VarStr = atom_to_list(Atom),
                    case VarStr of
                        [ $\\, $@ | VarStrTail] ->
                            {{tuple, L, [{atom, L2, 'record'}, {integer, L3, I1}, {atom, L4, pt_supp:string2atom([$@ | VarStrTail])}, DD]}, Vars};
                        [ $\\, $$ | VarStrTail] ->
                            {{tuple, L, [{atom, L2, 'record'}, {integer, L3, I1}, {atom, L4, pt_supp:string2atom([$$ | VarStrTail])}, DD]}, Vars};
                        [ $@ | VarStrTail] ->
                            {{tuple, L, [{atom, L2, 'record'}, {integer, L3, I1}, {var, L4, pt_supp:string2atom(VarStrTail)}, DD]}, Vars};
                        [ $$ | VarStrTail] ->
                            {{tuple, L, [{atom, L2, 'record'}, {integer, L3, I1}, {var, L4, pt_supp:string2atom(VarStrTail)}, DD]}, Vars};
                        _ ->
                            {Tr, Vars}
                    end;
                {tuple, L, [{atom, L2, 'record'}, {integer, L3, I1}, Var, Record, DD]} ->
                    NewRecord =
                        case Record of
                            {atom, L4, RecordAtom} ->
                                begin
                                    RecordStr = atom_to_list(RecordAtom),
                                    case RecordStr of
                                        [ $\\, $@ | RecordStrTail] -> {atom, L4, pt_supp:string2atom([$@ | RecordStrTail])};
                                        [ $\\, $$ | RecordStrTail] -> {atom, L4, pt_supp:string2atom([$$ | RecordStrTail])};
                                        [ $@ | RecordStrTail] -> {var, L4, pt_supp:string2atom(RecordStrTail)};
                                        [ $$ | RecordStrTail] -> {var, L4, pt_supp:string2atom(RecordStrTail)};
                                        _ -> Record
                                    end
                                end;
                            _ -> Record
                        end,
                    {{tuple, L, [{atom, L2, 'record'}, {integer, L3, I1}, Var, NewRecord, DD]}, Vars};
                {tuple, L, [{atom, L2, 'record_field'}, {integer, L3, I1}, Var, {atom, L4, Record}, Field]} ->
                    NewRecord =
                        begin
                            RecordStr = atom_to_list(Record),
                            case RecordStr of
                                [ $\\, $@ | RecordStrTail] -> {atom, L4, pt_supp:string2atom([$@ | RecordStrTail])};
                                [ $\\, $$ | RecordStrTail] -> {atom, L4, pt_supp:string2atom([$$ | RecordStrTail])};
                                [ $@ | RecordStrTail] -> {var, L4, pt_supp:string2atom(RecordStrTail)};
                                [ $$ | RecordStrTail] -> {var, L4, pt_supp:string2atom(RecordStrTail)};
                                _ -> {atom, L4, Record}
                            end
                        end,
                    {{tuple, L, [{atom, L2, 'record_field'}, {integer, L3, I1}, Var, NewRecord, Field]}, Vars};
                {tuple, L, [{atom, L2, 'record_index'}, {integer, L3, I1}, {atom, L4, Record}, Field]} ->
                    NewRecord =
                        begin
                            RecordStr = atom_to_list(Record),
                            case RecordStr of
                                [ $\\, $@ | RecordStrTail] -> {atom, L4, pt_supp:string2atom([$@ | RecordStrTail])};
                                [ $\\, $$ | RecordStrTail] -> {atom, L4, pt_supp:string2atom([$$ | RecordStrTail])};
                                [ $@ | RecordStrTail] -> {var, L4, pt_supp:string2atom(RecordStrTail)};
                                [ $$ | RecordStrTail] -> {var, L4, pt_supp:string2atom(RecordStrTail)};
                                _ -> {atom, L4, Record}
                            end
                        end,
                    {{tuple, L, [{atom, L2, 'record_index'}, {integer, L3, I1}, NewRecord, Field]}, Vars};
                _ -> {Tr, Vars}
            end
        end,
        [],
        AST).

process_line_var(AST, LineParamAST, attribute) ->
    Res = erl_syntax_lib:map(
            fun (T) ->
                case erl_syntax:revert(T) of
                    {tuple, Line1, [{atom, Line2, attribute}, {integer, _, _} | Tail]} ->
                        {tuple, Line1, [{atom, Line2, attribute}, LineParamAST | Tail]};
                    {tuple, Line1, [{atom, Line2, Type}, {integer, _, _} = Head | Tail]} ->
                        {tuple, Line1, [{atom, Line2, Type}, Head | Tail]};
                    _ -> T
                end
            end,
            AST
        ),
    erl_syntax:revert(Res);

process_line_var(AST, LineParamAST, _) ->
    Res = erl_syntax_lib:map(
            fun (T) ->
                case erl_syntax:revert(T) of
                    {tuple, Line1, [{atom, Line2, Type}, {integer, _, _} | Tail]} ->
                        {tuple, Line1, [{atom, Line2, Type}, LineParamAST | Tail]};
                    _ -> T
                end
            end,
            AST
        ),
    erl_syntax:revert(Res).

process_pattern_line_var(AST, LineVar) ->
    % Replace first line to variable
    AST1 = erl_syntax:revert(AST),
    AST2 = case LineVar of
                {var, _, LineVarAtom}  ->
                    case AST1 of
                        {tuple, Line1, [{atom, Line2, Type1}, {integer, Line3, _} | Tail1]} ->
                            {tuple, Line1, [{atom, Line2, Type1}, {var, Line3, LineVarAtom} | Tail1]};
                        {cons, Line1, {tuple, Line2, [{atom, Line3, Type1}, {integer, Line44, _} | Tail1]}, ListTail1} ->
                            {cons, Line1, {tuple, Line2, [{atom, Line3, Type1}, {var, Line44, LineVarAtom} | Tail1]}, ListTail1};
                        _ -> AST1
                    end;
                {integer, _, LineValue} ->
                    case AST1 of
                        {tuple, Line1, [{atom, Line2, Type1}, {integer, Line3, _} | Tail1]} ->
                            {tuple, Line1, [{atom, Line2, Type1}, {integer, Line3, LineValue} | Tail1]};
                        {cons, Line1, {tuple, Line2, [{atom, Line3, Type1}, {integer, Line44, _} | Tail1]}, ListTail1} ->
                            {cons, Line1, {tuple, Line2, [{atom, Line3, Type1}, {integer, Line44, LineValue} | Tail1]}, ListTail1};
                        _ -> AST1
                    end
           end,

    AST3 =  erl_syntax:revert(
            erl_syntax_lib:map_subtrees(
            fun (Tree) ->
            erl_syntax_lib:map(
                fun (T) ->
                    case erl_syntax:revert(T) of
                        {tuple, Line4, [{atom, Line5, Type2}, {integer, Line6, _} | Tail2]} ->
                            {tuple, Line4, [{atom, Line5, Type2}, {var, Line6, '_'} | Tail2]};
                        _ -> T
                    end
                end,
                erl_syntax:revert(Tree)
            ) end,
            AST2)),
    AST3.

%   fun(Pattern) -> Value;
%      (Tree) -> Tree
%    end.
%
%   Using \/, cause '@A' variables
%
%   fun(X) ->
%       case X of
%           Pattern -> Value;
%           _ -> X
%       end
%   end
construct_replace_fun(Pattern, Value, Line) ->
    pt_supp:insert_lines(erl_syntax:revert(erl_syntax:fun_expr(
        [erl_syntax:clause([erl_syntax:variable('__PT_LIB_REPLACE_CASE_VAR_P')], none, [
            erl_syntax:case_expr(erl_syntax:variable('__PT_LIB_REPLACE_CASE_VAR_P'), [
                erl_syntax:clause([Pattern], none, [Value]),
                erl_syntax:clause([erl_syntax:variable('__PT_LIB_REPLACE_CASE_VAR_X')], none, [erl_syntax:variable('__PT_LIB_REPLACE_CASE_VAR_X')])
            ])
        ])]
    )), Line).

format_error(E) ->
    pt_supp:format_error(E).
