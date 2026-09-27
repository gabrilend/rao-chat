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

## Related documents

- `notes/vision-planning.md` sections 3 ("Joining"), 15; section 14 (the
  port follow-up, question 11)
- `notes/rmail-rubric/addresses-and-ports.md`
