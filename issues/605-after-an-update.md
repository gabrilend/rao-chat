# 605 — After an update: restarting every home, and following its logs

**Phase:** 6 — Installation and running as a service
**Blocked by:** 604
**Blocks:** 606

## Current Behavior

One program folder serves every home installed from it (602 decision
6), so updating that folder (a `git pull`) is the whole update, but a
running home keeps the code it started with until its service restarts,
and nothing says so (rubric I10; rmail #622 found mailboxes running four
hours of old code).  Restarting by hand means remembering every home's
service name and its manager's command.  A home's logs are in two
places: the service's log in `/tmp` (604) and the running logs in its
RAM folders (211).

## Intended Behavior

- **A list of the homes installed from this program folder**,
  `<project>/installed-homes`, one line per home: service name, service
  manager, home folder.  The installer adds a line for each home it sets
  up as a service (604) and changes nothing else in it.  The file is
  ignored by git (`.gitignore`), so it is never committed, and so never
  reaches a `code/` branch (164 commits the folder with its
  `.gitignore` applying).
- **`scripts/restart-homes`** (Bash):
  - with no names, restarts every listed home with its manager's command
    (`systemctl --user restart`, `sudo systemctl restart`, `sudo sv
    restart`, `sudo rc-service … restart`; NixOS as systemd system), then
    checks each is running again (the manager's own status command) and
    says so for each, exit 0 only when all are;
  - `NAME...` restarts only those, once; `--check` says whether each
    listed service is installed, restarting nothing; `--list` prints the
    list; `--add NAME MANAGER HOME` adds a line (the installer's way);
  - **asks before using `sudo`** (rubric I5), once for the run; `--yes`
    says yes; with no `sudo` and not root, says what is needed and
    restarts none of the ones that need it;
  - a listed home whose service is not installed (the owner has not run
    the printed commands yet) is said, not restarted.
- **The installer's last question**, `restart_homes` ("Restart every
  listed home now, so each runs this version?"), asked only when the
  list is not empty and `--check` passes.
- **`scripts/view-logs [service | home folder]`** (Bash): follows the
  service's log (`tail -F`); with `--running`, the home's own running
  logs instead (the starter's and each gatherer's, in its RAM folder,
  each line marked with whose); with no argument and one listed home,
  that one; with several, lists them and asks, never interleaving two
  homes (rmail's `view-logs.sh`, #612).

## Status

Not built yet.

## Rubric

From `notes/rmail-rubric/installing-and-services.md`: **I10** (an update
is finished when every home restarts; the list belongs to the machine,
not git), **I5** (asks before `sudo`), **I8** (one log per service);
referee 7.

## Where we differ

rmail builds `restart-mailboxes.sh` per machine from a template, with
the list inside the built script and the script ignored by git.  Here
the **script is tracked and the list is a file of its own**, ignored.

- **Gains:** the restart script updates with the project like any other
  file (no rebuild step, nothing to carry over); the list is three words
  a line that a person can read and edit; each home names its own
  manager, so a machine that changed managers still restarts both.
- **Costs:** one more file in the program folder (ignored).

## Referees

With the stand-in service-manager commands of 604 (scratch `PATH`,
scratch `HOME`):

1. **The list**: the installer adds one line per home set up as a
   service, none for a home not set up as one; a second install of the
   same home adds no second line; `git status` shows nothing new.
2. **Restart**: two listed homes (one systemd user, one runit) are each
   restarted with their own manager's command and checked running; exit
   0.
3. **Asks before `sudo`**: the runit home's restart asks once; "no"
   restarts none that need it and says so; `--yes` asks nothing.
4. **Not installed**: a listed home whose service file is not in place is
   said by `--check` and skipped by a restart, exit 1.
5. **Logs**: `view-logs <service>` follows that service's log;
   `--running` shows the home's running-log lines marked starter and
   gatherer; with two homes listed and no argument it asks which.

## Suggested Implementation Steps

1. The list and `.gitignore`; the installer's `--add` and its last
   question.
2. `restart-homes`; `view-logs`.
3. The referees.

## Blockers that are not the owner's

- As 604: no real service is restarted here; every referee uses the
  stand-ins.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **The list is a plain file in the program folder, ignored by git**
   (above), so it cannot reach the `code/` branches a home shares.
2. **Each line names its manager**, not one manager per machine: a home
   set up as a systemd user service and another as a system one restart
   differently on the same machine.
3. **`--running` reads the RAM folders through the home's code** (161's
   `home_ram`), as 603 does, so the folder is never worked out twice.

## Related documents

- `notes/rmail-rubric/installing-and-services.md`
- issues 604, 164 (the `code/` branch, its `.gitignore`)
