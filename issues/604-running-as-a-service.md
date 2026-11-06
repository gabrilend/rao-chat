# 604 — Running as a service: one service per home, for the machine's service manager

**Phase:** 6 — Installation and running as a service
**Blocked by:** 603
**Blocks:** 605, 606

## Current Behavior

A home runs only while someone keeps `scripts/run-home` (603) open.
Planning section 12, phase 6: "Installation and running as a service —
as rmail's installer does."  rmail's installer ends by offering to set
the mailbox up as a service of whichever service manager the machine
runs (rubric note, section 1, "The service manager").

## Intended Behavior

- **Which service manager**: `src/install/235-service-manager` (Bash)
  prints one word by rmail's rules, first match wins: `nixos`
  (`/etc/NIXOS`), process 1's name (`systemd`, `runit`, `openrc-init`),
  the first of `systemctl`, `sv`, `rc-service` on the path, else
  `unknown`.  The installer's `--service-manager=<word>` overrides it.
- **One service per home** (rubric I1, R20), named
  `rao-chat-<home path, slashes as dashes>` (`/home/ritz/rao-home` →
  `rao-chat-home-ritz-rao-home`), or `--service-name`.  A service of that
  name already installed for another home (its file does not name this
  home) stops the installer with nothing written, and no second name is
  chosen for it.
- **One template per kind**, `src/install/templates/<index>-<kind>`, with
  `@NAME@` placeholders: systemd user, systemd system, runit, OpenRC,
  NixOS.  Each runs `<project>/scripts/run-home <project> <home>` (603),
  restarts it on failure after 5 s, appends its output to
  `<log folder>/<service>.log` (`/tmp` by default: RAM, rubric I8), and
  gives it 60 s to stop.  systemd's are `KillMode=mixed`, so the stop
  signal goes to the launcher alone and it stops the rest (603).
- **Filled by one function** that escapes every value for `sed` (I6) and
  refuses, removing the file, when a placeholder is left.
- **Where the files go** (I5: never raise privileges):

  | manager | written to | then |
  |---|---|---|
  | systemd, user (`user_service` yes) | `~/.config/systemd/user/<service>.service` | `systemctl --user daemon-reload`, `enable`, `start` (not with `--no-start-service`); `loginctl enable-linger` named |
  | systemd, system | `<home>/service/<service>.service` | the `sudo` commands printed |
  | runit | `<home>/service/<service>/run` | printed: copy to `/etc/sv/`, link into `/var/service/` |
  | OpenRC | `<home>/service/<service>.init` | printed: copy to `/etc/init.d/`, `rc-update add` |
  | NixOS | `<home>/service/<service>.nix` | printed: import in `configuration.nix`, `nixos-rebuild switch` |
  | unknown | nothing | said, with `scripts/run-home` to run it by hand |

