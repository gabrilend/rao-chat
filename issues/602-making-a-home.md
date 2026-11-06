# 602 — Making a home: the installer's questions and the home's config

**Phase:** 6 — Installation and running as a service
**Blocked by:** 601
**Blocks:** 603 to 606

## Current Behavior

A home (rao-home: `config`, `mailboxes`, `ignore`, `rooms/`, `people/`)
is made only by code: `open_home` (002) makes the folder, and every
demo and referee then sets each setting with `set_config`, taking the
first variant of every module's options file (201's `first_variants`)
and its own ports and addresses.  Every setting has no default, so a
home made by hand needs some 36 lines written correctly before its
starter will run.  A person cannot make a home without writing Lua.

## Intended Behavior

The owner (2026-09-27): "the user never needs to touch the filesystem
at all, except for pointing out where to store the mailboxes"; and on
config, "a stated value in the file, not a silent default in code".

- **`scripts/install-home`** (Bash), the installer, asks and then makes
  the home.  The questions, each with a key that a command-line flag can
  answer (rubric I3):

  | key | question | suggestion shown |
  |---|---|---|
  | `home` | Where should this home keep its mailboxes? | `~/rao-home` |
  | `home_name` | This home's name, as anyone sharing an upstream sees it (`git.home-name`) | the login name |
  | `device_port` | The port your phones and browsers connect to (`devices.port`) | a random free port |
  | `direct_port` | The port other homes send your direct messages to (the direct-message mailbox) | a random free port |
  | `address` | The address the home listens on (`gatherer.address`, `devices.address`) | `any` |

  Optional values with no question (flags only): `ram_root`
  (`gatherer.ram-root`).
- **An option store as rmail's** (rubric section 1, step 2):
  `--key=value` and `--key value`; `--silent` never prompts and stops,
  naming the flag, when a value it cannot know is missing; `--yes`
  answers every yes/no question yes unless `--no-<flag>`; values from
  the command line only, never from the environment.  Line editing at
  every prompt (I12).
- **No port is chosen without being shown or given** (I4): a suggested
  port is random in 50000–65000, not one already listening (`ss` or
  `netstat`, 601), never equal to the other one asked; under `--silent`
  both ports must be given.  A given port already listening is a warning
  (a stopped home holds nothing), and the two ports equal, or either
  equal to a mailbox port of the same home, is refused.
- **The home is written through the home's own code**:
  `luajit src/install/232-make-home.lua <project> <home> key=value ...`
  opens the home (002), sets the answered settings, writes **every
  other declared setting** that is not yet set with its first variant
  from the module's options file, under a comment holding the options
  file's question and the number of variants (`scripts/tally-options`
  shows them all), and makes the direct-message mailbox on its port
  (`make_mailbox`), or moves it to a new port when one is given.  It
  prints one line per setting: `set`, `kept` or `stated`.
