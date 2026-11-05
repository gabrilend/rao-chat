# 178-test-running-log.lua

Issue 215a's four referees, against the running-log module on
repositories in the test folder with a fake clock's lines (limit 1,000
bytes, 10,000 bytes in cycles, one of 2,500; a locked branch; a config
without the setting; the two branches apart), each with its broken
version: a split after the limit, an oversize cycle dropped, RAM emptied
before the commit, a missing setting defaulted, the log branch built on
the rooms' tree.  Then a real gatherer on loopback commits its own lines.
Run under the loopback-only wrapper; prints PASS/FAIL and "counts".
