# 160-test-phase-2-demo.lua

Issue 210's referee: the demo, run the way the owner would
(`run-phase-demo 2` from another folder), reports a figure from each
scene it can run and says why for each it cannot.

It checks input/ first and the goodbye last, that the exit status agrees
with the goodbye's counts, that each runnable scene ran and printed
figures, that the waiting scenes name 214, 215 and 211, that a missing
`fail2ban-regex` is named, and figures only the real stages give (three
acknowledgement times, connections from each home's own address, five
frames stopping at five different keys, flag then approve, the forged and
genuine leaves, the two-faced sender).

Broken versions it must catch:
1. A scene made to fail (`RAO_PHASE2_DEMO_BREAK=keys`): reported as
   could-not with the reason, the next scenes still run, exit 1.
2. A project copy without 156-cross-check.lua: the module is named as not
   loaded, every runnable scene could not run, exit 1.

Run it under the loopback-only wrapper:
`luajit src/phase-2-demo/tests/160-test-phase-2-demo.lua [project folder]`
Prints PASS/FAIL per check, then "counts <passed> <failed>".
