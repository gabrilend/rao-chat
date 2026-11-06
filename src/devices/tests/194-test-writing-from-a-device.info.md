# 194-test-writing-from-a-device.lua

Issue 305's referees: a file 183 writes into the mirror reaches the
room's gatherer's `typed/` in 301's shape and leaves the mirror; a
`typed-ok` for another file removes nothing; a file the home refuses is
kept with its reason (broken: `drop-refused`); the home refuses what the
filer would; the same file sent twice is put once (broken: `no-dedupe`),
and after a restart under the same name and bytes.  Run under the
loopback-only wrapper (127.0.0.2 and .4, port 46305):
`luajit src/devices/tests/194-test-writing-from-a-device.lua [project]`.
