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
-module (db_c_test).

-include_lib ("eunit/include/eunit.hrl").

%% -------------------------------------------------------------------
%% Startup/teardown code
%% -------------------------------------------------------------------
connected_startup () ->
    {ok, Client} = db_c:connect ({pb, {"127.0.0.1", 8081}}),
    Client.

connected_teardown (Client) ->
    db_c:disconnect (Client).

%% -------------------------------------------------------------------
%% Test many concurrent connections
%% -------------------------------------------------------------------
many_concurrent_conns_test () ->
    Clients = lists:map (fun (N) ->
                                 Client = connected_startup (),
                                 ?debugVal ({setup, N}),
                                 {N, Client}
                         end,
                         lists:seq (1,100)),
    ?debugMsg ("Many connections setup"),
    lists:map (fun ({N, Client}) ->
                       connected_teardown (Client),
                       ?debugVal ({teardown, N})
               end,
               lists:reverse (Clients)).

%% -------------------------------------------------------------------
%% Write siblings test
%% -------------------------------------------------------------------
write_siblings (Client) ->
    [fun () ->
             db_c:set_bucket (Client, <<"test">>, [{allow_mult, true}]),
             Obj1 = db_obj:create (<<"test">>, <<"key">>, {sibling1}),
             ?debugVal (Obj1),
             db_c:put (Client, Obj1),
             Obj2 = db_obj:create (<<"test">>, <<"key">>, {sibling2}),
             ?debugVal (Obj2),
             db_c:put (Client, Obj2),
             {ok, Siblings}=db_c:get (Client,<<"test">>,<<"key">>),
             ?debugVal (db_obj:get_siblings (Siblings)),
             db_c:delete (Client, <<"bucket">>, <<"key">>)
     end].

siblings_test_ () ->
    {setup,
     fun connected_startup/0,
     fun connected_teardown/1,
     fun write_siblings/1}.

%% -------------------------------------------------------------------
%% Write with undefined id to the db, get an id back.
%% -------------------------------------------------------------------
write_undefined_test_ () ->
    {setup,
     fun connected_startup/0,
     fun connected_teardown/1,
     fun write_undefined_tst_/1}.

write_undefined_tst_ (Client) ->
    [fun () ->
             DBObj = db_obj:create (<<"test">>, undefined, {test, item}),
             ?debugVal (DBObj),
             {ok, Key} = db_c:put (Client, DBObj),
             ?debugVal (Key),
             {ok, ReadDBItem} = db_c:get (Client, <<"test">>, Key),
             ReadItem = db_obj:get_value (ReadDBItem),
             ?debugVal (ReadItem),
             ReadItem = {test, item}
     end].



%% -------------------------------------------------------------------
%% Key filter test
%% -------------------------------------------------------------------
key_filter_test_ () ->
    {setup,
     fun() -> % setup
             Client = connected_startup(),
             Bucket = <<"key_filter_bucket">>,
             Id = db_c:get_unique_id(),
             StrId = integer_to_list(Id),
             Prefix = "key_filter",

             Key1 = list_to_binary(Prefix ++ "_1_" ++ StrId),
             Val1 = {test, item1, Id},
             DBObj1 = db_obj:create(Bucket, Key1, Val1),
             db_c:put(Client, DBObj1),

             Key2 = list_to_binary(Prefix ++ "_2_" ++ StrId),
             Val2 = {test, item2, Id},
             DBObj2 = db_obj:create(Bucket, Key2, Val2),
             db_c:put(Client, DBObj2),

             Key3 = list_to_binary(Prefix ++ "_3_" ++ StrId ++ "bob"),
             Val3 = {test, item3, Id},
             DBObj3 = db_obj:create(Bucket, Key3, Val3),
             db_c:put(Client, DBObj3),
             {Client, Bucket, StrId, Prefix, Val1, Val2, Val3}
     end,
     fun({Client, Bucket, _Id, _Pre, _Val1, _Val2, _Val3}) -> %teardown
             db_c:empty_bucket(Client, Bucket),
             connected_teardown(Client)
     end,
     fun({Client, Bucket, StrId, Prefix, Val1, Val2, Val3}) -> %test
             [fun() ->
                      KeyFilter1 = [[<<"ends_with">>,  list_to_binary(StrId)]],
                      Result1 = db_c:get_key_filter(Client, Bucket, KeyFilter1),
                      ?assertMatch({ok, _List}, Result1),
                      {ok, List1} = Result1,
                      Expected1 = [Val1, Val2],
                      equal_lists(Expected1, List1),

                      KeyFilter2 = [[<<"matches">>,  list_to_binary(StrId)]],
                      Result2 = db_c:get_key_filter(Client, Bucket, KeyFilter2),
                      ?assertMatch({ok, _List}, Result2),
                      {ok, List2} = Result2,
                      Expected2 = [Val1, Val2, Val3],
                      equal_lists(Expected2, List2),

                      KeyFilter3 = [[<<"and">>,
                                     [[<<"starts_with">>,  list_to_binary(Prefix)]],
                                     [[<<"ends_with">>,  <<"bob">>]]
                                    ]],
                      Result3 = db_c:get_key_filter(Client, Bucket, KeyFilter3),
                      ?assertMatch({ok, _List}, Result3),
                      {ok, List3} = Result3,
                      Expected3 = [Val3],
                      equal_lists(Expected3, List3)
              end]
     end}.


