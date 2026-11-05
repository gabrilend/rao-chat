# 163-gatherer.lua

One mailbox's gatherer (issue 211): `luajit 163-gatherer.lua <project>
<disk home> <mailbox tag>`.  It claims its port before anything else; a
port another program holds is named, with its `mailboxes` line, in state
and the running log, and it exits.  Then it loads the RAM home and runs
these threads under 162's loop:

- listener: accepts, at most `gatherer.connection-limit` held (the
  oldest is closed to make room); each connection gets
  `gatherer.frame-deadline` seconds per whole frame.
- each connection: puts frames in `arrived/` and sends what appears in
  `answers/`.
- filer: takes from `arrived/`, runs 133's `answer_frame`, and with
  `gatherer.acknowledge-after = disk` forces the room's log to disk before
  the answer exists.  An error ends that frame only.
- typed: `typed/` files (`room = <tag>`, a blank line, the text) become
  messages through 134's `write`.
- sender: 134's passes, each due item in its own thread; `due/` is
  rewritten after each attempt, one file per (pair, room) still owed.
- sync: every `gatherer.sync-interval` seconds, and once more at `stop`.
- state: written every second; a repeated problem is logged at most once
  per sync interval, with a count.

Text copies (215): git is required (without it the problem names the
program and it exits, status 1); the mailbox's repository is made at
start-up (173).  After each frame is answered, and after each typed
message is written, the filing hook brings that room's copies up to date;
a hook that fails is a `hook-text-copy` problem line and ends nothing.
Each sync cycle brings every room's copies up to date from its log and
commits once.  It reads `git.home-name`.

`RAO_COPIES_BROKEN` and `RAO_COPIES_FAIL` are 175's.
`RAO_GATHERER_BROKEN` and `RAO_GATHERER_CRASH` select the broken
versions and crash points that 167's referees must catch; nothing else
reads them.
