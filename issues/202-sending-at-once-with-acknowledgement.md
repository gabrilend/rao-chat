# 202 — Sending at once, with acknowledgement and retries

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 201, 201a, 211
**Blocks:** 204, 205, 209, 210

## Current Behavior

Nothing exists.  Phase 1 provides what this issue sends from and files
into: each room's `log` (105: one tab-separated record per message, with
its id, `from` = `me` or `"<address> <port>"`, written and arrived times)
and each room's send list (103's `send_list`: members minus withheld minus
those awaiting review).  211 gives the sender stage a place to run.

## Intended Behavior

- **A new message goes out immediately** to every (address, port) pair on
  the room's send list.  The retry timer governs only retries after a
  failure (planning section 5, "The one change for chat").
- **Every address-and-port pair is a recipient** (owner, 2026-09-27: "the
  contact entry is the room, and the IPs are the contacts").  A member
  with two addresses gets the message at both.  Nothing is "moved to the
  front"; there is no first-that-answers.
- **A delivery counts only when acknowledged**, and the acknowledgement
  (`ack` record, 201) **names the message ids it covers**, each with the
  receiver's word: `filed` or `duplicate`.  Both mean delivered.  An
  answer naming other ids, or none, delivers nothing.
- **The log is the outbox.**  There is no outbox folder and no queue file.
  Beside each room, a `delivered` file keeps, per pair on the send list,
  what that pair has acknowledged: a mark (written time, integer seconds
  since 1970 — every own message written at or before it is acknowledged)
  plus a short list of ids acknowledged after the mark.  "Not yet
  delivered to X" is computed: own messages in the log (`from` = `me`)
  after X's mark and not in X's list.  An acknowledgement moves the mark
  forward whenever the list closes a gap.
- **Resends carry the same id, always.**  The id is fixed when the message
  is filed (105), so a lost answer followed by a resend is recognised by
  the receiver as `duplicate`.
- **Retries slow down and never give up.**  Per pair: an interval (whole
  seconds) that doubles on each failed attempt from a floor to a ceiling
  (config `delivery.retry-floor`, `delivery.retry-ceiling`, no defaults;
  rmail's 30 s and 2 h are starting values to write), with each wait
  offset by a card dealt from a shuffled deck without replacement whose
  cards sum to zero (the phone's locked-screen device, planning section 6).
  One failed attempt is one failure however many messages wait.  Owner:
  "letting the messages pile up with unsent contacts still waiting is fine
  probably, unless it strains the rmail single-threaded messaging core
  engine in which case we'll re-assess at scale."
- **Receiving** (the filer, 211): the key that opens the frame says which
  room it is for; file it (105), unless the arriving address is on the
  ignore list at `hide` (103a), and record it heard (103's `heard_from`,
  which adds and flags as phase 1 decides).  Holding the token is being
  invited, so a genuine message from a new address is filed; the address
  becomes a sendable member once its hello (205) says where to call back.
  Then answer with the ids.

## Rubric

From `notes/rmail-rubric/delivery-and-retries.md` section 2.

- **The id is fixed when the message is written; every resend carries it**
  (R1).  A sender cannot tell "not delivered" from "delivered, answer
  lost"; only a stable id lets the second copy be recognised.  rmail draws
  a new id per planned send and filed one message eight times.
- **A repeat is acknowledged, not refused** (R2) — including a repeat from
  another address (105 already answers `duplicate` whatever address).
- **File first, then acknowledge** (R3) — 211's switch decides which write.
- **"Delivered" moves only on an acknowledgement, for every kind of
  change** (R4).  rmail stored an edit as sent while only planning it, so
  edits made while a contact was not due were lost.  An edit here is its
  own message with its own id.
- **An acknowledgement is authenticated and bound to what it
  acknowledges** (R5; sealing note R9).  An old "ok" replayed onto a new
  connection must not deliver a new message.
- **Receiving never waits on sending** (R6) — 211's separate sender stage.
- **Backoff belongs to each destination, and only a real attempt moves
  it** (R7).  A held-back attempt is not a failure.
- **One failed attempt is one failure, however many messages wait** (R8).
  rmail once stepped a contact from 30 s to 36 minutes in a single cycle.
- **The timer moves even when the work around it fails** (R9).
- **Every destination is eventually tried again; nothing is dropped
  silently** (R11).
- **Partial writes are completed; lengths bounded before reading** (R12) —
  201.
- **Jitter comes from a real random source** (structure note R7): rmail's
  unseeded generator gave every start the same "random" schedule.

## Where we differ

rmail keeps an outbox folder of files plus a JSON delivery record rewritten
whole each pass, one timer per contact with additive growth and ± 30 s
noise, and sends at the next due time.  This issue tries the delivery
note's **F1 (the log is the outbox) with F2 (one sending job per pair) and
F3 (a dealt deck and doubling)**.

- **Gains:** R1 and R4 hold by construction (the only thing ever sent is a
  log record with its log id); retry here and gap-filling in 209 become one
  operation ("send what X is missing"); nothing to keep in step between an
  outbox and a record; waits average exactly the interval over each deck;
  eight doublings to the ceiling instead of twenty additions.
- **Costs:** "what is X missing" means reading the log from X's mark (an
  index or the log's tail in RAM for big rooms — 211 already holds it in
  RAM); a new pair's mark is a policy (open question 3); doubling retries a
  flapping address less often than rmail's additive growth.

## Referees

From the delivery note's section 5, run between homes on one machine with
a fault-injecting relay where named.

1. **Lost answer** (R1, R2).  The relay forwards A's frame, then drops B's
   answer; A retries.  B holds the message once; the second attempt is
   answered `duplicate`; A marks it delivered and sends no third.
   *Broken:* a new id per attempt; a receiver that errors on a repeat.
2. **Mutual send** (R6).  A and B each send to the other at the same
   instant through a 2-second relay delay: both delivered on the first
   attempt, neither backs off.  *Broken:* a sender that waits for its
   answer before returning to accept.
3. **Edit while away** (R4).  B down; A writes a message and an edit; B
   returns and holds both.  *Broken:* an edit marked sent when planned.
4. **Held back is not failed** (R7).  B reachable, nothing due for several
   rounds: its interval stays at the floor.  *Broken:* counting a held-back
   attempt as a failure.
5. **Pile of fifty** (R8).  B down; A writes 50 messages in one round: B's
   interval after the round equals that after one message.  *Broken:*
   backoff per message.
6. **Long absence** (R11).  B down for a simulated 72 hours on a fake
   clock: everything reaches B afterwards; attempts per day at the ceiling
   match 24 h ÷ ceiling within one deck's spread.  *Broken:* a retry cap.
7. **Forged answer** (R5).  The relay drops B's answer and sends an `ack`
   sealed with another room's key, then one sealed correctly naming
   another id: the message stays undelivered both times.  *Broken:* any
   answer on the connection counts.
8. **Two addresses, two copies.**  A member with pairs P and Q: both
   receive; P acknowledging does not mark Q delivered.  *Broken:* rmail's
   first-that-answers.
9. **The deck averages exactly.**  Over one full deck the sum of waits
   equals cards × interval.  *Broken:* drawing with replacement.

## Suggested Implementation Steps

1. The `delivered` file per room (one line per pair: address, port, mark,
   ids after the mark) and the "missing for X" computation from the log.
   Add the file to the contract's room-folder table.
2. Sending on filing: the filer writes a `due/` entry per pair on the send
   list; the sender stage takes it.
3. The sender: one job per pair, the whole backlog on one connection, the
   `ack` read and applied id by id (R21 of the structure note).
4. Retry timers per pair with the deck and doubling; settings declared.
5. Receiving: file, record heard, answer with ids.
6. Measure the pile at scale (the owner's condition for re-assessing).
7. The referees above.

## Blockers that are not the owner's

- Needs 201, 201a and 211; filing needs 105; the ignore choice needs 103a;
  flagging needs 102 and 103.

## Open questions

1. **What resets a backed-off pair early?**  rmail resets a contact on
   hearing from it; rao-chat cannot tell which pair a frame came from.
   Match on the source IP (any pair at that IP becomes due now), wait for a
   hello naming the port, or never?  (Rubric question 7.)
2. **Timers across a restart**: keep each pair's interval on disk, or
   everyone due at start-up as in rmail?  (Rubric question 32.)
3. **A new or un-withheld pair's backlog**: does it get the room's past own
   messages (its mark starts at "nothing") or only what is written after
   it joins (its mark starts at "now")?  (Rubric question 22.)
4. **What the floor means once sends are immediate**: the first retry
   after a failure (proposed), since nothing healthy is polled?  (Rubric
   question 34.)
5. **A forged acknowledgement from another member**: any member on the
   path can seal an `ack` for another member's pair.  Betrayal (outside
   the threat model), or checked by a call-back (204)?  (Rubric
   question 35.)
6. **Showing a growing pile**: a count beside the pair in the viewer, and
   what number "strains the engine" — messages, bytes, or time since the
   last acknowledgement?  (Rubric question 30; was this issue's
   question 2.)
7. **An edit that arrives before its message** (105 builds `refuse`):
   refuse, so the sender retries until the message has arrived, or hold?
8. *(answered 2026-09-27)* **Two addresses: both, or the first that
   answers?**  Owner: "the contact entry is the room, and the IPs are the
   contacts" — both.
9. *(answered 2026-09-27)* **The log is the outbox.**  Owner, on it: "not
   just the outbox" — the log stays the delivery record, and receive hooks
   also write text copies into git (215).
10. *(to confirm)* **An acknowledgement names its ids** and a bare "ok" is
    refused.

## Decisions (2026-11-05)

Made by the builder: the owner's standing instruction is to answer open
questions rather than wait, choosing the option easiest to undo.  Each is
written so the owner can overturn it; what overturning costs is said.
Built in `src/delivery/` (130–137) and the `ack` row of
`src/sealing/126-inner-records.lua`; 211's stages, sockets and workers
are seams (see "Left for 211" below).

1. **What resets a backed-off pair early** (question 1): a frame that
   opens in a room, arriving from an address, makes every pair of that
   room at that address due now (`Stage:heard_at`, called by the
   receiver).  The interval is kept; only a delivered attempt puts it back
   to the floor.  Undo: one call in the receiving stage.
2. **Timers across a restart** (question 2): not kept.  At start-up every
   pair missing something is due at once (`Stage:start`), as in rmail.
   Undo: a small file of (pair, interval, due) per home; nothing reads one
   today.
3. **A new or un-withheld pair gets what is written from then on**
   (question 3).  Before an own record is filed, every pair on the send
   list without a line gets one that counts everything already filed as
   acknowledged, and lines of pairs no longer on the list are dropped, so
   a withheld pair that returns starts again then.  Chosen because a
   message sent cannot be unsent, while a missed one can still be sent
   (209's gap filling, or a line reset by hand).  Undo: `starting_line` in
   `130-delivered.lua` makes the mark 0 instead (and `join` keeps lines).
4. **The floor is the first wait after a failure** (question 4), as
   proposed.  Nothing healthy is polled.
5. **A forged acknowledgement from another member** (question 5): outside
   the threat model here.  An answer counts only if it opens with the
   room's key (so its tying value, 201a) and names ids sent on that same
   connection, which stops an old answer delivering a new message and an
   answer from another room (R5).  A member who forges answers for
   another member can only hide a gap, which 209's cross-check refills.
   204's question stands.
6. **Showing the pile** (question 6): `pile(home, tag)` gives, per pair,
   how many records wait and the written time of the oldest, for the
   viewer (301).  The measure is the count of messages; nothing is done
   about a large one yet.  Measured (step 6): working out what one pair
   misses in a log of 10,000 own messages takes about 0.07 s, and
   acknowledging 5,000 of them out of order about 0.09 s (test 137 prints
   it).  Both read the log from disk; 211 holds it in memory.
7. **An edit that arrives before its message** (question 7): refused, as
   105 builds it.  The receiver answers that frame with no word for its
   id, so the sender keeps it missing and sends it again on a later
   attempt.  A connection carries a pair's missing records in log order,
   a message before its edits, so this happens only when the message's
   own frame failed.
8. *(answered by the owner)* Both addresses.  Referee 8.
9. *(answered by the owner)* The log is the outbox.
10. **An acknowledgement names its ids** (question 10): confirmed.  The
    `ack` row has one field, `answers`: each id followed by `filed` or
    `duplicate`, separated by single spaces.  An odd count, another word
    or a malformed id makes the whole answer count for nothing; an empty
    one is allowed and delivers nothing; there is no bare "ok".  The
    receiver answers every frame with one `ack`.  Undo: the row and
    `read_answers` / `write_answers` in `132-send.lua`.
11. **Who an arriving frame is from.**  A connection shows the peer's
    address and a source port the system picked, not the port it listens
    on.  If exactly one member of the room is at that address, `from` is
    that member's pair and 103's `heard_from` records it; otherwise `from`
    is the address and the source port, and nobody is recorded heard,
    because `heard_from` would add the source port as a sendable member.
    205's hello says where to call back.  Undo: `sender_of` in
    `133-receive.lua`.
12. **A message from an address ignored at `hide`** is dropped and
    answered `filed`, so the sender stops resending and is not told it is
    ignored.  Undo: answer nothing, and the sender retries at the ceiling
    forever.
13. **A window of 32 frames**: a long backlog goes out 32 frames at a
    time, then their 32 answers are read, so answers never pile up in the
    sender's buffer while it writes (two blocking ends could otherwise
    wait on each other).  Undo: `WINDOW` in `132-send.lua`.
14. **The deck**: the eleven cards -5 .. 5, each worth floor(interval /
    12) seconds, so a wait is 7/12 to 17/12 of the interval and one deck
    at one interval adds up to exactly 11 intervals.  The same device
    answers the planning document's question 4 for the phone only if the
    owner wants it to; it is not applied there.  Undo: `CARDS` and
    `SPREAD` in `131-retry-timer.lua`.
15. **Own written times never go back in file order.**  `write` gives a
    record the time of your last own record when the clock reads earlier
    (a clock stepped back), because the mark ("everything written at or
    before it is acknowledged") would otherwise cover a record nobody
    received.  Undo: costs a mark that is a position in the log instead
    of a time.
16. **A new message wakes a healthy pair at once; a pair waiting out a
    failure keeps its time**, so a pile written while it is away is one
    attempt (R8).  A pair found with nothing missing is "held": not a
    failure, the interval does not move, and it is no longer waiting out a
    failure.
17. **The `due/` entries of step 2 are `Stage:wake` calls.**  Whether a
    wake crosses a process boundary (a file) or stays in memory is 211's
    design.
18. **The referees run in a simulation**: real homes on disk, the real
    modules, and in between a fake clock, cooperative threads for each
    home's stages and an in-memory relay.  Referee 2's broken version is
    a home whose one loop sends (waiting for each answer) and accepts.
    211 brings real sockets; 210's demo runs the same scenes between
    homes on one machine.
19. **Referee 6's tolerance is ± 2 attempts a day**, not ± 1: a day cuts
    the decks at arbitrary cards, and in 3,000 trial runs of the timer 12
    ± 1 held 99.7% of the time, with 10 and 14 in the rest.

### Left for 211

Running the stages (a receiving stage that never waits on the sender
stage), real connections and their timeouts, workers for the trial
opening and for a pass's jobs, and keeping one writer per room's
`delivered` file.  `Stage:pass`, `receive.serve` and `send.attempt` take
these as seams.

## Related documents

- `notes/vision-planning.md` sections 5 ("The one change for chat"), 6 (the
  deck), 15
- `notes/rmail-rubric/delivery-and-retries.md`
- `docs/phase-1-module-contract.md` (103 `send_list`, `heard_from`; 105)
