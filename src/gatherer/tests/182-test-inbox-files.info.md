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
`typed/` files in 301's shape and 211's are read and anything else
refused, a written time in the future is the filer's clock, and two
files with the same text are two ids.  `.room` gives the label, kind,
parent and path worked out on the whole home (not the gatherer's RAM
home, which may lack the parent: broken version `ram-tree`), members,
flagged and the pile, which empties after an acknowledgement; `.tree`
has one line per room with its parent.  Referee 4 runs two gatherers (A
on 127.0.0.2, B on .3): a typed file in 301's shape is filed at its own
written time, waits for B (A's `.room` shows it in the pile), is sent
and acknowledged, is in A's inbox once as `from: me`, and the typed file
is gone; with A crashing between filing and removing the typed file, it
is still filed and sent once (broken: `typed-fresh-id`, a duplicate;
`typed-remove-first`, lost); and the pile empties when B acknowledges,
not at the next sync (broken: `stale-pile`).  Run under the loopback-only wrapper:
`luajit src/gatherer/tests/182-test-inbox-files.lua [project]`; prints
PASS/FAIL and "counts <passed> <failed>".
