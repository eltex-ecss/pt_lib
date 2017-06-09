%%%-------------------------------------------------------------------
%%% -*- coding: utf-8 -*-
%%% @copyright (C) 2015, Eltex, Novosibirsk, Russia
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(pt_supp_tests).

-include("pt_lib.hrl").
-include("pt_error_macro.hrl").
-include("pt_supp.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(TEST_FILE, "test.erl").
-define(TEST_MODULE, test).

-ifdef(PT_SUPP_TESTS_ENABLE).

replace_remote_call_test() ->
    ?assertEqual(str_to_ast("foo:bar().", 42),
                 pt_supp:replace_remote_call(str_to_ast("bar:foo().", 42),
                                             bar, foo, fun replace_remote_call/2, {foo, bar})),
    ?assertEqual(str_to_ast("bar:foo().", 42),
                 pt_supp:replace_remote_call(str_to_ast("bar:foo().", 42),
                                             module, function, fun replace_remote_call/2, {foo, bar})),
    ?assertEqual(str_to_ast(["foo:bar().", "m:f(123)."], 42),
                 pt_supp:replace_remote_call(str_to_ast(["bar:foo().", "m:f(123)."], 42),
                                             bar, foo, fun replace_remote_call/2, {foo, bar})).

replace_local_call_test() ->
    ?assertEqual(str_to_ast("foobar().", 42),
                 pt_supp:replace_local_call(str_to_ast("foo().", 42), foo,
                                            fun replace_call/2, foobar)),
    ?assertEqual(str_to_ast("foo().", 42),
                 pt_supp:replace_local_call(str_to_ast("foo().", 42), function,
                                            fun replace_call/2, foobar)),
    ?assertEqual(str_to_ast(["foo().", "f(123)."], 42),
                 pt_supp:replace_local_call(str_to_ast(["bar().", "f(123)."], 42),
                                            bar, fun replace_call/2, foo)).

get_file_name_test() ->
    ?assertEqual("pt_supp_tests.erl", pt_supp:get_file_name([{attribute,1,file,{"pt_supp_tests.erl",1}}])),
    ?assertEqual(?TEST_FILE, pt_supp:get_file_name(test_ast())),
    ?assertThrow(_, pt_supp:get_file_name([str_to_ast("A = a.", 1)])).

get_module_name_test() ->
    ?assertEqual(test, pt_supp:get_module_name([str_to_ast("-module(test).", 10)])),
    ?assertThrow(_, pt_supp:get_module_name([str_to_ast("foo(42).", 1)])).

set_module_name_test() ->
    ?assertEqual([str_to_ast("A = a.", 10)],
                 pt_supp:set_module_name([str_to_ast("A = a.", 10)], foobar)),
    ?assertEqual([str_to_ast("-module(foo).", 1)],
                 pt_supp:set_module_name([str_to_ast("-module(bar).", 1)], foo)).

replace_test() ->
    ?assertEqual(str_to_ast("foo().", 42), pt_supp:replace(str_to_ast("bar().", 42),
                                                           fun (Tree) -> replace_call(Tree, foo) end)),
    ?assertEqual(str_to_ast("func(), func(123), func([], {}).", 42),
                 pt_supp:replace(str_to_ast("foo(), bar(123), foobar([], {}).", 42),
                                 fun (Tree) -> replace_call(Tree, func) end)),
    ?assertEqual(str_to_ast("foo(), bar().", 42),
                 pt_supp:replace(str_to_ast("foo(), bar().", 42), fun (Tree) -> Tree end)),
    ?assertEqual(str_to_ast("foo().", 42),
                 pt_supp:replace(str_to_ast("bar().", 42), fun (Tree) -> replace_call(Tree, foo) end, true)),
    ?assertEqual(str_to_ast("func(), func(123), func([], {}).", 42),
                 pt_supp:replace(str_to_ast("foo(), bar(123), foobar([], {}).", 42),
                                 fun (Tree) -> replace_call(Tree, func) end, true)),
    ?assertEqual(str_to_ast("foo(), bar().", 42),
                 pt_supp:replace(str_to_ast("foo(), bar().", 42), fun (Tree) -> Tree end, true)),
    ?assertEqual(str_to_ast("foo().", 42), pt_supp:replace(str_to_ast("bar().", 42), fun (Tree) -> replace_call(Tree, foo) end, false)),
    ?assertEqual(str_to_ast("func(), func(123), func([], {}).", 42),
                 pt_supp:replace(str_to_ast("foo(), bar(123), foobar([], {}).", 42),
                                 fun (Tree) -> replace_call(Tree, func) end, false)),
    ?assertEqual(str_to_ast("foo(), bar().", 42),
                 pt_supp:replace(str_to_ast("foo(), bar().", 42), fun (Tree) -> Tree end, false)).

replace_fold_test() ->
    ?assertEqual({str_to_ast("foo().", 42), 1},
                 pt_supp:replace_fold(str_to_ast("bar().", 42),
                                      fun (Tree, Acc) -> {replace_call(Tree, foo), if element(1, Tree) =:= call -> Acc + 1; true -> Acc end} end, 0)),
    ?assertEqual({str_to_ast("foo(), bar(123), foobar([], {}).", 42), []},
                 pt_supp:replace_fold(str_to_ast("foo(), bar(123), foobar([], {}).", 42),
                                      fun (Tree, Acc) -> {Tree, Acc} end, [])).

abstract_test() ->
    ?assertEqual(str_to_ast("a.", 42), pt_supp:abstract(a, 42)),
    ?assertEqual(str_to_ast("\"abc\".", 42), pt_supp:abstract("abc", 42)),
    ?assertThrow(_, pt_supp:abstract(fun replace_call/2, 42)).

% known bug in erl_syntax:revert
%revert_test() ->
%    ?assertEqual(str_to_ast("-record(a, {b}).", 1),
%                 erl_syntax:revert(erl_syntax:record_field(str_to_ast("-record(a, {b}).", 1)))).

insert_lines_test() ->
    ?assertEqual(str_to_ast("A = a.", 42), pt_supp:insert_lines(str_to_ast("A = a.", 1), 42)),
    ?assertEqual(str_to_ast("a(), b(1, 2, 3), c().", 42),
                 pt_supp:insert_lines(str_to_ast("a(), b(1, 2, 3), c().", 1), 42)),
    ?assertEqual(str_to_ast("[].", 42), pt_supp:insert_lines(str_to_ast("[].", 5), 42)),
    ?assertEqual(str_to_ast("func() -> ok.", 42),
                 pt_supp:insert_lines(str_to_ast("func() -> ok.", 1), 42)),
    % known bug in pt_supp:insert_lines
    %?assertEqual(str_to_ast("-record(a, {b, c}).", 42),
    %            pt_supp:insert_lines(str_to_ast("-record(a, {b, c}).", 1), 42)),
    ?assertEqual(str_to_ast("-export([foo/1]).", 42),
                 pt_supp:insert_lines(str_to_ast("-export([foo/1]).", 1), 42)),
    ?assertEqual(str_to_ast("-include(module).", 42),
                 pt_supp:insert_lines(str_to_ast("-include(module).", 1), 42)).

replace_first_test() ->
    ?assertEqual(str_to_ast("foo(), bar().", 42),
                 pt_supp:replace_first(str_to_ast("bar(), bar().", 42),
                                       fun (Tree) -> replace_call(Tree, foo) end)),
    ?assertEqual(str_to_ast(["foo().", "bar()."], 42),
                 pt_supp:replace_first(str_to_ast(["bar().", "bar()."], 42),
                                       fun (Tree) -> replace_call(Tree, foo) end)),
    ?assertEqual(str_to_ast(["func() -> foo(), bar().", "bar()."], 42),
                 pt_supp:replace_first(str_to_ast(["func() -> bar(), bar().", "bar()."], 42),
                                       fun (Tree) -> replace_call(Tree, foo) end)),
    ?assertEqual(str_to_ast("foo().", 42),
                 pt_supp:replace_first(str_to_ast("bar().", 42),
                                       fun (Tree) -> replace_call(Tree, foo) end)).

get_function_ast_test() ->
    ?assertEqual({ok, str_to_ast("foo() -> ok.", 1)},
                 pt_supp:get_function_ast([str_to_ast("foo() -> ok.", 1)], foo, 0)),
    ?assertEqual({error, not_found}, pt_supp:get_function_ast([str_to_ast("foo().", 1)], foo, 0)),
    ?assertThrow(_, pt_supp:get_function_ast([str_to_ast("foo() -> ok.", 1),
                                              str_to_ast("foo() -> ok.", 2)], foo, 0)),
    ?assertThrow(_, pt_supp:get_function_ast(str_to_ast("foo() -> ok.", 1), foo, 0)).

replace_function_clause_code_test() ->
    ?assertEqual(str_to_ast("foo() -> A + B + C.", 42),
                 pt_supp:replace_function_clause_code(str_to_ast("foo() -> ok.", 42),
                                                      foo, 0, [], [], [str_to_ast("A + B + C.", 42)])),
    ?assertEqual(str_to_ast("foo() -> ok.", 42),
                 pt_supp:replace_function_clause_code(str_to_ast("foo() -> ok.", 42),
                                                      bar, 0, [], [], [str_to_ast("A + B + C.", 42)])),
    ?assertEqual(str_to_ast("A = a.", 42), pt_supp:replace_function_clause_code(str_to_ast("A = a.", 42),
                                                                                foo, 0, [], [], [str_to_ast("A + B.", 42)])),
    ?assertEqual(str_to_ast("foo(A) when is_integer(A) -> A * 2.", 42),
                 pt_supp:replace_function_clause_code(str_to_ast("foo(A) when is_integer(A) -> A * 2.", 42),
                                                      foo, 1, [str_to_ast("A.", 42)], [],
                                                      [str_to_ast("A + 1.", 42)])),
    ?assertEqual(str_to_ast("foo(A) when is_integer(A) -> A + 1.", 42),
                 pt_supp:replace_function_clause_code(str_to_ast("foo(A) when is_integer(A) -> A * 2.", 42),
                                                      foo, 1, [str_to_ast("A.", 42)], [[str_to_ast("is_integer(A).", 42)]],
                                                      [str_to_ast("A + 1.", 42)])).

get_compile_options_test() ->
    ?assertEqual([export_all, debug_info],
                 pt_supp:get_compile_options([str_to_ast("-compile([export_all, debug_info]).", 1)])),
    ?assertEqual([debug_info, {parse_transform, pt_lib}],
                 pt_supp:get_compile_options(str_to_ast(["-compile({parse_transform, pt_lib}).", "-compile(debug_info)."], 1))),
    ?assertEqual([], pt_supp:get_compile_options([str_to_ast("a.", 1)])).

get_attribute_value_test() ->
    ?assertEqual([], pt_supp:get_attribute_value(module, [str_to_ast("A = a.", 1)])),
    ?assertEqual([foobar], pt_supp:get_attribute_value(module, [str_to_ast("-module(foobar).", 1)])),
    ?assertEqual([debug_info], pt_supp:get_attribute_value(compile, [str_to_ast("-compile(debug_info).", 1)])),
    ?assertEqual([debug_info, export_all],
                 pt_supp:get_attribute_value(compile, [str_to_ast("-compile([debug_info, export_all]).", 1)])),
    ?assertEqual([{func, 3}], pt_supp:get_attribute_value(export, [str_to_ast("-export([func/3]).", 1)])),
    ?assertEqual([{func, 3}, {foo, 0}], pt_supp:get_attribute_value(export, [str_to_ast("-export([func/3, foo/0]).", 1)])),
    ?assertEqual([{rec, [{record_field, 6, {atom, 6, a}, {string, 6, []}}, {record_field, 6, {atom, 6, b}, {nil, 6}}]}],
                 pt_supp:get_attribute_value(record, [str_to_ast("-record(rec, {a = \"\", b = []}).", 6)])),
    ?assertEqual([{rec1, [{record_field, 6, {atom, 6, c}}, {record_field, 6, {atom, 6, d}}]},
                  {rec, [{record_field, 6, {atom, 6, a}, {string, 6, []}}, {record_field, 6, {atom, 6, b}, {nil, 6}}]}],
                 pt_supp:get_attribute_value(record,
                                             str_to_ast(["-record(rec, {a =\"\", b = []}).", "-record(rec1, {c, d})."], 6))),
    ?assertEqual([{rec, [{record_field, 6, {atom, 6, c}}, {record_field, 6, {atom, 6, d}},
                         {record_field, 6, {atom, 6, a}, {string, 6, []}}, {record_field, 6, {atom, 6, b}, {nil, 6}}]}],
                 pt_supp:get_attribute_value(record,
                                             str_to_ast(["-record(rec, {a =\"\", b = []}).", "-record(rec, {c, d})."], 6))),
    ?assertMatch({?TEST_FILE, _},
                 lists:keyfind(?TEST_FILE, 1, pt_supp:get_attribute_value(file, test_ast()))).

set_attribute_test() ->
    ?assertEqual(str_to_ast(["-module(foo).", "-export([func/0]).", "a."], 1),
                 pt_supp:set_attribute(str_to_ast(["-module(foo).", "a."], 1), export, [{func, 0}])),
    ?assertEqual(str_to_ast(["-module(foo).", "-vsn(\"1.2.3\").", "-export([func/0, foo/3]).", "a."], 1),
                 pt_supp:set_attribute(str_to_ast(["-module(foo).", "-vsn(\"1.2.3\").", "-export([func/0]).", "a."], 1),
                                       export, [{func, 0}, {foo, 3}])),
    ?assertEqual(str_to_ast(["-export([func/0]).", "-include(\"a/b/c.hrl\")."], 1),
                 pt_supp:set_attribute(str_to_ast(["-export([func/0]).", "-include(\"a.hrl\")."], 1), include, "a/b/c.hrl")),
    ?assertEqual(str_to_ast(["-export([func/0]).", "-include(\"a/b/c.hrl\")."], 1),
                 pt_supp:set_attribute(str_to_ast(["-export([func/3]).", "-include(\"a/b/c.hrl\")."], 1), export, [{func, 0}])),
    ?assertThrow({parse_error, _}, pt_supp:set_attribute(str_to_ast(["-export([func/0]).", "func() -> ok."], 1), compile, debug)),
    ?assertThrow({parse_error, _}, pt_supp:set_attribute([str_to_ast("A = a.", 1)], export, [{func, 0}])).

replace_attribute_test() ->
    ?assertEqual({ok, [{attribute,1,attr,new_value}]}, pt_supp:replace_attribute([{attribute,1,attr,old_value}], attr, new_value, [])),
    ?assertEqual(not_found, pt_supp:replace_attribute([{attribute,1,other_attr,new_value}], attr, 123, [])).

str2ast_test() ->
    ?assertEqual({ok, [{match, 1, {var, 1, 'A'}, {atom, 1, a}}]}, pt_supp:str2ast("A = a.", 1)),
    ?assertEqual({ok, [{function, 1, foo, 2,
                        [{clause, 1, [{var, 1, 'A'}, {var, 1, 'B'}],
                          [[{call, 1, {atom, 1, is_integer}, [{var, 1, 'A'}]}]],
                          [{op, 1, '+', {var, 1, 'A'}, {var, 1, 'B'}}]}]}]},
                 pt_supp:str2ast("foo(A,  B) when is_integer(A) -> A + B.",  1)),
    ?assertEqual({ok, [{clause, 1, [], [], [{atom, 1, ok}]}]},
                 pt_supp:str2ast("() -> ok.", 1)),
    ?assertEqual({ok, [{clause, 1, [{var, 1, 'A'}], [[{call, 1, {atom, 1, is_atom},[{var, 1, 'A'}]}]], [{atom, 1, ok}]}]},
                 pt_supp:str2ast("(A) when is_atom(A) -> ok.", 1)),
    ?assertMatch({error, _},
                 pt_supp:str2ast("() when abc def-> ok.", 1)),
    ?assertEqual({ok, [{function, 1, f, 1, [{clause, 1, [{atom, 1, a}], [], [{atom, 1, b}]}]}]},
                 pt_supp:str2ast("f(a) -> b.", 1)),
    ?assertEqual({ok, [{attribute, 1, module, foo}]}, pt_supp:str2ast("-module(foo).", 1)),
    ?assertEqual({ok, [{attribute, 1, compile, {parse_transform, foobar}}]},
                 pt_supp:str2ast("-compile({parse_transform, foobar}).", 1)),
    ?assertEqual({error, miss_dot}, pt_supp:str2ast("A = a", 1)),
    ?assertMatch({error, {parse_error, _, _}}, pt_supp:str2ast("foo(A) when is_integer A) -> a.", 1)),
    ?assertMatch({error, {parse_error, _, _}}, pt_supp:str2ast("foo(A B) -> a.", 1)),
    ?assertMatch({error, {parse_error, _, _}}, pt_supp:str2ast("foo() -> A B.", 1)),
    ?assertMatch({error, {parse_error, _, _}}, pt_supp:str2ast("+.", 1)).

ast2str_test() ->
    ?assertEqual({ok, "A = 1"}, pt_supp:ast2str(str_to_ast("A = 1.", 1))),
    ?assertEqual({ok, "foo() -> ok."}, pt_supp:ast2str(str_to_ast("foo() -> ok.", 1))),
    ?assertEqual({ok, "foo(A, B) when is_integer(A) -> A + B."},
                 pt_supp:ast2str(str_to_ast("foo(A, B) when is_integer(A) -> A + B.", 1))),
    ?assertEqual({ok, "case A() of\n  a -> b;\n  b -> c\nend"},
                 pt_supp:ast2str(str_to_ast("case A() of a -> b; b -> c end.", 1))),
    ?assertEqual({ok, "if A > B -> a;\n   true -> b\nend"},
                 pt_supp:ast2str(str_to_ast("if A > B -> a; true -> b end.", 1))),
    ?assertEqual({ok, "-module(foo)."}, pt_supp:ast2str(str_to_ast("-module(foo).", 1))),
    ?assertEqual("-module(foo).\nfunc() -> ok.\n\n",
                 lists:flatten(element(2, pt_supp:ast2str(str_to_ast(["-module(foo).", "func() -> ok."], 1))))),
    ?assertEqual("f() -> a.\n\n", lists:flatten(element(2, pt_supp:ast2str(str_to_ast(["f() -> a."], 1))))),
    ?assertEqual("foo(), bar(), foobar()", lists:flatten(element(2, pt_supp:ast2str(str_to_ast(["foo(), bar(), foobar()."], 1))))),
    ?assertEqual({ok, "-compile(export_all)."}, pt_supp:ast2str(str_to_ast("-compile(export_all).", 1))),
    ?assertEqual({ok, "-include(\"a/b/c.hrl\")."}, pt_supp:ast2str(str_to_ast("-include(\"a/b/c.hrl\").", 1))),
    ?assertMatch({error, _}, pt_supp:ast2str([{abc, 1, {var, 1, 'A'}, {atom, 1, a}}])).

generate_errors_test() ->
    ?assertEqual([], pt_supp:generate_errors([], [], [])),
    ?assertMatch([{attribute, 0, file, {_FileName, 42}}, {error, {42, _, "Sample error"}}],
                 pt_supp:generate_errors([], [?mk_parse_error(42, "Sample error")], [])),
    ?assertEqual([{attribute, 0, file, {?TEST_FILE, 42}}, {error, {42, ?MODULE, "Sample error"}}],
                 pt_supp:generate_errors(test_ast(), [?mk_parse_error(42, "Sample error")], [])),
    ?assertMatch([{attribute, _Line, file, {?FILE, _Line}}, {error, {_Line, ?MODULE, "Sample error"}}],
                 pt_supp:generate_errors([], [?mk_error("Sample error")], [])),
    ?assertMatch([{attribute, _Line, file, {?FILE, _Line}}, {error, {_Line, ?MODULE, "Sample error"}}],
                 pt_supp:generate_errors([], [?mk_int_error("Sample error")], [])),
    ?assertMatch([{attribute, _Line, file, {_File, _Line}}, {error, {_Line, _Module, sample_error}}],
                 pt_supp:generate_errors([], [sample_error], [])).

format_errors_test() ->
    ?assertEqual(":42: Error: Cant format_error cause function module:format_error/1 is undefined\n\"Sample error\"",
                 lists:flatten(pt_supp:format_errors({42, module, "Sample error"}))),
    ?assertEqual(":42: Error: Unknown error: \"Sample error\"",
                 lists:flatten(pt_supp:format_errors({42, pt_supp, "Sample error"}))),
    ?assertEqual(":42: Error: More than one function with name foo/2",
                 lists:flatten(pt_supp:format_errors({42, pt_supp, {many_func, foo, 2}}))),
    ?assertEqual("file.erl:42: Error: Cant format_error cause function module:format_error/1 is undefined\n\"Sample error\"\n",
                 lists:flatten(pt_supp:format_errors([{"file.erl", [{42, module, "Sample error"}]}]))),
    ?assertEqual("file.erl:42: Error: Unknown error: \"Sample error\"\n",
                 lists:flatten(pt_supp:format_errors([{"file.erl", [{42, pt_supp, "Sample error"}]}]))),
    ?assertEqual("file.erl:42: Error: More than one function with name foo/2\n",
                 lists:flatten(pt_supp:format_errors([{"file.erl", [{42, pt_supp, {many_func, foo, 2}}]}]))),
    ?assertEqual("file.erl:42: Error: Variables ['A','C'] are unbound\n"
                 "file.erl:43: Error: Bad param: 'B'\nfile2.erl:42: Error: Unknown error: \"Sample error\"\n",
                 lists:flatten(pt_supp:format_errors([{"file.erl", [{42, pt_supp, {unbound_var, ['A', 'C']}},
                                                                    {43, pt_supp, {bad_param, 'B'}}]},
                                                      {"file2.erl", [{42, pt_supp, "Sample error"}]}]))).

format_warnings_test() ->
    ?assertEqual(":42: Warning: Cant format_error cause function module:format_error/1 is undefined\n\"Sample warning\"",
                 lists:flatten(pt_supp:format_warnings({42, module, "Sample warning"}))),
    ?assertEqual(":42: Warning: Unknown error: \"Sample warning\"",
                 lists:flatten(pt_supp:format_warnings({42, pt_supp, "Sample warning"}))),
    ?assertEqual(":42: Warning: More than one function with name foo/2",
                 lists:flatten(pt_supp:format_warnings({42, pt_supp, {many_func, foo, 2}}))),
    ?assertEqual("file.erl:42: Warning: Cant format_error cause function module:format_error/1 is undefined\n\"Sample warning\"\n",
                 lists:flatten(pt_supp:format_warnings([{"file.erl", [{42, module, "Sample warning"}]}]))),
    ?assertEqual("file.erl:42: Warning: Unknown error: \"Sample warning\"\n",
                 lists:flatten(pt_supp:format_warnings([{"file.erl", [{42, pt_supp, "Sample warning"}]}]))),
    ?assertEqual("file.erl:42: Warning: More than one function with name foo/2\n",
                 lists:flatten(pt_supp:format_warnings([{"file.erl", [{42, pt_supp, {many_func, foo, 2}}]}]))),
    ?assertEqual("file.erl:42: Warning: Variables ['A','C'] are unbound\n"
                 "file.erl:43: Warning: Bad param: 'B'\nfile2.erl:42: Warning: Unknown error: \"Sample warning\"\n",
                 lists:flatten(pt_supp:format_warnings([{"file.erl", [{42, pt_supp, {unbound_var, ['A', 'C']}},
                                                                      {43, pt_supp, {bad_param, 'B'}}]},
                                                        {"file2.erl", [{42, pt_supp, "Sample warning"}]}]))).

format_error_test() ->
    ?assertEqual("More than one function with name foo/1",
                 lists:flatten(pt_supp:format_error({many_func, foo, 1}))),
    ?assertEqual("Variables 'A' are unbound", lists:flatten(pt_supp:format_error({unbound_var, 'A'}))),
    ?assertEqual("Cant convert ast to string cause: reason",
                 lists:flatten(pt_supp:format_error({ast2str, reason}))),
    ?assertEqual("foo is not a valid term, cause: reason",
                 lists:flatten(pt_supp:format_error({bad_term, foo, reason}))),
    ?assertEqual("Cant convert string to ast cause: forget dot at the end of string: \"A\"",
                 lists:flatten(pt_supp:format_error({str2ast, miss_dot, "A"}))),
    ?assertEqual("Bad param: foo", lists:flatten(pt_supp:format_error({bad_param, foo}))),
    ?assertEqual("foo is undefined", lists:flatten(pt_supp:format_error({undef, foo}))),
    ?assertEqual("Function foo/3 already exists",
                 lists:flatten(pt_supp:format_error({fun_already_exists, foo, 3}))),
    ?assertEqual("Unhandled param in replace_function: foo",
                 lists:flatten(pt_supp:format_error({unhandled_replace_param, foo}))),
    ?assertEqual("Attribute \"module\" is not found in AST",
                 lists:flatten(pt_supp:format_error({get_module_name, not_found}))),
    ?assertEqual("Attribute \"file\" is not found in AST",
                 lists:flatten(pt_supp:format_error({get_file_name, not_found}))),
    ?assertEqual("Subtree is not found in AST: {match,1,{var,1,'A'},{atom,1,a}}",
                 lists:flatten(pt_supp:format_error({remove_subtree, not_found, str_to_ast("A = a.", 1)}))),
    ?assertEqual("Unknown error: unknown",
                 lists:flatten(pt_supp:format_error(unknown))).

print_error_test() ->
    ?assertEqual(?TEST_FILE ++ ":42: Error: Cant format_error cause function module:format_error/1 is undefined\n\"Sample error\"\n\n",
                 lists:flatten(pt_supp:print_error(test_ast(), {parse_error, {42, module, "Sample error"}}, fun io_lib:format/2))),
    ?assertEqual(":42: Error: Cant format_error cause function module:format_error/1 is undefined\n\"Sample error\"\n\n",
                 lists:flatten(pt_supp:print_error([], {parse_error, {42, module, "Sample error"}}, fun io_lib:format/2))),
    ?assertEqual("file.erl:42: error: Cant format_error cause function module:format_error/1 is undefined\n\"Sample error\"\nCallStack stack\n",
                 lists:flatten(pt_supp:print_error([], {error, {module, {"file.erl", 42}, "Sample error", {callstack, stack}}}, fun io_lib:format/2))),
    ?assertEqual("file.erl:42: internal_error: Cant format_error cause function module:format_error/1 is undefined\n"
                 "\"Sample error\"\nCallStack stack\n",
                 lists:flatten(pt_supp:print_error([], {internal_error, {module, {"file.erl", 42}, "Sample error", {callstack, stack}}},
                                                   fun io_lib:format/2))),
    ?assertEqual("Unknown error: unknown\n",
                 lists:flatten(pt_supp:print_error([], unknown, fun io_lib:format/2))).

format_str2ast_error_test() ->
    ?assertEqual("error when parsing string \"abcde\"\nparse_form: :42: Error: Unknown error: \"Sample error\"\n"
                 "parse_exprs: :42: Error: Unknown error: \"Sample error\"",
                 lists:flatten(pt_supp:format_str2ast_error("abcde", {parse_error, {42, pt_supp, "Sample error"},
                                                                      {42, pt_supp, "Sample error"}}))),
    ?assertEqual("error when parsing string \"abcde\":\n :1: Error: Unknown error: \"Sample error\"",
                 lists:flatten(pt_supp:format_str2ast_error("abcde", {scan_error, {1, pt_supp, "Sample error"}}))),
    ?assertEqual("forget dot at the end of string: \"A = a\"",
                 lists:flatten(pt_supp:format_str2ast_error("A = a", miss_dot))),
    ?assertEqual("bad format of str: abcde",
                 lists:flatten(pt_supp:format_str2ast_error("abcde", badformat))),
    ?assertEqual("unknown error unknown_error when parsing str: abcde",
                 lists:flatten(pt_supp:format_str2ast_error("abcde", unknown_error))).

is_var_name_test() ->
    ?assert(pt_supp:is_var_name("A")),
    ?assert(pt_supp:is_var_name("Abcde")),
    ?assertNot(pt_supp:is_var_name("A B")),
    ?assertNot(pt_supp:is_var_name("abc")),
    ?assertNot(pt_supp:is_var_name("foo()")).

list_map_test() ->
    ?assertEqual(str_to_ast("[a, b, c].", 42),
                 pt_supp:list_map(fun(E) -> E end, str_to_ast("[a, b, c].", 42))),
    ?assertNotEqual(str_to_ast("[a, b, c].", 123),
                    pt_supp:list_map(fun(E) -> E end, str_to_ast("[a, b, c].", 42))),
    ?assertEqual(str_to_ast("[2, 4, 6].", 42),
                 pt_supp:list_map(fun({integer, Line, Num}) -> {integer, Line, 2 * Num} end,
                                  str_to_ast("[1, 2, 3].", 42))),
    ?assertEqual(str_to_ast("[].", 1), pt_supp:list_map(fun(E) -> E end, str_to_ast("[].", 1))),
    ?assertThrow(_, pt_supp:list_map(fun(E) -> E end, str_to_ast("A = a.", 1))).

list_map_fold_test() ->
    ?assertEqual({str_to_ast("[a, b, c].", 42), 3},
                 pt_supp:list_map_fold(fun(AST, Acc) -> {AST, Acc + 1} end, 0, str_to_ast("[a, b, c].", 42))),
    ?assertNotEqual({str_to_ast("[a, b, c].", 123), 0},
                    pt_supp:list_map_fold(fun(AST, Acc) -> {AST, Acc} end, 0, str_to_ast("[a, b, c].", 42))),
    ?assertEqual({str_to_ast("[2, 4, 6, 8].", 42), 4},
                 pt_supp:list_map_fold(fun({integer, Line, Num}, Acc) -> {{integer, Line, 2 * Num}, Acc + 1} end,
                                       0, str_to_ast("[1, 2, 3, 4].", 42))),
    ?assertEqual({str_to_ast("[].", 42), 0},
                 pt_supp:list_map_fold(fun(AST, _Acc) -> {AST, 123} end, 0, str_to_ast("[].", 42))),
    ?assertThrow(_, pt_supp:list_map_fold(fun(AST, Acc) -> {AST, Acc} end, 0, str_to_ast("A = a.", 1))).

list_fold_test() ->
    ?assertEqual(42, pt_supp:list_fold(fun(_E, _L, _Acc) -> 42 end, 0,
                                       str_to_ast("[1, 2, 3, 4].", 1))),
    ?assertEqual(5, pt_supp:list_fold(fun(_E, _L, Acc) -> 1 + Acc end, 0,
                                      str_to_ast("[a, b, c, d, e].", 1))),
    ?assertEqual(42, pt_supp:list_fold(fun(_E, L, _Acc) -> L end, 0,
                                       str_to_ast("[a, b, c].", 42))),
    ?assertEqual([5, 4, 3, 2, 1],
                 pt_supp:list_fold(fun({integer, _L, E}, _L, Acc) -> [E|Acc] end, [],
                                   str_to_ast("[1, 2, 3, 4, 5].", 42))),
    ?assertEqual(1, pt_supp:list_fold(fun(_E, _L, _Acc) -> 0 end, 1,
                                      str_to_ast("[].", 42))),
    ?assertThrow(_, pt_supp:list_fold(fun(_E, _L, _Acc) -> 0 end, 0,
                                      str_to_ast("foo() -> ok.", 42))).

list_foldr_test() ->
    ?assertEqual(42, pt_supp:list_foldr(fun(_E, _L, _Acc) -> 42 end,
                                        0, str_to_ast("[1, 2, 3, 4].", 1))),
    ?assertEqual(5, pt_supp:list_foldr(fun(_E, _L, Acc) -> 1 + Acc end,
                                       0, str_to_ast("[a, b, c, d, e].", 1))),
    ?assertEqual(42, pt_supp:list_foldr(fun(_E, L, _Acc) -> L end,
                                        0, str_to_ast("[a, b, c].", 42))),
    ?assertEqual([1, 2, 3, 4, 5],
                 pt_supp:list_foldr(fun({integer, _L, E}, _L, Acc) -> [E|Acc] end,
                                    [], str_to_ast("[1, 2, 3, 4, 5].", 42))),
    ?assertEqual(1, pt_supp:list_foldr(fun(_E, _L, _Acc) -> 0 end,
                                       1, str_to_ast("[].", 42))),
    ?assertThrow(_, pt_supp:list_foldr(fun(_E, _L, _Acc) -> 0 end,
                                       0, str_to_ast("foo() -> ok.", 42))).

list_reverse_test() ->
    ?assertEqual(str_to_ast("[a, b, c, d].", 1),
                 pt_supp:list_reverse(str_to_ast("[d, c, b, a].", 1))),
    ?assertEqual(str_to_ast("[a].", 1),
                 pt_supp:list_reverse(str_to_ast("[a].", 1))),
    ?assertEqual(str_to_ast("[].", 1),
                 pt_supp:list_reverse(str_to_ast("[].", 1))),
    ?assertNotEqual(str_to_ast("[a, b].", 1),
                    pt_supp:list_reverse(str_to_ast("[a, b].", 1))),
    ?assertThrow(_, pt_supp:list_reverse(str_to_ast("-include(\"/a/b/c.hrl\").", 1))).

list_concat_test() ->
    ?assertEqual(str_to_ast("[a, b, c, d].", 1),
                 pt_supp:list_concat(str_to_ast("[a, b, c, d].", 1), str_to_ast("[].", 1))),
    ?assertEqual(str_to_ast("[a, b, c, d].", 1),
                 pt_supp:list_concat(str_to_ast("[].", 1), str_to_ast("[a, b, c, d].", 1))),
    ?assertEqual(str_to_ast("[a, b, c, d, c, d].", 1),
                 pt_supp:list_concat(str_to_ast("[a, b, c, d].", 1), str_to_ast("[c, d].", 1))),
    ?assertEqual(str_to_ast("[a, b].", 10),
                 pt_supp:list_concat(str_to_ast("[a, b].", 10), str_to_ast("[].", 20))),
    ?assertEqual(str_to_ast("[a, b, c, d].", 10),
                 pt_supp:list_concat(str_to_ast("[a, b].", 10), str_to_ast("[c, d].", 20))),
    ?assertEqual(str_to_ast("[].", 1),
                 pt_supp:list_concat(str_to_ast("[].", 1), str_to_ast("[].", 1))),
    ?assertThrow({error, _}, pt_supp:list_concat(str_to_ast("A.", 1), str_to_ast("[a, b].", 1))),
    ?assertEqual(str_to_ast("[a, b | c].", 1), pt_supp:list_concat(str_to_ast("[a, b].", 1), str_to_ast("c.", 1))),
    ?assertEqual(str_to_ast("[a, b | _].", 1), pt_supp:list_concat(str_to_ast("[a, b].", 1), str_to_ast("_.", 1))).

list_length_test() ->
    ?assertEqual(0, pt_supp:list_length(str_to_ast("[].", 1))),
    ?assertEqual(1, pt_supp:list_length(str_to_ast("[a].", 1))),
    ?assertEqual(5, pt_supp:list_length(str_to_ast("[a, b, c, d, e].", 1))).

match_test() ->
    ?assertEqual([str_to_ast("[].", 1)],
                 pt_supp:match(str_to_ast("[].", 1), fun(_AST) -> true end)),
    ?assertEqual(str_to_ast(["A = a.", "a.", "A."], 1),
                 pt_supp:match(str_to_ast("A = a.", 1), fun(_AST) -> true end)),
    ?assertEqual([],
                 pt_supp:match(str_to_ast("A = a.", 1), fun(_AST) -> false end)),
    ?assertEqual([str_to_ast("[a, b, c].", 1)],
                 pt_supp:match(str_to_ast(["-module(foo).", "[a, b, c]."], 1),
                               fun ({cons, _, _, _}) -> true;
                                   (_) -> false
                               end)).

compile_test() ->
    ?assertMatch({?TEST_MODULE, _}, pt_supp:compile(test_ast())),
    ?assertThrow({error, _}, pt_supp:compile(str_to_ast("A = a.", 1))).

compile_to_beam_test() ->
    try
        ?assertEqual(ok, pt_supp:compile_to_beam(test_ast(), "/tmp")),
        ?assert(filelib:is_file("/tmp/test.beam"))
    after
        file:delete("/tmp/test.beam")
    end,
    ?assertThrow({error, _}, pt_supp:compile_to_beam(pt_supp:set_module_name(test_ast(), test1), "\\")),
    ?assertError(_, pt_supp:compile_to_beam(str_to_ast("A = a.", 1), ".")).

compile_and_load_test() ->
    try
        ?assertEqual(ok, pt_supp:compile_and_load(pt_supp:set_module_name(test_ast(), test))),
        ?assert(erlang:module_loaded(test))
    after
        code:delete(test)
    end,
    ?assertMatch({error, {compile_error, foo, _Errors, _Warnings}},
                 pt_supp:compile_and_load([{attribute,1,module,foo}, {function,1,bar,0,[{error_clause,1,[],[],[{atom,1,ok}]}]}])).

create_clear_ast_test() ->
    ?assertEqual([{attribute, 1, module, foo}, {attribute, 2, export, []}, {eof, 3}],
                 pt_supp:create_clear_ast(foo)),
    ?assertThrow(_, pt_supp:create_clear_ast([foo])),
    ?assertThrow(_, pt_supp:create_clear_ast(123)).

string2atom_test() ->
    ?assertEqual(abc, pt_supp:string2atom("abc")),
    ?assertEqual(pt_supp:string2atom("Abc Def"), 'Abc Def').

mk_atom_test() ->
    ?assertEqual('', pt_supp:mk_atom("", "")),
    ?assertEqual('1', pt_supp:mk_atom("", 1)),
    ?assertEqual('', pt_supp:mk_atom("", '')),
    ?assertEqual(abc1, pt_supp:mk_atom("abc", 1)),
    ?assertEqual(abcde, pt_supp:mk_atom("abc", de)),
    ?assertEqual(abcde, pt_supp:mk_atom("abc", "de")).

is_term_test() ->
    ?assert(pt_supp:is_term(str_to_ast("''.", 1))),
    ?assert(pt_supp:is_term(str_to_ast("abc.", 1))),
    ?assert(pt_supp:is_term(str_to_ast("'Abc Def'.", 1))),
    ?assert(pt_supp:is_term(str_to_ast("\"abc\".", 1))),
    ?assert(pt_supp:is_term(str_to_ast("[a, b, c].", 1))),
    ?assert(pt_supp:is_term(str_to_ast("{a, b, c}.", 1))),
    ?assertNot(pt_supp:is_term(str_to_ast("foo() -> ok.", 1))),
    ?assertNot(pt_supp:is_term(str_to_ast(["a.", "b."], 1))),
    ?assertNot(pt_supp:is_term(str_to_ast("-module(foo).", 1))),
    ?assertNot(pt_supp:is_term(str_to_ast("A.", 1))).

is_term_or_var_test() ->
    ?assert(pt_supp:is_term_or_var(str_to_ast("a.", 1))),
    ?assert(pt_supp:is_term_or_var(str_to_ast("A.", 1))),
    ?assert(pt_supp:is_term_or_var(str_to_ast("123.", 1))),
    ?assertNot(pt_supp:is_term_or_var(str_to_ast(["-module(foo).", "-export([])."], 1))),
    ?assertNot(pt_supp:is_term_or_var(str_to_ast("A = a.", 1))).

replace_remote_call(Tree, {NewModule, NewFunction}) ->
    case Tree of
        {call, _N1, {remote, _N2, {atom, _N3, _Module}, {atom, _N4, _Function}}, _CallParameters} ->
            {call, _N1, {remote, _N2, {atom, _N3, NewModule}, {atom, _N4, NewFunction}}, _CallParameters};
        _ -> Tree
    end.

replace_call(Tree, NewFunction) ->
    case Tree of
        {call, _N1, {atom, _N4, _Function}, _CallParameters} ->
            {call, _N1, {atom, _N4, NewFunction}, _CallParameters};
        _ -> Tree
    end.

test_ast() ->
    [{attribute, 1, file, {?TEST_FILE, 1}}] ++
        str_to_ast(["-module(test).", "-export([f/0]).", "f() -> ok."], 1).

str_to_ast([], _Line) -> [];
str_to_ast([String|Tail], Line) when is_list(String) ->
    [str_to_ast(String, Line)|str_to_ast(Tail, Line)];
str_to_ast(String, Line) ->
    {ok, Forms} = pt_supp:str2ast(String, Line),
    case Forms of
        [AST] -> AST;
        _ -> Forms
    end.

-endif.