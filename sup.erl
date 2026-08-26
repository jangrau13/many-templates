-module(sup).
-export([new/1, handle_exit/3, alive/1]).

new(Children) -> #{children => Children, running => Children, restarts => []}.

%% If one child died, the others may be holding state it corrupted, so restart
%% all of them together. That way the group always comes back consistent.
handle_exit(State = #{children := Children}, _Child, _Reason) ->
    State#{running := Children}.

alive(#{running := R}) -> R.
