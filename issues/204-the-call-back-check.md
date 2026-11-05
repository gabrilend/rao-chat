# 204 — The call-back check

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 201, 202, 211
**Blocks:** 205, 207, 208, 210

## Current Behavior

Nothing exists.  rmail has no call-back: it applies an address
announcement on receipt (its per-pair token names the sender), and only
later treats a successful outbound send as proof the new address works
(addresses note, 1c and R8).

## Intended Behavior

Before trusting "I am at this address, listening on port N" (a hello,
205, or a pair learned from a members list, 207), or "I have left this
room" (208), the server calls that address and port and asks, sealed with
the room's key: "did you make claim C?"  Only a computer really listening
there, holding the room's key, and having made that claim can say yes.

- **Every claim carries a claim id** (32 hex characters, random), and the
  claimant keeps the claims it has made — kind (`hello` or `leave`), room
  local tag, claim id, when made (integer seconds) — in a `claims` file in
  each room's folder (RAM, 211; synced to disk).  The `did-you` record
  names the claim id; the `did-you-answer` names it back with `yes` or
  `no`.
- It proves where a server can be reached, never who wrote anything (the
  sender is unknowable by design), and needs no keys beyond the room's.
- It stops a false return address from aiming traffic at someone else, and
  a forged leave from cutting anyone off.
- **No answer means "not confirmed"**, never "confirmed"; a claim not
  confirmed within config `callback.answer-time` (whole seconds, no
  default) is left unconfirmed and retried by 202's timers, not dropped.
- The ask is sent to the **stated** pair, never to the address the claim's
  connection came from.

## Rubric

From `notes/rmail-rubric/addresses-and-ports.md` unless named.

- **A move (or any "I am here") is a claim; what proves it is a successful
  exchange in the direction in doubt** (R8).  Receiving a claim proves the
  claimant can reach you; only reaching them at the claimed pair proves
  the pair.  rmail's first handshake tested the wrong direction (its issue
  388).  In rao-chat any member can claim any address, so the check comes
  **before** the pair is used.
- **The port others must dial cannot be read off a connection** (R1): the
  call-back goes to the stated port.
- **A connection's source may be a router's** (R2, structure R11): never
  call back the source address.  And the hairpin trap (structure note
  section 4): a housemate's call-back through the router may reach the
  right machine and "confirm" a pair that only works inside the house.
- **"Nobody answered" is not "nothing changed"** (R6): silence confirms
  nothing.
- **Every record is safe to receive twice or reflected** (sealing R9): a
  replayed `did-you` gets the same answer and changes nothing; a claim id
  answered `yes` confirms only that claim.

## Where we differ

The formation here is **the answer comes from where the claim was
written**: the claimant answers from its own `claims` file, the same
record it wrote when it sent the claim, rather than from a separate
"recently sent" memory with an expiry.  How long a server can answer is
simply how long it keeps its claims — for as long as the room exists.

