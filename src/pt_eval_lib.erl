%%%-------------------------------------------------------------------
%%% @author nikita
%%% @copyright (C) 2017, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 31. Oct 2017 15:27
%%%-------------------------------------------------------------------
-module(pt_eval_lib).
-include_lib("../include/pt_supp.hrl").
-include_lib("../include/pt_error_macro.hrl").

-export([parse_transform/2, format_error/1]).
parse_transform_PATROL_LOGER_PT_FUN1(AST, _) ->
    F = fun (__PT_PT_LIB_MATCH_FUN_VAR) ->
        case __PT_PT_LIB_MATCH_FUN_VAR of
            {call, _, {atom, _, pt_eval}, [_]} -> true;
            _ -> false
        end
        end,
    ListAST = supp_match(AST, F),
    Timeout = case get_attribute_value(pt_eval_timeout, AST)
              of
                  [Timeout1] -> Timeout1;
                  _ -> 1000
              end,
    NewListAST = replace_const_fun(ListAST, Timeout),
    Module = get_module_name(AST),
    NameCall = list_to_atom("calc" ++
    erlang:atom_to_list(Module)),
    F1 = {function, 0, NameCall, 0,
        [{clause, 0, [], [],
            [{match, 0, {var, 0, 'L'}, NewListAST},
                {lc, 0, {call, 0, {var, 0, 'F'}, []},
                    [{generate, 0, {var, 0, 'F'}, {var, 0, 'L'}}]}]}]},
    AST2 = add_function1(AST, F1),
    {AST3, _} = replace_fold(AST2,
        fun (__PT_PT_LIB_REPLACE_FOLD_FUN_VAR,
            __PT_PT_LIB_REPLACE_FOLD_ACC_VAR) ->
            case {__PT_PT_LIB_REPLACE_FOLD_FUN_VAR,
                __PT_PT_LIB_REPLACE_FOLD_ACC_VAR}
            of
                {{call, _Line, {atom, _, pt_eval},
                    [String]},
                    Acc} ->
                    begin {String, Acc} end;
                PT_TMP_X -> PT_TMP_X
            end
        end,
        []),
    try case catch lib_compile_and_load(AST3) of
            ok ->
                Data = Module:NameCall(),
                {AST4, _} = create_new_ast(Data, AST),
                true = code:delete(Module),
                case compile:forms(AST4, [return_warnings]) of
                    {ok, _, _, [{_, Warning}]} ->
                        delete_unused_functions(Warning, AST4);
                    _ -> AST4
                end;
            _Er ->
                throw({parse_error,
                    {0, pt_const_fun,
                        {dynamic_data, {error, compile_and_load}}}}),
                AST
        end
    catch
        {error, {pt_lib, _, _, _}} ->
            {ok, Cwd} = file:get_cwd(),
            File = get_file_name(AST),
            FullFile = filename:join(Cwd, File),
            io_lib:format("~ts: Warning: can not compile",
                [FullFile]),
            AST
    end.

get_file_name(AST) ->
    case lists:keyfind(file, 3, AST) of
        {attribute, _, file, {Filename, _}} -> Filename;
        _ ->
            throw({error,
                {pt_eval_lib,
                    {"src/pt_eval_lib.erl", 83},
                    {get_file_name, not_found},
                    element(2, catch erlang:error(callstack))}})
    end.

lib_compile_and_load(AST) ->
    case supp_compile_and_load(AST) of
        ok -> ok;
        Err ->
            throw({error,
                {pt_eval_lib,
                    {"src/pt_eval_lib.erl", 89},
                    {compile_and_load, Err},
                    element(2, catch erlang:error(callstack))}})
    end.

supp_compile_and_load(AST) ->
    ModuleName = get_module_name(AST),
    case compile:forms(AST, [binary, return_errors]) of
        {ok, Module, Binary} ->
            case code:soft_purge(Module) of
                true ->
                    case code:load_binary(Module,
                        atom_to_list(Module) ++ ".erl", Binary)
                    of
                        {module, Module} -> ok;
                        {error, Cause} -> {error, {cant_load, Module, Cause}}
                    end;
                false -> {error, soft_purge_failed}
            end;
        error -> {error, {compile_error, ModuleName}};
        {error, Errors, Warnings} ->
            {error, {compile_error, ModuleName, Errors, Warnings}}
    end.

