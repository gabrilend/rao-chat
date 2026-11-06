# 303 — Pairing a device

**Phase:** 3 — Clients' connection
**Blocked by:** 302
**Blocks:** 304, 307, 310

## Current Behavior

302's server reads a `devices` file, but nothing writes one, and no
device can tell why a connection does not work.

## Intended Behavior

Planning section 6: "the device goes into the contacts file with a token
and `own = true`; the client is given address, port and token (rmail's
setup screen, its 'detect port' scan, and its connection test that says
exactly what failed)."

- **The `devices` file** in the disk home, rmail's contacts format:
  `<label>.token = "<token>"` and `<label>.own = true` per device.  An
  entry without `own = true` is not a device and stops the server, naming
  the line.  Mode 600.
- **Pairing on the home machine**: `luajit src/devices/189-pair.lua
  <project> <disk home> add <label>` makes a readable token (007's word
  list, as rooms do), writes the file whole under a temporary name and
  renames it, and prints what the device needs: the home's addresses (the
  home-network address and the public one when 212 knows it), the device
  port, and the token.  `list` shows labels only; `remove <label>`
  unpairs.  The server sees the change at its next connection, with no
  restart.
- **The reference device**, `src/devices/190-device.lua <device folder>
  <command>`, keeps its settings in `<device folder>/config` (`port`,
  `home-network`, `public`, `token`; mode 600).  Its `test` command says
  exactly what failed:
  - nothing listens at that address and port (refused);
  - the address cannot be reached (no route, or no answer to connect
    within the wait);
  - the home closed the connection without a word (the token is not one
    this home knows);
  - something listens but said nothing within the wait (this may not be
    a device port, or the home is stuck);
  - or "answered in N ms".

## Status

Built 2026-11-06: `src/devices/189-pair.lua` (`add`, `list`, `remove`),
`src/devices/190-device.lua` (`test`); referees 1 to 4 pass and catch
their broken versions (`src/devices/tests/191-test-pairing.lua`), with
1b (`list` and a second `add`), 2b (the owner's own lines kept), 3b
(`--public` with no public address) and 3c (a pong for another ping is
not an answer, against a stand-in home).
Referee 5 (a non-device entry stops the server) is 302's referee 6c.

## Rubric

- **The connection test says exactly what failed** (rmail's setup screen,
  structure note "Clients").
- **Tokens are text exactly as stored** (123's rule): the token printed is
  the token written, and a line break is refused.

## Referees

1. **Pairing gives a working device.**  `add phone` then `test` with the
   printed settings: answered.  *Broken:* writing the token with a
   trailing space (`trailing-space`).
2. **Unpairing works at once.**  `remove phone`, then `test` from the old
   settings: "closed the connection without a word", with no server
   restart.
3. **Each failure is named.**  A closed port: "nothing listens"; an
   address with no route: "cannot be reached"; a wrong token: "closed
   the connection without a word"; a listener that never answers: "said
   nothing".  *Broken:* one message for all (`one-message`).
4. **The file is private.**  After `add`, the `devices` file is mode 600
   and was never seen half-written.
5. **A non-device entry stops the server**, naming the line.

## Suggested Implementation Steps

1. The `devices` file reader (in 187) and writer (188).
2. 190's `config` and its `test`.
3. The referees.

## Blockers that are not the owner's

- Needs 302.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **Six words for a device token** (rooms suggest readable tokens; a
   device token opens the whole home, so it gets more words than a
   person types for a room): about 77 bits from the EFF list.
2. **No "detect port" scan.**  rmail's scan guesses which port its daemon
   is on; here the owner sets `devices.port` and pairing prints it, so
   there is nothing to guess and no scan traffic.
3. **The reference device is a Lua program**, as 183 is for the viewer:
   the Android app and the web page follow it, and the referees can drive
   it.

## Related documents

- `notes/vision-planning.md` section 6 ("Pairing")
- issue 302
