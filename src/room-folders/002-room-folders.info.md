# 002-room-folders.lua

The front door of room-folders: opens a rao-home, reads and writes its
settings, keeps its mailboxes (which listening port each group of rooms
uses), makes, reads and changes rooms (group rooms and direct messages
alike), works with tokens, and rings the change bell after every change.
Load with `require("002-room-folders")` after `001-load-path.lua` has run.

- A **home** is a table `{ dir = string }` (absolute path of rao-home, no trailing slash).
- A **local tag** is a string of 32 lower-case hex characters naming a room's folder; never sent.
- A **fingerprint** is a string of 64 lower-case hex characters: `SHA-256(SHA-256(token))`.
- An **entry** is a table:
  - `tag` string — the local tag
  - `label` string — your name for the room (one line, non-empty)
  - `token` string — the shared secret (one line, non-empty)
  - `kind` string — `"group"` or `"direct"`
  - `parent` string — parent's fingerprint, or `""`
  - `mailbox` string — the local tag of the mailbox the room is in (never `""`)
  - `filed_under` string — a held room's local tag, or `""`
  - `members` list of tables, each `{ address = string, port = integer 1–65535, heard = integer ≥ 0 (seconds since 1970; 0 = never) }`
- A **mailbox** is a table `{ tag = string (32 hex), label = string (one line), kind = "tree" | "direct" | "waiting", port = integer 1–65535 }`.
- A **port** is always a whole number 1–65535; there is no default port anywhere.
- "None" is always `""`, never nil.

## Home and settings

| function | takes | gives | what it does |
|---|---|---|---|
| `open_home(dir)` | string, absolute | home | Makes `dir`, `config`, an empty `mailboxes`, an empty `ignore`, `rooms/`, `people/` if missing; leaves existing ones alone.  Errors on a relative path, a missing folder above, or `dir` being a file. |
| `read_config(home)` | home | table string→string | Every setting in `config`; values stay strings.  Errors on a malformed line or a key set twice. |
| `set_config(home, key, value)` | home, string (`[A-Za-z0-9_.-]+`), string (one line, no edge spaces) | nothing | Rewrites the key's line in place or appends it. |
| `config_value(home, key)` | home, string | string | The value; **errors** when absent, naming the line to add. |

## Rooms

| function | takes | gives | what it does |
|---|---|---|---|
| `new_local_tag()` | — | string | 16 bytes of `/dev/urandom` as hex. |
| `is_local_tag(value)` | anything | bool | Shape check. |
| `make_room(home, spec)` | spec `{label, token, kind, parent, filed_under, members, mailbox_port}`, all required; `mailbox_port` integer when the room starts a new mailbox, else `""` | local tag | Picks the room's mailbox (below), builds `entry`, empty `withheld`, empty `flagged`, empty `log` in `rooms/.new-<tag>/`, renames into place, rings `created`, then settles waiting rooms.  Refuses: a missing or unknown spec field, any bad field (see 006-entry), a token already held here, a parent chain leading back to the room, a filing that is unheld/self/looping, a port where none belongs or none where one does, a missing direct/waiting mailbox. |
| `read_entry(home, tag)` | home, tag | entry | Read fresh from disk every call; errors on a missing room or a malformed entry (naming the file). |
| `write_label(home, tag, label)` | | nothing | Rings `label`. |
| `write_members(home, tag, members)` | list as above | nothing | Replaces the members, in the order given; rings `members`.  Shape only — who may join is 103's and 102's. |
| `write_heard(home, tag, address, port, when)` | string, integer, integer ≥ 0 | nothing | Sets one pair's `heard`; rings `heard`.  Errors if the pair is not a member. |
| `write_parent(home, tag, fingerprint)` | fingerprint or `""` | nothing | Rings `parent`, then settles waiting rooms.  Refuses a room inside itself; an unheld parent is allowed.  The room keeps its mailbox (unless it was waiting). |
| `write_filed_under(home, tag, other)` | tag or `""` | nothing | Rings `filed`.  Refuses self, an unheld tag, a filing loop. |
| `change_token(home, tag, token)` | string | nothing | Keeps folder, label, members, withheld, log.  Writes the entry, re-points held children from the old fingerprint to the new one (each rings `parent`), then rings `token`, then settles waiting rooms.  Refuses a token held by another room. |
| `list_rooms(home)` | home | sorted list of tags | Skips `.new-` folders; errors on any stranger in `rooms/`. |
| `list_rooms_by_kind(home, kind)` | `"group"`/`"direct"` | sorted list of tags | |
| `find_by_fingerprint(home, fingerprint)` | fingerprint | tag or `""` | Errors if two folders hold one token (a copied folder). |
| `room_exists(home, tag)` | | bool | |
| `room_dir`, `entry_path`, `withheld_path`, `flagged_path`, `where_path`, `log_path` `(home, tag)` | | string | Absolute paths; errors on a malformed tag. |
| `ignore_path(home)` | | string | `<home>/ignore`. |

