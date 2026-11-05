# 167-test-gatherer.lua

Issue 211's referees, run against real gatherer processes on loopback
(127.0.0.2 to .4) inside a network namespace with only `lo`.  Each that
the issue gives a broken version runs that version too and must catch
it.  Homes and RAM folders go in a folder of its own under /dev/shm,
removed at the end.  `ONLY=<words>` runs the checks whose name holds
them; `KEEP=1` leaves the folder.
