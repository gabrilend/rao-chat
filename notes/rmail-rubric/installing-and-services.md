# rmail as a rubric: installing, and running as a service

Written 2026-11-06 for rao-chat's phase 6 (issues 601–606), following
`strategems/other-peoples-software-as-a-rubric.md`, as the four notes
beside it were for phase 2.  rmail (`/home/ritz/programs/r-mail`) was
read, not run, called or copied: `scripts/install.sh`,
`scripts/detect-service-manager.sh`, `scripts/.templates/services/*`,
`scripts/make-restart-script.sh`, `scripts/.templates/restart-mailboxes.sh`,
`scripts/view-logs.sh`, `scripts/test-service-templates.sh`,
`run-rmail.sh`, and the installer's issues (#102, #117, #601 to #616,
#620, #622), at rmail commit `8334e2e`.

Covers what rmail's installer does, the rules any installer for a home
server must keep (what the operating system and the service managers
require, and what rmail's bugs taught), the choices rmail made that
rao-chat need not, and the referees phase 6 is graded by.

---

## 1. What rmail's installer does

One Bash-compatible POSIX script, `scripts/install.sh`, top to bottom:

1. **Questions first, before anything is built** (#607): the mailbox
   folder, a local name, the port.  The config is written into the
   mailbox as soon as those are known, so a failure later loses nothing
   typed.  An existing config at that path is the only source of
   defaults (#102: "the mailbox is the installation"; no registry of
   mailboxes is read).
2. **An option store**: every prompt has a key; `--key=value`,
   `--flag`/`--no-flag` answer it and skip the prompt; `--silent` refuses
   to prompt (a missing value stops the run, naming the flag); `--yes`
   answers every yes/no prompt yes unless `--no-flag` says otherwise.
   Values come from the command line only: environment variables are
   ignored on purpose, "since stale exports from earlier sessions tend
   to produce surprising installs" (#603).
3. **A port suggested, never defaulted in code**: a random one from
   50000–65000, skipping a few well-known ones, checked against what
   `ss` or `netstat` says is listening (a warning, not a refusal: a
   stopped mailbox holds nothing).
4. **A firewall primer** (#605): what a port is, how to look at the
   machine's rules with each common tool, which port to open.
5. **Builds its dependencies from source** into `deps/` and `libs/`
   (Lua, OpenSSL, LuaSocket, Info-ZIP, the port-forwarding helpers),
   saving each one's licence beside the binary.
6. **Service setup**: one service per mailbox, for the machine's service
   manager (below).
7. **Docs built from templates** with the real paths (#614).
8. **Offers to restart every listed mailbox** so each runs the new code
   (#622).

### The service manager

`detect-service-manager.sh` prints one word, first match wins: `nixos`
(`/etc/NIXOS`), then process 1's name (`systemd`, `runit`,
`openrc-init`), then the first of `systemctl`, `sv`, `rc-service` on the
path, else `unknown`.  The installer, the docs builder and the restart
script all ask it, so they agree.

| manager | file written | who puts it in place |
|---|---|---|
| systemd, user | `~/.config/systemd/user/<service>.service`, enabled and started | the installer |
| systemd, system | `<checkout>/<service>.service` | the owner, with the printed `sudo` commands |
| runit | `<checkout>/<service>-run` | the owner (`/etc/sv/<service>/run`, linked into `/var/service/`) |
| OpenRC | `<checkout>/<service>-init` | the owner (`/etc/init.d/`, `rc-update add`) |
| NixOS | `<checkout>/<service>.nix` | the owner (imported in `configuration.nix`, `nixos-rebuild switch`) |

Each file is a template with `@NAME@` placeholders, filled by one
function that escapes every value (a path holding `|`, `&` or `\` comes
through unchanged, #611) and refuses to leave a file holding a
placeholder it could not fill.  Services restart on failure after 5 s
and append their output to `/tmp/<service>.log` (#117: RAM, no disk
wear, nothing on the login screen).

### After installing

- `run-rmail.sh <config>` starts a daemon in the foreground with the
  bundled Lua if one was built, else the first system Lua found.
- `scripts/restart-mailboxes.sh` restarts every service on a list kept
  at its own top; it is built per machine from a template, untracked by
  git, so the list survives updates (#622).  `--add`, `--check`.
- `scripts/view-logs.sh` follows a service's log, choosing among
  several rather than interleaving them, and falls back to the journal.

---

## 2. Rules (what any correct answer must keep)

| # | rule | why | where rmail learned it |
|---|---|---|---|
| I1 | **One service per home, named after its path; refuse a name another home's service already holds, with no automatic second choice.** | Two installs with one name replace each other silently. | #612 (R20 of the structure note) |
| I2 | **Ask first, write the config as soon as its required values are known; later steps only amend it.** | A failure late in the run otherwise loses everything typed. | #607 |
| I3 | **Every prompt answerable from the command line; an unattended run never stops to ask and never guesses a value it cannot know.** | Configuration management and portable drives run it with nobody there. | #603 |
| I4 | **No default port and no default identity in code; a suggested port is checked against what is listening.** | A default only fires on a mistake, and then collides. | #382 (R10) |
| I5 | **Never raise privileges.  Write what needs root into the user's own folders and print the commands.** | An installer that runs `sudo` on its own is a surprise with root's reach. | install.sh "SERVICE SETUP" |
| I6 | **Every value put into a file is escaped for the tool that puts it there; a placeholder left over stops the run and removes the file.** | Paths with `&`, `|` or `\` were mangled on one machine and not another. | #611, #614 |
| I7 | **Re-running is safe: work already done is skipped, files a person edited are never overwritten, and a changed value is said.** | Re-running is how rmail is updated. | install.sh header; hooks "never overwritten once present" |
| I8 | **A service's output goes to a file in RAM, one per service, never to the console.** | Start-up lines covered the login prompt; two daemons in one file cannot be told apart. | #117, #612 |
| I9 | **The service's environment is not the installer's.** | A Lua found through the installer's own paths was not found by the service (system Lua with a project-local LuaSocket). | #609 |
| I10 | **A running program keeps the code it started with; an update is finished only when every home restarts, and the list of homes belongs to the machine, not to git.** | Mailboxes ran four hours of old code after an update, with nothing saying so. | #622 |
| I11 | **Report what was found, not what was expected.** | The installer printed a hard-coded Lua version. | #604 |
| I12 | **Interactive input gets line editing.** | Arrow keys typed `^[[A` into a path. | #602 |

---

## 3. rmail's choices that rao-chat need not make

| choice | what it buys rmail | rao-chat |
|---|---|---|
| builds Lua, OpenSSL and LuaSocket from downloaded sources | runs on a machine with only a compiler | the owner's preference is vendored local libraries and no package managers; phase 6 names what is missing instead of fetching it (601) |
| one daemon process per mailbox | the service is the program | a rao-chat home is two programs (the home starter with its gatherers, and the device server): something must hold them together under one service (603) |
| generated files written into the checkout | one place to look | the checkout is committed to each mailbox's `code/` branch (215): generated files belong in the home folder instead (604) |
| restart list kept inside a script built per machine | no other file | a list file the restart script reads, ignored by git (605) |
| docs built from templates | the guide names the real paths | the installer prints the commands with the real paths; no built docs (604) |
| a portable mailbox drive (#616) | carry a mailbox between machines | not in phase 6 |
| launchd for macOS (#620) | macOS | rao-chat reads `/proc` and uses Linux namespaces in its tests: Linux only for now |

---

## 4. Referees (written from the rules, grading phase 6)

1. **Unattended install** (I3, I4): `--silent` with every required value
   makes a home that opens and holds every setting the modules declare;
   `--silent` missing one stops before writing, naming the flag; no port
   is ever chosen without being given or shown.
2. **Re-run** (I2, I7): a second run with the same answers changes no
   byte of the home; a hand-edited config line survives; a new answer is
   written and said.
3. **Templates** (I6): every service template fills with nothing left,
   a path holding `| & \` and a space comes through unchanged, and a
   template asking for an unknown value writes no file.
4. **Clash** (I1): a service of the same name serving another home stops
   the install with nothing written.
5. **No privilege** (I5): nothing is written outside the home folder,
   the program folder's ignored list, and (systemd user services only)
   the user's own `~/.config/systemd/user`.
6. **A clean stop** (I8 and 603): the service's stop signal reaches every
   process of the home, each gatherer syncs once more, and nothing is
   left running.
7. **Restart** (I10): every listed home is restarted with its manager's
   command and checked running again; a listed home not installed is
   said, not restarted.