- **Gains:** answers "how long does a server remember what it sent" (this
  issue's old question 1) without a new timer; claims are small, one line
  each; the same file shows the person what their server has announced.
- **Costs:** the file grows with every hello and leave (bounded in practice:
  one hello per new pair and per move); a restored backup of an old home
  answers `yes` for claims its newer self also made (harmless: the claim
  is about the pair it answers on).

## Referees

1. **A genuine claim is confirmed.**  A says hello with pair P; B asks P;
   A answers `yes`; B adds P.  *Broken:* a claimant that answers from
   memory lost at restart (restart A between hello and ask: it must still
   answer `yes`).
2. **Someone else's address is refused.**  A's hello names a pair where a
   different home, holding the room key, listens: it answers `no` (it made
   no such claim); where nothing listens: no answer; P is not added either
   way.  *Broken:* confirming on any sealed answer.
3. **The source address is never called.**  A claim arrives through a
   relay whose source is 127.0.0.9; nothing connects to 127.0.0.9.
   *Broken:* rmail-style use of the connection's source.
4. **No answer is not confirmation.**  The stated pair is black-holed:
   after `callback.answer-time` the pair is unconfirmed and retried later.
   *Broken:* treating a timeout as yes.
5. **Replays change nothing.**  Record a `did-you` and replay it: same
   answer, no state change.

## Suggested Implementation Steps

1. The `claims` file and its line shape; the claim id on `hello` and
   `leave` records (201's table).
2. The `did-you` / `did-you-answer` kinds and answering from `claims`.
3. Asking: sent through 202's sender to the stated pair, with the answer
   time as a declared setting.
4. The referees above.

## Blockers that are not the owner's

- Needs 201 (the kinds), 202 (sending and timers), 211 (where claims live).

## Open questions

1. **Tor-only members** can never be called back: accept them as never
   confirmed, or plan for onion addresses?  (Rubric question 19.)
2. **Hairpin call-backs**: a housemate's pair confirmed through the router
   works only inside the house.  Mark pairs confirmed from the same public
   address as `home-only`, so 207 never passes them on?
3. **Forged acknowledgements** (202's question 5): should a call-back ever
   confirm a delivery, not only an address?
4. *(answered by the formation, to confirm)* **How long a server remembers
   what it claimed**: as long as the room exists (the `claims` file).
5. *(answered by the formation)* **The answer's time limit**: config
   `callback.answer-time`, declared, no default.

## Decisions (2026-11-05)

Made by the builder.  The owner's standing instruction is to answer open
questions rather than wait, choosing the option that is easiest to undo.
The owner can overturn each one; what overturning costs is said with it.
Built in `src/delivery/` (141 claims, 142 call-back, 144's referees, 143
the simulated world taken out of 137), the `did-you` and `did-you-answer`
rows of `src/sealing/126-inner-records.lua`, the answering in 133's
`serve`, and the checks in 134's stage.  205's hello and 208's leave are
not built: they will make claims with 141's `make`, carry the claim id in
a `claim` field, and hand what they hear to 142's `heard`.  The referees
make claims with 141 directly in their place.

1. **Tor-only members** (question 1): accepted as never confirmed.  A
   claim at a pair nobody can call stays unconfirmed and keeps being
   retried at the ceiling, and the pair is never added.  Onion addresses
   are left for when Tor is planned.  Undo: a pair kind that skips the
   check, which is the opposite of this issue's point, so it would want
   its own rubric line.
2. **Hairpin call-backs** (question 2): not marked yet.  Marking a pair
   `home-only` needs this home's public address, which 212 finds.  212
   should mark a pair confirmed from the same public address, and 207
   should not pass such pairs on.  Nothing here prevents it.
3. **Forged acknowledgements** (question 3): a call-back confirms
   addresses only, never a delivery.  202's decision 5 stands: a forged
   `ack` is outside the threat model, and 209's cross-check refills what
   it hid.
4. **How long a claimant remembers** (question 4): as long as the room
   exists; the `claims` file is never trimmed.  Confirmed as the issue's
   formation.
5. **The answer time** (question 5): `callback.answer-time`, declared in
   135 with no default.  The options file offers 8 s (rmail's connect
   timeout).
6. **A `did-you` names the pair it is asked at**, as well as the claim
   id, and the claimant says `yes` only if its claim stated that pair.
   So a key holder who passes on a genuine claim id with another pair is
   answered `no` there.  Undo: drop two fields from the row.
7. **The `claims` line carries the room's local tag** although the file
   is already in the room's folder, as the issue lists it.  A line naming
   another room is refused on reading.
8. **What a confirmed claim does**: a hello adds the pair (103's
   `add_member`, so the ignore list and the room tree's check still
   apply), and a leave removes it (103's `confirm_leave`).  A `no` ends
   the check, because asking again will not change the claimant's file.
   No answer is one failure of the check's timer, and the check is tried
   again (131's doubling and deck), never dropped.
9. **Checks are not kept across a restart of the asker**, like 202's
   timers (202 decision 2).  The claim is heard again when its maker
   resends its hello or leave.
10. **Checks run in 202's sender stage** (`Stage:check`, run in `pass`
    after the deliveries), each with a 131 timer of its own.
11. **The simulated world is shared.**  137's fake clock, relay and homes
    moved to `tests/143-test-world.lua`, used by 137 and 144.  The relay
    now records every connection attempt, and its connections have
    `settimeout`.

## Related documents

- `notes/vision-planning.md` section 14 ("Toward question 4", "Answers" 9,
  "Follow-up" 2)
- `notes/rmail-rubric/addresses-and-ports.md` (R1, R2, R6, R8)
- `notes/rmail-rubric/structure-and-defences.md` (section 4, hairpin and Tor)
