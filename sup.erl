-module(sup).
-export([new/1, handle_exit/3, alive/1]).

new(Children) -> #{children => Children, running => Children, restarts => []}.

%% Put the one that exited back, and leave its siblings alone.
handle_exit(State = #{running := Running}, Child, _Reason) ->
    State#{running := lists:usort([Child | Running])}.

alive(#{running := R}) -> R.
