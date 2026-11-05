# 212 — Where a mailbox can be reached: its outside port, the public address, and noticing a move

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 101, 211
**Blocks:** 205, 213, 215b, 210

## Current Behavior

Nothing exists.  Phase 1's `rao-home/mailboxes` gives each mailbox its
**listening** port (integer, 1–65535, no default).  Nothing records the
number the router forwards to it from outside, and nothing looks up the
home's public address.

rmail never distinguishes inside from outside: it announces its config
port everywhere and asks the router for outside = inside (addresses note,
1e and R1).

## Intended Behavior

- **The outside port is configured by the person, per mailbox**, in the
  viewer or the mailbox's configuration (owner, 2026-09-27; formation F1 of
  the addresses note; no sweep tool).  A mailbox with no outside port is
  an error at start-up naming the mailbox and what to write ("this mailbox
  has no outside port; write the number your router forwards to it").
  The first successful call-back (204) from any member is its proof; a
  mailbox whose hellos are never confirmed is reported against that
  mailbox.
- **The pairs a mailbox says it can be reached at** (for 205's hello),
  each with its kind as data:

  | kind | address | port |
  |---|---|---|
  | `public` | the home's public IPv4 address (from the lookup below) | the mailbox's outside port |
  | `hostname` | a hostname the person configured for the home, if any | the outside port |
  | `ipv6` | the machine's global IPv6 address, if any | the **listening** port (IPv6 has no address translation) |
  | `home-network` | the machine's private address, only for housemates (213) | the listening port |

- **The public address is one fact per home**, not per mailbox: the home
  starter (211) looks it up and writes it into one file in the home's RAM
  root (`public-address`: address, when confirmed, source operators); every
  gatherer reads that file.
- **Looked up from outside, and a change confirmed by a different
  operator** before anything is announced; "nobody answered" is reported
  apart from "no change" and retried sooner.
- **Rechecked while running**, at a random point within a configured window
  (config `address.recheck-earliest`, `address.recheck-latest`, whole
  seconds, no defaults; rmail uses 24–48 hours, the owner remembers "like
  once every 36 hours or so"), redrawn after every check from the
  operating system's random source.  **Each recheck is also a moment to
  pull and push the shared upstream** (215b).
- **A confirmed move** tells every gatherer, and each sends a fresh hello
  (205) to every pair on every room's send list; receivers call back
  before using the new pair, and add it beside the old (planning section
  3).  The same announcement is sent at start-up.
- **Carrier-grade address translation is named**: when the public address
  is in 100.64/10 the home cannot be reached from outside, and the viewer
  says so rather than sending hellos that can never be confirmed.

## Rubric

From `notes/rmail-rubric/addresses-and-ports.md` section 2.

- **The port others dial is the router's outside number and cannot be
  read off any connection** (R1).  It must be said.
- **A public address comes from outside, and one answer is not proof**
  (R5).  A missed change costs one period of staleness; a false one
  rewrites every peer's address book — so a change is confirmed by an
  independent operator (two addresses of one operator agree whether right
  or wrong).
- **"Nobody answered" is not "nothing changed"** (R6).
- **Addresses are rechecked while running** (R7).  rmail checked only at
  start-up and went 46 days stale with 41 messages stranded.
- **Send all your pairs; the receiver's attempts decide** (R9).
  Reachability depends on where the receiver stands.
- **The private-range test is exact** (R4): 10/8, 172.16/12, 192.168/16,
  100.64/10 (carrier translation, also Tailscale), 169.254/16; the rest of
  172/8 is public.
- **Some networks can never accept an inbound connection** (R12).
- **A change of the machine's home-network address silently breaks every
  manual forward** (R14) — multiplied here: one forward per mailbox.
- **Jitter from a real random source** (structure R7): rmail's unseeded
  generator made every boot's "random" schedule identical.

## Where we differ

rmail's daemon does every lookup per mailbox and knows only one port.
This issue tries **one watcher per home writing one fact file that every
mailbox reads** — the public address is the router's, so N gatherers
asking N times would be N times the traffic and N chances to disagree —
and **address kinds as data** (the table above), so the port-by-kind rule
and 207's "never pass on home-network pairs" read one field instead of
inferring from position, as rmail's `ip`/`ip[N]`/`local-ip` fields do.

- **Gains:** one lookup, one truth, per home; a gatherer's hello is built
  from a file it can read at any time; the kind column makes R3 and R9
  checkable.
- **Costs:** the starter becomes a small process with work of its own; a
  wider pair record (kind) than phase 1's `{address, port, heard}` —
  kinds live in the hello and in 207's lists, not in the room entry, until
  the owner says otherwise (open question 2).

## Referees

1. **Outside port is what is said.**  Home A listens on 41000, forwarded
   from 52000 by a local port-forwarding relay: A's hello carries 52000
   and B's call-back to it is answered.  *Broken:* the listening port;
   the connection's source port.
2. **Each mailbox says its own port.**  Two mailboxes, 52000 → 41000 and
   52001 → 41001: their hellos differ and each call-back lands on the
   right mailbox.  *Broken:* one home-wide port.
3. **One lookup does not move you.**  Fake operator X says a new address,
   Y the old: nothing announced; both say new: exactly one round.
   *Broken:* confirming with a second resolver of operator X.
4. **Silence is not sameness.**  All lookups time out: the stored address
   stands, nothing is announced, the next check comes sooner.
5. **Rechecks happen while running.**  Change the fake public address after
   start-up: seen within one window.  *Broken:* start-up only.
6. **Private-range table.**  172.15.0.1 and 172.32.0.1 public;
   172.16.0.1, 172.31.255.254, 169.254.1.1, 100.64.0.1, 100.127.255.255
   private; 100.128.0.1 public.  *Broken:* a `172.` prefix test.
7. **Carrier translation is named.**  A fake public address in 100.64/10:
   the viewer's `state` names it.  *Broken:* classifying it public.
8. **No outside port is an error.**  A mailbox without one: that gatherer
   refuses to start and names the line.  *Broken:* using the listening
   port.

## Suggested Implementation Steps

1. Where the outside port lives (open question 1), declared and checked.
2. The public-address lookup (several operators, a change confirmed by
   another) and the fact file.
3. The recheck clock in the home starter, and the move notice to gatherers
   (and to 215b's push-and-pull).
4. The pair set by kind, for 205.
5. The referees above.

## Blockers that are not the owner's

- Needs 101 (the mailboxes file) and 211 (the starter and gatherers).

## Open questions

1. **Where the outside port lives**: a new field in 101's `mailboxes`
   entries (`outside-port`) or a per-mailbox configuration file (the owner
   named "the mailbox's config file"; config is per home today)?  (Rubric
   question 15.)
2. **Both ports for IPv6**: a mailbox says (public IPv4, outside port)
   and (IPv6, listening port) — confirm.  And do address kinds become part
   of the room entry?  (Rubric question 15.)
3. **Automatic port opening**: must be written in config (on or off; rao-chat
   has no silent defaults); if on, one mapping per mailbox, and the port
   the router actually granted read back?  Keep, reduce or drop rmail's
   start-up router probe, which makes a real test mapping?  (Rubric
   question 16.)
4. **Carrier translation at home**: refuse to start mailboxes, or run them
   outbound-only and say so?  (Rubric question 17.)
5. **When a superseded pair is retired**, or only slowed to the ceiling
   forever (rmail dialled a replaced address 5,700 times a day)?  (Rubric
   question 18.)
6. **The lookup itself**: keep rmail's rule (DNS "what is my address" at
   three operators, a change confirmed by another); the "same network" test
   by the real network mask rather than rmail's first-three-numbers?
   (Rubric question 20.)
7. **Who receives the open-router warning** (every member of every room,
   direct messages only, or the owner only)?  (Rubric question 21.)
8. **Warn when the machine's home-network address changes**, naming every
   mailbox's forward (R14)?
9. **Testing a port forward** with no plaintext answer: a sealed ping from
   the viewer through the public address (needs a router that loops back)?
10. *(answered 2026-09-27)* **How a mailbox learns its outside port**:
    configured by the person per mailbox, in the viewer or the mailbox's
    config file; no sweep tool.
11. *(answered 2026-09-27)* **The recheck interval** is a config setting
    (planning section 15, "Git per mailbox").

## Decisions (2026-11-05)

Made by the builder.  The owner's standing instruction is to answer open
questions rather than wait, choosing the option that is easiest to undo.
The owner can overturn each one; what overturning costs is said with it.
Built in `src/delivery/` (149 reach, 150 public address, 151's
referees), three settings in 135 and 136, and 143's simulated homes, which
now state their pairs through 149 instead of 205's stand-in.  The home
starter and the gatherers (211) are not built: the watcher and the
outside-port check are ready for the starter to run, and 149's `seam` is
what a gatherer gives its sender stage.

1. **Where the outside port lives** (open question 1): a new home file,
   `outside-ports`, beside `mailboxes`, one line per mailbox:
   `<mailbox tag>.outside-port = <number>`.  It is not a field of 101's
   `mailboxes` entries, so phase 1's file and checks stay as they are.  A
   mailbox with no line is an error naming the mailbox, its listening
   port, and the exact line to write.  The listening port is never used in
   its place.  Undo: move the line into `mailboxes`; only 149's reader
   changes.
2. **Both ports for IPv6** (open question 2): confirmed as the issue
   says.  IPv6 pairs carry the listening port, public and hostname pairs
   the outside port.  Kinds stay in hellos and lists, not in the room
   entry.
3. **Automatic port opening** (open question 3): not built and not
   probed.  The person writes the outside port.  If it is wanted later it
   needs its own setting, on or off, with no default.
4. **Carrier translation at home** (open question 4): mailboxes run,
   outbound only.  A public address in 100.64/10 is never stated in a
   hello, because nobody outside could call it back, and `state` names
   carrier-grade translation for the viewer.
5. **Superseded pairs** (open question 5): not retired here.  A pair that
   stops answering is slowed to the retry ceiling by 202's timers.
   Retiring one is left for when 209's cross-check exists.
6. **The lookup** (open question 6): rmail's rule and rmail's sources
   (OpenDNS, Cloudflare and Google, two resolvers each), asked over DNS
   from 150 itself with LuaSocket.  A change counts only when a second,
   different operator gives the same new address.  "Nobody answered" is
   kept apart from "no change".  The first address a home ever learns
   needs the same two operators.  The same-network test by mask is 213's.
7. **The open-router warning** (open question 7): not built, because it
   belongs to automatic port opening (decision 3).
8. **A home-network address change** (open question 8): not warned yet.
   149 reads the machine's private addresses at every hello, so the
   hellos follow a change.  A warning naming each mailbox's forward
   needs the viewer (211).
9. **Testing a forward** (open question 9): not built.
10. **The recheck window** reads `address.recheck-earliest` and
    `address.recheck-latest`, with no defaults.  The options offer
    rmail's 86400 and 172800.  After a check nobody answered, or a
    disagreement or an unconfirmed change, the next check comes after a
    quarter to a half of the earliest.  Each wait is drawn from
    `/dev/urandom`.
11. **`address.hostname`** is a setting: a hostname, or `none`.  It is
    stated with the outside port.
12. **The public-address fact file** is one line: address, confirmed
    time, and the operators that agreed.  Its folder (the home's RAM
    root) is passed in, because 211 makes that folder.
13. **The machine's own addresses** are read from the kernel's lists:
    `/proc/net/if_inet6` for global IPv6, and `/proc/net/fib_trie` for
    private IPv4.  No `ip` command is needed.

What could not be checked here: the real DNS operators.  This machine
has no outside network, so the question and answer were checked against
a stand-in resolver on loopback UDP only.

## Related documents

- `notes/vision-planning.md` sections 5 ("Keeping addresses current"), 15
- `notes/rmail-rubric/addresses-and-ports.md` (section 6, formation F1)
