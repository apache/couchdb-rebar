%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
%% -------------------------------------------------------------------
%%
%% rebar: Erlang Build Tools
%%
%% Copyright (c) 2014 Vlad Dumitrescu
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.
%% -------------------------------------------------------------------
-module(app_src_script_rt).

-export([setup/1, files/0, run/1]).

-include_lib("eunit/include/eunit.hrl").

setup([Target]) ->
  retest_utils:load_module(filename:join(Target, "inttest_utils.erl")),
  ok.

files() ->
    [
     {create, "src/app_src_script.app.src.script", app_script(app_src_script)}
    ] ++ inttest_utils:rebar_setup().

run(Dir) ->
    retest_log:log(debug, "Running in Dir: ~s~n", [Dir]),
    {ok, [_Pid|Output]} = retest:sh("./rebar compile -vv",
                                    [{async, false}]),

    Regexp = "DEBUG: Evaluating config script .*/app_src_script\.app\.src\.script.*",
    ?assertEqual(true, has_line(Output, Regexp)),
    retest_log:log(debug, "Evaluated .app.src.script~n", []),

    %% check that ebin/app_src.app exists
    ?assertMatch(true, filelib:is_regular("ebin/app_src_script.app")),
    retest_log:log(debug, "Generated ebin/.app~n", []),

    %% check that ebin/.app has vsn="2"
    {ok, Bin} = file:read_file("ebin/app_src_script.app"),
    Str = binary_to_list(Bin),
    ?assertMatch({match, _}, re:run(Str, "{vsn, *\"2\"}")),
    retest_log:log(debug, "Variable replacement in .app is ok.~n", []),

    %% check that ebin/.app doesn't have foo=ok
    ?assertMatch(nomatch, re:run(Str, "{foo, *ok}")),
    retest_log:log(debug, "app.src hasn't 'foo' config.~n", []),

    ok.

has_line([], _RE) ->
    false;
has_line([L|T], RE) ->
    case re:run(L, RE, []) of
        {match, _Captured} ->
            true;
        match ->
            true;
        nomatch ->
            has_line(T, RE)
    end.

%%
%% Generate the contents of a simple .app.src.script file
%%
app_script(Name) ->
    "Vsn=\"2\".\n" ++
        "{application, " ++ atom_to_list(Name) ++ ",
           [{vsn, Vsn},
            {modules, []},
            {registered, []},
            {applications, [kernel, stdlib]}]}.\n".
