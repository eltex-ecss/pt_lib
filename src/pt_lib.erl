%%%-------------------------------------------------------------------
%%% -*- coding: utf-8 -*-
%%% @author Timofey Barmin
%%% @copyright (C) 2015, Eltex, Novosibirsk, Russia
%%% @doc
%%%     Library interface module.
%%% @end
%%%-------------------------------------------------------------------
-module(pt_lib).

-include("pt_error_macro.hrl").
-include("pt_lib.hrl").
-include("pt_supp.hrl").
-include("pt_types.hrl").

-export([
         match/2, match/3,
         replace_module_name/2,
         replace/3, replace/2,
         replace_fold/3, replace_fold/4,
         replace_first/3, replace_first/2,
         get_file_name/1, get_module_name/1,
         add_function/2, add_local_function/2, get_function_ast/3,
         replace_function/2,
         get_compile_options/1, get_attribute_value/2,
         list_map/2, list_map_fold/3, list_fold/3, list_foldr/3, list_reverse/1, list_concat/2, list_length/1,
         is_function/1, is_fun/1, is_string/1, is_atom/1, is_variable/1, is_list/1, is_tuple/1, is_term/1, is_term_or_var/1,
         remove_function/2, remove_function/3, remove_subtree/2,
         str2ast/2, ast2str/1, abstract/2,
         parse_transform/2, format_error/1,
         create_clear_ast/1, compile/1, compile_to_beam/2, compile_and_load/1,
         set_module_name/2,
         set_attribute/3
        ]).

-spec parse_transform(ast(), [compile:option()]) -> ast().
%%--------------------------------------------------------------------
%% @doc     Parse transforms `AST' by calling pt functions passed by
%%          compile options of form `{pt_parser, {Modle, Function, Param}}'.
%% @end
%%--------------------------------------------------------------------
parse_transform(AST, Options) ->
    AST1 = lists:foldl(
        fun ({attribute, _, compile, {pt_parser, {Module, Function, Param}}}, Acc) ->
                ?PT_INFO("User transformation of module ~p: ~p:~p()", [pt_lib:get_module_name(AST), Module, Function]),
                Module:Function(Acc, Options, Param);
            (_, Acc) -> Acc
        end,
        AST,
        AST
    ),

    lists:foldl(
        fun ({pt_parser, {Module, Function, Param}}, Acc) ->
                ?PT_INFO("User transformation of module ~p: ~p:~p()", [pt_lib:get_module_name(AST), Module, Function]),
                Module:Function(Acc, Options, Param);
            (_, Acc) -> Acc
        end,
        AST1,
        Options
    ).

-spec match(AST::ast(), ASTPattern::term()) -> ast().
%%--------------------------------------------------------------------
%% @doc     Returns AST representing list with elements from the
%%          `ListAST' which matches pattern `ASTPattern'.
%% @end
%%--------------------------------------------------------------------
match(_AST, _ASTPattern) ->
    erlang:error(undef).

-spec match(AST::ast(), ASTPattern::term(), Value::ast()) -> ast().
%%--------------------------------------------------------------------
%% @doc     Replaces every subtree in the `AST' which matches
%%          `ASTPattern' with `Value'.
%% @end
%%--------------------------------------------------------------------
match(_AST, _Pattern, _Value) ->
    erlang:error(undef).

-spec replace_module_name(ast(), atom()) -> ast().
%%--------------------------------------------------------------------
%% @doc     Replaces module name in the `AST' with `ModuleName'.
%% @end
%%--------------------------------------------------------------------
replace_module_name(AST, ModuleName) ->
    ?MODULE:replace(AST, {attribute, Line, module,  _}, {attribute, Line, module, ModuleName}).

-spec replace(AST::ast(), ASTPattern::term(), Value::ast()) -> ast().
%%--------------------------------------------------------------------
%% @doc     Replaces every subtree in the `AST' which matches
%%          `ASTPattern' with `Value'.
%% @end
%%--------------------------------------------------------------------
replace(_AST, _Pattern, _Value) ->
    erlang:error(undef).

