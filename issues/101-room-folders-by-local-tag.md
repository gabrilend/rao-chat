# 101 — Room folders by a local tag, each holding a contact-style entry

**Phase:** 1 — Rooms on the home server
**Blocks:** 102, 103, 103a, 104, 105, 106, 201
**Blocked by:** none
**Module folder:** `src/room-folders/` (indexes 001–019)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Rebuilt for "a room is a contact" (round 2) and given mailboxes and the
flagged file (round 3, 2026-09-25).  125 checks in
`src/room-folders/tests/018-run-tests`: 124 pass, 1 fails — the failure
is the real people-links module (104, frozen this round) refusing the new
bell kind `mailbox` (one line in its listener table fixes it).  14 of the
checks run against the real room-tree, recipients, ignore list,
people-links and message-log modules.  The shared parts of
`docs/phase-1-module-contract.md` describe it.  Round 1 and 2's `-done`
files are deleted (git history holds them).

What exists in `src/room-folders/` (each source file with a `.info.md`):

- `001-load-path.lua` — adds `libs/` and every folder under `src/` to
  Lua's search path.
- `002-room-folders.lua` — the front door.  `open_home` makes `config`,
  an empty `mailboxes`, an empty `ignore`, `rooms/`, `people/`.  Rooms are
  made from `{label, token, kind, parent, filed_under, members,
  mailbox_port}` (every field required) in a hidden `rooms/.new-<tag>/`
  with `entry`, an empty `withheld`, an empty `flagged` (103's private
  review list) and an empty `log`, then renamed into place and announced
  with `created`.  Reading an entry; writing the label, members, one
  member's last-heard time, parent, filing, mailbox; changing a token by
  hand (folder, label, members, withheld and log kept; child rooms held
  here re-pointed); listing all rooms, by kind, by mailbox; finding a room
  by token fingerprint; paths of every room file.  Refuses a token already
  held by another room, a room placed inside itself, a filing that is
  unheld, itself or a loop.  Errors never print a token.
- **Mailboxes** (in `002`, format in `014`).  Where a new room goes is a
  dispatch on its kind and parent: a top-level group room starts a new
  `tree` mailbox labelled with its label, on the port the maker gives
  (`mailbox_port`, no default); a child whose declared parent is held
  joins the parent's mailbox; every direct message goes in the one
  `direct` mailbox (made once with `make_mailbox`; a direct room before it
  is refused, naming the call); a child whose declared parent is not held
  goes by config `mailboxes.unheld-parent` — `own-mailbox` (a new tree
  mailbox, stays there) or `waiting-mailbox` (the one `waiting` mailbox;
  after every room made, token changed or parent written, waiting rooms
  whose parent is now held — and not itself waiting — move into its
  mailbox, pass after pass, ringing `mailbox` per room).  A port given
  where the room joins a mailbox, or missing where it starts one, is an
  error.  Two mailboxes on one port are allowed and reported every time
  the file is read (to a warning sink: stderr, or a function a test or
  the demo sets).  `mailboxes_by_port` gives what a frame arriving on a
  port is tried against; `list_rooms_by_mailbox` the rooms in each;
  `shared_ports`; `write_mailbox_port`; `write_mailbox` moves a room by
  hand (a direct room only into the direct mailbox, a group room only into
  a tree or waiting one).  A room already in a mailbox keeps it when its
  parent changes (open question 9).
- `003-disk.lua` — write-to-temporary-then-rename, folder making.
- `004-rmail-formats.lua` — rmail's config and contacts formats; every
  address with its own port, no default port.
