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
- **An update**: `restart-homes --yes` restarts both, each checked
  running again, and A's device catches up after it.
- **The stop**: `systemctl --user stop` for each; each launcher exits 0,
  each gatherer's state says it was asked, and nothing of either home
  runs.
- **Said plainly in the output**: no real service manager is used, and
  why (a demo installs nothing on the machine it runs on).

## Status

Not built yet.

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

## Related documents

- issues 106, 210, 310, 409 (the earlier demos)
- `notes/vision-planning.md` section 12
