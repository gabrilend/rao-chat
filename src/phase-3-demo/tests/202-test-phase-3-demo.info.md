# 202-test-phase-3-demo.lua

Issue 310's referee: the demo, run the way the owner would
(`run-phase-demo 3` from another folder), shows each scene and passes or
fails it.

It checks input/ first and the goodbye last, that the exit status agrees
with the goodbye's counts, that every scene ran, and what each printed:
four processes on their own addresses (a gatherer started by its home's
starter and a listening device port per home); both devices paired and
listed, no token printed whole, the devices file at mode 600, each
device's test answered by A; both mirrors holding every file of A's RAM
folder with every message the same, the
browser (only) reaching A through the WebSocket upgrade, a second
catch-up changing nothing; the phone's message in A's log, the browser's
mirror and B's log with times, and pushed to the browser; a check-in
catching B's message; the edit in A's inbox and both mirrors with times,
the two copies the same, the stand-in said.  Nothing is left behind: the
demo's folder is gone and none of its processes runs.

Broken versions it must catch:
1. A scene made to fail (`RAO_PHASE3_DEMO_BREAK=edit`): reported as
   could-not with the reason, the scenes before it ran, exit 1.
2. A project copy without 190-device.lua: the module is named as not
   loaded, every scene could not run, exit 1.

Run it under the loopback-only wrapper:
`luajit src/phase-3-demo/tests/202-test-phase-3-demo.lua [project folder]`
Prints PASS/FAIL per check, then "counts <passed> <failed>".
