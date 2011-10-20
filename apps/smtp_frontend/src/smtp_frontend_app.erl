-module(smtp_frontend_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    pg2:start_link(),
    smtp_frontend_sup:start_link().

stop(_State) ->
    ok.
