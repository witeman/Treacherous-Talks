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
%% -----------------------------------------------------------------------------
%% @doc
%% map contains the representation of a map, including where units stand.
%%
%% The module covers only what a real game-board would do, it knows nothing
%% about the rules.
%% The module uses dictionaries to store random information for each unit,
%% use the set/get_unit/province_info functions for this task.
%% @author <stephan.brandauer@gmail.com>
%% @end
%% -----------------------------------------------------------------------------
-module (map).

-include_lib ("eunit/include/eunit.hrl").

-export ([add_province/2,
          get_provinces/1,
          connect_provinces/4,
          add_unit/3,
          remove_unit/3,
          unit_exists/3,
          move_unit/4,
          get_units/1,
          get_units/2,
          get_units_histogram/1,
          get_province_info/3,
          get_province_info/4,
          set_province_info/4,
          get_unit_info/4,
          get_unit_info/5,
          set_unit_info/5,
          remove_unit_info/4,
          get_reachable/3,
          get_reachable/4,
          is_reachable/4,
          get_distance/3]).

-type prov_id () :: any ().

-type unit_type () :: any ().
-type unit () :: {unit_type (), Owner :: any ()}.

-type map () :: digraph ().
%-record (province_info, {owner :: any (),
%                         is_center :: boolean (),
%                         units = [] :: [unit ()] | []}).

-record (connection_info, {types=[]}).
-record (stored_unit, {unit,info}).

%% -----------------------------------------------------------------------------
%% @doc
%% Add a province to a Map.
%% @end
%% -----------------------------------------------------------------------------
-spec add_province (map (), prov_id ()) -> ok.
add_province (Map, Id) ->
    digraph:add_vertex (Map, Id, create_province_info ()),
    ok.

get_provinces (Map) ->
    digraph:vertices (Map).

get_units (Map) ->
    lists:foldl (
      fun (Province, Acc) ->
              case get_units (Map, Province) of
                  [] ->
                      Acc;
                  Units ->
                      lists:map (fun (Unit) ->
                                         {Province, Unit}
                                 end, Units) ++ Acc
              end
      end,
      [],
      get_provinces (Map)).

%% -----------------------------------------------------------------------------
%% @doc
%%  returns a nation -> number-of-units mapping.
%%
%%  Keys `:: nation ()' <br/>
%%  Values `:: pos_integer()' <br/>
%% Nations with 0 units don't show up
%% @end
%% -----------------------------------------------------------------------------
-spec get_units_histogram (map ()) -> dict ().
get_units_histogram (Map) ->
    lists:foldl (fun ({_, {_, Nation}}, Acc) ->
                         NewCnt = case dict:find (Nation, Acc) of
                                   {ok, Cnt} ->
                                       Cnt + 1;
                                   error ->
                                       1
                                  end,
                         dict:store (Nation, NewCnt, Acc)
                 end,
                 dict:new (),
                 map:get_units (Map)).

create_info () ->
    dict:new ().

create_province_info () ->
    Dict = create_info (),
    dict:store (units, [], Dict).

-spec set_province_info (map (), prov_id (), any (), any ()) -> ok.
set_province_info (Map, Id, Key, Value) ->
    {Id, Dict} = digraph:vertex (Map, Id),
    digraph:add_vertex (Map, Id, dict:store (Key, Value, Dict)),
    ok.

-spec get_province_info (map (), prov_id (), any ()) -> any ().
get_province_info (Map, Id, Key) ->
    get_province_info (Map, Id, Key, undefined).

-spec get_province_info (map (), prov_id (), any (), any ()) -> any ().
get_province_info (Map, Id, Key, Default) ->
    case digraph:vertex (Map, Id) of
        {Id, Dict} ->
            case dict:find (Key, Dict) of
                {ok, Value} ->
                    Value;
                _Other ->
                    Default
            end;
        false ->
            province_not_found
    end.

