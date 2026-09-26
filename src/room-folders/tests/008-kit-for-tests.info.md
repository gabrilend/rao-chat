# tests/008-kit-for-tests.lua

The toolkit room-folders' tests use.  Load with `dofile`; returns a table.

| function | takes | gives | what it does |
|---|---|---|---|
| `setup(dir)` | project folder: string | the room-folders module | Makes the RAM scratch folder `tmp/shared-memory/room-folders/`, sets the search path. |
| `check(name, test)` | string, function | nothing | Runs `test`; prints `PASS name` or `FAIL name: reason` and counts it. |
| `same(got, want, what)` | any, any, string or nil | nothing | Errors unless `got == want`. |
| `same_list(got, want, what)` | list, list, string or nil | nothing | Errors unless the lists match item by item. |
| `fails(action, text)` | function, string | nothing | Errors unless `action` raises an error containing `text` (plain substring). |
| `fresh_home_dir(name)` | string | string | An absolute path in the scratch folder, emptied first. |
| `test_home(rooms, name, merge)` | the module, string, `""`, `"automatic"` or `"ask"` | home | A fresh home with its direct mailbox (port `DIRECT_PORT`, 7700) made; with a value, `mailboxes.merge-when-parent-arrives` set to it (`""` leaves it unset). |
| `port_for(kind, parent)` | string, string | integer or `""` | What a make_room spec's `mailbox_port` must be: a fresh port for a top group room, `""` otherwise. |
| `port_for_home(rooms, home, kind, parent)` | the module, home, string, string | integer or `""` | As `port_for`, and also a fresh port for a group room whose declared parent is not held in `home` (it starts its own mailbox). |
| `fresh_port()` | — | integer | The next unused port from 7001 upward, so test mailboxes never share a port by accident. |
| `read_file(path)` / `write_file(path, text)` | string (, string) | string / nothing | Plain file helpers for checking what is on disk. |
| `finish()` | — | exits | Prints `counts <passed> <failed>` and exits 0 only if nothing failed. |

Runner: `tests/018-run-tests [project folder]` runs every `*-test-*.lua`, adds up
the counts, shows FAIL/NOTE lines, exits 1 on any failure or crash.
