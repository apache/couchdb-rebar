%% -*- erlang-indent-level: 4;indent-tabs-mode: nil -*-
%% ex: ts=4 sw=4 et
%% -------------------------------------------------------------------
%%
%% rebar: Erlang Build Tools
%%
%% Copyright (c) 2009 Dave Smith (dizzyd@dizzyd.com)
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
-module(rebar).

-export([main/1,
         run/2,
         help/0,
         parse_args/1,
         version/0,
         get_jobs/1]).

-include("rebar.hrl").

-ifndef(BUILD_TIME).
-define(BUILD_TIME, "undefined").
-endif.

-ifndef(VCS_INFO).
-define(VCS_INFO, "undefined").
-endif.

-ifndef(OTP_INFO).
-define(OTP_INFO, "undefined").
-endif.

-define(DEFAULT_JOBS, 3).

%% ====================================================================
%% Public API
%% ====================================================================

%% escript Entry point
main(Args) ->
    case catch(run(Args)) of
        ok ->
            ok;
        rebar_abort ->
            rebar_utils:delayed_halt(1);
        Error ->
            %% Nothing should percolate up from rebar_core;
            %% Dump this error to console
            io:format("Uncaught error in rebar_core: ~p\n", [Error]),
            rebar_utils:delayed_halt(1)
    end.

%% Erlang-API entry point
run(BaseConfig, Commands) ->
    _ = application:load(rebar),
    run_aux(BaseConfig, Commands).

%% ====================================================================
%% Internal functions
%% ====================================================================

run(["help"|RawCmds]) when RawCmds =/= [] ->
    ok = load_rebar_app(),
    Cmds = unabbreviate_command_names(RawCmds),
    Args = parse_args(Cmds),
    BaseConfig = init_config(Args),
    {BaseConfig1, _} = save_options(BaseConfig, Args),
    BaseConfig2 = init_config1(BaseConfig1),
    rebar_core:help(BaseConfig2, [list_to_atom(C) || C <- Cmds]);
run(["help"]) ->
    help();
run(["info"|_]) ->
    %% Catch calls to 'rebar info' to avoid treating plugins' info/2 functions
    %% as commands.
    ?CONSOLE("Command 'info' not understood or not applicable~n", []);
run(["version"]) ->
    ok = load_rebar_app(),
    %% Display vsn and build time info
    version();
run(RawArgs) ->
    ok = load_rebar_app(),
    %% Parse out command line arguments -- what's left is a list of commands to
    %% run -- and start running commands
    Args = parse_args(RawArgs),
    BaseConfig = init_config(Args),
    {BaseConfig1, Cmds} = save_options(BaseConfig, Args),

    case rebar_config:get_xconf(BaseConfig1, enable_profiling, false) of
        true ->
            ?CONSOLE("Profiling!\n", []),
            profile(BaseConfig1, Cmds);
        false ->
            run_aux(BaseConfig1, Cmds)
    end.

load_rebar_app() ->
    %% Pre-load the rebar app so that we get default configuration
    ok = application:load(rebar).

init_config({Options, _NonOptArgs}) ->
    %% If $HOME/.rebar/config exists load and use as global config
    GlobalConfigFile = filename:join([os:getenv("HOME"), ".rebar", "config"]),
    GlobalConfig = case filelib:is_regular(GlobalConfigFile) of
                       true ->
                           ?DEBUG("Load global config file ~p~n",
                                  [GlobalConfigFile]),
                           rebar_config:new(GlobalConfigFile);
                       false ->
                           rebar_config:new()
                   end,

    %% Set the rebar config to use
    GlobalConfig1 = case proplists:get_value(config, Options) of
                        undefined ->
                            GlobalConfig;
                        Conf ->
                            rebar_config:set_global(GlobalConfig, config, Conf)
                    end,

    GlobalConfig2 = set_log_level(GlobalConfig1, Options),
    %% Initialize logging system
    ok = rebar_log:init(GlobalConfig2),

    BaseConfig = rebar_config:base_config(GlobalConfig2),

    %% Keep track of how many operations we do, so we can detect bad commands
    BaseConfig1 = rebar_config:set_xconf(BaseConfig, operations, 0),
    %% Initialize vsn cache
    rebar_utils:init_vsn_cache(BaseConfig1).

