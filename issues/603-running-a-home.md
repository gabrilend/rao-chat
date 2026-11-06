# 603 — Running a home: one command, both programs, a clean stop

**Phase:** 6 — Installation and running as a service
**Blocked by:** 602
**Blocks:** 604 to 606

## Current Behavior

A home is two programs started separately: the home starter (164),
which starts one gatherer per mailbox, and the device server (187).
Each stops on a `stop` file in its RAM folder; neither stops cleanly on
a signal (163's gatherers do: SIGTERM syncs once more).  A service
manager stops a service with SIGTERM, so a home stopped that way loses
the starter at once and may leave its gatherers running with nobody to
look after them, and nothing holds the two programs together: one can
die and the other run on.  Only the demos start a home, each with its
own code.

## Intended Behavior

- **`scripts/run-home [project] <home>`** (Bash), the one command that
  runs a home, in the foreground (rmail's `run-rmail.sh`):
  1. reads the home's environment file, `<home>/environment`, when there
     is one (602 writes it): `PATH`, `LUA_PATH` and `LUA_CPATH` lines
     only, any other line refused (rubric I9);
  2. finds `luajit` and `git` on that path, and says which is missing,
     exit 1;
  3. takes the home's lock, `<home>/.run-home.lock` (`flock`, 601): a
     second launcher for a home already running says so and exits 1,
     before starting anything;
  4. starts the starter (164) and the device server (187), each a child
     it waits on, their output to its own (the service manager's log);
  5. on SIGTERM, SIGINT or SIGHUP: touches the starter's `stop` and the
     device server's `stop` (their own ways to stop), waits up to
     `stop-wait` seconds (20) for both, then kills what is left and says
     so; exits 0 when both stopped of themselves;
  6. when either program ends without being asked, stops the other the
     same way and exits 1, so the service manager restarts the whole home
     (`Restart=on-failure`, 604) rather than half of it.
- **Every line it prints starts with the time and `run-home:`**, so its
  lines read apart from the programs' in one log.
- **The home's RAM folder is found the home's way** (161's `home_ram`
  of `gatherer.ram-root`), through a one-line call into the home's code,
  not worked out again in Bash.

## Status

Not built yet.

## Rubric

From `notes/rmail-rubric/installing-and-services.md`: **I8** (one log
per service; the launcher writes to standard output, which the service
sends to its file), **I9** (the service's environment), referee 6 (a
clean stop).  From the structure note, **R20** (one home per service).

## Where we differ

rmail's `run-rmail.sh` is three lines that `exec` the one daemon; the
service manager is its supervisor.  A rao-chat home is two programs, so
the launcher stays as their parent: it **turns the service manager's one
signal into each program's own way of stopping**, and it **ends the
home when half of it ends**, so the supervisor above still sees one
thing, running or not.

- **Gains:** 164 and 187 stay as they are (no signal handling added to
  either); a stop through any service manager is the same `stop` file a
  demo uses; one home is never run twice.
- **Costs:** one more process per home; a device server that crashes
  restarts the gatherers too (they sync once more and are back within
  the service manager's restart wait).

## Referees

Run in a loopback-only namespace of its own (`unshare -rn`), a home made
by 232 on 127.0.0.2:

1. **It runs a home**: the starter's state names its gatherer running,
   and the device port and the direct mailbox's port both accept a
   connection.
2. **SIGTERM stops it cleanly**: within the wait, the launcher exits 0,
   the gatherer's state says `stopped = asked`, and no process of the
   home is left.
3. **Half a home is no home**: the device server killed, the launcher
   stops the starter (its gatherer `stopped = asked`) and exits 1.
4. **Once per home**: a second launcher for the same home exits 1 saying
   it is running, and the first is untouched.
5. **What is missing is said**: an environment file whose `PATH` holds no
   `git`, exit 1 naming git, nothing started; a line other than the
   three, refused, naming the line.

## Suggested Implementation Steps

1. The launcher; the RAM folder through 161.
2. The referee, with the namespace and a 232-made home.

## Blockers that are not the owner's

- None.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **A launcher, not signal handling in 164 and 187**: the stop files are
   already how every demo and referee stops them, and they are tested;
   the launcher is the one new piece, and it is the same for every
   service manager.
2. **Bash** (the owner's list): waiting on two children and turning a
   signal into files is what a shell does in a few lines; LuaJIT would
   need the FFI for signals (as 163 does) for no gain.
3. **One lock per home** (`flock` on a file in the home folder): two
   launchers for one home would start two gatherers on one port; the
   second would fail to claim it, but only after the home's state had
   been overwritten.
4. **20 s to stop** before anything is killed: a gatherer syncs to disk
   and commits once more at its stop (211); 604's service files give the
   service manager 30 s, so the launcher's own deadline comes first.
5. **The environment file belongs to the home**, `<home>/environment`:
   a person running a home by hand and a service manager running it get
   the same paths.

## Related documents

- issues 164 (via 211), 187 (via 302), 211 (stop files), 215 (git)
- `notes/rmail-rubric/installing-and-services.md`