equal_lists(L1, L2) ->
    ?debugVal(L1),
    ?debugVal(L2),
    ?assertEqual(length(L1), length(L2)),
    lists:foreach(fun(Val) ->
                          ?assert(lists:member(Val, L1))
                  end, L2).

%% -------------------------------------------------------------------
%% Secondary indices tests
%% -------------------------------------------------------------------
%% secondary_indices_test_ () ->
%%     {setup,
%%      fun connected_startup/0,
%%      fun connected_teardown/1,
%%      fun write_index/1}.
%%
%%
%% -record(index_test, {id,
%%                      nick = "bob",
%%                      other_stuff = "Blaaaaaaaaaaaaa"}).
%%
%% get_index_test_record() ->
%%     #index_test{id = list_to_binary(integer_to_list(db_c:get_unique_id()))}.
%%
%% write_index(Client) ->
%%     [fun() ->
%%              Bucket = <<"index_test">>,
%%              db_c:set_bucket (Client, Bucket, [{allow_mult, true}]),
%%              {ok, Keys} = db_c:list_keys(Client, Bucket),
%%              lists:foreach(fun(K) ->
%%                                db_c:delete(Client, Bucket, K)
%%                        end, Keys),
%%
%%              Val = get_index_test_record(),
%%              Key = Val#index_test.id,
%%              Obj1 = db_obj:create (Bucket, Key, Val),
%%              ?debugVal (Obj1),
%%
%%              Index = <<"nick_bin">>,
%%              IndexKey = list_to_binary(Val#index_test.nick),
%%              Obj2 = db_obj:add_index(Obj1, {Index, IndexKey}),
%%              ?debugVal(Obj2),
%%              db_c:put(Client, Obj2),
%%
%%              {ok, GetObj} = db_c:get (Client, Bucket, Key),
%%              ?debugVal(GetObj),
%%              ?assertEqual(Val, db_obj:get_value(GetObj)),
%% %%              ?assertEqual([{Index, IndexKey}], db_obj:get_indices(GetObj)),
%%
%%              IdxResult = db_c:get_index(Client, Bucket, {Index, IndexKey}),
%%              ?debugVal(IdxResult),
%%              {ok, GetIdx} = IdxResult,
%%              ?debugVal(GetIdx),
%%              ?assertEqual([ [Bucket, Key] ], GetIdx),
%%              db_c:delete(Client, Bucket, Key)
%%      end].


%% -------------------------------------------------------------------
%% Get a list from riak.
%% -------------------------------------------------------------------
get_list_test_() ->
    {setup,
     fun connected_startup/0,
     fun connected_teardown/1,
     fun get_list/1}.

get_list(Client) ->
    [fun() ->
             Bucket = <<"get_list_test">>,
             {ok, OldKeys} = db_c:list_keys(Client, Bucket),
             lists:foreach(fun(K) ->
                               db_c:delete(Client, Bucket, K)
                       end, OldKeys),
             % create some values in the db
             Count = 10,
             {Keys, Values} = lists:foldl(fun(No, {CurKeys, CurValues}) ->
                                                  Key = db:int_to_bin(
                                                          db_c:get_unique_id()),
                                                  Val = {val, No},
                                                  Obj = db_obj:create(Bucket, Key, Val),
                                                  db_c:put(Client, Obj),
                                                  {[Key|CurKeys], [Val|CurValues]}
                                          end, {[], []}, lists:seq(1, Count)),

             Result = db_c:get_values(Client, Bucket, Keys),
             ?assertMatch({ok, _Vals}, Result),
             {ok, ResValues} = Result,
             ?assertEqual(Count, length(ResValues)),
             lists:foreach(fun(Val) ->
                                   ?assertEqual(true, lists:member(Val, ResValues))
                           end, Values)
     end].
