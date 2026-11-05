# Phase 2 Progress

## Goals
Server-to-server delivery for "a room is a contact" (planning sections
1–5 and 15), built with rmail as a rubric, not a source
(`strategems/other-peoples-software-as-a-rubric.md`,
`notes/rmail-rubric/`): every issue carries the rules it must meet, the
formation it tries that differs from rmail's, and referee tests written
from the rules and checked against deliberately broken versions.

What the phase builds:

- **Sealing** with a key made from each room's random token, every sealed
  body starting with a key-tying value, trial opening limited to one
  mailbox's keys.
- **One data-gatherer process per mailbox**, working in RAM folders as a
  pipeline (listener, openers, filer, sender), loading from disk at
  start-up and syncing back every cycle; acknowledging after a disk write
  or after a RAM write, built both ways until the owner chooses.
- **Delivery** to every address-and-port pair at once, acknowledged by id,
  retried forever with a per-pair timer; the log is the outbox.
- **Where a mailbox can be reached**: its outside port configured per
  mailbox, the home's public address looked up and rechecked, housemates
  found on the home network.
- **Joining and membership**: the hello, the call-back check, syncing
  member lists by digest, leaving with a remembered record, and the
  periodic cross-check that catches a two-faced sender and fills gaps.
- **Signatures** read from each message's text by one rule.
- **One git repository per mailbox**: a text copy of every message
  (editable, never sent), the running log committed every sync cycle in
  size-bounded files, the running source code on its own branch, and an
  optional shared upstream pulled and pushed at start-up, shut-down and
  each public-address recheck.
- **The failed-decryption log** for fail2ban, and the phase demo.

Build order (lower numbers are not always earlier; the Blocked by fields
are the authority): 201 → 201a → 211 → 202 → 203 → 204 → 212 → 205 → 213
→ 207 → 208 → 209 → 214 → 215 → 215a → 215b → 210.  214 (signatures)
needs only phase 1 and may be built at any time.

Counts: `/home/ritz/programming/ai-stuff/scripts/progress-dashboard.lua
/home/ritz/programs/rao-chat -m`.  Open questions still waiting on the
owner, most blocking first: `notes/rmail-rubric/open-questions.md`.

## Completed Issues
(None yet.)

## Under way
- **201** — built 2026-11-05 in `src/sealing/` (123–128): key from token,
  sealing and opening, frames on a connection, the inner record table,
  keyrings per mailbox, trial opening split for workers; open questions
  1–5 answered as dated decisions the owner may overturn.  Left: the
  workers and the port (211), the other kinds' rows (their issues), and
  201a's referee.
