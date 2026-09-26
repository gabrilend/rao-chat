# 060-neighbour-reads.lua

The only file in people-links that calls another module.  Loaded with
`require("060-neighbour-reads")`; needs `002-room-folders` (issue 101) and
`021-room-tree` (issue 102).

Types: **home** is `{dir = string}`; a **tag** is 32 lower-case hex
characters; a **member key** is the string `"<address> <port>"`.

| function | takes | gives | purpose |
|---|---|---|---|
| `read_all(home)` | home | `tags` (sorted list of tags), `rooms` (tag → `{tag = string, label = string, kind = "group"\|"direct", members = list of member keys, tree_parent = tag or ""}`) | Every room in one pass, from 102's `snapshot(home)` (`entries` and `parent`).  Errors on a kind other than group/direct. |
| `config_value(home, key)` | home, string | string | 101's strict config read (error when absent). |
| `on_change(listener)` | function(home, tag, what) | nothing | Registers on 101's change bell. |
| `member_key(pair)` | `{address = string, port = integer or string}` | string | `"<address> <port>"`; equal keys mean the same member. |

Why one snapshot: asking 102 room by room re-reads the whole home per room;
measured at 100 rooms, a rebuild took 1.2 s that way and 12 ms with one
snapshot.
