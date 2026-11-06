# 309 — The browser's way in

**Phase:** 3 — Clients' connection
**Blocked by:** 302, 306
**Blocks:** 310 (and phase 4's web client)

## Current Behavior

A browser cannot open a plain TCP connection, so it cannot reach the
device port (302), which answers no clear text.

## Intended Behavior

Planning section 6: the web client is live "over a WebSocket to the home
server carrying the same encrypted frames as the phone", AES-GCM in the
browser's WebCrypto.

- **The device port accepts one clear-text exchange**: an HTTP/1.1
  `GET <devices.websocket-path>` with `Upgrade: websocket`, `Connection:
  Upgrade`, `Sec-WebSocket-Version: 13` and a `Sec-WebSocket-Key`, read
  with a byte cap and the frame deadline.  The answer is the standard
  `101 Switching Protocols` with `Sec-WebSocket-Accept` and nothing that
  names the server.  Any other request: closed with no byte sent.
- **After the upgrade**, each binary WebSocket message holds exactly one
  302 frame; the rest is 302 to 306 unchanged.  Masking (client to
  server) is required, as the standard says; text messages, fragments
  over the cap, and unmasked frames close the connection.

## Status

Built 2026-11-06: in `src/devices/187-device-server.lua`, the upgrade
(`read_head`, `upgrade_answer`, `accept_value` through libcrypto's SHA-1
and base64), the WebSocket wrapper (`M.websocket`, one 302 frame per
binary message) and a client side (`websocket_client`); the setting
`devices.websocket-path`; and 190 reaching its home as a browser when
its config has `websocket-path`.  Referees 1 to 4 pass, 2 catching its
broken version (`src/devices/tests/198-test-browsers-way-in.lua`), with
5 (the reference device as a browser catches up and is pushed to through
the upgrade) and 6 (the setting is required).

## Referees

1. **The upgrade is answered** with the accept value the standard's own
   example gives (RFC 6455 section 1.3).
2. **A wrong path, or a plain GET, gets nothing.**  *Broken:* answering
   404 (`answer-404`).
3. **A ping in a WebSocket message gets a pong** in one.
4. **An unmasked message closes the connection.**

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **The upgrade path is a setting** (`devices.websocket-path`, no
   default), so the port gives nothing away to a scanner guessing `/`.
2. **Serving the page itself is phase 4's** (planning question 5, how to
   trust the page): this issue serves no files.

### While building, 2026-11-06

3. **Every fragment is refused, not only those over the cap**: a 302
   frame is always sent as one whole binary message (browsers send a
   `send()` of an ArrayBuffer whole), so fragments are never needed and
   joining them would be one more thing to get wrong.
4. **WebSocket pings and pongs are not answered** (only a close is
   understood, as the end); the device keeps its connection with 302's
   sealed `ping` (306), so nothing is said outside a sealed frame.
5. **The request's head is capped at 4096 bytes** (`HEAD_MOST`) and must
   arrive within the frame deadline.  `Connection` may list other tokens
   beside `Upgrade` (browsers send `keep-alive, Upgrade`).
6. **The WebSocket code lives in 187** beside the port it guards, and 190
   borrows its client half: the device module's numbers end at 199, so
   there is no number for a file of its own.
7. **The setting is required**, like every other: a home with no browser
   still names a path.  It is checked to be `/` and letters, digits and
   `- . _ ~ /`.

## Related documents

- `notes/vision-planning.md` section 6 ("The web client"), section 9
- issue 302 (decision 1)
