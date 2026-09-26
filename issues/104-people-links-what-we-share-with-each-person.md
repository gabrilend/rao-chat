# 104 — The people/ links: what do I share with this person

**Phase:** 1 — Rooms on the home server
**Blocked by:** 101, 102, 103, 103a
**Blocks:** 106
**Module folder:** `src/people-links/` (indexes 060–079)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Rebuilt for the room-is-a-contact model (round 2, 2026-09-25), brought
up to round 3's mailboxes and flags, then round 4's declared settings and
answered flag choice, and tested against stand-ins, against the real 101
with a stand-in 102, and against the real 101, 102 and 103 together; every
check passes.  Run `luajit src/people-links/tests/073-run-tests.lua` for
the counts.

Round 4 (declared settings, one answer fixed in place):

- **The setting names are declared.**  101's config reader now refuses
  any config line whose name no module declares, and any read of an
  undeclared name.  `078-settings.lua` lists the five names this module
  reads (`people.link-collision`, `people.slash-in-link-name`,
  `people.direct-message-link`, `people.members-without-dm`,
  `people.person-folder-collision`) — all still open choices; declaring
  them decides nothing.  `071-test-choices.lua` checks the list equals the
  options file's switchable keys, that 061 reads each by name, and (real
  101) that 101 lists each as people-links' and refuses an undeclared
  `people.*` line.
- **A flagged member counts** toward the person's rooms — the owner's
  answer; the code already did this, so only the choice entry
  `people-flagged-members` went (options file, contract row, comments).
- **Tests set only declared names.**  The retired
  `mailboxes.unheld-parent` and `recipients.flag-after-passing` are no
  longer written by the harness, the neighbour test or the flag test; the
  harness sets 101's `mailboxes.merge-when-parent-arrives = automatic`
  instead (read by 101 when a room's parent arrives after it).  The
  stand-in 101 gives a room whose parent is not held its own mailbox
  always and never merges it (mailboxes move no link).

Round 3 (mailboxes and flags) as it touches people/:

- **Mailboxes change no link.**  A mailbox is a listening port grouping a
  top room's tree (or every direct message).  101's bell kind `mailbox`
  (a mailbox made, a port changed, a room moved) is heard and ignored;
  before this fix it was refused as an unknown kind, which stopped any home
  from making its direct mailbox while 104 was loaded.  An unlisted kind is
  still an error.
- **A flagged member counts.**  103's `add_member` can answer
  `added-flagged`: the member is written into the entry but held off the
  send list until approved or declined.  104 reads membership from the
  entry, so a flagged member makes the room theirs (and can make it a top
  for them) at once; the `withheld` ring, which now also covers 103's
  `flagged` file, still moves nothing (answered by the owner in round 4).
- **Tests make rooms the round-3 way.**  The test harness makes every home's
  direct mailbox first (so every test also hears a `mailbox` ring) and
  passes 101's `mailbox_port` (a fresh port for a room starting a mailbox,
  `""` for one joining its held parent's or the direct mailbox).  The
  stand-in 101 learned the same rule.  New test file
  `076-test-mailboxes-and-flags.lua` (a port change and a room move leave
  people/ unchanged; the owner's round-3 coder-in-shopping example, flagged
  by the real 103 in real mode and by hand otherwise; declining moves no
  link).  The neighbour test sets 102's and 103's current keys (the answered
  `ignore.hide-files`, `ignore.match`, `tree.unheld-parent-join` are no
  longer set).

What exists in `src/people-links/` (each file with a `.info.md`):

- `060-neighbour-reads.lua` — the only file that calls other modules.
  One rebuild reads the whole home once through 102's `snapshot` (each
  room's entry and its parent in the tree).  Asking 102 room by room
  re-read the home per room: 1.2 s per rebuild at 100 rooms, against
  12 ms now.
- `061-people-links.lua` — people are direct-message rooms (folder named by
  the label); a group room is theirs when one of its members is one of the
  direct message's address pairs; tops are their rooms whose tree parent
  (declared if held, else filed-under) is not theirs.  Rebuilds on
  `created`, `label`, `token`, `members`, `parent`, `filed`,
  `removed-room`; ignores `heard`, `withheld`, `ignore`, `log`, `mailbox`;
  errors on any other kind.  Offers `top_rooms_for` (by direct-message tag),
  `top_rooms_for_addresses`, `people`, `planned_links`, `rebuild_person`,
  `rebuild_all`, `read_snapshot`.
- `062-disk-links.lua` — unchanged from round 1.
- `063-link-names.lua` — the three collision modes; now also names
  people's folders (ids may be longer than a tag).
- `078-settings.lua` — the five setting names above, declared to 101.
- `079-options.lua` — seven choices: five switchable
  (`people.link-collision`, `people.slash-in-link-name`,
  `people.direct-message-link`, `people.members-without-dm`,
  `people.person-folder-collision`), two not (own devices, rebuild scope).
- Tests: the owner's example on the new model (programming filed under
  ritz, since the girlfriend is not in ritz and so cannot be in a declared
  child of it) in all three collision modes, bell-only; a person in three
  rooms, one a declared child (two links); two rooms labelled
  `programming`; labels with `/`, `.`, `..`; a person with two addresses
  counted once; a new address added to the direct message; the same host
  on another port not counted; relabelling, unfiling, a hand-changed token;
  safety of anything not ours; the real 102's ancestors agreeing with our
  tops; the real 103's `add_member` moving links and `withhold` not.

