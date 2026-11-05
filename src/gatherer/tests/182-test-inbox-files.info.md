# 182-test-inbox-files.lua

Issue 301's referees for its first step, the inbox files: order by name
(1), edits applied (2), hidden stays hidden and marked says so (3), and a
reader never sees half a file (5), each against the inbox module on a
home on disk and against the broken version it must catch (files named
by arrival, edits not applied, hidden addresses shown, files written in
place).  Also: a file is written only when it changes and a removed one
comes back without touching the log; a tag or id that cannot name a file
is refused; and one real gatherer on 127.0.0.2 writes the inbox at
start-up and from its filing hook after a typed message (`from: me`),
with a sync interval long enough that a sync cannot be what wrote them.
Referee 4 (typed becomes sent, with the issue's `room:` / `written:`
header) belongs to step 2.  Run under the loopback-only wrapper:
`luajit src/gatherer/tests/182-test-inbox-files.lua [project]`; prints
PASS/FAIL and "counts <passed> <failed>".
