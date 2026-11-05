# 148-test-leaving.lua

Issue 208's referees, run in 143's simulated world against the real
modules. Where the issue names a broken version, the referee must catch
it:
1. A genuine leave removes the pair, writes the `left` line and drops the
   `delivered` line.
2. A forged leave naming A's pair is answered `no` by A, and nothing
   changes. It catches removing on receipt.
3. A's new message after its leave re-adds A and clears the line.
4. A members list recorded before the leave and replayed after it leaves
   A out. It catches a leave with no record. 207 is stood in for.
5. A message pending for A at the leave is never sent. It catches keeping
   the `delivered` line.
6. Open question 1: a replayed leave older than A's newest message is
   ignored. It catches a missing written-time guard.

It also checks the record and a late old message. It checks that a hello
undoes a leave, that a home that left makes no start-up hello there, and
that a home's own leave sent back changes nothing.

Run: `luajit src/delivery/tests/148-test-leaving.lua [project folder]`
(about 2 s).
