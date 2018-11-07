%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
-module(tplugins_rt).
-export([setup/1, files/0, run/1]).

-include_lib("eunit/include/eunit.hrl").

-define(COMPILE_ERROR,
        "ERROR: Plugin bad_plugin contains compilation errors:").

setup([Target]) ->
  retest_utils:load_module(filename:join(Target, "inttest_utils.erl")),
  ok.

files() ->
    [
     {copy, "rebar.config", "rebar.config"},
     {copy, "bad.config", "bad.config"},
     {copy, "fish.erl", "src/fish.erl"},
     {copy, "test_plugin.erl", "plugins/test_plugin.erl"},
     {copy, "bad_plugin.erl", "bad_plugins/bad_plugin.erl"},
     {create, "fwibble.test", <<"fwibble">>},
     {create, "ebin/fish.app", app(fish, [fish])}
    ] ++ inttest_utils:rebar_setup().

run(_Dir) ->
    ?assertMatch({ok, _}, retest_sh:run("./rebar fwibble -v", [])),
    ?assertEqual(false, filelib:is_regular("fwibble.test")),
    Ref = retest:sh("./rebar -C bad.config -v clean", [{async, true}]),
    {ok, _} = retest:sh_expect(Ref, ".*ERROR: .*Plugin .*bad_plugin.erl "
                               "contains compilation errors:.*",
                               [{newline, any}]),
    ok.

%%
%% Generate the contents of a simple .app file
%%
app(Name, Modules) ->
    App = {application, Name,
           [{description, atom_to_list(Name)},
            {vsn, "1"},
            {modules, Modules},
            {registered, []},
            {applications, [kernel, stdlib]}]},
    io_lib:format("~p.\n", [App]).
