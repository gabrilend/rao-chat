# 146-test-hello.lua

Issue 205's referees, run in 143's simulated world against the real
modules; where the issue names a broken version, the referee must catch
it:
1. Joining: A joins with the token and B's pair; B calls A back, then adds
   A (catches adding without a call-back).
2. A hello naming a port where nothing listens stays unconfirmed (catches
   adding on receipt).
3. A pair without its port fails to decode (catches a default port).
4. A hello to a child room from a pair not in the parent is added flagged.
5. Two idle homes: one hello round and its call-backs, then silence, also
   after a restart (catches answering a hello with a hello).
6. A home's own hello sent back adds nothing (catches a receiver without
   the reflection guard).
7. In part: after a move the new pair is added beside the old one.

It also checks the record, the pairs stated (home-network only to a
housemate), one claim id for several pairs, the hello before the first
message, and a stage with no `own_pairs`.

Run: `luajit src/delivery/tests/146-test-hello.lua [project folder]`
(about 1 s).
