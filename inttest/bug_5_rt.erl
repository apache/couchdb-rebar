%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
-module(bug_5_rt).

-export([setup/1, files/0, run/1]).

setup([Target]) ->
  retest_utils:load_module(filename:join(Target, "inttest_utils.erl")),
  ok.

files() ->
    [{create, "ebin/a1.app", app(a1)},
     {create, "deps/d1/src/d1.app.src", app(d1)},
     {create, "rebar.config",
      <<"{deps, [{d1, \"1\", {hg, \"http://example.com\", \"tip\"}}]}.\n">>}
    ] ++ inttest_utils:rebar_setup("..").

run(_Dir) ->
    {ok, _} = retest:sh("./rebar compile"),
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
