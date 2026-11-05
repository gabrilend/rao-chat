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
- 301 — the RAM inboxes as the viewer's interface: step 1's message
  files built 2026-11-05 (`inbox/<room>/<written>-<id>`, written by each
  gatherer; referees 1, 2, 3, 5).  `.room`, `.tree`, the `typed/` shape,
  the reference viewer and referee 4 are left.