init_config1(BaseConfig) ->
    %% Determine the location of the rebar executable; important for pulling
    %% resources out of the escript
    ScriptName = filename:absname(escript:script_name()),
    BaseConfig1 = rebar_config:set_xconf(BaseConfig, escript, ScriptName),
    ?DEBUG("Rebar location: ~p\n", [ScriptName]),
    %% Note the top-level directory for reference
    AbsCwd = filename:absname(rebar_utils:get_cwd()),
    rebar_config:set_xconf(BaseConfig1, base_dir, AbsCwd).

profile(BaseConfig1, Commands) ->
    Profiler = rebar_config:get_global(BaseConfig1, profiler, "fprof"),
    profile(BaseConfig1, Commands, list_to_atom(Profiler)).

profile(Config, Commands, fprof) ->
    try
        fprof:apply(fun run_aux/2, [Config, Commands])
    after
        ok = fprof:profile(),
        ok = fprof:analyse([{dest, "fprof.analysis"}]),
        case rebar_utils:find_executable("erlgrind") of
            false ->
                ?CONSOLE(
                   "See fprof.analysis (generated from fprof.trace)~n", []),
                ok;
            ErlGrind ->
                Cmd = ?FMT("~s fprof.analysis fprof.cgrind", [ErlGrind]),
                {ok, []} = rebar_utils:sh(Cmd, [{use_stdout, false},
                                                abort_on_error]),
                ?CONSOLE("See fprof.analysis (generated from fprof.trace)"
                         " and fprof.cgrind~n", []),
                ok
        end
    end;
profile(Config, Commands, eflame) ->
    case code:lib_dir(eflame) of
        {error, bad_name} ->
            ?ABORT("eflame not found in code path~n", []),
            ok;
        EflameDir ->
            Trace = "eflame.trace",
            try
                eflame:apply(normal_with_children, Trace,
                             rebar, run, [Config, Commands])
            after
                %% generate flame graph
                Script = filename:join(EflameDir, "stack_to_flame.sh"),
                Svg = "eflame.svg",
                %% stack_to_flame.sh < eflame.trace > eflame.png
                Cmd = ?FMT("~s < ~s > ~s", [Script, Trace, Svg]),
                {ok, []} = rebar_utils:sh(Cmd, [{use_stdout, false},
                                                abort_on_error]),
                ?CONSOLE("See eflame.svg (generated from eflame.trace)~n", []),
                ok
            end
    end;
profile(_Config, _Commands, Profiler) ->
    ?ABORT("Unsupported profiler: ~s~n", [Profiler]).

run_aux(BaseConfig, Commands) ->
    %% Make sure crypto is running
    case application:start(crypto) of
        ok -> ok;
        {error,{already_started,crypto}} -> ok
    end,

    %% Make sure memoization server is running
    case rmemo:start() of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end,

    %% Make sure rebar_rnd module is generated, compiled, and loaded
    {ok, rebar_rnd} = rebar_rand_compat:init("rebar_rnd"),

    %% Convert command strings to atoms
    CommandAtoms = [list_to_atom(C) || C <- Commands],

    BaseConfig1 = init_config1(BaseConfig),

    %% Process each command, resetting any state between each one
    rebar_core:process_commands(CommandAtoms, BaseConfig1).

%%
%% print help/usage string
%%
help() ->
    OptSpecList = option_spec_list(),
    rebar_getopt:usage(OptSpecList, "rebar",
                       "[var=value,...] <command,...>",
                       [{"var=value", "rebar global variables (e.g. force=1)"},
                        {"command", "Command to run (e.g. compile)"}]),

    ?CONSOLE("To see a list of built-in commands, execute rebar -c.~n~n", []),
    ?CONSOLE(
       "Type 'rebar help <CMD1> <CMD2>' for help on specific commands."
       "~n~n", []),
    ?CONSOLE(
       "rebar allows you to abbreviate the command to run:~n"
       "$ rebar co           # same as rebar compile~n"
       "$ rebar eu           # same as rebar eunit~n"
       "$ rebar g-d          # same as rebar get-deps~n"
       "$ rebar x eu         # same as rebar xref eunit~n"
       "$ rebar l-d          # same as rebar list-deps~n"
       "$ rebar l-d l-t      # same as rebar list-deps list-templates~n"
       "$ rebar list-d l-te  # same as rebar list-deps list-templates~n"
       "~n", []),
    ?CONSOLE(
       "Core rebar.config options:~n"
       "  ~p~n"
       "  ~p~n"
       "  ~p~n"
       "  ~p~n"
       "  ~p~n"
       "  ~p~n"
       "  ~p~n"
       "  ~p~n"
       "  ~p~n"
       "  ~p~n"
       "Core command line options:~n"
       "  apps=app1,app2 (specify apps to process)~n"
       "  skip_apps=app1,app2 (specify apps to skip)~n",
       [
        {recursive_cmds, []},
        {require_erts_vsn, ".*"},
        {require_otp_vsn, ".*"},
        {require_min_otp_vsn, ".*"},
        {lib_dirs, []},
        {sub_dirs, ["dir1", "dir2"]},
        {plugins, [plugin1, plugin2]},
        {plugin_dir, "some_other_directory"},
        {pre_hooks, [{clean, "./prepare_package_files.sh"},
                     {"linux", compile, "c_src/build_linux.sh"},
                     {compile, "escript generate_headers"},
                     {compile, "escript check_headers"}]},
        {post_hooks, [{clean, "touch file1.out"},
                      {"freebsd", compile, "c_src/freebsd_tweaks.sh"},
                      {eunit, "touch file2.out"},
                      {compile, "touch postcompile.out"}]}
       ]),
    ?CONSOLE(
       "Environment variables:~n"
       "  REBAR_DEPS_PREFER_LIBS to look for dependecies in system libs prior fetching.~n"
       "  REBAR_VSN_CACHE_FILE to load vsn cache from and save to specified file.~n"
       "~n", []).

