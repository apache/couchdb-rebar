%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
-module(t_custom_config_rt).

-export([setup/1, files/0, run/1]).

-include_lib("eunit/include/eunit.hrl").

setup([Target]) ->
  retest_utils:load_module(filename:join(Target, "inttest_utils.erl")),
  ok.

files() ->
    [
     {copy, "custom.config", "custom.config"},
     {create, "ebin/custom_config.app", app(custom_config, [custom_config])}
    ] ++ inttest_utils:rebar_setup().

run(Dir) ->
    retest_log:log(debug, "Running in Dir: ~s~n", [Dir]),
    Ref = retest:sh("./rebar -C custom.config check-deps -vv",
                    [{async, true}]),

    {ok, Captured} =
        retest:sh_expect(Ref,
                         ".*DEBUG: .*Consult config file .*/custom.config.*",
                         [{capture, all, list}]),
    {ok, Missing} =
        retest:sh_expect(Ref,
                         ".*DEBUG: .*Missing deps  : \\[\\{dep,bad_name,"
                         "boo,\"\\.\",undefined,false\\}\\]",
                         [{capture, all, list}]),
    retest_log:log(debug, "[CAPTURED]: ~s~n", [Captured]),
    retest_log:log(debug, "[Missing]: ~s~n", [Missing]),
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
