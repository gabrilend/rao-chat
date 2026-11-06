# 227-phase-4-demo.lua

The phase 4 demo program (issue 409).  Run, not loaded:

    luajit src/phase-4-demo/227-phase-4-demo.lua [project folder]

(normally through `issues/completed/demos/phase-4-demo`, or
`run-phase-demo 4`, which run it under `unshare -rn` when the system
allows a network namespace).

What it does, in order (as 200 does for phase 3):

1. Lists `input/` (each file's name, bytes, first line): read first.
2. Looks for Node; without it, says so and exits 1 before starting
   anything (409 decision 2).  Says plainly that Node stands in for the
   browser and that the page's own drawing is not run here.
3. Loads the modules the scenes use, and checks the stand-in browser
   (`src/web/tests/208-stand-in-browser.js`) is there, naming it as there
   (with Node's version) or NOT THERE.  If either fails, every scene is
   reported as could-not, naming what is missing.
4. Makes 228's world under `tmp/shared-memory/phase-4-demo/`.
5. Runs each scene in `228-phase-4-scenes.ORDER`, reporting each as 200
   does (ran, PART NOT RUN, COULD NOT RUN with the error).
6. Stops every process the world started and removes its folder.
7. Prints each scene's state with its seconds of real time, and writes
   `output/phase-4-demo.goodbye` last (rewritten each run).

Exit status: 0 when every scene ran in full; 1 when any could not run (or
Node is missing); 2 when none failed but some ran with a part missing.

`RAO_PHASE4_DEMO_BREAK=<scene key>` makes that scene fail on purpose; it
is for 229's broken version only.

No outward functions.
