# 155-test-housemates.lua

Issue 213's referees 1–4, run against the real modules in 143's
simulated world, with two homes behind one router that cannot loop back.
Where the issue names a broken version, the referee must catch it:
1. A discover whose source is the router's: the pair kept is the one
   inside the seal. It catches using the packet's source.
2. A connection from a private address on another network keeps nothing
   and is logged once. It catches recording the source.
3. A home with no pair at its public address sends no datagram. It
   catches searching every room.
4. A found pair is kept only after it answers yes, and is never a member
   or in a members list. It catches keeping on receipt.

It also checks the records, reading the routing table, the real mask,
the sweep, the RAM file across a restart, the ports, a message routed
inside the house, and one real datagram over 127.0.0.1. Run it under the
loopback-only wrapper.

Run: `luajit src/delivery/tests/155-test-housemates.lua [project folder]`
