# 307 — Choosing an address

**Phase:** 3 — Clients' connection
**Blocked by:** 303
**Blocks:** 310

## Current Behavior

A device knows its home's home-network and public addresses (303) but
uses whichever it is told.

## Intended Behavior

Planning section 6: "The client tries its server's home-network address
first (quick timeout), then its public one, as rmail's phone does."

- 190 connects to `home-network` with `quick-wait` seconds, then to
  `public` with `wait` seconds, and says which one answered.
- An address that answered at the TCP level but not to the sealed ping
  is not tried again in that attempt (it is the home, and the token is
  wrong): the device says so instead of trying the next.

## Status

Built 2026-11-06: 190's `reach` (home-network with `quick-wait`, then
public with `wait`, each answering a sealed ping before it is used),
used by `catch-up`, `send` and `live`, which print which address it was.
Referees 1 to 3 pass and catch their broken version
(`src/devices/tests/196-test-choosing-an-address.lua`), with 2b (a
home-network address that never answers is given up after quick-wait)
and 3b (neither answers: both are said).

## Referees

1. **Home first.**  Both addresses answer: the home-network one is used.
2. **Public when away.**  The home-network address is unreachable: the
   public one is used within quick-wait plus its own time.
3. **A wrong token is not hidden** by trying the next address.
   *Broken:* falling through (`fall-through`).

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **Quick-wait and wait are the device's settings, no defaults**; the
   reference device's tests use 0.5 and 2 seconds.

### While building, 2026-11-06

2. **Anything after a connection, not only a closed one, stops the
   attempt**: a home that connects but closes, stays silent, or answers
   with something else is said as it is, and the public address is not
   tried.  Each of those is the home (or something on its port)
   answering, and passing over it would hide what is wrong.
3. **Every reach starts with a ping**, so an address counts only when
   the home has answered under this device's key; one round trip more
   per connection.
4. **`test` is left as 303 built it**: it tests the one address it is
   given (`--public` for the public one), so each address can still be
   checked on its own.

## Related documents

- `notes/vision-planning.md` section 6 ("Choosing an address")
- issue 212 (where a mailbox can be reached)
