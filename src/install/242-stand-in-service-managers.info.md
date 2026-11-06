# 242-stand-in-service-managers.lua

Stand-ins for the service managers' commands (issue 604), for the
referees (243) and the phase 6 demo (606): no real service is installed.

    luajit src/install/242-stand-in-service-managers.lua make <state>

makes `<state>/bin` (`systemctl`, `sv`, `rc-service`, `rc-update`,
`loginctl`, `nixos-rebuild`, `sudo`, `whoami`, each a small sh script
calling this file) and `<state>/root`, and prints the bin folder to put first on a
`PATH`.  Every call but `whoami`'s is written to `<state>/calls`.

- `systemctl [--user] start <unit>` reads the unit (`--user`: under
  `$HOME/.config/systemd/user/`; else `<state>/root/etc/systemd/system/`)
  and runs its `ExecStart` as systemd would: its quoting read back, a
  bare environment (systemd's `PATH`, `HOME`, its `Environment=`), output
  appended to its `StandardOutput=append:` file.  The pid and, later,
  the exit status go to `<state>/<unit>.pid` and `.status`.
- `stop`: SIGTERM to that process alone (`KillMode=mixed`), SIGKILL after
  `TimeoutStopSec`; prints the exit status.  `restart`, `is-active`.
  `daemon-reload`, `enable`, `disable` are only written down.
- `sv` and `rc-service` keep each service's run state in
  `<state>/<command>-<name>` (`restart`, `start`, `stop`) and say it on
  `status` in the manager's words; nothing is run.
- `sudo` is written down and runs its command as this user, so a referee
  sees whether it was used and for what (605).
- `whoami` prints `<state>/user` when that file exists: a referee that is
  root in its namespace plays someone who is not.

Required as a module it gives `unit_words`, systemd's reading of an
`ExecStart=` value.  It does not restart a failed service.
