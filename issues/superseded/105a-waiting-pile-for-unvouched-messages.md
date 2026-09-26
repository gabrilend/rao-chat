# 105a — The waiting pile: messages no one has vouched for yet

> **Superseded 2026-09-25, never built.**  Written for the model where a
> room's name was its key (planning document, Appendix B): a stranger could
> guess a name, so their messages had to wait until a member vouched for
> them.  In the adopted model (section 15, now sections 1–4) a room's key is
> a random token, and holding it is being invited, so a message that opens
> with the token is filed at once.  Kept as the record of that design.

**Phase:** 1 — Rooms on the home server
**Parent issue:** 105
**Blocked by:** 101, 103, 103a, 105
**Blocks:** 106
**Module folder:** `src/message-log/` (indexes 080–099, shared with 105)
**Contract:** `docs/phase-1-module-contract.md`

## Current Behavior

Nothing exists.

## Intended Behavior

When a message arrives for a room name from an address that is not a
member of any island of that name, it cannot be filed yet: nobody knows
which island it belongs to, or whether it belongs at all.  Phase 2 opens
it (the lock says whether it is genuine) and hands it here.  Owner: "opened
but not parsed. Not scanned. Not even touched."

- **Stored as it was opened.**  `rao-home/waiting/<room name, escaped>/`
  holds one file per message: the opened bytes exactly, unparsed, beside a
  small record of the room name, the address it arrived from, the port
  that address said to call back on, and when it arrived.
- **Released to an island.**  When a member of an island vouches for the
  address (phase 2 asks), everything waiting from that address under that
  name is filed into that island's room through the message log (105) —
  parsed for the first time there — and the address becomes a member
  (103).  **The island whose member vouches is the island it is filed
  in.**
- **Dropped after a set time.**  A message no one vouches for is deleted
  after a time read from config, with no default.
- **Shown only as a count.**  The room can say "3 messages from someone no
  one has vouched for" without showing any of them.
- **Ignored addresses** (103a) are not held: a message from an ignored
  address is dropped on arrival.

## Suggested Implementation Steps

1. Holding a message: write the bytes and the small record, atomically.
2. Listing what waits under a name, grouped by address; counting.
3. Releasing an address's messages to an island's room, through 105's
   filing (so duplicates and conflicts behave as anywhere else).
4. Dropping by age, reading the time from config.
5. Refusing ignored addresses.
6. Tests: hold, count, release to the right island when two islands share
   the name, drop by age, ignored address refused.

## Blockers that are not the owner's

- Needs 105's filing and 103a's ignore list; the asking and vouching are
  phase 2.

## Open questions

1. **Where the time limit lives.**  One value for the whole home in
   `config` (suggested), or one per room?  No default either way.
2. **Does a flood of unvouched messages count toward the failed-decryption
   log?**  They opened correctly, so they are not failures; but a stranger
   sending thousands is the flooding case.  A separate count per address?

## Related documents

- `notes/vision-planning.md` section 3 ("Joining"); section 14 ("Toward
  question 4", "Answers" 4 and 10, "Follow-up" 3 and 4)
- `docs/phase-1-module-contract.md`
