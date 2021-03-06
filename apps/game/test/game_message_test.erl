%%%-------------------------------------------------------------------
%%% @copyright
%%% Copyright (C) 2011 by Bermuda Triangle
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"), to deal
%%% in the Software without restriction, including without limitation the rights
%%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%%% copies of the Software, and to permit persons to whom the Software is
%%% furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included in
%%% all copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%%% THE SOFTWARE.
%%% @end
%%%-------------------------------------------------------------------
-module(game_message_test).

-include_lib ("eunit/include/eunit.hrl").
-include_lib ("datatypes/include/game.hrl").
-include_lib ("datatypes/include/message.hrl").
-include_lib ("datatypes/include/push_event.hrl").
-include_lib ("datatypes/include/bucket.hrl").


-export([receive_push_event/2, receive_init/0]).
-define (TEST_TIMEOUT, 3000).

apps () ->
    [datatypes, service, protobuffs, riakc, db, game, message, utils].

app_started_setup () ->
    ?debugMsg ("starting apps:"),
    Response = [{App, application:start (App)} || App <- apps ()],
    meck:new(controller),
    meck:expect(controller, sync_push_event,
                fun(UserID, Event) ->
                        game_msg ! {controller_push_event, {UserID, Event}},
                        {ok, success}
                end),
    ?debugMsg (io_lib:format ("~p", [Response])).

app_started_teardown (_) ->
    [application:stop (App) || App <- lists:reverse (apps ())],
    meck:unload(controller).

%%------------------------------------------------------------------------------
%% @doc
%%  the top level test
%% @end
%%------------------------------------------------------------------------------
game_messaging_test_ () ->
    {setup,
     fun app_started_setup/0,
     fun app_started_teardown/1,
     [ping_tst_(),
      game_msg_send_tst_(),
      mod_msg_success_tst_(),
      user_msg_fail_tst_(),
      operator_get_game_msg_tst_(),
      get_game_msg_tree_tst_()
     ]}.


ping_tst_ () ->
    [fun()-> {pong, _Pid} = game_worker:ping () end].

test_game (Press) ->
    #game{creator_id=123,
          name="game name",
          description="lorem ipsum dolor sit amet",
          press = Press,
          order_phase = 12*60,
          retreat_phase = 12*60,
          build_phase = 12*60,
          password="pass",
          waiting_time = 50*60}.