Retired (the `-done` copies carried by one commit, then deleted in round
3): the round-1 versions of 061, 063, 079, their `.info.md`s, and tests
064–073;
`people.split-records` (no splits any more); the `people.own-devices`
switch (the home keeps no list of your own devices now — no contacts file
— so `all-tops` has nothing to act on until pairing exists).

Found while building, not yet in the questions below:

- **`token` changes can move tops**, so it rebuilds (the issue listed
  `created`, `label`, `members`, `parent`, `filed`, `removed-room`).
- **Is the person's own direct message linked in their folder?**
  (`people.direct-message-link`: `leave-out`, `include`).
- **Two direct messages with the same label** need two folders, or one
  (`people.person-folder-collision`: `suffix-id`, `numbered`, `merge`).
- **Labels `.` and `..`** are legal labels now; they are rewritten under
  `people.slash-in-link-name` like `/` (`%2E`, or U+2024/U+2025).
- **Addresses are compared as written** (`GF.example` and `gf.example` are
  two members), as 101's entry keeps them.

Measured (open question 5), on the real 101 and 102: one rebuild 12 ms at
100 rooms, 39 ms at 400; making 400 rooms one by one took 32.7 s in all,
about 8 s of it 104's rebuilds.

## Intended Behavior

    people/
      <direct-message label>/
        <link name> -> ../../rooms/<local tag>

- `people/` answers "what do I share with this person?" with an `ls`.
  Owner: "we have symlinks in each person's contacts directory which point
  to each of the top-level directories they're a part of (from our
  perspective)."
- **A person is a direct-message room** (101): its label names them, and
  its address pairs are their machines.  A group room is theirs when one of
  those addresses is among its members (103).  A room is a **top room** for
  them when it is theirs and its parent (102) is not, or it has no parent.
- **The entries are the truth, the links are the view.**  Rebuilt on
  `created`, `label`, `members`, `parent`, `filed`, `removed-room`;
  deleting all of `people/` and rebuilding gives the same result.
  Withholding and ignoring do not change membership, so they do not
  change the links.
- **Links are relative**, so a copied `rao-home/` keeps working.  Only
  links of the shapes this module makes are ever removed.
- **Link names are the rooms' labels.**  Labels are your own and may repeat
  or hold `/`, so the collision modes and the `/` rule still apply.

## Suggested Implementation Steps

1. People from direct-message rooms; membership by address.
2. Tops from 102's tree.
3. Listen on the new bell kinds.
4. Keep the three collision modes and the `/` rule.
5. Retire `people.split-records`.
6. Tests: a person in three rooms, one a child of another (two links); two
   rooms both labelled `programming`; a label holding `/`; a person with two
   addresses counted once.

## Blockers that are not the owner's

- Needs 101 (entries, bell kinds), 102 (the tree), 103 (members).

## Open questions

Every choice this module holds open — those below, and those found while
building (named in Current Behavior) — is in its options file with what
building each variant showed; `scripts/tally-options --walk` goes through
them one at a time.  An issue with any of them unanswered is in progress.

1. **Two top rooms with the same label** (`people.link-collision`):
   `suffix-id` (`programming~3fa9`), `numbered` (`programming`,
   `programming-2`, which renumbers when a new one appears), or
   `id-folder` (one folder per room).  Builder's leaning: `suffix-id`.
2. **`/` in a label** (`people.slash-in-link-name`): `percent`
   (`home%2Fritz`) or `division-slash` (a look-alike character, U+2215).
3. **Members with no direct message.**  They have no `people/` folder.
   Should they get one, named by address?
4. **Your own devices** (`people.own-devices`: `none`, `all-tops`).  Never
   members, so `all-tops` would mean "the top of every tree you hold".
   Builder's leaning: `none`.
5. **Rebuilding everything on each bell ring** (waits on a measurement of a
   real home): 400 rooms take 19 ms per rebuild; making 400 rooms one by
   one, 5 s in total, growing with the square of the room count.
6. *(answered 2026-09-25, fixed in round 4)* **A flagged member** (added,
   but held off the send list until you approve or decline) counts toward
   the person's rooms, as built.

## Earlier designs

- **First model (built 2026-09-25):** people were contact names on
  `recipients` lists; tops were found one step up the `parent` file.  A
  split's read-only record could be shown or hidden.
- **Second model (written, not built):** people were found by address in
  rooms' `members`, and same-named islands made collisions common.

## Related documents

- `notes/vision-planning.md` section 4
- `docs/phase-1-module-contract.md`
