# 157-test-cross-check.lua

Issue 209's referees 1–5, run against the real modules in 143's
simulated world. Where the issue names a broken version, the referee must
catch it:
1. A message removed from B's log comes back with its own id, and a
   second summary sends nothing. It catches writing it again as new.
2. Withheld, ignored, and someone else's message: nothing is sent again.
   It catches resending to an ignored pair.
3. A message and its correction raise nothing.
4. One id with two texts, to B and to C: both raise it with both
   versions. It catches a fingerprint over `from` and `arrived`, and
   comparing ids only.
5. With no traffic, a summary leaves within the interval plus one
   second. It catches a round off the wake-up clock.

It also checks the records, the fingerprint, `forget` and `meant_for`,
207's digest riding on the round, and the window. Run it under the
loopback-only wrapper.

Run: `luajit src/delivery/tests/157-test-cross-check.lua [project folder]`