replace_fold([Tree | Tail], Fun, InitAcc, Res) ->
    {ResTree, NewAcc} = replace_fold(Tree, Fun, InitAcc),
    replace_fold(Tail, Fun, NewAcc, [ResTree | Res]);
replace_fold([], _Fun, InitAcc, Res) ->
    {lists:reverse(Res), InitAcc}.

replace_fold(AST, Fun, InitAcc)
    when erlang:is_list(AST) ->
    replace_fold(AST, Fun, InitAcc, []);
replace_fold(Tree, Fun, InitAcc) ->
    {AST, Acc} = erl_syntax_lib:mapfold(fun (T, Acc) ->
        Tr = erl_syntax:revert(T),
        {ResTr, ResAcc} = Fun(Tr, Acc),
        log_replace(Tr, ResTr),
        {ResTr, ResAcc}
                                        end,
        InitAcc, Tree),
    {erl_syntax:revert(AST), Acc}.

log_replace(Tree, Tree) -> ok;
log_replace(Tree, Res) ->
    begin
        case whereis(patrol_process) of
            undefined -> ok;
            _ ->
                pt_patrol:debug("pt <<<<<<~n~ts~n============~n~ts~npt "
                ">>>>>>~n ",
                    [case ast2str(Tree) of
                         {ok, String1} -> String1;
                         {error, E1} ->
                             throw({error,
                                 {pt_eval_lib,
                                     {"src/pt_eval_lib.erl",
                                         137},
                                     {ast2str, E1},
                                     element(2,
                                         catch
                                             erlang:error(callstack))}})
                     end,
                        case ast2str(Res) of
                            {ok, String2} -> String2;
                            {error, E2} ->
                                throw({error,
                                    {pt_eval_lib,
                                        {"src/pt_eval_lib.erl",
                                            142},
                                        {ast2str, E2},
                                        element(2,
                                            catch
                                                erlang:error(callstack))}})
                        end]),
                ok
        end,
        ok
    end,
    ok.

ast2str(P) ->
    try {ok, ast2str2(P)} catch _:E -> {error, E} end.

ast2str2([T | Tail]) ->
    Add = case {T, Tail} of
              {Tuple, _}
                  when is_tuple(Tuple) andalso
                  element(1, Tuple) =:= attribute ->
                  io_lib:format("~n", []);
              {{function, _, _, _, _}, _} ->
                  io_lib:format("~n~n", []);
              {_, []} -> "";
              {_, _} -> ", "
          end,
    ast2str2(T) ++ Add ++ ast2str2(Tail);
ast2str2([]) -> "";
ast2str2(Tree) ->
    try erl_prettypr:format(Tree) catch
        _:E -> throw({E, Tree})
    end.

supp_match(List, Fun) when erlang:is_list(List) ->
    supp_match(List, Fun, []);
supp_match(Tree, Fun) ->
    erl_syntax_lib:fold(fun (El, Acc) ->
        case Fun(El) of
            true -> [El | Acc];
            false -> Acc
        end
                        end,
        [], Tree).

supp_match([El | Tail], Fun, Res) ->
    supp_match(Tail, Fun, supp_match(El, Fun) ++ Res);
supp_match([], _Fun, Res) -> lists:reverse(Res).

