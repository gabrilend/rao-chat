# 129-test-key-tying.lua

Issue 201a's referees 1-4, each run against the real code and against a
deliberately broken version it must catch; what each broken version was
caught on is printed under its check.

Referee 1 builds a frame whose GCM check passes under two room keys, with
GCM's own arithmetic (GF(2^128) multiplication and inversion, GHASH) done
in the test.  A setup check compares that arithmetic with OpenSSL's tags
first, so a mistake in it fails loudly instead of passing quietly.
Referee 3 runs a keyring of 1,000 rooms (about a second).

Run: `luajit src/sealing/tests/129-test-key-tying.lua [project folder]`
(the folder defaults to the one the file is in).  Prints `PASS`/`FAIL` per
check and `counts <passed> <failed>`; exits 0 only when nothing failed.
A test home is made under `tmp/shared-memory/key-tying/` and removed.
