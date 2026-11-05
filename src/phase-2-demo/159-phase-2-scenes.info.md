# 159-phase-2-scenes.lua

The scenes of the phase 2 demo (issue 210), loaded by 158.

`M.ORDER`: the scenes in order, each `{key, title, issues}`.  `M[key]` is
either a function `(c) → {lines, gaps}` or, for a scene whose issue is not
built, `{waits = "<issue>: why"}`.

`c` (from 158): `T` (143's test world), `dir`, `scratch`, `m` (the modules
by short name: rooms, disk, tokens, tree, forest_text, recipients, ignore,
people, message_log, room_key, seal, records, keyring, delivered,
receive, delivery, fd, claims, call_back, hello, leaving, reach, public,
members, housemates, crosscheck, ram, loopback), `break_scene`.

Each scene resets the world, makes real rao-homes (each with its own RAM
folder), runs phase 2's stages between them on the simulated clock, and
returns lines read from the homes' files and the stages' state.  `gaps`
names a part that could not run (`fail2ban-regex` when it is not
installed; the home starters, when the demo is not in a loopback-only
namespace).

Two scenes run real processes instead (211): `gatherers` starts each
home's starter (164), which starts its gatherer (163), on 127.0.0.2, .3
and .4; it kills one gatherer and shows the starter start it again,
stops B and shows A's `due/` file for B, then starts B and shows `due/`
empty.  `acknowledge` runs two gatherers with
`gatherer.acknowledge-after` set each way, cuts the power under B after
10 answers, and counts what reached B's disk.  `git` (215) runs two
gatherers that each write a message, shows A's repository and a copy
whole, compares A's and B's copies byte for byte, edits one of B's by
hand and shows the commit and both logs unchanged, B's `labels`, and A's
`code/<name>` branch (from its starter), then A's running log on its
own branch (215a): its files and sizes, its first lines, and that the
two branches hold none of each other's files; and (215b) a bare
repository in the scene's folder as both homes' shared upstream: each
home's pulls, pushes and last moment, the upstream's branches, one file
per message with B's hand edit in it, and B's program readable on A and
never checked out.  All three bring the
namespace's loopback up (168) and stop every process they started.

`signatures` reads 214's table (170) with 169's rule and shows each
example's signature; 214's viewer field is named as not run (it waits on
301).

Addresses: every home has its own address and stated ports.  Most scenes
use 127.0.0.2, .3, .4 (.5 for a second pair, .6 for a joiner).  The
child and syncing scenes use 198.51.100.x (documentation addresses) for
the homes, because 207 never puts a loopback pair in a member list; the
syncing scene first shows the loopback homes' list coming out empty.
Nothing leaves the in-memory relay either way.

The scenes: delivery, down, join, keys, child, syncing, token, leaving,
crosscheck, housemates, failed, signatures, git, acknowledge, phase1; `gatherers` comes after
`down`.
