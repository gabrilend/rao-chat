# 205 — The hello: joining a room, and saying where to call back

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 201, 202, 204, 212
**Blocks:** 207, 210

## Current Behavior

Nothing exists.  Phase 1 makes a room from a token and a list of members
(101's `make_room`), adds members with the ignore refusal and the
parent-membership flag (103's `add_member`), and keeps every mailbox's
listening port.  212 adds the outside port and the home's pairs by kind.

## Intended Behavior

**Joining.**  Someone gives you a room's token and one member's pair (for
a child room, members who find you are not in its parent will see you
flagged until they approve you).  Your server makes the room (101) and
sends that pair a hello sealed with the token.  Holding the token is the
proof: the member calls you back (204), adds your pairs (103, with its
ignore refusal and parent-membership flag) and sends you its members
(207).

**A hello says where this mailbox can be reached**: every pair from 212
with its kind (`public` with the outside port, `hostname`, `ipv6` with the
listening port; `home-network` only to a housemate, 213), and a claim id
(204).  Owner, on ports: "no way. no default port numbers."  **A hello
without a port is an error**, not a guess.

**When a hello is sent:** before the first message to any pair not yet
confirmed; at start-up to every pair on every send list of the mailbox;
and when 212 reports a confirmed move.

**Receiving a hello:** each stated pair is called back (204) before it is
added; a pair already held is not called again unless it has been silent
past the retry ceiling.  Pairs are added beside the ones held, never
replacing them.

**A child room merging into its parent's mailbox** (phase 1, round 4)
changes its listening port: its gatherer sends a hello with the new pairs,
and the old port is still served for that room until every member has
called back on the new one.

## Rubric

- **The number to dial must be said, and is the outside one** (addresses
  R1).
- **Send all your pairs; let the receiver's attempts decide** (addresses
  R9, rmail's issue 388: announcing one address overwrote a housemate's
  working home-network address).
- **A private address is meaningful only on its own network** (addresses
  R3): `home-network` pairs go only to housemates.
- **A claim is proved in the direction in doubt, before use** (addresses
  R8) — 204.
- **Nothing that changes nothing is answered** (structure R6, addresses
  R10): a hello whose pairs are all already held and confirmed makes no
  reply beyond the call-back's answer; comparing is by set, not order.
  rmail's idle daemons once exchanged 1,500 announcements in 15 seconds.
- **A hostname is not overwritten by an address** (addresses R16) — met by
  "added beside, never replacing".
- **Every record is safe to receive twice or reflected** (sealing R9): a
  server's own hello sent back to it adds none of its own pairs as members.

## Where we differ

rmail announces one address per contact (later the set) with its config
port, and the receiver applies it at once because the key names the
sender.  The formation here is **the hello as the one message that both
joins and announces**: joining a room, telling members after a move, and
re-announcing at start-up are the same record with the same handling on
the receiving side — call back each pair, add what is new.

- **Gains:** one code path for three events; a moved home is re-found by
  any member it can still reach (the addresses note's "moves through the
  room" formation, carried on by 207).
- **Costs:** a start-up hello to every pair of every room is a burst of
  call-backs across the whole membership; with many rooms per mailbox, a
  hello per room rather than one per mailbox (each room has its own key).

## Referees

1. **Joining adds you.**  With a token and one member's pair, B's side
   adds A's pairs after calling back, and A receives B's members.
   *Broken:* adding without calling back.
2. **A wrong port is not confirmed.**  A hello naming a port where nothing
   listens: not added.  *Broken:* adding on receipt.
3. **No port is an error.**  A hello record with a pair missing its port
   fails to decode (201's table).  *Broken:* a default port.
4. **Child room outsider is flagged.**  A hello to a child room from a pair
   not in the parent: added flagged (103).
5. **Idle homes are quiet.**  Two homes with identical rooms restart: one
   hello round and its call-backs, then silence for 60 s.  *Broken:*
   answering a hello with a hello.
6. **Reflection.**  A's own hello sent back to A adds nothing.
7. **Merge moves the port.**  A child room merges into its parent's
   mailbox: members receive the new pairs and still reach the room on the
   old port until they have called back.  *Broken:* closing the old port
   at once.

## Suggested Implementation Steps

1. The `hello` record: pairs with kinds, claim id (201's table).
2. Joining: make the room from a token and one pair; send the hello.
3. The three sending moments (first message, start-up, move) in the
   gatherer.
4. Receiving: call back each new pair (204), then add (103).
5. The merge case: the old port kept for moved rooms until confirmed.
6. The referees above.

## Blockers that are not the owner's

- Needs 201, 202, 204, 212, and phase 1's 101 and 103.

## Open questions

1. **A new member's past messages** (202's question 3): does joining bring
   the room's history?
2. **Start-up hellos at scale**: one per room per pair is many frames for a
   big mailbox.  Send only to pairs silent longer than a setting?
3. *(answered 2026-09-27)* **Learning your own outside port.**  Configured
   by the person per mailbox (212); no sweep.

## Decisions (2026-11-05)

Made by the builder.  The owner's standing instruction is to answer open
questions rather than wait, choosing the option that is easiest to undo.
The owner can overturn each one; what overturning costs is said with it.
Built in `src/delivery/` (145 hello, 146's referees), the `hello` row and
the `pairs` field type of `src/sealing/126-inner-records.lua`, `make_for`
in 141, hello jobs in 134's stage, and the hand-over in 133's `serve`.
212 (where a mailbox can be reached) and 207 (members lists) are not
built; what stands in for them is said below.

1. **A new member gets no history** (open question 1).  202's decision 3
   stands: a pair joins the `delivered` file at the next own write, with
   everything before it counted as delivered.  Undo: 130's
   `starting_line`, as 202 says.
2. **Start-up hellos go to every pair on every send list** (open question
   2), as the issue says.  The cost is bounded on the receiving side: a
   pair already a member and heard from within the retry ceiling is not
   called back, so an idle restart is one frame each way (referee 5).
   Undo: skip pairs heard from recently in `Stage:announce`, behind a new
   setting.
3. **The `pairs` field** holds one pair per line, "kind address port",
   the lines joined with a line break that the log's escaping writes as
   `\n`.  Kinds are 212's four (`public`, `hostname`, `ipv6`,
   `home-network`); a port is 1 to 65535 and never guessed.  A pair
   missing its port, an unknown kind, or an empty list is refused on
   encoding and decoding.  Undo: the field type is two functions in 126.
4. **One claim id per hello**, one `claims` line per stated pair, all with
   that id (141's `make_for`).  The answer is `yes` when any line with
   that id states the pair asked about, so each pair is still confirmed on
   its own.  Undo: one id per pair, a list of ids in the record.
5. **The ack names the claim id**: 133 answers a hello with an `ack`
   holding the claim id and `filed`, or `duplicate` when this stage has
   heard that claim before (kept in memory).  An ack naming the claim ends
   the sender's hello job; anything else is a failure of its timer.
6. **Where this mailbox can be reached comes from a seam** until 212 is
   built: `seams.own_pairs(tag)` on the sender stage.  A stage without it
   sends no hellos and `join` refuses; nothing is guessed.
   `home-network` pairs are stated only to a housemate,
   `seams.is_housemate(pair)` (213's); without that seam nobody is one.
   Undo: 212 and 213 give the seams; nothing here changes.
7. **A confirmed hello counts as hearing from the pair**: 142's hello
   action is now 103's `heard_from` at the confirmation time (add, then
   record the time), not `add_member` alone.  This amends 204's decision
   8.  It is what lets the receiver skip pairs heard recently.  Undo: one
   line in 142's `ACTIONS`.
8. **"Silent past the retry ceiling"** is read as: not a member, or a
   member never heard from (heard 0), or last heard longer ago than the
   stage's `delivery.retry-ceiling`.  Only those pairs are called back.
9. **Ignored pairs are not called back**: 042's `refused_as_member`
   would refuse them at the add anyway.
10. **Reflection** (sealing R9): a hello whose claim id is in this room's
    own `claims` file is this home's own, sent back; nothing is added and
    nobody is called.
11. **"Before the first message to a pair not yet confirmed"** is read
    as: before the first message, in this run of the stage, to a member
    never heard from.  Hello jobs, like 202's timers, are not kept across
    a restart; start-up re-announces anyway.
12. **Hellos run first in a pass**, before deliveries and checks, so a
    pair hears where to call back before it gets the message.  A hello
    job keeps one claim and resends the same record on every retry; a
    move (`Stage:moved`) makes a fresh job with a new claim.
13. **Joining trusts the pair the person gave**: it is added as a member
    at once (with 103's refusals and flag), because the person typed it.
    Every field of `join`'s spec is required, like `make_room`'s.
14. **Referee 1's second half** ("A receives B's members") is 207's.
    The referee checks the join, the call-back and the add.
15. **Referee 7 is built in part.**  A move announces the new pair, which
    is called back and added beside the old one.  Keeping the old port
    served until every member has called back on the new one belongs to
    the gatherer (211), which owns the listeners; it is not built.

## Related documents

- `notes/vision-planning.md` sections 3 ("Joining"), 15; section 14 (the
  port follow-up, question 11)
- `notes/rmail-rubric/addresses-and-ports.md`
