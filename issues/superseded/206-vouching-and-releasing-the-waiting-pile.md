# 206 — Vouching, and releasing the waiting pile

> **Superseded 2026-09-25, never built.**  Written for the model where a
> room's name was its key (planning document, Appendix B), where vouching
> decided which of two same-named islands a stranger belonged to.  In the
> adopted model (section 15, now sections 1–4) each room has its own random
> token, so same-named rooms are simply different rooms and holding the
> token is being invited; joining is the hello (205).  Kept as the record of
> that design.

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 201, 202, 205
**Blocks:** 207, 210

## Current Behavior

Nothing exists.  105a holds messages from unvouched addresses.

## Intended Behavior

Owner: "you send out a request to the other people in the room "hey can
you send me your contact lists?" then you don't decrypt the untrusted
message until you get back a response that confirms that the sender is
invited."  And: "someone else in the room has to have added them to their
"contacts list" manually".

- **Inviting is vouching.**  Adding someone to a room (with `me` as the
  voucher) is what lets other members accept them.
- **Asking.**  When messages wait under a name from an unknown address, the
  server asks the members it knows in each island of that name: "do you
  vouch for this address?"
- **Answering.**  A member answers yes if the address is one of its
  members.
- **Releasing.**  The first yes decides the island: the waiting messages
  are filed there (105a → 105) and the address becomes a member there
  (103), with the answering member recorded as its voucher.  Owner: the
  island whose member vouches is where it is filed.
- **No answer** leaves the messages waiting until they age out (105a).

## Suggested Implementation Steps

1. `vouch-ask` and `vouch-answer` inner kinds.
2. Asking when something waits; answering from `members`.
3. Releasing on the first yes.
4. Tests: two `coffee-shop` islands, a stranger vouched for in one, filed
   there and not in the other; no voucher, nothing filed.

## Blockers that are not the owner's

- Needs 201, 202, 205, and phase 1's 103 and 105a.

## Open questions

1. **Two islands both vouch.**  The same address is vouched for by members
   of two same-named islands: file into both, or is this the signal to
   merge them (102, open question 1)?

## Related documents

- `notes/vision-planning.md` section 3 ("Joining"); section 14 ("Toward
  question 4")
