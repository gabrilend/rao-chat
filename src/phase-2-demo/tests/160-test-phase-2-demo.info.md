# 160-test-phase-2-demo.lua

Issue 210's referee: the demo, run the way the owner would
(`run-phase-demo 2` from another folder), reports a figure from each
scene it can run and says why for each it cannot.

It checks input/ first and the goodbye last, that the exit status agrees
with the goodbye's counts, that each runnable scene ran and printed
figures, that a waiting scene names its issue, that a missing
`fail2ban-regex` is named, and figures only the real stages give (three
acknowledgement times, connections from each home's own address, five
frames stopping at five different keys, flag then approve, the forged and
genuine leaves, the two-faced sender).  From the real-process scenes
(211): three gatherer processes on their own addresses, a killed one
started again, `due/` holding B's pair with 3 missing and empty once B is
back, and 0 of 10 lost under `acknowledge-after = disk`, 10 of 10 under
`ram`.  From the signatures scene, every row of 214's table as it says;
from the git scene (215), both homes' copies byte-identical under the
token's fingerprint, a hand edit committed with both logs unchanged, and
commits by the home's name, the running log on its own branch (215a), and a shared upstream with one
file per message, the hand edit shared and the other home's program
never checked out (215b).

Broken versions it must catch:
1. A scene made to fail (`RAO_PHASE2_DEMO_BREAK=keys`): reported as
   could-not with the reason, the next scenes still run, exit 1.
2. A project copy without 156-cross-check.lua: the module is named as not
   loaded, every runnable scene could not run, exit 1.

Run it under the loopback-only wrapper:
`luajit src/phase-2-demo/tests/160-test-phase-2-demo.lua [project folder]`
Prints PASS/FAIL per check, then "counts <passed> <failed>".
