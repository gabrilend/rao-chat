# 102 — The room tree: child rooms, and the parent-membership rule

**Phase:** 1 — Rooms on the home server
**Blocked by:** 101
**Blocks:** 103, 104, 106
**Module folder:** `src/room-tree/` (indexes 020–039)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Rebuilt for "a room is a contact" (round 2, 2026-09-25) and tested: 121
checks pass against a stand-in room-folders module and 142 against the
real round-2 modules (`src/room-tree/tests/038-run-tests.sh`), 21 of them
with the real members module (103) and people-links module (104) loaded.
The phase 1 demo's tree scene runs on it.  The contract's 102 section
describes it.  Round 1's files are kept beside the new ones as
`<name>-done` until one commit has carried them.

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
- **The parent-membership rule**: "may this (address, port) join this
  room?" — yes for a top or a merely filed room; for a declared child,
  only if that exact pair is a member of the declared parent here; for a
  child whose parent is not held here, the new setting
  `tree.unheld-parent-join` (`refuse` / `accept`).  103's `add_member`
  asks it and passes the refusal on as `not-in-parent` with the reason.
- **"Which child rooms hold this address?"** — every declared child below
  a room (all levels, top-down) whose members include the pair, for the
  client's clean-up when someone leaves a parent (open question 2).
- **Keeping `where` true**: a bell listener rewrites every room's `where`
  on `created`, `label`, `parent`, `filed` and `token`; on `removed-room`
  it first unfiles rooms filed under the removed one; member, last-heard,
  withheld, log and ignore changes are ignored.  A ring closed by a
  declared parent arriving above a room you filed is settled by the new
  setting `tree.filing-loop` (`unfile` / `refuse`); a ring of declared
  parents alone is always an error.  A token changed by hand needs nothing
  here: room-folders re-points held children before it rings.
- `022-where-file.lua` — `where` as two lines, `folder = …` and
  `labels = …`; a `/` inside a label is written `\/` (labels may hold
  any text but a line break), and the path splits back exactly.
- `024-forest-text.lua` — draws the forest as text with box-drawing
  branches and the marks `(filed)` and `(parent not held here)`.
- `039-options.lua` — six choices: `tree.unheld-parent-join`,
  `tree.filing-loop` (switchable), and four not switchable, each found
  while building: what counts as the same member (`exact-pair` built;
  a hostname is not matched to its IP), who cleans up child rooms when
  someone leaves a parent (`client-cleans-up` built, open question 2),
  whether the rule checks only the direct parent (`parent-only` built),
  and where rooms filed under a removed room go (`unfile` built; waits on
  phase 2's leaving).  Retired with the first model: parent disclosure,
  disclosure refresh, where per recipient, untelling on removal, slash in
  path.
- Retired to `-done`: `023-reader-forest.lua`, `move_room`, parent
  disclosure, `what_contact_receives`, and their tests (033, 034, 035 of
  round 1).

Tests (`tests/`): a three-level tree on one home with relabelling,
filing, a late-arriving parent, a token change and a removed room (58);
the same tree on two homes with different labels and tags, arriving
bottom-up on one (15); the rule, including a stranger refused in a child,
a grandchild refused someone only in the grandparent, both
`tree.unheld-parent-join` answers, and the child-rooms lookup (27); both
`tree.filing-loop` answers (10); the forest and its drawing (11); and with
the real 103 and 104 (21).  `029-measure-tree.lua` times it: at 200
rooms a snapshot takes about 0.01 s and making a room (every `where`
rewritten) about 0.04 s.  Measuring showed 104 calling the tree once per
room made each rebuild read the home rooms × rooms times (2.6 s per new
room at 200 rooms); 104 now takes one snapshot per rebuild.

Not done here: nothing in phase 1 removes a room, so the `removed-room`
path is tested by removing a folder and ringing the bell by hand.  The
owner's confirmation of open question 2 is still wanted.

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
   `cannot-check` (replacing the refusal and `tree.unheld-parent-join`),
   and "which members of this room's children now fail the check?" for
   re-checking when a parent's members change.
3. `where` rewritten on `created`, `label`, `parent`, `filed`.
4. Keep `024-forest-text.lua`, fed from the new tree.
5. Retire `move_room`, parent disclosure, `what_contact_receives`, the
   reader's forest (`023`), and their choices.
6. Tests: a three-level tree on one home; the same tree on a second home
   with different labels (the fingerprints match, the labels do not); an
   address answered `no` in a child room when not in the parent, and
   `cannot-check` when the parent is not held; a child whose
   parent is not held is a top room.

### Round 3 (2026-09-25)

1. **Detection, not refusal.**  The check answers `yes` / `no` /
   `cannot-check`; `tree.unheld-parent-join` goes.
2. **Every room above** (owner's answer to `tree-rule-depth`): an address
   is `yes` only if it is a member of every declared ancestor this home
   holds; a declared ancestor not held gives `cannot-check`.
3. **Re-checking**: "which members of this room's declared descendants now
   fail the check?", for 103 to flag when a room's members change.
4. **A room's mailbox** follows its declared parent (101 stores it); a
   child made while its parent is not held — see open question below.
5. Delete this module's `-done` files.
6. Tests: a grandchild member missing from the grandparent is `no`; an
   unheld ancestor is `cannot-check`; dropping someone from `home` shows
   them failing in `home`'s grandchildren.

**Open (found while writing):** a child room whose declared parent is not
held here — which mailbox?  Its own new one (needs a port), or held in a
waiting mailbox until the parent arrives?  Build both, switched.

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
   the parent's child rooms; the server flags them in the children (detection, not refusal)
   (owner: "This is UI work").  This module offers "which child rooms hold
   this address?" for the client.  Reading to be confirmed by the owner.

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
