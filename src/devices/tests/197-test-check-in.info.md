# 197-test-check-in.lua

Issue 308's referees: eleven deals from a fresh deck are −5 … +5 once
each (broken: `replace`); any whole number of passes averages exactly
30 s; the deck is shuffled again when it runs out, not always in the
same order (broken: `no-reshuffle`); the shuffle is fair; a `check-in`
loop with a 6 s base catches up each time and keeps no connection
between.  The last runs under the loopback-only wrapper (127.0.0.2, port
46308): `luajit src/devices/tests/197-test-check-in.lua [project]`.