%%------------------------------------------------------------------------------
%% Tests the get game state functionality
%%------------------------------------------------------------------------------
mod_msg_success_tst_() ->
    fun() ->
            GameRecord = test_game(grey),
            % Create a new Game
            Game = sync_get(sync_new(GameRecord)),
            % join players and countries
            JoinResult = game:join_game(Game#game.id, 1111, england),
            ?assertEqual({ok, Game#game.id}, JoinResult),

            GetGame= fun() -> sync_get(Game#game.id) end,
            UpdatedGame1= test_utils:wait_for_change(GetGame, Game, 100),

            JoinResult2 = game:join_game(Game#game.id, 2222, germany),
            ?assertEqual({ok, Game#game.id}, JoinResult2),
            UpdatedGame2= test_utils:wait_for_change(GetGame, UpdatedGame1, 100),

            JoinResult3 = game:join_game(Game#game.id, 3333, france),
            ?assertEqual({ok, Game#game.id}, JoinResult3),
            test_utils:wait_for_change(GetGame, UpdatedGame2, 100),


            game_timer:sync_event(Game#game.id, timeout),

            GMsg = #game_message{content = "test moderator game message",
                                 from_id= 1357,
                                 game_id = Game#game.id},
            %?debugVal(_Result = game:game_msg(GMsg, Countries, moderator)),
            {UserIDs, Senders} = sync_game_msg(GMsg,
                                               [germany, france], moderator),
            sync_delete(Game#game.id),
            ?assert(lists:member(2222, UserIDs)),
            ?assert(lists:member(3333, UserIDs)),
            ?assertEqual([moderator, moderator], Senders)
    end.

user_msg_fail_tst_() ->
    fun() ->
            GameRecord = test_game(grey),
            % Create a new Game
            Game = sync_get(sync_new(GameRecord)),
            % join players and countries
            JoinResult = game:join_game(Game#game.id, 1111, england),
            ?assertEqual({ok, Game#game.id}, JoinResult),
            JoinResult2 = game:join_game(Game#game.id, 2222, germany),
            ?assertEqual({ok, Game#game.id}, JoinResult2),
            JoinResult3 = game:join_game(Game#game.id, 3333, france),
            ?assertEqual({ok, Game#game.id}, JoinResult3),
            game_timer:sync_event(Game#game.id, timeout),

            % the sender is not a game player!
            GMsg = #game_message{content = "test user game message", from_id= 1357,
                                 game_id = Game#game.id},
            Res = game:game_msg(GMsg, [germany, france], user),
            sync_delete(Game#game.id),
            ?assertEqual({error, user_not_playing_this_game}, Res)
    end.

game_msg_send_tst_() ->
    [fun() ->
             ?debugMsg("Ensure a in-game message is correctly delivered to controller"),
             ?debugMsg("send game message test to several users white press"),
             GameRecord = test_game(white),
             % Create a new Game
             Game = sync_get(sync_new(GameRecord)),
             % join new player with id=1122 and country=england
             JoinResult = game:join_game(Game#game.id, 1111, england),
             ?assertEqual({ok, Game#game.id}, JoinResult),
             GetGame= fun() -> sync_get(Game#game.id) end,
             UpdatedGame1= test_utils:wait_for_change(GetGame, Game, 100),

             JoinResult2 = game:join_game(Game#game.id, 2222, germany),
             ?assertEqual({ok, Game#game.id}, JoinResult2),
             UpdatedGame2= test_utils:wait_for_change(GetGame, UpdatedGame1, 100),

             JoinResult3 = game:join_game(Game#game.id, 3333, france),
             ?assertEqual({ok, Game#game.id}, JoinResult3),
             test_utils:wait_for_change(GetGame, UpdatedGame2, 100),

             UserIDs = [2222,3333],
             FromCountries = [england, england],

             game_timer:sync_event(Game#game.id, timeout),
             timer:sleep(50),
             GMsg = #game_message{content = "test send game message", from_id= 1111,
                                  game_id = Game#game.id},

             {Result1, Result2} = sync_game_msg(GMsg, [germany, france], user),
             sync_delete(Game#game.id),
             ?assertEqual([], UserIDs -- Result1),
             ?assertEqual([], FromCountries -- Result2)
    end,
     fun() ->
             ?debugMsg("send game message when game is not started"),
             GameRecord = test_game(white),
             % Create a new Game
             Game = sync_get(sync_new(GameRecord)),
             % join new player with id=1122 and country=england
             JoinResult = game:join_game(Game#game.id, 1111, england),
             ?assertEqual({ok, Game#game.id}, JoinResult),

             GetGame= fun() -> sync_get(Game#game.id) end,
             UpdatedGame1= test_utils:wait_for_change(GetGame, Game, 100),

             JoinResult2 = game:join_game(Game#game.id, 2222, germany),
             ?assertEqual({ok, Game#game.id}, JoinResult2),
             UpdatedGame2= test_utils:wait_for_change(GetGame, UpdatedGame1, 100),
             JoinResult3 = game:join_game(Game#game.id, 3333, france),
             ?assertEqual({ok, Game#game.id}, JoinResult3),
             test_utils:wait_for_change(GetGame, UpdatedGame2, 100),

             GMsg = #game_message{content = "test send game message", from_id= 1111,
                                  game_id = Game#game.id},
             Result = game:game_msg(GMsg, [germany, france], user),
             sync_delete(Game#game.id),
             ?assertEqual({error,game_phase_not_ongoing}, Result)
    end,
     fun() ->
             ?debugMsg("Ensure a in-game message is correctly delivered to controller"),
             ?debugMsg("send game message to several users grey press"),
             GameRecord = test_game(grey),
             % Create a new Game
             Game = sync_get(sync_new(GameRecord)),
             % join new player with id=1122 and country=england
             JoinResult = game:join_game(Game#game.id, 1111, england),
             ?assertEqual({ok, Game#game.id}, JoinResult),
             GetGame= fun() -> sync_get(Game#game.id) end,
             UpdatedGame1= test_utils:wait_for_change(GetGame, Game, 100),
             JoinResult2 = game:join_game(Game#game.id, 2222, germany),
             ?assertEqual({ok, Game#game.id}, JoinResult2),
             UpdatedGame2= test_utils:wait_for_change(GetGame, UpdatedGame1, 100),
             JoinResult3 = game:join_game(Game#game.id, 3333, france),
             ?assertEqual({ok, Game#game.id}, JoinResult3),
             test_utils:wait_for_change(GetGame, UpdatedGame2, 100),

             UserIDs = [2222,3333],
             FromCountries =[unknown, unknown],

             game_timer:sync_event(Game#game.id, timeout),
             timer:sleep(50),
             GMsg = #game_message{content = "test send game message", from_id= 1111,
                                  game_id = Game#game.id},
             ?debugMsg("sync_game_msg"),
             {Result1, Result2} = sync_game_msg(GMsg, [germany, france], user),
             sync_delete(Game#game.id),
             ?assertEqual([], UserIDs -- Result1),
             ?assertEqual([], FromCountries -- Result2)
    end].

get_game_msg_tree_tst_() ->
    {setup,
      fun() ->
              GameRecord = test_game(white),
              Game = sync_get(sync_new(GameRecord)),
              JoinResult = game:join_game(Game#game.id, 1111, england),
              ?assertEqual({ok, Game#game.id}, JoinResult),
              JoinResult2 = game:join_game(Game#game.id, 2222, russia),
              ?assertEqual({ok, Game#game.id}, JoinResult2),
              JoinResult3 = game:join_game(Game#game.id, 3333, austria),
              ?assertEqual({ok, Game#game.id}, JoinResult3),

              GameId = Game#game.id,
              game_timer:sync_event(GameId, timeout),
              timer:sleep(50),

              Msg1 = #game_message{game_id=GameId, content="msg1",
                                   sender_country=england,
                                   from_id=1111, to_id=2222},
              Msg2 = #game_message{game_id=GameId, content="msg2",
                                   sender_country=england,
                                   from_id=1111, to_id=2222},
              Msg3 = #game_message{game_id=GameId, content="msg3",
                                   sender_country=england,
                                   from_id=2222, to_id=1111},
              Msg4 = #game_message{game_id=GameId, content="msg4",
                                   sender_country=russia,
                                   from_id=2222, to_id=1111},
              Msg5 = #game_message{game_id=GameId, content="msg5",
                                   sender_country=austria,
                                   from_id=3333, to_id=2222},
              ?debugVal(GameId),
              CurGameFun = fun() ->
                                BinKey = game_utils:get_game_current_key(GameId),
                                {ok, DBReply} = db:get(?B_GAME_CURRENT,
                                                       BinKey, [{r,1}]),
                                db_obj:get_value(DBReply)
                        end,
              Initial = CurGameFun(),
              ?debugVal(sync_game_msg(Msg1, [russia], user)),
              game_timer:sync_event(GameId, timeout),
              CurGame1 = test_utils:wait_for_change(CurGameFun, Initial, 10),
              ?debugVal(sync_game_msg(Msg2, [russia], user)),
              ?debugVal(sync_game_msg(Msg3, [england], user)),
              game_timer:sync_event(GameId, timeout),
              CurGame2 = test_utils:wait_for_change(CurGameFun, CurGame1, 10),
              ?debugVal(sync_game_msg(Msg4, [england], user)),
              game_timer:sync_event(GameId, timeout),
              CurGame3 = test_utils:wait_for_change(CurGameFun, CurGame2, 10),
              game_timer:sync_event(GameId, timeout),
              CurGame4 = test_utils:wait_for_change(CurGameFun, CurGame3, 10),
              game_timer:sync_event(GameId, timeout),
              CurGame5 = test_utils:wait_for_change(CurGameFun, CurGame4, 10),
              game_timer:sync_event(GameId, timeout),
              test_utils:wait_for_change(CurGameFun, CurGame5, 10),
              ?debugVal(sync_game_msg(Msg5, [russia], user)),
              GameId
     end,
     fun(GameId) ->
             sync_delete(GameId),
             delete_messages(GameId)
     end,
     fun(GameId) ->
         [fun() ->
             {ok, Actual} = game_utils:get_game_msg_tree(GameId),
             Expected = [{1901,[{{spring,order_phase},[england]},
                                {{spring,retreat_phase},[russia, england]},
                                {{fall,order_phase},[russia]}]},
                         {1902,[{{spring,retreat_phase},[austria]}]}],
             ?assertEqual(Expected, Actual)
          end]
    end}.

operator_get_game_msg_tst_() ->
    [{setup,
      fun() ->
              GameRecord = test_game(white),
              Game = sync_get(sync_new(GameRecord)),
              JoinResult = game:join_game(Game#game.id, 1111, england),
              ?assertEqual({ok, Game#game.id}, JoinResult),
              JoinResult2 = game:join_game(Game#game.id, 2222, russia),
              ?assertEqual({ok, Game#game.id}, JoinResult2),
              JoinResult3 = game:join_game(Game#game.id, 3333, austria),
              ?assertEqual({ok, Game#game.id}, JoinResult3),

              GameId = Game#game.id,
              CurGameFun = fun() ->
                                   BinKey = game_utils:get_game_current_key(GameId),
                                   db:get(?B_GAME_CURRENT, BinKey, [{r,1}])
                        end,
              Initial = CurGameFun(),
              game_timer:sync_event(GameId, timeout),
              CurGame1 = test_utils:wait_for_change(CurGameFun, Initial, 10),

              Msg1 = #game_message{game_id=GameId, content="msg1",
                                   sender_country=england,
                                   from_id=1111, to_id=2222},
              Msg2 = #game_message{game_id=GameId, content="msg2",
                                   sender_country=england,
                                   from_id=1111, to_id=2222},
              Msg3 = #game_message{game_id=GameId, content="msg3",
                                   sender_country=england,
                                   from_id=1111, to_id=2222},
              ?debugVal(GameId),
              ?debugVal(sync_game_msg(Msg1, [russia], user)),
              ?debugVal(sync_game_msg(Msg2, [russia], user)),
              game_timer:sync_event(GameId, timeout),
              test_utils:wait_for_change(CurGameFun, CurGame1, 10),
              ?debugVal(sync_game_msg(Msg3, [russia], user)),
              {GameId, Msg1, Msg2}
     end,
     fun({GameId, _, _}) ->
             sync_delete(GameId),
             delete_messages(GameId)
     end,
     fun({GameId, Msg1, Msg2}) ->
             [fun() ->
        Key = integer_to_list(GameId) ++
                          "-1901-spring-order_phase-england",
        BinID = list_to_binary(Key),
        Orders = [move,support,convoy,hold],
        DBGameOrderObj = db_obj:create(?B_GAME_ORDER, BinID,
                                       #game_order{order_list=Orders}),
        db:put(DBGameOrderObj),

        {ok, Actual} = game:operator_get_game_msg(
                         Key, GameId, 1901, spring, order_phase),

        db:delete (?B_GAME_ORDER, BinID),

        Expected = {[Msg1, Msg2], Orders},
        % Get the lists and check for membership in the message list since we
        % cannot guarantee ordering
        {ActualMsgList, ActualOrderList} = Actual,
        {ExpectedMsgList, ExpectedOrderList} = Expected,
        ?debugVal(Actual),
        ?assertEqual(length(ExpectedMsgList), length(ActualMsgList)),
        ?assertEqual(ExpectedOrderList, ActualOrderList),
        lists:foreach(fun(Msg) ->
                              ExptMsg = lists:keyfind(
                                          Msg#game_message.content,
                                          #game_message.content,
                                          ExpectedMsgList),
                              ?assertMatch(#game_message{}, ExptMsg)
                      end, ActualMsgList)
              end]
    end
     }].
%%------------------------------------------------------------------------------
%% Helpers
%%------------------------------------------------------------------------------
%%------------------------------------------------------------------------------
%% @doc
%%   synchronious send game message
%%   Since message:game_msg is a gen_server cast, we need to meck up controller
%%   function which being called when game messages are logged.
%%   this function sends message to message app and meck controller:push_event
%%   to get the reponse from the function's arguments.
%%   it returns the userid of the receiver of the message and the from country
%%   of the sender.
%% @end
%%------------------------------------------------------------------------------
sync_game_msg(GMsg, Countries, Role) ->
    Pid = spawn(?MODULE, receive_init, []),
    register(game_msg, Pid),

    {ok, _GameID} = game:game_msg(GMsg, Countries, Role),
    receive
    after
        3000 ->
            Pid!{self(), get_user_ids},
            receive
                {ok, UserIDs, FromCountries} ->
                    {UserIDs, FromCountries}
            end
    end.

receive_init()->
    receive_push_event([], []).

receive_push_event(UserIDs, FromCountries) ->
    receive
        {controller_push_event,
         {UserID, #push_event{data = GMsg}}} ->
            FromCountry = GMsg#game_message.from_country,
            receive_push_event([UserID | UserIDs], [FromCountry | FromCountries]);
        {Pid, get_user_ids} ->
            unregister(game_msg),
            Pid ! {ok, UserIDs, FromCountries}
    end.

sync_new(Game=#game{}) ->
    {ok, Id} = game:new_game(Game),
    Id.

sync_get(ID) ->
    {ok, Game} = game:get_game(ID),
    Game.

sync_delete(ID) ->
    case game:delete_game(ID) of
        ok ->
            ok;
        Other ->
            erlang:error ({error, {{received, Other}, {expected, ok}}})
    end.

delete_messages(GameId) ->
    Query = [[<<"matches">>, db:int_to_bin(GameId)]],
    Res = db:get_key_filter(?B_GAME_MESSAGE, Query),
    {ok, Msgs} = Res,
    lists:foreach(fun(#game_message{id=Id}) ->
                          db:delete(?B_GAME_MESSAGE, Id, [{w, all}]),
                          db:delete(?B_GAME_MESSAGE_UNREAD, Id, [{w, all}])
                  end, Msgs).

