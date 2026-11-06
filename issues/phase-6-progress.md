# Phase 6 Progress

## Goals
Installation and running as a service (planning section 12, phase 6:
"as rmail's installer does"): a person who has the program folder makes
a home by answering a few questions, and the home runs as a service of
the machine's own service manager, stops cleanly, restarts after an
update, and can be followed in its logs.  It ends with two homes
installed and run that way, talking.
Counts: `/home/ritz/programming/ai-stuff/scripts/progress-dashboard.lua
/home/ritz/programs/rao-chat -m`.

## Issues (written 2026-11-06 from planning section 12 and a reading of rmail's installer)

The rubric is `notes/rmail-rubric/installing-and-services.md` (rules I1
to I12, referees 1 to 7).

Build order, each blocked only by earlier ones:

- 601 — what a home needs, found or named
- 602 — making a home: the installer's questions and the home's config
- 603 — running a home: one command, both programs, a clean stop
- 604 — running as a service: one service per home, for the machine's
  service manager
- 605 — after an update: restarting every home, and following its logs
- 606 — phase 6 demo: two homes installed and run as services, talking

Phase 5 (the Android app) is planned in its own issues and waits on the
Android toolchain on the owner's machine; phase 6 does not wait on it.

Every open question was answered by the builder on 2026-11-06 under the
owner's standing instruction of 2026-11-02; each answer is a dated
decision in its issue, and the owner may overturn it.

Left for later issues, not phase 6's: building missing libraries from
vendored sources in `libs/` (601 decision 1); macOS (601 decision 4); a
portable home on a drive (rmail #616).

## Completed Issues
(None yet.)

## In Progress
- 601 — what a home needs: built 2026-11-06
  (`src/install/230-what-a-home-needs.lua`; referees in
  `src/install/tests/231-test-what-a-home-needs.lua`).
- 602 — making a home: built 2026-11-06 (`scripts/install-home`,
  `src/install/232-make-home.lua`; referees in
  `src/install/tests/233-test-install-home.lua`).
- 603 — running a home: built 2026-11-06 (`scripts/run-home`; referees in
  `src/install/tests/234-test-run-home.lua`).
- 604 — running as a service: built 2026-11-06
  (`src/install/235-service-manager`, `236-service-files.lua`, the
  templates 237–241, the stand-ins `242-stand-in-service-managers.lua`,
  and the installer's service section; referees in
  `src/install/tests/243-test-running-as-a-service.lua`).
- 605 — after an update: built 2026-11-06 (`scripts/restart-homes`,
  `scripts/view-logs`, the list `installed-homes` ignored by git, the
  installer's last question; referees in
  `src/install/tests/244-test-after-an-update.lua`).
- 606 — phase 6 demo: built 2026-11-06
  (`issues/completed/demos/phase-6-demo`, `src/phase-6-demo/245-*`,
  `246-*`; referee `src/phase-6-demo/tests/247-test-phase-6-demo.lua`).

Every phase 6 issue is built, each on its own branch stacked on the one
before, waiting on the owner's review.  The check left for a person: a
real install on the owner's machine (`scripts/install-home` with
`--setup-service`, then `systemd-analyze verify` on the unit and a
`systemctl --user start`), since no real service manager was used here.
