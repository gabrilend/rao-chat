# 177-running-log.lua

The gatherer's running log, committed every sync cycle (issue 215a).
`take_and_commit(folder, repo, name, limit)` reads the RAM `running-log`
(whole lines), appends them to `running-log/<name>/<NNNN>.log` on the
branch `running-log/<name>` (an index of its own, on the branch's own
tip, never checked out), and only then takes the committed bytes off the
front of the RAM file; a failure leaves RAM as it was.  The split is
138's numbered rule, line by line: a new file before a line would pass
`git.log-file-size`, a longer line split across files.  `settings(home)`
reads the limit strictly.
