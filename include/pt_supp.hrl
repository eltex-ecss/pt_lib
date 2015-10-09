%%%-------------------------------------------------------------------
%%% -*- coding: utf-8 -*-
%%% @copyright (C) 2015, Eltex, Novosibirsk, Russia
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-define(PATROL_PROC, patrol_process).

%-define(PT_ERROR(Str, Args),
%    begin
%        case whereis(?PATROL_PROC) of
%            undefined ->
%                io:format("~s:~p: pt error: " ++ Str ++ "~n", [?FILE, ?LINE] ++ Args),
%                %erlang:error(pt_error),
%                ok;
%            _ -> pt_patrol:error("~s:~p: " ++ Str, [?FILE, ?LINE] ++ Args)
%        end,
%        ok
%    end
%    ).

%-define(PT_USER_ERROR(Line, Str, Args),
%    begin
%        F = "~s:~p: (~p:~p) pt error: " ++ Str,
%        A = [pt_supp:get_file_name(), Line, ?MODULE, ?LINE] ++ Args,
%        case whereis(?PATROL_PROC) of
%            undefined ->
%                io:format(F ++ "~n", A),
%                %erlang:error(pt_error),
%                ok;
%            _ -> pt_patrol:error(F, A)
%        end,
%        ok
%    end
%    ).

%-define(PT_EXCEPT(Str, Args),
%    begin
%        case whereis(?PATROL_PROC) of
%            undefined ->
%                io:format("~s:~p: pt error: " ++ Str ++ "~nStacktrace: ~p~n", [?FILE, ?LINE] ++ Args ++ [erlang:get_stacktrace()]),
%                %erlang:error(pt_error),
%                ok;
%            _ ->
%                pt_patrol:exception("~s:~p: " ++ Str, [?FILE, ?LINE] ++ Args),
%                ok
%        end,
%        ok
%    end
%    ).

-define(PT_INFO(Str, Args),
    begin
        case whereis(?PATROL_PROC) of
            undefined ->
%               io:format(Str ++ "~n", Args),
                ok;
            _ ->
                pt_patrol:info(Str, Args),
                ok
        end,
        ok
    end
    ).
-define(PT_DBG(Str, Args),
    begin
        case whereis(?PATROL_PROC) of
            undefined ->
%               io:format(Str ++ "~n", Args),
                ok;
            _ ->
                pt_patrol:debug(Str, Args),
                ok
        end,
        ok
    end
    ).