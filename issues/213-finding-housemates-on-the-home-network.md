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

## Decisions (2026-11-05)

Made by the builder.  The owner's standing instruction is to answer open
questions rather than wait, choosing the option that is easiest to undo.
The owner can overturn each one; what overturning costs is said with it.
Built in `src/delivery/` (154 housemates, 155's referees), with the
`discover` and `here` rows in 126, a `discover` claim kind in 141, its
action in 142, and 143's simulated home network.  It replaces 205's
stand-in: `seams.is_housemate` is now 154's.  Discovery is tested only
inside the simulated world and, for the one real datagram, on 127.0.0.1
inside a network namespace with only loopback; nothing was sent to a
real network.

1. **The same-network test** (open question 1): the real network mask,
   as proposed, read from the kernel's routing table (`/proc/net/route`:
   attached routes, no gateway, private destinations).  A /25 and a /20
   are told apart exactly.  Undo: 154's `on_own_network` alone decides.
2. **Found addresses across a restart** (open question 2): kept in the
   gatherer's RAM folder (`<ram>/housemates`: room, home address and
   port, the public pairs it stated), read back when the housemates
   table is made, and not synced to disk.  They survive a gatherer
   restart, but not a reboot, where the address may have changed anyway.
   Every start searches again.  Undo: stop reading the file in `new`.
3. **The sweep's ports** (open question 3): the ports named by the room's
   members at this home's public address, plus this mailbox's own
   listening port (a housemate on the same defaults).  The group and the
   sweep both go to each.  A housemate whose router maps a different
   outside port to its listening port is found only if it searches
   itself, which it does at its own start.  Undo: 154's `ports`.
4. **The claim:** a discover or here carries a `discover` claim (141)
   stating every pair the mailbox states.  The receiver calls back the
   home-network pair inside the seal, and on yes keeps it.  A claim kind
   of its own keeps a found pair from ever being added as a member
   (142's `discover` action calls 154's `keep`).
5. **Routing:** a kept housemate's stated public pairs are routed to its
   home-network pair (`route`), so a member at this home's public address
   is reached inside the house.  The room's entry still holds the public
   pair, so a housemate who moves away is still reached from outside.
6. **What is called back:** only a home-network address on this
   machine's own network.  A body naming any other address is ignored,
   so a datagram cannot make this home call arbitrary addresses.
7. **When a room is searched:** once a run (`start`), after a confirmed
   move (`moved`), and when a connection in that room arrives from an
   address on this machine's own network (`from_connection`).  A private
   address on another network is a relay: one log line per address, kept
   nowhere.
8. **The multicast group** is 239.192.82.78, next to rmail's
   239.192.82.77, so the two programs do not wake each other.
   Time-to-live 1, and the sender does not hear its own copy.
9. **The sweep** covers every host of each attached private network,
   less the network, broadcast and own addresses.  A network wider than
   /24 is swept on the /24 around this machine's address, so a /16 costs
   253 packets, not 65,000.
10. **Datagrams that do not open are dropped silently.**  Other programs
    use multicast too, so they are not failed-decryption lines (203).
11. **What runs it is 211's:** `udp_listen` (a socket on the mailbox's
    port, joined to the group) and `udp_send` are ready for the gatherer,
    which hands each datagram to `receive` and calls `start` and `moved`.

## Related documents

- `notes/vision-planning.md` section 5 ("Finding each other at home")
- `notes/rmail-rubric/addresses-and-ports.md` (1d, R2, R4, R11, "Discovery once per home")