-spec replace_fold(AST::ast(),
                   {ASTPattern::term(), Acc::term()},
                   {Value::ast(), NewAcc::term()}, InitAcc::term()) ->
    ast().
%%--------------------------------------------------------------------
%% @doc     Replaces every subtree in the `AST' which matches pattern
%%          `ASTPattern'. For each matched subtree `Acc' is replaced by
%%          `NewAcc' starting with `InitAcc'.
%% @end
%%--------------------------------------------------------------------
replace_fold(_AST, {_Pattern, _Acc}, {_Value, _NewAcc}, _InitAcc) ->
    erlang:error(undef).

-spec replace_first(AST::ast(), ASTPattern::term(), Value::ast()) ->
    ast().
%%--------------------------------------------------------------------
%% @doc     Replaces first subtree in the `AST' which matches `ASTPattern'
%% @end
%%--------------------------------------------------------------------
replace_first(_AST, _Pattern, _Value) ->
    erlang:error(undef).

-spec replace(ast(), fun((ast()) -> ast())) -> ast().
%%--------------------------------------------------------------------
%% @doc     Replaces every subtree in the `AST' with result of
%%          applying `Fun' to subtree.
%% @end
%%--------------------------------------------------------------------
replace(AST, Fun) ->
    pt_supp:replace(AST, Fun).

-spec replace_fold(
            AST :: ast(),
            Fun :: fun((ast(), Acc :: term()) -> {ast(), ResAcc :: term()}),
            InitAcc :: term()) ->
        {ast(), ResAcc :: term()}.
%%--------------------------------------------------------------------
%% @doc     Same as `replace(AST, Fun)', but takes initiall accumulator
%%          `InitAcc' and folds `AST' to `ResAcc'.
%% @end
%%--------------------------------------------------------------------
replace_fold(AST, Fun, InitAcc) ->
    pt_supp:replace_fold(AST, Fun, InitAcc).

-spec replace_first(
            AST::ast(),
            Fun::fun((ast()) -> ast())) ->
    ast().
%%--------------------------------------------------------------------
%% @doc     Replaces first subtree in the `AST' with result of
%%          applying `Fun' to subtree.
%% @end
%%--------------------------------------------------------------------
replace_first(_AST, _Fun) ->
    erlang:error(unimplemented).

-spec get_module_name(ast()) ->
    ModuleName :: atom().
%%--------------------------------------------------------------------
%% @throws  {get_module_name, not_found}
%%
%% @doc     Returns module name for the `AST'.
%% @end
%%--------------------------------------------------------------------
get_module_name(AST) ->
    pt_supp:get_module_name(AST).

-spec set_module_name(ast(), ModuleName :: module()) -> ast().
%%--------------------------------------------------------------------
%% @doc     Sets module name `ModuleName' for the `AST'.
%% @end
%%--------------------------------------------------------------------
set_module_name(AST, ModuleName) ->
    pt_supp:set_module_name(AST, ModuleName).

-spec get_file_name(ast()) ->
    Filename :: string().
%%--------------------------------------------------------------------
%% @throws  {get_file_name, not_found}
%%
%% @doc     Returns module filename for the `AST'.
%% @end
%%--------------------------------------------------------------------
get_file_name(AST) ->
    pt_supp:get_file_name(AST).

-spec get_function_ast(ast(), atom(), arity()) -> ast().
%%--------------------------------------------------------------------
%% @throws  {bad_param, AST} |
%%          {parse_error, {Line, Module,
%%                          {many_func, FunctionName, Arity}}}
%%
%% @doc     Returns AST for function `FunctionName' from the `AST'.
%% @end
%%--------------------------------------------------------------------
get_function_ast(AST, FunctionName, Arity) ->
    pt_supp:get_function_ast(AST, FunctionName, Arity).

-spec get_compile_options(ast()) ->
    [Values :: term()].
%%--------------------------------------------------------------------
%% @doc     Returns compile options from the `AST'.
%% @end
%%--------------------------------------------------------------------
get_compile_options(AST) ->
    pt_supp:get_compile_options(AST).

%%--------------------------------------------------------------------
%% @doc     Returns `Attribute' values list from the `AST'.
%% @end
%%--------------------------------------------------------------------
get_attribute_value(Attribute, AST) ->
    pt_supp:get_attribute_value(Attribute, AST).

