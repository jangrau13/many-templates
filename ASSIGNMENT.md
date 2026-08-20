# Keep the workers running (example assignment)

Five workers under one supervisor. They crash. Your supervisor decides what
happens next.

Your problem is `sup.erl`, and `handle_exit/3`.

## What to do

1. **`handle_exit(State, Child, Reason)`** — return the new state.
2. A child that crashes must not be able to take the whole system down.

## What you are marked on

Whether you can defend the strategy in a viva.
