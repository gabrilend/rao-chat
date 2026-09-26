# 103a — The ignore list, by address

**Phase:** 1 — Rooms on the home server
**Parent issue:** 103
**Blocked by:** 101, 103
**Blocks:** 104, 106
**Module folder:** `src/recipients/` (indexes 040–059, shared with 103)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Built (round 2, 2026-09-25) in `src/recipients/042-ignore-list.lua`, with
its `.info.md`, and tested in `src/recipients/tests/048-test-ignore.lua`
(17 of 103's 62 checks; all pass against the stand-ins and against the real
101 and 102).

- **The file** is `rao-home/ignore` (101 makes it empty with the home): one
  line per entry, `<address> <port> <level> <added> <scope>` — level `hide`
  or `mark`, added in whole seconds since 1970, scope `*` for the whole
  home or a room's local tag.
- **Ignoring** gives ignored, level-changed (the time is restamped) or
  already (nothing written, no bell); **un-ignoring** something not on the
  list is an error.  Every change rings the bell `ignore`: on `""` for a
  whole-home entry, on the room's tag for a one-room entry.
- **Asking** "how is this address ignored in this room?" gives none, hide
  or mark; when two lines match, hide wins over mark, as a rule, so the
  order of lines never decides.  A second question, "should this message
  be filed at all?", is for the message log (105) to ask before filing.
- **The member filter**: 103's adding refuses an address ignored at either
  level, so another member's list cannot bring it back; un-ignoring lets
  it in again.  Ignoring an existing member does not remove them, and does
  not withhold them.
- **An address change escapes the list**, by design.

Built every way, chosen in `rao-home/config` (absent or unknown values are
errors), recorded in `059-options.lua`:

- `ignore.hide-files` — open question 1: `filed` or `not-filed`.  `mark` is
  filed under both, since the room must show that they spoke.
- `ignore.scope` — open question 2: `home` (a one-room entry is refused,
  and one found in the file is reported) or `home-and-room`.
- `ignore.match` — found while building: an entry covers its exact
  `pair`, or every port at the `host`.  The owner's words ("until they
  change IP addresses") lean to host; the glossary's "an address is always
  a pair" leans to pair.  Host also ignores everyone sharing that public
  address.

Not integrated: the message log (105) does not yet ask `how_ignored` or
`files_message`; the clients' views that show "someone you ignore spoke"
are later phases.

## Intended Behavior

Owner: "if you wanted to block or remove someone, you could have two
levels - hide all their messages from me because I don't want to see them,
but maybe I do want to know that they said something, or hide them
entirely from me."  And: "we could just keep track of our ignore list.
That'll stay valid until they change IP addresses."

- **One list for the whole home**, `rao-home/ignore`: one address per
  line, with its level and when it was added.
- **Two levels.**
  - `hide` — their messages are filed (your log is your record) but never
    shown.
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

1. **Does `hide` file the message at all?**  Filed-but-never-shown keeps
   your log a full record (useful for the periodic cross-check, phase 2);
   not filing saves space.  Suggested: filed.
2. **Per room, or whole home?**  Written as whole home; would anyone want
   to ignore an address in one room only?

## Related documents

- `notes/vision-planning.md` sections 2 ("ignore list"), 3; section 14
- `docs/phase-1-module-contract.md`
