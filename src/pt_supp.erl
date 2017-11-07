%%%-------------------------------------------------------------------
%%% -*- coding: utf-8 -*-
%%% @author Timofey Barmin
%%% @copyright (C) 2015, Eltex, Novosibirsk, Russia
%%% @doc
%%%     pt_lib auxiliary module.
%%%     Contains "clean" ast transformation functions.
%%%     No "pt magic" is allowed here.
%%% @end
%%%-------------------------------------------------------------------
-module(pt_supp).
-compile({parse_transform, pt_eval_lib}).

-include("pt_supp.hrl").
-include("pt_error_macro.hrl").
-include("pt_types.hrl").

-export([
            replace_remote_call/5,
            replace_local_call/4,
            get_file_name/1,
            get_module_name/1,
            set_module_name/2,
            replace/2,
            replace/3,
            replace_fold/3,
            abstract/2,
            insert_lines/2,
            replace_first/2,
            get_function_ast/3,
            replace_function_clause_code/6,
            get_compile_options/1,
            get_attribute_value/2,
            set_attribute/3,
            str2ast/2,
            ast2str/1,
            generate_errors/3,
            format_errors/1,
            format_warnings/1,
            format_error/1,
            print_error/2,
            print_error/3,
            format_str2ast_error/2,
            is_var_name/1,
            list_map/2,
            list_map_fold/3,
            list_fold/3,
            list_foldr/3,
            list_reverse/1,
            list_concat/2,
            list_length/1,
            match/2,
            first_clause/2,
            compile/1,
            compile_to_beam/2,
            compile_and_load/1,
            create_clear_ast/1,
            string2atom/1,
            mk_atom/2,
            is_term/1,
            is_term_or_var/1
        ]).

-ifdef(TEST).
-export([replace_attribute/4]).
-endif.

-spec get_module_name(ast()) ->
    ModuleName :: module().
%%--------------------------------------------------------------------
%% @throws  {get_module_name, not_found}
%%
%% @doc     Returns module name for the `AST'.
%% @end
%%--------------------------------------------------------------------
get_module_name(AST) ->
    case lists:keyfind(module, 3, AST) of
        {attribute,_,module,Module} when is_atom(Module) -> Module;
        {attribute,_,module,Module} when is_list(Module) -> concat_module_name(Module);
        _ ->
            throw(?mk_error({get_module_name, not_found}))
    end.

-spec set_module_name(ast(), Module :: module()) -> ast().
%%--------------------------------------------------------------------
%% @doc     Sets module name `ModuleName' for the `AST'.
%% @end
%%--------------------------------------------------------------------
set_module_name(AST, ModuleName) ->
    lists:map(
        fun ({attribute, L, module, _}) -> {attribute, L, module, ModuleName};
            (E) -> E
        end, AST).

-spec get_file_name(ast()) ->
    Filename :: string().
%%--------------------------------------------------------------------
%% @throws  {get_file_name, not_found}
%%
%% @doc     Returns module filename for the `AST'.
%% @end
%%--------------------------------------------------------------------
get_file_name(AST) ->
    case lists:keyfind(file, 3, AST) of
        {attribute,_,file, {Filename, _}} -> Filename;
        _ ->
            throw(?mk_error({get_file_name, not_found}))
    end.

-spec get_compile_options(ast()) ->
    [Values :: term()].
%%--------------------------------------------------------------------
%% @doc     Returns compile options from the `AST'.
%% @end
%%--------------------------------------------------------------------
get_compile_options(AST) ->
    get_attribute_value(compile, AST).

%%--------------------------------------------------------------------
%% @doc     Returns `Attribute' values list from the `AST'.
%%          But attribute list is interpreted as a list of one
%%          element, i.e. list ~ [list].
%% @end
%%--------------------------------------------------------------------
get_attribute_value(Attribute, AST) ->
    lists:foldl(
    fun(Tree, Acc) ->
        case Tree of
            {attribute, _, Attribute, List} when is_list(List) -> List ++ Acc;
            {attribute, _, Attribute, {Attr, List}} when is_list(List) and is_atom(Attr) ->
                case lists:map(
                        fun (P) ->
                            case P of
                                {Attr, AList} when is_list(AList) -> {Attr, List ++ AList};
                                _ -> P
                            end
                        end, Acc) of
                    Acc -> [{Attr, List} | Acc];
                    Res -> Res
                end;
            {attribute, _, Attribute, Attr} -> [Attr | Acc];
            _ -> Acc
        end
    end, [], AST).

-spec set_attribute(ast(), Attribute :: atom(), Value :: term()) ->
    ast().
%%--------------------------------------------------------------------
%% @throws  {parse_error, {0, Module, {no_module_attribute, Res}}}
%%
%% @doc     Adds or replaces `Attribute' in the `AST' with `Value'.
%% @end
%%--------------------------------------------------------------------
set_attribute(AST, Attribute, Value) ->
    case replace_attribute(AST, Attribute, Value, []) of
        {ok, ResultAST} ->
            ResultAST;
        not_found ->
            add_attribute(AST, Attribute, Value, [])
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%--------------------------------------------------------------------
%% Add attribute after module attribute.
%%--------------------------------------------------------------------
add_attribute([], _Attribute, _Value, Res) ->
    throw(?mk_parse_error(0, {no_module_attribute, lists:reverse(Res)}));
add_attribute([{attribute, Line, module, _} = M|AST], Attribute, Value, Res) ->
    lists:reverse([{attribute, Line, Attribute, Value}, M|Res]) ++ AST;
add_attribute([M|AST], Attribute, Value, Res) ->
    add_attribute(AST, Attribute, Value, [M|Res]).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%--------------------------------------------------------------------
%% Replace exists attribute on value. In case of attribute doesn't exists - return not_found.
%%--------------------------------------------------------------------
replace_attribute([], _Attribute, _Value, _Res) ->
    not_found;