add_local_function1(AST,
    Fun = {function, LineFunction, Name, Arity, _}) ->
    case lists:keyfind(Name, 3, AST) of
        {function, L, Name, Arity, _} ->
            throw({parse_error,
                {L, pt_eval_lib,
                    {fun_already_exists, Name, Arity}}});
        _ -> ok
    end,
    case supp_match(
        AST,
        fun (__PT_PT_LIB_MATCH_FUN_VAR) ->
            case __PT_PT_LIB_MATCH_FUN_VAR of
                {eof, _} -> true;
                _ -> false
            end
        end
    )
    of
        [{eof, Line} = EOF] ->
            case LineFunction /= 0 andalso LineFunction < Line of
                true ->
                    ASTTmp = replace(
                        AST,
                        fun (__PT_PT_LIB_REPLACE_FUN_VAR) ->
                            case __PT_PT_LIB_REPLACE_FUN_VAR of
                                EOF -> Fun;
                                PT_TMP_X -> PT_TMP_X
                            end
                        end
                    );
                false ->
                    ASTTmp = replace(
                        AST,
                        fun (__PT_PT_LIB_REPLACE_FUN_VAR) ->
                            case __PT_PT_LIB_REPLACE_FUN_VAR of
                                EOF ->
                                    insert_lines(Fun, Line);
                                    PT_TMP_X -> PT_TMP_X
                            end
                        end
                    )
            end,
            lists:append(ASTTmp, [{eof, Line}]);
        _ ->
            throw({parse_error, {0, pt_eval_lib, {bad_param, AST}}})
    end;
add_local_function1(_AST, Fun) ->
    throw({
        error,
        {
            pt_eval_lib,
            {"src/pt_eval_lib.erl", 216},
            {bad_param, Fun},
            element(2, catch erlang:error(callstack))
        }
    }).

insert_lines(ListAST, Line) when is_list(ListAST) ->
    erl_syntax:revert([insert_lines(T, Line) || T <- ListAST]);
insert_lines(AST, Line) ->
    AST1 = erl_syntax_lib:map(fun (T) ->
        case erl_syntax:revert(T) of
            {Atom, N, P}
                when is_atom(Atom) and
                is_integer(N) ->
                {Atom, Line, P};
            {Atom, N, P1, P2}
                when is_atom(Atom) and
                is_integer(N) ->
                {Atom, Line, P1, P2};
            {Atom, N, P1, P2, P3}
                when is_atom(Atom) and
                is_integer(N) ->
                {Atom, Line, P1, P2, P3};
            {nil, N} when is_integer(N) ->
                {nil, Line};
            Tr -> Tr
        end
                              end,
        AST),
    erl_syntax:revert(AST1).

add_function1(AST, Fun = {function, _, Name, Arity, _}) ->
    AST1 = add_local_function1(AST, Fun),
    AST2 =
        case
            supp_match(
                AST1,
                fun (__PT_PT_LIB_MATCH_FUN_VAR) ->
                    case __PT_PT_LIB_MATCH_FUN_VAR of
                        {attribute, _, export, _} -> true;
                        _ -> false
                    end
                end
            )
        of
            [] ->
                lists:foldr(
                    fun ({attribute, ML, module, _} = M, Acc) ->
                        [M, {attribute, ML, export, []} | Acc];
                        (El, Acc) -> [El | Acc]
                    end,
                    [],
                    AST1
                );
            _ -> AST1
        end,
        case
            lists:any(
                fun ({_, _, _, List}) ->
                    lists:member({Name, Arity}, List)
                end,
                supp_match(
                    AST2,
                    fun (__PT_PT_LIB_MATCH_FUN_VAR) ->
                        case __PT_PT_LIB_MATCH_FUN_VAR of
                            {attribute, _, export, _} -> true;
                            _ -> false
                        end
                    end
                )
            )
        of
            false ->
                replace_first(
                    AST2,
                    fun (__PT_LIB_REPLACE_CASE_VAR_P) ->
                        case __PT_LIB_REPLACE_CASE_VAR_P of
                            {attribute, Line1, export, List} ->
                                {attribute, Line1, export, [{Name, Arity} | List]};
                            __PT_LIB_REPLACE_CASE_VAR_X ->
                                __PT_LIB_REPLACE_CASE_VAR_X
                        end
                    end
                );
            _ -> AST2
        end;
add_function1(_AST, Fun) ->
    throw(
        {
            error,
            {
                pt_eval_lib,
                {"src/pt_eval_lib.erl", 266},
                {bad_param, Fun},
                element(2, catch erlang:error(callstack))
            }
        }
    ).

