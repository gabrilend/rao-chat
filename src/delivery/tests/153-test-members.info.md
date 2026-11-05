# 153-test-members.lua

Issue 207's referees 1–6, run against the real modules in 143's
simulated world. Where the issue names a broken version, the referee must
catch it:
1. C joins through A; B learns C from A's digest, asks, calls C back and
   adds C, and C receives the list (205's referee 1, second half). It
   catches sending the digest only to the newcomer.
2. One digest per notice, nothing in 10 idle minutes, and a reordered
   entry sends nothing. It catches sending a digest for pairs added from
   a list.
3. A pair B ignores is neither called back nor added. It catches a
   missing ignore check.
4. In a child room, C arrives flagged and is never sent to.
5. A's list holds no private pair, and one that arrives anyway is not
   called back. It catches the list sent verbatim.
6. A list recorded before C leaves, replayed to a restarted A, leaves C
   out. It catches adding list pairs without 208's guard.

It also checks the records, the digest as a set, what is shareable, that
anyone may ask, and that held pairs and a home's own list are skipped.
The homes use documentation addresses (198.51.100.x). Run it under the
loopback-only wrapper.

Run: `luajit src/delivery/tests/153-test-members.lua [project folder]`
