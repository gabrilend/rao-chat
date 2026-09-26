# Phase 1 module contract — how the room modules plug together

> **Round 2 (2026-09-25): rewritten for "a room is a contact".**  The
> shared parts — where each module lives, loading, the home folder, the
> entry, the change bell, and 101's functions — describe the design in
> `notes/vision-planning.md` sections 1–4 (decided in section 15).  Each
> other module's section is rewritten by its own builder while it rebuilds;
> a section still marked "being rewritten" is not yet a promise.  The
> round-1 contract (the first model, Appendix A) is kept beside this file
> as `phase-1-module-contract.md-done` until one commit has carried it.

Phase 1 ("Rooms on the home server") is built as five modules and one demo,
each by its own builder, each in its own folder.  This document is the plug
shape they share, so each can be built before its neighbours exist.  It is
the reference the issue files 101–106 and 103a point to.

If a module needs to change the shape described here, it writes the change
into this document and posts a note on the builders' board (below) — it does
not quietly change a neighbour's file.

## Where each module lives

| issue | module folder | reading-order indexes | owns |
|---|---|---|---|
| 101 | `src/room-folders/` | 001–019 | the home folder, config, local tags, the room `entry` (rmail's contacts format), making rooms, tokens (fingerprint, readable suggestions, changing by hand), the empty `ignore`, `withheld` and `log` files at birth, the change bell |
| 102 | `src/room-tree/` | 020–039 | the tree: parent by token fingerprint, children, ancestors, top rooms, `filed-under`, the parent-membership check, the `where` file, drawing the tree as text |
| 103 | `src/recipients/` | 040–059 | members (the entry's address pairs) and when each was last heard from, the `withheld` list, the send list, leaving |
| 103a | `src/recipients/` (shares 103's range) | 040–059 | the home's `ignore` list and its two levels |
| 104 | `src/people-links/` | 060–079 | the `people/` folder of links |
| 105 | `src/message-log/` | 080–099 | the message log, message ids, ordering, repeat-safety, edits |
| 106 | `src/phase-1-demo/`, `scripts/`, `issues/completed/demos/` | 100–119 | the options tally and the phase 1 demo |

Every source file's name starts with its reading-order index (for example
`src/room-folders/002-room-folders.lua`).  Tests live in each module's own
`tests/` folder.  Each source file has a `<file>.info.md` beside it listing
its outward-facing functions with their inputs and outputs.  A retired file
is renamed `<name>-done` and kept until one commit has carried it; no test
runner runs `-done` files.

## Loading one module from another

`src/room-folders/001-load-path.lua` returns a function; called with the
project folder, it adds every `src/<module>/` folder and `libs/` to Lua's
search path.  After that, a module is loaded by its file name without
`.lua`:

    dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)
    local rooms = require("002-room-folders")

`require` hands every caller the same copy of a module, so there is one
change bell per running program.

## The home folder (rao-home)

    rao-home/
      config                  settings: key = value lines (rmail's config format)
      ignore                  the ignore list (103a's format); made EMPTY by open_home
      rooms/
        <local tag>/
          entry               one entry in rmail's contacts format (below); 101's
          withheld            one address per line (103's format); made EMPTY by make_room
          where               this folder's path and the path of labels (102's)
          log                 the messages (105's format); made EMPTY by make_room
      people/                 links (104's)
        <direct-message label>/<link name> -> ../../rooms/<local tag>

There is no `contacts` file any more: a person you talk to is a
direct-message room (`kind = direct`) under `rooms/`, built and read by the
same code as a group room.

A **home** value passed between modules is a table `{ dir = <string,
absolute path of rao-home, no trailing slash> }`.

A **local tag** is a string of exactly 32 lower-case hexadecimal characters
(16 bytes from `/dev/urandom`).  It names a room's folder on this home only
and is **never sent** to anyone; two homes holding the same room give it
different tags.  What travels is the token (sealed, phase 2) and the
token's fingerprint.

A **token fingerprint** is a string of exactly 64 lower-case hexadecimal
characters: `SHA-256(SHA-256(token))`, i.e. the room's sealing key
(`SHA-256(token)`, phase 2, as rmail makes one) scrambled once more.  The
same token gives the same fingerprint on every home; the fingerprint does
not give back the token or the key.  It is how a child room names its
parent, and how a home finds the room a token belongs to.

"None" is always the empty string `""`, never nil (no parent, not filed).

## The entry

A room's `entry` file is **one entry in rmail's contacts format**, named by
the room's local tag, so `cat rooms/*/entry` is itself a valid contacts
file (tags never repeat).  Written by 101 only, always whole
(write-to-temporary-then-rename), fields always in this order:

    // rao-chat room entry: rmail's contacts format, one entry named by its local tag
    3f9a0c1e5b7d42a8a6e1f0c2d4b6a8e0.label       = "programming"
    3f9a0c1e5b7d42a8a6e1f0c2d4b6a8e0.token       = "maple-orbit-velvet-tin"
    3f9a0c1e5b7d42a8a6e1f0c2d4b6a8e0.kind        = group
    3f9a0c1e5b7d42a8a6e1f0c2d4b6a8e0.parent      = 5e0b...(64 hex)...
    3f9a0c1e5b7d42a8a6e1f0c2d4b6a8e0.filed-under =
    3f9a0c1e5b7d42a8a6e1f0c2d4b6a8e0.ip[1]       = 203.0.113.9
    3f9a0c1e5b7d42a8a6e1f0c2d4b6a8e0.port[1]     = 7777
    3f9a0c1e5b7d42a8a6e1f0c2d4b6a8e0.heard[1]    = 1790000000
    3f9a0c1e5b7d42a8a6e1f0c2d4b6a8e0.ip[2]       = sorelu.example.org
    3f9a0c1e5b7d42a8a6e1f0c2d4b6a8e0.port[2]     = 7778
    3f9a0c1e5b7d42a8a6e1f0c2d4b6a8e0.heard[2]    = 0

| field | on disk | in Lua (`read_entry`) | rule |
|---|---|---|---|
| (name) | the local tag before each `.` | `tag` (string) | must equal the folder's tag |
| `label` | quoted text | `label` (string) | your own name for the room; non-empty, any characters but a line break (`/` allowed); never sent; may repeat across rooms |
| `token` | quoted text | `token` (string) | the room's shared secret; non-empty, any characters but a line break; **no two rooms in one home hold the same token** |
| `kind` | `group` or `direct` | `kind` (string) | a direct message is a room with one other person (who may have several machines) |
| `parent` | 64 hex or empty | `parent` (string) | the parent room's token fingerprint; `""` for a room with no declared parent.  The parent need **not** be held here (then the room is a top room, 102) |
| `filed-under` | 32 hex or empty | `filed_under` (string) | a local tag of a room held here under which you placed this one on your own screen, or `""`; its meaning is 102's (open question) |
| `ip[N]` / `port[N]` / `heard[N]` | N = 1, 2, 3 … with no gaps | `members` = list of `{address = string, port = integer, heard = integer}` in N order | **always all three together**: an address without its port, a port without its address, or either without `heard` is an error; there is **no default port** |

- `address` is an IP address (v4 or v6) or a hostname: non-empty, no
  spaces, tabs, line breaks or `"`.  `port` is a whole number 1–65535.
  The same (address, port) pair may not appear twice in one entry; the same
  address with two ports is two members.
- `heard` is when that address was last heard from, in whole seconds since
  1970; **`0` means never heard**.  103 records it (through `write_heard`)
  so a client can offer pruning of long-silent members; 101 only stores it.
- Your own devices are never members.
- Any other field, a field set twice, or a malformed value is an error that
  names the file and line; nothing is guessed.
- rmail itself writes a first address as plain `ip` (and a default `port`);
  `004-rmail-formats.address_pairs` reads that shape too (plain `ip` with
  plain `port` is pair 0), but an entry written by 101 only ever uses
  `ip[N]`/`port[N]`/`heard[N]`, numbered from 1.

## The change bell (owned by 101)

Modules keep derived files (`where`, `people/` links) true by listening for
changes instead of calling each other directly.

- `rooms.on_change(listener)` — registers `listener(home, tag, what)`.
- `rooms.notify(home, tag, what)` — rings the bell.  101 rings it for its
  own writes; other modules ring the kinds they own (table below).
- A listener that raises an error stops the ring, and the error reaches
  whoever made the change (no derived file is left silently stale).  The
  change itself is already on disk when the bell rings (open question 1).
- Listeners are told in the order they registered.  Loading 102 keeps
  `where` current; loading 104 keeps `people/` current.

| `what` | `tag` | rung by | means |
|---|---|---|---|
| `created` | the new room | 101 `make_room` | a room folder now exists with `entry`, empty `withheld`, empty `log` |
| `label` | the room | 101 `write_label` | the entry's label changed |
| `token` | the room | 101 `change_token` | the entry's token (so its fingerprint) changed; held children were re-pointed first, each ringing `parent` |
| `members` | the room | 101 `write_members` (called by 103) | the address pairs changed (added, removed, reordered) |
| `heard` | the room | 101 `write_heard` (called by 103) | one pair's last-heard time changed; membership did **not** change |
| `parent` | the room | 101 `write_parent`, `change_token` | the entry's parent fingerprint changed |
| `filed` | the room | 101 `write_filed_under` | the entry's filed-under changed |
| `withheld` | the room | 103 | the room's `withheld` file changed |
| `log` | the room | 105 | a record was filed in the room's log |
| `ignore` | `""` (the whole home) or a local tag (a room-scoped ignore) | 103a | the home's `ignore` file changed |
| `removed-room` | the room | whoever retires a room folder (none in phase 1; leaving is phase 2) | the room folder is gone |

Any other `what` is an error.  `ignore` is rung with `""` (a whole-home change) or
the tag of the room an ignore is scoped to; every other kind with a local tag.

## The functions each module offers

Types: `string`, `integer` (whole number), `list` (Lua array), `bool`.

### 101 room-folders — `require("002-room-folders")`

| function | takes | gives |
|---|---|---|
| `open_home(dir)` | string, absolute | home; makes `config`, `ignore` (empty), `rooms/`, `people/` if absent; the folder above must exist |
| `read_config(home)` | home | table string→string |
| `set_config(home, key, value)` | home, string, string | — |
| `config_value(home, key)` | home, string | string; **error** if the key is absent |
| `new_local_tag()` | — | local tag |
| `is_local_tag(value)` | any | bool |
| `token_fingerprint(token)` | string | fingerprint (64 hex) |
| `is_fingerprint(value)` | any | bool |
| `suggest_token(home)` | home | string such as `"maple-orbit-velvet-tin"`: random words from the word list joined by `-`, how many read from config `rooms.suggested-token-words` |
| `suggest_token_of(word_count)` | integer ≥ 1 | the same, with the count given (no config) |
| `make_room(home, spec)` | spec `{label, token, kind, parent, filed_under, members}` — every field required (`parent`/`filed_under` `""` for none, `members` a list, may be empty) | local tag; rings `created` once |
| `read_entry(home, tag)` | home, local tag | entry `{tag, label, token, kind, parent, filed_under, members}` (shapes above); read fresh from disk every call |
| `write_label(home, tag, label)` | | — (rings `label`) |
| `change_token(home, tag, token)` | | — ; keeps folder, label, members, log; re-points every held room whose `parent` was the old fingerprint (each rings `parent`), then rings `token` |
| `write_members(home, tag, members)` | list of `{address, port, heard}` | — (rings `members`); the list is written as given, in order |
| `write_heard(home, tag, address, port, when)` | string, integer, integer | — (rings `heard`); error if the pair is not a member |
| `write_parent(home, tag, fingerprint)` | fingerprint or `""` | — (rings `parent`) |
| `write_filed_under(home, tag, other_tag)` | local tag or `""` | — (rings `filed`) |
| `list_rooms(home)` | home | sorted list of local tags |
| `list_rooms_by_kind(home, kind)` | `"group"` or `"direct"` | sorted list of local tags |
| `find_by_fingerprint(home, fingerprint)` | | the local tag of the held room with that token fingerprint, or `""` |
| `room_exists(home, tag)` | | bool |
| `room_dir / entry_path / withheld_path / where_path / log_path(home, tag)` | | string (absolute path) |
| `ignore_path(home)` | | string |
| `on_change(listener)` / `notify(home, tag, what)` | | — |
| `listener_count()` | — | integer (for tests and the demo) |
| `BELL_KINDS` | — | table what → `{scope = "room" or "home-or-room", meaning = string}` (read-only; for the demo and tests) |
| `KINDS` | — | table `"group"`/`"direct"` → meaning (read-only) |
| `SUGGESTED_WORDS_KEY` | — | `"rooms.suggested-token-words"` |

101's rules the others can rely on:

- `make_room` builds the room in a hidden `rooms/.new-<tag>/` — `entry`,
  an **empty `withheld`** and an **empty `log`** — and renames it into
  place, then rings only `created`; no room is ever visible without them.
  `where` is written by 102's listener on `created`.
- Every file write is write-to-temporary-then-rename.
- A token already held by another room is refused (by `make_room` and
  `change_token`): one room per token per home, so `find_by_fingerprint`
  has one answer.
- A parent that would put a room inside itself is refused by `make_room`,
  `write_parent` and `change_token`: the walk upward through held rooms'
  `parent` fingerprints may not reach the room's own fingerprint.  A
  parent not held here is allowed and ends the walk.
- `filed_under` must be `""` or the tag of another room held here, and a
  chain of filings may not loop.  Whether filing and parents mix is 102's
  (its open question).
- `read_entry` and every `write_*` error on a room that does not exist.
  `list_rooms` skips hidden entries and errors on any other entry in
  `rooms/` that is not a local tag.
- Config is strict: `config_value` errors on an absent key; there are no
  silent defaults anywhere.
- Errors never print a token (they end up in logs); they name the room by
  its local tag.
- For phase 2: `require("007-tokens").sha256(text)` gives raw SHA-256
  bytes (32), so the sealing key is `sha256(token)`, the same bytes the
  fingerprint is taken over.  Suggested tokens come from
  `assets/eff-large-wordlist.txt` (EFF large word list, 7,772 words, CC BY
  3.0 US; see `assets/eff-large-wordlist.about.md`).

### 102 room-tree — `require("021-room-tree")`

A room sits under another either **declared** (its entry's `parent` is
the fingerprint of a held room's token; the parent-membership rule
applies) or **filed** (its `filed_under` is a held room's tag; your own
screen, no rule).  A held declared parent wins over a filing; a declared
parent not held here leaves the room a top with `parent_unheld = true`.
Every answer is worked out afresh from the entries (no index is kept);
`snapshot` gives all of it from one read.

| function | gives |
|---|---|
| `may_join(home, tag, address, port)` | bool, reason (string, `""` when allowed).  `port` must be an integer (text is an error).  Top or only filed: true.  Held declared parent: true only if that exact (address, port) pair is among its members.  Declared parent not held: `tree.unheld-parent-join`, read only then |
| `child_rooms_holding(home, tag, address, port)` | list of tags: declared child rooms below `tag` (all levels, top-down, siblings by label then tag) holding the pair; filed rooms excluded |
| `tree_parent_of(home, tag)` | tag or `""`: the room it shows under (declared if held, else filed) |
| `declared_parent_of(home, tag)` | tag or `""`: the held room its `parent` names |
| `placement(home, tag)` | `{how = "declared" \| "filed" \| "top", parent_unheld = bool}` |
| `children_of(home, tag)` / `tops(home)` | list of tags, by label then tag |
| `ancestors(home, tag)` | list of tags, top first, ending with `tag` |
| `path_of_labels(home, tag)` | string, `"home/ritz/programming"` in this home's labels; `/` in a label written `\/`, `\` as `\\` |
| `forest(home)` | list of top nodes `{tag, label, kind, placed, parent_unheld, children}`, sorted by label then tag; direct messages included (filter on `kind`) |
| `file_under(home, tag, under)` | — ; `under` a tag or `""` (unfile).  Refuses unheld, itself, or a ring.  Writes through `write_filed_under` |
| `snapshot(home)` | `{tags, entries (tag→entry), by_print (fingerprint→tag), declared, parent (tag→tag or ""), unheld, placed, children, tops}` — one read of every entry; **a caller looping over rooms should take one snapshot rather than call the functions above per room** (each builds its own) |
| `write_all_where(home)` / `read_where(home, tag)` | — / `{folder, labels}` |

`where` is two lines, `folder = <room folder>` and `labels = <path of
labels>` (022's `split_path` reverses the escaping).  Drawing:
`024-forest-text` `lines(forest)` / `text(forest)`, marks `(filed)` and
`(parent not held here)`.

The bell listener: `created`, `label`, `parent`, `filed`, `token` → mend
a ring if one closed, rewrite every `where`; `removed-room` → unfile rooms
filed under it, then the same; `members`, `heard`, `withheld`, `log`,
`ignore` → nothing; any other kind → error.  A ring can close without
anyone filing into it (a declared parent arrives above a room you filed);
`tree.filing-loop` decides, read only then.  A ring of declared parents
alone is always an error.  Every question errors on a tag not held here.

### 103 recipients — `require("041-recipients")`

A **pair** is `{address = string, port = integer}` (040-address-pairs: an
address with no spaces, a port 1–65535, no default).  A **member** is 101's
`{address, port, heard}`.  Members are read fresh from the entry every call;
103 changes them only through 101's `write_members` / `write_heard`.

| function | gives |
|---|---|
| `members(home, tag)` | list of member, entry order |
| `is_member(home, tag, address, port)` | bool |
| `add_member(home, tag, address, port)` | `"added"` (rings `members`; `heard = 0`), `"already"`, `"ignored"` (103a), or `"not-in-parent"` plus a reason (102's `may_join`) — refusals are answers, not errors; checked in that order |
| `withheld(home, tag)` | list of pair (may hold former members) |
| `withhold / unwithhold(home, tag, address, port)` | `"withheld"`/`"already"` / `"unwithheld"`; rings `withheld`; error on a non-member / a pair not withheld |
| `send_list(home, tag)` | list of pair: members minus withheld, entry order — what phase 2 delivers to |
| `heard_from(home, tag, address, port, when)` | `add_member`'s word; then `write_heard` (rings `heard`) only if `when` is later than the recorded time |
| `confirm_leave(home, tag, address, port)` | `"removed"` (rings `members`); the **only** removal — phase 2 calls it after the call-back check (204/208); error on a non-member; any withheld line is kept |
| `silent_since(home, tag, since)` | list of member last heard before `since` (never-heard included), for a client's pruning offer; removes nothing |
| `shown_as(home, address, port)` | `{text, how}`: the label of the one direct-message room holding the pair (`how = "label"`), the text `"<address> <port>"` when none (`"address"`), and when several, config `recipients.shared-address-label` (read only then): `all-labels` → sorted labels joined `", "` (`"labels"`), `address` → the address |

`withheld` holds one `<address> <port>` per line (101 makes it empty).  To
turn a pair into 105's `from`: `address .. " " .. port`.  103 registers no
bell listener.

### 103a ignore list — `require("042-ignore-list")`

`rao-home/ignore` (101 makes it empty): one line per entry,
`<address> <port> <level> <added> <scope>` — level `hide` or `mark`, added in
whole seconds since 1970, scope `*` (the whole home) or a room's local tag.
Every change rings `ignore` on tag `""` for a whole-home entry, or on the room's
tag for a one-room entry.

| function | gives |
|---|---|
| `entries(home)` | list of `{address, port, level, added, scope}` |
| `ignore(home, address, port, level, scope, added)` | `"ignored"`, `"level-changed"`, `"already"` (no ring) |
| `unignore(home, address, port, scope)` | `"unignored"`; error if no such entry |
| `how_ignored(home, tag, address, port)` | `"none"`, `"hide"`, `"mark"` — for 105's view; when several lines match, `hide` wins |
| `files_message(home, tag, address, port)` | bool — should an arriving message be filed?  false only for `hide` under `ignore.hide-files = not-filed` |
| `refused_as_member(home, tag, address, port)` | bool (either level) — 103's member filter |

Reads `ignore.scope`, `ignore.match` and `ignore.hide-files` on use; an
absent or unknown value is an error.

### 104 people-links — `require("061-people-links")`

A **person** is a direct-message room: its label names the folder
`people/<label>/`, its member pairs are the person's machines.  A group
room is **theirs** when one of its members is one of those pairs (compared
as the text `"<address> <port>"`, exactly as written).  A **top** for them is
a room of theirs whose parent in 102's tree (declared if held, else
filed-under, else none) is not theirs.  Links are relative:
`people/<p>/<name> -> ../../rooms/<tag>`, or under `id-folder`
`people/<p>/<tag>/<name> -> ../../../rooms/<tag>`; only links of exactly
these shapes are ever removed.

| function | takes | gives |
|---|---|---|
| `top_rooms_for(home, dm_tag)` | home, tag of a direct-message room | sorted list of tags (error if not a direct room) |
| `top_rooms_for_addresses(home, pairs)` | list of `{address, port}` | sorted list of tags of top group rooms holding any of them |
| `people(home)` | home | list of `{folder, id, dm_tags = list, addresses = list of "<address> <port>"}`, sorted by folder |
| `planned_links(home, folder)` | home, string | list of `{path, target, room_id (tag), folder ("" or tag), name}` — no disk touched |
| `rebuild_person(home, folder)` / `rebuild_all(home)` | | — |
| `read_snapshot(home)` | home | the whole-home read one rebuild uses (for tests and the demo) |

Uses from 101 `config_value` and `on_change`; from 102 **`snapshot(home)`**
(its `entries` and `parent` fields), read once per rebuild — asking
`tree_parent_of` room by room re-reads the home per room (1.2 s per rebuild
at 100 rooms, against 12 ms).  Bell: `created`, `label`, `token`,
`members`, `parent`, `filed`, `removed-room` rebuild all of `people/`;
`heard`, `withheld`, `ignore`, `log` change nothing; any other kind is an
error.  Keys read on every rebuild (must be in config before the first room
is made once 061 is loaded): `people.link-collision`,
`people.direct-message-link`, `people.members-without-dm`.  Read only on
their edge case: `people.slash-in-link-name` (a label with `/`, or exactly
`.` or `..`), `people.person-folder-collision` (two people's folders would
share a name).

### 105 message-log — `require("081-message-log")`

Uses from 101 only `config_value`, `log_path(home, tag)`,
`notify(home, tag, "log")`, and the empty `log` that `make_room` makes.

A **message** is `{id=string, from=string, written=integer,
arrived=integer, text=string}`.  `from` is `"me"` or the address the copy
arrived from, written `"<address> <port>"` — one space, the port a whole
number 1–65535 with no leading zero, the address any run of
non-whitespace (so an entry member `{address, port}` becomes
`address .. " " .. port`).  It proves nothing about who wrote the message;
the signature, if any, is the last line of `text`, stored as written.
Times are whole seconds since 1970.  Message ids may hold only letters,
digits, `-` and `_`.

| function | gives |
|---|---|
| `new_message_id()` | string, 32 hex |
| `append(home, tag, message)` | `"filed"` (rings `log`) or `"duplicate"` (same id, same contents); **error** when the id is already filed with different `written`/`kind`/`target`/`text`, naming both versions.  `arrived` never counts; a repeat differing only in `from` goes by `log.same-id-new-address` |
| `has_message(home, tag, message_id)` | bool |
| `read(home, tag)` | list of records in file order: each message as above plus `kind` (`"message"`, `"correction"`, `"deletion"`) and `target` (the id an edit changes; `""` for a message) — both always present.  No `author` field |
| `read_ordered(home, tag)` | messages only, edits applied, sorted by written time then message id (nothing local takes part, so every home shows one order); each `{id, from, written, arrived, text, edited=bool, deleted=bool, changed_from=string}` — `changed_from` is the `from` of the edit applied, `""` if none; a deleted message stays, text `""` |
| `correct(home, tag, correction)` | `{id (new), from, written, arrived, target, text}` → `"filed"`/`"duplicate"`; always allowed, no time limit; error when the target is missing, is itself an edit, is already deleted, or `log.who-may-edit` refuses |
| `delete(home, tag, deletion)` | `{id (new), from, written, arrived, target}` → as `correct`; the original stays in the file |

Config keys (absent is an error when read): `log.record-shape`,
`log.shape-mixing`, `log.duplicate-check` on every call;
`log.who-may-edit` when filing an edit; `log.same-id-new-address` only
when a repeated id matches in everything but `from`.  Copying one log into
another (`copy_log`) is retired: rooms never split or merge.

## Choices the owner has not made yet

Where an open question in `notes/vision-planning.md` touches a module, the
module builds **every** variant, chosen by a key in `rao-home/config`.  A
module reads its key with `config_value`, which fails loudly when the key is
absent: there is no silent default.

| config key | question | variants | module |
|---|---|---|---|
| `rooms.suggested-token-words` | issue 101 open question 3 (how many words in a suggested token; list is the EFF large list, 7,772 words, about 12.9 bits each) | `6`, `5`, `4` | 101 |
| (not switchable) | issue 101 open question 1: a bell listener fails after a room was written | `keep-and-raise` (built), `undo-and-raise` (not built) | 101 |
| (not switchable) | issue 101 open question 2, waits on state (phase 6 measurement): room files surviving a power cut | `rename-only` (built), `fsync-then-rename` (not built) | 101 |
| (not switchable) | issue 101 open question 4 / planning questions 6–7: where rao-chat's entries meet rmail's contacts | `own-folders` (built), `read-rmail-contacts` (not built) | 101 |
| (not switchable) | new: a token changed by hand, and the child rooms naming the old fingerprint | `repoint-held` (built: this home's children follow), `leave-children` (not built) | 101 |
| (not switchable) | issue 101 open question 6 (new): where a member's last-heard time lives | `in-entry` (built: heard[N], bell kind `heard`), `separate-file` (not built) | 101 |
| (not switchable) | issue 101 open question 7 (new): may one home hold two folders with one token | `refuse-second` (built), `allow-several` (not built) | 101 |
| `tree.unheld-parent-join` | new (issue 102: a child whose declared parent is not held here — can anyone join it here? read only in that case) | `refuse`, `accept` | 102 |
| `tree.filing-loop` | new (issue 102 open question 1: a declared parent arrives that puts a room you filed above the room it is filed under; read only then) | `unfile`, `refuse` | 102 |
| (not switchable) | new (issue 102: is "a member of the parent" the exact (address, port) pair, or the same machine?) | `exact-pair` (built), `resolved` (not built) | 102 |
| (not switchable) | issue 102 open question 2: someone leaves a parent — who removes them from its child rooms? | `client-cleans-up` (built: `child_rooms_holding`), `server-withholds` (not built) | 102 |
| (not switchable) | new (issue 102: does the rule check only the direct parent, or every room above?) | `parent-only` (built), `every-ancestor` (not built) | 102 |
| (not switchable; waits on phase 2 leaving) | new (issue 102: rooms filed under a removed room) | `unfile` (built), `take-its-place` (not built) | 102 |
| `ignore.hide-files` | issue 103a open question 1 (is a hidden message filed?) | `filed`, `not-filed` | 103a |
| `ignore.scope` | issue 103a open question 2 (whole home only, or also one room?) | `home`, `home-and-room` | 103a |
| `ignore.match` | new (an entry covers its exact port, or every port at the address?) | `pair`, `host` | 103a |
| `recipients.shared-address-label` | new (an address held by two direct-message rooms; read only in that case) | `all-labels`, `address` | 103 |
| (not switchable) | issue 103 open question 2: a member who moves — old address kept or dropped | `keep` (built), `drop-old` (not built: nothing ties two addresses to one person) | 103 |
| (not switchable) | new: a withheld member leaves and returns | `still-withheld` (built), `forgotten` (not built) | 103 |
| (not switchable; waits on phase 2) | new: what records last-heard | `arrival-calls` (built: `heard_from`), `log-bell` (not built) | 103 |
| `people.link-collision` | issue 104 open question 1 (two top rooms, one label) | `suffix-id`, `numbered`, `id-folder` | 104 |
| `people.slash-in-link-name` | issue 104 open question 2 (a label with `/`, or exactly `.`/`..`, as a file name; read only in that case) | `percent`, `division-slash` | 104 |
| `people.direct-message-link` | new (is the person's own direct message linked in their folder too) | `leave-out`, `include` | 104 |
| `people.members-without-dm` | issue 104 open question 3 (a member no direct message holds: a folder named by address?) | `leave-out`, `address-folder` | 104 |
| `people.person-folder-collision` | new (two direct messages with one label; read only in that case) | `suffix-id`, `numbered`, `merge` | 104 |
| (not switchable; waits on pairing) | issue 104 open question 4 (own devices; the home keeps no device list now) | `none` (built), `all-tops` (not built) | 104 |
| (not switchable; waits on a measurement) | issue 104 open question 5 (rebuild all of `people/` per ring) | `rebuild-all` (built), `rebuild-affected` (not built) | 104 |
| `log.record-shape` | issue 105 q1 (planning q8) | `tsv`, `block`, `jsonl` | 105 |
| `log.who-may-edit` | issue 105 q2 (the writer is unknowable; read only when filing an edit) | `anyone`, `same-address` | 105 |
| `log.shape-mixing` | issue 105 q3 (a log holding records of more than one shape after `log.record-shape` changes) | `per-record`, `fixed` | 105 |
| `log.duplicate-check` | issue 105 q4 (waits on state: is the phase 2 server one long-running program) | `remembered`, `scan` | 105 |
| `log.same-id-new-address` | issue 105 q8, new (a repeat equal in contents but from another address; read only then) | `duplicate`, `error` | 105 |
| (not switchable) | issue 105 q5 (a deleted message: kept in the room view empty and marked, or vanishes) | `marked-empty` built, `vanish` not | 105 |
| (not switchable) | issue 105 q6 (an edit arriving before its message; waits on phase 2) | `refuse` built | 105 |
| (not switchable; `input/phase-1-demo.config` overrides per key) | new (what the demo sets the choices a scene is not about to) | `first-listed` built, `builder-leaning` not (needs a machine-readable leaning field) | 106 |

A builder who finds another undecided choice adds a row here.

## The options tally

Each module keeps `<index>-options.lua` (the last index of its range: 019,
039, 059, 079, 099) returning a list of choices, one table per choice:

    {
      id          = "log-record-shape",       -- string, unique across modules
      question    = "...",                     -- plain English
      waits_on    = "owner" | "state",         -- who or what must resolve it
      detail      = "open question 8" | "issue 105: ...",
      config_key  = "log.record-shape",        -- or "" when not switchable
      variants    = { { name, summary, built_in, tests, findings }, ... },
      leaning     = "...",                     -- the builder's suggestion and why
    }

`waits_on = "state"` marks a choice blocked on something other than the
owner — another module's behaviour, a later phase, a measurement.  The
`scripts/tally-options` tool (issue 106) reads all of these and walks through
them one at a time.  (106 keeps its own at `src/phase-1-demo/119-options.lua`.)

What the tally accepts, exactly: files named `src/<module>/<3 digits>-options.lua`,
one folder deep (never inside `tests/`); `built_in`, `tests` and `findings`
may each be one string or a list of strings; every text field but
`config_key` must be non-empty; `variants` must be a non-empty list; an `id`
used twice anywhere is an error.

The phase 1 demo reads these files too: for every choice with a
`config_key`, the **first variant listed** is the value its homes start with
(unless `input/phase-1-demo.config` names another built variant), and the
scenes run every listed variant of the key they are about.  So the order of
`variants` matters, and a key the modules read must appear in some options
file or the demo cannot set it.

A retired `<index>-options.lua-done` is never read (the name must end in
`-options.lua`).  Round 2's demo has nine scenes (issue 106) and runs
every listed variant of four keys: `rooms.suggested-token-words` (tokens),
`ignore.hide-files` (ignoring), `people.link-collision` (people) and
`log.record-shape` (log); every other key sits at its baseline.  The demo
calls, and so relies on: 101 `open_home`, `set_config`, `make_room`,
`read_entry`, `list_rooms`, `list_rooms_by_kind`, `suggest_token`,
`suggest_token_of`, `change_token`, `token_fingerprint`, the `*_path`
functions; 102 `forest`, `may_join`; 024 `lines`; 103 `add_member`,
`is_member`, `withhold`, `unwithhold`, `send_list`, `confirm_leave`,
`heard_from`; 103a `ignore`, `unignore`, `how_ignored`, `files_message`;
105 `new_message_id`, `append`, `correct`, `read`, `read_ordered`.

## The builders' board

`tmp/shared-memory/agent-network/` holds one append-only file per builder
(`101.log` … `106.log`).  A builder appends a dated line when an interface
becomes usable, when it changes something here, or when it has a question for
another builder; builders read each other's files while they work.