concat_module_name([First | Atoms])
    when is_list(Atoms) ->
    Name = lists:foldl(fun (A, Acc) ->
        Acc ++ "." ++ erlang:atom_to_list(A)
                       end,
        erlang:atom_to_list(First), Atoms),
    erlang:list_to_atom(Name).

get_module_name(AST) ->
    case lists:keyfind(module, 3, AST) of
        {attribute, _, module, Module} when is_atom(Module) ->
            Module;
        {attribute, _, module, Module} when is_list(Module) ->
            concat_module_name(Module);
        _ ->
            throw({error,
                {pt_eval_lib,
                    {"src/pt_eval_lib.erl", 282},
                    {get_module_name, not_found},
                    element(2, catch erlang:error(callstack))}})
    end.

get_attribute_value(Attribute, AST) ->
    lists:foldl(fun (Tree, Acc) ->
        case Tree of
            {attribute, _, Attribute, List} when is_list(List) ->
                List ++ Acc;
            {attribute, _, Attribute, {Attr, List}}
                when is_list(List) and is_atom(Attr) ->
                case lists:map(fun (P) ->
                    case P of
                        {Attr, AList}
                            when
                            is_list(AList) ->
                            {Attr,
                                    List ++ AList};
                        _ -> P
                    end
                               end,
                    Acc)
                of
                    Acc -> [{Attr, List} | Acc];
                    Res -> Res
                end;
            {attribute, _, Attribute, Attr} -> [Attr | Acc];
            _ -> Acc
        end
                end,
        [], AST).

delete_unused_functions([{_, _,
    {unused_function, {Name, CountArg}}}
    | TailWarning],
    AST) ->
    NewAST = delete_unused_function(AST, {Name, CountArg},
        []),
    delete_unused_functions(TailWarning, NewAST);
delete_unused_functions([_ | TailWarning], AST) ->
    delete_unused_functions(TailWarning, AST);
delete_unused_functions(_, AST) -> AST.

delete_unused_function([{function, _, Name, CountArg, _}
    | TailAST],
    {Name, CountArg}, Acc) ->
    delete_unused_function(TailAST, {Name, CountArg}, Acc);
delete_unused_function([HeadAST | TailAST],
    {Name, CountArg}, Acc) ->
    delete_unused_function(TailAST, {Name, CountArg},
        [HeadAST | Acc]);
delete_unused_function(_, _, Acc) -> lists:reverse(Acc).

replace_const_fun([HeadAST | TailAST], Timeout) ->
    {NewHeadAST, _} = replace_fold(HeadAST,
        fun
            (__PT_PT_LIB_REPLACE_FOLD_FUN_VAR,
                __PT_PT_LIB_REPLACE_FOLD_ACC_VAR) ->
                case
                    {__PT_PT_LIB_REPLACE_FOLD_FUN_VAR,
                        __PT_PT_LIB_REPLACE_FOLD_ACC_VAR}
                of
                    {{call, _,
                        {atom, _, pt_eval},
                        [String]},
                        Acc} ->
                        begin
                            {create_new_fun(String,
                                Timeout),
                                Acc}
                        end;
                    PT_TMP_X -> PT_TMP_X
                end
        end,
        []),
    {cons, 0, NewHeadAST,
        replace_const_fun(TailAST, Timeout)};
replace_const_fun(_, _) -> {nil, 0}.

create_new_ast(Data, AST) ->
    replace_fold(AST,
        fun (__PT_PT_LIB_REPLACE_FOLD_FUN_VAR,
            __PT_PT_LIB_REPLACE_FOLD_ACC_VAR) ->
            case {__PT_PT_LIB_REPLACE_FOLD_FUN_VAR,
                __PT_PT_LIB_REPLACE_FOLD_ACC_VAR}
            of
                {{call, Line, {atom, _, pt_eval}, [String]},
                    [Head | Tail]} ->
                    begin
                        case Head of
                            {ok, NewData} ->
                                {abstract(NewData, Line), Tail};
                            _ ->
                                throw({parse_error,
                                    {Line, pt_const_fun,
                                        {dynamic_data, Head}}}),
                                {String, Tail}
                        end
                    end;
                PT_TMP_X -> PT_TMP_X
            end
        end,
        Data).

