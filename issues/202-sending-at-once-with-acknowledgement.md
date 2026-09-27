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

## Related documents

- `notes/vision-planning.md` sections 5 ("The one change for chat"), 6 (the
  deck), 15
- `notes/rmail-rubric/delivery-and-retries.md`
- `docs/phase-1-module-contract.md` (103 `send_list`, `heard_from`; 105)
