%%--------------------------------------------------------------------
%% Copyright (c) 2020 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_bridge_nats).

-include("emqx.hrl").
-include("emqx_bridge_nats.hrl").

-export([ load/1
        , unload/0
        ]).

%% Client Lifecircle Hooks
-export([on_client_connected/3
        , on_client_disconnected/4
        ]).

%% Session Lifecircle Hooks
-export([on_session_subscribed/4
        , on_session_unsubscribed/4
        ]).

%% Message Pubsub Hooks
-export([on_message_publish/2
        , on_message_delivered/3
        , on_message_acked/3
        , on_message_dropped/4
        ]).

%-record(state, {conn}).

%% Called when the plugin application start
load(Env) ->
    {ok, Conn} = teacup_init(Env),
    ets:new(app_data, [named_table, protected, set, {keypos, 1}]),
    ets:insert(app_data, {nats_conn, Conn}),
    emqx:hook('client.connected',    {?MODULE, on_client_connected, [Env]}),
    emqx:hook('client.disconnected', {?MODULE, on_client_disconnected, [Env]}),
    emqx:hook('session.subscribed',  {?MODULE, on_session_subscribed, [Env]}),
    emqx:hook('session.unsubscribed',{?MODULE, on_session_unsubscribed, [Env]}),
    emqx:hook('message.publish',     {?MODULE, on_message_publish, [Env]}),
    emqx:hook('message.delivered',   {?MODULE, on_message_delivered, [Env]}),
    emqx:hook('message.acked',       {?MODULE, on_message_acked, [Env]}),
    emqx:hook('message.dropped',     {?MODULE, on_message_dropped, [Env]}).

%%--------------------------------------------------------------------
%% Client Lifecircle Hooks
%%--------------------------------------------------------------------

