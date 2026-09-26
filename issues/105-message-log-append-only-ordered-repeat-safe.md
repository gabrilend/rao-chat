# 105 — The message log: append-only, ordered, repeat-safe

**Phase:** 1 — Rooms on the home server
**Blocked by:** 101
**Blocks:** 106
**Module folder:** `src/message-log/` (indexes 080–099)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Rewritten for "a room is a contact" (round 2, 2026-09-25).  Every test
passes, both against a stand-in of the round-2 room-folders module and
against the real one.  Run `src/message-log/tests/098-run-tests` for
current counts.

What exists in `src/message-log/`:

- `081-message-log.lua` — the front door.  Filing a message
  (`append`), a correction (`correct`) or a deletion (`delete`); asking
  whether an id is there (`has_message`); reading in file order (`read`);
  reading as a person sees it (`read_ordered`: messages only, edits
  applied, sorted by written time then message id — nothing local takes
  part, so two homes that hold the room under different folder tags show
  one order).  Each record holds `from`: `"me"` or the address the copy
  arrived from, as `"<address> <port>"`.  There is no author field.
  A repeated id with the same contents answers `duplicate`.  If the
  written time, kind, target or text differ, the result is an error that
  names the id and describes both versions, and nothing is filed.  The
  arrival time never counts.  A repeat that differs only in `from` goes by
  `log.same-id-new-address` (`duplicate` or `error`).  That key is read
  only in this case.  Filing rings the bell with `log`.  Copying one log
  into another is retired.
- `082-message-ids.lua` — message ids, and the field checks.
  `check_from` accepts `"me"` or a non-whitespace address, one space, and
  a port from 1 to 65535.
- `083-record-codecs.lua` — the three record shapes (tsv, block, jsonl),
  field `from` in place of `author`.
- `084-log-reader.lua` — log text back into records.  It can now also
  decode the single record at a known position (`parse_one`), so a repeat
  can be compared without decoding the whole log.
- `085-duplicate-check.lua` — `find` gives the already-filed record, not
  just yes/no.  `scan` finds it by marker and decodes that one record.
  `remembered` now keeps whole records in memory (not just ids).
- `086-edits.lua` — edits are always allowed, with no time limit.  Who may
  edit (open question 2) is built both ways under `log.who-may-edit`:
  `anyone`, or `same-address`.  That key is read only when an edit is
  filed.  The rule governs filing; reading applies every edit in the
  file.  Each view carries `changed_from`, the address of the edit
  applied.  The `never` and `window` rules, and the keys `log.edits` and
  `log.edit-window-seconds`, are retired.
- `099-options.lua` — eight choices (five switchable), with measured figures.
- `tests/` — codecs, log (all 12 setting combinations; the conflict
  error; a repeat from another address under both values; the address
  shapes; two homes with different tags showing one order), edits (both
  `log.who-may-edit` values in every shape), mixing and memory, measure,
  runner.
- Retired round-1 files are kept beside the new ones as `<name>-done`.

From room-folders, the log uses only `config_value`, `log_path`,
`notify` and the empty log made at birth.  The tests also use
`make_room` and `new_local_tag`.  The size and speed figures in the
options file were measured with the stand-in.  To re-measure against the
real module, run `tests/095-measure.lua "" real 10000`.

## Intended Behavior

- **One record per message**, plain text, appended, never rewritten: the
  message id, **the address it arrived from** (`me` for your own), time
  written and time arrived (whole seconds since 1970), kind (`message`,
  `correction`, `deletion`), the id it changes (empty for a message), and
  the text.  A person can read a room with `cat` or `less`, back it up by
  copying the folder, and search it with `grep`.
- **The signature is part of the text** — its last line, by convention.
  The log stores it as written; showing it apart is the client's job.
  Nothing here checks it: the sender is unknowable by design, and the
  address a message came from proves nothing about who wrote it.
