# 601 — What a home needs, found or named

**Phase:** 6 — Installation and running as a service
**Blocked by:** 409 (phase 4 complete)
**Blocks:** 602 to 606

## Current Behavior

A home runs only on a machine that happens to have what its programs
load: LuaJIT (its `ffi` and `bit`), LuaSocket built for LuaJIT
(`require("socket")` in 28 files), OpenSSL's `libcrypto` reached through
the FFI (`ffi.load("crypto")` in 124), and git (215: the starter and
each gatherer exit without it).  Nothing checks for them before a home
is started, so a missing one is found by a program stopping with a Lua
error.  rmail's installer builds the missing ones from downloaded
sources (rubric note `installing-and-services.md`, section 1, step 5).

## Intended Behavior

- **One check, `luajit src/install/230-what-a-home-needs.lua [project]`**,
  that loads each thing the way the home's programs load it and prints
  one line for each, found or missing, with what it is for:

  | need | how it is checked | required |
  |---|---|---|
  | LuaJIT | the check itself runs on it: `jit.version`, `ffi`, `bit` | yes |
  | LuaSocket | `require("socket")` with the project's own `libs/` first (001), its version and where `socket.core` was found | yes |
  | libcrypto | `ffi.load("crypto")`, its version string, and AES-256-GCM and SHA-256 asked for by name, as 124 asks | yes |
  | git | `git --version` | yes |
  | a RAM folder | `/dev/shm` exists and can be written (161 falls back to `/tmp` and says so) | no: a note |
  | `flock` | on the path (603's one-home-one-launcher lock) | yes |
  | `setsid` | on the path (603 starts the home's programs in a session of their own; added while building 603) | yes |
  | the usual tools | `find`, `sort`, `ls`, `mkdir`, `rm`, `mv`, `cp`, `touch`, `chmod`, `stat`, `kill`, `sleep` on the path (the programs run them through the shell; 001 lists `src/` with `find` and `sort`) | yes |
  | `ss` or `netstat` | on the path (602's port check) | no: the check is skipped and said |
  | Node 22 or later | `node --version` | no: only the web page's referees and the phase 4 demo |
  | `unshare` | on the path | no: only the referees and demos |

- **What was found is reported as found** (rubric I11): the version
  each thing gives, never one expected.
- **A missing thing is named with what needs it** and what to do in
  words ("install LuaSocket for LuaJIT with your system's packages, or
  put its `socket.lua` and `socket/core.so` in `<project>/libs/`"); the
  check fetches and builds nothing (decision 1).
- **Exit status**: 0 when every required thing is found, 1 otherwise;
  `--quiet` prints only what is missing.
- The installer (602) runs this first and stops when it says 1, before
  writing anything.

## Status

Built 2026-11-06: `src/install/230-what-a-home-needs.lua`; referees in
`src/install/tests/231-test-what-a-home-needs.lua` (1 to 5 pass, with
their broken versions).

## Rubric

From `notes/rmail-rubric/installing-and-services.md`: **I11** (report
what was found, not what was expected) and **I9** (the service's
environment is not the installer's: the check reports where LuaSocket
was found, so 602 can say when it was found only through `LUA_PATH` or
`LUA_CPATH`).

## Where we differ

rmail compiles what is missing (Lua, OpenSSL, LuaSocket) from sources it
downloads, with their licences saved beside the binaries.  This check
**names** what is missing and builds nothing.

- **Gains:** nothing is fetched from the network at install time; the
  installer stays a short script a person can read; the owner's
  preference (vendored local libraries, no package managers) is kept by
  `libs/`, which 001 already searches first: a library put there is
  found before the system's.
- **Costs:** a machine without LuaSocket for LuaJIT needs a person to
  get it.  Building vendored sources from `libs/` (rmail's step 5 with
  the sources already in the project) is left for a later issue.

## Referees

1. **On this machine every required thing is found**, each line naming
   the version it reported, exit 0.
2. **A missing LuaSocket is named**: run with a `package.path` and
   `package.cpath` that find nothing (a broken version of the check's
   environment), the line says missing, names LuaSocket and `libs/`,
   exit 1.
3. **A missing libcrypto is named**: the check run with the library's
   name replaced by one that cannot load (`RAO_NEEDS_BROKEN=crypto`),
   missing, exit 1.
4. **A missing git, `flock` and the usual tools are named**: run with a
   `PATH` holding only `luajit`, each named, exit 1; Node and `unshare` missing
   are notes, not failures.
5. **`--quiet`** prints nothing on a whole machine and only the missing
   lines otherwise.

## Suggested Implementation Steps

1. The check, one function per need, each returning found/missing, the
   version or reason, and whether it is required.
2. The referee, running the check as a program under the environments
   above.

## Blockers that are not the owner's

- None: the check only reads.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02
("If there are open questions, answer them yourself"); the owner can
overturn each.

1. **Name what is missing; fetch and build nothing.**  rmail's installer
   downloads and compiles; the owner's preference for rao-chat's tools is
   vendored local libraries and no package managers, and a download at
   install time is the thing a vendored library avoids.  `libs/` is
   already first on the search path (001), so a person can put a library
   there by hand and the check finds it.
2. **The check is Lua, run by LuaJIT**, so it loads each thing exactly as
   the home's programs do; only "is LuaJIT there at all" is asked by the
   installer's Bash before it (602).
3. **`flock` (and, from 603, `setsid`) is required** because 603's launcher holds a lock so one
   home is never run twice; it is part of util-linux on every Linux the
   home runs on.  `ss`/`netstat`, Node and `unshare` are notes.
4. **Linux only**: the home reads `/proc` (164's `alive`) and the tests
   use Linux namespaces; macOS and the BSDs are not checked for (rmail's
   #620 adds launchd later; rao-chat has no such issue yet).

## Related documents

- `notes/rmail-rubric/installing-and-services.md` (rules I9, I11)
- `notes/vision-planning.md` section 11 ("the same crypto, socket and JSON
  libraries rmail bundles") and section 12 (phase 6)
- issues 124 (libcrypto through the FFI), 215 (git required)
