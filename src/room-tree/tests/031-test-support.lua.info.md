# tests/031-test-support.lua

Shared helpers for the room-tree tests (`dofile`d, returns a table).

| function | takes | gives | purpose |
|---|---|---|---|
| `setup(dir, which)` | string (project folder), `"stand-in"` or `"real"` | room-folders module, room-tree module (021), forest-text module (024) | loads the tree on top of the stand-in (030) or the real room-folders; anything else is an error. |
| `fresh_home(rooms, name)` | room-folders module, string | home | an empty home at `tmp/shared-memory/room-tree/<which>/<name>`. |
| `room(rooms, home, label, token, parent_room, members)` | module, home, string, string, tag or `""`, list of `{address, port}` | tag | makes a group room through `make_room`; `parent_room` is a room in the same home whose token's fingerprint becomes `parent`. |
| `members(pairs)` | list of `{address (string), port (integer)}` | list of `{address, port, heard = 0}` | member records as 101 takes them. |
| `check(condition, label)` | bool, string | — | counts a pass or prints a failure. |
| `equal(got, wanted, label)` | any, any, string | — | `check` on `==`, printing both on failure. |
| `same_list(got, wanted, label)` | list, list, string | — | compares two lists of strings. |
| `refuses(fn, pattern, label)` | function, string, string | — | passes when `fn` raises an error whose message holds `pattern` (plain text). |
| `finish(name)` | string | exits | prints the counts; exit 1 on any failure. |

Other files in `tests/`:

- `029-measure-tree.lua [DIR] [sizes] [tree-only|with-people]` — times a
  snapshot, a `may_join` and a `make_room` at growing home sizes against
  the real 101 (not run by the runner; not pass/fail).
- `030-stand-in-room-folders.lua` — the stand-in for 101 (same names as
  the contract's 101 table, a fake fingerprint of the real length).
- `032-test-tree`, `033-test-two-homes`, `034-test-membership`,
  `035-test-rings`, `037-test-forest-text` — run against either module.
- `036-test-with-neighbours.lua` — real only: loads 103 and 104 too;
  103's refusals follow `may_join`, 104's tops agree with the tree.
- `038-run-tests.sh [DIR] [stand-in|real|both]` — the runner (exit 1 on a
  failure, 3 when the real module was absent; never runs `-done` files).
