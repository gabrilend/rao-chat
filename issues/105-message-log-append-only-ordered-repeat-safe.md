# 105 — The message log: append-only, ordered, repeat-safe

**Phase:** 1 — Rooms on the home server
**Blocked by:** 101
**Blocks:** 106, 211, 214, 215
**Module folder:** `src/message-log/` (indexes 080–099)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Round 3 (2026-09-25): the owner's answered choices are fixed in place and
their switches removed.  Round 4: the log's one setting name is declared
to 101's config reader, which answered the retired-settings question.
Every test passes, both against a stand-in of the room-folders module and
against the real round-4 one (with mailboxes and declared settings).  Run
`src/message-log/tests/098-run-tests` for current counts.

What exists in `src/message-log/`:

- `081-message-log.lua` — the front door.  Filing a message
  (`append`), a correction (`correct`) or a deletion (`delete`); asking
  whether an id is there (`has_message`); reading in file order (`read`);
  reading as a person sees it (`read_ordered`: messages only, edits
  applied, sorted by written time then message id — nothing local takes
  part, so two homes that hold the room under different folder tags show
  one order).  Each record holds `from`: `"me"` or the address the copy
  arrived from, as `"<address> <port>"`.  There is no author field.
  A repeated id with the same written time, kind, target and text is
  `duplicate`, whatever address it came from and whenever it arrived; the
  first copy's `from` stays in the file (owner: "duplicate").  If any of
  those four differ, the result is an error that names the id and
  describes both versions, and nothing is filed.  Filing rings the bell
  with `log`.  The one config key read is `log.duplicate-check`, by
  `append`, `correct`, `delete` and `has_message`; reading needs none.
- `082-message-ids.lua` — message ids, and the field checks.
  `check_from` accepts `"me"` or a non-whitespace address, one space, and
  a port from 1 to 65535.
- `083-record-codecs.lua` — the one record shape, tsv: one line per
  record, `id TAB from TAB written TAB arrived TAB kind TAB target TAB
  text`, with backslash, tab, line feed and carriage return in the text
  escaped.  It is still looked up in a table by name (`codecs.SHAPE`,
  `codecs.SHAPES`), so a shape can be added back.  The block and jsonl
  codecs are deleted, and with them `libs/dkjson.lua`, which nothing else
  in the project required (checked with a project-wide search).
- `084-log-reader.lua` — log text back into records, one line each; it can
  also decode the single record at a known position (`parse_one`), so a
  repeat can be compared without decoding the whole log.  Recognising a
  record's shape by its first characters, and `log.shape-mixing`, are
  deleted.  A line left in a retired shape is refused loudly.
- `085-duplicate-check.lua` — `find` gives the already-filed record.
  `scan` finds it by its id marker and decodes that one record (so it
  does not notice a damaged line elsewhere until the log is read);
  `remembered` keeps whole records in memory and decodes each new record
  once (so a damaged line is an error at the next filing).
- `086-edits.lua` — edits are always allowed, by anyone, with no time
  limit (owner: anyone).  `check` only confirms the target is a message in
  the room and not already deleted.  Reading applies every edit in the
  file; each view carries `changed_from`, the address of the edit
  applied.  A deleted message stays in the view, empty and marked
  `deleted`; showing it as a gap or hiding it is the person's setting in
  the client (owner: "This is a UI concern").  Its text stays in the file.
- `087-settings.lua` — the setting names this module reads, declared to
  101's config reader (round 4): only `log.duplicate-check`.  The four
  retired names (`log.record-shape`, `log.shape-mixing`,
  `log.who-may-edit`, `log.same-id-new-address`) are deliberately absent,
  so a home whose config still holds one is refused by 101 when its
  config is read, with the line quoted — the owner's answer to "a retired
  key still in config" (it used to stop applying silently).
- `099-options.lua` — three choices still open: `log-duplicate-check`
  (switchable, waits on phase 2), `log-pictures`, `log-early-edits`
  (waits on phase 2).  Its header lists the choices removed as answered
  (round 4: `log-retired-keys-in-config`).
