# 103a — The ignore list, by address

**Phase:** 1 — Rooms on the home server
**Parent issue:** 103
**Blocked by:** 101, 103
**Blocks:** 104, 106
**Module folder:** `src/recipients/` (indexes 040–059, shared with 103)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Built (round 2) and fixed in place for two answered choices (round 3,
2026-09-25) in `src/recipients/042-ignore-list.lua`, with its `.info.md`,
and tested in `src/recipients/tests/048-test-ignore.lua` (part of 103's
run; see 103 for the counts).

- **The file** is `rao-home/ignore` (101 makes it empty with the home): one
  line per entry, `<address> <port> <level> <added> <scope>` — level `hide`
  or `mark`, added in whole seconds since 1970, scope `*` for the whole
  home or a room's local tag.
- **Ignoring** gives ignored, level-changed (the time is restamped) or
  already (nothing written, no bell); **un-ignoring** something not on the
  list (exact pair and scope) is an error.  Every change rings the bell
  `ignore`: on `""` for a whole-home entry, on the room's tag for a
  one-room entry.
- **An entry covers the whole IP address**, every port there (answered
  2026-09-25; the `ignore.match` switch is gone).  The port is still
  written on the line, since an address is always kept as a pair.
  Ignoring one port of an address ignores the others; everyone else behind
  that same public address is covered too.
- **Asking** "how is this address ignored in this room?" gives none, hide
  or mark; when two lines match (two ports at one address, or a whole-home
  line beside a one-room line), hide wins over mark, as a rule.
- **A hidden address's messages are not filed** (answered 2026-09-25; the
  `ignore.hide-files` switch is gone): "should this message be filed at
  all?" answers false for `hide` and true otherwise (`mark` is filed, so
  the room can show that they spoke).  The message log (105) asks it
  before filing.  Nothing is sent back.
- **The member filter**: 103's adding refuses an address ignored at either
  level, before the room tree is asked, so another member's list cannot
  bring it back; un-ignoring lets it in again.  Ignoring an existing
  member does not remove them, and does not withhold them.
- **An address change escapes the list**, by design.

Still built both ways, chosen in `rao-home/config` (absent or unknown values
are errors), recorded in `059-options.lua`: `ignore.scope` — open question
2: `home` (a one-room entry is refused, and one found in the file is
reported) or `home-and-room`.

Not integrated: the message log (105) does not yet ask `how_ignored` or
`files_message`; the cross-check's "no summaries to an ignored address"
is phase 2 (issue 209); the clients' views that show "someone you ignore
spoke" are later phases.

## Intended Behavior

Owner: "if you wanted to block or remove someone, you could have two
levels - hide all their messages from me because I don't want to see them,
but maybe I do want to know that they said something, or hide them
entirely from me."  And: "we could just keep track of our ignore list.
That'll stay valid until they change IP addresses."

- **One list for the whole home**, `rao-home/ignore`: one address per
  line, with its level and when it was added.
- **Two levels.**
  - `hide` — their messages are dropped on arrival: not filed, not shown,
    and nothing is sent back (answered 2026-09-25).
  - `mark` — their messages are not shown, but the room shows that they
    spoke ("someone you ignore spoke").
- **Ignoring is separate from withholding.**  Withholding (103) is whether
  your messages reach them; ignoring is whether theirs reach your eyes.
- **It also filters members.**  An ignored address brought back by another
  member's contact list is refused as a member, so syncing cannot undo
  your choice.
- **It holds until the address changes**, by design; nothing tries to
  follow a person to a new address.
- Changes ring the bell with `ignore`.

## Suggested Implementation Steps

1. Reading and writing `ignore` (address, level, added).
2. Ignoring, changing level, un-ignoring.
3. Asking "how is this address ignored?" — `none`, `hide`, `mark` — for
   the message log's view (105).
4. The member filter used by 103's adding.
5. Tests: both levels; a synced-back ignored address refused as a member;
   un-ignoring lets it back.

## Blockers that are not the owner's

- Needs 101's `ignore` file and bell kind, and 103's member adding.

## Open questions

Every choice this module holds open — those below, and those found while
building (named in Current Behavior) — is in its options file with what
building each variant showed; `scripts/tally-options --walk` goes through
them one at a time.  An issue with any of them unanswered is in progress.

1. *(answered 2026-09-25)* **`hide` does not file the message**: dropped on
   arrival, nothing kept, and nothing sent (ignoring is quiet).  No
   cross-check summaries go to an ignored address (issue 209), so it cannot
   tell; un-ignoring lets its server fill the gaps on the next cycle.
2. **Per room, or whole home?**  Written as whole home; would anyone want
   to ignore an address in one room only?

## Related documents

- `notes/vision-planning.md` sections 2 ("ignore list"), 3; section 14
- `docs/phase-1-module-contract.md`
