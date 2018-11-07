%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
-module(eunit_rt).
-export([files/0, run/1]).

-include_lib("eunit/include/eunit.hrl").

setup([Target]) ->
  retest_utils:load_module(filename:join(Target, "inttest_utils.erl")),
  ok.

files() ->
    [
     {create, "ebin/foo.app", app(foo)},
     {copy, "src", "src"},
     {copy, "eunit_src", "eunit_src"},
     {copy,
      "rebar-eunit_compile_opts.config",
      "rebar-eunit_compile_opts.config"}
    ] ++ inttest_utils:rebar_setup().

run(_Dir) ->
    ifdef_test(),
    eunit_compile_opts_test(),
    ok.

ifdef_test() ->
    {ok, Output} = retest:sh("./rebar -v eunit"),
    ?assert(check_output(Output, "foo_test")),
    ?assertMatch({ok, _}, retest:sh("./rebar clean")).

eunit_compile_opts_test() ->
    {ok, Output} =
        retest:sh("./rebar -v -C rebar-eunit_compile_opts.config eunit"),
    ?assert(check_output(Output, "bar_test")),
    ?assertMatch(
       {ok, _},
       retest:sh("./rebar -C rebar-eunit_compile_opts.config clean")).

check_output(Output, Target) ->
    lists:any(fun(Line) ->
                      string:str(Line, Target) > 0
              end, Output).

%%
%% Generate the contents of a simple .app file
%%
app(Name) ->
    App = {application, Name,
           [{description, atom_to_list(Name)},
            {vsn, "1"},
            {modules, []},
            {registered, []},
            {applications, [kernel, stdlib]}]},
    io_lib:format("~p.\n", [App]).