- `tests/` — codecs (tsv round trips, retired-shape lines refused), log
  (both duplicate checks; the conflict error; a repeat from another
  address answered duplicate with no key set; the exact line on disk; the
  address shapes; two homes with different tags showing one order), edits
  (anyone may edit; a leftover `log.who-may-edit` line is refused by the
  real 101 and never read by the log under the stand-in; the settings list
  holds exactly `log.duplicate-check` and the real 101 names this module
  as its owner; deleted messages stay marked), memory (the remembered check against outside
  appends and replaced files; a retired-shape line under both checks),
  measure, runner.  The test harness makes each room a top-level room in
  its own mailbox (make_room's round-3 `mailbox_port`); the stand-in
  insists on that field as the real module does.
- The round-1 and round-2 `-done` files are deleted (git history holds
  them).

Removed this round (answered by the owner): `log.record-shape` (tsv; the
block and jsonl variants went), `log.shape-mixing` (per-record and fixed
went), `log.who-may-edit` (anyone; same-address went),
`log.same-id-new-address` (duplicate; error went), and the deleted-view
choice (marked, shown as the client chooses).

Measured against the real round-3 room-folders module, 10,000 messages
(`tests/095-measure.lua "" real 10000`): 124.3 bytes per message; filing
all 10,000 takes 0.42 s with `remembered` and 5.7 s with `scan`;
delivering all 10,000 again takes 0.26 s and 3.6 s; reading them back
takes 0.03 s, in written order 0.04 s.

From room-folders, the log uses only `config_value`, `log_path`,
`notify` and the empty log made at birth.  The tests also use
`make_room` (with `mailbox_port`) and `new_local_tag`.

## Intended Behavior

- **One record per message**, one tab-separated line, appended, never
  rewritten: the message id, **the address it arrived from** (`me` for your own), time
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
  is `duplicate` and not filed again, even when it came from another
  address (owner: "duplicate").  **The same id with different
  contents is an error** — raised to the person, not quietly settled
  (owner: "If there's ever a discrepancy it's raised as an error, not a
  silent warning in some log somewhere that gets auto-corrected").
- **Edits are always allowed**, by anyone, with no time limit.  An edit is its own
  record with its own id, naming the one it changes; the original stays in
  the file, and the view shows the latest and the address the change came
  from.  A deleted message stays in the view, marked; the client decides
  how to show it.  Owner: "Everything is
  edit-able by design with no record, so nothing can be trusted unless
  you make local copies yourself."  The log is that local copy.
- **Filing rings the bell** with `log`.

## Suggested Implementation Steps

1. Records carry `from` (an address, or `me`), never an author, in the
   one record shape, tsv; keep the codec a table so a shape can be added.
2. Duplicate check: compare contents (written, kind, target, text) when an
   id repeats; equal is `duplicate` whatever address it came from,
   different is an error naming both.  Build both ways of finding the
   filed record (`scan`, `remembered`) under `log.duplicate-check` until
   phase 2 settles whether the server runs continuously.
3. Edits: corrections and deletions, by anyone, no time limit; the view
   applies the latest by (written, id) and names the address of the change;
   a deleted message stays in the view, marked.
4. Order by written time, ties by message id only.
5. No copying one log into another.
6. Tests: the conflict error; a repeat from another address; ordering
   identical on two homes whose local tags differ; lines in retired
   shapes refused.

## Blockers that are not the owner's

- Needs 101's room folders and bell.

## Open questions

Every choice this module holds open is in its options file with what
building each variant showed; `scripts/tally-options --walk` goes through
them one at a time.  An issue with any of them unanswered is in progress.

4. **Duplicate check** (`log.duplicate-check`, waits on phase 2):
   `remembered` (records kept in memory; 0.42 s to file 10,000) or `scan`
   (5.7 s; about 1 ms per message at 10,000).  Depends on whether the
   phase 2 server is one long-running program.
6. **An edit that arrives before its message** (phase 2): refused now;
   phase 2 will need to hold it until the message arrives.  Reading
   already applies such an edit once its message is filed.
7. **Pictures** (planning question 9): text only for now.

Answered (2026-09-25) and built as answered: record shape (1: tsv), who
may edit (2: anyone), mixing shapes (3: gone with the other shapes), a
deleted message (5: kept marked; the client chooses how to show it), the
same message from another address (8: duplicate).  Answered later and
built in round 4: a retired key still in config (9: an error — 101's
config reader refuses any line no module declares; the log declares only
`log.duplicate-check`).

## Earlier design (first model, built 2026-09-25)

Records carried an author (`me` or a contact name), edits could be
forbidden, allowed, or allowed within a time window, and a repeated id
was answered `duplicate` without comparing contents.  Three record shapes
were built and measured at 10,000 messages (bytes per message / seconds to
read all): tsv 116 / 0.02, a labelled block 167 / 0.04, one JSON object
per line 185 / 0.10; no index of ids was needed.  Round 2 kept all three
shapes, a switch for logs mixing them, and switches for who may edit and
for a repeat from another address; round 3 removed them as answered.

## Related documents

- `notes/vision-planning.md` sections 3 ("Order", "Edits", "Checking each
  other"), 4; section 14 ("Answers", 6, 7); section 15 ("Answers from
  the tally, round 2", "Five more from the tally", 1 and 3)
- `docs/phase-1-module-contract.md`
