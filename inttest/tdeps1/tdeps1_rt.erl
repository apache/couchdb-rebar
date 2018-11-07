%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
-module(tdeps1_rt).

-export([setup/1, files/0, run/1]).

setup([Target]) ->
  retest_utils:load_module(filename:join(Target, "inttest_utils.erl")),
  ok.

%% Exercise transitive dependencies
%% A -> B -> C, where A includes a .hrl from B which includes .hrl from C
files() ->
    [
     %% A application
     {create, "ebin/a.app", app(a, [a])},
     {copy, "a.rebar.config", "rebar.config"},
     {copy, "a.erl", "src/a.erl"},

     %% B application
     {create, "repo/b/ebin/b.app", app(b, [])},
     {copy, "b.rebar.config", "repo/b/rebar.config"},
     {copy, "b.hrl", "repo/b/include/b.hrl"},

     %% C application
     {create, "repo/c/ebin/c.app", app(c, [])},
     {copy, "c.hrl", "repo/c/include/c.hrl"}
    ] ++ inttest_utils:rebar_setup().

apply_cmds([], _Params) ->
    ok;
apply_cmds([Cmd | Rest], Params) ->
    io:format("Running: ~s (~p)\n", [Cmd, Params]),
    {ok, _} = retest_sh:run(Cmd, Params),
    apply_cmds(Rest, Params).

run(_Dir) ->
    %% Initialize the b/c apps as git repos so that dependencies pull
    %% properly
    GitCmds = ["git init",
               "git add -A",
               "git config user.email 'tdeps@example.com'",
               "git config user.name 'tdeps'",
               "git commit -a -m \"Initial Commit\""],
    apply_cmds(GitCmds, [{dir, "repo/b"}]),
    apply_cmds(GitCmds, [{dir, "repo/c"}]),

    {ok, _} = retest_sh:run("./rebar get-deps", []),
    {ok, _} = retest_sh:run("./rebar compile", []),

    true = filelib:is_regular("ebin/a.beam"),
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
