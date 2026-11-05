# 158-phase-2-demo.lua

The phase 2 demo program (issue 210).  Run, not loaded:

    luajit src/phase-2-demo/158-phase-2-demo.lua [project folder]

(normally through `issues/completed/demos/phase-2-demo`, or
`run-phase-demo 2`, which run it under `unshare -rn` when the system
allows a network namespace).

What it does, in order:

1. Lists `input/` (each file's name, bytes, first line): read first.
2. Loads the phase 1 and phase 2 modules (002, 003, 007, 021, 024, 041,
   042, 061, 081, 123, 124, 126, 127, 130, 133, 134, 139, 141, 142, 145,
   147, 149, 150, 152, 154, 156, 161, 168), reporting any that fail.  If one fails,
   every runnable scene is reported as could-not, naming the modules:
   the stages run together, so a world missing one is not the design.
3. Sets up 143's test world (the delivery tests' simulated clock and
   in-memory relay) with its scratch folder
   `tmp/shared-memory/phase-2-demo/`.  The `gatherers`, `acknowledge` and
   `git` scenes run real gatherer processes (211) under that folder instead, on
   loopback addresses, and stop every one they start.
4. Runs each scene in `159-phase-2-scenes.ORDER`.  A scene that is a
   `{waits = ...}` table prints "WAITS" and the issue it waits on; a scene
   that fails prints "COULD NOT RUN" with the error, and the rest go on; a
   scene that ran with a part missing prints "PART NOT RUN" for each.
5. Prints each scene's state (ran, gaps, waits, could not) with its
   milliseconds of real time and the first line of why.
6. Writes `output/phase-2-demo.goodbye` (rewritten each run): run time, one
   line per scene, the four counts, "goodbye." — written last.

Exit status: 0 when every scene ran in full; 1 when any could not run; 2
when none failed but some wait on an issue or ran with a part missing.

`RAO_PHASE2_DEMO_BREAK=<scene key>` makes that scene fail on purpose; it
is for 160's broken version only.

No outward functions.
