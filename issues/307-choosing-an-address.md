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

## Related documents

- `notes/vision-planning.md` section 6 ("Choosing an address")
- issue 212 (where a mailbox can be reached)
