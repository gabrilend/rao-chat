# install-home

The installer (issues 602, 604, 605): makes a rao-chat home on this
machine, or brings one up to date.  Run from any folder; the program
folder is the one the script is in (`--project=<folder>` for another).

| step | what |
|---|---|
| 1 | LuaJIT on the path, then `src/install/230-what-a-home-needs.lua`: a missing required thing stops it, nothing written |
| 2 | the questions: `--home`, `--home-name`, `--device-port`, `--direct-port`, `--address`, `--setup-service`, and on systemd `--user-service` (each flag skips its question); a service name already serving another home stops it here, nothing written |
| 3 | the home, through `src/install/232-make-home.lua`: the answers set, every other setting stated with its question, the direct-message mailbox on its port |
| 4 | `<home>/environment`: the `PATH` (and `LUA_PATH`, `LUA_CPATH` when set) the home's programs run with |
| 5 | the service (604), when asked for: its file filled from `src/install/templates/` by `src/install/236-service-files.lua`; a systemd user service enabled and started, a system service's install commands printed |
| 6 | the home's ports, a firewall primer, how to pair a phone or a browser, where the page's folder is, the service, how to run the home by hand |

- `--silent` never asks: a value it cannot know (the home, its name, both
  ports, the address) must be given, or it stops naming the flag, before
  writing anything.  `--yes` answers yes/no questions yes.  Values come
  from the command line only.
- No default port: asked, a free port in 50000-65000 is suggested
  (checked with `ss` or `netstat` when either is there); a port something
  listens on is refused, unless it is one this home already holds.
- Re-running with the same answers changes no byte; a new answer is
  written and said (`changed`, `moved`); hand edits are kept.
- The service (604): the manager is found by
  `src/install/235-service-manager` or named by `--service-manager`; the
  name is `rao-chat-<home path, slashes as dashes>` or `--service-name`;
  the log is `<--log-dir, /tmp>/<service>.log`.

  | manager | file | then |
  |---|---|---|
  | systemd, user | `~/.config/systemd/user/<service>.service` | `systemctl --user daemon-reload`, `enable`, `start` (not with `--no-start-service`); `loginctl enable-linger` named |
  | systemd, system | `<home>/service/<service>.service` | the `sudo` commands printed |
  | runit | `<home>/service/<service>/run` | printed |
  | OpenRC | `<home>/service/<service>.init` | printed (paths of plain characters only: OpenRC evals them) |
  | NixOS | `<home>/service/<service>.nix` | printed |
  | unknown | nothing | said, with `scripts/run-home` |

  A file of the service's name (under `~/.config/systemd/user/`, or
  `--system-root`'s `etc/systemd/system/`, `etc/sv/`, `etc/init.d/`)
  whose `# rao-chat home:` line names another home stops the installer,
  exit 1, nothing written; one naming this home is written again.
- It writes nothing outside the home folder but a systemd user service's
  file (and the log folder, when `--log-dir` names one that is missing),
  and never raises its own privileges.

Exit status: 0 made or up to date, 1 not (and why), 2 a mistaken argument.
