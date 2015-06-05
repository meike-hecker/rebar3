-module(rebar_hooks_SUITE).

-export([suite/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2,
         all/0,
         build_and_clean_app/1,
         escriptize_artifacts/1,
         run_hooks_once/1,
         run_hooks_for_plugins/1,
         deps_hook_namespace/1]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/file.hrl").

suite() ->
    [].

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    meck:unload().

init_per_testcase(_, Config) ->
    rebar_test_utils:init_rebar_state(Config).

end_per_testcase(_, _Config) ->
    catch meck:unload().

all() ->
    [build_and_clean_app, run_hooks_once, escriptize_artifacts,
     run_hooks_for_plugins, deps_hook_namespace].

%% Test post provider hook cleans compiled project app, leaving it invalid
build_and_clean_app(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),
    rebar_test_utils:run_and_check(Config, [], ["compile"], {ok, [{app, Name, valid}]}),
    rebar_test_utils:run_and_check(Config, [{provider_hooks, [{post, [{compile, clean}]}]}],
                                  ["compile"], {ok, [{app, Name, invalid}]}).

escriptize_artifacts(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    Artifact = "bin/"++Name,
    RConfFile =
        rebar_test_utils:create_config(AppDir,
                                       [
                                       {escript_name, list_to_atom(Name)}
                                       ,{artifacts, [Artifact]}
                                       ]),
    {ok, RConf} = file:consult(RConfFile),

    try rebar_test_utils:run_and_check(Config, RConf, ["compile"], return)
    catch
        {error,
         {rebar_prv_compile,
          {missing_artifact, Artifact}}} ->
            ok
    end,
    rebar_test_utils:run_and_check(Config, RConf++[{provider_hooks, [{post, [{compile, escriptize}]}]}],
                                  ["compile"], {ok, [{app, Name, valid}
                                                    ,{file, filename:join([AppDir, "_build/default/", Artifact])}]}).

run_hooks_once(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),
    RebarConfig = [{pre_hooks, [{compile, "mkdir blah"}]}],
    rebar_test_utils:create_config(AppDir, RebarConfig),
    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),
    rebar_test_utils:run_and_check(Config, RebarConfig, ["compile"], {ok, [{app, Name, valid}]}).

deps_hook_namespace(Config) ->
    mock_git_resource:mock([{deps, [{some_dep, "0.0.1"}]}]),
    Deps = rebar_test_utils:expand_deps(git, [{"some_dep", "0.0.1", []}]),
    TopDeps = rebar_test_utils:top_level_deps(Deps),

    RebarConfig = [
        {deps, TopDeps},
        {overrides, [
            {override, some_dep, [
                {provider_hooks, [
                    {pre, [
                        {compile, clean}
                    ]}
                ]}
            ]}
        ]}
    ],
    rebar_test_utils:run_and_check(
        Config, RebarConfig, ["compile"],
        {ok, [{dep, "some_dep"}]}
    ).

run_hooks_for_plugins(Config) ->
    AppDir = ?config(apps, Config),

    Name = rebar_test_utils:create_random_name("app1_"),
    Vsn = rebar_test_utils:create_random_vsn(),

    rebar_test_utils:create_app(AppDir, Name, Vsn, [kernel, stdlib]),

    PluginName = rebar_test_utils:create_random_name("plugin1_"),
    mock_git_resource:mock([{config, [{pre_hooks, [{compile, "echo whatsup > randomfile"}]}]}]),

    RConfFile = rebar_test_utils:create_config(AppDir,
                                               [{plugins, [
                                                          {list_to_atom(PluginName),
                                                          {git, "http://site.com/user/"++PluginName++".git",
                                                          {tag, Vsn}}}
                                                          ]}]),
    {ok, RConf} = file:consult(RConfFile),

    rebar_test_utils:run_and_check(Config, RConf, ["compile"], {ok, [{app, Name, valid},
                                                                     {plugin, PluginName},
                                                                     {file, filename:join([AppDir, "_build", "default", "plugins", PluginName, "randomfile"])}]}).
