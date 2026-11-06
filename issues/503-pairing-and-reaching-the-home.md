# 503 — Pairing and reaching the home: Servers and Setup

**Phase:** 5 — The Android app
**Blocked by:** 502
**Blocks:** 504 to 509

**Needs the Android toolchain on the owner's machine.**  This machine
has a JDK and Gradle but no Android SDK, no Kotlin compiler of its own
and no emulator or phone, and nothing may be installed here; so this
issue is a plan, written 2026-11-06, and none of it is built.  No Kotlin
is written until it can be compiled (501 decision 3).

## Current Behavior

A device is paired on the home machine with `189-pair.lua add <label>`,
which prints the lines a device needs (`port`, `home-network`, `public`,
`token`; 303).  The reference device (190) reaches the home by its
home-network address first with a quick timeout, then the public one
(307), and its `test` says exactly what failed.  The app has no screen
for any of it.

## Intended Behavior

Planning sections 6 and 8: Servers ("the home servers this phone is
paired with; + to pair another", rmail's mailbox list) and Setup
("address, port, token; detect port; a connection test that names
exactly what failed").

- **Setup** takes the lines 189 prints, pasted whole or typed field by
  field; the token box hides what is typed; "detect port" tries the
  device port on the home-network address as rmail's scan does (only the
  home's own address, a short list of ports: decision 2).
- **The connection test** is 190's `test`: the same exchange and the same
  words for each failure (no route, refused, timed out, the frame did not
  open: a wrong token).
- **Choosing an address**, 307's rule: the home-network address with a
  quick timeout, then the public one; the one that answered is said.
- **Servers** lists the homes this phone is paired with, by the label
  the person gives each; **+** opens Setup.  Tapping the title anywhere
  returns here.
- **Where the token is kept**: Android's EncryptedSharedPreferences, or
  the Keystore with a key of its own (decision 1); never in a log or a
  screenshot (`FLAG_SECURE` on Setup).

## Status

Plan only (2026-11-06); not built.

## Rubric

From `notes/rmail-rubric/addresses-and-ports.md`: the home-network
address first with a quick timeout, then the public one; a test that
names what failed.

## Referees

1. **Pairing lines**: the four lines 189 prints, pasted, fill Setup; a
   missing or unknown line is said.
2. **The test's words**: against a home on the owner's machine, each
   failure (home not running, wrong port, wrong token) gives 190's words
   for it (an instrumented test, or a person following a list).
3. **The address**: with the home-network address unreachable, the
   public one is used and said.

## Suggested Implementation Steps

1. `net/` (the connection, 307's choice), Setup, the test.
2. Servers, and keeping the token.
3. The referees.

## Blockers that are not the owner's

- A home running on the owner's machine to pair with (phase 6's
  installer makes one).

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **The token in EncryptedSharedPreferences** (AndroidX Security), as
   the simplest store Android encrypts with a Keystore key; rmail's app
   keeps its token in its settings, and this is one step safer at no
   cost to the person.
2. **"Detect port" tries only the home's own address**, at the device
   port 189 printed and the first variant of `devices.port`: it is a
   convenience, not a scan of a network.

## Related documents

- issues 189 (pairing), 303, 307, 403 (the page's way)
