%%%-------------------------------------------------------------------
%%% -*- coding: utf-8 -*-
%%% @author Timofey Barmin
%%% @copyright (C) 2015, Eltex, Novosibirsk, Russia
%%% @doc
%%%
%%% Usage:
%%%
%%% -include_lib("pt_lib/include/pt_patrol.hrl").
%%%
%%%  parse_tranform(AST, Options) ->
%%%      ...
%%%      throw(mk_parse_error(Line, error1)) % Use it when you detect error in parsed module.
%%%                                          % Patrol will call format_error with throwed error which should return human readable error description.
%%%                                          % It writes an error like it occurs in processed file at line Line.
%%%      ...
%%%      throw(mk_error(error2)) % Error in your script. Patrol writes error like it occurs in your parse transformation script.
%%%      ...
%%%
%%%  format_error(error1) -> "Error string description";
%%%  format_error(error2) -> "...".
%%%
%%% @end
%%%-------------------------------------------------------------------
-define(mk_parse_error(Line, ErrorDescriptor), {parse_error, {Line, ?MODULE, ErrorDescriptor}}).
-define(mk_error(ErrorDescriptor), {error, {?MODULE, {?FILE, ?LINE}, ErrorDescriptor, element(2, catch erlang:error(callstack))}}).
-define(mk_int_error(ErrorDescriptor), {internal_error, {?MODULE, {?FILE, ?LINE}, ErrorDescriptor, element(2, catch erlang:error(callstack))}}).