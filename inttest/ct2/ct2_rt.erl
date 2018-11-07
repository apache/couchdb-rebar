%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
-module(ct2_rt).

-export([setup/1, files/0, run/1]).

setup([Target]) ->
  retest_utils:load_module(filename:join(Target, "inttest_utils.erl")),
  ok.

files() ->
    [
     {create, "ebin/foo.app", app(foo)},
     {copy, "foo.test.spec", "foo.test.spec"},
     {copy, "deps/bar.test.spec", "deps/bar.test.spec"},
     {copy, "foo_SUITE.erl", "test/foo_SUITE.erl"}
    ] ++ inttest_utils:rebar_setup().

run(_Dir) ->
    Ref = retest:sh("./rebar compile ct -vvv", [async]),
    {ok, [[CTRunCmd]]} = retest:sh_expect(Ref, "^\"ct_run.*",
                                  [global, {capture, first, binary}]),
    {match, _} = re:run(CTRunCmd, "foo.test.spec", [global]),
    %% deps/bar.test.spec should be ignored by rebar_ct:collect_glob/3
    nomatch = re:run(CTRunCmd, "bar.test.spec", [global]),
    ok.

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