replace_attribute([{attribute, Line, Attribute, _}|AST], Attribute, Value, Res) ->
    {ok, lists:reverse([{attribute, Line, Attribute, Value}|Res]) ++ AST};
replace_attribute([M|AST], Attribute, Value, Res) ->
    replace_attribute(AST, Attribute, Value, [M|Res]).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec match(ast(),
            Fun :: fun( (ast()) -> true  | false ),
            Res :: ast()) ->
        ast().

match([El | Tail], Fun, Res) ->
    match(Tail, Fun, match(El, Fun) ++ Res);
match([], _Fun, Res) ->
    lists:reverse(Res).

-spec match(ListAST :: ast(),
            Fun :: fun((ast()) -> true  | false)) ->
    ast().
%%--------------------------------------------------------------------
%% @doc     Returns AST representing list with elements from the
%%          `ListAST' for which `Fun' returns true.
%% @end
%%--------------------------------------------------------------------
match(List, Fun) when is_list(List) ->
    match(List, Fun, []);
match (Tree, Fun) ->
    erl_syntax_lib:fold(
        fun (El, Acc) ->
            case Fun(El) of
                true -> [El | Acc];
                false -> Acc
            end
        end,
        [],
        Tree
    ).


-spec first_clause(ast(),
            Fun :: fun( (ast()) -> true  | false ),
            Res :: ast()) ->
        ast().

first_clause([El | Tail], Fun, Res) ->
    case first_clause(El, Fun) of
        [] ->
            first_clause(Tail, Fun, Res);
        _ ->
            {_, TypeClause} = type_clause(El),
            first_clause(Tail, Fun, [{TypeClause, El} | Res])
    end;
first_clause([], _Fun, Res) ->
    lists:reverse(Res).

type_clause(Tree) ->
    erl_syntax_lib:fold(
        fun (El, {Leaf, _} = Acc) ->
            case return_type_clause(El) of
                type_undef ->
                    Acc;
                EndClauseType ->
                    {[El | Leaf], EndClauseType}
            end
        end,
        {[], type_undef},
        Tree
    ).

-spec first_clause(ListAST :: ast(),
            Fun :: fun((ast()) -> true  | false)) ->
    ast().
%%--------------------------------------------------------------------
%% @doc     Returns AST representing list with elements from the
%%          `ListAST' for which `Fun' returns true.
%% @end
%%--------------------------------------------------------------------
first_clause(List, Fun) when is_list(List) ->
    first_clause(List, Fun, []);
first_clause(Tree, Fun) ->
    erl_syntax_lib:fold(
        fun (El, Acc) ->
            case Fun(El) of
                true -> [El | Acc];
                false -> Acc
            end
        end,
        [],
        Tree
    ).

return_type_clause({'case', _, _, _}) ->
    type_case;
return_type_clause({'fun', _, {clauses, _}}) ->
    type_fun;
return_type_clause({'if', _, _}) ->
    type_if;
return_type_clause({'receive', _, _}) ->
    type_receive;
return_type_clause({'receive', _, _, _, _}) ->
    type_receive_after;
return_type_clause({'try', _, _, [], _, []}) ->
    type_try_catch;
return_type_clause({'try', _, _, _, _, []}) ->
    type_try_case_catch;
return_type_clause({'try', _, _, [], [], _}) ->
    type_try_after;
return_type_clause({'try', _, _, _, [], _}) ->
    type_try_case_after;
return_type_clause({'try', _, _, [], _, _}) ->
    type_try_catch_after;
return_type_clause({'try', _, _, _, _, _}) ->
    type_try_case_catch_after;
return_type_clause(_) ->
    type_undef.

-spec replace(ast(),
              Fun :: fun((ast()) -> ast())) ->
    ast().
%%--------------------------------------------------------------------
%% @equiv   replace(AST, Fun, true)
%% @end
%%--------------------------------------------------------------------
replace(AST, Fun) ->
    replace(AST, Fun, true).

-spec replace(ast(),
              Fun :: fun((ast()) -> ast()),
              Log :: true|false) ->
    ast().
%%--------------------------------------------------------------------
%% @doc     Replaces every subtree in the `AST' with result of
%%          applying `Fun' to subtree. If `Log' is `true' then
%%          every replacement is logged.
%% @end
%%--------------------------------------------------------------------
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

-spec replace_fold(
            ast(),
            Fun :: fun((ast(), Acc :: term()) -> {ast(), ResAcc :: term()}),
            InitAcc :: term(),
            Res :: [erl_syntax:syntaxTree()]) ->
    {ast(), ResAcc :: term()}.

replace_fold([Tree | Tail], Fun, InitAcc, Res) ->
    {ResTree, NewAcc} = replace_fold(Tree, Fun, InitAcc),
    replace_fold(Tail, Fun, NewAcc, [ResTree | Res]);
replace_fold([], _Fun, InitAcc, Res) ->
    {lists:reverse(Res), InitAcc}.

-spec replace_fold(
            ast(),
            Fun :: fun((ast(), Acc :: term()) -> {ast(), ResAcc :: term()}),
            InitAcc :: term()) ->
        {ast(), ResAcc :: term()}.
%%--------------------------------------------------------------------
%% @doc     Same as `replace(AST, Fun)', but takes initiall accumulator
%%          `InitAcc' and folds `AST' to `ResAcc'.
%% @end
%%--------------------------------------------------------------------
replace_fold(AST, Fun, InitAcc) when is_list(AST) ->
    replace_fold(AST, Fun, InitAcc, []);
replace_fold(Tree, Fun, InitAcc) ->
   {AST, Acc} = erl_syntax_lib:mapfold(
        fun(T, Acc) ->
            Tr = erl_syntax:revert(T),
            {ResTr, ResAcc} = Fun(Tr, Acc),
            log_replace(Tr, ResTr),
            {ResTr, ResAcc}
        end,
        InitAcc,
        Tree),
    {erl_syntax:revert(AST), Acc}.

-spec replace_first(
            ast(),
            Fun :: fun((ast()) -> ast())) ->
    ast().
