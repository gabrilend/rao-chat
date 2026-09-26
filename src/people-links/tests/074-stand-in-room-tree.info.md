# tests/074-stand-in-room-tree.lua

A small stand-in for 102's `021-room-tree`, used in `stand-in` and
`real-101` modes.

| function | takes | gives |
|---|---|---|
| `tree_parent_of(home, tag)` | home, tag | the held room whose token fingerprint the entry's `parent` names; else the entry's `filed_under`; else `""` |
| `snapshot(home)` | home | `{entries = tag -> entry, parent = tag -> tree_parent_of}` (only the two fields people-links reads) |