- **The home's environment file**, `<home>/environment`, which the
  launcher (603) and every service (604) run with: `PATH` holding the
  folders of the `luajit`, `git` and `flock` that 601 found, then
  `/usr/local/bin:/usr/bin:/bin`; `LUA_PATH` and `LUA_CPATH` only when
  the installer's own environment has them, with a line saying so
  (rubric I9: a service does not see the installer's shell).  Rewritten
  on every run, since what was found can move (a system upgrade).
- **Written early** (I2): the home is written as soon as the questions
  are answered, before anything else the installer does.
- **Re-running is safe** (I7): an existing home's config gives the
  suggestions; a setting already in the file is kept unless a new value
  was given or typed, and a change is said (`changed devices.port 51000
  → 52000`); a line the person wrote by hand is kept, comments and
  order included (002's `set_config` rewrites one line in place).
- **At the end** it prints the home's folder, its ports, a firewall
  primer naming the device port and every mailbox port (rmail #605), how
  to pair a phone or a browser (`189 add <label> [--browser]`), where the
  page's folder is (`src/web`, 401 decision 1), and how to run the home
  (603) or set it up as a service (604).
- **Before anything is written**, 601's check runs; a missing required
  thing stops the installer with exit 1 and nothing written.  LuaJIT
  itself is looked for by the Bash first.

## Status

Not built yet.

## Rubric

From `notes/rmail-rubric/installing-and-services.md`: **I2** (write
early), **I3** (every prompt from the command line; never guess under
`--silent`), **I4** (no default port), **I7** (re-running is safe),
**I9** (LuaSocket found only through `LUA_PATH`/`LUA_CPATH` is written
into the home's environment file, 603), **I12** (line editing).

## Where we differ

rmail's installer writes its config with a heredoc in Bash and sets lines
with `awk`.  Here **the home's own code writes the home**: Bash only asks;
232 calls `open_home`, `set_config` and `make_mailbox`, so a config the
installer writes is one 002 has already read back and accepted, and a
setting a module adds later is written by the next re-run without the
installer changing.

- **Gains:** one writer of the config format; every declared setting is
  stated in the file with its question beside it; no second parser.
- **Costs:** the installer needs LuaJIT before it can write anything (it
  needs it anyway to run the home).

## Referees

1. **Unattended**: `--silent` with every required value makes a home
   that 002 opens, holding every setting the modules declare, the asked
   ones as given, the rest as the first variants with their comments;
   the direct-message mailbox on its port.
2. **`--silent` missing a value** stops before anything is written,
   naming the flag (`--device-port`), exit 1; the home folder is not
   made.
3. **Ports**: equal ports refused; a port held by a listener warned and
   (under `--silent`) refused; a suggestion is never a listening port.
4. **Re-run**: the same answers change no byte of the home; a
   hand-written comment and a hand-changed setting survive; a new
   `--device-port` is written and said as changed; a new
   `--direct-port` moves the mailbox.
5. **Nothing but the home** is written: the scratch `HOME` and the
   program folder are as they were (git status clean), apart from the
   home folder.
6. **A missing need stops it**: with 601 made to fail, exit 1 and no
   home folder.
7. **Escaping**: a home path holding a space, `&`, `|` and `\` is made
   and named correctly in the summary.

## Suggested Implementation Steps

1. 232, the writer, with `--show` (the current values the installer
   offers as suggestions).
2. The installer's option store, questions and summary.
3. The referees, running the installer with a scratch `HOME`.

## Blockers that are not the owner's

- None.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **Five questions, not more.**  The owner's words above limit what a
   person is asked to where the mailboxes are kept; the ports must be
   asked because there is no default port (owner: "no default port
   numbers"), the name because it is seen by others (below), the address
   because two homes on one machine need their own.  Every other setting
   is stated in the file from its options file's first variant, which is
   what every demo home already runs with.
2. **The suggested name is the login name**, not the options file's
   `home`: `git.home-name` names the `code/` and `running-log/` branches
   a shared upstream receives (215, 215a), and two homes both called
   `home` would write the same branches.  The prompt says who sees it.
3. **A suggested port, never a default** (rmail's way): shown at the
   prompt, random, checked against what is listening; under `--silent`
   there is nothing to show it to, so both ports must be given.
4. **The direct-message mailbox is made at install**, since every home
   has exactly one and it needs a port; tree mailboxes are made with
   their rooms, later, from the viewer.
5. **`address` sets both `gatherer.address` and `devices.address`**: one
   machine, one answer; a person wanting them apart edits the config,
   and re-running keeps the edit unless `--address` is given again.
6. **The project folder is the one the installer is in**, found from its
   own path, not a folder named at the top of the script: the service
   (604) must run the program the person actually installed from.
   Another folder can be given with `--project`.
7. **The installer's own language is Bash** (the owner's list: Lua,
   Bash, C), as rmail's; every write goes through 232 (Lua).

## Related documents

- `notes/rmail-rubric/installing-and-services.md`
- `notes/vision-planning.md`, "The server's shape, the outside port, and
  rooms as git history (2026-09-27)" (the owner's words above) and "Git
  per mailbox, signatures settled, sharing edits (2026-09-27)" (stated
  values in config)
- issues 211 (the home and its RAM folders), 303 (pairing), 401
  (the page's folder)
