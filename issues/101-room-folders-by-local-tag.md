# 101 — Room folders by a local tag, each holding a contact-style entry

**Phase:** 1 — Rooms on the home server
**Blocks:** 102, 103, 103a, 104, 105, 106, 201
**Blocked by:** none
**Module folder:** `src/room-folders/` (indexes 001–019)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Rebuilt for "a room is a contact" (round 2, 2026-09-25) and tested: 89
checks pass (`src/room-folders/tests/018-run-tests`), 12 of them against
the real room-tree, recipients, ignore list, people-links and message-log
modules.  The shared parts of `docs/phase-1-module-contract.md` describe
it.  Round 1's files are kept beside the new ones as `<name>-done` until
one commit has carried them.

What exists in `src/room-folders/` (each source file with a `.info.md`):

- `001-load-path.lua` — adds `libs/` and every folder under `src/` to
  Lua's search path.  Unchanged.
- `002-room-folders.lua` — the front door.  `open_home` makes `config`,
  an empty `ignore`, `rooms/`, `people/` (no `contacts` file any more).
  Rooms are made from `{label, token, kind, parent, filed_under,
  members}` (every field required) in a hidden `rooms/.new-<tag>/` with
  `entry`, an empty `withheld` and an empty `log`, then renamed into
  place and announced with `created`.  Reading an entry; writing the
  label, members, one member's last-heard time, parent, filing; changing
  a token by hand (folder, label, members, withheld and log kept; child
  rooms held here re-pointed to the new fingerprint); listing all rooms or
  by kind; finding a room by token fingerprint; paths of every room file.
  Refuses a token already held by another room, a room placed inside
  itself (through parent fingerprints), a filing that is unheld, itself
  or a loop.  Errors never print a token.
- `003-disk.lua` — write-to-temporary-then-rename, folder making.
  Unchanged.
- `004-rmail-formats.lua` — rmail's config and contacts formats; gained
  `address_pairs`, which refuses an address without its own port, a port
  without an address, and malformed indexes (no default port).
- `005-change-bell.lua` — kinds `created`, `label`, `token`, `members`,
  `heard`, `parent`, `filed`, `withheld`, `log`, `ignore`,
  `removed-room`.  `heard` was added so a busy room's last-heard updates
  do not rebuild `people/`.  `ignore` is rung with `""` (whole home) or a
  room tag (a room-scoped ignore, 103a's choice); every other kind needs a
  tag.  Unknown kinds are errors; a listener's error reaches the writer.
- `006-entry.lua` — the entry in rmail's contacts format, named by the
  local tag (so `cat rooms/*/entry` is one valid contacts file): quoted
  `label` and `token`, `kind`, `parent`, `filed-under`, and
  `ip[N]`/`port[N]`/`heard[N]` always together, numbered from 1.  Every
  field checked on write and on read, the file named in every error.
- `007-tokens.lua` — the fingerprint `SHA-256(SHA-256(token))` through
  the system's libcrypto (checked against `sha256sum`); raw `sha256` for
  phase 2's key; readable suggestions drawn evenly from
  `assets/eff-large-wordlist.txt` (the EFF large word list, 7,772 words,
  CC BY 3.0 US; origin in `assets/eff-large-wordlist.about.md`).
- `019-options.lua` — seven choices (below).

Tests (`tests/`): `009` formats and the entry (18), `010` tokens and the
word-count variants (17), `011` home and rooms (30), `012` the bell (12),
`013` with the real neighbours (12; a module that fails to load is
skipped with a NOTE).  `008-kit-for-tests.lua` is the shared kit.

Choices in `019-options.lua`: `rooms.suggested-token-words` (`6`, `5`,
`4`; any whole number is accepted), and six not switchable:
bell-failure (`keep-and-raise`), write-durability (`rename-only`, waits on
phase 6), rmail contacts (`own-folders`), token change and children
(`repoint-held`), last-heard location (`in-entry`), one folder per token
(`refuse-second`).  Retired: `rooms.unknown-parent`, `rooms.slash-in-name`.

Not done here: nothing retires a room folder (`removed-room` has no
ringer in phase 1; leaving is phase 2).

## Intended Behavior

A home server keeps everything under one folder, `rao-home/`:

    rao-home/
      config          settings (rmail's config format)
      ignore          (written by 103a)
      rooms/
        <local tag>/
          entry       one entry in rmail's contacts format (below)
          withheld    (written by 103)
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
  - `filed-under` — see 102.
- **Folders are named by a local tag**, 32 lower-case hex characters from
  `/dev/urandom`, never sent to anyone.  The folder's own path is kept
  beside the label (102's `where`).  Owner: "we keep the actual file-path
  of the file on our disk right next to the file, easily accessible as
  easily as accessing the name."
- **Making a token.**  Any text is accepted; the maker may type their own.
  When asked, this module suggests a readable one — random words from a
  word list ("maple-orbit-velvet-tin").  Owner: "we don't restrict what
  users use for their token, but we suggest readable tokens like that."
- **Changing a token** is done by hand, for now (owner: "For now, let's say
  it's manually modified").  The room keeps its folder, label, members and
  log; only `token` changes.
- **Config** stays strict: an absent key is an error, never a silent
  default.
- **The change bell.**  Writes ring a bell other modules listen on, so the
  derived files (`where`, `people/`) stay true without this module knowing
  about them.  Kinds: `created`, `label`, `token`, `members`, `parent`,
  `filed`, `withheld`, `log`, `ignore`, `removed-room`.  An unknown kind is
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
3. **The word list for suggested tokens.**  How many words, and how many
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
