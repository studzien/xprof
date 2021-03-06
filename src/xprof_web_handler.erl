-module(xprof_web_handler).

-export([init/3,handle/2,terminate/3]).

-behavior(cowboy_http_handler).

%% Cowboy callbacks

init(_Type, Req, _Opts) ->
    {ok, Req, no_state}.

handle(Req, State) ->
    {What,_} = cowboy_req:binding(what, Req),
    handle_req(What, Req, State).

terminate(_Reason, _Req, _State) ->
    ok.

%% Private

%% Handling different HTTP requests

handle_req(<<"funs">>, Req, State) ->
    {Query, _} = cowboy_req:qs_val(<<"query">>, Req, <<"">>),

    Funs = lists:sort(xprof_vm_info:get_available_funs(Query)),
    Json = jsone:encode(Funs),

    lager:debug("Returning ~b functions matching phrase \"~s\"",
                [length(Funs), Query]),

    {ok, Req2} = cowboy_req:reply(200,
                                  [{<<"content-type">>,
                                    <<"application/json">>}],
                                  Json,
                                  Req),
    {ok, Req2, State};
handle_req(<<"mon_start">>, Req, State) ->
    Query = get_query(Req),
    lager:info("Starting monitoring via web on '~s'~n", [Query]),

    Req2 =
        case xprof_tracer:monitor(Query) of
            ok -> Req;
            {error, already_traced} -> Req;
            _Error ->
                {ok, ResReq} = cowboy_req:reply(400, Req),
                ResReq
        end,
    {ok, Req2, State};


handle_req(<<"mon_stop">>, Req, State) ->
    MFA = {M,F,A} = get_mfa(Req),

    lager:info("Stopping monitoring via web on ~w:~w/~w~n",[M,F,A]),

    xprof_tracer:demonitor(MFA),
    {ok, Req, State};

handle_req(<<"mon_get_all">>, Req, State) ->
    Funs = xprof_tracer:all_monitored(),
    FunsArr = [tuple_to_list(MFA) || MFA <- Funs],
    Json = jsone:encode(FunsArr),
    {ok, ResReq} = cowboy_req:reply(200,
                                    [{<<"content-type">>,
                                      <<"application/json">>}],
                                    Json, Req),
    {ok, ResReq, State};

handle_req(<<"data">>, Req, State) ->
    MFA = get_mfa(Req),
    {LastTS, _} = cowboy_req:qs_val(<<"last_ts">>, Req, <<"0">>),

    {ok, ResReq} =
        case xprof_tracer:data(MFA, binary_to_integer(LastTS)) of
            {error, not_found} ->
                cowboy_req:reply(404, Req);
            Vals ->
                Json = jsone:encode([{Val} || Val <- Vals]),

                cowboy_req:reply(200,
                                 [{<<"content-type">>,
                                   <<"application/json">>}],
                                 Json, Req)
        end,
    {ok, ResReq, State};

handle_req(<<"trace_set">>, Req, State) ->
    {Spec, _} = cowboy_req:qs_val(<<"spec">>, Req),

    {ok, ResReq} = case lists:member(Spec, [<<"all">>, <<"pause">>]) of
                       true ->
                           xprof_tracer:trace(list_to_atom(binary_to_list(Spec))),
                           cowboy_req:reply(200, Req);
                       false ->
                           lager:info("Wrong spec for tracing: ~p",[Spec]),
                           cowboy_req:reply(400, Req)
                   end,
    {ok, ResReq, State};

handle_req(<<"trace_status">>, Req, State) ->
    {_, Paused, _} = xprof_tracer:trace_status(),
    Json = jsone:encode({[{tracing, not Paused}]}),
    {ok, ResReq} = cowboy_req:reply(200,
                                    [{<<"content-type">>,
                                      <<"application/json">>}],
                                    Json, Req),

    {ok, ResReq, State};

handle_req(<<"capture">>, Req, State) ->
    MFA = {M,F,A} = get_mfa(Req),
    {ThresholdStr, _} = cowboy_req:qs_val(<<"threshold">>, Req),
    {LimitStr, _} = cowboy_req:qs_val(<<"limit">>, Req),
    Threshold = binary_to_integer(ThresholdStr),
    Limit = binary_to_integer(LimitStr),

    lager:info("Capture ~b calls to ~w:~w:~b~n exceeding ~b ms",
               [Limit ,M,F,A,Threshold]),

    {ok, CaptureId} = xprof_tracer_handler:capture(MFA, Threshold, Limit),
    Json = jsone:encode({[{capture_id, CaptureId}]}),

    {ok, ResReq} = cowboy_req:reply(200,
                                    [{<<"content-type">>,
                                      <<"application/json">>}], Json, Req),
    {ok, ResReq, State};
handle_req(<<"capture_stop">>, Req, State) ->
    MFA = get_mfa(Req),

    lager:info("Stopping slow calls capturing for ~p", [MFA]),

    {ok, ResReq} =
        case xprof_tracer_handler:capture_stop(MFA) of
            ok ->
                cowboy_req:reply(204, Req);
            {error, _Reason} ->
                cowboy_req:reply(500, Req)
        end,
    {ok, ResReq, State};
handle_req(<<"capture_data">>, Req, State) ->
    MFA  = get_mfa(Req),
    {OffsetStr, _} = cowboy_req:qs_val(<<"offset">>, Req),
    Offset = binary_to_integer(OffsetStr),

    {ok, ResReq} =
        case xprof_tracer_handler:get_captured_data(MFA, Offset) of
            {error, not_found} ->
                cowboy_req:reply(404, Req);
            {ok, {Id, Threshold, Limit, OriginalLimit}, Items} ->
                ItemsJson = [{args_res2proplist(Item)} || Item <- Items],
                Json = jsone:encode({[{capture_id, Id},
                                      {threshold, Threshold},
                                      {limit, OriginalLimit},
                                      {items, ItemsJson},
                                      {has_more, Offset + length(Items) < Limit}]}),
                cowboy_req:reply(200,
                                 [{<<"content-type">>,
                                   <<"application/json">>}],
                                 Json, Req)
        end,
    {ok, ResReq, State}.

%% Helpers

-spec get_mfa(cowboy:req()) -> xprof:mfaid().
get_mfa(Req) ->
    {Params, _} = cowboy_req:qs_vals(Req),
    {list_to_atom(binary_to_list(proplists:get_value(<<"mod">>, Params))),
     list_to_atom(binary_to_list(proplists:get_value(<<"fun">>, Params))),
     case proplists:get_value(<<"arity">>, Params) of
         <<"*">> -> '*';
         Arity -> binary_to_integer(Arity)
     end}.

-spec get_query(cowboy:req()) -> string().
get_query(Req) ->
    {Params, _} = cowboy_req:qs_vals(Req),
    binary_to_list(proplists:get_value(<<"query">>, Params)).

args_res2proplist([Id, Pid, CallTime, Args, Res]) ->
    [{id, Id},
     {pid, list_to_binary(io_lib:format("~p",[Pid]))},
     {call_time, CallTime},
     {args, list_to_binary(io_lib:format("~w",[Args]))},
     {res, list_to_binary(io_lib:format("~p",[Res]))}].
