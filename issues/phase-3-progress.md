# Phase 3 Progress

## Goals
Clients' connection (planning sections 6 and 15): the Android app and the
web page are both **viewers** of the RAM inboxes the mailbox gatherers
(phase 2, issue 211) keep — reading one file per message, writing what the
person types into the right place, so the person never touches the
filesystem.  Then pairing, catching up, live pushing, several devices at
once, and the locked-screen check-in, as the planning document describes.
Counts: `/home/ritz/programming/ai-stuff/scripts/progress-dashboard.lua
/home/ritz/programs/rao-chat -m`.

## Completed Issues
(None yet.)

## In Progress
- 301 — the RAM inboxes as the viewer's interface: steps 1 and 2 built
  2026-11-05 (`inbox/<room>/<written>-<id>`, `.room`, `.tree`, written by
  each gatherer; `typed/` in 301's shape, filed once under its own id;
  referees 1 to 5).  The reference viewer (step 3) is left.
