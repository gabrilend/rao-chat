# 207 — Contact syncing within a room

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 204, 205
**Blocks:** 208, 209, 210

## Current Behavior

Nothing exists.  Phase 1's 103 adds members (`add_member`: already,
ignored, or added — flagged when a child room's parent check fails) and
103a keeps the ignore list.

## Intended Behavior

Owner: "could just, have everyone sync their contacts list whenever they
notice that a new person joined the room. We can't tell when someone left.
Also, we should be able to request that others automatically send their
contacts list to us, in the same way that the RGPL requires people to send
their source-code if requested. Like, if we make a special type of message
and put it in the outbox. In the UI it'll probably be tapping a button or
something, or the user could make it auto-triggered..."

- **When a new member is noticed** in a room, this server tells every pair
  on the room's send list what it holds — first as a **digest**: the
  fingerprint (SHA-256, 32 bytes) of the room's member pairs sorted as
  text `"<address> <port>"`, with the count.  A receiver whose own digest
  differs answers with `members-ask`; only then is the full list sent.
- **Anyone may ask** with `members-ask`; the full `members` list is sent
  back automatically.  In the viewer, a button, or automatic.
- **A received list adds nothing directly.**  Each pair it holds that this
  server does not is **called back** (204) and added only once confirmed —
  through 103, so the ignore refusal and the parent flag apply.
