# rmail as a rubric: delivery, acknowledgement and retries

Read 2026-09-26 from `/home/ritz/programs/r-mail` (rmail.lua at its
current tip, 7,257 lines; `rmail_inotify.c`, `rmail_kqueue.c`;
`docs/protocol.md`, `docs/defensive-patterns.md`; issues 104, 204, 324,
374, 377, 386, 387, 389, 396, 397; `git log`).  rmail was read, not run.
Nothing in rmail was changed.

For rao-chat issues **202** (sending at once, with acknowledgement and
retries) and **209** (the periodic cross-check, including "a sender
resends its own messages to a member who lacks them").

Line numbers are `rmail.lua` unless another file is named.

---

## 1. What this area does in rmail

### The pieces of state

- **The outbox folder** (`outbox/`, on disk).  One plain-text file per
  message.  Its `to:` lines name contacts; the rest is the body.  The file
  is the message; nothing else holds its text.
- **The delivery record** (`.state/outbox.json`, on disk, rewritten whole
  at the end of every outbox pass).  A table keyed by outbox file name
  (text).  Each entry holds:
  - `recipients`: a table keyed by contact name (text), each value a table
    with `message_id` (text, a random UUID), and optionally `self`
    (true/false: delivered to our own inbox with no network) and `error`
    (text, for example `body_too_large`).
  - `body_checksum`: text, the SHA-256 of the body as last seen, used to
    notice edits.

  **"Not yet delivered" is an absence**: a contact named on a `to:` line
  who has no entry under `recipients`.  An entry is written only after an
  acknowledgement (5095–5102).
- **The per-contact timers** (`ctimer`, 905–1014, in memory only; lost on
  restart).  A table keyed by contact name (text); each value holds
  `interval` (whole seconds, number) and `next_due` (seconds since 1970,
  fractional number).  Plus three per-cycle sets keyed by contact name:
  `attempted` (true: something was actually put on the wire),
  `skipped` (true: something was held back because the contact was not
  due), and `outcome` (true/false: did any attempt reach them this cycle).
- **The receiver's filing record** (`.state/inbox.json`).  A table keyed by
  inbox file name (text); each value holds `from` (the contact name the
  key identified, text) and `message_id` (text).

### How a new message is noticed

The daemon asks the kernel to wake it when anything in `outbox/` or the
`contacts` file changes: inotify on Linux (`rmail_inotify.c`, opened
non-blocking), kqueue on BSD/macOS (`rmail_kqueue.c`).  Which one loads is
decided once at startup, with no polling fallback: a machine with neither
refuses to start (330–359).  The notice's contents are never read — it is
a doorbell.  Reading it sets one yes/no flag, "go and look at the outbox"
(7114–7123); the look itself re-reads the whole folder.

### The main loop: one thread, one wait

`main` (7035–7255) is a single thread built around one `select()` call,
which waits on the listening sockets, the two change doorbells, and every
open incoming connection.  It sleeps until the earliest of: a socket is
ready, a doorbell rings, the earliest contact timer comes due, the address
re-check comes due, or three seconds pass (7066–7087).

- **Incoming connections** each run in a coroutine (a function that can
  pause mid-way and be resumed): a wrapped socket that, instead of
  blocking, pauses the coroutine and hands control back to the loop
  (`make_async_socket`, 6960–7025).  Many incoming connections interleave
  this way.  Only one runs at any instant.
- **The sync cycle runs inline, not as a coroutine** (comment at 7032).
  When the doorbell rang or any timer is due (7218), the loop calls
  `run_sync_cycle` (6556) and does nothing else until it returns — it does
  not accept, read or answer anything meanwhile.  Issue 104 planned the
  sync as a coroutine; it was built inline "to keep state management
  simple".

### Sending

`run_sync_cycle` runs seven builders in a fixed order; the first is the
outbox builder (`sync_outbox`, 4494–5199), in three phases:

1. **Plan** (4555–4865).  For each outbox file and each `to:` contact with
   no record: plan a `deliver` operation carrying a **freshly drawn
   message id** (`message_id = uuid()`, 4703), the body, and the file's
   modification time.  For recorded recipients whose body checksum
   changed: plan an `update` carrying the recorded id.  For removed
   recipients and deleted files: plan removal/deletion notices.
2. **Build and send** (4870–5063).  Every planned operation becomes one
   sealed request.  They all go to `http_post_batch_with_fallback`
   (3087–3155), **the one gate every outbound request passes**: a request
   for a contact whose timer is not due is held back and reported to its
   builder as an ordinary failure, flagged `skipped` (3098–3100).  The rest
   go out together (`http_post_batch`, 2909–3006): every connection opened
   non-blocking at once, then one `select()` loop over only *these*
   sockets, with an **8-second deadline for the whole batch** (2941).  A
   request whose first address got no answer at all is then tried at the
   contact's other addresses **one at a time**, each with its own 8-second
   batch (3008–3085); the address that answers is moved to the front of
   the contact's list.
3. **Record** (5070–5140).  A `deliver` that came back acknowledged writes
   the recipient's record.  Anything else writes nothing, so the next
   cycle plans it again.

### The acknowledgement

A request is a sealed frame (length, nonce, sealed text, check value)
holding an HTTP-shaped request.  The receiver answers **on the same
connection** with a sealed HTTP-shaped response, sealed with the same key
(6546).  "Delivered" means the response opened, and its status line said
200 (2880–2903).  A status of 404 means "already done on my end" and counts
as reaching the contact (5079).  A response that never arrives, or does
not open, is "no answer".  The response does not name the message it
acknowledges; the connection is the binding.

The receiver (`handle_deliver_message`, 2165–2256) writes the inbox file
(2238), then its filing record, and only then sends the response.  A
repeat of an id it already holds *from the same contact* is answered 200
without filing again (2173–2179).

### Timers and backoff

Per contact (issue 377, built 2026-09-22):

- A contact never yet reached is **due at once**; so at startup everyone
  is due (949–957).
- **Success**: interval back to the floor, 30 s; next due 30 s ± 30 s
  later (964–968).
- **Failure**: interval grows by **adding 360 s**, capped at **7,200 s (2
  hours)**; next due one interval ± 30 s later (970–986).  So after one
  failure the next try is about 6½ minutes away, not 30 seconds; the
  ceiling is reached after 20 failures, about 19 hours of outage.  There is
  no limit on attempts and no expiry: nothing is ever dropped.
- The jitter is drawn from `/dev/urandom`, not the language's seeded
  generator, so failed contacts drift apart instead of retrying in step
  (942–946).
- **Timers move once per contact per cycle, not once per operation**, at
  the end of the cycle (6573–6602).  A contact reached by any operation
  counts as reached.
- **A contact due but with nothing to send** goes back to the floor with
  no network traffic (6604–6612).
- **Hearing from a contact** — any frame that opens with their key — sets
  their interval to the floor and makes them due *now* (988–994, called at
  6370, after decryption so a forged packet resets nothing).  This is what
  makes two talking daemons feel like push.

### The consequence for "sent at once"

The doorbell starts a sync at once, but the gate still holds back any
contact not yet due.  A healthy contact was reached within the last ~30 s
and is due again within ~0–60 s, so a new message usually waits up to about
a minute; a backed-off contact's new message waits for its timer (up to 2
hours) unless they speak first.  This is the behaviour rao-chat's
planning section 5 ("The one change for chat") replaces.

