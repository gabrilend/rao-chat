# 606 — Phase 6 demo

**Phase:** 6 — Installation and running as a service
**Blocked by:** 601 to 605

## Intended Behavior

As 106, 210, 310 and 409: one command (`run-phase-demo 6`) on loopback
only, showing phase 6 as the planning document puts it: "Installation
and running as a service — as rmail's installer does."

- **What a home needs** (601), as this machine answers it.
- **Two homes installed by the installer**, unattended (`--silent`),
  each into a scratch folder: A on 127.0.0.2 and B on 127.0.0.3, each
  set up as a systemd user service (the service-manager commands are the
  604 stand-ins on a scratch `PATH`, `HOME` a scratch folder, logs in a
  scratch folder): the config's asked lines and a few stated ones with
  their comments, the unit file written, the list of homes (605).
- **Installed again, nothing changes** (602 referee 4): every file of
  both homes is byte for byte as it was.
- **The services run the homes**: the stand-in `systemctl --user start`
  runs each unit's `ExecStart` as written; each home's launcher (603)
  starts its starter, gatherer and device server; the ports answer.
- **The homes talk**: a room made between them (the demo stands in for
  the viewer, which cannot make rooms yet), a device paired with A
  (189, the reference device 190) writes, and B's RAM inbox has it.
  The demo's timing settings (sync every 2 s, quick retries) are set
  with 232 first, as a person would edit the config (decision 4).
- **An update**: `restart-homes --yes` restarts both, each checked
  running again, and A's device catches up after it.
- **The stop**: `systemctl --user stop` for each; each launcher exits 0,
  each gatherer's state says it was asked, and nothing of either home
  runs.
- **Said plainly in the output**: no real service manager is used, and
  why (a demo installs nothing on the machine it runs on).

## Status

Built 2026-11-06 on branch `claude/606-phase-6-demo`:

- `issues/completed/demos/phase-6-demo` (the wrapper, run by
  `run-phase-demo 6`), `src/phase-6-demo/245-phase-6-demo.lua` (the
  driver), `src/phase-6-demo/246-phase-6-scenes.lua` (eight scenes:
  needs, install, again, room, services, talk, update, stop).
- Referee: `src/phase-6-demo/tests/247-test-phase-6-demo.lua`, 28 checks,
  all passing.  Two mutations were caught: `restart-homes` not running
  the restart command, and the launcher ignoring SIGTERM (each stop then
  ends in the stand-in's SIGKILL after 60 s).
- The whole demo runs in about 15 s.

## Referees

1. **The demo runs whole** through `run-phase-demo 6` from `/`: every
   scene passes, the exit status says so, and nothing is left running
   or on disk.
2. **The installed homes talk**: B's inbox holds the line A's device
   wrote, after both were started from their unit files.
3. **Broken versions fail**: a scene made to fail
   (`RAO_PHASE6_DEMO_BREAK`), and a project copy missing the launcher.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **A stand-in service manager, never the machine's own**: the demo
   runs where it is run, and a demo that installs a real service would
   change the machine.  The stand-in runs exactly the unit file the
   installer wrote, so what the real one would run is what runs.
2. **systemd user services for both homes**: the kind the installer
   starts itself; the other kinds are written and printed (604's
   referees show them), and their files are shown.
3. **310's world is borrowed where it fits** (its helpers, as 409
   decision 3), and the homes themselves are the installer's.

### While building, 2026-11-06

4. **The demo's timing is a hand edit after the install**, with 232
   (`gatherer.sync-interval = 2` and five more), not installer flags:
   the installer asks only five questions, and the first variants (a
   30 s sync) would make the demo wait minutes.  It also shows that the
   installer keeps hand edits: the second install comes before it and
   changes nothing.
5. **Without a network namespace the demo does not run** (exit 1, said),
   where 106 to 409 run with a part missing: here every scene runs the
   homes' own starters, which check the public address.
6. **Printed paths read `<demo>` and `<project>`**, so the output reads
   the same wherever the project is; the service names still carry the
   real path (they are made from it).

## Related documents

- issues 106, 210, 310, 409 (the earlier demos)
- `notes/vision-planning.md` section 12
