# 102 — The room tree: child rooms, and the parent-membership rule

**Phase:** 1 — Rooms on the home server
**Blocked by:** 101
**Blocks:** 103, 104, 106
**Module folder:** `src/room-tree/` (indexes 020–039)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Round 3 (2026-09-25) is built on top of round 2's "a room is a contact"
tree.  The runner (`src/room-tree/tests/038-run-tests.sh`) gives 132
checks passing against the stand-in room-folders module and 181
against the real round-3 modules.  The contract's 102 section describes
it.  Round 1's and round 2's `-done` files are deleted (git history holds
them).

What exists in `src/room-tree/` (each source file with a `.info.md`):

- `021-room-tree.lua` — the tree, worked out afresh from every room's
  entry on each question (no index kept; one read of the home is a
  "snapshot").  A room sits under its **declared** parent (the held room
  whose token fingerprint its `parent` names) when that parent is held
  here; else under the room it is **filed** under (`filed-under`, a local
  tag); else it is a top.  A declared parent not held here leaves the room
  a top, marked "parent not held".  Offers: the parent in the tree, the
  declared parent, how a room is placed, children, tops, ancestors (top
  first), the path of your own labels, the whole forest as nested nodes,
  filing and unfiling (refusing itself, an unheld room, or a ring), and
  the snapshot itself (104 reads it once per rebuild).
- **The parent-membership check, detected, never enforced.**  "Does this
  (address, port) belong in this room, by the rooms declared above it?"
  answers one of three words: `yes` (a top or merely filed room, or every
  declared room above holds that exact pair); `no` (some declared room
  above, held here, lacks it — the reason names each such room, nearest
  first); `cannot-check` (every held room above holds it, but the chain of
  declared parents runs into one this home does not hold).  It walks
  **every** declared room above, not only the parent (the owner's answer
  to how far up to look), and stops at the first room not held: that
  room's own parent is written in an entry this home does not have.  `no`
  wins over `cannot-check`.  Filing is never followed.  Nothing is
  refused: 103 adds the member either way and flags it on `no` or
  `cannot-check`.  A second form takes a snapshot already made, for
  checking many members at once.
- **Re-checking** — "which members below this room now fail the check?":
  every member of every declared descendant (all levels, top-down) whose
  answer is not `yes`, each row naming the room, the address, the port,
  the answer and the reason; and the same for one room's own members
  (for when a declared parent arrives and a room's `cannot-check` members
  can now be answered).  It lists every failing member, not only newly
  failing ones: 103 keeps the flags and knows which it has already
  raised.  Dropping someone from `home` shows them failing in `home`'s
  children and grandchildren.
- **Keeping `where` true**: a bell listener rewrites every room's `where`
  on `created`, `label`, `parent`, `filed` and `token`; on `removed-room`
  it first unfiles rooms filed under the removed one; member, last-heard,
  withheld, log, ignore and **mailbox** changes are ignored (mailboxes
  group rooms by listening port and place nothing in the tree).  A ring
  closed by a declared parent arriving above a room you filed is settled
  by `tree.filing-loop` (`unfile` / `refuse`); a ring of declared parents
  alone is always an error.
- **Mailboxes** are 101's: a top group room starts a mailbox, a declared
  child joins its parent's, a child made while its parent is not held
  goes where `mailboxes.unheld-parent` says (`own-mailbox`: a mailbox and
  port of its own, kept when the parent arrives; `waiting-mailbox`: the
  one waiting mailbox, and moved into the parent's mailbox when the
  parent arrives, repeated until nothing moves).  Agreed with 101 on the
  board that the choice lives in 101's `make_room` and 101's options file,
  since the code that picks a mailbox is 101's.  The tree's
  `tests/028-test-mailboxes.lua` builds `home > ritz > programming`
  bottom-up under both answers and checks mailboxes, tree and check agree
  at each step: under `waiting-mailbox` the whole chain ends in home's
  mailbox (programming, two levels down, moves too); under `own-mailbox`
  one tree drawn is three mailboxes listening on three ports.
