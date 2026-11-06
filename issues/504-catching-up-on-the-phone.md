# 504 — Catching up on the phone

**Phase:** 5 — The Android app
**Blocked by:** 503
**Blocks:** 505 to 509

**Needs the Android toolchain on the owner's machine.**  This machine
has a JDK and Gradle but no Android SDK, no Kotlin compiler of its own
and no emulator or phone, and nothing may be installed here; so this
issue is a plan, written 2026-11-06, and none of it is built.  No Kotlin
is written until it can be compiled (501 decision 3).

## Current Behavior

A device catches up with 304's exchange: it says what it holds (each
file's path and digest), the home sends what is new or changed and says
what to drop; the result is a mirror of the home's RAM folder in 301's
layout.  190 keeps its mirror in a folder; the page keeps one in memory
(404).

## Intended Behavior

- **A mirror in the app's own files** (`filesDir/<home label>/mirror/`),
  in 301's layout, so what the app shows is what the home holds and 192's
  rules apply unchanged: a path is checked before it is written, a file
  is written whole under a temporary name and renamed.
- **The exchange is 304's**, sealed by 502: what it holds, then what is
  new, changed or dropped; a file's digest checked before it is kept.
- **A new phone gets the whole history in one exchange; one away for a
  week catches up in one** (section 6).
- **Several homes**: one mirror each, by label.

## Status

Plan only (2026-11-06); not built.

## Referees

1. **The mirror is the home's**: after a catch-up against a home on the
   owner's machine, the mirror and the home's RAM folder hold the same
   paths and the same message files (a script on the home machine
   compares them, as 201's `compared` does).
2. **Nothing twice**: a second catch-up with nothing new receives no
   message.
3. **A bad path or digest is refused**, nothing written (192's referees'
   cases, as JVM tests).

## Suggested Implementation Steps

1. The mirror's rules (a port of 192's checks) with JVM tests.
2. The exchange; the comparison script.

## Blockers that are not the owner's

- None.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **The mirror on the phone's storage, not only in memory** (the page
   keeps it in memory, 404): an app is stopped and started by Android at
   any time, and a mirror kept means a catch-up of only what is new.

## Related documents

- issues 301, 304, 192 (the mirror), 404 (the page's)
