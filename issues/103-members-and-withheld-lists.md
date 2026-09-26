# 103 — Members and withheld lists: who is in a room, and who you send to

**Phase:** 1 — Rooms on the home server
**Blocked by:** 101, 102
**Blocks:** 103a, 104, 106
**Sub-issues:** 103a (the ignore list)
**Module folder:** `src/recipients/` (indexes 040–059)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Rebuilt for "a room is a contact" (round 2, 2026-09-25) and tested: 62
checks pass against the stand-in neighbours, and 62 against the real
round-2 room folders (101) and room tree (102).  103a's ignore list shares
the folder and the test run (its own issue says what it covers).

What exists in `src/recipients/` (each source file with a `.info.md`):

- `040-address-pairs.lua` — the one shape of an address everywhere in this
  module: an address (IP v4, v6 or hostname, no spaces) always with its
  port (whole number 1–65535, no default).  Reads and writes the small
  space-separated files, each line starting `<address> <port>`.
- `041-recipients.lua` — members and who hears you:
  - members are read fresh from the room's entry (101's `read_entry`), and
    changed only through 101's member and last-heard writers;
  - adding a member gives a word, not an error: added, already, ignored
    (103a), or not-in-parent (102's check, whose reason is passed on).
    Ignoring is checked first, then the parent rule;
  - withholding and un-withholding write the room's `withheld` file (one
    `<address> <port>` per line) and ring the bell `withheld`; the send
    list is the members minus the withheld, in the entry's order;
  - a genuine message arriving (`heard_from`) adds the address if it is
    new (same refusals) and moves its last-heard time forward — never
    backward, so a late old message changes nothing;
  - `confirm_leave` is the only removal; phase 2 calls it after the
    address confirmed its own leave.  A withheld line outlives the leave,
    so a returning member is still withheld;
  - `silent_since` lists members not heard from since a given time
    (never-heard included), for a client's pruning offer; nothing removes
    them;
  - `shown_as` shows a member by the label of the one direct-message room
    holding its address, else by the address.
  Own devices are never members by construction: they have no entry, and
  nothing here adds them.
- `059-options.lua` — seven choices (four switchable, shared with 103a).
- `tests/` — stand-ins for 101 (`044`) and 102 (`046`), the harness
  (`045`, which starts every home with every module's first-listed
  variant), seven test files, and the runner `050-run-tests.lua` with
  three wirings: `stand-in`, `real-101` (real room folders, stand-in tree)
  and `real`.

Retired, renamed `-done` and kept until one commit carries them: the first
model's `041-recipients.lua` (split, arrival modes, `live_room_for`, the
`split` and `arrival` marker files), its `.info.md`, its tests (`046`–`049`),
its stand-ins (`042`, `043`), and copies of the rewritten harness, runner,
options test and options file.  Choices removed from the options file:
`recipients-arrival-list`, `recipients-split-shape`,
`recipients-split-parent`, `recipients-split-alone`,
`recipients-arrival-room-name`, `recipients-arrival-parent`.

Questions found while building (recorded in `059-options.lua` and the
contract's choices table; still open):

- **An address held by two direct-message rooms** (one person with two
  tokens, or two people misconfigured): shown by every label, or by the
  address?  Built both (`recipients.shared-address-label`), read only when
  it happens.
- **A withheld member who leaves and returns**: still withheld (built), or
  forgotten?
- **What records last-heard**: the arrival path calling `heard_from`
  (built), or a listener on the log's bell (not built: the bell does not
  say which message, so the log would be re-read every ring).  Waits on
  phase 2's arrival path.
- Open question 2 below (two addresses, one person) is built as "kept";
  "dropped" cannot be built, because nothing in a group room ties a new
  address to an old one.

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
- **Addresses are added freely**, with two refusals: an ignored address
  (103a), and, in a child room, an address that is not a member of the
  parent (102's check).  A second address for someone (they moved) is
  added beside the first.
- **An address is removed only by its own say-so** (a confirmed leave,
  phase 2).  Speaking again adds it back.  This is what stops a forged
  leave notice from cutting anyone off.
- **Your own devices are never members.**  They read the room through the
  home server.
- **No minimum.**  A room may have no members but you (one you are about to
  invite people to).

## Suggested Implementation Steps

1. Reading and writing members through 101's entry; `withheld`.
2. Adding a member, with the ignore and parent-membership refusals.
3. Withholding and un-withholding.
4. The send list: members minus withheld, as the list phase 2 delivers to.
5. Removing a member by its own confirmed leave (called by phase 2).
6. Showing a member by direct-message label or address.
7. Retire the split, the arrival modes, the `split` and `arrival` marker
   files, `live_room_for`, and their choices.
8. Tests: every member hears you by default; withholding; a move adds an
   address; a forged leave does nothing until confirmed; speaking again
   re-adds; a child room refuses an address not in the parent.

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