%%--------------------------------------------------------------------
%% @doc     Replaces first subtree in the `AST' with result of
%%          applying `Fun' to subtree.
%% @end
%%--------------------------------------------------------------------
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

-spec log_replace(ast(), ast()) -> ok.

log_replace(Tree, Tree) -> ok;
log_replace(Tree, Res) ->
    ?PT_DBG("pt <<<<<<~n~ts~n============~n~ts~npt >>>>>>~n ", [
        case ast2str(Tree) of
            {ok, String1} -> String1;
            {error, E1} ->
                throw(?mk_error({ast2str, E1}))
        end,
        case ast2str(Res) of
            {ok, String2} -> String2;
            {error, E2} ->
                throw(?mk_error({ast2str, E2}))
        end
    ]),
    ok.

-spec replace_local_call(
            ast(),
            FunctionName :: atom(),
            Callback :: fun( (ast(), Params :: term()) -> ast()),
            CallbackParams :: term()) ->
    ast().
%%--------------------------------------------------------------------
%% @doc     Replaces call of `FunctionName' in the `AST' with result
%%          of applying `Callback' to `FunctionName' AST and
%%          `CallbackParams'.
%% @end
%%--------------------------------------------------------------------
replace_local_call(AST, FunctionName, Callback, CallbackParams) when is_list(AST)->
    erl_syntax:revert([replace_local_call(Tree, FunctionName, Callback, CallbackParams) || Tree <- AST]);

replace_local_call(AST, FunctionName, Callback, CallbackParams) ->
    Res = erl_syntax_lib:map(
        fun (Tree) ->
            RevertedTree = erl_syntax:revert(Tree),
            case RevertedTree of
                {call, _, {atom, _, FunctionName}, _} ->
                    NewTr = Callback(RevertedTree, CallbackParams),
                    log_replace(RevertedTree, NewTr),
                    erl_syntax:revert(NewTr);
                _ ->
                    Tree
            end
        end,
        AST
    ),
    erl_syntax:revert(Res).

-spec replace_remote_call(
            ast(),
            ModuleName :: atom(),
            FunctionName :: atom(),
            Callback :: fun( (ast(), Params :: term()) -> ast()),
            CallbackParams :: term()) ->
    ast().
%%-------------------------------------------------------------------
%% @doc     Replaces call of `ModuleName:FunctionName'
%%          in the `AST' with result of applying `Callback' to
%%          `ModuleName:FunctionName' AST and `CallbackParams'.
%% @end
%%-------------------------------------------------------------------
replace_remote_call(AST, ModuleName, FunctionName, Callback, CallbackParams) when is_list(AST) ->
    erl_syntax:revert([ replace_remote_call(Tree, ModuleName, FunctionName, Callback, CallbackParams) || Tree <- AST]);

replace_remote_call(AST, ModuleName, FunctionName, Callback, CallbackParams) ->
    Res = erl_syntax_lib:map(
        fun (Tree) ->
            RevertedTree = erl_syntax:revert(Tree),
            case RevertedTree of
                {call, _, {remote, _, {atom, _, ModuleName}, {atom, _, FunctionName}}, _} ->
                    NewTr = erl_syntax:revert(Callback(RevertedTree, CallbackParams)),
                    log_replace(RevertedTree, NewTr),
                    NewTr;
                _ ->
                    Tree
            end
        end,
        AST
    ),
    erl_syntax:revert(Res).

-spec abstract(term(), line()) ->
    ast().
%%--------------------------------------------------------------------
%% @throws  {error, {Module, {File, Line}, {bad_term, Term, Error},
%%            Callstack}}
%% @doc     Converts `Term' to AST. `Line' will be asigned to each
%%          node of the abstract form.
%% @end
%%--------------------------------------------------------------------
abstract(Term, Line) ->
    Res = try
            erl_parse:abstract(Term)
          catch
            _:E ->
                throw(?mk_error({bad_term, Term, E}))
          end,
    insert_lines(Res, Line).

-spec insert_lines(ast(), line()) ->
    ast().
%%--------------------------------------------------------------------
%% @doc     Replaces line number in each node of the `AST' with
%%          `Line'.
%% @end
%%--------------------------------------------------------------------
insert_lines(ListAST, Line) when is_list(ListAST) ->
    erl_syntax:revert([ insert_lines(T, Line) || T <- ListAST]);
insert_lines(AST, Line) ->
    AST1 = erl_syntax_lib:map(
        fun (T) ->
            case erl_syntax:revert(T) of
                {Atom, N, P}  when is_atom(Atom) and is_integer(N) -> {Atom, Line, P};
                {Atom, N, P1, P2} when is_atom(Atom) and is_integer(N)  -> {Atom, Line, P1, P2};
                {Atom, N, P1, P2, P3} when is_atom(Atom) and is_integer(N) -> {Atom, Line, P1, P2, P3};
                {nil, N} when is_integer(N) -> {nil, Line};
                Tr -> Tr
            end
        end,
        AST
    ),
    erl_syntax:revert(AST1).

-spec get_function_ast(ast(), atom(), arity()) -> ast().
%%--------------------------------------------------------------------
%% @throws  {bad_param, AST} |
%%          {parse_error, {Line, Module,
%%                          {many_func, FunctionName, Arity}}}
%%
%% @doc     Returns AST for function `FunctionName' from the `AST'.
%% @end
%%--------------------------------------------------------------------
get_function_ast(AST, FunctionName, Arity) when is_list(AST)->
    FunList = lists:flatten([erl_syntax_lib:fold(
        fun(FunctionAst, Acc) ->
            case erl_syntax:revert(FunctionAst) of
                {function, _, FunctionName, Arity, _} -> [erl_syntax:revert(FunctionAst) | Acc];
                _ -> Acc
            end
        end,
        [],
        ASTEl
    ) || ASTEl <- AST]),

    case FunList of
        [] -> {error, not_found};
        [Element] -> {ok, Element};
        [ {function, Line, _, _, _} | _] ->
            throw(?mk_parse_error(Line, {many_func, FunctionName, Arity}))
    end;