abstract(Term, Line) ->
    Res = try erl_parse:abstract(Term) catch
              _:E ->
                  throw({error,
                      {pt_eval_lib,
                          {"src/pt_eval_lib.erl", 367},
                          {bad_term, Term, E},
                          element(2, catch erlang:error(callstack))}})
          end,
    insert_lines(Res, Line).

create_new_fun(String, Timeout) ->
    CallFunction = {'fun', 0,
        {clauses,
            [{clause, 0, [], [],
                [{'try', 0,
                    [{match, 0, {var, 0, 'Data'}, String},
                        {op, 0, '!', {var, 0, 'Self'},
                            {tuple, 0,
                                [{tuple, 0, [{atom, 0, ok}, {var, 0, 'Data'}]},
                                    {var, 0, 'Ref'}]}}],
                    [],
                    [{clause, 0,
                        [{tuple, 0,
                            [{var, 0, 'Exception'}, {var, 0, 'Reason'},
                                {var, 0, '_'}]}],
                        [],
                        [{op, 0, '!', {var, 0, 'Self'},
                            {tuple, 0,
                                [{tuple, 0,
                                    [{atom, 0, error}, {var, 0, 'Exception'},
                                        {var, 0, 'Reason'}]},
                                    {var, 0, 'Ref'}]}}]}],
                    []}]}]}},
    {'fun', 0,
        {clauses,
            [{clause, 0, [], [],
                [{match, 0, {var, 0, 'Self'},
                    {call, 0, {atom, 0, self}, []}},
                    {match, 0, {var, 0, 'Ref'},
                        {call, 0, {atom, 0, make_ref}, []}},
                    {call, 0, {atom, 0, spawn}, [CallFunction]},
                    {'receive', 0,
                        [{clause, 0,
                            [{tuple, 0, [{var, 0, 'Result'}, {var, 0, 'Ref'}]}], [],
                            [{var, 0, 'Result'}]}],
                        abstract(Timeout, 0),
                        [{tuple, 0,
                            [{atom, 0, error}, {atom, 0, timeout}]}]}]}]}}.

format_error({dynamic_data, Error}) ->
    case Error of
        {error, TypeError, NameError} ->
            io_lib:format("~p: occurred during compilation pt_eval ~p",
                [TypeError, NameError]);
        {error, NameError} ->
            io_lib:format("~p: occurred during compilation pt_eval ~p",
                [error, NameError]);
        _ ->
            io_lib:format("~p: can not compile pt_eval", [warning])
    end;
format_error(Unknown) ->
    io_lib:format("Unknown error: ~p", [Unknown]).

parse_transform(AST, Options) ->
    StartRes = startPatrolProcess_PATROL_LOGER_PT_FUN1(AST),
    ResAST = try Tmp =
        parse_transform_PATROL_LOGER_PT_FUN1(AST, Options),
    stopPatrolProcess_PATROL_LOGER_PT_FUN1(Tmp, StartRes),
    Tmp
             catch
                 C:E ->
                     case {C, E} of
                         {throw, {parse_error, _} = Error} ->
                             stopPatrolProcess_PATROL_LOGER_PT_FUN1({string, 0,
                                 "Compilation error."},
                                 StartRes),
                             generate_errors(AST, [Error], []) ++ AST;
                         {throw, {error, _} = Error} ->
                             stopPatrolProcess_PATROL_LOGER_PT_FUN1({string, 0,
                                 "Compilation error."},
                                 StartRes),
                             generate_errors(AST, [Error], []) ++ AST;
                         {throw, {internal_error, _} = Error} ->
                             stopPatrolProcess_PATROL_LOGER_PT_FUN1({string, 0,
                                 "Compilation error."},
                                 StartRes),
                             generate_errors(AST, [Error], []) ++ AST;
                         {C, E} ->
                             ST = erlang:get_stacktrace(),
                             stopPatrolProcess_PATROL_LOGER_PT_FUN1({string, 0,
                                 "Compilation error."},
                                 StartRes),
                             generate_errors(AST,
                                 [{internal_error, {pt_patrol, 0},
                                     {exception, {E, ST}},
                                     element(2,
                                         catch
                                             erlang:error(callstack))}],
                                 [])
                             ++ AST
                     end
             end,
    ResAST.

