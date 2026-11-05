# 144-test-call-back.lua

Issue 204's referees 1–5. Each runs against the real modules and against
a deliberately broken version that it must catch:
1. A genuine claim is confirmed, even across a restart of the claimant.
2. Another home's pair is answered `no`, and an empty pair not at all.
3. The source address is never called.
4. Silence after the answer time is not confirmation, and the check is
   retried.
5. A replayed `did-you` gets the same answer and changes nothing.

It also checks the claims file, the two records, a confirmed leave, and
the answer-time setting. It runs in 143's simulated world; claims are made
with 141 directly in place of 205's hello and 208's leave.

Run: `luajit src/delivery/tests/144-test-call-back.lua [project folder]`
(about 1 s).