%%
%% Parse command line arguments using getopt and also filtering out any
%% key=value pairs. What's left is the list of commands to run
%%
parse_args(RawArgs) ->
    %% Parse getopt options
    OptSpecList = option_spec_list(),
    case rebar_getopt:parse(OptSpecList, RawArgs) of
        {ok, Args} ->
            Args;
        {error, {Reason, Data}} ->
            ?ERROR("~s ~p~n~n", [Reason, Data]),
            help(),
            rebar_utils:delayed_halt(1)
    end.

save_options(Config, {Options, NonOptArgs}) ->
    %% Check options and maybe halt execution
    ok = show_info_maybe_halt(Options, NonOptArgs),

    GlobalDefines = proplists:get_all_values(defines, Options),

    Config1 = rebar_config:set_xconf(Config, defines, GlobalDefines),

    %% Setup profiling flag
    Config2 = rebar_config:set_xconf(Config1, enable_profiling,
                                     proplists:get_bool(profile, Options)),

    %% Setup flag to keep running after a single command fails
    Config3 = rebar_config:set_xconf(Config2, keep_going,
                                     proplists:get_bool(keep_going, Options)),

    %% Setup flag to enable recursive application of commands
    Config4 = rebar_config:set_xconf(Config3, recursive,
                                     proplists:get_bool(recursive, Options)),

    %% Set global variables based on getopt options
    Config5 = set_global_flag(Config4, Options, force),
    Config6 = case proplists:get_value(jobs, Options, ?DEFAULT_JOBS) of
                  ?DEFAULT_JOBS ->
                      Config5;
                  Jobs ->
                      rebar_config:set_global(Config5, jobs, Jobs)
              end,

    %% Filter all the flags (i.e. strings of form key=value) from the
    %% command line arguments. What's left will be the commands to run.
    {Config7, RawCmds} = filter_flags(Config6, NonOptArgs, []),
    {Config7, unabbreviate_command_names(RawCmds)}.

%%
%% set log level based on getopt option
%%
set_log_level(Config, Options) ->
    {IsVerbose, Level} =
        case proplists:get_bool(quiet, Options) of
            true ->
                {false, rebar_log:error_level()};
            false ->
                DefaultLevel = rebar_log:default_level(),
                case proplists:get_all_values(verbose, Options) of
                    [] ->
                        {false, DefaultLevel};
                    Verbosities ->
                        {true, DefaultLevel + lists:last(Verbosities)}
                end
        end,

    case IsVerbose of
        true ->
            Config1 = rebar_config:set_xconf(Config, is_verbose, true),
            rebar_config:set_global(Config1, verbose, Level);
        false ->
            rebar_config:set_global(Config, verbose, Level)
    end.

%%
%% show version information and halt
%%
version() ->
    {ok, Vsn} = application:get_key(rebar, vsn),
    ?CONSOLE("rebar ~s ~s ~s ~s\n",
             [Vsn, ?OTP_INFO, ?BUILD_TIME, ?VCS_INFO]).


