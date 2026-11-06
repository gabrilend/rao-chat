# 237-systemd-user.service

A template of issue 604, filled by `src/install/236-service-files.lua` (its placeholders are listed there).  A systemd user service: `~/.config/systemd/user/<service>.service`, enabled and started by the installer through `systemctl --user`.  `WantedBy=default.target`.

Every template starts with `# rao-chat home: <home>` (the line the installer reads to refuse a name already serving another home), runs `<project>/scripts/run-home <project> <home>` (603), appends its output to `<log folder>/<service>.log`, and restarts it when it fails.  The systemd ones are `KillMode=mixed` with `TimeoutStopSec=60`: the stop signal goes to the launcher alone, which stops the home's programs itself.
