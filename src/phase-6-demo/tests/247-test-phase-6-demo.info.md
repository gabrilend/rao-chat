# 247-test-phase-6-demo.lua

Issue 606's referee: the demo, run the way the owner would
(`run-phase-demo 6` from `/`), under the loopback-only wrapper.

1. It runs whole: `input/` first, the goodbye last, every scene ran,
   exit 0; it says no real service manager is used, and why; what each
   scene printed (601's lines, both homes installed and listed, the unit
   running `run-home`, nothing changed by the second install, both
   services active with launchers in a bare environment and four
   gatherers, both restarted with new launchers and the phone caught up,
   both stopped with status 0 and four gatherers `stopped = asked`);
   nothing left running or on disk.
2. The installed homes talk: B's inbox holds the line the phone wrote,
   after both homes were started from their units.
3. Broken versions: `RAO_PHASE6_DEMO_BREAK=talk` reports that scene as
   could-not, the earlier ones ran, exit 1, nothing left; a project copy
   without `scripts/run-home` names it and reports all eight scenes as
   could-not, exit 1.
