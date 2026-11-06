# 302 — The device port

**Phase:** 3 — Clients' connection
**Blocked by:** 201, 211, 301
**Blocks:** 303, 304, 305, 306, 309, 310

## Current Behavior

A home's mailboxes each listen on their own port (211, 212) and answer
nothing in the clear.  The viewer's folder (301) can only be read on the
home machine: nothing carries it to a phone or a browser.

## Intended Behavior

Decision of 2026-11-06 (301 decision 22, rubric question 24; the owner may
overturn it): **one device port per home**, separate from every mailbox
port.

- **Set by the owner**: `devices.port` (1 to 65535, no default: "no
  default port numbers") and `devices.address` (the address to listen on,
  or `any`) in the home's `config`.  `devices.frame-deadline` is the whole
  seconds a connection has to deliver one whole frame.
- **One small process per home**, `src/devices/187-device-server.lua
  <project> <disk home>`, beside the home starter.  It reads only the
  home's RAM folder (as 183 does) and the home's `devices` file.
- **Frames are the mailbox ports' frames** (201: 4-byte length, nonce,
  sealed body, check value; 124's cap), sealed under a **paired device's
  own token** (303), never under a room's token.  A device's key is made
  from its token by 123's rule, so its tying value keeps a device frame
  from ever opening as a room frame.
- **The first frame picks the device**: every paired device's key is
  tried (127's keyring).  None opens it: the connection is closed without
  a byte sent.  One opens it: the connection belongs to that device, and
  every later frame must open under the same key or the connection is
  closed.
- **Records** are one line, the kind first, fields tab-separated with the
  log's escaping (083), as 126's: `src/devices/186-device-records.lua`.
  This issue's kinds are `ping` (`id`) and `pong` (`id`, `at`: the home's
  clock, whole seconds).  Later issues add theirs to the same table.
- **Nothing in the clear**: a connection whose first four bytes are not a
  frame length 124 accepts is closed without an answer.  (309 adds the
  one exception, the browser's WebSocket upgrade.)
- **The process's own `state`** in `<home RAM>/devices/state`: `port`,
  `devices` (how many are paired), `refused` (frames no device key
  opened), problems as `problem.<name>`.  A `stop` file in that folder
  stops it.

## Status

Built 2026-11-06: `src/devices/185-settings.lua`, `186-device-records.lua`
(`ping`, `pong`), `187-device-server.lua`; referees 1 to 6 pass and catch
their broken versions (`src/devices/tests/188-test-device-port.lua`),
with two more: 0 (the record table refuses what it was not written for)
and 1b (a record the home does not answer closes the connection).

## Rubric

From `notes/rmail-rubric/structure-and-defences.md` and the sealing note.

- **Nothing in the clear** (R11): rmail's daemon answers a plain-text
  health check with its own name.  The device port answers no clear text.
- **Lengths before bodies** (R3): 125's reader, unchanged.
- **One stuck connection stops nothing** (the structure note's commonest
  failure): connections are coroutines under 162's wait loop, each with a
  frame deadline.
- **Which key opens it says only "a paired device"**: nothing in the
  clear names the device or the home.

## Where we differ

rmail's phone talks to its daemon's own port, the same port its contacts
use.  The formation here is **a port of the home's, not a mailbox's**:
the viewer is one per home and sees every mailbox, so the device link is
the home's.

- **Gains:** the mailbox ports keep their rule whole; a device pairs once
  per home, not once per mailbox; a mailbox restarting does not drop the
  phone.
- **Costs:** one more port to forward from outside; one more process.

## Referees

1. **A paired device is answered.**  A `ping` sealed under a paired
   device's token gets a `pong` with the same id, sealed under the same
   token.  *Broken:* answering under another key (`wrong-key`).
2. **An unknown key gets nothing.**  A frame sealed under a token no
   device holds (a room's token included): the connection closes with no
   byte sent.  *Broken:* answering with an error record (`answer-unknown`).
3. **Clear text gets nothing.**  "GET / HTTP/1.1" and a health-check line:
   closed with no byte sent.
4. **A connection keeps its device.**  After a ping under device A, a
   frame under device B's token on the same connection closes it.
   *Broken:* trying every key on every frame (`any-key`).
5. **A stuck connection stops nothing.**  A connection that sends two
   bytes and waits: another device's ping is still answered.
6. **Settings are required.**  A home without `devices.port`: the server
   stops naming the line to add.

## Suggested Implementation Steps

1. The settings file and the record table (`ping`, `pong`).
2. The server: listener, per-connection threads under 162's loop, the
   first-frame key choice, the pinned key.
3. A test client in the referees (a frame written by hand).
4. The referees above.

## Blockers that are not the owner's

- Needs 201 (sealing), 211 (the wait loop and RAM folders), 301 (the
  folder it serves).

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **A device port per home** (rubric question 24; 301 decision 22).
2. **A device's token is its own** (planning section 6: "the device goes
   into the contacts file with a token and `own = true`"), so a lost phone
   is unpaired without changing any room's token.
3. **Records share 126's line shape but not its table**: the device kinds
   are another conversation and live in 186, so a room frame's kinds and a
   device frame's kinds can never be mistaken for each other.
4. **The `devices` file must not be readable by others** (mode 600 or
   stricter, as the gatherer requires of nothing else yet): the server
   refuses to start otherwise, naming the file and the `chmod` to run.
   Every token in it opens the whole home.

## Related documents

- `notes/vision-planning.md` section 6 ("Clients ↔ their home server")
- `notes/rmail-rubric/open-questions.md` question 24
- issue 301 (decisions 22 and 23)