- `022-where-file.lua` — `where` as two lines, `folder = …` and
  `labels = …`; a `/` inside a label is written `\/`.
- `024-forest-text.lua` — draws the forest as text with box-drawing
  branches and the marks `(filed)` and `(parent not held here)`.
- `039-options.lua` — three choices left: `tree.filing-loop` (switchable),
  what counts as the same member (`exact-pair` built), and where rooms
  filed under a removed room go (`unfile` built; waits on phase 2's
  leaving).  Removed in round 3 as answered: `tree.unheld-parent-join`
  (with its `refuse` / `accept` code — replaced by `cannot-check`), the
  rule's depth (`parent-only` code replaced by every room above), and who
  cleans up after someone leaves a parent (the `client-cleans-up` lookup
  "which child rooms hold this address?" is gone; they are only flagged,
  found by the re-check).

Tests (`tests/`): a three-level tree on one home with relabelling,
filing, a late-arriving parent, a token change and a removed room (58);
the same tree on two homes with different labels and tags, arriving
bottom-up on one (15); the check — a stranger `no` in a child, someone in
the child but missing from the grandparent `no`, a member at another port
and a hostname `no`, filed and top rooms `yes`, a parent not held
`cannot-check`, a held parent with an unheld grandparent `cannot-check`
turning into `yes` when the grandparent arrives, and the re-check after
someone is dropped from `home` (38); both `tree.filing-loop` answers
(10); the forest and its drawing (11); mailboxes under both
`mailboxes.unheld-parent` answers (25, real only); and with the real 103
and 104 (24: 103 adds and flags by the check, 103's own listener flags the sister in ritz and programming after she is dropped from `home`, and 104's tops agree with the tree — the friend, flagged in ritz rather than refused, now has ritz as a top too).  `029-measure-tree.lua` times it: at 200 rooms a
snapshot takes about 0.014 s, one check about the same, a re-check down a
nine-deep chain about 0.012 s, and making a room (every `where`
rewritten) about 0.04 s.

Not done here: nothing in phase 1 removes a room, so the `removed-room`
path is tested by removing a folder and ringing the bell by hand.
104's own tests (not changed this round) fail against the real modules only where their test rooms are made without 101's new `mailbox_port` field; 102's snapshot, which 104 reads, did not change shape.

## Intended Behavior

Owner: "in the UI we will have rooms sorted like a directory tree
structure. Picture a filesystem that lets you open and collapse nodes to
view the contents in the tree. Very Microsoft Windows Explorer core."

