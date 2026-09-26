# 204 — The call-back check

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 201, 202
**Blocks:** 205, 208, 210

## Current Behavior

Nothing exists.

## Intended Behavior

Before trusting "I am at this address, listening on port N", or "I have
left this room", the server calls that address and port and asks, sealed
with the room's key: "did you send message X?" / "did you leave?"  Only a
computer really listening there can answer.

- It proves where a server can be reached, never who wrote anything
  (the sender is unknowable by design).
- It needs no keys beyond the room's.
- It stops a false return address being used to aim traffic at someone
  else, and a forged leave notice from cutting anyone off.
- No answer means "not confirmed", never "confirmed".

## Suggested Implementation Steps

1. The `did-you` ask and its answer (201's inner kinds).
2. Remembering what this server sent recently, so it can answer.
3. A time limit for the answer (config, no default).
4. Tests: a genuine claim confirmed; a claim naming someone else's address
   refused; no answer is not a confirmation.

## Blockers that are not the owner's

- Needs 201 and 202.

## Open questions

1. **How long does a server remember what it sent**, so it can answer
   "did you send X?"
2. **The answer's time limit**: which config key?

## Related documents

- `notes/vision-planning.md` section 14 ("Toward question 4", "Answers" 9,
  "Follow-up" 2)