-spec get_unit_dict (map (), unit (), prov_id ()) -> dict ().
get_unit_dict (Map, Unit, Id) ->
    StoredUnits = get_province_info (Map, Id, units),
    case lists:keyfind (Unit, #stored_unit.unit, StoredUnits) of
        #stored_unit{info = Dict} ->
            Dict;
        false ->
            create_info ()
    end.

-spec set_unit_dict (map (), unit (), prov_id (), dict ()) -> ok.
set_unit_dict (Map, Unit, Id, Dict) ->
    StoredUnits = get_province_info (Map, Id, units),
    NewStoredUnit = #stored_unit{unit=Unit, info=Dict},
    NewStoredUnits = lists:keyreplace (Unit, #stored_unit.unit,
                                       StoredUnits, NewStoredUnit),
    set_province_info (Map, Id, units, NewStoredUnits).

-spec get_unit_info (map (), unit (), prov_id (), any ()) -> any ().
get_unit_info (Map, Unit, Id, Key) ->
    get_unit_info (Map, Unit, Id, Key, undefined).

-spec get_unit_info (map (), unit (), prov_id (), any (), any ()) -> any ().
get_unit_info (Map, Unit, Id, Key, Default) ->
    Dict = get_unit_dict (Map, Unit, Id),
    case dict:find (Key, Dict) of
        {ok, InfoValue} ->
            InfoValue;
        _Other ->
            Default
    end.

remove_unit_info (Map, Unit, Id, Key) ->
    NewDict = dict:erase (Key, get_unit_dict (Map, Unit, Id)),
    set_unit_dict (Map, Unit, Id, NewDict).

set_unit_info (Map, Unit, Id, Key, Value) ->
    NewDict = dict:store (Key, Value, get_unit_dict (Map, Unit, Id)),
    set_unit_dict (Map, Unit, Id, NewDict).

%% -----------------------------------------------------------------------------
%% @doc
%% adds a unit to a province without any checking. Assumes that you know where
%% you are placing it
%% @end
%% -----------------------------------------------------------------------------
-spec add_unit (Map :: map (), Unit :: unit (), To :: prov_id ()) -> ok.
add_unit (Map, Unit, To) ->
    add_stored_unit (Map, #stored_unit{unit=Unit, info=create_info ()}, To).

add_stored_unit (Map, Unit=#stored_unit{}, To) ->
    Units = get_province_info (Map, To, units),
    set_province_info (Map, To, units, [Unit | Units]).

%% -----------------------------------------------------------------------------
%% @doc
%% Checks for a certain unit in a given province
%% @end
%% -----------------------------------------------------------------------------

-spec unit_exists (Map, Id, Unit) -> boolean () when
      Map :: map (),
      Id :: prov_id (),
      Unit :: unit ().
unit_exists (Map, Id, Unit) ->
    Units = get_units(Map, Id),
    lists:any(fun(U) when U == Unit -> true; (_) -> false end, Units).

%% -----------------------------------------------------------------------------
%% @doc
%% Removes a unit from a province.
%% Will throw {error, [Map, Unit, From], unit_not_there} if the unit does not
%% exist.
%% @end
%% -----------------------------------------------------------------------------
-spec pop_stored_unit (Map, Unit, From) ->
                              #stored_unit{} | unit_does_not_exist when
      Map :: map (),
      Unit :: unit (),
      From :: prov_id ().
pop_stored_unit (Map, Unit, From) ->
    Units = get_province_info (Map, From, units),
    case lists:keyfind (Unit, #stored_unit.unit, Units) of
        false ->
            unit_does_not_exist;
        StoredUnit ->
            set_province_info (Map, From,
                               units,
                               lists:delete (StoredUnit, Units)),
            StoredUnit
    end.

-spec remove_unit (Map, Unit, From) -> ok when
      Map :: map (),
      Unit :: unit (),
      From :: prov_id ().
remove_unit (Map, Unit, From) ->
    pop_stored_unit (Map, Unit, From),
    ok.

%% -----------------------------------------------------------------------------
%% @doc
%% Moves a unit from one province to another.
%% exist.
%% @end
%% -----------------------------------------------------------------------------
-spec move_unit (Map, Unit, From, To) -> ok | no_return () when
      Map :: map (),
      Unit :: unit (),
      From :: prov_id (),
      To :: prov_id ().
move_unit (Map, Unit, From, To) ->
    case pop_stored_unit (Map, Unit, From) of
        SUnit = #stored_unit{} ->
            add_stored_unit (Map, SUnit, To);
        Other ->
            Other
    end.

get_units (Map, Id) ->
    lists:map (fun (#stored_unit{unit=Unit}) ->
                       Unit
               end,
               get_province_info (Map, Id, units)).

-spec get_reachable (Map, From, UnitType) -> [prov_id ()] when
      Map :: map (),
      From :: prov_id (),
      UnitType :: unit_type ().
get_reachable (Map, From, UnitType) ->
    get_reachable (Map, From, UnitType, 1).

is_reachable (Map, From, To, UnitType) ->
    lists:member (To, get_reachable (Map, From, UnitType)).

%% -----------------------------------------------------------------------------
%% @doc
%% returns every province that is reachable within <code>Degree</code> moves
%% @end
%% -----------------------------------------------------------------------------
-spec get_reachable (Map, From, UnitType, Degree) -> [prov_id ()] when
      Map :: map (),
      From :: prov_id (),
      UnitType :: unit_type (),
      Degree :: pos_integer ().
get_reachable (Map, From, UnitType, Degree)  when Degree > 1 ->
    DirectNeighbours = get_reachable (Map, From, UnitType),
    ordsets:union ([DirectNeighbours | [get_reachable (Map,
                                                       Neigh,
                                                       UnitType,
                                                       Degree-1)
                                        || Neigh <- DirectNeighbours]]);
get_reachable (Map, From, UnitType, 1) ->
    % take those outgoing edges, where UnitType is in #connection_info.types,
    % return an ordered set (because the first clause implicitly expects that
    % by using ordsets:union)
    ordsets:from_list (
      lists:foldl (fun (E, Acc) ->
                           {_E, From, To, #connection_info{types=Types}} =
                               digraph:edge (Map, E),
                           case UnitType of
                               '_' ->
                                   [To | Acc];
                               UnitType ->
                                   case lists:member (UnitType, Types) of
                                       true ->
                                           [To | Acc];
                                       false ->
                                           Acc
                                   end
                           end
                   end,
                   [From],
                   digraph:out_edges (Map, From))).

%% @doc
%%  a pretty naive distance algorithm.
%%  returns the distance between two provinces disregarding unit types)
%% @end
get_distance (_, [], _, _) ->
    not_found;
get_distance (_, [{_B, Dis} | _], _B, _Visited) ->
    Dis;
get_distance (Map, [{A, Dis} | Rest], B, Visited) ->
%    ?debugVal ({get_distance, 'Map', [A | Rest], B}),
%    Visiting = A,
%    ?debugVal (Visiting),
    Q = Rest ++ lists:map (fun (Prov) -> {Prov, Dis+1} end,
                    map:get_reachable (Map, A, '_')),
%    ?debugVal (Q),
    FilteredQ = lists:filter (fun ({Prov, _Dis}) ->
                                      Prov =/= A
                              end,
                              Q),
%    ?debugVal (FilteredQ),
    get_distance (Map, FilteredQ, B, [{A, Dis} | Visited]).

get_distance (Map, A, B) ->
    get_distance (Map, [{A, 0}], B, []).

get_distance_test () ->
    Map = map_data:create (standard_game),
    ?assertEqual (1,
                  get_distance (Map, vienna, bohemia)),
    ?assertEqual (2,
                  get_distance (Map, paris, spain)),
    map_data:delete (Map).

%% -----------------------------------------------------------------------------
%% @doc
%% Create a connection (two-way) between two provinces
%% @end
%% -----------------------------------------------------------------------------
-spec connect_provinces (Map, Id1, Id2, Types) -> ok when
      Map :: map (),
      Id1 :: prov_id (),
      Id2 :: prov_id (),
      Types :: [unit_type ()].
connect_provinces (Map, Id1, Id2, Types) ->
    digraph:add_edge (Map, Id1, Id2, #connection_info{types=Types}),
    digraph:add_edge (Map, Id2, Id1, #connection_info{types=Types}),
    ok.