-spec set_attribute(ast(), Attribute :: atom(), Value :: term()) ->
    ast().
%%--------------------------------------------------------------------
%% @throws  {parse_error, {0, Module, {no_module_attribute, Res}}} |
%%          {parse_error, {0, Module, {no_attribute, Attribute, Res}}}
%%
%% @doc     Adds or replaces `Attribute' in the `AST' with `Value'.
%% @end
%%--------------------------------------------------------------------
set_attribute(AST, Attribute, Value) ->
    pt_supp:set_attribute(AST, Attribute, Value).

-spec ast2str(ast()) -> string().
%%--------------------------------------------------------------------
%% @throws  {error, {Module, {File, Line}}, {ast2str, Reason}, Callstack}
%%
%% @doc     Converts the `AST' to its text representation.
%% @end
%%--------------------------------------------------------------------
ast2str(AST) ->
    case pt_supp:ast2str(AST) of
        {ok, Str} -> Str;
        {error, Reason} -> throw(?mk_error({ast2str, Reason}))
    end.

-spec str2ast(string(), line()) -> ast().
%%--------------------------------------------------------------------
%% @throws  {error, {Module, {File, Line}}, {str2ast, Reason, Str}, Callstack}
%%
%% @doc     Builds AST for the code in `Str'. `Line' will be
%%          assigned to each node of the resulting AST.
%% @end
%%--------------------------------------------------------------------
str2ast(Str, Line) ->
    case pt_supp:str2ast(Str, Line) of
        {ok, AST} -> AST;
        {error, Reason} -> throw(?mk_error({str2ast, Reason, Str}))
    end.

-spec add_function(ast(), Fun::ast()) -> ast().
%%--------------------------------------------------------------------
%% @throws  {error, {Module, {File, Line}}, {bad_param, Fun}, Callstack} |
%%          {parse_error, {0, Module, {bad_param, AST}}} |
%%          {parse_error, {Line, Module, {fun_already_exits, Name, Arity}}}
%%
%% @doc     Same as `add_local_function(AST, Fun)', but exports added
%%          function.
%% @end
%%--------------------------------------------------------------------
add_function(AST, Fun = {function, _, Name, Arity, _}) ->
    AST1 = add_local_function(AST, Fun),

    % check that export attribute exists, create it else
    AST2 =
        case pt_lib:match(AST1, {attribute, _, export, _}) of
            [] ->
                lists:foldr(
                    fun
                        ({attribute, ML, module, _} = M, Acc) -> [M, {attribute, ML, export, []} | Acc];
                        (El, Acc) -> [ El | Acc]
                    end,
                    [],
                    AST1);
            _ ->
                AST1
        end,

    case lists:any(
            fun ({_, _, _, List}) ->
                lists:member({Name, Arity}, List)
            end,
            pt_lib:match(AST2, {attribute, _, export, _})) of

        false ->
            pt_lib:replace_first(AST2,
                {attribute, Line1, export, List},
                {attribute, Line1, export, [{Name, Arity} | List]});
        _ -> AST2
    end;

add_function(_AST, Fun) ->
    %?PT_ERROR("Bad format of Fun: ~p", [Fun]), AST.
    throw(?mk_error({bad_param, Fun})).

-spec replace_function(AST :: ast(), Fun :: ast()) -> ast().
%%--------------------------------------------------------------------
%% @throws  {error, {Module, {File, Line}}, {bad_param, Fun}, Callstack} |
%%          {error, {Module, {File, Line}}, {not_found, Fun}, Callstack} |
%%          {parse_error, {0, Module, {bad_param, AST}}} |
%%
%% @doc     Replace function on Fun in the AST.
%% @end
%%--------------------------------------------------------------------
replace_function(AST, Fun = {function, _Line, Name, Arity, Causes}) ->
    ReplaceFun =
        % В AST ранее нашли и заменили нашу функцию.
        fun (E, {ASTLocal, true}) ->
                {[E | ASTLocal], true};
            % В AST нашли нашу функцию.
            ({function, LineL, NameL, ArityL, _}, {ASTLocal, _}) when NameL == Name, ArityL == Arity ->
                {[{function, LineL, Name, Arity, Causes} | ASTLocal], true};
            (E, {ASTLocal, Replaced}) -> {[E | ASTLocal], Replaced}
        end,
    case lists:foldr(ReplaceFun, {[], false}, AST) of
        % Функцию заменили
        {AST1, true} ->
            AST1;
        _ ->
            throw(?mk_error({not_found, Fun}))
    end;

replace_function(_AST, Fun) ->
    throw(?mk_error({bad_param, Fun})).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec add_local_function(ast(), Fun::ast()) -> ast().
%%--------------------------------------------------------------------
%% @throws  {parse_error, {0, Module, {bad_param, AST}}} |
%%          {parse_error, {Line, Module, {fun_already_exits, Name, Arity}}} |
%%          {error, {Module, {File, Line}}, {bad_param, Fun}, Callstack}
%%
%% @doc     Adds local function AST `Fun' to `AST'.
%% @end
%%--------------------------------------------------------------------
add_local_function(AST, Fun = {function, LineFunction, Name, Arity, _}) ->
    case lists:keyfind(Name, 3, AST) of
        {function, L, Name, Arity, _} ->
            throw(?mk_parse_error(L, {fun_already_exists, Name, Arity}));
        _ -> ok
    end,

    case pt_lib:match(AST, {eof, _}) of
        [{eof, Line} = EOF] ->
            case LineFunction /= 0 andalso LineFunction < Line of
                true ->
                    ASTTmp = pt_lib:replace(AST, EOF, Fun);
                false ->
                    ASTTmp = pt_lib:replace(AST, EOF, pt_supp:insert_lines(Fun, Line))
            end,
            lists:append(ASTTmp, [{eof, Line}]);
        _ ->
            throw(?mk_parse_error(0, {bad_param, AST}))
    end;

