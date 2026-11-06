# 403 — Reaching the home from the page

**Phase:** 4 — The web client
**Blocked by:** 402
**Blocks:** 404 to 409

## Current Behavior

The page can seal a frame (402) but opens no connection, and pairing
(303) prints settings for the reference device only: they do not name
the WebSocket path a browser needs.

## Intended Behavior

Planning section 6: pairing gives the client "address, port and token
(rmail's setup screen ... and its connection test that says exactly what
failed)"; the client "tries its server's home-network address first
(quick timeout), then its public one".

- **Pairing a browser**: `189-pair.lua ... add <label> --browser` prints
  190's lines and, for a browser, `websocket-path` (the home's
  `devices.websocket-path`), `wait`, `quick-wait` and `keep-alive` (half
  the home's `devices.idle-limit`, whole seconds): stated values the
  person can change, never defaults hidden in the page.
- **The settings are those lines, pasted**: the page's Settings take the
  block pairing printed, "name = value" lines as 190's `config`, and
  check it as 190 does (a port 1 to 65535, an address or `unknown`, a
  path starting `/`, waits that are numbers, a token 123 accepts).
- **One WebSocket per connection**, to `ws://<address>:<port><path>`,
  binary, one 302 frame per message (309); the first frame is a sealed
  `ping`.
- **Choosing an address as 307**: the home-network address with
  `quick-wait`, then the public one with `wait`; each must answer the
  ping before it is used.
- **The connection test says what a browser can tell apart**:
  - no WebSocket could be opened there (a browser is not told why:
    nothing listens, the address cannot be reached, or the path is not
    the home's);
  - nothing answered the opening within the wait;
  - opened, then closed without a word: the token is not one this home
    knows;
  - opened, but no answer to the ping within the wait;
  - answered with something that is not a frame under this token;
  - or "answered in N ms by A P".
- **What the page keeps**: the settings without the token, and only when
  the person ticks "remember on this computer" (decision 2).

## Status

Built 2026-11-06: `189-pair.lua add <label> --browser`;
`src/web/213-reaching-the-home.js` (`rao.link`: the settings, the
WebSocket link, choosing an address, the test's words); the page's
Settings form (Connect, Test the connection, Forget this home, remember);
the stand-in's `settings`, `remember`, `test` and `reach`; the referees'
kit, `src/web/tests/214-kit-for-page-tests.lua`.  Referees 1 to 5 pass,
2 to 4 catching their broken versions
(`src/web/tests/215-test-reaching-the-home.lua`), with 1b (a phone's
lines are as they were; the token box wins over a token line), 3b (a
home that opens but refuses the ping is said, not passed over) and 3c (a
pong for another ping is not an answer, against a stand-in home).

## Rubric

- **The connection test says exactly what failed** (rmail's setup
  screen).  A browser hides a refused port behind the same event as an
  unreachable one; the page says so rather than guessing.
- **Tokens are text exactly as stored** (123): the pasted token is used
  byte for byte, a trailing space included; a line break is refused.

## Referees

1. **Pairing gives a working page.**  `add laptop --browser`, its lines
   pasted into the stand-in's settings, then `test`: answered.
2. **Each failure is named.**  A wrong token: "closed without a word";
   a wrong path and a closed port: "no WebSocket could be opened"; a
   listener that never answers the opening: "nothing answered".
   *Broken:* one message for all (`one-message`).
3. **Home network first.**  With the home-network address unreachable,
   the public one is used, and the page says which.  *Broken:* the
   public one first (`public-first`).
4. **The token is never kept.**  What "remember" stores holds every line
   but the token.  *Broken:* storing the whole block (`keep-token`).
5. **Settings are checked**: a block missing `port`, a port of 70000, a
   path without `/`: refused, naming the line.

## Suggested Implementation Steps

1. 189's `--browser`.
2. `rao.link`: settings, opening, the ping, choosing an address, the
   test's words.
3. The stand-in's `test`, the referees against a real device server in
   the loopback-only namespace.

## Blockers that are not the owner's

- Needs 402.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **The page's settings are pairing's own lines**, pasted, not a form of
   separate fields: what 189 prints is what the device reads, for the
   reference device and the page alike, so the two cannot drift.
2. **The token is never stored by the page.**  A page opened from a file
   shares its browser storage with other pages opened from files (how
   much differs between browsers), and the token opens the whole home
   (302 decision 4).  The person pastes it when they open the page; the
   token box is a password box, so a browser's own password keeper may
   offer to hold it, which is the person's choice, not the page's.
3. **`--browser` adds lines rather than changing 190's**: a phone's
   settings stay as they were, and 190 does not start speaking WebSocket
   because a line appeared.
4. **`keep-alive` is printed as half the idle limit**, so a page that has
   sent nothing for that long pings well before the home would close it
   (306 decision 4).

### While building, 2026-11-06

5. **The settings' lines are read by 190's config rule**, which trims
   each line, so a token written in a `token =` line loses spaces at its
   ends; the token box's text is used byte for byte.  The page takes the
   token box first and the `token` line only when the box is empty.
6. **`wait = 10` and `quick-wait = 1` are what `--browser` prints**: a
   browser has no faster way to learn that an address is away than its
   own WebSocket giving up, so the home-network try is kept short.
7. **A WebSocket that opens but whose home refuses the ping stops the
   attempt** (307 decision 2), but one that cannot be opened is passed
   over for the public address: a browser cannot tell a wrong path from
   an address that is away, so a wrong path on the home network is
   reported with the public address's words too.
8. **The page opens Settings when it starts**, since the token is pasted
   each time (decision 2).

## Related documents

- issues 303, 307, 309
- `notes/vision-planning.md` section 6 ("Pairing", "Choosing an address")
