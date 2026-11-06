# 200-phase-3-demo.lua

The phase 3 demo program (issue 310).  Run, not loaded:

    luajit src/phase-3-demo/200-phase-3-demo.lua [project folder]

(normally through `issues/completed/demos/phase-3-demo`, or
`run-phase-demo 3`, which run it under `unshare -rn` when the system
allows a network namespace).

What it does, in order:

1. Lists `input/` (each file's name, bytes, first line): read first.
2. Loads the modules the scenes use (002, 003, 041, 081, 161, 168, 181,
   183, 186, 187, 190, 192), reporting any that fail.  If one fails,
   every scene is reported as could-not, naming the modules.
3. Makes 201's world under `tmp/shared-memory/phase-3-demo/`: two homes,
   made but not started.
4. Runs each scene in `201-phase-3-scenes.ORDER`.  A scene that fails
   prints "COULD NOT RUN" with the error, and the rest go on (a scene
   that needs what an earlier one did not make fails too, saying so); a
   scene that ran with a part missing prints "PART NOT RUN" for each.
5. Stops every process the world started and removes its folder (201's
   `finish`).
6. Prints each scene's state (ran, gaps, could not) with its seconds of
   real time and the first line of why.
7. Writes `output/phase-3-demo.goodbye` (rewritten each run): run time,
   one line per scene, the three counts, "goodbye." — written last.

Exit status: 0 when every scene ran in full; 1 when any could not run; 2
when none failed but some ran with a part missing.

`RAO_PHASE3_DEMO_BREAK=<scene key>` makes that scene fail on purpose; it
is for 202's broken version only.

No outward functions.