get_function_ast(AST, _, _) ->
    throw(?mk_error({bad_param, AST})).

-spec replace_function_clause_code(ast(), atom(), arity(), ast(), ast(), ast()) -> ast().
%%--------------------------------------------------------------------
%% @doc     Finds function `FunctionName' with `Arity', `Params' and
%%          `Guards' in the `AST' and replaces its body with `Code'.
%% @end
%%--------------------------------------------------------------------
% replace
% FunctionName(Params) when Guards -> ...
% with
% FunctionName(Params) when Guards -> Code.
replace_function_clause_code(AST, FunctionName, Arity, Params, Guards, Code) ->
    pt_supp:replace(AST,
        fun (T) ->
            case T of
                {function, Line, FunctionName, Arity, Clauses} ->
                    {function, Line, FunctionName, Arity, lists:map(
                       fun (Clause = {clause, CLine, CParams, CGuards, _}) ->
                            A = pt_supp:insert_lines(CParams, 0),
                            B = pt_supp:insert_lines(Params, 0),
                            C = pt_supp:insert_lines(CGuards, 0),
                            D = pt_supp:insert_lines(Guards, 0),
                            if (A =:= B) and (C =:= D) ->
                                {clause, CLine, Params, Guards, Code};
                               true -> Clause
                            end
                        end,
                        Clauses)};
               _ -> T
            end
        end
    ).

-spec str2ast(string(), line()) -> {ok, ast()} | {error, term()}.
%%--------------------------------------------------------------------
%% @doc     Builds AST for the code in `String'. `Line' will be
%%          assigned to each node of the resulting AST.
%% @end
%%--------------------------------------------------------------------
-define(REMATCH(RE), pt_eval(erlang:element(2, re:compile(RE)))).
-define(REMATCH(RE, OPT), pt_eval(erlang:element(2, re:compile(RE, OPT)))).

str2ast(String, Line) ->
    try
        ParseSimple = fun(Str) ->
                        case re:run(Str, ?REMATCH(".*\\.\\s*$"), [{capture, [], list}]) of
                            match ->
                                case erl_scan:string(Str, Line) of
                                    {ok, Tokens, _} ->
                                        case erl_parse:parse_form(Tokens) of
                                            {ok, Abs} -> {ok, [Abs]};
                                            {error, ParseFormError} ->
                                                case erl_parse:parse_exprs(Tokens) of
                                                    {ok, List} -> {ok, List};
                                                    {error, ParseExprsError} ->
                                                        {error, {parse_error, ParseExprsError, ParseFormError}}
                                                end
                                        end;
                                    {error, ScanErrorInfo, _ScanEndLocation} ->
                                        {error, {scan_error, ScanErrorInfo}}
                                end;
                            nomatch ->
                                {error, miss_dot}
                        end
                     end,
        ProcessDotVars =
            fun(Str) ->
                Str0 = [$\s | Str],
                Str1 = re:replace(Str0, ?REMATCH("receive\\s*\\.\\.\\.(\\S*)\\.\\.\\.\\s*after", [unicode]), "receive '__PT_CLAUSE_DOT_VAR_REPLACE' -> \\1 after", [global, {return, list}]),
                Str2 = re:replace(Str1, ?REMATCH("receive\\s*\\.\\.\\.(\\S*)\\.\\.\\.\\s*end", [unicode]), "receive '__PT_CLAUSE_DOT_VAR_REPLACE' -> \\1 end", [global, {return, list}]),
                Str3 = re:replace(Str2, ?REMATCH("case(.*)of\\s*\\.\\.\\.(\\S*)\\.\\.\\.\\s*end", [unicode]), "case \\1 of '__PT_CLAUSE_DOT_VAR_REPLACE' -> \\2 end", [global, {return, list}]),
                Str4 = re:replace(Str3, ?REMATCH("\\#([^\\.]+)\\{(.*)\\.\\.\\.(\\S+)\\.\\.\\.(\\s*)\\}", [unicode]), "\\#\\1\\{\\2'__PT_RECORDFIELD_DOT_VAR_REPLACE' = \\3\\4\\}", [global, {return, list}]),

                Str5 = re:replace(Str4, ?REMATCH("(\\S+)/(\\S+)\\s*\\[\\.\\.\\.(\\S+)\\.\\.\\.\\]", [unicode]), "\\1('__PT_FUNCTION_DOT_VAR_REPLACE') -> \\3; \\1('__PT_FUNCTION_DOT_VAR_REPLACE_ARITY') -> \\2", [global, {return, list}]),
                Str6 = re:replace(Str5, ?REMATCH("(\\S+)\\s*\\[\\.\\.\\.(\\S+)\\.\\.\\.\\]", [unicode]), "\\1('__PT_CLAUSE_DOT_VAR_REPLACE') -> \\2 ", [global, {return, list}]),
                Str7 = re:replace(Str6, ?REMATCH("\\s*\\.\\.\\.(\\S*)\\.\\.\\.\\s*", [unicode]), "{pt_consvar, \\1}", [global, {return, list}]),
                Str8 = re:replace(Str7, ?REMATCH("([^\\'\\\\])(\\$\\w+)", [unicode]), "\\1'\\2'", [global, {return, list}]),
                Str9 = re:replace(Str8, ?REMATCH("([^\\'\\\\])(\\@\\w+)", [unicode]), "\\1'\\2'", [global, {return, list}]),

                Str10 = re:replace(Str9, ?REMATCH("fun\\s+([^\\/\\:]+\\:)?\\'([^\\/]+)\\'/\\'(\\$\\w+)\\'", [unicode]), "fun \\1'__PT_FUN_NAME_AND_ARITY_\\2__PT_SEPARATOR__\\3'/0", [global, {return, list}]),
                Str11 = re:replace(Str10, ?REMATCH("fun\\s+([^\\/\\:]+\\:)?\\'([^\\/]+)\\'/\\'(\\@\\w+)\\'", [unicode]), "fun \\1'__PT_FUN_NAME_AND_ARITY_\\2__PT_SEPARATOR__\\3'/0", [global, {return, list}]),
                Str12 = re:replace(Str11, ?REMATCH("fun\\s+([^\\/\\:]+\\:)?([^\\/]+)/\\'(\\$\\w+)\\'", [unicode]), "fun \\1'__PT_FUN_NAME_AND_ARITY_\\2__PT_SEPARATOR__\\3'/0", [global, {return, list}]),
                Str13 = re:replace(Str12, ?REMATCH("fun\\s+([^\\/\\:]+\\:)?([^\\/]+)/\\'(\\@\\w+)\\'", [unicode]), "fun \\1'__PT_FUN_NAME_AND_ARITY_\\2__PT_SEPARATOR__\\3'/0", [global, {return, list}]),
                Str13
            end,

        ParseParams =   fun(Str) ->
                            case Str of
                                [] -> {ok, []};
                                _ -> ParseSimple(Str ++ ".")
                            end
                        end,

        ParseExprs =    fun(Str) ->
                            case str2ast(Str ++ ".", Line) of
                                {ok, _} = S2aBRes -> S2aBRes;
                                Error -> Error
                            end
                        end,

        String0 = re:replace(String, ?REMATCH("\\n"), "", [global, {return, list}]),
        String1 = ProcessDotVars(String0),
        % TODO: add guards support!!!
        case re:run(String1, ?REMATCH("^\\s*\\(\\s*(?<PARAMS>[^\\(\\)]*)\\)\\s*(when\\s*(?<GUARDS>.+))?\\s*->\\s*(?<BOBY>.+)\\.\\s*$"), [{capture, ['PARAMS', 'GUARDS', 'BOBY'], list}]) of
            {match, [Params, Guards, Body]} ->
                ParamsRes = ParseParams(Params),
                BodyRes = ParseExprs(Body),

                ListOfGuards = string:tokens(string:strip(Guards), ";"),
                {ListOfGuardsRes, GuardsErrors} = lists:mapfoldl(
                    fun (El, Acc) ->
                        case ParseSimple(El ++ ".") of
                            {ok, R} -> {R, Acc};
                            {error, R} -> {error, [R | Acc]}
                        end
                    end,
                    [],
                    ListOfGuards),

                ListOfGuardsRes2 = case ListOfGuardsRes of
                                    [[{tuple, _ ,[{atom, _ ,pt_consvar},{atom, _, _}]}] = VarName] -> VarName;
                                    _ -> ListOfGuardsRes
                                  end,

                case {ParamsRes, BodyRes, GuardsErrors} of
                    {{ok, ListOfParamsAST}, {ok, BodyAST}, []} ->
                       {ok, [{clause, Line, ListOfParamsAST, ListOfGuardsRes2, BodyAST}]};
                    {_, _, [_ | _]} -> {error, GuardsErrors};
                    {{ok, _}, {error, Error2}, _} -> {error, Error2};
                    {{error, Error1}, {ok, _}, _} -> {error, Error1};
                    {{error, Error1}, {error, Error2}, _} -> {error, {Error1, Error2}}
                end;
            nomatch ->
                ParseSimple(String1)
        end

    catch
        _C:_E_ ->
            {error, badformat}
    end.

