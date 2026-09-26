# 103 — Members and withheld lists: who is in a room, and who you send to

**Phase:** 1 — Rooms on the home server
**Blocked by:** 101, 102
**Blocks:** 103a, 104, 106
**Sub-issues:** 103a (the ignore list)
**Module folder:** `src/recipients/` (indexes 040–059)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Rebuilt for "a room is a contact" (round 2) and extended for flagged
members (round 3, 2026-09-25).  Tests: see the end of this section.  103a's
ignore list shares the folder and the test run (its own issue says what it
covers).

What exists in `src/recipients/` (each source file with a `.info.md`):

- `040-address-pairs.lua` — the one shape of an address everywhere in this
  module: an address (IP v4, v6 or hostname, no spaces) always with its
  port (whole number 1–65535, no default).  Reads and writes the small
  space-separated files, each line starting `<address> <port>`.
- `041-recipients.lua` — members and who hears you:
  - members are read fresh from the room's entry (101's `read_entry`), and
    changed only through 101's member and last-heard writers;
  - adding a member gives a word, not an error: added, added-flagged,
    already, or ignored (103a, the one refusal, checked before the tree);
  - **flagged members.**  An address that 102's check answers `no` (not a
    member of every declared room above, as seen here) or `cannot-check`
    (a room above is not held here) is added and flagged: a line
    `<address> <port> <no|cannot-check>` in the room's private `flagged`
    file (beside `withheld`; never sent).  The flag is written before the
    member, so no unreviewed member is ever on the send list.  Approving
    turns the line into `approved` (kept, so a later re-check does not flag
    them again); declining withholds the address and deletes the line;
    a confirmed leave deletes it too (a return is checked afresh).  Flag
    changes ring the bell `withheld` — both files only change who you send
    to, and a new kind would break listeners that refuse unknown kinds;
  - **re-checking**: the module listens on 101's bell.  When a room's
    members change (or its token), every room declared below it is checked
    again (102's `failing_below`) and newly failing members — no line yet,
    not withheld — are flagged, so someone who leaves a parent, or is shut
    out of it, shows up flagged in its children and grandchildren; nothing
    removes them.  When a room is made or its declared parent changes, its
    own members are checked too (a room arrives with its members already
    in it, and a parent arriving turns cannot-check into yes or no).  Each
    re-check also asks again about every flag awaiting review in the home:
    a changed answer is rewritten; a pass is handled by the open choice
    `recipients.flag-after-passing` (kept or cleared);
  - withholding and un-withholding write the room's `withheld` file and
    ring `withheld`; the send list is the members minus the withheld minus
    those awaiting review, in the entry's order;
  - a genuine message arriving (`heard_from`) adds the address if it is new
    (flagged if the tree says so; refused only if ignored) and moves its
    last-heard time forward — never backward;
  - `confirm_leave` is the only removal; phase 2 calls it after the address
    confirmed its own leave.  A withheld line outlives the leave;
  - `silent_since` lists members not heard from since a given time, for a
    client's pruning offer; nothing removes them;
  - `shown_as` shows a member by the label of the one direct-message room
    holding its address, else by the address.
  Own devices are never members by construction.
- `059-options.lua` — seven choices, three switchable (one shared with
  103a).
- `tests/` — stand-ins for 101 (`044`, with the `flagged` file and
  mailboxes) and 102 (`046`, the three-way check and the re-check lists),
  the harness (`045`: every home starts with every module's first-listed
  variant and the direct mailbox; `h.make` fills in make_room's
  `mailbox_port`), seven test files, and the runner `050-run-tests.lua`
  with three wirings: `stand-in`, `real-101` and `real`.

The round-2 `-done` files (the first model's recipients, its tests and
stand-ins, and copies of the rewritten harness, runner, options test and
options file) are still on disk: deleting them was refused by the
permission system in this session.  They are all in git (commit 99a2c77),
so the coordinator can remove them.

Choices: removed this round — none of 103's own (103a's `ignore-hide-files`
and `ignore-match` went, fixed in place).  Added — `recipients.flag-after-
passing` (switchable: `kept` / `cleared`) and "how long an approval lasts"
(built as until-they-leave).  Still open from before: an address held by two
direct-message rooms (`recipients.shared-address-label`); a withheld member
who leaves and returns (built: still withheld); what records last-heard
(built: the arrival path calls `heard_from`; waits on phase 2); open
question 2 below (built as kept).

Tests: 73 checks, all passing in each wiring — against the stand-ins,
against the real room folders (101) with the stand-in tree, and against the
real 101 and 102 together.  People-links (104, which reads members) was not
changed: its stand-in run passes (244); its real runs crash inside its own
test files before reaching this module, because 101's `make_room` now
requires `mailbox_port` (and 104's bell listener refuses the new `mailbox`
kind) — not caused by this module.

