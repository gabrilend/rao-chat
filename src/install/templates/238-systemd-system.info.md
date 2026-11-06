# 238-systemd-system.service

A template of issue 604, filled by `src/install/236-service-files.lua` (its placeholders are listed there).  A systemd system service, `User=` the installing user: written to `<home>/service/<service>.service`, copied to `/etc/systemd/system/` by a person (the installer prints the commands).  `WantedBy=multi-user.target`, after `network-online.target`.

Every template starts with `# rao-chat home: <home>` (the line the installer reads to refuse a name already serving another home), runs `<project>/scripts/run-home <project> <home>` (603), appends its output to `<log folder>/<service>.log`, and restarts it when it fails.  The systemd ones are `KillMode=mixed` with `TimeoutStopSec=60`: the stop signal goes to the launcher alone, which stops the home's programs itself.
