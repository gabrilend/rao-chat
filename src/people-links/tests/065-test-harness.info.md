# tests/065-test-harness.lua

Shared helpers for the people-links tests.  `dofile` it; it returns a table
`H` holding counters `passed`, `failed` (integers) and these functions:

| function | takes | gives | purpose |
|---|---|---|---|
| `setup(dir, mode)` | string, `"stand-in"`, `"real-101"` or `"real"` | nothing | Loads the modules into `H.rooms`, `H.tree`, `H.people`, `H.disk`, `H.names`: stand-in 101 and 102 (064, 074), real 101 with the stand-in 102, or both real. |
| `fresh_home(name, config)` | string, table key → string (or `false` to leave a key out) | home | A new rao-home under `tmp/shared-memory/people-links/<mode>-<name>`, with `people.link-collision = suffix-id`, `people.direct-message-link = leave-out`, `people.members-without-dm = leave-out` and 101's `mailboxes.unheld-parent = own-mailbox` unless `config` says otherwise; then makes the home's direct mailbox (port 7700), which rings `mailbox` — so every test also checks people-links hears that ring. |
| `pair(text)` | `"<address> <port>"` | `{address = string, port = integer, heard = 0}` | One member. |
| `group(home, label, members, opts)` | home, string, list of `"<address> <port>"`, `{parent = tag, filed = tag, parent_fingerprint = string}` or nil | tag | A group room with a fresh unique token; `parent` declares a held parent by its token's fingerprint.  Passes 101's `mailbox_port`: a fresh port (7701, 7702, …) for a top room or a room whose declared parent is not held here, `""` for a room under a held parent. |
| `direct(home, label, members)` | home, string, list | tag | A direct-message room (a person), `mailbox_port = ""` (it joins the direct mailbox). |
| `set_members(home, tag, members)` | home, tag, list | nothing | `write_members` with the pairs. |
| `fingerprint_of(home, tag)` | home, tag | string | The fingerprint of that room's token. |
| `view(home, folder)` | home, string or nil | sorted list of string | Everything under `people/` (or one folder): `"path -> target"` for links, `"path/"` for folders, `"path (file)"` for files. |
| `label_through(home, path)` | home, string | string | The label of the room a link leads to, or `"(unreachable)"`. |
| `link_line(folder, name, tag)` | strings | string | An expected view line for a flat link (`folder` `""` for a one-person view). |
| `sorted(list)` | list | list | A sorted copy. |
| `check(ok, label)` / `same(got, want, label)` / `fails(fn, fragment, label)` | | nothing | Count a check; `same` compares lists of strings; `fails` wants an error containing `fragment`. |
| `finish()` | — | exits | Prints `RESULT <mode> pass=N fail=M`, exits non-zero on any failure. |