Not integrated: nothing calls `heard_from` or `confirm_leave` yet (phase
2's arrival path and leave check); the message log (105) does not yet ask
103a before filing.

## Intended Behavior

- **Members are the entry's address pairs** (101): each an address (IP or
  hostname) with its own port.  A member is shown by the label of the
  direct-message room holding that address, if any, else by the address.
- **Everyone hears you unless withheld.**  Your messages in a room go to
  every member not on your `withheld` list (one address per line).
  Withholding is all removal is; un-withholding brings them back.  Owner:
  "you could just... remove that person from everyone else's send-to
  contact list."
- **You cannot choose who hears anyone else.**  Each person keeps their own
  withheld list.  To shut someone out entirely, the room's token is
  changed by hand (101).
- **Addresses are added freely**, with one refusal: an ignored address
  (103a).  A second address for someone (they moved) is added beside the
  first.
- **Flagged members.**  In a declared child room, an address that 102's
  check answers `no` (not in the parent) or `cannot-check` (parent not
  held here) is added but **flagged**.  A flagged member is left out of the
  send list until the person reviews it: approving makes it an ordinary
  member, declining withholds it.  The client shows flagged members
  highlighted (owner: "The UI might flag them and highlight them in orange
  or something, to be manually reviewed by the user before sending
  messages to them").  When a parent's members change, its children's
  members are checked again and newly failing ones flagged.
- **An address is removed only by its own say-so** (a confirmed leave,
  phase 2).  Speaking again adds it back.  This is what stops a forged
  leave notice from cutting anyone off.
- **Your own devices are never members.**  They read the room through the
  home server.
- **No minimum.**  A room may have no members but you (one you are about to
  invite people to).

## Suggested Implementation Steps

1. Reading and writing members through 101's entry; `withheld`.
2. Adding a member, with the ignore refusal and the parent-membership
   flag; approving and declining a flagged member; re-checking children
   when a parent's members change.
3. Withholding and un-withholding.
4. The send list: members minus withheld, as the list phase 2 delivers to.
5. Removing a member by its own confirmed leave (called by phase 2).
6. Showing a member by direct-message label or address.
7. Retire the split, the arrival modes, the `split` and `arrival` marker
   files, `live_room_for`, and their choices.
8. Tests: every member hears you by default; withholding; a move adds an
   address; a forged leave does nothing until confirmed; speaking again
   re-adds; a child room flags an address not in the parent and leaves it
   off the send list until approved; dropping someone from a parent flags
   them in its children.

### Round 3 (2026-09-25)

Items 1, 2 and 4 are done and described in Current Behavior.  Left:

3. **Delete this module's `-done` files.**  Refused by the permission
   system in the builder's session; every file is in commit 99a2c77, so
   removing them loses nothing.

## Blockers that are not the owner's

- Needs 101's entry and bell kinds, and 102's parent-membership check.
- Confirming a leave is phase 2 (208); this issue gives it the function to
  call.

## Open questions

Every choice this module holds open — those below, and those found while
building (named in Current Behavior) — is in its options file with what
building each variant showed; `scripts/tally-options --walk` goes through
them one at a time.  An issue with any of them unanswered is in progress.

1. *(answered 2026-09-25)* **A silent member is never removed by the
   server.**  Owner: "no but we can add something in the UI to
   automatically prune users who've been silent for a while, according to
   their specifications."  This module records when each address was last
   heard from, so a client can offer pruning.
2. **Two addresses, one person.**  When a member moves, is the old address
   kept until it leaves (as rmail keeps several per contact), or dropped?
   The address rule says kept.
3. **A flag whose member later passes** (found in round 3): the room above
   arrives and holds them, or they join it.  Does the flag stay until you
   review it, or clear by itself?  Built both
   (`recipients.flag-after-passing`: `kept`, `cleared`).
4. **How long an approval lasts** (found in round 3): until the address
   leaves (built), or only until the tree's answer changes (e.g. an
   approved `cannot-check` whose parent arrives and says `no`)?

## Earlier designs

- **First model (built 2026-09-25):** each room kept contact names you
  sent to; removing someone split the room (`fork` or `rekey`), and rooms
  made on first arrival chose whom replies went to.  Building it showed
  that `heard-from` let a removed person back in the next time they spoke
  until a "declined" list was added — which survives as the ignore list
  (103a).
- **Second model (written, not built):** members were vouched for by
  existing members; replaced because holding a random token is itself the
  invitation.

## Related documents

- `notes/vision-planning.md` section 3; sections 14 ("Answers" 2, 3, 9)
  and 15
- `docs/phase-1-module-contract.md`