-spec format_str2ast_error(string(), term()) -> string().
%%--------------------------------------------------------------------
%% @doc     Returns text representation of `str2ast(Str)' parsing
%%          error in accordance with `Reason'.
%% @end
%%--------------------------------------------------------------------
format_str2ast_error(Str, Reason) ->
    case Reason of
        {parse_error, ParseExprsError, ParseFormError} ->
            io_lib:format("error when parsing string \"~s\"~nparse_form: ~s~nparse_exprs: ~s", [Str, format_errors(ParseFormError), format_errors(ParseExprsError)]);
        {scan_error, ScanErrorInfo} ->
            io_lib:format("error when parsing string \"~s\":~n ~s", [Str, format_errors(ScanErrorInfo)]);
        miss_dot ->
            io_lib:format("forget dot at the end of string: \"~s\"", [Str]);
        badformat ->
            io_lib:format("bad format of str: ~s", [Str]);
        Unknown ->
            io_lib:format("unknown error ~p when parsing str: ~s", [Unknown, Str])
    end.

-spec ast2str(ast()) -> {ok, string()} | {error, term()}.
%%--------------------------------------------------------------------
%% @doc     Converts the `AST' to its text representation.
%% @end
%%--------------------------------------------------------------------
ast2str(P) ->
    try
        {ok, ast2str2(P)}
    catch
        _:E -> {error, E}
    end.

-spec ast2str2(ast()) -> string().

ast2str2([T | Tail]) ->
    Add = case {T, Tail} of
            {Tuple, _} when is_tuple(Tuple) andalso element(1, Tuple) =:= attribute ->
                io_lib:format("~n", []);
            {{function, _, _, _, _}, _} ->
                io_lib:format("~n~n", []);
            {_, []} ->
                "";
            {_, _} ->
                ", "
         end,

    ast2str2(T) ++ Add ++ ast2str2(Tail);

ast2str2([]) ->
    "";
ast2str2(Tree) ->
    try
        erl_prettypr:format(Tree)
    catch
        _:E -> throw({E, Tree})
    end.

-spec is_var_name(string()) -> true | false.
%%--------------------------------------------------------------------
%% @doc     Checks if `Str' represents legal erlang variable.
%% @end
%%--------------------------------------------------------------------
is_var_name(Str) ->
    case catch erl_scan:string(Str) of
        {ok, [{var, _, _}], _} -> true;
        _ -> false
    end.

-spec list_map(fun ( (ast()) -> ast() ),
               ast()) ->
    ast().
%%--------------------------------------------------------------------
%% @doc     Produces new AST by applying `Fun' to every element in the
%%          `ListAST'.
%% @end
%%--------------------------------------------------------------------
list_map(Fun, ListAST) ->
    list_reverse(list_map(Fun, ListAST, {nil, 0})).