- **Home-network pairs are never in a list** (212's kind), and pairs
  confirmed only from inside the house are left out.
- **Consent**: being in a room is consent to your pairs being passed to its
  members.

## Rubric

- **A write that tells a peer nothing new must not produce a reply; "new"
  is judged by comparing sets, not orderings** (structure R6, addresses
  R10).  rmail's idle daemons, each rewriting an unchanged list, made 1,500
  exchanges and 350 KB of log in 15 seconds.
- **A private address never goes to a peer elsewhere** (addresses R3).
  192.168.x.x names a stranger's device on every other network.
- **A claim about where someone is must be proved before use** (addresses
  R8): a list is a claim by one member about others.
- **Every record is safe to receive twice, late, or replayed by anyone
  who recorded it** (structure R13): a replayed old list must not re-add a
  member whose leave was confirmed (208 keeps the record of that).
- **Anything hashed for comparison is of stable, written fields** (rmail's
  2026-08-03 edge case: `table: 0x…` written into contacts made a hash that
  never settled).

## Where we differ

rmail sends a contact's whole address set at every change.  The formation
here is **digest first, list on demand**: a members message costs 36
bytes when nothing differs, and a mismatch is what triggers the list.  And
**nothing arrives trusted**: every pair from a list is called back before
it is added, which answers the replay risk and the "moves through the
room" recovery at once.

- **Gains:** ping-pong is impossible by construction (equal digests send
  nothing); replayed lists add nothing that is not answering now; a member
  who moved is found through any member who still reaches them.
- **Costs:** two round trips when lists differ; a call-back per new pair
  per receiver (a room of n homes learning one newcomer makes n call-backs
  to it); a flagged-then-approved state and the digest must agree on what
  "held" means (proposed: every pair in the entry, flagged or not).

## Referees

1. **A newcomer reaches everyone.**  Three homes; C joins through A; B
   learns C through A's digest, asks, calls C back, adds C.  *Broken:*
   sending only to the member who was joined through.
2. **Idle is quiet.**  Two homes with identical lists run 10 minutes: no
   `members` frames beyond one digest per notice.  Reordering a list on
   disk sends nothing.  *Broken:* sending on every change-bell ring,
   including rings caused by writing a received list.
3. **Ignored stays out.**  A list naming an ignored pair: not added.
4. **Child room outsider is flagged, not sent to.**
5. **Private pairs stay home.**  A's list to C (elsewhere) holds no
   private-range address; one that arrives anyway is not added.
   *Broken:* the list sent verbatim.
6. **Replay after a leave.**  Record B's list holding D; D leaves (208);
   replay the list: D is not re-added.  *Broken:* adding list pairs on
   receipt.

## Suggested Implementation Steps

1. The digest and the `members` / `members-ask` records (201's table).
2. Sending a digest when a member is added (the change bell's `members`
   ring caused by an arrival, not by a received list).
3. Answering an ask; sending the full list.
4. Receiving a list: call back each new pair, add through 103.
5. The referees above.

## Blockers that are not the owner's

- Needs 204 (call-backs), 205 (joining), and phase 1's 102, 103 and 103a.

## Open questions

1. **Automatic asking**: how often, if the person turns it on?
2. **Private home-network pairs in lists**: never shared (proposed), or
   shared marked with their network and dropped elsewhere?  (Rubric
   question 14.)
3. **A replayed list** (rubric question 8): answered here by calling back
   every pair; with 208's leave record also refusing a confirmed leaver
   until they speak again — confirm both.

## Decisions (2026-11-05)

Made by the builder.  The owner's standing instruction is to answer open
questions rather than wait, choosing the option that is easiest to undo.
The owner can overturn each one; what overturning costs is said with it.
Built in `src/delivery/` (152 members, 153's referees), with three rows
in 126 and small hooks in 133 (the frames), 134 (the jobs and the
notice), 142 (keeping the confirmed claim) and 143 (the simulated homes'
seam).  Every referee runs in the simulated world, each against a
broken version where the issue names one.  The homes run at
documentation addresses (198.51.100.x), because a loopback address is
never shareable and so could never be listed.

1. **Automatic asking** (open question 1): not built.  Asking is
   `Stage:ask_members(tag, pair, now)`, for the viewer's button; nothing
   asks on a timer.  209's cross-check is the periodic exchange, so a
   second timer here would duplicate it.  Undo: a setting with no
   default and a timer that calls `ask_members`; nothing else changes.
2. **Private pairs in lists** (open question 2): never shared, as
   proposed.  A pair is listed only when its address is public IPv4,
   global IPv6 or a hostname (152's `shareable`, from 149's `classify`);
   private, carrier-grade, link-local and loopback addresses are left
   out, and one that arrives in a list anyway is not called back.  The
   check is on the address, not on the kind the sender wrote.  Pairs
   confirmed only from inside the house are 213's to mark; nothing marks
   them yet.  Undo: list home-network pairs marked with their network,
   and drop them at a receiver on another network (213's test).
3. **A replayed list** (open question 3): both confirmed.  Every pair
   from a list is called back before it is added, and a pair with a line
   in the room's `left` file is skipped (208's `may_add_from_list`)
   until it speaks again.  Referee 6 replays a list to a restarted home,
   whose checks are forgotten, so the guard is what keeps the leaver out.
4. **The three records**: `members-digest` and `members-ask` carry `id`,
   `digest` (64 hex) and `count`; `members` carries `id`, `digest`,
   `pairs` (the hello's form) and `claims`, the claim ids line up with
   the pairs, separated by spaces.  All three travel on one connection:
   a digest is answered with an ack naming its id (same digest) or a
   `members-ask` (different); that ask is answered with the `members`
   list, which is acked.  A `members-ask` sent alone is answered with
   an ack (same) or the list.  Undo: the rows are 126's, and 152 is the
   only reader.
5. **Why a list carries claim ids**: a call-back asks the pair "did you
   make claim C?", so the receiver needs a claim that pair made.  When a
   hello's call-back confirms a pair that stays a member, 142 keeps that
   claim in the room's new `vouched` file ("address TAB port TAB claim
   id TAB confirmed").  A list names, for each pair, the claim it
   answered yes to.  A member with no vouched claim is held but not
   listed.  This home's own pairs are listed under a hello claim it
   makes for them, once per run.  Undo: drop the file, and have the
   receiver ask a new kind of question instead; the frames change.
6. **What "held" means** (the issue's proposal): every member of the
   room, flagged or not, plus this mailbox's own shareable pairs (212's
   `own_pairs`), less unshareable ones.  The digest is SHA-256 of
   `"<address> <port>"` lines sorted as text and joined by newlines,
   which are written fields only.  The own pairs are counted so that
   homes that hold each other agree: A holds B and itself, B holds A and
   itself, and both digests are of the same set.  Undo: leave the own
   pairs out and every exchange between two homes would always differ.
7. **When a digest is sent**: when a call-back confirms a hello and that
   adds the pair (103's `added` or `added-flagged`), to every pair on the
   send list, the newcomer included.  That is how a joiner receives the
   list, the second half of 205's referee 1.  A pair added from a
   received list sends nothing, and nothing listens to the change bell,
   so rewriting or reordering the room's entry sends nothing.  A home
   that has left the room sends no digest, and leaving drops its
   pending members jobs.  Undo: a bell listener; referee 2 would catch
   it unless it ignores list adds.
8. **Members jobs run like hellos**: one per (room, pair) in the stage's
   hello table, with the same retry timer, ended by a finished exchange.
   The stage counts its notices (`stage.notices`), which referee 2
   reads.
9. **A stale `vouched` line is harmless**: a pair that leaves keeps its
   line, but it is no longer held, so it is not listed; a later hello
   replaces it.  Undo: 147's `confirm` could drop the line.

## Related documents

- `notes/vision-planning.md` section 3; section 14 ("Answers" 5)
- `notes/rmail-rubric/addresses-and-ports.md` (R3, R8, R10; "Moves through the room")
- `notes/rmail-rubric/structure-and-defences.md` (R6, R13)
