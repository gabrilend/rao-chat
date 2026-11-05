# 143-test-world.lua

The simulated world the delivery tests run in. It was taken out of 137 so
that 202's referees (137) and 204's (144) share it. It has:
- a fake clock and cooperative threads;
- an in-memory relay that can delay, refuse, drop or replace what passes,
  records every connection attempt, and gives connections `settimeout`;
- real homes, each with an accepting stage, a serving stage and a sending
  stage, that can be restarted on the same home;
- the check kit.

A home made with `lan` (213) has `housemates` (154): it hears datagrams
sent on its home network (`world.send_datagram`, the multicast group
included), routes connections through its kept housemates, and connects
from its home address; `world.refuse` models a router that cannot loop a
connection back in.

Each home's serving stage hands hellos and leaves to 147's `on_claim`
and members frames to 152's `answer` (207).

Use it as `dofile(...)(DIR, name)`, which returns a table of these. Its
`finish()` prints the counts and exits.
