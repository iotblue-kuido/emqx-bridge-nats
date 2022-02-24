-module(emqx_bridge_nats_conn).

-behavihour(ecpool_worker).

-include("emqx_bridge_nats.hrl").

-export([connect/1]).
-export([publish/2]).

connect(Opts) ->
    case emqx_bridge_nats_driver:start_link(Opts) of
        {ok, Pid} ->
            {ok, Pid};
        {error, Reason} ->
            io:format("[NATS] Can't connect to NATS server: ~p~n", [Reason]),
            {error, Reason}
    end.

publish(Payload, Topic) ->
    ecpool:with_client(?APP, fun(DriverPid) ->
        ok = gen_server:call(DriverPid, {Payload, Topic}, 1000)
    end).