- **The question** `setup_service` ("Set this home up to run as a
  service?") and, on systemd, `user_service`, each answerable by flag;
  `--yes` says yes to both.
- **Every service runs with the home's environment file** (602, 603),
  never with the service manager's bare path (rubric I9).

## Status

Built 2026-11-06 on branch `claude/604-running-as-a-service`:

- `src/install/235-service-manager` (Bash): the word, by rmail's rules;
  `--root` for the referees.
- `src/install/236-service-files.lua`: the name, the filler (`fill`,
  `check`) with a quoting per syntax, and `names-home`.
- `src/install/templates/237-systemd-user.service`,
  `238-systemd-system.service`, `239-runit-run`, `240-openrc-init`,
  `241-nixos.nix`.
- `src/install/242-stand-in-service-managers.lua`: the stand-ins.
- `scripts/install-home`: the service questions (`--setup-service`,
  `--user-service`), the flags `--service-manager`, `--service-name`,
  `--log-dir`, `--system-root`, `--no-start-service`, the clash check
  before anything is written, and step 5, the service.
- Referees: `src/install/tests/243-test-running-as-a-service.lua`, 45
  checks, all passing.  Five mutations were each caught (systemd's `\`
  left unescaped; the clash check skipped; `enable` not asked for;
  OpenRC filled with any path; `/etc/NIXOS` not looked at).
- 233 and 234 now pass `--no-setup-service` (under `--silent` the new
  question must be answered, as every other).

## Rubric

From `notes/rmail-rubric/installing-and-services.md`: **I1** (one
service per home, clash refused), **I5** (never raise privileges),
**I6** (escaping, no placeholder left), **I8** (the log in RAM, one per
service), **I9** (the service's environment); referees 3, 4 and 5.

## Where we differ

- **Generated files go in the home, not the program folder**
  (`<home>/service/`).  The program folder is committed to every
  mailbox's `code/` branch at start-up (215) and shared with an
  upstream; a service file there would carry this machine's paths and
  user name into it.  The home folder is already "the installation"
  (rmail's #102 said it of the mailbox).
- **One template for NixOS**, not two: the launcher finds `luajit`
  through the home's environment file, so the module names the launcher,
  not a store path of Lua.  After a NixOS upgrade moves `luajit`,
  re-running the installer rewrites the environment file.
- **`KillMode=mixed`**: rmail's daemon is one process and is stopped by
  the signal itself; a home is several, and only the launcher knows how
  to stop them.
- **No built guide** (rmail #614): the installer prints the commands
  with the real paths, and this issue and `scripts/install-home.info.md`
  are the guide.

## Referees

1. **Templates**: each of the five fills with no placeholder left; a
   home path and project path holding a space, `&`, `|` and `\` come
   through unchanged where the syntax can carry them, and OpenRC refuses
   them (decision 7); each names `run-home`, the project, the home and
   the log; a template asking for an unknown value writes no file.
2. **Detection**: the word is one of the five (`nixos`, `systemd`,
   `runit`, `openrc`, `unknown`); `--service-manager` overrides it.
3. **systemd user service, through a stand-in `systemctl`** (a script on
   a scratch `PATH`, scratch `HOME`): the unit is written under the
   scratch `HOME`, and `daemon-reload`, `enable` and `start` are asked
   for, in that order; `--no-start-service` asks for none.
4. **System services**: runit, OpenRC, NixOS and systemd-system each
   write into `<home>/service/` and print the commands; nothing outside
   the scratch home is written and no `sudo` is run.
5. **Clash**: a stand-in installed service of the same name serving
   another home stops the installer, exit 1, nothing written; one serving
   this home is updated and said.
6. **The service runs the home**: the stand-in `systemctl start` runs the
   unit's `ExecStart` with its `Environment`; the home answers on its
   ports; `systemctl stop` (SIGTERM to the launcher) stops it cleanly
   (603's referee 2).

## Suggested Implementation Steps

1. 236, the templates, and the installer's service section.
2. A stand-in for the service managers' commands, for the referees and
   606.
3. The referees.

## Blockers that are not the owner's

- No real service is installed here: every referee uses the stand-in,
  a scratch `HOME`, and a scratch `--log-dir`.  A real install on the
  owner's machine is the check left for a person.
- This machine has no real systemd, runit, OpenRC or Nix (its
  `systemctl`, `sv` and `rc-service` are stub scripts), so no template
  was read by its real manager: systemd's and nix's quoting were read
  back by the referee's own reading of their rules, runit's by `sh`, and
  OpenRC's `eval` by `sh`.  `systemd-analyze verify` on the owner's
  machine is the first check to make.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **Service files are written into `<home>/service/`** (above: the
   program folder is shared through `code/` branches).
2. **systemd user service by default when systemd is found** (asked; yes
   under `--yes`): it is the one kind the installer can start without
   root, as rmail's.
3. **`--service-manager`, `--log-dir` and `--system-root`** are flags for
   a person and for the referees: the first overrides detection, the
   second where logs go, the third where the clash check looks for
   installed services (`/` by default).  The installer still writes only
   where the table says.
4. **The service name keeps rmail's slug rule** (slashes to dashes, the
   leading one dropped) with `rao-chat-` in front, and is checked as
   rmail checks it (letters, digits, `-`, `_`).
5. **NixOS opens the firewall for nothing**: rmail's module opens its
   one port; a home's ports are several and change as rooms are made, so
   the printed commands name the ports to open instead.

### While building, 2026-11-06

6. **60 s to stop, not 30** (`TimeoutStopSec=60`, OpenRC's
   `retry=TERM/60/KILL/5`, `sv -w 60 stop`): the launcher waits up to
   20 s for its programs, then up to 10 s for each gatherer it has to
   stop itself; 30 s could kill it while it is still stopping a home
   cleanly.
7. **Each value is quoted the way its syntax reads it** (`236`), not by
   one `sed` escape: systemd's `ExecStart=` words double-quoted (`\`,
   `"`, `%`, `$` escaped), nix's string escapes on top of that, sh's
   single quotes for runit.  **OpenRC refuses** a program folder or home
   whose path holds anything but letters, digits, `.`, `_`, `+`, `-` and
   `/`: OpenRC reads `command` and `command_args` through `eval`, which
   splits a path at its spaces, and this cannot be checked here without
   OpenRC.  The installer checks this before writing anything and says
   so.  The log folder and the service name are held to plain characters
   for every kind (`StandardOutput=append:` takes the rest of the line
   bare).
8. **A home path's other characters become `_` in the derived name**
   (`/srv/a b` → `rao-chat-srv-a_b`), so the installer can suggest a name
   for any home; a `--service-name` given is checked and refused as
   rmail's is.
9. **The clash check looks where each kind is installed** (the user
   unit's place, and under `--system-root`: `etc/systemd/system/`,
   `etc/sv/<name>/run`, `etc/init.d/`), reading the `# rao-chat home:`
   line every template starts with.  A NixOS module imported from
   elsewhere is not found by it (there is no one place to look).
10. **A user service already running is not restarted** by the
   installer: it says so and prints `systemctl --user restart`, so
   re-running the installer never stops a running home by surprise
   (restarting every home after an update is 605's).
11. **Under `--silent` the service question must be answered**
   (`--setup-service` or `--no-setup-service`), as rmail's: an unattended
   install never sets up, or skips, a service silently.  `--yes` answers
   both questions yes.
12. **A missing `--log-dir` folder is made** by the installer and said:
   the service manager appends to a file but makes no folder.

## Related documents

- `notes/rmail-rubric/installing-and-services.md`;
  `notes/rmail-rubric/structure-and-defences.md` R20
- issue 603 (the launcher), 215 (`code/` branches)
