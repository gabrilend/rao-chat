# 151-test-reach.lua

Issue 212's referees 1–8, run against the real modules. Where the issue
names a broken version, the referee must catch it:
1. A mailbox behind a forward from 52000 to 41000 states 52000, and the
   call-back lands. It catches stating the listening port.
2. Two mailboxes state their own outside ports. It catches one home-wide
   port.
3. One operator's answer does not move the home, and two operators' do,
   once. It catches counting a second resolver of the same operator.
4. Silence keeps the stored address and checks again sooner.
5. A change after start-up is seen within one window. It catches checking
   at start-up only.
6. The private-range table is exact. It catches a `172.` prefix test.
7. Carrier-grade translation is named and never stated. It catches
   classifying it as public.
8. A missing outside port is an error naming the line. It catches using
   the listening port.

It also checks a confirmed move ending in fresh hellos, the pairs by
kind, the kernel's address lists from fixtures, the settings, and a DNS
question and answer over loopback UDP. Run it under the loopback-only
wrapper.

Run: `luajit src/delivery/tests/151-test-reach.lua [project folder]`