- **Order.**  Shown by time written; a late message is placed where it
  belongs.  Ties are broken by message id alone, so every reader sees the
  same order.  Ordering happens when reading, never by rewriting the file.
- **Ids make delivery safe to repeat.**  The same id with the same contents
  is `duplicate` and not filed again.  **The same id with different
  contents is an error** — raised to the person, not quietly settled
  (owner: "If there's ever a discrepancy it's raised as an error, not a
  silent warning in some log somewhere that gets auto-corrected").
- **Edits are always allowed**, with no time limit.  An edit is its own
  record with its own id, naming the one it changes; the original stays in
  the file, and the view shows the latest.  Owner: "Everything is
  edit-able by design with no record, so nothing can be trusted unless
  you make local copies yourself."  The log is that local copy.
- **Filing rings the bell** with `log`.

## Suggested Implementation Steps

1. Rename the `author` field to `from` (an address, or `me`) in every
   record shape and in reading.
2. Duplicate check: compare contents when an id repeats; equal is
   `duplicate`, different is an error naming both.
3. Edits: keep `corrections`; retire `never` and `window` and the
   `log.edits` / `log.edit-window-seconds` keys.  Remove the "only the
   author may edit" rule (see open question 2).
4. Tie-break by message id only.
5. Retire copying one log into another.
6. Keep the three record shapes, both mixing rules and both duplicate
   checks as switchable choices until the owner picks.
7. Tests: the conflict error; ordering identical on two homes whose local
   tags differ.

## Blockers that are not the owner's

- Needs 101's room folders and bell.

## Open questions

Every choice this module holds open — those below, and those found while
building (named in Current Behavior) — is in its options file with what
building each variant showed; `scripts/tally-options --walk` goes through
them one at a time.  An issue with any of them unanswered is in progress.

1. **Record shape** (planning question 8, `log.record-shape`): `tsv`
   (116 bytes per message, reads 10,000 in 0.02 s), `block` (167, 0.04 s),
   `jsonl` (185, 0.10 s).  Builder's leaning: `tsv`.
2. **Who may edit a message?**  The first build allowed only its author,
   but the author is now unknowable.  Any edit accepted (the original is
   always kept and viewable), or only edits arriving from the same address
   as the original?  (Found while rewriting.)
3. **Mixing shapes** (`log.shape-mixing`): may one log hold records in
   several shapes after the setting changes (`per-record`), or not
   (`fixed`)?  Builder's leaning: `per-record`.
4. **Duplicate check** (`log.duplicate-check`, waits on phase 2):
   `remembered` (ids kept in memory, about 0.1 ms per message) or `scan`
   (about 1 ms per message at 10,000).  Depends on whether the phase 2
   server is one long-running program.
5. **A deleted message** is shown as empty and marked, so links to it still
   work; its text stays in the file, so deletion hides rather than erases.
   Right?
6. **An edit that arrives before its message** (phase 2): refused now;
   phase 2 will need to hold it until the message arrives.
7. **Pictures** (planning question 9): text only for now.
8. **The same message from another address** (`log.same-id-new-address`,
   found while rewriting).  Suppose a repeat matches the filed message in
   everything but the address it came from.  That can be honest: a member
   who moved, or a missing message fetched from another member during the
   cross-check.  Should it be answered `duplicate`, or raised as an
   `error`?  Builder's leaning: `duplicate`, because the address proves
   nothing either way.

## Earlier design (first model, built 2026-09-25)

Records carried an author (`me` or a contact name), edits could be
forbidden, allowed, or allowed within a time window, and a repeated id
was answered `duplicate` without comparing contents.  Measured then: the
figures in open question 1; no index of ids needed at 10,000 messages.

## Related documents

- `notes/vision-planning.md` sections 3 ("Order", "Edits", "Checking each
  other"), 4; section 14 ("Answers", 6, 7)
- `docs/phase-1-module-contract.md`
