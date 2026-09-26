# 002-room-folders.lua

The front door of room-folders: opens a rao-home, reads and writes its
settings, makes, reads and changes rooms (group rooms and direct messages
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
  - `filed_under` string — a held room's local tag, or `""`
  - `members` list of tables, each `{ address = string, port = integer 1–65535, heard = integer ≥ 0 (seconds since 1970; 0 = never) }`
- "None" is always `""`, never nil.

## Home and settings

| function | takes | gives | what it does |
|---|---|---|---|
| `open_home(dir)` | string, absolute | home | Makes `dir`, `config`, an empty `ignore`, `rooms/`, `people/` if missing; leaves existing ones alone.  Errors on a relative path, a missing folder above, or `dir` being a file. |
| `read_config(home)` | home | table string→string | Every setting in `config`; values stay strings.  Errors on a malformed line or a key set twice. |
| `set_config(home, key, value)` | home, string (`[A-Za-z0-9_.-]+`), string (one line, no edge spaces) | nothing | Rewrites the key's line in place or appends it. |
| `config_value(home, key)` | home, string | string | The value; **errors** when absent, naming the line to add. |

## Rooms

| function | takes | gives | what it does |
|---|---|---|---|
| `new_local_tag()` | — | string | 16 bytes of `/dev/urandom` as hex. |
| `is_local_tag(value)` | anything | bool | Shape check. |
| `make_room(home, spec)` | spec `{label, token, kind, parent, filed_under, members}`, all required | local tag | Builds `entry`, empty `withheld`, empty `log` in `rooms/.new-<tag>/`, renames into place, rings `created`.  Refuses: a missing or unknown spec field, any bad field (see 006-entry), a token already held here, a parent chain leading back to the room, a filing that is unheld/self/looping. |
| `read_entry(home, tag)` | home, tag | entry | Read fresh from disk every call; errors on a missing room or a malformed entry (naming the file). |
| `write_label(home, tag, label)` | | nothing | Rings `label`. |
| `write_members(home, tag, members)` | list as above | nothing | Replaces the members, in the order given; rings `members`.  Shape only — who may join is 103's and 102's. |
| `write_heard(home, tag, address, port, when)` | string, integer, integer ≥ 0 | nothing | Sets one pair's `heard`; rings `heard`.  Errors if the pair is not a member. |
| `write_parent(home, tag, fingerprint)` | fingerprint or `""` | nothing | Rings `parent`.  Refuses a room inside itself; an unheld parent is allowed. |
| `write_filed_under(home, tag, other)` | tag or `""` | nothing | Rings `filed`.  Refuses self, an unheld tag, a filing loop. |
| `change_token(home, tag, token)` | string | nothing | Keeps folder, label, members, withheld, log.  Writes the entry, re-points held children from the old fingerprint to the new one (each rings `parent`), then rings `token`.  Refuses a token held by another room. |
| `list_rooms(home)` | home | sorted list of tags | Skips `.new-` folders; errors on any stranger in `rooms/`. |
| `list_rooms_by_kind(home, kind)` | `"group"`/`"direct"` | sorted list of tags | |
| `find_by_fingerprint(home, fingerprint)` | fingerprint | tag or `""` | Errors if two folders hold one token (a copied folder). |
| `room_exists(home, tag)` | | bool | |
| `room_dir`, `entry_path`, `withheld_path`, `where_path`, `log_path` `(home, tag)` | | string | Absolute paths; errors on a malformed tag. |
| `ignore_path(home)` | | string | `<home>/ignore`. |

## Tokens (from 007-tokens)

| function | takes | gives |
|---|---|---|
| `token_fingerprint(token)` | string, one line, non-empty | fingerprint |
| `is_fingerprint(value)` | anything | bool |
| `suggest_token(home)` | home | string of N list words joined by `-`, N from config `rooms.suggested-token-words` (no default) |
| `suggest_token_of(n)` | integer ≥ 1 | the same, N given |

## The change bell (from 005-change-bell)

| function / value | takes | gives |
|---|---|---|
| `on_change(listener)` | function(home, tag, what) | nothing |
| `notify(home, tag, what)` | home, tag (or `""` for `ignore`), a kind from `BELL_KINDS` | nothing; a listener's error passes through |
| `listener_count()` | — | integer |
| `BELL_KINDS` | — | table what → `{scope = "room" or "home-or-room", meaning = string}` |
| `KINDS` | — | table `"group"`/`"direct"` → meaning |
| `SUGGESTED_WORDS_KEY` | — | `"rooms.suggested-token-words"` |
