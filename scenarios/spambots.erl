%%==============================================================================
%% Copyright 2015 Erlang Solutions Ltd.
%% Licensed under the Apache License, Version 2.0 (see LICENSE file)
%%==============================================================================
-module(spambots).
-define(HOST, <<"localhost">>).
-behaviour(amoc_scenario).
-export([start/1]).
-export([init/0]).
-type binjid() :: binary().

-spec init() -> ok.
init() ->
    ok.

xmpp_server_dns_hostname() ->
    EnvVar = "CHAT_SERVER_HOSTNAME",
    case os:getenv(EnvVar) of
        V when is_list(V) -> list_to_binary(V);
        _ -> error(EnvVar ++ " not set")
    end.

-spec user_spec(binary(), binary(), binary()) -> escalus_users:user_spec().
user_spec(ProfileId, XMPPToken, Res) ->
    [ {username, ProfileId},
      {server, ?HOST},
      {host, xmpp_server_dns_hostname()},
      {password, XMPPToken},
      {carbons, false},
      {stream_management, false},
      {resource, Res}].

-spec make_user_cfg(amoc_scenario:user_id(), binary()) -> escalus_users:user_spec().
make_user_cfg(GeriId, R) ->
    BinId = integer_to_binary(GeriId),
    user_spec(BinId, BinId, R).

-spec start(amoc_scenario:user_id()) -> any().
start(MyId) ->
    _ = rand:seed(exs64),
    BehaviorModel = make_behavior_model(MyId),
    Cfg = make_user_cfg(MyId, <<"res1">>),
    {ok, Client, _} = escalus_connection:start(Cfg),
    send_presence_available(Client),
    chat_loop(MyId, Client, BehaviorModel).

random_wpm() ->
    %% wpm and variance for general pop
    rand:normal(40, (16*16)).

random_phrases(Count) ->
    Length = fun() -> rand:uniform(30) end,
    [ base64:encode(crypto:strong_rand_bytes(Length()))
      || _ <- lists:seq(1,Count) ].

make_behavior_model(Id) ->
    case Id rem 13 == 0 of
        true ->
            lager:info("Spammer ~p generated!", [Id]),
            #{spammer => true,
              wpm => 300,      %% fast typist
              chattiness => 1, %% chance to initiate chat per second
              phrases => random_phrases(5), %% limited messages
              reply_rate => 0.8}; %% eager to reply
        false ->
            lager:info("User ~p generated!", [Id]),
            #{spammer => false,
              wpm => random_wpm(),
              chattiness => (abs(rand:normal(1,2))/60.0), % mean 1 new conv/min
              phrases => infinity,
              reply_rate => 0.5}
    end.

chat_loop(Id, Client, Behavior) ->
    timer:sleep(erlang:floor(500 + (rand:uniform()*500))),
    maybe_initiate_convo(Id, Client, Behavior),
    maybe_reply(Id, Client, Behavior),
    chat_loop(Id, Client, Behavior).

get_phrase(infinity) ->
    hd(random_phrases(1));
get_phrase(Phrases) when is_list(Phrases) ->
    lists:nth(erlang:ceil(rand:uniform(length(Phrases))), Phrases).

nearby_id(Id) when is_number(Id) ->
    Id + abs(erlang:floor(rand:uniform(Id*2))).

maybe_initiate_convo(Id, Client, #{phrases := P, chattiness := CH} = B) ->
    case (rand:uniform() < CH) of
        true ->
            lager:info("~p Initiating convo ~p", [Id, CH]),
            Phrase = get_phrase(P),
            TargetId = nearby_id(Id),
            send_message(Client, TargetId, Phrase, B),
            ok;
        false ->
            ok
    end.

maybe_reply(Id, Client, #{reply_rate := R} = Behavior) ->
    WillReply = rand:uniform() < R,
    receive
        {stanza, _Pid, Stanza} ->
            lager:info("got stanza"),
            if WillReply -> reply(Client, Behavior, Stanza);
               (not WillReply) -> ok
            end,
            maybe_reply(Id, Client, Behavior)
    after 0 -> ok
    end.

reply(Client, #{phrases := P} = B, {xmlel, <<"message">>, Props, _Body}) ->
    {<<"from">>, BinJid} = lists:keyfind(<<"from">>, 1, Props),
    [BinId | _] = binary:split(BinJid, <<"@">>),
    IntId = binary_to_integer(BinId),
    send_message(Client, IntId, get_phrase(P), B),
    Client;
reply(Client, _, _) ->
    %% no sense replying to presence, etc.
    %% TODO don't reply to messages from self (xmpp errors, etc)
    Client.

-spec send_message(escalus:client(), binjid(), binary(), map()) -> ok.
send_message(Client, ToId, Body, #{wpm := WPM, spammer := S}) ->
    TypingTime = trunc(byte_size(Body)/(WPM*5/60) * 1000),
    timer:sleep(TypingTime),
    Msg = make_message(ToId, Body, S),
    escalus_connection:send(Client, Msg),
    ok.

make_message(ToId, Body, IsSpam) ->
    MsgId = if IsSpam -> <<"s", (escalus_stanza:id())/binary>>;
               true -> escalus_stanza:id() end,
    TargetJid = make_jid(ToId),
    escalus_stanza:set_id(escalus_stanza:chat_to(TargetJid, Body), MsgId).

-spec make_jid(amoc_scenario:user_id()) -> binjid().
make_jid(Id) ->
    BinInt = integer_to_binary(Id),
    Host = ?HOST,
    << BinInt/binary, "@", Host/binary >>.

-spec send_presence_available(escalus:client()) -> ok.
send_presence_available(Client) ->
    Pres = escalus_stanza:presence(<<"available">>),
    escalus_connection:send(Client, Pres).

%% -spec send_presence_unavailable(escalus:client()) -> ok.
%% send_presence_unavailable(Client) ->
%%     Pres = escalus_stanza:presence(<<"unavailable">>),
%%     escalus_connection:send(Client, Pres).

%% stop(Client) ->
%%     send_presence_unavailable(Client),
%%     escalus_connection:stop(Client).
