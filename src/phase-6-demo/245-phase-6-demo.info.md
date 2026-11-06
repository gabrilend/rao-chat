# 245-phase-6-demo.lua

The phase 6 demo program (issue 606).  Run, not loaded:

    luajit src/phase-6-demo/245-phase-6-demo.lua [project folder]

(normally through `issues/completed/demos/phase-6-demo`, or
`run-phase-demo 6`, which run it under `unshare -rn`; without a network
namespace it does not run, since the homes' starters check the public
address).

What it does, in order:

1. Lists `input/` (each file's name, bytes, first line): read first.
2. Loads the modules the scenes use (002, 003, 041, 161, 168, 192, 236)
   and finds the programs they run (230, `install-home`, 232, `run-home`,
   242, `restart-homes`, 189, 190, 183).  One missing, and every scene is
   reported as could-not, naming it.
3. Makes 246's world under `tmp/shared-memory/phase-6-demo/`: the
   stand-in service managers, a scratch `HOME`, nothing installed.
4. Runs each scene in `246-phase-6-scenes.ORDER`; a scene that fails
   prints "COULD NOT RUN" with the error and the rest go on.
5. Stops everything the world started and removes its folder.
6. Says which scenes ran, with a part missing, or could not run.
7. Writes `output/phase-6-demo.goodbye`: last.

Exit status 0 every scene ran in full, 1 one could not, 2 one ran with a
part missing.  `RAO_PHASE6_DEMO_BREAK=<scene key>` (the referee's) makes
that scene fail on purpose.