## Mailboxes

Where `make_room` puts a room: a `direct` room → the one direct mailbox
(`mailbox_port = ""`); a group room with no parent → a new `tree` mailbox
labelled with the room's label, on `mailbox_port`; a group room whose
declared parent is held → the parent's mailbox (`""`); a group room whose
declared parent is not held → config `mailboxes.unheld-parent`:
`own-mailbox` (a new tree mailbox, `mailbox_port` given) or
`waiting-mailbox` (the one waiting mailbox, `""`; the room moves into its
parent's mailbox when the parent arrives).

| function | takes | gives | what it does |
|---|---|---|---|
| `make_mailbox(home, spec)` | `{label, kind = "direct" or "waiting", port}` | mailbox tag | At most one of each per home; tree mailboxes are made only by `make_room`.  Rings `mailbox` with `""`. |
| `read_mailboxes(home)` | home | list of mailbox, sorted by tag | Reports every port shared by two or more mailboxes to the warning sink, every call. |
| `read_mailbox(home, mailbox_tag)` | | mailbox | Errors if absent. |
| `direct_mailbox(home)` / `waiting_mailbox(home)` | | tag or `""` | The one of that kind, or `""` if not made. |
| `list_rooms_by_mailbox(home, mailbox_tag)` | | sorted list of room tags | Errors on an unknown mailbox. |
| `mailboxes_by_port(home, port)` | integer | sorted list of mailbox tags | Which mailboxes a frame arriving on `port` is tried against. |
| `shared_ports(home)` | | list of `{port = integer, mailboxes = sorted list of tags}` | Ports named twice or more (reported as a read is). |
| `write_mailbox_port(home, mailbox_tag, port)` | integer | nothing | Rings `mailbox` with `""`. |
| `write_mailbox(home, tag, mailbox_tag)` | room tag, mailbox tag | nothing | Moves a room by hand; a direct room only into the direct mailbox, a group room only into a tree or waiting one.  Rings `mailbox` with the room's tag. |
| `set_warning_sink(fn)` | function(text) | nothing | Where shared-port reports go (starts as one `rao-chat WARNING:` line on stderr). |
| `mailboxes_path(home)` | | string | `<home>/mailboxes`. |

## Tokens (from 007-tokens)

| function | takes | gives |
|---|---|---|
| `token_fingerprint(token)` | string, one line, non-empty | fingerprint |
| `is_fingerprint(value)` | anything | bool |
| `suggest_token(home)` | home (checked, nothing read) | string of six list words joined by `-` |
| `suggest_token_of(n)` | integer ≥ 1 | the same, N given |

## The change bell (from 005-change-bell)

| function / value | takes | gives |
|---|---|---|
| `on_change(listener)` | function(home, tag, what) | nothing |
| `notify(home, tag, what)` | home, tag (or `""` for `ignore` and `mailbox`), a kind from `BELL_KINDS` | nothing; a listener's error passes through |
| `listener_count()` | — | integer |
| `BELL_KINDS` | — | table what → `{scope = "room" or "home-or-room", meaning = string}` |
| `KINDS` | — | table `"group"`/`"direct"` → meaning |
| `MAILBOX_KINDS` | — | table `"tree"`/`"direct"`/`"waiting"` → `{how_many = "many" or "one", meaning}` |
| `SUGGESTED_WORD_COUNT` | — | `6` |
| `UNHELD_PARENT_KEY` | — | `"mailboxes.unheld-parent"` |