- **Child rooms.**  A room made inside another carries the parent's token
  fingerprint in its entry's `parent`.  Anyone in a room may make a child
  room (owner: "Anyone. It's not like it's taking up space on a server
  somewhere").
- **The tree.**  A room's parent is the held room whose token fingerprint
  matches its `parent`; its children are the held rooms naming it.  A room
  whose parent is not held here is a top room.  Ancestors are listed top
  first.
- **The parent-membership rule** — tiers of trust.  Owner: "The farther
  down in the directory structure you go, the more people you'll need to
  have invited you."  **Detected, not enforced** (owner, 2026-09-25: "we
  can't control who gets to be in which room, because it's just a contact
  list on a person's computer ... however, we can *detect* when such
  things aren't true, and I believe we should").  This module answers
  "does this address belong in this room, by its parent?": `yes`; `no`
  (a declared child, and the address is not a member of the parent as this
  home server sees it); or `cannot-check` (a declared child whose parent
  this home does not hold).  103 adds the address either way and flags it
  on `no` or `cannot-check`.  The check is re-run for a room's children
  whenever the room's members change, so someone dropped from a parent
  shows up flagged in its children.
- **The `where` file** holds the room folder's path and the room's path of
  labels from the top (`home/ritz/programming`, in your own labels), kept
  beside the room so either is one read away.  Rewritten when a label,
  parent or filing changes above it.
- **Drawing the tree as text** stays, kept apart from the code that works
  the tree out, for the demo; the clients draw it as open-and-close
  folders.

## Suggested Implementation Steps

1. Parent by token fingerprint (101 gives the lookup); children, ancestors,
   top rooms.
2. The parent-membership check, for 103, answering `yes` / `no` /
   `cannot-check`, looking at every declared room above (not only the
   parent), and "which members of this room's declared descendants now
   fail the check?" for 103 to re-check when a room's members change.
3. `where` rewritten on `created`, `label`, `parent`, `filed`; the bell
   kind `mailbox` changes nothing in the tree.
3a. A room's mailbox follows its declared parent — chosen and moved by
   101; this module's tests check the tree and the mailboxes agree when a
   chain arrives bottom-up, under both answers to open question 3.
4. Keep `024-forest-text.lua`, fed from the new tree.
5. Retire `move_room`, parent disclosure, `what_contact_receives`, the
   reader's forest (`023`), and their choices.
6. Tests: a three-level tree on one home; the same tree on a second home
   with different labels (the fingerprints match, the labels do not); an
   address answered `no` in a child room when not in the parent, and
   `cannot-check` when the parent is not held; a child whose
   parent is not held is a top room; a grandchild member
   missing from the grandparent is `no`; an unheld ancestor further up is
   `cannot-check`; dropping someone from `home` shows them failing in
   `home`'s grandchildren.

### Round 4 (2026-09-25)

1. Declare this module's setting names to 101's config reader (101 round 4).
2. Point the open mailbox question at 101's new merge choice.

## Blockers that are not the owner's

- Needs 101's entry, token fingerprint and bell kinds.

## Open questions

Every choice this module holds open — those below, and those found while
building (named in Current Behavior) — is in its options file with what
building each variant showed; `scripts/tally-options --walk` goes through
them one at a time.  An issue with any of them unanswered is in progress.

1. *(answered 2026-09-25)* **Filing.**  A room may also be filed under
   another on your own screen only: the entry's `filed-under` (the local
   tag of the room it sits under, or empty), never sent, no rule applied.
   Declared children and filed rooms show in one tree; a room with both
   shows under its declared parent.  This module builds it.
2. *(answered 2026-09-25)* **When a member leaves the parent**, they are
   only flagged in its children (owner: "I think it's fine if they're just
   flagged if they no longer appear in the parent rooms that you know of.
   They won't know they're flagged for you - it's a personal setting.");
   nothing removes them, and a flag is never sent.  Earlier reading, kept
   for the record: the client also removes them from
   the parent's child rooms (owner: "This is UI work"); the lookup "which
   child rooms hold this address?" built for it was removed in round 3.

3. **A child room whose declared parent is not held here — which
   mailbox?**  Found while writing round 3.  Its own new mailbox (needs a
   port; stays there when the parent arrives, so one tree drawn can listen
   on several ports), or the one waiting mailbox until the parent arrives
   (then moved into the parent's mailbox, changing its listening port,
   which phase 2 must announce)?  Both built in 101's `make_room`,
   switched by `mailboxes.unheld-parent` (`own-mailbox` /
   `waiting-mailbox`), listed in 101's options file as
   `rooms-unheld-parent-mailbox`; tested here in
   `tests/028-test-mailboxes.lua`.

## Earlier designs

- **First model (built 2026-09-25):** each room recorded its parent's
  shared id; a reader's trees were joined from parent ids senders chose to
  disclose.  Building it showed the gap between two of a reader's trees
  closing one level per message, and that nothing told can be untold.
- **Second model (written, not built):** the tree was the room's name
  (`coffee-shop/games`), with islands and merging.  Replaced with the
  name-as-key idea.

## Related documents

- `notes/vision-planning.md` sections 1, 3 ("Child rooms"), 4, 15
- `docs/phase-1-module-contract.md`
