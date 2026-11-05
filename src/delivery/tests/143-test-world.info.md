# 143-test-world.lua

The simulated world the delivery tests run in. It was taken out of 137 so
that 202's referees (137) and 204's (144) share it. It has:
- a fake clock and cooperative threads;
- an in-memory relay that can delay, refuse, drop or replace what passes,
  records every connection attempt, and gives connections `settimeout`;
- real homes, each with an accepting stage, a serving stage and a sending
  stage, that can be restarted on the same home;
- the check kit.

Use it as `dofile(...)(DIR, name)`, which returns a table of these. Its
`finish()` prints the counts and exits.