%%
%% set global flag based on getopt option boolean value
%%
set_global_flag(Config, Options, Flag) ->
    Value = case proplists:get_bool(Flag, Options) of
                true ->
                    "1";
                false ->
                    "0"
            end,
    rebar_config:set_global(Config, Flag, Value).

%%
%% show info and maybe halt execution
%%
show_info_maybe_halt(Opts, NonOptArgs) ->
    false = show_info_maybe_halt(help, Opts, fun help/0),
    false = show_info_maybe_halt(commands, Opts, fun commands/0),
    false = show_info_maybe_halt(version, Opts, fun version/0),
    case NonOptArgs of
        [] ->
            ?CONSOLE("No command to run specified!~n",[]),
            help(),
            rebar_utils:delayed_halt(1);
        _ ->
            ok
    end.

show_info_maybe_halt(O, Opts, F) ->
    case proplists:get_bool(O, Opts) of
        true ->
            F(),
            rebar_utils:delayed_halt(0);
        false ->
            false
    end.

%%
%% print known commands
%%
commands() ->
    S = <<"
clean                                    Clean
compile                                  Compile sources

escriptize                               Generate escript archive

create      template= [var=foo,...]      Create skel based on template and vars
create-app  [appid=myapp]                Create simple app skel
create-lib  [libid=mylib]                Create simple lib skel
create-node [nodeid=mynode]              Create simple node skel
list-templates                           List available templates

doc                                      Generate Erlang program documentation

prepare-deps                             Run 'rebar -r get-deps compile'
refresh-deps                             Run 'rebar -r update-deps compile'

check-deps                               Display to be fetched dependencies
get-deps                                 Fetch dependencies
update-deps                              Update fetched dependencies
delete-deps                              Delete fetched dependencies
list-deps                                List dependencies

generate    [dump_spec=0/1]              Build release with reltool
overlay                                  Run reltool overlays only

generate-upgrade  previous_release=path  Build an upgrade package

generate-appups   previous_release=path  Generate appup files

eunit       [suite[s]=foo]               Run EUnit tests in foo.erl and
                                         test/foo_tests.erl
            [suite[s]=foo] [test[s]=bar] Run specific EUnit tests [first test
                                         name starting with 'bar' in foo.erl
                                         and test/foo_tests.erl]
            [test[s]=bar]                For every existing suite, run the first
                                         test whose name starts with bar and, if
                                         no such test exists, run the test whose
                                         name starts with bar in the suite's
                                         _tests module.
            [random_suite_order=true]    Run tests in a random order, either
            [random_suite_order=Seed]    with a random seed for the PRNG, or a
                                         specific one.

ct          [suite[s]= [group[s]= [case[s]=]]] Run common_test suites

qc                                       Test QuickCheck properties

xref                                     Run cross reference analysis

dialyze                                  Analyze the code for discrepancies
build-plt                                Build project-specific PLT
check-plt                                Check the PLT for consistency and
                                         rebuild it if it is not up-to-date
delete-plt                               Delete project-specific PLT

shell                                    Start a shell similar to
                                         'erl -pa ebin -pa deps/*/ebin'

help                                     Show the program options
version                                  Show version information
">>,
    io:put_chars(S).

get_jobs(Config) ->
    rebar_config:get_global(Config, jobs, ?DEFAULT_JOBS).

%%
%% options accepted via getopt
%%
option_spec_list() ->
    Jobs = ?DEFAULT_JOBS,
    JobsHelp = io_lib:format(
                 "Number of concurrent workers a command may use. Default: ~B",
                 [Jobs]),
    [
     %% {Name, ShortOpt, LongOpt, ArgSpec, HelpMsg}
     {help,     $h, "help",     undefined, "Show the program options"},
     {commands, $c, "commands", undefined, "Show available commands"},
     {verbose,  $v, "verbose",  integer,   "Verbosity level (-v, -vv)"},
     {quiet,    $q, "quiet",    boolean,   "Quiet, only print error messages"},
     {version,  $V, "version",  undefined, "Show version information"},
     {force,    $f, "force",    undefined, "Force"},
     {defines,  $D, undefined,  string,    "Define compiler macro"},
     {jobs,     $j, "jobs",     integer,   JobsHelp},
     {config,   $C, "config",   string,    "Rebar config file to use"},
     {profile,  $p, "profile",  undefined,
      "Profile this run of rebar. Via profiler= you can optionally select "
      "either fprof (default) or eflame. The result can be found in "
      "fprof.analysis or eflame.svg. Additionally, in fprof mode, if "
      "erlgrind can be found in $PATH, a Cachegrind file (fprof.cgrind) "
      "will be generated as well."},
     {keep_going, $k, "keep-going", undefined,
      "Keep running after a command fails"},
     {recursive, $r, "recursive", boolean,
      "Apply all commands recursively. Alternatively, you can selectively"
      " configure what other commands in addition to the always-recursive"
      " ones (compile, *-deps) should also be applied recursively."
      " For example, to make 'eunit' recursive, add {recursive_cmds, [eunit]}"
      " to rebar.config."}
    ].

