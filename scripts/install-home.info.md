# install-home

The installer (issues 602, 604, 605): makes a rao-chat home on this
machine, or brings one up to date.  Run from any folder; the program
folder is the one the script is in (`--project=<folder>` for another).

| step | what |
|---|---|
| 1 | LuaJIT on the path, then `src/install/230-what-a-home-needs.lua`: a missing required thing stops it, nothing written |
| 2 | the questions: `--home`, `--home-name`, `--device-port`, `--direct-port`, `--address` (each flag skips its question) |
| 3 | the home, through `src/install/232-make-home.lua`: the answers set, every other setting stated with its question, the direct-message mailbox on its port |
| 4 | `<home>/environment`: the `PATH` (and `LUA_PATH`, `LUA_CPATH` when set) the home's programs run with |
| 5 | the home's ports, a firewall primer, how to pair a phone or a browser, where the page's folder is, how to run the home |

- `--silent` never asks: a value it cannot know (the home, its name, both
  ports, the address) must be given, or it stops naming the flag, before
  writing anything.  `--yes` answers yes/no questions yes.  Values come
  from the command line only.
- No default port: asked, a free port in 50000-65000 is suggested
  (checked with `ss` or `netstat` when either is there); a port something
  listens on is refused, unless it is one this home already holds.
- Re-running with the same answers changes no byte; a new answer is
  written and said (`changed`, `moved`); hand edits are kept.
- It writes nothing outside the home folder and never raises its own
  privileges.

Exit status: 0 made or up to date, 1 not (and why), 2 a mistaken argument.
