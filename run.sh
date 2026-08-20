#!/bin/sh
# The candidate's supervisor, run against a crash the examiner picks.
#
# There are no probes in this brief, so the examiner has to find out what the
# code does by making it do it. Each target below crashes children and reports
# what came back, and nothing here knows how `sup` is implemented: every answer
# is read back out of `sup:alive/1`.
#
# /work is root-owned and cannot be written to, so the submission is copied
# into /build, which is where the probe module is written and where erlc's
# .beam files land.
set -eu

TARGET="${1:-radius}"

if [ "$TARGET" = "--list" ]; then
# An id and a sentence saying what running it shows. The sentence is what the
# examiner chooses on, so it says what the run can settle rather than naming it.
cat <<'LIST'
radius        Crashes one child of five and prints who is running before and after, with the supervisor's own state, so a restart of the four that did not crash is visible even though everyone ends up running either way.
absent-child  Crashes one child until it stops being restarted, then crashes a different one, and reports whether the absent child came back. The one difference between restarting the child that died and restarting the group that can be seen from outside.
escalate      Crashes the same child over and over and reports the crash it was finally not restarted from, or that there is no such crash, and how many of its four siblings are still up afterwards.
budget        Spends one child's restarts, then crashes a second child once, and reports whether the first child's failures were charged to the second one's allowance.
LIST
  exit 0
fi

# The target also names the function to call, so it is mapped rather than
# interpolated: nothing the examiner types reaches `erl -eval`.
case "$TARGET" in
  radius)       FUN=radius ;;
  absent-child) FUN=absent ;;
  escalate)     FUN=escalate ;;
  budget)       FUN=budget ;;
  *) echo "no such target: $TARGET"; echo "run.sh --list names all four"; exit 2 ;;
esac

# $TMPDIR is set to /build/tmp by the image; the tmpfs is mounted fresh for
# each session, so the directory itself has to be made here rather than baked in.
mkdir -p "${TMPDIR:-/build/tmp}"
W=/build/viva-run
rm -rf "$W"
mkdir -p "$W"

if [ ! -f /work/sup.erl ]; then
  echo "the submission has no sup.erl at its root"
  exit 2
fi

# Every module at the root, not only sup.erl: a supervisor that calls a helper
# the candidate wrote needs that helper compiled beside it.
cp /work/*.erl "$W/"
cd "$W"

for f in *.erl; do
  if [ "$f" = sup.erl ]; then continue; fi
  # A helper that will not compile is worth a line rather than the whole run.
  # sup.erl is what every target is about, and its own errors are shown below.
  if ! erlc "$f" >/dev/null 2>&1; then
    echo "note: $f did not compile, so sup cannot call it"
  fi
done

cat > probe.erl <<'ERL'
%% Crashes, and what came back.
%%
%% Five children, one of them singled out. The supervisor's state is never
%% taken apart — a candidate may hold it however they like — so everything is
%% read back through sup:alive/1, and the raw term is printed where the
%% examiner may want to look at the bookkeeping itself.
-module(probe).
-export([radius/0, absent/0, escalate/0, budget/0]).

-define(CHILDREN, [a, b, c, d, e]).
%% How many crashes to allow before deciding that nothing ever stops a restart.
-define(PATIENCE, 200).

radius() ->
    S0 = sup:new(?CHILDREN),
    io:format("five children:      ~p~n", [alive(S0)]),
    S1 = sup:handle_exit(S0, c, crashed),
    A = alive(S1),
    io:format("c crashes, then:    ~p~n", [A]),
    io:format("  count: ~p of 5~n~n", [length(A)]),
    %% Counting settles nothing on its own: under a supervisor that restarts
    %% only the child that died and under one that restarts all five, everybody
    %% is running a second later. What separates them is whether the four that
    %% did not crash were touched, and that is in the bookkeeping.
    io:format("state before: ~p~n", [S0]),
    io:format("state after:  ~p~n", [S1]).

absent() ->
    S0 = sup:new(?CHILDREN),
    case drop(S0, d, 0) of
        {out, S1, N} ->
            io:format("d was not restarted from crash ~p~n", [N]),
            io:format("  running: ~p~n", [alive(S1)]),
            case lists:member(c, alive(S1)) of
                false ->
                    io:format("c is not running either, so crashing it settles nothing.~n"),
                    io:format("Giving up on one child took the others with it — run escalate.~n");
                true ->
                    S2 = sup:handle_exit(S1, c, crashed),
                    A = alive(S2),
                    io:format("then c crashes: ~p~n", [A]),
                    case lists:member(d, A) of
                        true ->
                            io:format("d CAME BACK — c's crash restarted the whole group, and "
                                      "brought back a child nothing had asked for~n");
                        false ->
                            io:format("d stayed out — only the child that died was restarted~n")
                    end
            end;
        {never, _S1, N} ->
            io:format("d was restarted from all ~p of its crashes, so no child can be~n", [N]),
            io:format("put out of the group and this comparison has nothing to compare.~n"),
            io:format("That nothing ever stops it is the finding — run escalate.~n")
    end.

escalate() ->
    S0 = sup:new(?CHILDREN),
    {How, S1, N} = drop(S0, a, 0),
    case How of
        out ->
            io:format("a crashed ~p times and was not restarted from the last one~n", [N]);
        never ->
            io:format("a crashed ~p times and was restarted from every one of them — "
                      "nothing here stops~n", [N])
    end,
    A = alive(S1),
    io:format("  still running: ~p~n", [A]),
    Siblings = [X || X <- ?CHILDREN, X =/= a, lists:member(X, A)],
    io:format("  a's four siblings: ~p of 4 still up~n", [length(Siblings)]).

budget() ->
    S0 = sup:new(?CHILDREN),
    case drop(S0, a, 0) of
        {out, S1, N} ->
            io:format("a was not restarted from crash ~p~n", [N]),
            case lists:member(b, alive(S1)) of
                false ->
                    io:format("b is already out, so nothing can be charged to it.~n"),
                    io:format("Giving up on a took b with it — run escalate.~n");
                true ->
                    S2 = sup:handle_exit(S1, b, crashed),
                    case lists:member(b, alive(S2)) of
                        true ->
                            io:format("b then crashed once and was restarted: "
                                      "the allowance is each child's own~n");
                        false ->
                            io:format("b then crashed ONCE and was not restarted: "
                                      "a's ~p failures were charged to b~n", [N])
                    end
            end;
        {never, _S1, N} ->
            io:format("a was restarted from all ~p of its crashes, so there is no~n", [N]),
            io:format("allowance for a second child to be charged for.~n")
    end.

alive(S) -> lists:sort(sup:alive(S)).

%% Crash one child until the supervisor stops bringing it back. Two of the
%% probes need a child that is absent, and this is the only way to get one
%% without knowing how the supervisor is written.
drop(S, _Child, N) when N >= ?PATIENCE -> {never, S, N};
drop(S, Child, N) ->
    S1 = sup:handle_exit(S, Child, crashed),
    case lists:member(Child, sup:alive(S1)) of
        true  -> drop(S1, Child, N + 1);
        false -> {out, S1, N + 1}
    end.
ERL

erlc sup.erl 2>&1 || exit 1
erlc probe.erl 2>&1 || exit 1
erl -noshell -pa . -eval "probe:$FUN(), init:stop()." 2>&1