- `005-change-bell.lua` — kinds `created`, `label`, `token`, `members`,
  `heard`, `parent`, `filed`, `withheld` (now "withheld or flagged
  changed: who you send to", rung by 103 for both), `log`, `ignore`,
  `removed-room`, and `mailbox` (rung with `""` when `make_mailbox` makes
  one or a port changes; with a room's tag when that room moves).  A new
  tree mailbox made by `make_room` rings only `created`.
- `006-entry.lua` — the entry in rmail's contacts format, named by the
  local tag: quoted `label` and `token`, `kind`, `parent`, `mailbox` (a
  mailbox tag, never empty), `filed-under`, and `ip[N]`/`port[N]`/
  `heard[N]` always together, numbered from 1.  An entry without
  `mailbox` (from round 2) is an error on read; no conversion.
- `007-tokens.lua` — the fingerprint `SHA-256(SHA-256(token))` through
  libcrypto; raw `sha256` for phase 2's key; readable suggestions from
  `assets/eff-large-wordlist.txt`.  `suggest_token(home)` gives **six**
  words (answered; the `rooms.suggested-token-words` switch and its 5/4
  variants are gone); `suggest_token_of(n)` any count.
- `014-mailboxes.lua` — the `mailboxes` file (rmail's contacts format,
  one entry per mailbox named by its own local tag: quoted `label`,
  `kind` tree|direct|waiting, `port`), sorted by tag, every field
  checked; at most one direct and one waiting mailbox.
- `019-options.lua` — eight choices (below).

Tests (`tests/`): `009` formats and the entry (18), `010` tokens (17),
`011` home and rooms (30), `012` the bell (15), `013` with the real
neighbours (14: flagged-then-approved member, child rooms in their top's
mailbox, every neighbour accepting `mailbox` — fails on 104), `015`
mailboxes (31: a top room and its child in one mailbox, a direct message
in the direct mailbox, a shared port reported on every read, mailboxes by
port, both unheld-parent variants, a bottom-up chain settling top-down,
settling through a token change and a parent write).
`008-kit-for-tests.lua` is the shared kit (`test_home` makes a home with
its direct mailbox; `port_for` gives a top room a fresh port).

Choices in `019-options.lua`: `rooms-unheld-parent-mailbox` (key
`mailboxes.unheld-parent`: `own-mailbox`, `waiting-mailbox`; issue 102's
question, agreed on the board to live here), and seven not switchable:
mailbox after a parent change (`keep`, new), bell-failure
(`keep-and-raise`), write-durability (`rename-only`, waits on phase 6),
rmail contacts (`own-folders`), token change and children
(`repoint-held`), last-heard location (`in-entry`), one folder per token
(`refuse-second`).  Removed as answered: `rooms-suggested-token-words`.

Effect on the people-links module (104, not changed this round): its
tests make rooms without `mailbox_port` and its bell listener refuses
`mailbox`; stand-in 244/0, real-101 53/5, real 53/6, every failure one
of those two.  The fix on its side is one spec field in its test harness
and one line (`["mailbox"] = changes_no_links`) in its listener table.

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
  `port`, a whole number with no default).  A top-level group room is made
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
  default.
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

### Round 4 (2026-09-25)

1. **Unknown config lines are errors.**  Every module declares the setting
   names it reads (a small list each module hands to the config reader, or
   read from the options files — builder's call, recorded); opening a home
   whose `config` holds a name nobody declared is an error naming the line.
   Owner: "I think it should probably just give an error if it doesn't
   recognize a value."  Replaces the log's retired-keys choice.
2. **Own mailbox, fixed**: `mailboxes.unheld-parent` goes; a child whose
   parent is not held always gets its own mailbox and port.
3. **Merging into the parent's mailbox later.**  Once a room's declared
   parent arrives, the room can be moved into the parent's mailbox (reuse
   the waiting-mailbox move, which otherwise retires).  Built both ways,
   switched: `mailboxes.merge-when-parent-arrives` = `ask` (listed as
   waiting for the person's yes) or `automatic`.  The move rings `mailbox`;
   phase 2 (issue 205/202) announces the new port and keeps trying the old
   one for that room until members confirm.
4. Tests: an unknown config line refused; a known one accepted; a child
   made without its parent gets its own mailbox; after the parent arrives,
   `ask` lists it as mergeable and `automatic` moves it.

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

8. **A child room whose declared parent is not held here: which mailbox?**
   (issue 102's question, found in round 3; config
   `mailboxes.unheld-parent`, both built).  `own-mailbox`: its own port,
   never moves (one more router port; the tree then spans two mailboxes
   here).  `waiting-mailbox`: one shared waiting port, moves into the
   parent's mailbox when the parent arrives — but its listening port then
   changes, and members still sending to the waiting port are lost until
   phase 2 announces the move.  Leaning: own-mailbox.
9. **A room in a mailbox given another declared parent** (found in round
   3): keeps its mailbox (built), or moves with its subtree into the new
   parent's?  Moving changes the port members send to, as in 8.
10. **A retired config key left in a home's config** (raised by 105 in
    round 3, its options entry `log-retired-keys-in-config`): is silently
    ignored now.  Refusing it in 101's config reader would need a list of
    retired keys somewhere (the options files do not keep one).

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