add_local_function(_AST, Fun) ->
    throw(?mk_error({bad_param, Fun})).

-spec remove_function(ast(), atom(), arity()) -> ast().
%%--------------------------------------------------------------------
%% @doc     Removes function with `Name' and `Arity' from the `AST'.
%% @end
%%--------------------------------------------------------------------
remove_function(AST, Name, Arity) ->
    AST1 =
        lists:foldr(
            fun ({function, _, Name2, Arity2, _}, Acc) when Name2 == Name, Arity2 == Arity -> Acc;
                (E, Acc) -> [E|Acc]
            end, [], AST),

    AST2 =
        lists:map(fun ({attribute, Line1, export, List}) ->
                        NewList = lists:foldr(
                                    fun (X, Acc) ->
                                        case X of
                                            {Name, Arity} -> Acc;
                                            _ -> [X | Acc]
                                        end
                                    end, [], List),
                        {attribute, Line1, export, NewList};
                      (E) -> E
                  end, AST1),

    AST3 =
        lists:foldr(fun ({attribute, _, spec, {{Name2, Arity2}, _}}, Acc) when Name2 == Name, Arity2 == Arity -> Acc;
                        (E, Acc) -> [E|Acc]
                    end, [], AST2),

    AST3.


-spec remove_function(ast(), ast()) -> ast().
%%--------------------------------------------------------------------
%% @doc     Removes function with AST `Fun' from the `AST'.
%% @end
%%--------------------------------------------------------------------
remove_function(AST, Fun = {function, _, Name, Arity, _}) ->
    AST1 = remove_subtree(AST, Fun),
    AST2 =
        lists:map(fun ({attribute, Line1, export, List}) ->
                        NewList = lists:foldr(
                                    fun (X, Acc) ->
                                        case X of
                                            {Name, Arity} -> Acc;
                                            _ -> [X | Acc]
                                        end
                                    end, [], List),
                        {attribute, Line1, export, NewList};
                      (E) -> E
                  end, AST1),
    lists:foldr(fun ({attribute, _, spec, {{Name2, Arity2}, _}}, Acc) when Name2 == Name, Arity2 == Arity -> Acc;
                    (E, Acc) -> [E|Acc]
                end, [], AST2).