### Parallelism

None at the operating-system level: one thread, one process per mailbox.
Outgoing requests within one batch overlap (non-blocking sockets and one
`select()`); incoming connections overlap with each other (coroutines).
Outgoing and incoming **never overlap**, because the sync is inline.
Issue 387 considered threads and set them aside (2026-09-22): "threading
would add locking around the state files and the contacts file".

---

## 2. RULES

Each rule: what must hold · why (the mechanism) · where rmail shows it ·
for rao-chat.

### R1. The id of a message is fixed when it is written, and every resend carries the same id.

- **Why.**  Delivery over a network can succeed at the far end while the
  answer is lost (the connection drops after filing, the sender's wait
  ends first).  The sender then cannot tell "not delivered" from
  "delivered, answer lost", so it must resend; only a stable id lets the
  receiver recognise the second copy.  A new id per attempt turns every
  lost answer into a second message.
- **rmail.**  Violated: `message_id = uuid()` is drawn each time a
  `deliver` is *planned* (4703), and a delivery that got no answer is
  planned again next cycle.  The receiver's repeat check (2175) is correct
  but never sees a repeat.  This is the eight-copies bug (section 4, E1).
- **rao-chat.**  Applies unchanged.  105 already makes the id part of the
  log record, so the id exists before any sending; 202 must send that id,
  and 209's gap-filling resend must send the same id again, never a new
  one.

