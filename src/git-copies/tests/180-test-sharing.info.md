# 180-test-sharing.lua

Issue 215b's six referees, with real gatherers on loopback whose only
upstreams are bare repositories in the test folder (never a real remote):
the three moments (start-up, a recheck file, the stop and SIGTERM), two
homes filing one message without a conflict, two different edits of one
copy reported as a conflict with both kept, another home's `code/` branch
readable and never checked out or run, a child room's copies kept from a
top-room member who fetches the upstream under each `git.upstream-rooms`
choice (on homes on disk), and a black-holed upstream on 127.0.0.9 that
delays no delivery and is reported failed within its deadline.  Each
referee catches its broken version (`RAO_SHARE_BROKEN`).  Run under the
loopback-only wrapper; prints PASS/FAIL and "counts".