-spec remove_subtree(ast(), ast()) -> ast().
%%--------------------------------------------------------------------
%% @throws  {error, {Module, {File, Line}}, {bad_param, AST}, Callstack} |
%%          {error, {Module, {File, Line}}, {remove_subtree, not_found, Tree},
%%            Callstack}
%%
%% @doc     Removes subtree `Tree' from the `AST'.
%% @end
%%--------------------------------------------------------------------
remove_subtree(AST, Tree) ->
    case erlang:is_list(AST) of
        true -> ok;
        _ -> throw(?mk_error({bad_param, AST}))
    end,
    {Res, K} = lists:foldr(
        fun (X, {Acc, N}) ->
            case X of
                Tree -> {Acc, N + 1};
                _ -> {[X | Acc], N}
            end
        end,
        {[], 0},
        AST
    ),
    case K of
        0 -> throw(?mk_error({remove_subtree, not_found, Tree}));
        _ -> Res
    end.

% can be used in guards:

-spec is_string(AST::ast()) -> true | false.
%%--------------------------------------------------------------------
%% @doc     Returns `true' if `AST' represents string, that is
%%          term of form `{string, _, _}'. Can be used in guards.
%% @end
%%--------------------------------------------------------------------
is_string(_Variable) ->
    erlang:error(undef).

-spec is_atom(AST::ast()) -> true | false.
%%--------------------------------------------------------------------
%% @doc     Returns `true' if `AST' represents atom, that is
%%          term of form `{atom, _, _}'. Can be used in guards.
%% @end
%%--------------------------------------------------------------------
is_atom(_Variable) ->
    erlang:error(undef).

-spec is_list(AST::ast()) -> true | false.
%%--------------------------------------------------------------------
%% @doc     Returns `true' if `AST' represents list, that is term of
%%          form `{cons, _, _, _}' or `{nil, _}'. Can be used in guards.
%% @end
%%--------------------------------------------------------------------
is_list(_Variable) ->
    erlang:error(undef).

-spec is_function(AST::ast()) -> true | false.
%%--------------------------------------------------------------------
%% @doc     Returns `true' if `AST' represents function, that is
%%          term of form `{function, _, _, _, _}'. Can be used in guards.
%% @end
%%--------------------------------------------------------------------
is_function(_Variable) ->
    erlang:error(undef).

-spec is_fun(AST::ast()) -> true | false.
%%--------------------------------------------------------------------
%% @doc     Returns `true' if `AST' represents fun, that is term of
%%          form `{fun, _, _, _}'. Can be used in guards.
%% @end
%%--------------------------------------------------------------------
is_fun(_Variable) ->
    erlang:error(undef).

-spec is_variable(AST::ast()) -> true | false.
%%--------------------------------------------------------------------
%% @doc     Returns `true' if `AST' represents variable, that is
%%          term of form `{var, _, _}'. Can be used in guards.
%% @end
%%--------------------------------------------------------------------
is_variable(_Variable) ->
    erlang:error(undef).

-spec is_tuple(AST::ast()) -> true | false.
%%--------------------------------------------------------------------
%% @doc     Returns `true' if `AST' represents tuple, that is
%%          term of form `{tuple, _, _}'. Can be used in guards.
%% @end
%%--------------------------------------------------------------------
is_tuple(_Variable) ->
    erlang:error(undef).

% couln't be used in guards:

-spec is_term(ast()) -> true | false.
%%--------------------------------------------------------------------
%% @doc     Returns `true' if `AST' represents erlang term.
%%          Can't be used in guards.
%% @end
%%--------------------------------------------------------------------
is_term(AST) ->
    pt_supp:is_term(AST).

-spec is_term_or_var(ast()) -> true | false.
%%--------------------------------------------------------------------
%% @doc     Returns `true' if `AST' represents erlang term or variable.
%%          Can't be used in guards.
%% @end
%%--------------------------------------------------------------------
is_term_or_var(AST) ->
    pt_supp:is_term_or_var(AST).

-spec list_map(fun ( (ast()) -> ast() ),
               ast()) ->
    ast().
