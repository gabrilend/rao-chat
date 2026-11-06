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

## Issues (written 2026-11-06 from planning section 6)

Build order, each blocked only by earlier ones:

- 302 — the device port (a port of the home's, frames sealed under a
  paired device's own token)
- 303 — pairing a device (the `devices` file, `189-pair`, the reference
  device's connection test)
- 304 — catching up (positions and digests per room, the device's mirror)
- 305 — writing from a device (`typed` records into the right gatherer)
- 306 — live pushing, and several devices at once
- 307 — choosing an address (home network first, then public)
- 308 — the locked-screen check-in (the deck, −5 … +5)
- 309 — the browser's way in (the WebSocket upgrade on the device port)
- 310 — phase 3 demo

The questions that held them (rubric question 24, 301's questions 1 and
2, planning question 4) were answered by the builder on 2026-11-06 under
the owner's standing instruction of 2026-11-02; each answer is a dated
decision in its issue, and the owner may overturn it.

## Completed Issues
(None yet.)

## In Progress
- 302 — the device port: built 2026-11-06 (`src/devices/185` to `188`;
  referees 0 to 6).
- 303 — pairing a device: built 2026-11-06 (`189-pair`, `190-device`'s
  `test`, referees in `191-test-pairing.lua`).
- 304 — catching up: built 2026-11-06 (`192-mirror`, `catch-up` and
  `want` in 187, 190's `catch-up`; referees in `193-test-catching-up.lua`).
- 305 — writing from a device: built 2026-11-06 (`typed` in 187, 190's
  `send`; referees in `194-test-writing-from-a-device.lua`).
- 306 — live pushing, and several devices at once: built 2026-11-06
  (pushing and `devices.idle-limit` in 187, 190's `live`; referees in
  `195-test-live-pushing.lua`).
- 301 — the RAM inboxes as the viewer's interface: built 2026-11-05
  (`inbox/<room>/<written>-<id>`, `.room`, `.tree`, written by each
  gatherer; `typed/` in 301's shape, filed once under its own id; the
  reference viewer, `src/viewer/183-viewer.lua`; referees 1 to 5).  Kept
  here until the owner reviews it; the remote viewers are the next
  issues.
