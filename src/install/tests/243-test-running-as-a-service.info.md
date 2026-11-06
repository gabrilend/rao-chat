# 243-test-running-as-a-service.lua

Issue 604's referees, through the stand-in service managers (242), a
scratch `HOME`, a scratch system root and a scratch log folder, in a
loopback-only namespace (it runs itself again under `unshare -rn`).

1. Templates: all five fill with no placeholder left and name run-home,
   the program folder, the home and the log; a home and program folder
   holding a space, `&`, `|` and `\` are read back unchanged by systemd's
   rules (both units), nix's string rules and sh (runit's `run` run with a
   stand-in `chpst`); OpenRC's plain paths come back through `eval`, and
   hard ones are refused with the old file removed; an unknown
   placeholder, a service name or log folder with a space, and a home
   with a newline are refused.
2. Detection: `/etc/NIXOS`; process 1 named systemd, runit, openrc-init;
   `rc-service`, `sv`, `systemctl` on the path; else unknown.
3. The systemd user service: under the scratch `HOME`; `daemon-reload`,
   `enable`, `is-active`, `start` in that order; `--no-start-service`
   runs none; the log folder made.
4. runit, OpenRC, NixOS and systemd-system: the file in `<home>/service/`,
   the commands printed, no command of a manager (nor `sudo`) run,
   nothing in the scratch `HOME` or under the system root.
5. The clash: a system unit of the same name naming another home stops
   the installer (exit 1, the home not made); one naming this home is
   written again and said; `--service-name` naming another home's user
   unit is refused, that file and this home untouched.
6. The service runs the home: started by the stand-in in a bare
   environment, both ports answer; the stop (SIGTERM to the launcher)
   ends it with status 0, the launcher's log says everything stopped when
   asked, nothing is left, the ports close.

`luajit src/install/tests/243-test-running-as-a-service.lua [project folder]`.
