# 240-openrc-init

A template of issue 604, filled by `src/install/236-service-files.lua` (its placeholders are listed there).  An OpenRC init script under `supervise-daemon` (`respawn_delay=5`): written to `<home>/service/<service>.init`, copied to `/etc/init.d/` and added with `rc-update` by a person.  `retry=TERM/60/KILL/5`.  OpenRC evals `command` and `command_args`, so only plain paths are filled.  Not tried on a real OpenRC here.

Every template starts with `# rao-chat home: <home>` (the line the installer reads to refuse a name already serving another home), runs `<project>/scripts/run-home <project> <home>` (603), appends its output to `<log folder>/<service>.log`, and restarts it when it fails.  The systemd ones are `KillMode=mixed` with `TimeoutStopSec=60`: the stop signal goes to the launcher alone, which stops the home's programs itself.