generate_errors(_AST, [], Res) -> Res;
generate_errors(AST, [Error | Tail], Res) ->
    NewRes = case Error of
                 {parse_error, {Line, _, _} = ErrorInfo} ->
                     FileName = case catch get_file_name(AST) of
                                    FName when is_list(FName) -> FName;
                                    _ -> ""
                                end,
                     [{attribute, 0, file, {FileName, Line}},
                         {error, ErrorInfo}
                         | Res];
                 {error,
                     {Module, {Filename, Line}, ErrorDescriptor,
                         {callstack, _CallStack}}} ->
                     [{attribute, Line, file, {Filename, Line}},
                         {error, {Line, Module, ErrorDescriptor}}
                         | Res];
                 {internal_error,
                     {Module, {Filename, Line}, ErrorDescriptor,
                         {callstack, _CallStack}}} ->
                     [{attribute, Line, file, {Filename, Line}},
                         {error, {Line, Module, ErrorDescriptor}}
                         | Res];
                 Unknown ->
                     [{attribute, 491, file,
                         {"src/pt_eval_lib.erl", 491}},
                         {error, {491, pt_eval_lib, Unknown}}
                         | Res]
             end,
    generate_errors(AST, Tail, NewRes).

startPatrolProcess_PATROL_LOGER_PT_FUN1(_) ->
%%    Params = lists:map(fun ({source, FileName}) ->
%%        {source,
%%            process_macro_PATROL_LOGER_PT_FUN1(FileName,
%%                AST)};
%%        ({file, FileName, Filter}) ->
%%            {file,
%%                process_macro_PATROL_LOGER_PT_FUN1(FileName,
%%                    AST),
%%                Filter};
%%        (X) -> X
%%                       end,
%%        [{tty, error}]),
    ok.

%%process_macro_PATROL_LOGER_PT_FUN1(Str, AST) ->
%%    Str1 = re:replace(Str, "%MODULE",
%%        atom_to_list(get_module_name(AST)),
%%        [unicode, global, {return, list}]),
%%    {ok, [[HomeDir]]} = init:get_argument(home),
%%    Str2 = re:replace(Str1, "%HOME", HomeDir,
%%        [unicode, global, {return, list}]),
%%    User = filename:basename(HomeDir),
%%    re:replace(Str2, "%USER", User,
%%        [unicode, global, {return, list}]).

stopPatrolProcess_PATROL_LOGER_PT_FUN1(_, _) ->
    ok.

replace(AST, Fun) ->
    replace(AST, Fun, true).

replace(List, Fun, Log) when is_list(List) ->
    erl_syntax:revert([replace(Tree, Fun, Log) || Tree <- List]);

replace(Tree, Fun, Log) ->
    erl_syntax:revert(erl_syntax_lib:map(
        fun(T) ->
            Tr = erl_syntax:revert(T),
            NewTr = Fun(Tr),
            case Log of
                true -> log_replace(Tr, NewTr);
                _ -> ok
            end,
            NewTr
        end,
        Tree)).

replace_first(List, Fun) when is_list(List) ->
    erl_syntax:revert(element(1, lists:mapfoldl(
        fun
            (T, false) ->
                replace_first_(T, Fun);
            (T, true) ->
                {T, true}
        end, false, List)));

replace_first(Tree, Fun) ->
    element(1, replace_first_(Tree, Fun)).

replace_first_(Tree, Fun) ->
    {Tree2, Res} = erl_syntax_lib:mapfold(
        fun(T, false) ->
            Tr = erl_syntax:revert(T),
            NewTr = Fun(Tr),
            log_replace(Tr, NewTr),
            case NewTr of
                Tr -> {Tr, false};
                NewTr -> {NewTr, true}
            end;
            (T, true) -> {erl_syntax:revert(T), true}
        end,
        false,
        Tree),

    {erl_syntax:revert(Tree2), Res}.
