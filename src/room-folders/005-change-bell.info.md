# 005-change-bell.lua

The change bell.  Code that changes a room rings it; modules keeping
summaries (`where`, `people/`) listen.  One bell per running program
(`require` shares it).  Reached through `002-room-folders`, which
re-exports all of it.

| function / value | takes | gives | what it does |
|---|---|---|---|
| `on_change(listener)` | function(home, tag, what) | nothing | Signs the listener up; listeners are told in sign-up order. |
| `notify(home, tag, what)` | home table, string, string | nothing | Tells every listener.  Errors on an unknown `what`, a non-home, or a tag that does not fit the kind's scope.  A listener's error stops the ring and reaches the caller. |
| `listener_count()` | — | integer | How many listeners signed up. |
| `BELL_KINDS` | — | table what (string) → `{scope = string, meaning = string}` | The kinds: `created label token members heard parent filed withheld log ignore removed-room`.  `scope = "room"`: the tag must be a local tag.  `scope = "home-or-room"` (only `ignore`): `""` for the whole home, or a local tag. |
