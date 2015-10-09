%%%-------------------------------------------------------------------
%%% -*- coding: utf-8 -*-
%%% @author Anton N Ryabkov
%%% @copyright (C) 2015, Eltex, Novosibirsk, Russia
%%% @doc
%%%
%%% @end
%%% Created : 29 Nov 2013
%%%-------------------------------------------------------------------
-module(pt_utils).
-export([
         get_app_options/2,
         get_app_file_path/1,
         get_output_dir/1
        ]).

-spec get_app_options(OptionName :: atom(), CompileOptions :: list()) -> {ok, Result :: term()} | {error, Reason :: term()}.
%%--------------------------------------------------------------------
%% Получить свойство из описания application-а.
%%--------------------------------------------------------------------
get_app_options(OptionName, CompileOptions) ->
    AppFilePath = get_app_file_path(CompileOptions),
    case file:consult(AppFilePath) of
        {ok, [{_AppName, _AppDescription, Options}]} ->
            {ok, proplists:get_value(OptionName, Options)};
        {error, Reason} ->
            {error, {AppFilePath, Reason}};
        BadResult ->
            {error, {bad_result, BadResult}}
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec get_app_file_path(CompileOptions :: list()) ->
    nonempty_string() | {error | no_app_file}.
%%--------------------------------------------------------------------
%% Получить путь до app файла приложения.
%%--------------------------------------------------------------------
get_app_file_path(CompileOptions) ->
    Path = get_output_dir(CompileOptions),
    OutDir = filename:basename(filename:dirname(Path)),
    case string:rchr(OutDir, $-) of
        0 ->
            {error, no_app_file};
        Inx ->
            AppName = string:substr(OutDir, 1, Inx - 1),
            filename:join(Path, AppName ++ ".app")
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec get_output_dir(CompileOptions :: list()) -> string().
%%--------------------------------------------------------------------
%% @doc Получить путь до output директории из настроект компилятора.
%%--------------------------------------------------------------------
get_output_dir(CompileOptions) ->
    case lists:keyfind(outdir, 1, CompileOptions) of
        {_, OutDir} ->
            OutDir;
        _ -> ""
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++