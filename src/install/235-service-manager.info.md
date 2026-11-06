# 235-service-manager

Prints the one word naming this machine's service manager (issue 604):
`nixos`, `systemd`, `runit`, `openrc` or `unknown`, by rmail's rules,
first match wins: `/etc/NIXOS`; process 1's name (`systemd`, `runit`,
`openrc-init`); `systemctl`, `sv`, `rc-service` on the path.

    src/install/235-service-manager [--root=FOLDER]

`--root` is where `/etc/NIXOS` and `/proc/1/comm` are read (the referees'
scratch root).  It uses only the shell's own commands, so a bare `PATH`
is enough.  The installer's `--service-manager` overrides it.