on_client_connected(ClientInfo = #{clientid := ClientId}, ConnInfo, _Env) ->
%    io:format("Client(~s) connected, ClientInfo:~n~p~n, ConnInfo:~n~p~n", [ClientId, ClientInfo, ConnInfo]),
    Event = [{action, <<"connected">>}, {clientId, ClientId}],
    PublishTopic = <<"iotpaas.devices.connected">>,
    publish_to_nats(Event, PublishTopic).


on_client_disconnected(ClientInfo = #{clientid := ClientId}, ReasonCode, ConnInfo, _Env) ->
%    io:format("Client(~s) disconnected due to ~p, ClientInfo:~n~p~n, ConnInfo:~n~p~n", [ClientId, ReasonCode, ClientInfo, ConnInfo]),
    Event = [{action, <<"disconnected">>}, {clientId, ClientId}, {reasonCode, ReasonCode}],
    PublishTopic = <<"iotpaas.devices.disconnected">>,
    publish_to_nats(Event, PublishTopic).

%%--------------------------------------------------------------------
%% Session Lifecircle Hooks
%%--------------------------------------------------------------------

on_session_subscribed(#{clientid := ClientId}, Topic, SubOpts, _Env) ->
%    io:format("Session(~s) subscribed ~s with subOpts: ~p~n", [ClientId, Topic, SubOpts]),
    Event = [{action, <<"subscribe">>}, {clientId, ClientId}, {topic, Topic}],
    PublishTopic = <<"iotpaas.devices.subscribed">>,
    publish_to_nats(Event, PublishTopic).

on_session_unsubscribed(#{clientid := ClientId}, Topic, Opts, _Env) ->
%    io:format("Session(~s) unsubscribed ~s with opts: ~p~n", [ClientId, Topic, Opts]),
    Event = [{action, <<"unsubscribe">>}, {clientId, ClientId}, {topic, Topic}],
    PublishTopic = <<"iotpaas.devices.unsubscribed">>,
    publish_to_nats(Event, PublishTopic).

%%--------------------------------------------------------------------
%% Message PubSub Hooks
%%--------------------------------------------------------------------

%% Transform message and return
on_message_publish(Message = #message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};

on_message_publish(Message = #message{topic = <<"/bootstrapping", _/binary>>}, _Env) ->
    io:format("Publish ~s~n", [emqx_message:format(Message)]),
    io:format("Username ~s~n", [maybe(emqx_message:get_header(username, Message))]),
    {ok, Message}.

on_message_publish(Message, _Env) ->
%    io:format("Publish ~s~n", [emqx_message:format(Message)]),
    {ok, Payload} = format_payload(Message, <<"message_publish">>),
    PublishTopic = <<"iotpaas.devices.message">>,
    publish_to_nats(Payload, PublishTopic),
    {ok, Message}.

on_message_dropped(#message{topic = <<"$SYS/", _/binary>>}, _By, _Reason, _Env) ->
    ok;
on_message_dropped(Message, _By = #{node := Node}, Reason, _Env) ->
%    io:format("Message dropped by node ~s due to ~s: ~s~n", [Node, Reason, emqx_message:format(Message)]),
    {ok, Payload} = format_payload(Message, <<"message_dropped">>),
    PublishTopic = <<"iotpaas.devices.dropped">>,
    publish_to_nats(Payload, PublishTopic).

on_message_delivered(_ClientInfo = #{clientid := ClientId}, Message, _Env) ->
%    io:format("Message delivered to client(~s): ~s~n", [ClientId, emqx_message:format(Message)]),
    {ok, Payload} = format_payload(Message, <<"message_delivered">>),
    PublishTopic = <<"iotpaas.devices.delivered">>,
    publish_to_nats(Payload, PublishTopic),
    {ok, Message}.

on_message_acked(_ClientInfo = #{clientid := ClientId}, Message, _Env) ->
%    io:format("Message acked by client(~s): ~s~n", [ClientId, emqx_message:format(Message)]),
    {ok, Payload} = format_payload(Message, <<"message_acked">>),
    PublishTopic = <<"iotpaas.devices.acked">>,
    publish_to_nats(Payload, PublishTopic).


teacup_init(_Env) ->
    {ok, _} = application:ensure_all_started(teacup_nats),
    NatsAddress = application:get_env(emqx_bridge_nats, address, "127.0.0.1"),
    NatsPort = application:get_env(emqx_bridge_nats, port, 4222),
    PoolOpts = [{address, NatsAddress}, {port, NatsPort}],
    {ok, Conn} = nats:connect(list_to_binary(proplists:get_value(address,  PoolOpts)), proplists:get_value(port,  PoolOpts)),
    {ok, Conn}.

publish_to_nats(Message, Topic) ->
    [{_, Conn}] = ets:lookup(app_data, nats_conn),
    nats:pub(Conn, Topic, #{payload => emqx_json:encode(Message)}),
    ok.

format_payload(Message, Action) ->
    <<T1:64, T2:48, T3:16>> = Message#message.id,
    Payload = [
        {id, T1 + T2 + T3},
        {action, Action},
        {qos, Message#message.qos},
        {clientId, Message#message.from},
        {topic, Message#message.topic},
        {payload, Message#message.payload},
        {time, erlang:system_time(Message#message.timestamp)}
    ],
    {ok, Payload}.

%% Called when the plugin application stop
unload() ->
    emqx:unhook('client.connected',    {?MODULE, on_client_connected}),
    emqx:unhook('client.disconnected', {?MODULE, on_client_disconnected}),
    emqx:unhook('session.subscribed',  {?MODULE, on_session_subscribed}),
    emqx:unhook('session.unsubscribed',{?MODULE, on_session_unsubscribed}),
    emqx:unhook('message.publish',     {?MODULE, on_message_publish}),
    emqx:unhook('message.delivered',   {?MODULE, on_message_delivered}),
    emqx:unhook('message.acked',       {?MODULE, on_message_acked}),
    emqx:unhook('message.dropped',     {?MODULE, on_message_dropped}).

