%%%-------------------------------------------------------------------
%%% -*- coding: utf-8 -*-
%%% @copyright (C) 2015, Eltex, Novosibirsk, Russia
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-type ast()   :: [erl_syntax:syntaxTree()] | erl_syntax:syntaxTree().
-type line()  :: non_neg_integer().