-spec list_map(fun ( (ast()) -> ast() ),
               ast(),
               ast()) ->
    ast().

list_map(Fun, {cons, Line, Element, Tail}, {nil, _}) ->
    list_map(Fun, Tail, {cons, Line, Fun(Element), {nil, Line}});
list_map(Fun, {cons, Line, Element, Tail}, {cons, _, E2, T2}) ->
    list_map(Fun, Tail, {cons, Line, Fun(Element), {cons, Line, E2, T2}});
list_map(_, {nil, Line}, {nil, _}) ->
    {nil, Line};
list_map(_, {nil, Line}, {cons, _, E2, T2}) ->
    {cons, Line, E2, T2};
list_map(_, R, _) ->
    throw(?mk_error({bad_param, R})).

-spec list_map_fold(fun ( (ast(), term()) -> {ast(), term()} ),
                    term(),
                    ast()) ->
    {ast(), term()}.
%%--------------------------------------------------------------------
%% @doc     Combines `list_map/2' and `list_fold/3' into one function.
%% @end
%%--------------------------------------------------------------------
list_map_fold(Fun, InitAcc, ListAST) ->
    {L, A} = list_map_fold(Fun, InitAcc, ListAST, {nil, 0}),
    {list_reverse(L), A}.




-spec list_map_fold(fun ( (ast(), term()) -> {ast(), term()} ),
                    term(),
                    ast(),
                    ast()) ->
    {ast(), term()}.

list_map_fold(Fun, InitAcc, {cons, Line, Element, Tail}, {nil, _}) ->
    {L, A} = Fun(Element, InitAcc),
    list_map_fold(Fun, A, Tail, {cons, Line, L, {nil, Line}});
list_map_fold(Fun, InitAcc, {cons, Line, Element, Tail}, {cons, _, E2, T2}) ->
    {L, A} = Fun(Element, InitAcc),
    list_map_fold(Fun, A, Tail, {cons, Line, L, {cons, Line, E2, T2}});
list_map_fold(_, InitAcc, {nil, Line}, {nil, _}) ->
    {{nil, Line}, InitAcc};
list_map_fold(_, InitAcc, {nil, Line}, {cons, _, E2, T2}) ->
    {{cons, Line, E2, T2}, InitAcc};
list_map_fold(_, _, R, _) ->
    throw(?mk_error({bad_param, R})).

-spec list_reverse(ast()) -> ast().
%%--------------------------------------------------------------------
%% @doc     Returns AST with `ListAST' elements in reversed order.
%% @end
%%--------------------------------------------------------------------
list_reverse(ListAST) ->
    list_reverse(ListAST, {nil, 0}).

-spec list_reverse(ast(), ast()) -> ast().

list_reverse({cons, Line, El, Tail}, {nil, _}) ->
    list_reverse(Tail, {cons, Line, El, {nil, Line}});
list_reverse({cons, Line, El, Tail}, {cons, _, E2, T2}) ->
    list_reverse(Tail, {cons, Line, El, {cons, Line, E2, T2} });
list_reverse({nil, Line}, {nil, _}) ->
    {nil, Line};
list_reverse({nil, Line}, {cons, _, E2, T2}) ->
    {cons, Line, E2, T2};
list_reverse(R, _) ->
    throw(?mk_error({bad_param, R})).

-spec list_fold(fun( (ast(), line(), Acc::term()) ->  term()),
                term(),
                ast()) ->
    term().
%%--------------------------------------------------------------------
%% @throws  {error, {Module, {File, Line}, {bad_param, R}, Callstack}}
%%
%% @doc     Calls `Fun' on successive subtree of `AST', starting with
%%          `Acc == InitAcc'. `Fun' must return a new accumulator.
%%          The function returns the final value of accumulator.
%% @end
%%--------------------------------------------------------------------
list_fold(_Fun, InitAcc, {nil, _}) ->
    InitAcc;
list_fold(Fun, InitAcc, {cons, L, Element, Tail}) ->
    list_fold(Fun, Fun(Element, L, InitAcc), Tail);
list_fold(_, _, R) ->
    throw(?mk_error({bad_param, R})).

-spec list_foldr(fun( (ast(), line(), term()) -> term()),
                term(),
                ast()) ->
    ast().
%%--------------------------------------------------------------------
%% @throws  {error, {Module, {File, Line}, {bad_param, R}, Callstack}}
%%
%% @doc     Like `list_fold/3', but the `ListAST' is traversed from
%%          right to left.
%% @end
%%--------------------------------------------------------------------
list_foldr(Fun, InitAcc, ListAST) ->
    list_fold(Fun, InitAcc, list_reverse(ListAST)).

-spec list_concat(ast(), ast()) ->
    ast().
%%--------------------------------------------------------------------
%% @doc     Concatenates `List1' and `List2'.
%% @end
%%--------------------------------------------------------------------
list_concat(List1, List2) ->
    SL = element(2, List1),
    Res = list_foldr(
            fun
                (E, L, {nil, _}) -> {cons, L, E, {nil, L}};
                (E, L, {cons, _, E1, T1}) -> {cons, L, E, {cons, L, E1, T1}};
                (E, L, El) when El =:= List2 -> {cons, L, E, El};
                (_, _, R) -> throw(?mk_error({bad_param, R}))
            end,
            List2,
            List1),
    insert_lines(Res, SL).

-spec list_length(ListAST::ast()) ->
    integer().
%%--------------------------------------------------------------------
%% @doc     Returns number of elements in the `ListAST'.
%% @end
%%--------------------------------------------------------------------
list_length(List) ->
    list_length(List, 0).

-spec list_length(ast(), integer()) ->
    integer().

list_length({cons, _, _, Tail}, N) ->
    list_length(Tail, N + 1);
list_length({nil, _}, N) -> N.

-spec create_clear_ast(atom()) -> ast().
%%--------------------------------------------------------------------
%% @doc     Creates AST with `ModuleName' and empty export attribute.
%% @end
%%--------------------------------------------------------------------
create_clear_ast(ModuleName) when is_atom(ModuleName) ->
    [
     {attribute, 1, module, ModuleName},
     {attribute, 2, export, []},
     {eof, 3}
    ];

