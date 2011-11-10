-module(game_timer).
-behaviour(gen_fsm).
-include_lib("datatypes/include/game.hrl").
-include_lib ("eunit/include/eunit.hrl").
%% ------------------------------------------------------------------
%% Ecternal API Function Exports
%% ------------------------------------------------------------------
-export([start_link/1, event/2, sync_event/2,
         current_state/1, get_game_state/1, stop/1]).

%% ------------------------------------------------------------------
%% gen_fsm Function Exports
%% ------------------------------------------------------------------
-export([init/1, handle_event/3, handle_sync_event/4,
         handle_info/3, terminate/3, code_change/4]).

-export([waiting_phase/2, waiting_phase/3,
        order_phase/2, order_phase/3, retreat_phase/2,
        retreat_phase/3, build_phase/2, build_phase/3]).

%%---------------------------------------------------------------------
%% Datatype: state
%% where:
%%       game: a game record
%%       phase: the current state
%%---------------------------------------------------------------------
-record(state, {game, phase = init}).

-define(ID(State),(State#state.game)#game.id).
%% ------------------------------------------------------------------
%% API Function Definitions
%% ------------------------------------------------------------------

start_link(Game) ->
    gen_fsm:start_link({global, {?MODULE, Game#game.id}}, ?MODULE, Game, []).

%%-------------------------------------------------------------------
%% @doc
%% Sends an event to change the state of the FSM Timer.
%% @end
%% [@spec event(Timer::pid(), Event::atom()) -> ok.
%% @end]
%%-------------------------------------------------------------------
-spec event(pid(), atom()) -> ok.
event(Timer, Event) ->
    gen_fsm:send_event({global, {?MODULE, Timer}}, Event).

sync_event(Timer, Event) ->
    gen_fsm:sync_send_event({global, {?MODULE, Timer}}, Event).

%%-------------------------------------------------------------------
%% @doc
%% Sends an event to Timer, to find out the current state (ONLY for testing)
%% @end
%% [@spec current_state(Timer::pid()) -> StateName::atom().
%% @end]
%%-------------------------------------------------------------------
-spec current_state(pid()) -> atom().
current_state(Timer) ->
    gen_fsm:sync_send_all_state_event({global, {?MODULE, Timer}}, phasename).
%%-------------------------------------------------------------------
%% @doc
%% Sends an event to Timer, to find out the state of the game (ONLY for testing)
%% @end
%% [@spec get_game_state(Timer::pid()) -> Game::game{}.
%% @end]
%%-------------------------------------------------------------------
-spec get_game_state(pid()) -> atom().
get_game_state(Timer) ->
    gen_fsm:sync_send_all_state_event({global, {?MODULE, Timer}}, game).

%%-------------------------------------------------------------------
%% @doc
%% Sends an event to Timer, to stop it
%% @end
%% [@spec stop(Timer::pid()) -> ok.
%% @end]
%%-------------------------------------------------------------------
-spec stop(pid()) -> ok.
stop(Timer) ->
    gen_fsm:sync_send_all_state_event({global, {?MODULE, Timer}}, stop).

%% ------------------------------------------------------------------
%% gen_server Function Definitions
%% ------------------------------------------------------------------
init(Game) ->
    Timeout = timer:minutes(Game#game.waiting_time),
    {ok, waiting_phase, #state{game = Game, phase = waiting_phase}, Timeout}.


waiting_phase({reconfig, UpdatedGame}, State) ->
    Timeout = timer:minutes(UpdatedGame#game.waiting_time),
    {next_state, waiting_phase, State#state{game = UpdatedGame}, Timeout};
waiting_phase(timeout, State) ->
    %% This is where we "move" on to the next state!
    NewState = State#state{phase = order_phase,
                           game = State#state.game#game{status = ongoing}},
    game:phase_change(NewState#state.game, started),
    Timeout = timer:minutes((State#state.game)#game.order_phase),
    {next_state, order_phase, NewState, Timeout};
waiting_phase(_Event, State) ->
    %% any other event than timeout or reconfig
    Timeout = timer:minutes((State#state.game)#game.waiting_time),
    {next_state, waiting_phase, State, Timeout}.
waiting_phase(_Event, From, State) ->
    syncevent(waiting_phase, From, State).
    %% TODO: This currently only restarts the phase
    %{reply, {waiting_phase, State}, waiting_phase, State}.


%% All events are handled in the same way
order_phase(_Event, State) ->
    {ok, Data} = game:process_phase(?ID(State), order_phase),
    %% order phase is handled and we move to retreat phase
    case Data of
        [] -> % skip retreat phase
            case game:phase_change(?ID(State), build_phase) of
                {ok, true} ->
                    Timeout = timer:minutes((State#state.game)#game.build_phase),
                    {next_state, build_phase, State#state{phase = build_phase}, Timeout};
                {ok, skip} ->
                    game:phase_change(?ID(State), order_phase),
                    Timeout = timer:minutes((State#state.game)#game.order_phase),
                    {next_state, order_phase, State#state{phase = order_phase}, Timeout}
            end;
        _Orders -> % we have some conflicts - need retreat phase
            game:phase_change(?ID(State), retreat_phase),
            Timeout = timer:minutes((State#state.game)#game.retreat_phase),
            {next_state, retreat_phase, State#state{phase = retreat_phase}, Timeout}
    end.
% TODO: Currently "restarts" the phase
order_phase(_Event, From, State) ->
    syncevent(order_phase, From, State).
    %Reply = {order_phase, State},
    %{reply, Reply, order_phase, State}.

%% All events are handled equally
retreat_phase(_Event, State) ->
    game:process_phase(?ID(State), retreat_phase),
    %% retreat is handled and we enter count phase
    case game:phase_change(?ID(State), build_phase) of
        {ok, true} ->
            Timeout = timer:minutes((State#state.game)#game.build_phase),
            {next_state, build_phase, State#state{phase = build_phase}, Timeout};
        {ok, skip} ->
            game:phase_change(?ID(State), order_phase),
            Timeout = timer:minutes((State#state.game)#game.order_phase),
            {next_state, order_phase, State#state{phase = order_phase}, Timeout}
    end.
% TODO: Currently "restarts" the phase
retreat_phase(_Event, From, State) ->
    syncevent(retreat_phase, From, State).
    %Reply = {retreat_phase, State},
    %{reply, Reply, retreat_phase, State}.


build_phase(_Event, State) ->
    game:process_phase(?ID(State), build_phase),
    game:phase_change(?ID(State), order_phase),
    Timeout = timer:minutes((State#state.game)#game.order_phase),
    {next_state, order_phase, State#state{phase = order_phase}, Timeout}.
% TODO: Currently "restarts" the phase
build_phase(_Event, From, State) ->
    syncevent(build_phase, From, State).
    %Reply = {build_state, State},
    %{reply, Reply, build_phase, State}.


handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.

handle_sync_event(stop, _From, _StateName, State) ->
    io:format("Stopping timer for ~p...~n", [(State#state.game)#game.id]),
    {stop, stop, ok, State};
handle_sync_event(statename, _From, StateName, State) ->
    %% for this to pick up where it was, we need to recalculate
    %% the timeout, so only use for tests where timeouts are not used!
    {reply, StateName, StateName, State};
handle_sync_event(phasename, _From, StateName, State) ->
    %% for this to pick up where it was, we need to recalculate
    %% the timeout, so only use for tests where timeouts are not used!
    {reply, State#state.phase, StateName, State};
handle_sync_event(game, _From, StateName, State) ->
    {reply, State#state.game, StateName, State};
handle_sync_event(_Event, _From, StateName, State) ->
    Reply = ok,
    {reply, Reply, StateName, State}.

handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

terminate(_Reason, _StateName, State) ->
    io:format("Terminating game timer ~p~n", [State]),
    ok.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%% ------------------------------------------------------------------
%% Internal Function Definitions
%% ------------------------------------------------------------------
syncevent(waiting_phase, From, State) ->
    %% This is where we "move" on to the next state!
    NewState = State#state{phase = order_phase,
                           game = State#state.game#game{status = ongoing}},
    game:phase_change(State#state.game, started),
    Timeout = timer:minutes((State#state.game)#game.order_phase),
    gen_fsm:reply(From, ok),
    {next_state, order_phase, NewState, Timeout};
syncevent(order_phase, From, State) ->
    ?debugMsg("Received order_phase sync event"),
    {ok, Data} = game:process_phase(?ID(State), order_phase),
    %% order phase is handled and we move to retreat phase
    case Data of
        [] -> % skip retreat phase
            case game:phase_change(?ID(State), build_phase) of
                {ok, true} ->
                    Timeout = timer:minutes((State#state.game)#game.build_phase),
                    {next_state, build_phase, State#state{phase = build_phase}, Timeout};
                {ok, skip} ->
                    game:phase_change(?ID(State), order_phase),
                    Timeout = timer:minutes((State#state.game)#game.order_phase),
                    gen_fsm:reply(From, ok),
                    {next_state, order_phase, State#state{phase = order_phase}, Timeout}
            end;
        _Orders -> % we have some conflicts - need retreat phase
            game:phase_change(?ID(State), retreat_phase),
            Timeout = timer:minutes((State#state.game)#game.retreat_phase),
            gen_fsm:reply(From, ok),
            {next_state, retreat_phase, State#state{phase = retreat_phase}, Timeout}
    end;
syncevent(retreat_phase, From, State) ->
    ?debugMsg("Received retreat_phase sync event"),
    game:process_phase(?ID(State), retreat_phase),
    %% retreat is handled and we enter count phase
    case game:phase_change(?ID(State), build_phase) of
        {ok, true} ->
            Timeout = timer:minutes((State#state.game)#game.build_phase),
            gen_fsm:reply(From, ok),
            {next_state, build_phase, State#state{phase = build_phase}, Timeout};
        {ok, skip} ->
            game:phase_change(?ID(State), order_phase),
            Timeout = timer:minutes((State#state.game)#game.order_phase),
            gen_fsm:reply(From, ok),
            {next_state, order_phase, State#state{phase = order_phase}, Timeout}
    end;
syncevent(build_phase, From, State) ->
    ?debugMsg("Received build_phase sync event"),
    game:process_phase(?ID(State), build_phase),
    game:phase_change(?ID(State), order_phase),
    Timeout = timer:minutes((State#state.game)#game.order_phase),
    gen_fsm:reply(From, ok),
    {next_state, order_phase, State#state{phase = order_phase}, Timeout}.
