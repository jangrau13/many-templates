%% Restarting the workers under a supervisor when one of them dies.
%%
%% The plumbing is settled: something else starts the supervisor and tells it a
%% child has exited. `handle_exit/3` is the part with a decision in it.
-module(sup).
-export([new/1, handle_exit/3, alive/1]).

new(Children) -> #{children => Children, running => Children, restarts => []}.

%% A child exited with Reason. Return the new state.
handle_exit(_State, _Child, _Reason) -> erlang:error(not_implemented).

alive(#{running := R}) -> R.