create_clear_ast(P) ->
    throw(?mk_error({bad_param, P})).

-spec compile_to_beam(ast(), string()) -> ok.
%%--------------------------------------------------------------------
%% @throws  {error, {Moudle, {File, Line},
%%                    {write_error, BeamFileName, Reason}, Callstack}}
%%
%% @doc     Compiles `AST' to .beam file. File will be saved to
%%          `BinDir'.
%% @end
%%--------------------------------------------------------------------
compile_to_beam(AST, BinDir) ->
    {ok, Module, Bin} = compile:forms(AST),

    BeamFileName = filename:join([BinDir, atom_to_list(Module) ++ ".beam"]),

    case file:write_file(BeamFileName, Bin) of
        ok ->
            ok;
        {error, Reason} ->
            throw(?mk_error({write_error, BeamFileName, Reason}))
    end.

-spec compile(ast()) -> {ModuleName::atom(), binary()}.
%%--------------------------------------------------------------------
%% @throws  {error, {Moudle, {File, Line},
%%                    {'compile-error', Error, Warnings}, Callstack}}
%%
%% @doc     Compiles the `AST' to binary.
%% @end
%%--------------------------------------------------------------------
compile(AST) ->              %debug_info
    Opts = case os:getenv("DIALYZER_CHECK_PT_OPTIONS") of
        "ok"  -> [encrypt_debug_info, return];
        _     -> [return]
    end,
    case compile:forms(AST, Opts) of
        {ok, M, B, _W} ->
            {M, B};
        {error, Error, Warnings} ->
            throw(?mk_error({'compile-error', Error, Warnings}))
    end.

-spec compile_and_load(ast()) -> ok | {error, term()}.
%%--------------------------------------------------------------------
%% @doc     Compiles the `AST' and loads compiled module.
%% @end
%%--------------------------------------------------------------------
compile_and_load(AST) ->
    ModuleName = pt_lib:get_module_name(AST),
    case compile:forms(AST, [binary, return_errors]) of
        {ok, Module, Binary} ->
            case code:soft_purge(Module) of
                true ->
                    case code:load_binary(Module, atom_to_list(Module) ++ ".erl", Binary) of
                        {module, Module} ->
                            ok;
                        {error, Cause} -> {error, {cant_load, Module, Cause}}
                    end;
                false ->
                    {error, soft_purge_failed}
            end;
        error -> {error, {compile_error, ModuleName}};
        {error, Errors, Warnings} ->
            {error, {compile_error, ModuleName, Errors, Warnings}}
    end.

-spec is_term(ast()) -> true | false.
%%--------------------------------------------------------------------
%% @doc     Checks if the `AST' represents a term.
%% @end
%%--------------------------------------------------------------------
is_term(AST) when is_list(AST) -> false;
is_term(AST) ->
    erl_syntax:is_literal(AST).

-spec is_term_or_var(ast()) -> true | false.
%%--------------------------------------------------------------------
%% @doc     Checks if the `AST' represents term or variable.
%% @end
%%--------------------------------------------------------------------
is_term_or_var(AST) when is_list(AST) -> false;
is_term_or_var(AST) ->
    AST1 = pt_supp:replace(AST,
        fun
            ({var, Line, Var}) when is_atom(Var) -> {atom, Line, Var};
            (X) -> X
        end, false),
    is_term(AST1).

-spec format_errors([{File::string(), [{line(), ParseModule::atom(), ErrorDescriptor::term()}]}] |
    {line(), ParseModule::atom(), ErrorDescriptor::term()}) -> string().
%%--------------------------------------------------------------------
%% @doc     Returns text representation of list of errors.
%% @end
%%--------------------------------------------------------------------
format_errors(List) when is_list(List) ->
    format_errors(List, "Error");
format_errors(Error = {_ErrorLine, _ParseModule, _ErrorDescriptor}) ->
    format_error("", Error, "Error").

-spec format_warnings([{File::string(), [{line(), ParseModule::atom(), ErrorDescriptor::term()}]}] |
    {line(), ParseModule::atom(), ErrorDescriptor::term()}) -> string().
%%--------------------------------------------------------------------
%% @doc     Retruns text representation of list of warnings.
%% @end
%%--------------------------------------------------------------------
format_warnings(List) when is_list(List) ->
    format_errors(List, "Warning");
format_warnings(Error = {_ErrorLine, _ParseModule, _ErrorDescriptor}) ->
    format_error("", Error, "Warning").

-spec format_errors([{File::string(), [{line(), ParseModule::atom(), ErrorDescriptor::term()}]}],
                    string()) ->
        string().

format_errors([{FileName, [Error | Tail]} | ErrorsTail], Prefix) ->
    format_error(FileName, Error, Prefix) ++ io_lib:format("~n", []) ++ format_errors([{FileName, Tail} | ErrorsTail], Prefix);
format_errors([{_, []} | ErrorsTail], Prefix) ->
    format_errors(ErrorsTail, Prefix);
format_errors([], _) ->
    "".

-spec format_error(string(), {line(), ParseModule::atom(), ErrorDescriptor::term()}, string()) -> string().
format_error(FileName, _ErrorInfo = {ErrorLine, ParseModule, ErrorDescriptor}, Prefix) ->
    io_lib:format("~s:~p: ~s: ~s", [FileName, ErrorLine, Prefix, call_format_error(ParseModule, ErrorDescriptor)]).

call_format_error(Module, Param) ->
    try
        Module:format_error(Param)
    catch
        _:_ ->
            io_lib:format("Cant format_error cause function ~p:format_error/1 is undefined~n~p", [Module, Param])
    end.

