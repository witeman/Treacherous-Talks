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
%%% @author Andre Hilsendeger <Andre.Hilsendeger@gmail.com>
%%%
%%% @doc The user management lib provides all the CRU users functionality.
%%%
%%% @end
%%%
%%% @since : 17 Oct 2011 by Bermuda Triangle
%%% @end
%%%-------------------------------------------------------------------
-module(user_management).

-include_lib("datatypes/include/user.hrl").
-include_lib("datatypes/include/bucket.hrl").
-include_lib ("eunit/include/eunit.hrl").

%% Public application interface
-export([
         assign_moderator/2,
         create/1,
         get/1,
         get_by_idx/2,
         update/1
        ]).


%%-------------------------------------------------------------------
%% @doc
%% Creates a new user and returns the result to the Client.
%%
%% @spec create(#user{}) ->
%%         {ok, #user{}} |
%%         {error, nick_already_exists} |
%%         {error, any()}
%% @end
%%-------------------------------------------------------------------
create(#user{id = IdIn} = UserIn) ->
    case get_by_idx(#user.nick, UserIn#user.nick) of
        {ok, _CurUser} ->
            {error, nick_already_exists};
        {error, does_not_exist} ->
            Id = case IdIn of
                     undefined ->
                         db:get_unique_id();
                     IdIn ->
                         IdIn
                 end,
            User = UserIn#user{id = Id, date_created = erlang:universaltime()},

            BinId = db:int_to_bin(Id),
            DbObj = db_obj:create(?B_USER, BinId, User),
            DbObj2 = db_obj:set_indices(DbObj, create_idx_list(User)),
            db:put(DbObj2),
            {ok, User};
        Other ->
            {error, Other}
    end.

%%-------------------------------------------------------------------
%% @doc
%% Updates an existing user and returns the result to the Client.
%%
%% @spec update(NewUser::#user{}) ->
%%         {ok, #user{}} | {error, doesn_not_exist} | {error, any()}
%% @end
%%-------------------------------------------------------------------
update(#user{id = Id} = NewUser) when is_integer(Id) ->
    case db:get(?B_USER, db:int_to_bin(Id)) of
        {ok, Obj} ->
            Obj2 = case db_obj:has_siblings(Obj) of
                       false ->
                           Obj;
                       true ->
                           % If we get siblings at this stage (after login),
                           % we have an old session writing => overwrite it
                           [H|_] = db_obj:get_siblings(Obj),
                           H
                   end,
            NewObj = db_obj:set_value(Obj2, NewUser),
            NewObj2 = db_obj:set_indices(NewObj, create_idx_list(NewUser)),
            db:put(NewObj2),
            {ok, NewUser};
        {error, notfound} ->
            {error, does_not_exist};
        Error ->
            {error, Error}
    end;
update(_User) ->
    {error, does_not_exist}.

%%-------------------------------------------------------------------
%% @doc
%% Queries a user by index.
%% @end
%%-------------------------------------------------------------------
get_by_idx(Field, Val) ->
    case create_idx(Field, Val) of
        {error, field_not_indexed} ->
            {error, field_not_indexed};
        Idx ->
            case db:get_index(?B_USER, Idx) of
                {ok, [[?B_USER, Key]]} ->
                    {ok, DbObj} = db:get(?B_USER, Key),
                    {ok, DbObj};
                {ok, []} ->
                    {error, does_not_exist};
                {ok, List} ->
                    {ok, {index_list, List}};
                Other ->
                    {error, Other}
            end
    end.

%%-------------------------------------------------------------------
%% @doc
%% Gets user from the database.
%% @end
%%-------------------------------------------------------------------
get(Id) ->
    BinId = db:int_to_bin(Id),
    case db:get(?B_USER, BinId) of
        {ok, RiakObj} ->
            db_obj:get_value(RiakObj);
        {error, Error} ->
            {error, Error};
        Other ->
            erlang:error({error, {unhandled_case, Other, {?MODULE, ?LINE}}})
    end.


%%-------------------------------------------------------------------
%% @doc
%% Updates an existing user, to add the moderator role or to remove
%% the moderator role.
%%
%% @spec assign_moderator(Username :: string(), Action :: atom()) ->
%%         {ok, #user{}} | {error, user_not_found}
%% @end
%%-------------------------------------------------------------------
assign_moderator(Username, Action) ->
    case get_by_idx(#user.nick, Username) of
        {ok, {index_list, _UserList}} ->
            {error, user_not_found};
        {ok, UserObj} ->
            User = db_obj:get_value(UserObj),
            case Action of
                add ->
                    ModUser = User#user{role = moderator};
                remove ->
                    ModUser = User#user{role = user}
            end,
            update(ModUser);
        _Error ->
            {error, user_not_found}
    end.

%% ------------------------------------------------------------------
%% Internal Functions
%% ------------------------------------------------------------------

%%-------------------------------------------------------------------
%% @doc
%% Creates the index list for the database
%% @end
%%-------------------------------------------------------------------
create_idx_list(#user{nick=Nick, role=Role, score=Score, email=Mail}) ->
    [
     create_idx(#user.nick, Nick),
     create_idx(#user.role, Role),
     create_idx(#user.score, Score),
     create_idx(#user.email, Mail)
    ].
%%-------------------------------------------------------------------
%% @doc
%% Creates an index tuple for the database.
%% @end
%%-------------------------------------------------------------------
create_idx(#user.nick, Nick) ->
    {<<"nick_bin">>, list_to_binary(Nick)};
create_idx(#user.role, Role) ->
    {<<"role_bin">>, term_to_binary(Role)};
create_idx(#user.score, Score) ->
    {<<"score_int">>, Score};
create_idx(#user.email, Mail) ->
    {<<"email_bin">>, list_to_binary(Mail)};
create_idx(_, _) ->
    {error, field_not_indexed}.
