# 508 — People and Settings on the phone

**Phase:** 5 — The Android app
**Blocked by:** 507
**Blocks:** 509

**Needs the Android toolchain on the owner's machine.**  This machine
has a JDK and Gradle but no Android SDK, no Kotlin compiler of its own
and no emulator or phone, and nothing may be installed here; so this
issue is a plan, written 2026-11-06, and none of it is built.  No Kotlin
is written until it can be compiled (501 decision 3).

## Current Behavior

The page has People and Settings (408).  The app's tabs are empty.

## Intended Behavior

Planning section 8:

- **People (tab)**: "contacts, edited as a form as in rmail; each
  person's page lists the rooms you share with them."  As the page
  (408 decision 1): the direct-message rooms, each with its label and
  its last line, since the `people/` links are not in the viewer's
  folder.
- **Settings (tab)**: "addresses, token, colours, notification detail
  (sender and text / sender only / no preview / none), the locked-screen
  check-in, a 'danger zone' to forget this server."  The signature (506)
  is here too.
- **Colours adjustable**, as rmail's: the palette's values (501) may be
  changed, and "back to the palette" restores them.
- **The danger zone** forgets this home on this phone (its mirror, its
  token, its typed files once sent), after a confirmation that names it.

## Status

Plan only (2026-11-06); not built.

## Referees

1. **Settings survive**: every setting kept across the app being
   stopped.
2. **Forgetting** removes that home's mirror and token and nothing of
   another home's.
3. **People** lists the direct-message rooms of the mirror, and opens one.

## Suggested Implementation Steps

1. Settings, then People.

## Blockers that are not the owner's

- None.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **People lists the direct-message rooms**, as the page does (408
   decision 1); editing people and members from a device waits for a
   device record the home does not have yet.
2. **Forgetting a home keeps a typed file not yet sent**, and says so,
   until the person confirms a second time: a message written and not
   sent is the one thing the home does not hold.

## Related documents

- issue 408
