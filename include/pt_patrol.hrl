%%%-------------------------------------------------------------------
%%% -*- coding: utf-8 -*-
%%% @copyright (C) 2015, Eltex, Novosibirsk, Russia
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-compile({parse_transform, pt_patrol}).

-define(PATROL_DEBUG(F, A), pt_patrol:debug("~p:~b: (~s) " ++ F, [?FILE, ?LINE, ?FUNC_STRING| A])).
-define(PATROL_INFO(F, A), pt_patrol:info("~p:~b: (~s) " ++ F, [?FILE, ?LINE, ?FUNC_STRING | A])).
-define(PATROL_ERROR(F, A), pt_patrol:error("~p:~b: (~s) " ++ F, [?FILE, ?LINE, ?FUNC_STRING | A])).
-define(PATROL_EXCEPTION(F, A), pt_patrol:exception("~p:~b: (~s) " ++ F, [?FILE, ?LINE, ?FUNC_STRING | A])).