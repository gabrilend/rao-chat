# 208 — Leaving a room

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 204, 207
**Blocks:** 210

## Current Behavior

Nothing exists.  Phase 1's 103 offers the only removal, `confirm_leave`
(removes the pair from the entry, keeps any withheld line, deletes any
flag line), for this issue to call after the call-back.

## Intended Behavior

Owner: "the moment we know that the person has left the room. We should add
messages that do so."  And: "the address will send to everyone and say
"hello I'm not in this room anymore" and if they receive more messages from
them, they get re-added of course because that's how it works in general
right?"

- **Leaving sends a `leave` record** (with a claim id, 204) to every pair on
  the room's send list.
- **A receiver confirms it** by asking the leaving pair "did you make claim
  C?" (204) before removing it (103's `confirm_leave`).  A forged leave is
  not confirmed and changes nothing.
- **A confirmed leave is remembered**: a line in the room's `left` file —
  address (text), port (integer), when confirmed (integer seconds), claim id
  (32 hex).  A members list (207) naming a remembered pair does not re-add
  it.
- **Speaking again re-adds** the pair, as any genuine message does, and
  clears its `left` line — the leaver's own new message or hello is the only
  thing that undoes a leave.
- **What was not yet delivered** to the leaving pair is dropped: its line
  in the room's `delivered` file (202) is removed.

## Rubric

- **A leave notice is a claim, proved in the direction in doubt** (addresses
  R8): only the leaving pair itself can say yes.
- **Every effect of a frame is safe if the frame is replayed later, by
  anyone who recorded it** (structure R13): a replayed old `members` list
  must not undo a confirmed leave.  A replayed `leave` is harder: its
  claim really was made, so the call-back answers yes even after the
  leaver has come back (open question 1).
- **"Delivered" state moves item by item** (structure R21): dropping the
  leaver's pending messages is one line, not a rewrite of every message.

## Where we differ

rmail has no leaving; a contact is removed by editing a file.  The
formation here is **the tombstone**: a confirmed leave leaves a small
record behind, and only the leaver's own newer speech removes it.

- **Gains:** replayed lists are harmless without calling back a pair
  already known to have left; the person can see who left and when.
- **Costs:** one more file per room; ordering "newer than the leave" relies
  on the written time the leaver's server stamps, which a malicious member
  could set — acceptable under the threat model (betrayal by a member is
  outside it).

## Referees

1. **A genuine leave removes.**  A leaves; B calls back, A says yes, B
   removes A and writes `left`.
2. **A forged leave does not.**  C sends a leave naming A's pair: A says
   no; nothing changes.  *Broken:* removing on receipt.
3. **Speaking again re-adds.**  A writes a new message after leaving: B
   files it, adds A back, clears `left`.
4. **A replayed list does not re-add.**  Record a list holding A before the
   leave; replay it after: A stays out.  *Broken:* a leave with no record.
5. **Pending is dropped.**  Messages undelivered to A at the leave are not
   sent afterwards.

## Suggested Implementation Steps

1. The `leave` record and sending it; the claim written (204).
2. Receiving: call back, then `confirm_leave`, then the `left` line and the
   `delivered` line removed.
3. The `left` check in 207's receiving path; clearing it on new speech.
4. The referees above.

## Blockers that are not the owner's

- Needs 204 (confirming), 207 (lists to guard), 202 (`delivered`).

## Open questions

1. **A replayed leave after the leaver returned**: a recorded old `leave`,
   replayed, is answered `yes` (the claim was really made).  Proposed: a
   leave older than the pair's latest filed message is ignored.  Confirm.
2. **Leaving a parent**: phase 1 flags the leaver in its children (nothing
   removes them).  Should leaving a parent offer to leave its children too?

## Decisions (2026-11-05)

Made by the builder.  The owner's standing instruction is to answer open
questions rather than wait, choosing the option that is easiest to undo.
The owner can overturn each one; what overturning costs is said with it.
Built in `src/delivery/` (147 leaving, 148's referees), the `leave` row
of `src/sealing/126-inner-records.lua`, `drop` in 130, leave jobs in
134's stage, the leave action in 142, and the rejoining path in 133.
207 (members lists) is not built: 147's `may_add_from_list` is the guard
it must call, and referee 4 replays a list through a stand-in receiver
that calls it.

1. **A replayed leave after the leaver returned** (open question 1): the
   proposal, as built.  A leave whose written time is older than the
   newest message filed from that pair is ignored: no call-back, nothing
   removed (referee 6).  Undo: one comparison in 147's `receive`.
2. **Leaving a parent** (open question 2): it does not offer to leave the
   children, for now.  Phase 1 already flags the leaver in each child
   room, and a person who wants out of a child leaves it too.  Undo: the
   viewer offers it when 211's viewer exists; nothing here changes.
3. **The `leave` record**: `claim`, `written` (the leaver's own clock),
   and `pairs` in the hello's form, all of this mailbox's pairs from
   212's `own_pairs` seam, with `home-network` pairs only to housemates,
   as for a hello.  Each stated pair that is a member is called back on
   its own.
4. **The `left` line has a fifth field**, the leave's written time, after
   the four the issue lists.  "Newer than the leave" then compares the
   leaver's own written times, as the issue's Costs describe, and never
   this home's confirmation time against the leaver's clock.  Undo: drop
   the field and compare with `confirmed`, accepting clock skew.
5. **The leaver keeps the room.**  Its `claims` file must keep answering
   `did-you` until every member has called back, so leaving deletes
   nothing.  A `left-by-me` file holds the leave's written time; while it
   is there the room gets no start-up hellos, because a hello would undo
   the leave.  Writing in the room again removes it (speaking again).
   The leaver's own members are not changed.  Removing the room from the
   person's view is the viewer's (211).
6. **Leaving drops the room's pending hellos** and sends one leave job
   per send-list pair, resent until an ack names its claim (the hello's
   machinery, 145's `attempt`).
7. **Speaking again re-adds by address.**  133 finds a message's sender
   among the members by address.  When no member is at that address and
   exactly one pair in `left` is, the message is from that pair.  If it
   was written after the leave, the pair is re-added (103's `heard_from`)
   and its line cleared.  An older message, delivered late, is filed and
   re-adds nobody.
8. **A confirmed hello also undoes a leave**: 142's hello action clears
   the pair's `left` line once the pair is a member again.
9. **Deliveries wait while a leave is checked.**  The leave frame makes
   the pair due at once (202's decision 1), and a delivery run before the
   confirmation would send what the leave drops.  So a pair with a leave
   check not yet settled gets no delivery attempt until it settles.  A
   forged leave delays a pair's deliveries by one call-back.
10. **A confirmed leave for a pair no longer a member** still writes the
    `left` line and drops the `delivered` line, and gives "recorded"
    instead of calling 103's `confirm_leave`, which would error.

## Related documents

- `notes/vision-planning.md` section 3 ("Leaving"); section 14 ("Answers"
  3, 9; "Follow-up" 2)
- `notes/rmail-rubric/structure-and-defences.md` (R13, open question 7)
