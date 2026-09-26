# 042-ignore-list.lua  (issue 103a)

The home's ignore list, `rao-home/ignore` (made empty by 101's `open_home`):
one line per entry, `<address> <port> <level> <added> <scope>` — level
`hide` or `mark`, added in whole seconds since 1970, scope `*` (whole home)
or a room's local tag.  Every change rings the bell `ignore` on tag `""` for
a whole-home entry, or on the room's tag for a one-room entry.

Fixed (answered 2026-09-25): an entry covers **every port** at its address
(the port is still written, since an address is always kept as a pair); a
`hide` address's messages are **not filed** (dropped on arrival).
Reads one config key, `ignore.scope` (`home` / `home-and-room`); absent or
unknown values are errors.  `ignore.match` and `ignore.hide-files` are no
longer read.

| function | takes | gives | what it does |
|---|---|---|---|
| `entries(home)` | home | list of `{address=string, port=integer, level=string, added=integer, scope=string}` | The list, file order. |
| `ignore(home, address, port, level, scope, added)` | …, `"hide"`/`"mark"`, `"*"` or tag, integer | `"ignored"`, `"level-changed"`, `"already"` | One entry per (pair, scope).  A tag scope needs `ignore.scope = home-and-room` and a room held here. |
| `unignore(home, address, port, scope)` | | `"unignored"` | Error if there is no such entry (exact pair and scope). |
| `how_ignored(home, tag, address, port)` | | `"none"`, `"hide"`, `"mark"` | For the message view (105).  Any port at an entry's address matches; when several lines match, `hide` beats `mark`. |
| `files_message(home, tag, address, port)` | | bool | Should an arriving message be written to the log?  False only for `hide`. |
| `refused_as_member(home, tag, address, port)` | | bool | True at either level: the member filter `041-recipients` applies. |
