# 159-phase-2-scenes.lua

The scenes of the phase 2 demo (issue 210), loaded by 158.

`M.ORDER`: the scenes in order, each `{key, title, issues}`.  `M[key]` is
either a function `(c) → {lines, gaps}` or, for a scene whose issue is not
built, `{waits = "<issue>: why"}`.

`c` (from 158): `T` (143's test world), `dir`, `scratch`, `m` (the modules
by short name: rooms, disk, tokens, tree, forest_text, recipients, ignore,
people, message_log, room_key, seal, records, keyring, delivered,
receive, delivery, fd, claims, call_back, hello, leaving, reach, public,
members, housemates, crosscheck), `break_scene`.

Each scene resets the world, makes real rao-homes (each with its own RAM
folder), runs phase 2's stages between them on the simulated clock, and
returns lines read from the homes' files and the stages' state.  `gaps`
names a part that could not run (the pile in the gatherer's `due/`
folder, waiting on 211; `fail2ban-regex` when it is not installed).

Addresses: every home has its own address and stated ports.  Most scenes
use 127.0.0.2, .3, .4 (.5 for a second pair, .6 for a joiner).  The
child and syncing scenes use 198.51.100.x (documentation addresses) for
the homes, because 207 never puts a loopback pair in a member list; the
syncing scene first shows the loopback homes' list coming out empty.
Nothing leaves the in-memory relay either way.

The scenes: delivery, down, join, keys, child, syncing, token, leaving,
crosscheck, housemates, failed, signatures (waits on 214), git (waits on
215, 215a, 215b), acknowledge (waits on 211), phase1.
