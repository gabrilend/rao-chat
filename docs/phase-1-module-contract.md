# Phase 1 module contract — how the room modules plug together

> **Round 2 (2026-09-25): rewritten for "a room is a contact".**  The
> shared parts — where each module lives, loading, the home folder, the
> entry, the change bell, and 101's functions — describe the design in
> `notes/vision-planning.md` sections 1–4 (decided in section 15).  Each
> other module's section is rewritten by its own builder while it rebuilds;
> a section still marked "being rewritten" is not yet a promise.  The
> round-1 contract (the first model, Appendix A) is in git history.
>
> **Round 3 (2026-09-25): mailboxes.**  A home keeps a `mailboxes` file:
> one mailbox per top-level group room (its child rooms join it), one for
> every direct message, each with its own listening port.  Every entry
> names its mailbox; `make_room` takes a `mailbox_port`; the bell has a
> new kind, `mailbox`.  Answered choices are built as answered (their
> switches are gone from the table below).
>
> **Round 4 (2026-09-26): declared settings.**  Every module lists the
> config names it reads in its own `src/<module>/<index>-settings.lua`;
> a `config` line naming something no module lists is an error naming the
> line (see "Settings").  `mailboxes.unheld-parent` is retired (a child
> of an unheld parent always starts its own mailbox);
> `mailboxes.merge-when-parent-arrives` is new.

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
| 101 | `src/room-folders/` | 001–019 | the home folder, config (and the check that every config line names a declared setting), local tags, the `mailboxes` file and which mailbox each room is in, the room `entry` (rmail's contacts format), making rooms, tokens (fingerprint, readable suggestions, changing by hand), the empty `ignore`, `withheld` and `log` files at birth, the change bell |
| 102 | `src/room-tree/` | 020–039 | the tree: parent by token fingerprint, children, ancestors, top rooms, `filed-under`, the parent-membership check, the `where` file, drawing the tree as text |
| 103 | `src/recipients/` | 040–059 | members (the entry's address pairs) and when each was last heard from, the `withheld` list, the send list, leaving |
| 103a | `src/recipients/` (shares 103's range) | 040–059 | the home's `ignore` list and its two levels |
| 104 | `src/people-links/` | 060–079 | the `people/` folder of links |
| 105 | `src/message-log/` | 080–099 | the message log, message ids, ordering, repeat-safety, edits |
| 106 | `src/phase-1-demo/`, `scripts/`, `issues/completed/demos/` | 100–119 | the options tally and the phase 1 demo |

Every source file's name starts with its reading-order index (for example
`src/room-folders/002-room-folders.lua`).  Tests live in each module's own
`tests/` folder.  Each source file has a `<file>.info.md` beside it listing
its outward-facing functions with their inputs and outputs.  From round 3
a retired file is simply deleted (git history holds it); no `-done` files
are made, and no test runner runs one.

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
      mailboxes               one entry per mailbox (rmail's contacts format, below); 101's; made EMPTY by open_home
      ignore                  the ignore list (103a's format); made EMPTY by open_home
      outside-ports           each mailbox's outside port, "<mailbox tag>.outside-port = N" (phase 2,
                              212's); written by the person or the viewer; absent = none yet
      rooms/
        <local tag>/
          entry               one entry in rmail's contacts format (below); 101's
          withheld            one address per line (103's format); made EMPTY by make_room
          flagged             members awaiting review, private, never sent (103's format); made EMPTY by make_room
          where               this folder's path and the path of labels (102's)
          log                 the messages (105's format); made EMPTY by make_room
          delivered           what each pair on the send list has acknowledged (phase 2, 202's
                              format); made by 202 at the first own write; absent = no lines
          claims              the hellos and leaves this home has claimed, one line each (phase 2,
                              204's format); appended by the claim's sender; absent = none
          left                pairs whose leave this home confirmed, one line each (phase 2,
                              208's format); absent = none
          left-by-me          the written time of this home's own leave (phase 2, 208); removed
                              when this home writes in the room again; absent = not left
          vouched             the claim each member answered yes to in a hello's call-back,
                              "address TAB port TAB claim id TAB confirmed" (phase 2, 207);
                              absent = none
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

## Settings: every name is declared (owned by 101)

`rao-home/config` holds `name = value` lines (rmail's config format).  Two
rules make it strict:

- **A setting a module asks for and does not find is an error**, never a
  silent default (`config_value`, since round 1).
- **A line naming a setting no module reads is an error** (round 4; the
  owner: "I think it should probably just give an error if it doesn't
  recognize a value").  A retired setting left behind, a typo, and a
  setting from a newer version are all caught this way.

**How a module declares its names.**  Each module folder holds exactly
one file named `<three digits>-settings.lua` (one folder deep, never in
`tests/`; the index is one of the module's own), returning a **plain
list of strings** — every config name the module reads, switched choice
or fixed setting alike:

    -- src/room-tree/0NN-settings.lua
    return {
        "tree.filing-loop",
    }

Rules, each an error naming the file when broken: the file returns a
list (keys 1..n, no gaps); every item is a setting name (letters, digits,
`_`, `-`, `.`); no name twice in one list; **no name declared by two
modules** (each setting has one owner, who says what its values mean —
any module may still *read* another's setting with `config_value`); at
most one such file per module folder.  A module that reads no settings
may leave the file out (or return `{}`).

**How the check finds them.**  101 (`017-declared-settings.lua`) lists
every folder under the `src/` it was loaded from and reads each
declaration file, once per running program.  It does **not** depend on
which modules a program loaded: a test that loads only 101 and opens a
home the demo filled with every module's settings sees the same
declarations.  (The alternative — each module handing over its list when
`require`d — was set aside because a name would be "unknown" whenever its
module happened not to be loaded.)

**Where the check runs** (all in 101's `002-room-folders`):

| call | what is checked |
|---|---|
| `open_home(dir)` | every line of `config`; an undeclared name is an error `<path>/config line N: '<name>' is not a setting any module reads ... — remove or correct the line: <name> = <value>` |
| `read_config(home)` | the same, every call (a line added by hand is caught on the next read) |
| `set_config(home, key, value)` | `key` must be declared (else error, nothing written); the existing file is checked first |
| `config_value(home, key)` | `key` must be declared (a module reading a name it forgot to list is an error), then present |

**For tests and the demo.**  Homes are built as before — `open_home`, then
`set_config` for each setting — as long as every name set is declared by
some module under `src/`.  A test cannot set a made-up name (`"a.b"`); it
uses a real one.  Stand-in room-folders modules inside a module's own
`tests/` are not affected (they are not 101).  `declared_settings()`
gives name → `{module, file}` for a demo or test that wants to show or
walk the list.  The options files (`<index>-options.lua`) are unchanged
and separate: they record *undecided choices*; the settings list records
*every name read*.  A switchable choice's `config_key` must also be in its
module's settings list, or its homes cannot be configured.

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
    3f9a0c1e5b7d42a8a6e1f0c2d4b6a8e0.mailbox     = 9c41d07a2be35f6e8810aa3c5d7e9f01
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
| `mailbox` | 32 hex | `mailbox` (string) | the local tag of the mailbox (in `rao-home/mailboxes`) this room is in; never empty.  Chosen by `make_room` (rules under "Mailboxes"); changed only by `write_mailbox` |
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

## Mailboxes (owned by 101)

A **mailbox** is a group of rooms with its own listening port.  Rooms stay
stored flat under `rooms/`; a mailbox is only named in each room's entry
and listed, with its port, in `rao-home/mailboxes`.  Phase 2 listens on
every mailbox's port, and a frame arriving on a port is tried only against
the keys of the rooms in the mailboxes on that port.

`rao-home/mailboxes` is rmail's contacts format, one entry per mailbox
named by the mailbox's own local tag (32 hex, same generator as a room's,
never sent), entries sorted by tag, fields in this order:

    // rao-chat mailboxes: rmail's contacts format, one entry per mailbox named by its local tag
    9c41d07a2be35f6e8810aa3c5d7e9f01.label = "programming"
    9c41d07a2be35f6e8810aa3c5d7e9f01.kind  = tree
    9c41d07a2be35f6e8810aa3c5d7e9f01.port  = 7777
    9c41d07a2be35f6e8810aa3c5d7e9f01.awaits-parent-of =
    e27f...(32 hex)...............08.label = "direct messages"
    e27f...(32 hex)...............08.kind  = direct
    e27f...(32 hex)...............08.port  = 7700
    e27f...(32 hex)...............08.awaits-parent-of =

| field | on disk | in Lua | rule |
|---|---|---|---|
| (name) | the mailbox's local tag | `tag` (string) | unique in the file |
| `label` | quoted text | `label` (string) | a name for people reading the file; non-empty, one line.  A tree mailbox takes its top room's label at making (not renamed with it) |
| `kind` | `tree` or `direct` | `kind` (string) | `tree`: a top-level group room and everything under it (or a child room whose parent is not held here, until it merges).  `direct`: every direct message (**at most one** per home).  Round 3's `waiting` kind is retired (round 4) and refused |
| `port` | whole number | `port` (integer) | 1–65535, **no default** |
| `awaits-parent-of` | a room's local tag, or empty | `awaits_parent_of` (string) | round 4: set only on a `tree` mailbox made for a child room whose declared parent was not held here — that room's tag — so the mailbox can merge into the parent's later; `""` otherwise and after the merge.  A round-3 file without this field is an error (no conversion) |

Which mailbox `make_room` puts a new room in (a dispatch on the room's
kind and parent; the spec's `mailbox_port` is an integer exactly when a
new mailbox is made, `""` otherwise — anything else is an error):

| the new room | mailbox | `mailbox_port` |
|---|---|---|
| `direct` | the one `direct` mailbox; **error** if none has been made (`make_mailbox`) | `""` |
| `group`, `parent = ""` (a top room) | a **new `tree` mailbox**, labelled with the room's label | the port (integer) |
| `group`, declared parent held here | the parent's mailbox | `""` |
| `group`, declared parent **not** held here | a **new `tree` mailbox** of its own (the owner's answer, round 4), labelled with the room's label, `awaits-parent-of` = the room's tag | the port (integer) |

- **Two mailboxes may name the same port**: allowed (the owner: "we can
  accept from the same port and route to the right location if necessary.
  It's not recommended though").  **Every read** of the mailboxes file
  that finds a shared port reports it through 101's warning sink (stderr
  unless a test or the demo sets another with `set_warning_sink`), naming
  the port and the mailboxes.  It is a warning, not an error.
- **Merging when the parent arrives** (round 4).  After `make_room`,
  `change_token`, `write_parent` and `merge_mailbox`, a mailbox **can
  merge** when the room in its `awaits-parent-of` has its declared parent
  held here, in another mailbox.  Only then is config
  `mailboxes.merge-when-parent-arrives` read (101's setting; no default):
  - `automatic` (listed first; the owner's preference): every room of that
    mailbox — the awaited room first, then the others by tag — moves into
    the parent's mailbox, each ringing `mailbox` with its tag; the mark is
    cleared.  Repeated until nothing can merge, so a chain arriving
    bottom-up merges step by step (a room can change port more than once).
  - `ask`: nothing moves.  `mergeable_mailboxes(home)` lists each possible
    merge until the person's yes, `merge_mailbox(home, mailbox_tag)`.
  - Any other value is an error.
  The emptied mailbox **stays**, with its port: phase 2 (issues 205/202)
  announces the new port to members and keeps trying the old one for the
  moved rooms until they confirm.
- A room's mailbox does **not** follow later changes of its declared
  parent (`write_parent`; open question 9), except a room whose own
  mailbox still awaits its parent (the merge above).  Moving a room by
  hand is `write_mailbox`; moving the awaited room out of its mailbox
  clears that mailbox's `awaits-parent-of` (the person placed it).
- A room's kind must fit its mailbox's: a `direct` room only in the
  `direct` mailbox, a `group` room only in a `tree` one.
- A mailbox is never removed in phase 1 (an empty one is allowed).

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
| `created` | the new room | 101 `make_room` | a room folder now exists with `entry`, empty `withheld`, empty `flagged`, empty `log`; if the room started a new mailbox, that mailbox is already in `mailboxes` (no separate `mailbox` ring) |
| `mailbox` | `""` (the mailboxes file) or a room's tag (that room moved) | 101 `make_mailbox`, `write_mailbox_port` (`""`); `write_mailbox` and every merge (the room's tag) | `""`: a mailbox was made by `make_mailbox` or its port changed.  A tag: that room's entry now names another mailbox.  Membership did **not** change |
| `label` | the room | 101 `write_label` | the entry's label changed |
| `token` | the room | 101 `change_token` | the entry's token (so its fingerprint) changed; held children were re-pointed first, each ringing `parent` |
| `members` | the room | 101 `write_members` (called by 103) | the address pairs changed (added, removed, reordered) |
| `heard` | the room | 101 `write_heard` (called by 103) | one pair's last-heard time changed; membership did **not** change |
| `parent` | the room | 101 `write_parent`, `change_token` | the entry's parent fingerprint changed |
| `filed` | the room | 101 `write_filed_under` | the entry's filed-under changed |
| `withheld` | the room | 103 | the room's `withheld` or `flagged` file changed: who you send to (round 3: 103 rings it for flag changes too, rather than a new kind) |
| `log` | the room | 105 | a record was filed in the room's log |
| `ignore` | `""` (the whole home) or a local tag (a room-scoped ignore) | 103a | the home's `ignore` file changed |
| `removed-room` | the room | whoever retires a room folder (none in phase 1; leaving is phase 2) | the room folder is gone |

Any other `what` is an error.  `ignore` and `mailbox` are rung with `""`
(a whole-home change) or a room's tag; every other kind with a local tag.
Round 3: a listener that errors on kinds it does not know must add
`mailbox` (for 102 and 104 it changes nothing drawn).

## The functions each module offers

Types: `string`, `integer` (whole number), `list` (Lua array), `bool`.

### 101 room-folders — `require("002-room-folders")`

| function | takes | gives |
|---|---|---|
| `open_home(dir)` | string, absolute | home; makes `config`, `mailboxes` (empty), `ignore` (empty), `rooms/`, `people/` if absent; the folder above must exist; **error** naming the line if `config` holds an undeclared name |
| `read_config(home)` | home | table string→string; **error** naming the line if `config` holds a name no module declares (see "Settings") |
| `set_config(home, key, value)` | home, string, string | — ; **error** if `key` is not declared by any module |
| `config_value(home, key)` | home, string | string; **error** if the key is not declared, or absent |
| `declared_settings()` | — | table name → `{module = folder name, file = path}`: every setting any module declares (a copy) |
| `new_local_tag()` | — | local tag |
| `is_local_tag(value)` | any | bool |
| `token_fingerprint(token)` | string | fingerprint (64 hex) |
| `is_fingerprint(value)` | any | bool |
| `suggest_token(home)` | home (checked, not read) | string such as `"maple-orbit-velvet-tin-..."`: **six** random words from the word list joined by `-` (answered; no config) |
| `suggest_token_of(word_count)` | integer ≥ 1 | the same, with another count |
| `make_room(home, spec)` | spec `{label, token, kind, parent, filed_under, members, mailbox_port}` — every field required (`parent`/`filed_under` `""` for none, `members` a list, may be empty; `mailbox_port` an integer 1–65535 exactly when the room starts a new mailbox, else `""` — see "Mailboxes") | local tag; rings `created` once (then `mailbox` per room a merge moves, under `automatic`) |
| `read_entry(home, tag)` | home, local tag | entry `{tag, label, token, kind, parent, mailbox, filed_under, members}` (shapes above); read fresh from disk every call |
| `make_mailbox(home, spec)` | spec `{label, kind, port}`, kind `"direct"` (tree mailboxes are made only by `make_room`; `waiting` is retired) | mailbox tag; rings `mailbox` with `""`; error if it exists |
| `read_mailboxes(home)` | home | list of `{tag, label, kind, port, awaits_parent_of}` sorted by tag; reports shared ports to the warning sink |
| `read_mailbox(home, mailbox_tag)` | | one `{tag, label, kind, port, awaits_parent_of}`; error if absent |
| `direct_mailbox(home)` | | the direct mailbox's tag, or `""` if not made (`waiting_mailbox` is gone) |
| `mergeable_mailboxes(home)` | home | list of `{mailbox, room, into, rooms}` (tags; `rooms` the sorted room tags that would move), sorted by mailbox — the merges now possible; reads no config |
| `merge_mailbox(home, mailbox_tag)` | mailbox tag | — ; the person's yes: one merge (rings `mailbox` per room moved), then settles; error if the mailbox awaits nothing or its room's parent is not held yet |
| `list_rooms_by_mailbox(home, mailbox_tag)` | | sorted list of room tags; error if the mailbox is absent |
| `mailboxes_by_port(home, port)` | integer | sorted list of mailbox tags listening on that port (for phase 2's trial opening: try the keys of `list_rooms_by_mailbox` of each) |
| `shared_ports(home)` | | list of `{port = integer, mailboxes = sorted list of tags}`, one per port named by two or more mailboxes, sorted by port (reports as `read_mailboxes` does) |
| `write_mailbox_port(home, mailbox_tag, port)` | integer | — (rings `mailbox` with `""`) |
| `write_mailbox(home, tag, mailbox_tag)` | room tag, mailbox tag | — (rings `mailbox` with the room's tag); the room's kind must fit the mailbox's; moving an awaited room out of its mailbox clears the mark |
| `set_warning_sink(fn)` | function(text) | — ; where shared-port reports go (default: a line on stderr) |
| `mailboxes_path(home)` | | string |
| `write_label(home, tag, label)` | | — (rings `label`) |
| `change_token(home, tag, token)` | | — ; keeps folder, label, members, log; re-points every held room whose `parent` was the old fingerprint (each rings `parent`), then rings `token` |
| `write_members(home, tag, members)` | list of `{address, port, heard}` | — (rings `members`); the list is written as given, in order |
| `write_heard(home, tag, address, port, when)` | string, integer, integer | — (rings `heard`); error if the pair is not a member |
| `write_parent(home, tag, fingerprint)` | fingerprint or `""` | — (rings `parent`, then settles merges) |
| `write_filed_under(home, tag, other_tag)` | local tag or `""` | — (rings `filed`) |
| `list_rooms(home)` | home | sorted list of local tags |
| `list_rooms_by_kind(home, kind)` | `"group"` or `"direct"` | sorted list of local tags |
| `find_by_fingerprint(home, fingerprint)` | | the local tag of the held room with that token fingerprint, or `""` |
| `room_exists(home, tag)` | | bool |
| `room_dir / entry_path / withheld_path / flagged_path / where_path / log_path(home, tag)` | | string (absolute path) |
| `ignore_path(home)` | | string |
| `on_change(listener)` / `notify(home, tag, what)` | | — |
| `listener_count()` | — | integer (for tests and the demo) |
| `BELL_KINDS` | — | table what → `{scope = "room" or "home-or-room", meaning = string}` (read-only; for the demo and tests) |
| `KINDS` | — | table `"group"`/`"direct"` → meaning (read-only) |
| `MAILBOX_KINDS` | — | table `"tree"`/`"direct"` → meaning (read-only) |
| `SUGGESTED_WORD_COUNT` | — | `6` (`SUGGESTED_WORDS_KEY` is gone with its switch) |
| `MERGE_KEY` | — | `"mailboxes.merge-when-parent-arrives"` (`UNHELD_PARENT_KEY` is gone with its setting) |

101's rules the others can rely on:

- `make_room` builds the room in a hidden `rooms/.new-<tag>/` — `entry`,
  an **empty `withheld`**, an **empty `flagged`** and an **empty `log`** —
  and renames it into
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
- A room's `mailbox` always names a mailbox in `mailboxes` when `make_room`
  or `write_mailbox` writes it; `read_entry` checks only its shape (a
  hand-edited mailbox tag is caught by `list_rooms_by_mailbox` callers
  finding the room nowhere, not on every read).
- An entry written before round 3 has no `mailbox` field and is an error
  on read; there is no conversion (no home from round 2 is kept).
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
the fingerprint of a held room's token; the parent-membership check
applies) or **filed** (its `filed_under` is a held room's tag; your own
screen, no rule).  A held declared parent wins over a filing; a declared
parent not held here leaves the room a top with `parent_unheld = true`.
Every answer is worked out afresh from the entries (no index is kept);
`snapshot` gives all of it from one read.

| function | gives |
|---|---|
| `check_member(home, tag, address, port)` | answer, reason.  Answer `"yes"` \| `"no"` \| `"cannot-check"`; reason `""` for yes.  Detects, never refuses (round 3).  Walks **every declared room above** `tag` (never filing), stopping at the first not held here.  yes: no declared parent, or every held room above holds that exact (address, port) pair.  no: a held room above lacks it (reason names each) — wins over cannot-check.  cannot-check: all held rooms above hold it, but the chain runs into a parent not held.  `port` must be an integer (text is an error) |
| `check_member_in(snap, tag, address, port)` | the same, from a `snapshot` already taken |
| `failing_members(home, tag)` | list of rows `{room = tag, address, port (integer), answer = "no" \| "cannot-check", reason}`: members of `tag` itself not answered yes, in member order |
| `failing_below(home, tag)` | rows as above for every member of every declared descendant of `tag` (all levels, top-down, siblings by label then tag), for 103's re-check when `tag`'s members change; lists all failing, not only newly failing; filed rooms excluded |
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
`ignore`, `mailbox` → nothing (re-checking after `members` is 103's
listener, through `failing_below`); any other kind → error.  Mailboxes
place nothing in the tree: 101 chooses and moves them (a child follows its
declared parent's mailbox; a child of a parent not held gets its own,
merged into the parent's when it arrives as `mailboxes.merge-when-parent-arrives`
says), and 102's `tests/028-test-mailboxes.lua` checks the two agree under
both values.  102 declares `tree.filing-loop` in `023-settings.lua`.  A ring can close without
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
| `add_member(home, tag, address, port)` | `"added"` (rings `members`; `heard = 0`); `"added-flagged"` plus 102's answer (`"no"` / `"cannot-check"`) and reason — added AND flagged (the flag is written first, ringing `withheld`, then the member, ringing `members`); `"already"`; `"ignored"` (103a, the one refusal — an answer, not an error).  Order: already, ignored, then 102's `check_member` |
| `flags(home, tag)` | every line of the room's `flagged` file: list of `{address, port, state}`, state `"no"` / `"cannot-check"` (awaiting review) or `"approved"` |
| `flagged(home, tag)` | the flags awaiting review (`no` / `cannot-check`) — what a client highlights |
| `approve(home, tag, address, port)` | `"approved"`: the line becomes `approved` (kept, so re-checks do not flag them again); rings `withheld`; error if not awaiting review |
| `decline(home, tag, address, port)` | `"declined"`: withheld (if not already) and the line deleted; rings `withheld`; error if not awaiting review |
| `recheck(home, tag, itself)` | number newly flagged, list of rooms the tree reported: flags the failing members of `tag`'s declared descendants (and of `tag` itself when `itself` is true) that have no line and are not withheld; then re-asks every awaiting flag in the home (a changed answer is rewritten; a pass deletes the flag line: the flag clears by itself; approved lines are never re-flagged — an approval lasts until the leave).  Run from the bell; callable by hand |
| `withheld(home, tag)` | list of pair (may hold former members) |
| `withhold / unwithhold(home, tag, address, port)` | `"withheld"`/`"already"` / `"unwithheld"`; rings `withheld`; error on a non-member / a pair not withheld |
| `send_list(home, tag)` | list of pair: members minus withheld minus those awaiting review, entry order — what phase 2 delivers to |
| `heard_from(home, tag, address, port, when)` | `add_member`'s word (and, for `added-flagged`, its answer and reason); then `write_heard` (rings `heard`) only if `when` is later than the recorded time — a flagged member's time is recorded too |
| `confirm_leave(home, tag, address, port)` | `"removed"` (rings `members`); the **only** removal — phase 2 calls it after the call-back check (204/208); error on a non-member; any withheld line is kept, any flag line is deleted (a return is checked afresh) |
| `silent_since(home, tag, since)` | list of member last heard before `since` (never-heard included), for a client's pruning offer; removes nothing |
| `shown_as(home, address, port)` | `{text, how}`: the label of the one direct-message room holding the pair (`how = "label"`), the text `"<address> <port>"` when none (`"address"`), and when several, config `recipients.shared-address-label` (read only then): `all-labels` → sorted labels joined `", "` (`"labels"`), `address` → the address |

`withheld` holds one `<address> <port>` per line (101 makes it empty).
`flagged` (beside it; 101 makes it empty, path from `flagged_path`) holds one
`<address> <port> <state>` per line, state `no` | `cannot-check` |
`approved`; private to this home, never sent, written only by 103.  Flag
changes ring `withheld` (both files only change who you send to; no new
bell kind).  To turn a pair into 105's `from`: `address .. " " .. port`.

103 registers a bell listener (re-checking flags): `members` and `token` on
X → X's declared descendants; `created` and `parent` on X → X's own members
and its descendants (a room is made with its members already in it; a
parent arriving turns cannot-check into yes or no); `label`, `heard`,
`filed`, `withheld`, `log`, `ignore`, `mailbox`, `removed-room` → nothing.
Any other kind is an error.

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
| `how_ignored(home, tag, address, port)` | `"none"`, `"hide"`, `"mark"` — for 105's view; an entry covers every port at its address (answered); when several lines match, `hide` wins |
| `files_message(home, tag, address, port)` | bool — should an arriving message be filed?  false only for `hide` (answered: hidden messages are dropped on arrival) |
| `refused_as_member(home, tag, address, port)` | bool (either level) — 103's member filter |

Reads only `ignore.scope` on use; an absent or unknown value is an error.
`ignore.match` and `ignore.hide-files` were answered (round 3) and are no
longer read.
Both 103 and 103a declare their names in the recipients folder's one list,
`043-settings.lua`: `ignore.scope` and `recipients.shared-address-label`.
`recipients.flag-after-passing` was answered (round 4: cleared) and is no
longer read, so a config line naming it is refused.

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
`heard`, `withheld`, `ignore`, `log`, `mailbox` change nothing; any other
kind is an error.  Round 3: `mailbox` (a mailbox made, its port changed,
or a room moved into another) moves no label, member or tree parent, so no
link.  A **flagged** member (103's `added-flagged`: in the entry, held off
the send list until approved or declined) is a member, so it counts toward
that person's rooms like any other; flag changes ring `withheld`, which
moves nothing (the owner's answer, round 4: a flagged member counts).
104 reads nothing of the `mailboxes` or `flagged` files.  Keys read on every rebuild (must be in config before the first room
is made once 061 is loaded): `people.link-collision`,
`people.direct-message-link`, `people.members-without-dm`.  Read only on
their edge case: `people.slash-in-link-name` (a label with `/`, or exactly
`.` or `..`), `people.person-folder-collision` (two people's folders would
share a name).  All five are declared in `078-settings.lua`.

### 105 message-log — `require("081-message-log")`

Uses from 101 only `config_value`, `log_path(home, tag)`,
`notify(home, tag, "log")`, and the empty `log` that `make_room` makes.
Nothing about mailboxes: a room's log is the same whichever mailbox the
room is in.

A log is plain text, one line per record (tsv, the owner's answer):
`id TAB from TAB written TAB arrived TAB kind TAB target TAB text`, with
`\`, tab, line feed and carriage return in the text written `\\`, `\t`,
`\n`, `\r`.

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
| `append(home, tag, message)` | `"filed"` (rings `log`) or `"duplicate"` (same id, same contents); **error** when the id is already filed with different `written`/`kind`/`target`/`text`, naming both versions.  Neither `arrived` nor `from` counts: the same contents from another address are `"duplicate"`, and the first copy's `from` stays |
| `has_message(home, tag, message_id)` | bool |
| `read(home, tag)` | list of records in file order: each message as above plus `kind` (`"message"`, `"correction"`, `"deletion"`) and `target` (the id an edit changes; `""` for a message) — both always present.  No `author` field |
| `read_ordered(home, tag)` | messages only, edits applied, sorted by written time then message id (nothing local takes part, so every home shows one order); each `{id, from, written, arrived, text, edited=bool, deleted=bool, changed_from=string}` — `changed_from` is the `from` of the edit applied, `""` if none; a deleted message stays, text `""`, `deleted = true` (a marked gap or hidden is the client's setting) |
| `correct(home, tag, correction)` | `{id (new), from, written, arrived, target, text}` → `"filed"`/`"duplicate"`; always allowed, from any address, no time limit; error when the target is missing, is itself an edit, or is already deleted |
| `delete(home, tag, deletion)` | `{id (new), from, written, arrived, target}` → as `correct`; the original stays in the file |

Config key (absent is an error when read): `log.duplicate-check`, read by
`append`, `correct`, `delete` and `has_message`; `read` and
`read_ordered` read no config.  Retired in round 3 and no longer read:
`log.record-shape` (tsv), `log.shape-mixing`, `log.who-may-edit`
(anyone), `log.same-id-new-address` (duplicate).  The log declares only
`log.duplicate-check` (`087-settings.lua`), so since round 4 a home whose
config still names a retired one is refused by 101.  Copying one log into
another (`copy_log`) is retired: rooms never split or merge.

## Choices the owner has not made yet

Where an open question in `notes/vision-planning.md` touches a module, the
module builds **every** variant, chosen by a key in `rao-home/config`.  A
module reads its key with `config_value`, which fails loudly when the key is
absent: there is no silent default.

| config key | question | variants | module |
|---|---|---|---|
| `mailboxes.merge-when-parent-arrives` | answered as a setting kept both ways (round 4; the owner prefers automatic): a child room's own mailbox, once its parent arrives — read only when a merge is possible | `automatic`, `ask` | 101 |
| (not switchable) | new (issue 101 round 4, open question 11): under `ask`, a merge the person declines | `stays-listed` (built), `remember-no` (not built) | 101 |
| (not switchable) | new (issue 101 round 3: a room in a mailbox is given another declared parent — does it move?) | `keep` (built; only a room whose own mailbox awaits its parent merges), `follow` (not built) | 101 |
| (not switchable) | issue 101 open question 1: a bell listener fails after a room was written | `keep-and-raise` (built), `undo-and-raise` (not built) | 101 |
| (not switchable) | issue 101 open question 2, waits on state (phase 6 measurement): room files surviving a power cut | `rename-only` (built), `fsync-then-rename` (not built) | 101 |
| (not switchable) | issue 101 open question 4 / planning questions 6–7: where rao-chat's entries meet rmail's contacts | `own-folders` (built), `read-rmail-contacts` (not built) | 101 |
| (not switchable) | new: a token changed by hand, and the child rooms naming the old fingerprint | `repoint-held` (built: this home's children follow), `leave-children` (not built) | 101 |
| (not switchable) | issue 101 open question 6 (new): where a member's last-heard time lives | `in-entry` (built: heard[N], bell kind `heard`), `separate-file` (not built) | 101 |
| (not switchable) | issue 101 open question 7 (new): may one home hold two folders with one token | `refuse-second` (built), `allow-several` (not built) | 101 |
| `tree.filing-loop` | new (issue 102 open question 1: a declared parent arrives that puts a room you filed above the room it is filed under; read only then) | `unfile`, `refuse` | 102 |
| (not switchable) | new (issue 102: is "a member of the parent" the exact (address, port) pair, or the same machine?) | `exact-pair` (built), `resolved` (not built) | 102 |
| (not switchable; waits on phase 2 leaving) | new (issue 102: rooms filed under a removed room) | `unfile` (built), `take-its-place` (not built) | 102 |
| `ignore.scope` | issue 103a open question 2 (whole home only, or also one room?) | `home`, `home-and-room` | 103a |
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
| `log.duplicate-check` | issue 105 q4 (waits on state: is the phase 2 server one long-running program) | `remembered`, `scan` | 105 |
| (not switchable) | issue 105 q7 / planning q9 (pictures in chat) | `text-only` built | 105 |
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

The phase 1 demo reads these files too.  Since round 4 its homes set
**exactly the declared setting names** (`declared_settings()`, see
"Settings: every name is declared") — no other name can be set.  Each
declared name starts at the **first variant listed** for it in an options
file (unless `input/phase-1-demo.config` names another built variant), and
the scenes run every listed variant of the key they are about.  So the
order of `variants` matters; an options file's `config_key` that no module
declares, or a declared name with no options entry and no value in
`input/phase-1-demo.config`, stops the demo's baseline (every scene that
makes a home is then reported could-not with that reason).

A retired `<index>-options.lua-done` is never read (the name must end in
`-options.lua`).  Round 4's demo has ten scenes (issue 106) and runs
every listed variant of two keys: `mailboxes.merge-when-parent-arrives`
(mailboxes: a child made before its parent, in its own mailbox, then
merged — `automatic` at once, `ask` after `merge_mailbox`) and
`people.link-collision` (people); answered choices are built fixed and
not varied, and every other key sits at its baseline.  The mailboxes scene
also shows an undeclared name refused by `set_config`, and by `open_home`
and `read_config` after a line is written into `config` by hand.  Every home the demo
makes gets its direct mailbox at birth (port 7700); top rooms take ports
from 7701 up.  The demo calls, and so relies on: 101 `open_home`,
`read_config`, `set_config`, `declared_settings`, `make_room`, `make_mailbox`, `read_entry`,
`list_rooms`, `list_rooms_by_kind`, `suggest_token`, `change_token`,
`token_fingerprint`, `find_by_fingerprint`, `read_mailboxes`,
`read_mailbox`, `mergeable_mailboxes`, `merge_mailbox`, `list_rooms_by_mailbox`,
`mailboxes_by_port`, `shared_ports`, `set_warning_sink`, the `*_path`
functions (with `flagged_path`, `mailboxes_path`); 102 `forest`,
`check_member`; 024 `lines`; 103 `add_member`, `is_member`, `withhold`,
`unwithhold`, `approve`, `decline`, `send_list`, `confirm_leave`,
`heard_from`; 103a `ignore`, `unignore`, `how_ignored`, `files_message`;
105 `new_message_id`, `append`, `correct`, `read`, `read_ordered`.

## The builders' board

`tmp/shared-memory/agent-network/` holds one append-only file per builder
(`101.log` … `106.log`).  A builder appends a dated line when an interface
becomes usable, when it changes something here, or when it has a question for
another builder; builders read each other's files while they work.