%%
%% Seperate all commands (single-words) from flags (key=value) and store
%% values into the rebar_config global storage.
%%
filter_flags(Config, [], Commands) ->
    {Config, lists:reverse(Commands)};
filter_flags(Config, [Item | Rest], Commands) ->
    case string:tokens(Item, "=") of
        [Command] ->
            filter_flags(Config, Rest, [Command | Commands]);
        [KeyStr, RawValue] ->
            Key = list_to_atom(KeyStr),
            Value = case Key of
                        verbose ->
                            list_to_integer(RawValue);
                        _ ->
                            RawValue
                    end,
            Config1 = rebar_config:set_global(Config, Key, Value),
            filter_flags(Config1, Rest, Commands);
        Other ->
            ?CONSOLE("Ignoring command line argument: ~p\n", [Other]),
            filter_flags(Config, Rest, Commands)
    end.

command_names() ->
    [
     "build-plt",
     "check-deps",
     "check-plt",
     "clean",
     "compile",
     "create",
     "create-app",
     "create-lib",
     "create-node",
     "ct",
     "delete-plt",
     "delete-deps",
     "dialyze",
     "doc",
     "eunit",
     "escriptize",
     "generate",
     "generate-appups",
     "generate-upgrade",
     "get-deps",
     "help",
     "list-deps",
     "list-templates",
     "prepare-deps",
     "qc",
     "refresh-deps",
     "update-deps",
     "overlay",
     "shell",
     "version",
     "xref"
    ].

unabbreviate_command_names([]) ->
    [];
unabbreviate_command_names([Command | Commands]) ->
    case get_command_name_candidates(Command) of
        [] ->
            %% let the rest of the code detect that the command doesn't exist
            %% (this would perhaps be a good place to fail)
            [Command | unabbreviate_command_names(Commands)];
        [FullCommand] ->
            [FullCommand | unabbreviate_command_names(Commands)];
        Candidates ->
            ?ABORT("Found more than one match for abbreviated command name"
                   " '~s',~nplease be more specific. Possible candidates:~n"
                   "  ~s~n",
                   [Command, string:join(Candidates, ", ")])
    end.

get_command_name_candidates(Command) ->
    %% Get the command names which match the given (abbreviated) command name.
    %% * "c"        matches commands like compile, clean and create-app
    %% * "create"   matches command create only, since it's unique
    %% * "create-"  matches commands starting with create-
    %% * "c-a"      matches create-app
    %% * "create-a" matches create-app
    %% * "c-app"    matches create-app
    Candidates = [Candidate || Candidate <- command_names(),
                               is_command_name_candidate(Command, Candidate)],
    %% Is there a complete match?  If so return only that, return a
    %% list of candidates otherwise
    case lists:member(Command, Candidates) of
        true  -> [Command];
        false -> Candidates
    end.

is_command_name_candidate(Command, Candidate) ->
    lists:prefix(Command, Candidate)
        orelse is_command_name_sub_word_candidate(Command, Candidate).

is_command_name_sub_word_candidate(Command, Candidate) ->
    %% Allow for parts of commands to be abbreviated, i.e. create-app
    %% can be shortened to "create-a", "c-a" or "c-app" (but not
    %% "create-" since that would be ambiguous).
    ReOpts = [{return, list}],
    CommandSubWords = re:split(Command, "-", ReOpts),
    CandidateSubWords = re:split(Candidate, "-", ReOpts),
    is_command_name_sub_word_candidate_aux(CommandSubWords, CandidateSubWords).

is_command_name_sub_word_candidate_aux([CmdSW | CmdSWs],
                                       [CandSW | CandSWs]) ->
    lists:prefix(CmdSW, CandSW) andalso
        is_command_name_sub_word_candidate_aux(CmdSWs, CandSWs);
is_command_name_sub_word_candidate_aux([], []) ->
    true;
is_command_name_sub_word_candidate_aux(_CmdSWs, _CandSWs) ->
    false.
