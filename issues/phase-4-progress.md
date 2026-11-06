# Phase 4 Progress

## Goals
The web client (planning sections 6, 7, 9 and 11): a page of plain HTML,
CSS and JavaScript, from one folder of static files, that seals with
WebCrypto, reaches its home through 309's WebSocket, and is a viewer of
the home's RAM inboxes like the reference device (190): catching up,
writing, live while open.  It ends with two clients talking to each
other.
Counts: `/home/ritz/programming/ai-stuff/scripts/progress-dashboard.lua
/home/ritz/programs/rao-chat -m`.

## Issues (written 2026-11-06 from planning sections 6, 7, 9 and 11)

Build order, each blocked only by earlier ones:

- 401 — the page's folder (opened from a copy on the computer; planning
  question 5)
- 402 — sealing in the page (123, 124 and 186 in WebCrypto)
- 403 — reaching the home from the page (pairing a browser, the
  connection test, choosing an address)
- 404 — catching up in the page (a mirror in memory)
- 405 — how a room looks (section 7)
- 406 — writing from the page (the compose line, the signature)
- 407 — live while the page is open (pushes, keep-alive, the error strip)
- 408 — People and Settings
- 409 — phase 4 demo: two clients talking to each other

The question that held them (planning question 5, trusting the web
page) was answered by the builder on 2026-11-06 under the owner's
standing instruction of 2026-11-02 (401 decision 1); each answer is a
dated decision in its issue, and the owner may overturn it.

Left for later issues, not phase 4's: editing a message from a device
(406 decision 3), and changing people, members, withheld and ignore
lists from a device (408 decision 1); both need a device record the
home does not have yet.

## Completed Issues
(None yet.)

## In Progress
- 401 — the page's folder: built 2026-11-06 (`src/web/203` to `207`, the
  stand-in browser `tests/208`; referees in
  `src/web/tests/209-test-the-pages-folder.lua`).
- 402 — sealing in the page: built 2026-11-06 (`src/web/210-sealing.js`,
  `211-records.js`; referees in `src/web/tests/212-test-sealing-in-the-page.lua`).
- 403 — reaching the home from the page: built 2026-11-06 (`189 add
  --browser`, `src/web/213-reaching-the-home.js`; referees in
  `src/web/tests/215-test-reaching-the-home.lua`, with the kit `214`).
- 404 — catching up in the page: built 2026-11-06 (`src/web/216-mirror.js`;
  referees in `src/web/tests/217-test-catching-up-in-the-page.lua`).
- 405 — how a room looks: built 2026-11-06 (`src/web/218-room-view.js`,
  drawing in `207`; referees in `src/web/tests/219-test-how-a-room-looks.lua`).
- 406 — writing from the page: built 2026-11-06 (`src/web/220-signature.js`,
  `221-writing.js`, the compose line in `207`; referees in
  `src/web/tests/222-test-writing-from-the-page.lua`).
- 407 — live while the page is open: built 2026-11-06 (`src/web/223-live.js`;
  referees in `src/web/tests/224-test-live-in-the-page.lua`).
- 408 — People and Settings: built 2026-11-06 (`src/web/225-panels.js`;
  referees in `src/web/tests/226-test-people-and-settings.lua`).
- 409 — phase 4 demo: built 2026-11-06 (`issues/completed/demos/phase-4-demo`,
  `src/phase-4-demo/227` and `228`; referee `229-test-phase-4-demo.lua`).
  Two pages, one on each home, talk to each other; Node stands in for
  both browsers, and the page's drawing is tried only on the stand-in's
  paper document (405 decision 10), so a real browser is still to try.
