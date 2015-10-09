%%%-------------------------------------------------------------------
%%% -*- coding: utf-8 -*-
%%% @author Timofey Barmin
%%% @copyright (C) 2015, Eltex, Novosibirsk, Russia
%%% @doc
%%%
%%%     1) Wrap parse_transform function and try to handle errors created by macros from include/pt_error_macro.hrl.
%%%         So you'll see human readable error report when your script detects error and throw it with appropriate macro.
%%%     2) Start gen server and log events from child parse_transform script.
%%%
%%%     Usage examples:
%%%
%%%     -include_lib("pt_lib/include/pt_lib.hrl").
%%%     -include_lib("pt_lib/include/pt_patrol.hrl").
%%%
%%%     -patrol([
%%%             % put info logs of this trasformation to file
%%%             {file, "%ROOT/parse_transform/log/%MODULE_transformation.log", info},
%%%             % put error logs to tty
%%%             {tty, error},
%%%             % write parse transform result to file
%%%             {source, "%HOME/.pt_lib/str_parser/src/%MODULE.erl"}
%%%         ]).
%%%     Variable:
%%%         %HOME -> /home/user_name
%%%         %USER -> user_name
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(pt_patrol).

-include("pt_error_macro.hrl").
-include("pt_lib.hrl").
-include("pt_supp.hrl").
-include("pt_types.hrl").

-compile({no_auto_import,[error/2]}).

-behaviour(gen_server).

