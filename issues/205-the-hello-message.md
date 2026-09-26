# 205 — The hello: joining a room, and saying where to call back

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 201, 202, 204
**Blocks:** 207, 210

## Current Behavior

Nothing exists.

## Intended Behavior

**Joining.**  Someone gives you a room's token and one member's address
(for a child room, you must already be in its parent).  Your server makes
the room (101) and sends that member a hello sealed with the token.
Holding the token is the proof: the member adds your address (103, with
its ignore and parent-membership refusals) and sends you its members
(207).

**Every first contact with an address carries a hello**, sealed with the
room's key: the port this server listens on, as seen from outside (a
forwarded port's outside number).  Owner, on ports: "no way. no default
port numbers."  **A hello without a port is an error**, not a guess.  The
sending address needs no saying: every packet carries it in the open.

The receiver confirms the port with the call-back check (204) before
adding the address.

## Suggested Implementation Steps

1. The `hello` inner kind with its port.
2. Joining: make the room from a token and one address; send the hello.
3. Sending a hello before a first message to any new address.
4. Receiving: call back (204), then add the member (103).
5. Tests: joining with a token adds you on the member's side; a hello with
   a wrong port is not confirmed; a hello with no port is an error; a
   hello to a child room from an address not in the parent is refused.

## Blockers that are not the owner's

- Needs 201, 202, 204, and phase 1's 103.

## Open questions

1. **Learning your own outside port.**  Behind a router, a server may not
   know its forwarded port's outside number.  rmail has a "detect port"
   scan; is the owner expected to write it in config, or should the server
   find it?

## Related documents

- `notes/vision-planning.md` sections 3 ("Joining"), 15; section 14 (the
  port follow-up, question 11)
