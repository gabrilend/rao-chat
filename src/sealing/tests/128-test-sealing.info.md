# 128-test-sealing.lua

Issue 201's referees 1-10 and the sealing note's padding referee (14),
each run against the real code and against a deliberately broken version
it must catch; what each broken version was caught on is printed under its
check.  Written from the rules, not from rmail's code.

Run: `luajit src/sealing/tests/128-test-sealing.lua [project folder]`
(the folder defaults to the one the file is in).  Prints `PASS`/`FAIL` per
check and `counts <passed> <failed>`; exits 0 only when nothing failed.
Test homes are made under `tmp/shared-memory/sealing/` and removed.
Referee 4 forks two processes through the ffi.

Not covered here, and why: referee 6's second half (a mailbox port answers
`GET / HTTP/1.0` with zero bytes) needs a listening port, which is 211's;
referee 5's "every reader in the project agrees" has one reader so far,
this one; 201a's own referee (a frame built to pass GCM under two keys)
belongs to 201a.