%%--------------------------------------------------------------------
%% @doc     Produces new AST by applying `Fun' to every element in the
%%          `ListAST'.
%% @end
%%--------------------------------------------------------------------
list_map(Fun, ListAST) ->
    pt_supp:list_map(Fun, ListAST).

-spec list_map_fold(fun ((ast(), term()) -> {ast(), term()}),
                    term(),
                    ast()) ->
    {ast(), term()}.
%%--------------------------------------------------------------------
%% @doc     Combines `list_map/2' and `list_fold/3' into one function.
%% @end
%%--------------------------------------------------------------------
list_map_fold(Fun, InitAcc, ListAST) ->
    pt_supp:list_map_fold(Fun, InitAcc, ListAST).

-spec list_fold(fun((ast(), line(), Acc::term()) ->  term()),
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
list_fold(Fun, InitAcc, ListAST) ->
    pt_supp:list_fold(Fun, InitAcc, ListAST).

-spec list_foldr(fun((ast(), line(), term()) -> term()),
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
    pt_supp:list_foldr(Fun, InitAcc, ListAST).

-spec list_reverse(ast()) -> ast().
%%--------------------------------------------------------------------
%% @doc     Returns AST with `ListAST' elements in reversed order.
%% @end
%%--------------------------------------------------------------------
list_reverse(ListAST) ->
    pt_supp:list_reverse(ListAST).

-spec list_concat(ast(), ast()) ->
    ast().
%%--------------------------------------------------------------------
%% @doc     Concatenates `List1' and `List2'. First parameter must be list.
%%          Second parameter may be not list, in case of: List1 = [a, b], List2 = c, Concat = [a, b | c].
%%          In case of List1 = [a, b], List2 = [c], Concat = [a, b, c].
%% @end
%%--------------------------------------------------------------------
list_concat(ListAST1, ListAST2) ->
    pt_supp:list_concat(ListAST1, ListAST2).

-spec abstract(term(), line()) ->
    ast().
%%--------------------------------------------------------------------
%% @throws  {error, {Module, {File, Line}, {bad_term, Term, Error},
%%            Callstack}}
%%
%% @doc     Converts `Term' to AST. `Line' will be asigned to each
%%          node of the abstract form.
%% @end
%%--------------------------------------------------------------------
abstract(Term, Line) ->
    pt_supp:abstract(Term, Line).

-spec list_length(ListAST::ast()) ->
    integer().
%%--------------------------------------------------------------------
%% @doc     Returns number of elements in the `ListAST'.
%% @end
%%--------------------------------------------------------------------
list_length(List) ->
    pt_supp:list_length(List).

-spec create_clear_ast(atom()) -> ast().
%%--------------------------------------------------------------------
%% @doc     Creates AST with `ModuleName' and empty export attribute.
%% @end
%%--------------------------------------------------------------------
create_clear_ast(ModuleName) ->
    pt_supp:create_clear_ast(ModuleName).

-spec compile(ast()) -> {ModuleName::atom(), binary()}.
%%--------------------------------------------------------------------
%% @throws  {error, {Moudle, {File, Line},
%%                    {'compile-error', Error, Warnings}, Callstack}}
%%
%% @doc     Compiles the `AST' to binary.
%% @end
%%--------------------------------------------------------------------
compile(AST) ->
    pt_supp:compile(AST).

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
    pt_supp:compile_to_beam(AST, BinDir).

-spec compile_and_load(ast()) -> ok.
%%--------------------------------------------------------------------
%% @throws  {error, {Module, {File, Line}}, {compile_and_load, Error}, Callstack}
%%
%% @doc     Compiles the `AST' and loads compiled module.
%% @end
%%--------------------------------------------------------------------
compile_and_load(AST) ->
    case pt_supp:compile_and_load(AST) of
        ok -> ok;
        Err -> throw(?mk_error({compile_and_load, Err}))
    end.

%%--------------------------------------------------------------------
%% @doc     Returns text representations of error `E'.
%% @end
%%--------------------------------------------------------------------
format_error(E) ->
    pt_supp:format_error(E).
