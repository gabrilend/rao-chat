# 213 — Finding housemates on the home network

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 201, 211, 212
**Blocks:** 210

## Current Behavior

Nothing exists.  Planning section 5 adopts rmail's discovery ("Servers on
the same home network find each other by multicast and a sweep of the
local network"); no issue held it until now.

## Intended Behavior

Many home routers cannot loop a connection from inside the house back in
through the public address, so two homes behind one router must reach each
other by their home-network addresses.

- **Only for rooms that need it**: a gatherer searches for housemates in a
  room only when one of the room's pairs has the home's own public address
  (212's fact file) — someone behind the same router.
- **A `discover` record**, sealed with that room's key and sent over UDP
  to a multicast group with time-to-live 1 **and** to every address of the
  home network (the same port on each — the mailbox's listening port on
  the housemate side is not known yet, so the sweep goes to the ports the
  room's pairs name), carrying inside the seal this machine's home-network
  address and the mailbox's listening port.
- **A `here` answer**, sealed with the same key, to the address and port
  **inside** the discover record, carrying the answerer's home-network
  address and listening port.
- **Found pairs are called back** (204) like any other claim, then kept as
  `home-network` pairs (212's kind) in memory and in the gatherer's RAM
  folder; they are never passed on in members lists (207).
- **Learning from connections**: a connection arriving from a private
  address is a housemate's own address only if it is on this machine's own
  network (by the real network mask); otherwise it is a router relaying,
  noted once in the running log, never kept.

## Rubric

From `notes/rmail-rubric/addresses-and-ports.md`.

- **A discovery packet carries, inside its sealed body, the home address
  and the port to answer to** (R11): the visible source can be rewritten
  by a router, and a UDP source port is not a listening port.  rmail filed
  a peer as the router in March 2026.
- **A connection's source may be a router's** (R2): kept only if on this
  machine's own network.  rmail filed a two-router relay as a housemate in
  September 2026, and every send was refused.
- **The private-range test is exact** (R4).
- **No single discovery method reaches every home network** (edge case
  2026-03-25: global broadcast, directed broadcast and ARP each failed on
  some router in one evening): multicast and a sweep, both.
- **Which key opens it says only "a member of this room"**, never who
  (sealing note, rao-chat's twist on R11).

## Where we differ

rmail's daemon sends its multicast and 253-address sweep for every contact
sharing its public address, per daemon.  The formation here is **discovery
asked per room, only where a pair shares the home's public address, and
proved by call-back like every other claim** — discovery becomes one more
source of claims, not a separate trust path.

- **Gains:** no discovery traffic at all in a home with no housemates; one
  trust rule for every pair however it was learned.
- **Costs:** a housemate who shares several rooms is discovered once per
  room (each room has its own key); the sweep still costs one packet per
  home-network address per trigger.

## Referees

1. **Discovery trusts the body** (addresses T11).  A discover whose visible
   source is the router's address but whose sealed body says
   (192.168.1.20, 41000): the found pair is (192.168.1.20, 41000).
   *Broken:* using the packet's source.
2. **A relaying router is not a housemate** (addresses T3).  A connection
   from a private address on another network: nothing kept.  *Broken:*
   recording the source.
3. **No housemate, no traffic.**  A home whose rooms hold no pair at its
   public address sends no discover.
4. **Found pairs are called back and never shared.**

## Suggested Implementation Steps

1. The `discover` and `here` records (201's table, sealed as datagrams:
   nonce, sealed body, check value, no length).
2. The trigger (a pair at our public address) and the send (multicast and
   sweep).
3. Answering, calling back, keeping as `home-network`.
4. The connection-source rule, by the real network mask.
5. The referees above.

## Blockers that are not the owner's

- Needs 201 (sealing), 211 (the gatherer), 212 (the public address and
  pair kinds).

## Open questions

1. **The same-network test**: the real network mask (proposed) or rmail's
   first-three-numbers rule?  (Rubric question 20.)
2. **Found addresses across a restart**: memory only (rmail) or kept in the
   RAM folder and synced?
3. **The sweep's ports**: the housemate's mailbox port is unknown until it
   answers; sweep the ports the room's pairs name (proposed), or one
   multicast only?

## Related documents

- `notes/vision-planning.md` section 5 ("Finding each other at home")
- `notes/rmail-rubric/addresses-and-ports.md` (1d, R2, R4, R11, "Discovery once per home")
