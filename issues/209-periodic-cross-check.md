# 209 — Periodic cross-checking between members

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 207
**Blocks:** 210

## Current Behavior

Nothing exists.  105 raises an error when one id arrives with two
different contents.

## Intended Behavior

Owner: "we shouldn't syncronize on every single message, but like...
periodically we can sync. If there's ever a discrepancy it's raised as an
error, not a silent warning in some log somewhere that gets auto-corrected.
But remember, we also need to be able to edit messages as well... Phew
this is complex!"

- **Periodically**, members send each other a `summary`: for a room, each
  message id they hold with a fingerprint of its contents.
- **A missing message is normal** — everyone chooses whom they send to —
  **but a sender fills its own gaps.**  When a summary shows that an
  address on this server's send list lacks one of this server's *own*
  messages, the message is sent again (owner: "the sender will notice "hey
  this person on the sending list doesn't have this message, I should send
  it" on their next sync cycle").  Only its own messages, and never to a
  withheld address: passing on others' messages would override their
  choice of whom to send to.
- **No summaries go to an ignored address** (103a), so ignoring stays quiet:
  the ignored server cannot see the gaps, and does not resend every cycle.
  Un-ignoring lets the next summary show the gaps and the messages come
  back.
- **The same id with a different fingerprint is an error**, raised to the
  person.  This catches someone showing different words to different
  people under one id.
- **Edits never cause one**: an edit is its own message with its own id.

## Suggested Implementation Steps

1. Fingerprint of a record's contents.
2. The `summary` inner kind; sending on a timer (config, no default).
3. Comparing; raising the error with both versions.
4. Tests: an edit produces no error; a two-faced sender does.

## Blockers that are not the owner's

- Needs 207 (members to compare with) and 105's conflict error.

## Open questions

1. **How often**, and does a summary cover the whole room or only recent
   messages?
2. **Where the error is raised**: a notice in the room (centred, boxed, as
   section 7 describes), and anywhere else?

## Related documents

- `notes/vision-planning.md` section 3 ("Checking each other"); section 14
  ("Answers" 7)
