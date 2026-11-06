# 239-runit-run

A template of issue 604, filled by `src/install/236-service-files.lua` (its placeholders are listed there).  A runit `run` script: written to `<home>/service/<service>/run`, copied to `/etc/sv/` and linked into `/var/service/` by a person.  Output appended to the log with `exec >>`; the launcher run through `chpst -u <user>`.  runit starts it again about a second after it ends (its own rule; there is no 5 s delay); `sv -w 60 stop` gives it the time to stop.

Every template starts with `# rao-chat home: <home>` (the line the installer reads to refuse a name already serving another home), runs `<project>/scripts/run-home <project> <home>` (603), appends its output to `<log folder>/<service>.log`, and restarts it when it fails.  The systemd ones are `KillMode=mixed` with `TimeoutStopSec=60`: the stop signal goes to the launcher alone, which stops the home's programs itself.