### R2. A repeat of a message already filed is acknowledged, not refused.

- **Why.**  R1's resend only stops if the answer to it says "delivered".
  A receiver that answers a repeat with an error, or with silence, leaves
  the sender retrying forever.
- **rmail.**  A repeat from the same contact is answered 200 (2173–2179);
  a 404 on an update or deletion counts as reached (5079, 5265, and the
  comment at 3115–3117: "a 404 ... is a reachable contact, not a dead
  one").
- **rao-chat.**  Applies; 105 already answers a repeat `duplicate`.  The
  sender must treat `duplicate` as delivered.  Changed in one way: in
  rao-chat a repeat may come from *another* address (105: "duplicate,
  whatever address it came from"), and must still be acknowledged.

### R3. File first, then acknowledge.

- **Why.**  An acknowledgement is a promise the sender acts on by
  forgetting the message for that address.  If the receiver acknowledges
  and then fails to file (crash, full disk, power loss), the message is
  lost with no one holding it as "not yet delivered".
- **rmail.**  File, record, then answer (2238–2255, response at 6546).
  The write is a plain close with no flush-to-disk call, so a power cut in
  the next few seconds could still lose an acknowledged message; not seen
  in any issue.
- **rao-chat.**  Applies unchanged.  Whether the log append is forced to
  disk before acknowledging is a choice (C9).

### R4. "Delivered" moves forward only on an acknowledgement — for every kind of change, not only new messages.

- **Why.**  Any state that records "this change has reached them" and is
  written before the answer comes back will, on a failure, believe the
  change arrived and never send it again.
- **rmail.**  New messages obey it (5095–5102).  Edits do not: the new
  body checksum is stored while the update is being planned (4853),
  before anything is sent, so an edit made while the contact is not due,
  or unreachable, is silently never sent (section 4, E3).
- **rao-chat.**  Applies; mostly satisfied by construction, because an
  edit is its own message with its own id (planning section 3, "Edits")
  and so rides the same queue.  Anything else that tracks "sent" (member
  lists 207, leave notices 208, hellos 205) must also advance only on
  acknowledgement.

### R5. An acknowledgement must be authenticated, and bound to what it acknowledges.

- **Why.**  Anyone on the path can inject a TCP reset or a forged reply.
  If an unauthenticated "ok" counted, an attacker could make a sender drop
  messages it believes delivered.  And if acknowledgements are not bound to
  a particular message (by the connection, or by naming the id), an old
  one replayed could acknowledge a new message.
- **rmail.**  The response is sealed with the contact's key and must open
  (2880–2903); the binding is the single request-response connection with
  `Connection: close`.
- **rao-chat.**  Changed.  A room key is held by every member, so any
  member on the path can forge a sealed "ok" for another member's address.
  An acknowledgement should name the message id(s) it covers; whether it
  must also prove *which* member sent it cannot be done under the room key
  alone (planning section 1: "the sender of a message is unknowable by
  design") — open question 5.

### R6. Receiving must never wait on sending.

- **Why.**  Two servers that each send to the other and, while waiting for
  their answer, do not answer anyone, each wait for the other: both hit
  their timeout, both record failure, both deliveries were in fact filed
  (the kernel accepted the connection and buffered the bytes into the
  listen backlog; the frame is read and filed once the loop comes back).
  With R1 violated this becomes duplicates; with R1 honoured it is still a
  wasted timeout and a needless backoff step for a healthy peer.
- **rmail.**  Violated by construction: the sync is inline in the one
  thread (7032, 7225), so outgoing waits of up to 8 s per batch (2941),
  plus 8 s per fallback address (3024–3027, one single-request batch each), block every incoming connection.
  Issues 374 ("both sit out an 8-second timeout") and 387 (a dead contact
  used 94 % of every cycle; the phone's uploads waited behind it).
- **rao-chat.**  Applies, and harder: in a room of many members, several
  servers sending at once to each other is the ordinary case, not an edge
  case.  The owner's "single-threaded messaging core engine" (202) must not
  mean "one thread that both sends and waits".

### R7. Backoff state belongs to each destination, and only a real attempt moves it.

- **Why.**  One shared interval for many destinations means a lively one
  holds everyone at the fast rate and a dead one drags everyone slow.  A
  held-back attempt ("not due yet") says nothing about reachability; if it
  counted as a failure, backoff would feed itself.
- **rmail.**  Per contact since 377; held-back requests are marked
  `skipped` and excluded from both the timer and the "unreachable" summary
  (1023–1042, 3098–3100, 3137–3148).
- **rao-chat.**  Changed: per **address** (an (address, port) pair), as
  202 says, since each pair is a recipient.

### R8. One failed attempt to a destination is one failure, however many messages are waiting for it.

- **Why.**  If each waiting message counts as its own failure, a
  destination with a pile backs off in proportion to the pile, not to its
  unreachability.
- **rmail.**  Fixed 2026-09-22 (commit 2ed6129): applying per operation
  took one contact from 30 s to 36 minutes in a single cycle (comment at
  3120–3128).  Now the outcome is recorded and applied once per contact per
  cycle (6573–6602).
- **rao-chat.**  Applies unchanged — more so, since a room can pile up many
  messages for one away member (202, owner: "letting the messages pile
  up ... is fine probably").

### R9. The timer moves even when the work around it fails.

- **Why.**  If the step that advances "next due" is skipped when anything
  earlier in the cycle throws an error, every due destination stays due,
  the wait until next cycle computes to zero, and the loop spins at full
  speed repeating the same error.
- **rmail.**  Violated until issue 397's design; seen 2026-09-22 → 23:
  1,091,617 identical error lines, 200 MB of log, all outbound mail from
  that mailbox stopped (issue 397).  The fix (design, partly built) runs the
  bookkeeping as the last part of every pass, even after a code error.
- **rao-chat.**  Applies unchanged.

### R10. A change notice is a hint to look, never the record of what changed.

- **Why.**  Kernel change queues can overflow, can be read in partial
  batches (`rmail_inotify.c` reads one 4,096-byte buffer per call), and are
  discarded by any code that drains them to ignore its own writes.  The
  kqueue form does not even say which file changed.  Only re-reading the
  folder (or log) is complete.
- **rmail.**  The notice only sets a flag (7116–7118; the kqueue module's
  header, `rmail_kqueue.c` 33–46).  But the end-of-cycle drain (7238)
  cannot tell its own writes from a person's, so a save made during a sync
  waits for a timer (issue 396, absorbed into 397).
- **rao-chat.**  Probably does not apply as-is: messages reach the home
  server from its own clients over their connection (planning section 6),
  so the server writes the log itself and knows the moment it does.  It
  applies only if a message written into a room's `log` by hand (with a
  shell, `cat >>`) is meant to be sent — open question 3.

### R11. Every destination is eventually tried again, and nothing is dropped silently.

- **Why.**  An address can be away for weeks (asleep, moved, off) and come
  back.  A retry limit or expiry drops messages nobody chose to drop.
- **rmail.**  "There is deliberately no TTL: a permanently-failing op is
  backed off, never dropped" (900–902; issue 377, "No TTL").  The cost is
  shown by `aurelia`: an address superseded in May was dialled ~5,700
  times a day until September; at the 2-hour ceiling it is ~12 a day.
- **rao-chat.**  Applies (202: "never giving up").  Changed in scale: a
  move "adds the new address beside the old" (planning section 3), so dead
  addresses accumulate by design and each keeps a growing pile.

### R12. Partial writes must be completed, and lengths bounded before reading.

- **Why.**  A non-blocking send hands the kernel only what fits in its
  buffer; the rest must be sent in a loop or the frame arrives truncated,
  fails to open, and looks like "no answer".  A length prefix from the
  network must be checked before the bytes are awaited, or one frame can
  demand gigabytes.
- **rmail.**  Truncated large frames were issue 204 (fixed, recorded
  2026-03-27); the loop is at 2861–2877.  The receiver refuses a length
  under 28 or over 64 MB (6341–6342, and 2737–2738).
- **rao-chat.**  Applies unchanged; chat frames are small, so the bound can
  be far tighter.

---

## 3. CHOICES

Each: rmail's value · what it traded · whether rao-chat's owner has
already decided otherwise.

| # | choice | rmail's value | what it traded | rao-chat |
|---|---|---|---|---|
| C1 | When a new message leaves | at the next due time of that contact (≈0–60 s healthy; up to 2 h backed off), even though noticed at once | fewer connections, packets that look like a regular poll (`docs/defensive-patterns.md`, "Timing jitter"), against latency | **Decided differently**: "immediately to every reachable recipient; the timer governs only retries" (planning section 5, "The one change for chat"; 202). |
| C2 | Floor | 30 s (908) | frequent polling when healthy | 202 keeps "30 seconds, then longer". What "30 s floor" means when sends are immediate is open (question 4). |
| C3 | Growth | add 360 s per failed cycle (910) | 20 steps to the ceiling (~19 h), spends long in the middle; issue 377 considered doubling and kept adding | Not decided. |
| C4 | Ceiling | 2 h (909) | ~12 tries a day to a dead address | 202 keeps "up to 2 hours". |
| C5 | Jitter | ± 30 s uniform, `/dev/urandom` (911, 942–946) | simple; averages right only over many draws | rao-chat's phone already uses a **deck dealt without replacement** whose cards sum to zero (planning section 6); a candidate here too (formation F3). |
| C6 | Expiry | none (900–902) | dead addresses forever | 202: "never giving up" — same. |
| C7 | Timers survive restart? | no; in memory, everyone due at startup (issue 377, "Persistence") | a restart re-dials every dead contact once | Not decided. |
| C8 | Where "not yet delivered" lives | absence of a recipient entry in `.state/outbox.json`, beside an outbox *file* | two things to keep in step (file and record) | rao-chat has no outbox folder; the log holds every message (105). See formations. |
| C9 | Flush to disk before acknowledging | no | speed, against losing an acknowledged message on power loss | Not decided. |
| C10 | Batch deadline | 8 s for all first attempts together (2941); fallbacks 8 s each, one at a time | a single slow receiver adds 8 s; three dead fallback addresses add 24 s | Not decided. |
| C11 | Several addresses for one destination | tried in order, first in parallel, others one by one; the one that answers moves to the front and gets the message | one copy per person | **Conflict in rao-chat's own documents**: section 15 (owner: "each contact could have several IPs, and we'd deliver to all of them. Each of these IP/port combinations ... would be a recipient") against 202 ("a second address for a member is tried beside the first; the one that answers moves to the front, as in rmail").  Open question 1. |
| C12 | Who resets a backed-off destination | any frame that opens with that contact's key (988–994, 6370) | nothing else can | rao-chat cannot map an arriving frame to a member (the source port of a connection is not the listening port, and the sender is unknowable by design). Open question 2. |
| C13 | Threads | one; incoming coroutines; outgoing fan-out in one `select()` | no locking; head-of-line blocking (R6) | The owner prefers **multithreading where work can be split** (planning, section 14 answers, question 3: "we make the decoding multithreaded"; 201), and also calls the core "single-threaded" (202). Open question 6. |
| C14 | Acknowledgement format | HTTP-shaped status inside the sealed reply, one per connection, id not named | simple; one connection per message | Not decided; see R5. |
| C15 | Connection per request | yes, `Connection: close` (2848) on the sending side, though the receiver accepts several per connection (6319–6546) | a new TCP handshake per message | Not decided; a pile for one address is naturally one connection. |
| C16 | Unreachable report | one log line per cycle naming everyone who failed every attempt (1023–1042); 397 adds a report file per contact | quiet logs | 202 raises nothing yet; the owner treats silent fallbacks as errors, and a pile growing forever is worth showing. |

---

## 4. EDGE CASES ALREADY HIT

**E1. Two daemons dialling each other filed one message eight times
(found 2026-09-23, recorded in issue 374, "Found while verifying"; not
fixed in rmail as of this reading).**  A and B each started a sync and each
dialled the other.  Neither answered, because neither was in its loop
(R6).  Both waited out 8 s.  A's frame was in B's listen backlog; when B's
sync ended it read, filed, and answered a closed connection.  A recorded a
failure and next cycle drew a **new** id (R1), so B filed it again under a
new name (`letter-64adf3`, `letter-22aade`, ...): eight copies in three
minutes.  Teaches R1 and R6 together: either alone would have prevented
the duplicates; R6 alone also prevents the wasted timeouts.

**E2. A dead contact dialled ~5,700 times a day for four months (found
2026-09-21, issue 377; fixed 2026-09-22).**  One global interval, no
per-contact backoff, and a failed op counted as an idle cycle.  Teaches
R7 and R11: back off per destination, never drop.

**E3. Backoff multiplied by the pile (fixed 2026-09-22, commit 2ed6129).**
Applying one failure per queued operation took a contact from 30 s to 36
minutes in one cycle.  Also: a success applied immediately pushed the
contact's due time forward, so the gate then held back that contact's
*other* operations later in the same cycle.  Teaches R8, and that the
decision "due or not" should be made once per destination per round.

**E4. An edit made while the contact is not due is lost (found 2026-09-23,
issue 374; not fixed as of this reading).**  The edit's "already sent"
checksum is stored during planning (4853).  Teaches R4.

**E5. One bad record spun the whole daemon (2026-09-22 → 23, issue 397).**
An error thrown mid-sync skipped the timer bookkeeping; every contact
stayed due; 1,091,617 identical lines.  Teaches R9.

**E6. A slow or dead contact stalled every incoming request (observed
2026-09-22, issue 387, open).**  Two 8 s stalls per cycle; 94 % of every
cycle spent waiting on a host gone for four months; the phone's uploads
pinned to cycle boundaries, then its 30 s read timeout (issue 386).
Teaches R6.

**E7. A message saved during a sync waited for a timer (issue 396,
answered 2026-09-23, built in 397's design).**  The drain that throws away
the daemon's own change notices threw away a person's too.  Teaches R10.

**E8. Large frames truncated on non-blocking sockets (issue 204, closed by
2026-03-27).**  Looked like "no answer" forever.  Teaches R12.

**E9. A mailbox with no contacts never synced (fixed 2026-09-22, issue 377
follow-up).**  With only per-destination timers, nothing could come due.
Teaches: when timers are per destination, "is there anything to do at all"
needs its own wake-up.  In rao-chat, a room with no one on its send list
(everyone withheld or flagged) is the same shape.

**Stale documentation, noted in passing:** `docs/protocol.md`, "Sync
timing", still describes the old single adaptive interval (starts at 5
minutes, shrinks with work); the per-contact timers replaced it.

---

## 5. REFEREE TESTS

Written from the rules above, not from rmail's code or rao-chat's.  Each
is to be run on two or more home servers on one machine (202 step 6), with
a fault-injecting relay between them where a test says so.  For each, a
deliberately broken version the test must fail.

| # | test | passes when | broken version it must catch |
|---|---|---|---|
| T1 (R1, R2) | **Lost answer.**  The relay forwards A's frame to B, then drops B's reply.  Let A retry. | B's room holds the message exactly once; A's second attempt is answered `duplicate`; A then marks it delivered and sends no third attempt. | A sender that draws a new id for each attempt (B files two). A receiver that answers a repeat with an error (A never stops). |
| T2 (R6) | **Mutual send.**  A and B each have a new message for the other at the same instant; the relay adds 2 s of delay to every packet. | Both messages delivered and acknowledged on the first attempt; neither address backs off; no attempt takes longer than the injected delay plus a small margin. | A server whose sending blocks its listening (wait on the reply before returning to accept): both time out. |
| T3 (R6) | **Dead peer does not delay a live one.**  A room with C (black-holed: packets dropped, no refusal) and B (healthy).  A writes a message. | B has it within a small bound (e.g. under 1 s on one machine), however long the timeout for C is. A client connected to A is answered meanwhile. | Sending to members one after another, waiting out each; or waiting for the whole batch before answering clients. |
| T4 (R3) | **Crash between filing and answering.**  Kill B right after it acknowledges; restart. | The message is in B's log. | A receiver that answers before appending (kill it after the answer: the log lacks it). |
| T5 (R4) | **Edit while away.**  B is down.  A writes a message and an edit of it.  B comes back. | B holds both the message and the edit. | A sender that marks the edit as sent at planning time. |
| T6 (R7) | **Held back is not failed.**  B is reachable; A is made to consider B not due (or has nothing for B) for several rounds. | B's interval stays at the floor. | A gate that counts a held-back attempt as a failure. |
| T7 (R8) | **Pile of fifty.**  B is down; A writes 50 messages in one round. | B's interval after that round equals the interval after one message. | Backoff applied per message. |
| T8 (R9) | **Throwing record.**  Plant a record that makes one send throw. | The loop keeps its ordinary cadence (count wake-ups over 60 s); other members still receive; one error entry per round. | Bookkeeping placed after the work with no guard: the loop spins. |
| T9 (R11) | **Long absence.**  B down for a simulated 72 hours (fake clock), then up. | Every message A wrote meanwhile reaches B; attempts per day at the ceiling ≈ 24 h ÷ ceiling. | A retry cap or expiry; or an interval that stops growing below the ceiling. |
| T10 (R5) | **Forged answer.**  The relay drops B's reply and sends A an "ok" sealed with a *different* room's key, then one sealed correctly but naming another message id. | A still counts the message undelivered in both cases. | A sender that treats any reply on the connection as success; or one that does not check which id is acknowledged. |
| T11 (R12) | **Slow reader.**  The relay passes bytes to B at 1 byte per millisecond for a frame larger than the socket buffer. | Delivered intact. | A single non-looping send. |
| T12 (R12) | **Huge length.**  Send B a frame header announcing 2 GB. | B closes the connection without waiting for or reserving that much memory; B's other connections are unaffected. | A receiver that reads the announced length unconditionally. |
| T13 (209 + R1) | **Gap filling uses the old id.**  A's message to B is removed from B's log by hand; the next cross-check runs. | A resends with the original id; B files it once; running the cross-check again sends nothing. | A gap-filler that rewrites the message as new (second id): the next cross-check shows a new gap forever, or B holds two. |
| T14 (209) | **Gap filling respects choices.**  Same as T13, but B is withheld (or ignored, 103a) on A, or the gap is someone else's message. | Nothing is resent. | A gap-filler that resends everything missing. |

---

## 6. A DIFFERENT FORMATION

Three shapes that meet the rules without copying rmail's.

### F1. The log is the outbox; each address keeps a "received up to" mark. *(my leaning, combined with F2)*

There is no separate queue.  The room's log already holds every message,
with its id and written time, and marks which are the server's own (`me`,
planning section 4).  Beside the room, one small file per address on the
send list records what that address has acknowledged: **a written-time
mark** (whole seconds since 1970: every own message at or before it is
acknowledged) **plus a short list of ids** acknowledged after the mark.
"Not yet delivered to X" is computed: own messages in the log, after X's
mark, not in X's list.  An acknowledgement moves the mark forward whenever
the list closes a gap.

- **Gains.**  R1 and R4 hold by construction (the only thing sent is a log
  record, with its log id; an edit is a log record).  209's gap-filling
  resend and 202's retry become the *same* operation — "send what X is
  missing" — fed either by the local mark (retry) or by X's summary
  (cross-check).  A pile costs no storage beyond the log.  Nothing to keep
  in step between an outbox and a record (rmail's E7 and the outbox-cleanup
  cases in 5182–5199 have no counterpart).
- **Costs.**  Computing "what is X missing" means reading the log from the
  mark; an index or keeping the tail in memory is needed for large rooms.
  A new member's mark starts at "joined now" or "nothing" (a policy: open
  question 7).  Withholding and un-withholding must say what happens to
  messages written while withheld (sent later, or never).

### F2. Listening and sending as separate workers, sending split per address.

One thread only receives: accepts, trial-opens (itself split across threads
by key, as 201 already plans), files, acknowledges.  A pool of sender
threads takes "address X has something due" jobs from a queue; each job
opens one connection to X and sends X's whole backlog on it, one
acknowledgement per message id.  The timers are one table keyed by address,
read by a single scheduler that feeds the pool.

- **Gains.**  R6 by construction: no sender ever blocks receiving.  A dead
  address holds one sender thread for one timeout, not the round.  Matches
  the owner's multithreading preference where the work genuinely splits
  (one address per job).  A backlog goes in one connection, which is also
  R8's "one attempt, one failure".
- **Costs.**  The log gains writers on several threads (receiving files
  others' messages; clients add one's own); an append-only log with one
  appending thread and others only reading keeps the locking to one queue.
  More moving parts to test than rmail's single loop; T2 and T3 are the
  proof it works.  The "single-threaded messaging core engine" the owner
  named in 202 becomes "a single-threaded filer" — open question 6.

### F3. Backoff drawn from a deck, and reset by rooms rather than by senders.

Instead of adding 360 s with ± 30 s noise, each address's wait is its
current interval plus a card dealt from a shuffled deck without
replacement whose cards sum to zero — the same device the phone uses for
its locked-screen check-ins (planning section 6).  The interval doubles
(30 s, 1 min, 2 min ... capped at 2 h: eight steps instead of twenty).  And
since a frame cannot say which member sent it, "hearing from someone" is
replaced by "hearing *in this room* from this IP address": any frame that
opens with the room's key and arrives from an IP matching one of the room's
addresses makes every address on that IP due now.

- **Gains.**  Waits average exactly the interval over each deck; less time
  spent in the "slow but not yet at ceiling" middle; one mechanism shared
  with the phone.  Works with the unknowable sender.
- **Costs.**  Doubling retries a flapping address less often than rmail's
  additive growth; the IP match can wake several members behind one home
  router or VPN exit (harmless: one extra attempt each).

### F4 (contrast, not recommended). Keep rmail's shape: poll on a timer, send new messages at the next tick.

Listed to show the trade: it is simpler and hides timing better
(`docs/defensive-patterns.md`), and it is what the owner has already ruled
out for chat (C1).

---

## 7. OPEN QUESTIONS FOR THE OWNER

Most blocking first.

1. **A member with two addresses: send to both, or to the first that
   answers?**  Section 15 says every (address, port) pair is a recipient and
   all are delivered to; 202 says the second is "tried beside the first; the
   one that answers moves to the front, as in rmail."  These give different
   send lists, different piles, and a different meaning of "a move adds the
   new address beside the old".  (In rao-chat there is no "member" above the
   address unless one is added: the room entry lists pairs.)
2. **What resets a backed-off address?**  rmail resets a contact when a
   frame opens with their key.  In rao-chat a frame opens with the room's
   key and arrives from an IP and an ephemeral port that is not the
   listening port.  Match on the IP alone (F3), wait for a hello (205) or
   other frame that names the listening port, or never reset early?
3. **Is writing a line into a room's `log` by hand a way to send?**  If
   not, the server sends at the moment it files its own message and no
   file watcher is needed (R10 does not apply).  If yes, the watcher and its
   "notice is only a hint" rule come back.
4. **What the 30 s floor means once sends are immediate.**  In rmail it is
   the healthy polling rate.  In rao-chat nothing is polled (209's summaries
   have their own timer, no default).  Is 30 s the first retry after a
   failure (then longer), or is there no timer at all for a healthy address?
5. **Forged acknowledgements from other members.**  Under a shared room key,
   any member on the network path can forge an "ok" for another member's
   delivery (R5).  Accept that (it is betrayal, which planning section 1
   puts outside what rao-chat defends against), or ask 204's call-back check
   to confirm deliveries in some cases?
6. **"Single-threaded core" versus "multithreaded where it splits."**  Is
   the single thread the owner named in 202 a requirement (one thread files
   and sends), or a description of rmail to be measured against?  R6 forbids
   the one thread from waiting on a send; F2 keeps one filing thread and
   splits sending.
7. **A new member's backlog.**  When an address joins (205), does it get the
   room's past own messages (so the gap-filling resend in 209 would send
   them anyway at the next summary), or only messages written after it
   joined?  Same question for an address un-withheld after a while.
8. **Showing a growing pile.**  An address that has not acknowledged for a
   long time holds an ever-longer pile.  Is that shown to the person (a
   count beside the member), and at what size does "strains the engine"
   (202, open question 2) start — messages per address, total bytes, or
   time since last acknowledgement?
9. **Flush to disk before acknowledging** (C9): worth a slower
   acknowledgement to rule out losing an acknowledged message on power
   loss?
10. **Timers across restarts** (C7): keep each address's interval on disk so
    a restart does not re-dial every dead address at once, or start everyone
    due as rmail does?