-spec string2atom(String::string()) -> atom().
%%--------------------------------------------------------------------
%% @doc     Converts `String' to atom.
%% @end
%%--------------------------------------------------------------------
string2atom(List) ->
    list_to_atom(List).

-spec mk_atom(string(), term()) -> atom().
%%--------------------------------------------------------------------
%% @doc     Makes atom from `String' and `Par'.
%% @end
%%--------------------------------------------------------------------
mk_atom(String, Par) ->
    NewStr = mk_new_str(String, Par),
    pt_supp:string2atom(NewStr).

-spec mk_new_str(string(), term()) -> string().

mk_new_str(String, N) when is_integer(N) ->
    String ++ integer_to_list(N);
mk_new_str(String, A) when is_atom(A) ->
    String ++ atom_to_list(A);
mk_new_str(String, S) when is_list(S) ->
    String ++ S.

-spec format_error(Error::term()) -> string().
%%--------------------------------------------------------------------
%% @doc     Returns text representation of `Error'.
%% @end
%%--------------------------------------------------------------------
format_error({many_func, FunctionName, Arity}) ->
    io_lib:format("More than one function with name ~p/~p", [FunctionName, Arity]);
format_error({unbound_var, Vars}) ->
    io_lib:format("Variables ~w are unbound", [Vars]);
format_error({ast2str, Reason}) ->
    io_lib:format("Cant convert ast to string cause: ~p", [Reason]);
format_error({bad_term, Term, E}) ->
    io_lib:format("~p is not a valid term, cause: ~p", [Term, E]);
format_error({str2ast, Reason, Str}) ->
    io_lib:format("Cant convert string to ast cause: " ++ pt_supp:format_str2ast_error(Str, Reason), []);
format_error({bad_param, L}) ->
    io_lib:format("Bad param: ~p", [L]);
format_error({undef, P}) ->
    io_lib:format("~p is undefined", [P]);
format_error({fun_already_exists, Name, Arity}) ->
    io_lib:format("Function ~p/~p already exists", [Name, Arity]);
format_error({unhandled_replace_param, Call}) ->
    io_lib:format("Unhandled param in replace_function: ~p", [Call]);
format_error({get_module_name, not_found}) ->
    io_lib:format("Attribute \"module\" is not found in AST", []);
format_error({get_file_name, not_found}) ->
    io_lib:format("Attribute \"file\" is not found in AST", []);
format_error({remove_subtree, not_found, Tree}) ->
    io_lib:format("Subtree is not found in AST: ~p", [Tree]);
format_error(Unknown) ->
    io_lib:format("Unknown error: ~p", [Unknown]).

-spec print_error(ast(), Error :: term()) -> term().
%%--------------------------------------------------------------------
%% @equiv   print_error(AST, Error, fun io:format/2)
%% @end
%%--------------------------------------------------------------------
print_error(AST, Error) ->
    print_error(AST, Error, fun io:format/2).

-spec print_error(ast(),
                  Error :: term(),
                  PrintFun :: fun((Format :: string(), Data :: [term()]) -> term())) ->
                         term().
%%--------------------------------------------------------------------
%% @doc     Prints `Error' for the `AST' using `PrintFun' for printing
%% @end
%%--------------------------------------------------------------------
print_error(AST, Error, PrintFun) ->
    case Error of
        {parse_error, ErrorInfo} ->
            FileName = case catch pt_supp:get_file_name(AST) of
                            FName when is_list(FName) -> FName;
                            _ -> ""
                       end,
            PrintFun(pt_supp:format_errors([{FileName, [ErrorInfo]}]) ++ "~n", []);
        {error, {Module, {Filename, Line},  ErrorDescriptor, {callstack, CallStack}}} ->
            PrintFun("~s:~p: error: ~s~nCallStack ~p~n", [Filename, Line, call_format_error(Module,ErrorDescriptor), CallStack]);
        {internal_error, {Module, {Filename, Line}, ErrorDescriptor, {callstack, CallStack}}} ->
            PrintFun("~s:~p: internal_error: ~s~nCallStack ~p~n", [Filename, Line, call_format_error(Module,ErrorDescriptor), CallStack]);
        Unknown ->
            PrintFun("Unknown error: ~p~n", [Unknown])
    end.

-spec generate_errors(ast(), Errors :: list(), Res :: list()) ->
    Res :: list().
%%--------------------------------------------------------------------
%% @doc     Generates AST list for the `Errors' list and concatenates
%%          it with `Res'. ASTs include
%%          line numbers, module name and error descriptions.
%% @end
%%--------------------------------------------------------------------
generate_errors(_AST, [], Res) -> Res;
generate_errors(AST, [Error | Tail], Res) ->
    NewRes =
        case Error of
            {parse_error, {Line, _, _} = ErrorInfo} ->
                FileName = case catch pt_supp:get_file_name(AST) of
                                FName when is_list(FName) -> FName;
                                _ -> ""
                           end,
                [{attribute, 0, file, {FileName, Line}},{error, ErrorInfo} | Res];

            {error, {Module, {Filename, Line},  ErrorDescriptor, {callstack, _CallStack}}} ->
                [{attribute, Line, file, {Filename, Line}},{error, {Line, Module, ErrorDescriptor}} | Res];

            {internal_error, {Module, {Filename, Line}, ErrorDescriptor, {callstack, _CallStack}}} ->
                [{attribute, Line, file, {Filename, Line}},{error, {Line, Module, ErrorDescriptor}} | Res];

            Unknown ->
                [{attribute, ?LINE, file, {?FILE, ?LINE}}, {error, {?LINE, ?MODULE, Unknown}} | Res]
        end,
    generate_errors(AST, Tail, NewRes).

concat_module_name([First | Atoms]) when is_list(Atoms) ->
    Name =
        lists:foldl(
            fun (A, Acc) ->
                Acc ++ "." ++ erlang:atom_to_list(A)
            end, erlang:atom_to_list(First), Atoms),

    erlang:list_to_atom(Name).
