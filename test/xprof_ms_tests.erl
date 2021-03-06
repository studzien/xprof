-module(xprof_ms_tests).

-include_lib("eunit/include/eunit.hrl").

-define(M, xprof_ms).

heuristic_test_() ->
    [?_assertEqual(
        {mfa, 'm.m', f, 1},
        ?M:fun2ms("m.m:f/1")),
     ?_assertEqual(
        {mfa, 'M@:f', f, 1},
        ?M:fun2ms("M@:f:f/1")),
     ?_assertMatch(
        {error,"expression is not an xprof match-spec fun" ++ _},
        ?M:fun2ms(":f/1")),
     ?_assertMatch(
        {error,"expression is not an xprof match-spec fun" ++ _},
        ?M:fun2ms("m:/1")),
     ?_assertEqual(
        {error,"syntax error before: '/' at column 4"},
        ?M:fun2ms("m:f/"))
    ].

tokens_test_() ->
    [?_assertEqual(
        {error,"expression is not an xprof match-spec fun []"},
        ?M:fun2ms("")),
     ?_assertEqual(
        {error,"unterminated atom starting with 'true' at column 16"},
        ?M:fun2ms("m:f(_) -> 'true")),
     ?_assertMatch(
        {error,"expression is not an xprof match-spec fun" ++ _},
        ?M:fun2ms("a+b"))
    ].

parse_test_() ->
    [?_assertEqual(
        {mfa, m, f, 1},
        ?M:fun2ms("m:f/1")),
     ?_assertEqual(
        {error,"syntax error before: 'end' at column 4"},
        ?M:fun2ms("m:f(")),
     ?_assertEqual(
        {error,"expression is not an xprof match-spec fun"},
        ?M:fun2ms("m:f f/1, begin true"))
    ].

ensure_dor_test_() ->
    MSs = {[{'_',[],[{return_trace},{message,arity},true]}],
           [{'_',[],[{return_trace},{message,'$_'},true]}]},
    [?_assertEqual(
        {ms, m, f, MSs},
        ?M:fun2ms("m:f(_) -> true")),
     ?_assertEqual(
        {ms, m, f, MSs},
        ?M:fun2ms("m:f(_) -> true.")),
     ?_assertEqual(
        {ms, m, f, MSs},
        ?M:fun2ms("m:f(_) -> true end."))
    ].

ms_test_() ->
    [?_assertEqual(
        {error,
         "dbg:fun2ms requires fun with single variable "
         "or list parameter at column 4"},
        ?M:fun2ms("m:f(A, B) -> {A, B}")),
    ?_assertEqual(
       {error,
        "in fun head, only matching (=) on toplevel can be translated "
        "into match_spec at column 8"},
        ?M:fun2ms("m:f([A = {B, _}]) -> {A, B}"))
    ].

traverse_ms_test_() ->

    MSs =
    {%% capture args off
      [%% false -> false: no trace
       {[a,'_'], [], [{return_trace},{message,arity},{message,false}]},
       %% true -> arity: trace without args
       {[b,'_'], [], [{return_trace},{message,arity},{message,arity}]},
       %% custom msg -> arity: trace without args
       {['_','$1'], [], [{return_trace},{message,arity},{message,arity}]}],
      %% capture args on
      [%% false -> false: no trace
       {[a,'_'], [], [{return_trace},{message,'$_'},{message,false}]},
       %% true -> '$_' aka object(): trace with all args
       {[b,'_'], [], [{return_trace},{message,'$_'},{message,'$_'}]},
       %% custom msg -> custom msg: trace with one arg only
       {['_','$1'], [], [{return_trace},{message,'$_'},{message,'$1'}]}]},

    [?_assertEqual(
        {ms, m, f, MSs},
        ?M:fun2ms("m:f([a, _]) -> message(false);"
                  "   ([b, _]) -> message(true);"
                  "   ([_, C]) -> message(C) end."))
    ].
