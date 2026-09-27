# 101 — Room folders by a local tag, each holding a contact-style entry

**Phase:** 1 — Rooms on the home server
**Blocks:** 102, 103, 103a, 104, 105, 106, 201, 211, 212
**Blocked by:** none
**Module folder:** `src/room-folders/` (indexes 001–019)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Rebuilt for "a room is a contact" (round 2), given mailboxes and the
flagged file (round 3), and, in round 4 (2026-09-26), declared settings,
the own mailbox fixed and merging into the parent's mailbox.  141 checks
in `src/room-folders/tests/018-run-tests`, all passing; 16 of them run
against the real room-tree, recipients, ignore list, people-links and
message-log modules.  The shared parts of `docs/phase-1-module-contract.md`
describe it (new section "Settings: every name is declared").

What exists in `src/room-folders/` (each source file with a `.info.md`):

- `001-load-path.lua` — adds `libs/` and every folder under `src/` to
  Lua's search path.
- `002-room-folders.lua` — the front door.  `open_home` makes `config`,
  an empty `mailboxes`, an empty `ignore`, `rooms/`, `people/`, then reads
  `config` through the declared-settings check.  Rooms are made from
  `{label, token, kind, parent, filed_under, members, mailbox_port}`
  (every field required) in a hidden `rooms/.new-<tag>/` with `entry`, an
  empty `withheld`, an empty `flagged` (103's private review list) and an
  empty `log`, then renamed into place and announced with `created`.
  Reading an entry; writing the label, members, one member's last-heard
  time, parent, filing, mailbox; changing a token by hand (folder, label,
  members, withheld and log kept; child rooms held here re-pointed);
  listing all rooms, by kind, by mailbox; finding a room by token
  fingerprint; paths of every room file.  Refuses a token already held by
  another room, a room placed inside itself, a filing that is unheld,
  itself or a loop.  Errors never print a token.
- **Declared settings** (`016-settings.lua`, `017-declared-settings.lua`,
  wired into `002`).  Every module keeps one file
  `src/<module>/<3 digits>-settings.lua` returning a plain list of the
  config names it reads (101's: `mailboxes.merge-when-parent-arrives`).
  `017` finds them by listing every folder under the `src/` it was loaded
  from, once per program — so the answer does not depend on which modules
  a program loaded (the other design, each module registering its list
  when `require`d, was set aside for that reason: a name would be
  "unknown" whenever its module was not loaded).  A list that is not a
  plain list of setting names, a name twice, a name declared by two
  modules, or two lists in one folder is an error naming the file(s).
  `open_home` and every `read_config` refuse a config line whose name no
  module declares, naming the file, line number and line ("a retired
  setting, a typo, or a setting from a newer version — remove or correct
  the line"); `set_config` refuses an undeclared name before writing;
  `config_value` refuses an undeclared name (a module reading a name it
  forgot to list).  `declared_settings()` gives name → `{module, file}`.
  `004-rmail-formats.parse_config_lines` keeps each line's number for the
  message.  Tests and the demo build homes as before, setting only
  declared names; by the end of the round every module that reads a
  setting had its list (room-folders, room-tree, recipients with the
  ignore list, people-links, message-log; the demo reads none).  This replaces 105's retired-keys choice (open question 10).
- **Mailboxes** (in `002`, format in `014`).  Where a new room goes is a
  dispatch on its kind and parent: a top-level group room starts a new
  `tree` mailbox labelled with its label, on the port the maker gives
  (`mailbox_port`, no default); a child whose declared parent is held
  joins the parent's mailbox; every direct message goes in the one
  `direct` mailbox (made once with `make_mailbox`; a direct room before it
  is refused, naming the call); **a child whose declared parent is not
  held always starts a `tree` mailbox of its own** on the port given
  (answered; `mailboxes.unheld-parent`, the `waiting` mailbox kind,
  `waiting_mailbox` and `UNHELD_PARENT_KEY` are gone), and that mailbox
  records the room in its `awaits-parent-of` field.  A port given where
  the room joins a mailbox, or missing where it starts one, is an error.
  Two mailboxes on one port are allowed and reported every time the file
  is read (to a warning sink: stderr, or a function a test or the demo
  sets).  `mailboxes_by_port`, `list_rooms_by_mailbox`, `shared_ports`,
  `write_mailbox_port`, `write_mailbox` (a direct room only into the
  direct mailbox, a group room only into a tree one; moving an awaited
  room out of its mailbox ends that mailbox's wait).
- **Merging into the parent's mailbox.**  After `make_room`,
  `change_token`, `write_parent` and `merge_mailbox`, a mailbox can merge
  when the room it awaits the parent of has its declared parent held here,
  in another mailbox.  Only then is `mailboxes.merge-when-parent-arrives`
  read (no default): `automatic` (listed first; the owner's preference)
  moves every room of that mailbox — the awaited room first, then by tag
  — into the parent's mailbox with the move code the waiting mailbox used,
  each ringing `mailbox` with its tag, clears the mark, and repeats until
  nothing can merge (a chain arriving bottom-up merges step by step);
  `ask` moves nothing, and `mergeable_mailboxes(home)` lists
  `{mailbox, room, into, rooms}` until the person's yes,
  `merge_mailbox(home, mailbox_tag)` (an error when the mailbox awaits
  nothing or the parent is not held yet).  The emptied mailbox stays, with
  its port, for phase 2 (issue 205/202) to keep trying until members
  confirm the new port.  A room in a settled mailbox keeps it when its
  parent changes (open question 9).
- `003-disk.lua` — write-to-temporary-then-rename, folder making.
- `004-rmail-formats.lua` — rmail's config and contacts formats (config
  lines with their line numbers); every address with its own port, no
  default port.
- `005-change-bell.lua` — kinds `created`, `label`, `token`, `members`,
  `heard`, `parent`, `filed`, `withheld` (103's, for withheld or flagged
  changes), `log`, `ignore`, `removed-room`, and `mailbox` (rung with `""`
  when `make_mailbox` makes one or a port changes; with a room's tag when
  that room moves, by hand or by a merge).  A new tree mailbox made by
  `make_room` rings only `created`.
- `006-entry.lua` — the entry in rmail's contacts format, named by the
  local tag: quoted `label` and `token`, `kind`, `parent`, `mailbox` (a
  mailbox tag, never empty), `filed-under`, and `ip[N]`/`port[N]`/
  `heard[N]` always together, numbered from 1.
- `007-tokens.lua` — the fingerprint `SHA-256(SHA-256(token))` through
  libcrypto; raw `sha256` for phase 2's key; readable suggestions from
  `assets/eff-large-wordlist.txt`; `suggest_token(home)` gives six words
  (answered), `suggest_token_of(n)` any count.
- `014-mailboxes.lua` — the `mailboxes` file (rmail's contacts format,
  one entry per mailbox named by its own local tag: quoted `label`,
  `kind` tree|direct, `port`, `awaits-parent-of` a room tag or empty),
  sorted by tag, every field checked; at most one direct mailbox; a
  round-3 file (no `awaits-parent-of`, or a `waiting` mailbox) is refused.
- `016-settings.lua` — 101's declared setting names.
- `017-declared-settings.lua` — finding and checking every module's list.
- `019-options.lua` — nine choices (below).

Tests (`tests/`): `009` formats and the entry (18), `010` tokens (17:
the round-2 token-words setting is now refused as undeclared), `011` home
and rooms (42: a known config line accepted, an unknown one refused by
`open_home` and every later read naming its line, a typo refused,
`set_config` and `config_value` refusing undeclared names, and the
gathering rules on scratch `src/` folders — one folder deep only, every
broken list shape, two owners, two files), `012` the bell (15), `013`
with the real neighbours (16: every options key declared, flagged-then-
approved member, a stray child merging into its arriving parent's mailbox
with every neighbour listening), `015` mailboxes (33: the file with
`awaits-parent-of`, placement, shared ports, a child of an unheld parent
in its own mailbox, the merge setting read only when needed and refused
when unknown, `automatic` moving a child and grandchild / a bottom-up
chain / through a token change / through `write_parent`, `ask` listing
then merging on the yes, a yes refused before the parent arrives, a yes
lower in a chain landing in the parent's current mailbox, a hand move
ending the wait).  `008-kit-for-tests.lua` is the shared kit
(`test_home(rooms, name, merge)` makes a home with its direct mailbox and
optionally the merge setting; `port_for_home` gives a fresh port to a top
room or a child of an unheld parent).

Choices in `019-options.lua`: `rooms-merge-when-parent-arrives` (key
`mailboxes.merge-when-parent-arrives`: `automatic`, `ask` — answered as a
setting kept both ways; listed so the demo and tally know its values),
and eight not switchable: a declined merge under `ask` (`stays-listed`,
new), mailbox after a parent change (`keep`), bell-failure
(`keep-and-raise`), write-durability (`rename-only`, waits on phase 6),
rmail contacts (`own-folders`), token change and children
(`repoint-held`), last-heard location (`in-entry`), one folder per token
(`refuse-second`).  Removed as answered: `rooms-unheld-parent-mailbox`
(round 4), `rooms-suggested-token-words` (round 3).

Neighbours after this round's changes: people-links (104) 798/0
(stand-in, real-101, real); phase-1 demo tests (106) 300/0, including the
demo end to end through `run-phase-demo 1`; room-tree (102) 0 files
failed; recipients (103/103a) 72/0 stand-in, 73/0 real-101 and real;
message-log (105) all passing, stand-in and real.

Not done here: nothing retires a room folder or a mailbox (`removed-room`
has no ringer in phase 1; leaving is phase 2).

## Intended Behavior

A home server keeps everything under one folder, `rao-home/`:

    rao-home/
      config          settings (rmail's config format)
      mailboxes       one entry per mailbox: label, kind, port
      ignore          (written by 103a)
      rooms/
        <local tag>/
          entry       one entry in rmail's contacts format (below)
          withheld    (written by 103)
          flagged     (written by 103; made empty here)
          where       (written by 102)
          log         (written by 105; made empty here)
      people/         (written by 104)

- **Every conversation is a room**, group or direct message alike, in the
  same folder shape, read and written by the same code.  Owner: "We can
  keep them separate, so that we can communicate with people with
  direct-messaging style conversations and group chats. Though, I'd like if
  all of them used the same general architecture, with as much code-reuse
  as possible."  Listing can be by kind.
- **The entry** is one entry in rmail's contacts format:
  - `label` — your own name for the room (text, one line); rename freely.
  - `token` — the room's shared secret (text, any characters but a line
    break).  Holding it is being invited; phase 2 makes the sealing key
    from it.
  - `kind` — `group` or `direct`.
  - `ip[N]` / `port[N]` — the members' addresses, **always in pairs**: an
    address without its port, or a port without its address, is an error.
    There is no default port.  (rmail lets a missing `port[N]` fall back to
    a default; rao-chat does not.)
  - `parent` — for a child room, the fingerprint of its parent's token (a
    one-way scramble, so naming the parent reveals nothing); empty
    otherwise.
  - `mailbox` — the local tag of the mailbox the room is in.
  - `filed-under` — see 102.
- **Mailboxes.**  A mailbox is a group of rooms with its own listening
  port, listed in `rao-home/mailboxes` (rmail's format, one entry per
  mailbox named by its own local tag: `label`, `kind` tree | direct,
  `port`, a whole number with no default; `awaits-parent-of` on a mailbox
  made for a child whose parent is not held yet).  A top-level group room is made
  with a new tree mailbox, its port given by the maker; a child room joins
  its declared parent's mailbox; every direct message goes in the one
  direct mailbox.  Rooms stay stored flat; the mailbox is only named in
  each entry.  Two mailboxes may name the same port: allowed, reported
  every time it is read (owner: "listening port, but we can accept from
  the same port and route to the right location if necessary. It's not
  recommended though."; direct messages: "this one is just a more simple
  rmail inbox. Just one.").  Rooms can be listed by mailbox and mailboxes
  by port, for phase 2's trial opening.
- **Folders are named by a local tag**, 32 lower-case hex characters from
  `/dev/urandom`, never sent to anyone.  The folder's own path is kept
  beside the label (102's `where`).  Owner: "we keep the actual file-path
  of the file on our disk right next to the file, easily accessible as
  easily as accessing the name."
- **Making a token.**  Any text is accepted; the maker may type their own.
  When asked, this module suggests a readable one — six random words from
  the EFF large word list ("maple-orbit-velvet-tin-...").  Owner: "we don't restrict what
  users use for their token, but we suggest readable tokens like that."
- **Changing a token** is done by hand, for now (owner: "For now, let's say
  it's manually modified").  The room keeps its folder, label, members and
  log; only `token` changes.
- **Config** stays strict: an absent key is an error, never a silent
  default, and a line naming a setting no module reads is an error naming
  the line (owner: "I think it should probably just give an error if it
  doesn't recognize a value").  Every module declares the names it reads
  in a plain list of its own.
- **A child room whose parent is not held here** gets its own mailbox and
  port; once the parent arrives its mailbox's rooms can merge into the
  parent's (owner: "we should make it so that they can merge into the
  parent rooms later on if possible"), by the setting
  `mailboxes.merge-when-parent-arrives` = `automatic` (owner: "I prefer
  automatic") or `ask`.
- **The change bell.**  Writes ring a bell other modules listen on, so the
  derived files (`where`, `people/`) stay true without this module knowing
  about them.  Kinds: `created`, `label`, `token`, `members`, `heard`,
  `parent`, `filed`, `withheld`, `log`, `ignore`, `removed-room`,
  `mailbox`.  An unknown kind is
  an error; a listener's error reaches whoever made the change.

## Suggested Implementation Steps

1. Keep `001`, `003`; in `004`, refuse unpaired `ip[N]`/`port[N]` and drop
   the default-port fallback.
2. In `002`: the local tag (same generator as the old ids); making a room
   from `{label, token, kind, parent}`; reading and writing the entry;
   writing the empty `log` in the hidden folder before the rename; listing
   rooms, by kind; finding a room by token fingerprint (phase 2 and 102
   need it).  Drop `name`, `parent`, `recipients` files and their writers.
3. The token fingerprint (a one-way scramble of the token, as hex text).
4. The readable-token suggester and its word list, kept in `libs/` or
   `assets/`.
5. Changing a token by hand.
6. `ignore` opened with the home (empty).
7. In `005`: the new bell kinds.
8. Retire `rooms-unknown-parent` and `rooms-slash-in-name` (labels are the
   reader's own and may hold any text but a line break).  Keep
   `rooms-bell-failure` and `rooms-write-durability`.
9. Tests: an unpaired address refused; a direct message and a group read
   by the same code; changing a token keeps the log; the fingerprint is
   the same on two homes for the same token; every bell kind.

## Blockers that are not the owner's

None; this is the foundation the others plug into.  The contract document
is rewritten in the same step.

## Open questions

Every choice this module holds open — those below, and those found while
building (named in Current Behavior) — is in its options file with what
building each variant showed; `scripts/tally-options --walk` goes through
them one at a time.  An issue with any of them unanswered is in progress.

1. **A listener fails after a room was written** (not switchable): keep the
   write and pass the error on (built), or undo it?
2. **Surviving a power cut** (waits on state: phase 6 measurement): write
   and rename only, or also force the data to disk before the rename?
3. **The word list for suggested tokens.**  *Answered (round 3): six
   words, fixed; the switch is gone.*  How many words, and how many
   words per token?  (Four words from a list of 2,048 is 44 bits: hard to
   guess by hand, easy to read aloud.)  Found while rewriting.  *Round 2:*
   the list is settled as the EFF large word list (7,772 words, about 12.9
   bits each); the count is config `rooms.suggested-token-words`, built
   for any whole number, offered as 6 / 5 / 4.  Finding: a token is
   guessed by machine, offline — against recorded sealed traffic, or
   against the parent fingerprint a child room's invitation carries (two
   SHA-256 per guess; about 775,000 a second on one CPU core here).  At an
   assumed 5 billion guesses a second on one GPU, four words (51.7 bits)
   falls in about 4 days, five (64.6) in about 90 years, six (77.5) in
   about 700,000 years.  Leaning: 6.
4. **Where rao-chat's entries meet rmail's contacts.**  A direct message is
   exactly an rmail contact.  Keep rao-chat's entries in its own folders,
   or read direct messages straight from rmail's contacts file?  (Planning
   questions 6 and 7.)  Built: own folders; each entry is named by its
   local tag so `cat rooms/*/entry` is already one valid contacts file.
5. **A token changed by hand, and the child rooms below it** (found in
   round 2).  Children name their parent by the parent token's
   fingerprint, which changes with the token.  Built: children held on
   this home are re-pointed at once.  Open: on every other member's home
   the children keep the old fingerprint until the new token is entered
   there, and meanwhile show as top rooms (and 102's parent-membership
   check has no parent to consult).  Should phase 2 carry "this parent's
   fingerprint changed" to members, sealed with the new token?  And the
   person shut out still holds each child's own token: shutting someone
   out of a tree means changing every token in it.
6. **Where a member's last-heard time lives** (found in round 2).  103
   records it for pruning; it was put in the entry as `heard[N]` beside
   `ip[N]`/`port[N]`, with its own bell kind (`heard`) so it does not
   rebuild `people/`.  The cost: the entry is rewritten each time a member
   is heard from later than before, so an entry is no longer a file that
   changes only when a person edits the room.  The alternative (103's
   first proposal) was a separate `heard` file per room.  Kept in the
   entry for now; revisit with the power-cut measurement (question 2).
7. **One folder per token** (found in round 2).  Making a room, or
   changing to a token, that another room here already holds is refused,
   so a token (and its fingerprint) always leads to one folder.  Someone
   invited twice to the same room would be told "already held here"
   rather than get a second folder.  Is that what the owner wants?

8. *Answered (round 4): its own mailbox and port, fixed; it can merge
   into the parent's later (`mailboxes.merge-when-parent-arrives`,
   automatic or ask, a setting).  The waiting variant is gone.*
   **A child room whose declared parent is not held here: which mailbox?**
   (issue 102's question, found in round 3; config
   `mailboxes.unheld-parent`, both built).  `own-mailbox`: its own port,
   never moves (one more router port; the tree then spans two mailboxes
   here).  `waiting-mailbox`: one shared waiting port, moves into the
   parent's mailbox when the parent arrives — but its listening port then
   changes, and members still sending to the waiting port are lost until
   phase 2 announces the move.  Leaning: own-mailbox.
9. **A room in a mailbox given another declared parent** (found in round
   3): keeps its mailbox (built), or moves with its subtree into the new
   parent's?  Moving changes the port members send to, as in 8.  *Round
   4:* a room whose own mailbox still awaits its parent is not covered by
   this: given a held parent by `write_parent`, it merges by the merge
   setting (built so, since the mailbox exists only to wait for a parent).
10. *Answered (round 4): every config line nothing reads is an error
    naming the line; built as declared settings (above).*  **A retired
    config key left in a home's config** (raised by 105 in round 3, its
    options entry `log-retired-keys-in-config`).
11. **A merge the person declines under `ask`** (found in round 4, options
    entry `rooms-merge-declined`): there is no "no" — it stays listed in
    `mergeable_mailboxes` until a yes or a hand move (built), or should a
    no be remembered and never offered again?

## Earlier designs

- **First model (built 2026-09-25):** rooms were folders named by a random
  id that travelled between servers; `parent` held the parent's id and
  `recipients` the contact names written to.
- **Second model (written, not built):** a room's name was its key; folders
  held `name`, `island`, `members`, `withheld`.  Replaced because a guessed
  name opened a room, which needed islands, vouching and a waiting pile to
  work around.

## Related documents

- `notes/vision-planning.md` sections 1–5, 15
- `docs/phase-1-module-contract.md`
