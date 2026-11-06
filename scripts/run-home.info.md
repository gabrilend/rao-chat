# run-home

Runs one home in the foreground (issue 603): its starter (164, with a
gatherer per mailbox) and its device server (187), held together as one
thing.  A service manager runs it (604); so can a person.

    scripts/run-home [project] <home> [--stop-wait=SECONDS]

| step | what |
|---|---|
| environment | `<home>/environment`: `PATH`, `LUA_PATH`, `LUA_CPATH` lines only (blank and `#` lines skipped); any other line refused, naming it |
| tools | `luajit`, `git`, `flock`, `setsid` on that path, or exit 1 naming the missing ones |
| lock | `flock` on `<home>/.run-home.lock`: a home already running is said, exit 1, nothing started |
| start | a stale `stop` file removed; the starter and the device server each started with `setsid` (a Ctrl-C reaches the launcher alone) |
| stop | SIGTERM, SIGINT or SIGHUP: both `stop` files touched, up to `--stop-wait` seconds (20) waited, then SIGKILL for what is left and SIGTERM (then SIGKILL) for any gatherer still running; exit 0 when everything stopped when asked, 1 otherwise |
| half a home | either program ending without being asked: the other stopped the same way, exit 1, so the service manager restarts the whole home |

The home's RAM folder is found by the home's own code (161's `home_ram`
of `gatherer.ram-root`).  Every line starts with the time and
`run-home:`.  Exit 2 for a mistaken argument.