-export([error/2, error/1, info/2, info/1, debug/2, debug/1, exception/2, exception/1]).
-export([parse_transform/2, write/1, format_error/1]).
-export([start/1, stop/2, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(PATROL_PROC_NAME, patrol_process).

-type filter_type() :: info | debug | error | nothing.
-type user_params() :: {file, string(), filter_type()} | {tty, filter_type()} | {source, string()}.

-record(patrol_state, {
    file :: {string, term(), filter_type()},
    tty :: filter_type(),
    source :: string()
}).

-spec parse_transform(ast(), term()) -> ast().

parse_transform(AST, _Options) ->
    try
        case pt_lib:match(AST, ast_pattern("parse_transform/2[...$_...]. ")) of

            [ast_pattern("$Name/$Arity[...$Clauses...].", Line) = F] ->
                PT_postfix = "_PATROL_LOGER_PT_FUN",
                NewName = pt_supp:mk_atom(atom_to_list(Name), PT_postfix),
                StartFuncName = pt_supp:mk_atom("startPatrolProcess", PT_postfix),
                StopFuncName = pt_supp:mk_atom("stopPatrolProcess", PT_postfix),
                ProcessMacroFuncName = pt_supp:mk_atom("process_macro", PT_postfix),
                Module = ?MODULE,
                ServerModule = ?MODULE,
                ProcessingModule = pt_lib:get_module_name(AST),
                Params =
                    case pt_lib:get_attribute_value(patrol, AST) of
                        [] ->  [{tty, error}];
                        PPS -> PPS
                    end,

                params_check(Params),

                case Params of
                    [] -> ?PT_INFO("-patrol attribute in module ~p is empty, so patrol is switched off", [ProcessingModule]);
                    _ -> ok
                end,

                AST1 = pt_lib:replace(AST, F, ast("$NewName/$Arity[...$Clauses...].", Line)),

                AST2 = pt_lib:add_function(AST1,
                    ast("
                        @Name(AST, Options) ->

                            StartRes = @StartFuncName(AST),

                            Module = try pt_lib:get_module_name(AST) catch _:_ -> unknown end,

                            @Module:info(\"Parse transforming ~p by ~p\", [Module, @ProcessingModule]),

                            ResAST = try
                                        Tmp = @NewName(AST, Options),
                                        @StopFuncName(Tmp, StartRes),
                                        Tmp
                                     catch
                                        C:E ->
                                            case {C,E} of
                                                {throw, {parse_error, _} = Error} ->"
                                                    "@StopFuncName({string, 0, \"Compilation error.\"}, StartRes),
                                                    pt_supp:generate_errors(AST, [Error], []) ++ AST;
                                                {throw, {error, _} = Error} ->"
                                                    "@StopFuncName({string, 0, \"Compilation error.\"}, StartRes),
                                                    pt_supp:generate_errors(AST, [Error], []) ++ AST;
                                                {throw, {internal_error, _} = Error} ->"
                                                    "@StopFuncName({string, 0, \"Compilation error.\"}, StartRes),
                                                    pt_supp:generate_errors(AST, [Error], []) ++ AST;
                                                {C, E} ->
                                                    ST = erlang:get_stacktrace(),
                                                    @Module:error(\"Exception: ~p~nStacktrace~p\", [E, ST]),
                                                    @StopFuncName({string, 0, \"Compilation error.\"}, StartRes),
                                                    pt_supp:generate_errors(AST, [{internal_error, {@Module, 0}, {exception, {E, ST}}, element(2, catch erlang:error(callstack))}], []) ++ AST
                                            end
                                     end,
                            ResAST.
                        ", Line)),

                AST3 = case Params of
                        [] ->
                            pt_lib:add_local_function(AST2, ast("@StartFuncName(_AST) -> ok.", Line));
                        _ ->
                            pt_lib:add_local_function(AST2,
                            ast("
                                @StartFuncName(AST) ->

                                    Params = lists:map(
                                                fun ({source, FileName}) -> {source, @ProcessMacroFuncName(FileName, AST)};
                                                    ({file, FileName, Filter}) -> {file, @ProcessMacroFuncName(FileName, AST), Filter};
                                                    (X) -> X
                                             end, @Params),

                                    @ServerModule:start(Params).
                                ", Line))
                       end,

                AST4 = case Params of
                        [] ->
                            AST3;
                        _ ->
                            pt_lib:add_local_function(AST3,
                                ast("
                                    @ProcessMacroFuncName(Str, AST) ->
                                        Str1 = re:replace(Str, \"\\%MODULE\", atom_to_list(pt_lib:get_module_name(AST)), [unicode, global, {return, list}]),
                                        {ok, [[HomeDir]]} = init:get_argument(home),
                                        Str2 = re:replace(Str1, \"\\%HOME\", HomeDir, [unicode, global, {return, list}]),
                                        User = filename:basename(HomeDir),
                                        re:replace(Str2, \"\\%USER\", User, [unicode, global, {return, list}]).
                                    ", Line))
                       end,

                AST5 = case Params of
                        [] ->
                            pt_lib:add_local_function(AST4, ast("@StopFuncName(_ResAST, _) -> ok.", Line));
                        _ ->
                            pt_lib:add_local_function(AST4,
                                ast("
                                    @StopFuncName(ResAST, StartRes) ->
                                        @ServerModule:stop(ResAST, StartRes).
                                    ", Line))
                       end,
                AST5;

            [] ->
                throw(?mk_parse_error(0, {parse_transform, not_found}))
        end
    catch
        throw:{parse_error, _} = Error ->
            pt_supp:print_error(AST, Error),
            pt_supp:generate_errors(AST, [Error], []) ++ AST;
        throw:{error, _} = Error ->
            pt_supp:print_error(AST, Error),
            pt_supp:generate_errors(AST, [Error], []) ++ AST;
        throw:{internal_error, _} = Error ->
            pt_supp:print_error(AST, Error),
            pt_supp:generate_errors(AST, [Error], []) ++ AST
    end.

-spec write({filter_type(), {string(), [term()]}}) -> ok.

write({_Priority, {_F, _A}} = Mess) ->
    gen_server:cast(?PATROL_PROC_NAME, Mess),
ok.

-spec info(string(), [term()]) -> ok.
info(F, A)  -> write({info,  {F, A}}).

-spec debug(string(), [term()]) -> ok.
debug(F, A) -> write({debug, {F, A}}).

-spec error(string(), [term()]) -> ok.
error(F, A) -> write({error, {F, A}}).

-spec exception(string(), [term()]) -> ok.
exception(F, A) -> write({error, {F ++ "~nStacktrace: ~p", A ++ [erlang:get_stacktrace()]}}).

-spec info(string()) -> ok.
info(F) -> info(F, []).

-spec debug(string()) -> ok.
debug(F) -> debug(F, []).

-spec error(string()) -> ok.
error(F) -> error(F, []).

-spec exception(string()) -> ok.
exception(F) -> exception(F, []).

-spec start(term()) -> ok | already_started.

start(Params) ->
    case gen_server:start_link({local, ?PATROL_PROC_NAME}, ?MODULE, Params, []) of
	{ok, _} ->
	    debug("Patrol started ~p", [Params]),
	    ok;
	{error, {already_started, _Pid}} ->
	    already_started;
	Error ->
	    throw(?mk_error({patrol_start_error, Error}))
    end.

-spec stop(ast(), ok | already_started) -> ok.

stop(ResAST, StartRes) ->
    case StartRes of
        ok ->
            debug("Patrol stoped"),
            case catch gen_server:call(?PATROL_PROC_NAME, {stop, ResAST}) of
                {'EXIT', {normal, _}} -> ok;
                Error ->
                    io:format("PATROL STOP ERROR: ~p!!!~n", [Error])
            end;
        _ ->
            ok
    end.

-spec params_check([user_params()]) -> ok.

params_check([P | T]) ->
    param_check(P),
    params_check(T);
params_check([]) -> ok.

-spec param_check(user_params()) -> ok.

param_check({tty, Filter}) ->
    filter_check(Filter);
param_check({file, FName, Filter}) when is_list(FName) ->
    filter_check(Filter);
param_check({source, FName}) when is_list(FName) ->
    ok;
param_check(P) ->
    throw(?mk_parse_error(0, {bad_config, P})).



-spec filter_check(filter_type()) -> ok.

filter_check(debug) -> ok;
filter_check(info) -> ok;
filter_check(error) -> ok;
filter_check(nothing) -> ok;
filter_check(Filter) -> throw(?mk_parse_error(0, {bad_config, Filter})).


-spec init([user_params()]) ->
    {ok, State :: #patrol_state{}} |
    {stop, _Reason}.

init(Params) ->
    try
        State = lists:foldl(
                    fun
                        ({file, FileName, Filter}, S) when is_list(FileName) ->
                            filter_check(Filter),
                            filelib:ensure_dir(FileName),
                            case file:open(FileName, [append]) of
                                {ok, H} -> S#patrol_state{file = {FileName, H, Filter}};
                                Error -> throw({error, {cant_open, FileName, Error}})
                            end;
                        ({tty, Filter}, S) ->
                            filter_check(Filter),
                            S#patrol_state{tty = Filter};
                        ({source, FileName}, S) ->
                            S#patrol_state{source = FileName};
                        (Unknown, _S) -> throw({error, {bad_config, Unknown}})
                    end, #patrol_state{file = null, tty = null, source = null}, Params),
        {ok, State}
    catch
        throw:{error, _} = E ->
            {stop, E}
    end.



-spec format_str({filter_type(), {string(), [term()]}}) -> string().

format_str({Priority, {F, A}}) ->
    UserStr = re:replace(lists:flatten(io_lib:format(F ++ "~n", A)), "~", "~~", [unicode, global, {return, list}]),
    Header = case Priority of
                debug -> "DEBUG ";
                info ->  "INFO  ";
                error -> "";
                _ ->     "UNKNOWN"
             end,
    Tokens = string:tokens(UserStr, "\n"),
    string:join([Header ++ Str || Str <- Tokens], "\n") ++ "\n".



-spec handle_cast({filter_type(), {string(), [term()]}}, #patrol_state{}) -> {noreply, #patrol_state{}}.

handle_cast({Priority, {_F, _A}} = M, State = #patrol_state{file = File, tty = TTY}) ->
    Str = format_str(M),
    case File of
        null -> ok;
        {_, H, Filter} ->
            case filter(Priority, Filter) of
                true -> io:format(H, Str, []);
                false -> ok
            end
    end,

    case TTY of
        null -> ok;
        Filter2 ->
            case filter(Priority, Filter2) of
                true-> io:format(Str, []);
                false -> ok
            end
    end,
    {noreply, State};

handle_cast(_Unknown, State) ->
    handle_cast({error, {"Unhandled cast request in patrol: ~p", [_Unknown]}}, State).


-spec handle_call({stop, ast()}, term(), #patrol_state{}) -> {stop, normal, #patrol_state{}} | {stop, error, term(), #patrol_state{}}.

handle_call({stop, ResAST}, _From, State = #patrol_state{file = FileConf, source = SourceConf}) ->
    Res1 = case FileConf of
            null -> ok;
            {FileName, H, _} ->
                case file:close(H) of
                    ok -> ok;
                    Error ->
                        {close_file_error, FileName, Error}
                end
           end,

    Res2 = case SourceConf of
            null -> ok;
            SFileName ->
                try
                    filelib:ensure_dir(SFileName),
                    {ok, H2} = file:open(SFileName, [write]),
                    case pt_supp:ast2str(ResAST) of
                        {error, E} -> io:format(H2, "%% Auttogenerated by patrol~n~nError:~n~p", [E]);
                        {ok, Str} when is_list(Str) -> io:format(H2, "%% Autogenerated by patrol~n~n~s", [Str])
                    end,
                    ok = file:close(H2)
                catch
                    error:{badmatch, E2} ->
                        {save_source_error, SFileName, E2}
                end
           end,

    case {Res1, Res2} of
        {ok, ok} -> {stop, normal, State};
        {Err, ok} -> {stop, error, Err, State};
        {ok, Err} -> {stop, error, Err, State};
        {Err1, Err2} -> {stop, error, {Err1, Err2}, State}
    end;

handle_call(_Msg, _From, State) ->
    handle_cast({error, {"Unhandled call request in patrol: ~p", [_Msg]}}, State).

handle_info(_Info, State) ->
    handle_cast({error, {"Unhandled info request in patrol: ~p", [_Info]}}, State).

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

-spec filter(filter_type(), filter_type()) -> true | false.

filter(nothing, debug) -> true;
filter(nothing, info) -> true;
filter(nothing, error) -> true;
filter(nothing, nothing) -> false;
filter(error, debug) -> true;
filter(error, info) -> true;
filter(error, error) -> true;
filter(error, nothing) -> false;
filter(info, debug) -> true;
filter(info, info) -> true;
filter(info, error) -> false;
filter(info, nothing) -> false;
filter(debug, debug) -> true;
filter(debug, info) -> false;
filter(debug, error) -> false;
filter(debug, nothing) -> false.

-spec format_error(term()) -> string().

format_error({parse_transform, not_found}) ->
    io_lib:format("Function parse_transform is not found", []);
format_error({patrol_start_error, {error, {bad_config, Param}}}) ->
    io_lib:format("Cant start patrol cause bad config param: ~p", [Param]);
format_error({patrol_start_error, {error, {cant_open, FileName, Error}}}) ->
    io_lib:format("Cant start patrol cause file ~s open error ~p", [FileName, Error]);
format_error({patrol_start_error, Error}) ->
    io_lib:format("Cant start patrol cause: ~p", [Error]);
format_error({patrol_stop_error, {close_file_error, FileName, Error}}) ->
    io_lib:format("Stop patrol error, cause file ~s close error ~p", [FileName, Error]);
format_error({patrol_stop_error, {save_source_error, SFileName, Error}}) ->
    io_lib:format("Stop patrol error, case save source ~s error ~p", [SFileName, Error]);
format_error({patrol_stop_error, {{close_file_error, FileName, Error},{safe_source_error, SFileName, SError}}}) ->
    io_lib:format("Stop patrol error, cause file ~s close error ~p and case save source ~s error ~p", [FileName, Error, SFileName, SError]);
format_error({patrol_stop_error, Error}) ->
    io_lib:format("Stop patrol error, cause ~p", [Error]);
format_error({bad_config, P}) ->
    io_lib:format("Bad patrol config param: ~p", [P]);
format_error(Unknown) ->
    io_lib:format("Unknown error: ~p", [Unknown]).