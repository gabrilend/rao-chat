# 209 — Periodic cross-checking between members

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 202, 207
**Blocks:** 210

## Current Behavior

Nothing exists.  105 raises an error when one id arrives with two
different contents, naming both versions.

## Intended Behavior

Owner: "we shouldn't syncronize on every single message, but like...
periodically we can sync. If there's ever a discrepancy it's raised as an
error, not a silent warning in some log somewhere that gets auto-corrected.
But remember, we also need to be able to edit messages as well... Phew
this is complex!"

- **Periodically** (config `crosscheck.interval`, whole seconds, no
  default; on the gatherer's clock, 211) each server sends a `summary` to
  every pair on a room's send list: for each message written within the
  last `crosscheck.window` seconds (config, no default), its id and a
  **content fingerprint** — the first 16 bytes of SHA-256 over the fields
  every home agrees on (id, written time, kind, target, text: the same
  "agreed part" the shared text copies use, 215), never `from` or
  `arrived`, which differ per home.
- **A missing message is normal** — everyone chooses whom they send to —
  **but a sender fills its own gaps.**  A summary is a statement of what
  its sender holds, so when it shows that a pair on this server's send
  list lacks one of this server's own messages, that pair's `delivered`
  record (202) is corrected so the message is "not yet delivered" again,
  and 202's sender sends it — with its original id.  Owner: "the sender
  will notice "hey this person on the sending list doesn't have this
  message, I should send it" on their next sync cycle".  Only its own
  messages, and never to a withheld pair.
- **No summaries go to an ignored address** (103a), so ignoring stays
  quiet; un-ignoring lets the next summary show the gaps.
- **The same id with a different fingerprint is an error**, raised to the
  person with both versions: someone showing different words to
  different people under one id.
- **Edits never cause one**: an edit is its own message with its own id.

## Rubric

- **Gap-filling resends with the original id** (delivery R1).  A gap-filler
  that rewrites the message as new makes a new gap forever, or two copies.
- **"Delivered" moves only on acknowledgement** (delivery R4): the summary
  un-marks; only a real `ack` marks again.
- **Anything hashed for comparison is of stable, written fields**
  (structure note, rmail's 2026-08-03 edge case): the fingerprint covers
  only what every home writes identically.
- **Every periodic task is on the wake-up clock** (structure R8): a quiet
  server still sends its summaries.
- **The nonce budget** (sealing R1): summaries are sealed frames under the
  room key; every member summarising to every other member is the largest
  producer of frames in a big room.

## Where we differ

The earlier plan had its own resend path.  The formation here is **a
summary as a correction of 202's delivery record**: the cross-check never
sends a message itself; it only moves a pair's `delivered` record back, and
the one sending path does the rest.  And the summary is **windowed by
written time**, so its size follows recent traffic, not the room's age.

- **Gains:** one sending path, so R1 cannot be broken in two places; a
  summary of a quiet room is small.
- **Costs:** a two-faced message older than the window is never compared;
  the window must be long enough to cover a member's usual absence.

## Referees

1. **Gap filling uses the old id** (delivery T13).  A's message is removed
   from B's log by hand; after the next summary A resends it with its
   original id; a second summary sends nothing.  *Broken:* a new id.
2. **Choices are respected** (delivery T14).  B withheld or ignored on A,
   or the gap is someone else's message: nothing is resent.  *Broken:*
   resending everything missing.
3. **An edit is no discrepancy.**
4. **A two-faced sender is caught.**  A sends one id with text X to B and
   text Y to C; B and C's summaries meet: both raise the error with both
   versions.  *Broken:* a fingerprint over `from` or `arrived` (every
   message would differ); comparing ids only.
5. **Quiet servers summarise** (structure T8): with no traffic, the summary
   leaves within the interval plus one second.

## Suggested Implementation Steps

1. The agreed-part fingerprint (shared with 215).
2. The `summary` record and the timer, settings declared.
3. Comparing: un-marking in `delivered`; raising the error.
4. The referees above.

## Blockers that are not the owner's

- Needs 202 (`delivered` and the sender), 207 (members to compare with),
  and 105's conflict error.

## Open questions

1. **How often, and how far back**: values for `crosscheck.interval` and
   `crosscheck.window`?  (Was this issue's question 1.)
2. **Where the error is raised**: a notice in the room (centred, boxed, as
   section 7 describes), in the viewer's error strip, and anywhere else?
3. **The nonce budget** in large rooms (201's question 4) applies mostly
   here.

## Decisions (2026-11-05)

Made by the builder.  The owner's standing instruction is to answer open
questions rather than wait, choosing the option that is easiest to undo.
The owner can overturn each one; what overturning costs is said with it.
Built in `src/delivery/` (156 cross-check, 157's referees), with the
`summary` and `versions` rows in 126, two settings in 135 and 136, a
join point and `forget` in 130, the round in 134's stage, and a seam in
133.  Every referee runs in the simulated world, each against a broken
version where the issue names one.

1. **How often, and how far back** (open question 1): `crosscheck.interval`
   3600 seconds and `crosscheck.window` 604800 (a week), declared as
   options with no built-in default.  Hourly is quiet and fills a gap the
   same hour; a week covers a usual absence.  Undo: change the settings.
2. **Where the error is raised** (open question 2): in the room's
   `conflicts` file (the id, both fingerprints, the time, and both
   versions in words; once per id and pair of versions), in the stage's
   `conflicts` list, and through the stage seam `on_conflict(tag, id,
   mine, theirs)`.  The notice in the room and the viewer's error strip
   are phase 3's, built on that seam.  Nothing is corrected silently.
3. **The nonce budget** (open question 3): one connection per pair per
   round, carrying at most four frames (digest, its answer, summary,
   versions) plus their answers.  At an hour and 20 homes, 380
   connections an hour per room; 201's random 96-bit nonces stay far from
   their limit at that rate.  Revisit for rooms of hundreds.
4. **207's digest rides on the round** (207's decision 1): each job
   first runs 207's members exchange (`members-digest`) on the same
   connection, then the summary.  That is 207's automatic asking.
5. **Where a gap is filled:** the summary carries the summariser's own
   stated pairs (not its connection's source, which a router may
   rewrite).  The receiver makes its own records missing again only for
   those of the pairs that are on its send list and not ignored.  Naming
   a pair can only make this home send its own message to its own
   chosen recipient again, which the receiver files as a duplicate.
6. **Only messages meant for that pair:** `delivered` keeps, per line,
   the newest own record when the line was made (`after`).  A gap is
   filled only for own records after it, so a pair that joined later is
   not sent what was written before it (202's decision for open question
   3).  Lines made before this keep no `after` and count everything.
7. **One sending path:** the cross-check never sends a message.  It
   makes records missing again (130's `forget`) and wakes the stage, and
   202's sender sends them with their original ids.  Only an
   acknowledgement marks them delivered again (R4).
8. **Both versions on both sides:** a receiver whose fingerprint differs
   answers with its versions; the summariser raises the difference and
   sends its own versions back; the receiver raises it too.
9. **The fingerprint** is the first 16 bytes of SHA-256 over the
   record's agreed part, encoded by 126's own row for its kind: kind, id,
   written time, target and text, never `from` or `arrived`.  215's
   shared text copies may use the same encoding.
10. **A summary lists at most 10,000 records**, the newest, so a frame
    stays far under the 1 MiB cap.
11. **The round is on the stage's clock** (134's `pass` and `next_due`),
    armed by `start` when the stage can state its pairs, so a quiet home
    still summarises within the interval.

## Related documents

- `notes/vision-planning.md` section 3 ("Checking each other"); section 14
  ("Answers" 7)
- `notes/rmail-rubric/delivery-and-retries.md` (F1, T13, T14)
