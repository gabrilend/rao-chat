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

## Related documents

- `notes/vision-planning.md` section 14 ("Toward question 4", "Answers" 9,
  "Follow-up" 2)
- `notes/rmail-rubric/addresses-and-ports.md` (R1, R2, R6, R8)
- `notes/rmail-rubric/structure-and-defences.md` (section 4, hairpin and Tor)
