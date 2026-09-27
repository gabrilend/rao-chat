# rmail as a rubric: addresses and ports

Written 2026-09-26 from a reading of rmail (`/home/ritz/programs/r-mail`,
read only, not run).  Line numbers are `rmail.lua` unless another file is
named.  This note covers: how rmail works out its own public address,
announcing a move, several addresses per contact and promoting the one that
works, home-network discovery, the September 2026 router-mistaken-for-a-
housemate fix, how rmail learns its port ("detect port"), automatic port
opening, and what rmail's three networking documents found.  It serves
rao-chat issues 204 (the call-back check), 205 (the hello and joining), 207
(contact syncing) and 208 (leaving), and gives most of its weight to the
question now blocking 205: **how a home server learns its own outside port
when every top-level room is a mailbox with its own listening port.**

---

## 1. What this area does in rmail

rmail runs one program (the daemon) per mailbox.  One mailbox has one
listening port, written in its own config as `port = N`.  Everything below
is per mailbox; two mailboxes on one machine each do all of it separately.

### 1a. The address book: several addresses per contact

Each contact is a block of `name.field = value` lines in the contacts file.
After loading (1055–1260), one contact holds:

| field | type | holds |
|---|---|---|
| `ip` | text | the pinned default address: an IPv4 address, an IPv6 address, or a hostname |
| `port` | whole number (text on disk) | the default port for every address that does not name its own |
| `ip[N]` / `port[N]` | text / whole number, N = 1, 2, ... | further addresses, each with an optional port of its own |
| `local-ip`, `local-ip[N]` | text | private IPv4 addresses, tried only from the same home network |
| `token` | text | the secret shared with that one contact; its SHA-256 is the AES-256-GCM key |
| `own` | "true" or absent | one of your own devices |

From these the loader builds, in memory only, a list called endpoints: one
record per address, each record holding `addr` (text), `port` (whole
number), `is_default` (true/false), `index` (whole number or nothing) and
`contact_name` (text) (1186–1255).  A missing `port[N]` inherits the default
`port` (1215) — the fallback rao-chat drops.

**Trying addresses in order** (`contact_endpoints`, 1279–1311): same-network
`local-ip` addresses first, but only those whose first three numbers match
this machine's own home-network address (the "/24" test, 647–651); then the
pinned default; then `ip[N]` in order.  A send that fails to connect walks
down the list (3017–3052).  **Promotion**: when a later `ip[N]` succeeds,
its address and port are rotated together into position 1 on disk
(`promote_contact_index`, 1365–1447), so the next cycle tries it first.  The
unindexed default is never moved by promotion; a `local-ip` win is never
promoted either (it carries no index).

### 1b. Finding its own public address

State files hold what the daemon believes about itself, one line of text
each: `public_ip`, `public_ipv6`, `lan_ip`.

- **Public IPv4** (5300–5500).  A home machine cannot see its public address
  from inside: the router holds it.  rmail asks the outside world, over
  plain DNS on UDP port 53, using eight resolver addresses belonging to three
  operators (OpenDNS, Cloudflare, Google), each of which answers "the address
  this question came from" (5388–5397).  The list is shuffled (5402–5413),
  the first answer is taken (5421–5427).  If the answer differs from the
  stored one, it is confirmed by asking **a different operator**, not a
  different address of the same operator (5432–5441): two Cloudflare
  addresses would agree whether right or wrong.  Only a confirmed change is
  written and announced (5456–5494).  "No operator answered" is reported
  apart from "no change" (5448–5455).
- **Public IPv6** (5499–5545): read from the machine's own interface (no NAT
  in IPv6), skipping temporary and deprecated addresses; no confirmation.
- **Home-network address** (`nat.get_local_ip`, 1865–1897): the source
  address the kernel would use to reach 1.1.1.1.  A change writes a note to
  the inbox telling the person their router's forward now points at the old
  machine address (6140–6158), unless automatic port opening is on.
- **When** (6660–6728): at startup, then again after a random wait drawn
  from /dev/urandom, uniform between 24 and 48 hours, redrawn after every
  check; one hour if nobody answered.

### 1c. Announcing a move

A move (or every startup, 6895–6915) queues, per contact, a pending entry
`{ip = text, port = whole number}` in `pending-address.json`.  The sync cycle
turns each into a sealed `POST /update-address` (5550–5645) whose body holds:

| field | type | holds |
|---|---|---|
| `ip`, `port` | text, whole number | the single address, for old peers |
| `ips` | list of `{addr = text, port = whole number, kind = "hostname" / "public"}` | every public address: configured hostname first, then public IPv4, then global IPv6 (`addrset.mine`, 1531–1552) |
| `local_ips` | list of `{addr, port, kind = "private"}`, or absent | private addresses, sent only to a contact already known to be on this network (1558–1569) |

The port in every entry is the mailbox's own listening port, `config.port`.

The receiver (`handle_update_address`, 2500–2667) knows the sender because
only that one contact's token opened the frame.  It keeps private addresses
only if they share its own /24 and puts them in `local-ip`; merges the
public ones (1662–1685): a hostname or private default it holds is kept
first, then the announced set in the sender's order, then any old entry that
is not "ours to replace" (1600–1604); compares old and new **as sorted
sets** and writes only if the membership changed.  It then leaves a hidden
marker file `.address-update-<name>`.  That marker queues an announcement of
its own back (5553–5568), and is removed when a send **to** the moved
contact succeeds (6587–6606): only an outbound success tests the new
address.

### 1d. Finding housemates (home-network discovery)

For every contact whose public address equals this machine's own (a
housemate behind the same router), rmail sends a sealed UDP packet
`RMAIL-DISCOVER <my port> <my home address>` to the multicast group
239.192.82.77 with time-to-live 1, at the **contact's** port, and also to
each of the 253 other addresses in its /24 (6190–6221).  The receiver tries
every contact's key; the one that opens it names the sender (#393); it files
the home address from inside the packet (not the packet's source) and
answers `RMAIL-HERE <home address>` to the address and port inside the
packet (6223–6258).  The same search is sent once when a connection to a
housemate's public address times out (6270–6305).  Found addresses live in
memory only (`rt.lan.peers`, contact name → text address).

**Learning from connections** (6380–6420): when a housemate connects in from
a private address, that address is kept only if it shares this machine's
/24; otherwise it is a router passing traffic along, logged once, never kept
(the September 2026 fix, section 4).

### 1e. The port: set, never discovered, by the daemon

The daemon never learns a port.  It reads `port` from config and refuses to
start without it (6739–6758; the old 8025 fallback was removed, #382), binds
it before any router work (6796–6851), and from then on uses that one number
as **both** the port it listens on **and** the port it tells others.  It has
no idea of an outside number differing from the inside one: the
announcement sends `config.port` (5474, 5567, 6905); `/api/myaddress`
returns it (5721–5726); automatic port opening asks for outside = inside
(1909–1912, 1934–1935).

**"Detect port"** is not in the daemon.  It is a button in the Android
app's setup screen (`clients/android/.../SetupScreen.kt` 153–200,
373–446).  It sweeps TCP ports 1024–65535 on the host the person typed,
150 at a time, 800 ms connect limit per port, sending on each a request
sealed with the token the person typed; only the real daemon can seal a
reply the phone can open, so only it counts (`probeRmailPort`, 431–446).
If that finds nothing, it sweeps every address .1–.254 of the phone's own
network over two ranges (8000–8100 and 50000–65000, the installer's
random-port range).  Pointed at the public address, the first sweep goes
through the router — it finds an **outside** port, provided the router
supports hairpin (docs/ports-explained.md "What is hairpin NAT?").

### 1f. Automatic port opening (off by default) and the router check

`auto_port_forward` (default false).  When on, after binding: delete the
mapping recorded last run (`nat_mapping.json`, 1955–1961), then ask the
router with `upnpc` (UPnP) for outside port = inside port, or failing that
`natpmpc` (NAT-PMP) with a one-hour lifetime (1963–1986); renew every 30
minutes (7229–7235).  **Regardless of the setting**, every startup probes
for both protocols; the UPnP probe proves itself by creating and deleting a
real test mapping on a port 60000–63999 (1995–2003).  If either answers, the
log warns and every contact not yet warned gets a message; when the router
stops answering, those contacts get a "resolved" message (2009–2040).

### 1g. What rmail's three documents found

- **docs/nat-traversal-report.md**: UPnP, NAT-PMP and PCP all let any device
  on the home network open any port on the router, with no password; their
  authentication extensions exist on paper and in no product.  Conficker and
  Mirai used UPnP.  NAT-PMP mappings expire (renew at half the lifetime); UPnP
  ones can be permanent and go stale.  The daemon cannot catch its own
  shutdown, so cleanup happens at the next start.  Manual forwarding is the
  recommended default.  Carrier-grade NAT (phones, some ISPs; 100.64/10)
  makes inbound connections impossible: no forward exists to make.  Hole
  punching needs a coordinator and fails under symmetric/carrier NAT.
  IPv6 is the only real fix.  So the always-on home server is required and
  the phone only ever connects outward.
- **docs/ports-explained.md**: a port is the apartment number; forwarding
  is the router rule "outside port → this machine"; many routers do not
  support hairpin (a housemate reaching you through the public address), so
  housemates should use each other's home addresses; LAN and WAN ports can
  differ, which is what `port[N]` expresses.
- **docs/connection-suggestions.md**: owner's free-form notes, not design.
  Three lines bear on this area: "a permanent TCP connection that never goes
  offline", "ID to location available on trusted request", and "store key
  ... and trial decrypt the rand ping".

---

## 2. RULES

Each: the rule; why it holds; where rmail shows it; whether it applies to
rao-chat.

**R1. The port others must dial is the router's outside number, and it
cannot be read off any connection.**  An outgoing TCP connection leaves from
a temporary port the operating system picks, and the router may rewrite it
again; neither is the listening port, and neither is the forward's outside
number.  The number must be *said*.  rmail: never distinguishes inside from
outside — announces `config.port` (5474, 5567, 6905), maps outside = inside
(1912, 1935); the setup of `port[N]` exists for the case where they differ
(docs/ports-explained.md).  **Applies, changed**: rao-chat already says the
port in every hello (205); what rmail lacks is any idea that the said number
can differ from the listening number, and rao-chat has N of them per home.

**R2. The address a connection arrives from may be a router's, not the
peer's.**  A router relaying a housemate's hairpinned or double-NAT'd
traffic replaces the source with its own address; UDP broadcasts can be
rewritten the same way.  A private source address is only trusted as the
peer's own if it is on this machine's own network.  rmail: 6380–6420 (commit
aad3f4c, 2026-09-23); `issues/completed/203` (UDP source rewritten, fixed by
carrying the address inside the sealed payload).  **Applies unchanged**,
and more strongly: rao-chat's sender is unknowable, so a source address
never names anyone — at most it is a place to call back (204).

**R3. A private address is meaningful only on its own network; never hand
one to a peer elsewhere, never keep one received from elsewhere.**
192.168.x.x exists in every home; sent to a remote peer it names a stranger's
device on *their* network.  rmail: private addresses split into `local-ip`
(1153–1182), tried only from the same /24 (1279–1311), sent only to a contact
known to be on this network (1558–1569), dropped on receipt unless on the
receiver's /24 (2522–2540).  **Applies, changed and more pressing**: 207
spreads member lists to every member of a room; a housemate's private
address in that list would reach every member.  Private pairs need to be
kept out of shared member lists, or marked and filtered on both ends.

**R4. The private-range test must be exact.**  172.16.0.0/12 is private,
the rest of 172/8 is public; 169.254/16 (failed DHCP) and 100.64/10
(carrier NAT) are not reachable from the internet.  A wrong test sends
contacts addresses they can never reach, or treats strangers as housemates.
rmail: 595–623 (bug fixed in f0f4814, 2026-09-22).  **Applies unchanged.**
Note from #388: Tailscale also uses 100.64/10.

**R5. A public address comes from outside, and one answer is not proof.**
The machine cannot see the router's public address; it must ask an outside
party, which can be wrong or lying.  A *change* must be confirmed by an
independent operator before it is broadcast, because a missed change costs
one period of staleness and a false one rewrites every peer's address book.
rmail: 5432–5494; `#353` (DNS, three operators), `#379` "Confirmation on
change: kept".  **Applies unchanged**, once per home (not per mailbox: every
mailbox shares the router's one public address).

**R6. "Nobody answered" is not "nothing changed".**  A failed lookup is
usually a network outage.  rmail: 5448–5455, retry in 1 hour (6700–6713).
**Applies unchanged**; for rao-chat it extends to the call-back check (204
already says "no answer means not confirmed").

**R7. Addresses must be rechecked while running.**  A long-running server
that checks only at startup cannot see a move by construction.  rmail:
`#379` — 46 days stale, 41 phone messages stranded (found 2026-09-21).
**Applies unchanged**, and for each outside port too, not only the public
address (a router reset loses forwards; see R14).

**R8. A move announcement is a claim, and what proves it is a successful
exchange in the direction in doubt.**  Receiving an announcement proves the
sender can reach you; only reaching *them* at the new address proves the
new address.  An idle pair makes no traffic, so the claim must generate its
own test.  rmail: 6587–6606, 5553–5568; `#388` "The handshake was implemented
backwards".  **Applies, changed**: rmail *applies* a move on receipt
(2500–2667) because its pairwise token identifies the sender.  A rao-chat
room token is held by every member, so any member can claim any address;
the call-back check (204) must come *before* the address is used, and
(planning section 3) a move adds the new pair beside the old rather than
replacing it.

**R9. The sender cannot know which of its addresses a given receiver can
reach; send all, let the receiver's attempts decide.**  Reachability depends
on the receiver's position (same house, other house, IPv6 or not).  rmail:
`#388`; 1514–1552; promotion 3017–3062.  **Applies**: a rao-chat home's
pairs for one mailbox are (public IPv4, outside port), (hostname, outside
port), (global IPv6, *listening* port — no NAT on IPv6), and for housemates
(home address, listening port).  Note the port differs by address kind.

**R10. A write to watched or shared state needs a "did anything actually
change" guard, comparing sets, not orderings.**  Otherwise a write triggers
a sync, which re-announces, which writes on the other side: rmail measured
about 1,500 exchanges and 350 KB of log in 15 seconds between two idle
daemons.  rmail: 2567–2640; `#388` "An unchanged set still rewrote the
contacts file".  **Applies, strongly**: 207 sends members "when a new member
is noticed"; two homes that each notice the other would ping-pong unless
"new" is judged against the set already held.

**R11. A discovery packet must carry, inside its sealed body, the home
address and the port to answer to.**  The packet's visible source can be
rewritten (R2), and a UDP source port is not a listening port (R1).  rmail:
6199–6201, 6232–6246; `issues/completed/203`.  **Applies unchanged**, with
rao-chat's twist: which room key opens it says only "a member of this room",
not who.

**R12. Some networks can never accept an inbound connection.**  Carrier-grade
NAT has no forward to make.  A home behind it cannot be a member address;
its hello's pair will never answer a call-back.  rmail: nat-traversal-report
part 9.  **Applies unchanged**; rao-chat should say *why* the call-back
failed when its own public address is in 100.64/10.

**R13. Automatic port opening has no authentication, mappings expire or go
stale, and the daemon cannot clean up on exit.**  NAT-PMP mappings expire
at their lifetime (renew at half); UPnP ones may be permanent; a crash
leaves them.  The NAT-PMP reply states the outside port the router actually
granted, which may differ from the one asked for.  rmail: report parts 2–3,
7; 1955–1986, 7229–7235; rmail *does not read* the granted port (1934–1941
checks only that "Mapped public port" appears).  **Applies**; and the
granted-port point is a direct answer to part of the outside-port question.

**R14. A change of the machine's home address silently breaks every manual
forward.**  The router forwards to a fixed inside address.  rmail:
6140–6158; `issues/completed/302` (192.168.0.8 → 192.168.1.60), `#379`
(192.168.0.6 → .22).  **Applies, multiplied**: with one forward per
mailbox, one address change breaks all of them at once.

**R15. Bind the listening port before anything optional, because binding is
the only moment a collision becomes known.**  rmail: 6796–6851, `#382`.
**Applies, changed**: rao-chat allows two mailboxes on one port (with a
warning each time), so a shared port is one socket serving two mailboxes,
not a collision; a port held by *another program* is still an error.

**R16. A hostname is not overwritten by an address announcement.**  The
point of a hostname is that name lookup follows the moves.  rmail: 2508–2512,
1600–1604.  **Applies unchanged** (rao-chat's "add beside, never replace"
already covers it).

---

## 3. CHOICES

| choice | rmail's value | what it traded | rao-chat's owner |
|---|---|---|---|
| inside vs outside port | the same number, always | simplicity; wrong whenever the router forward uses a different outside number | differs: "the port worth telling others is the outside forwarded one" (planning section 14, just before question 11) |
| default port | none (removed, #382) | nothing; the fallback could only ever misfire | same: "no way. no default port numbers." (section 14, q11) |
| a port per address | `port[N]` optional, falls back to `port` | shorter config; a silent guess | differs: every address carries its port, missing is an error (section 5) |
| public-address lookup | DNS to 3 operators, 8 resolver addresses, shuffled, first answer | trusts large operators; no HTTP service | not decided |
| confirming a change | a second, different operator | one extra query on change days | not decided |
| recheck timing | uniform 24–48 h, 1 h after a failed lookup, redrawn at boot | a move can go unseen up to 48 h | not decided (would be config, no default) |
| announce at startup | always, to every contact | traffic at every restart; repairs stale peers | section 5: "announces itself at startup" |
| what a move does to a peer's book | merge; public ones replaced; hostname and private kept | the old public address is lost | differs: "a move adds the new address beside the old" (section 3) |
| retiring a move claim | first successful outbound send | needs traffic, so the claim makes its own | 204 makes it explicit: call back first |
| who is told | every contact | none | differs: every member of every room, sealed per room |
| discovery | multicast 239.192.82.77 TTL 1 **and** a sweep of 253 /24 addresses, on start and on a timeout | 254 packets per housemate per trigger; works when routers drop multicast | section 5 adopts it |
| same-network test | first three numbers equal (/24) | wrong on /16 home networks, errs toward "not local" | not decided |
| learned-from-connection addresses | memory only, own /24 only | lost at restart | not decided |
| automatic port opening | off; UPnP then NAT-PMP; 1-hour lifetime; renew 30 min | convenience vs an unauthenticated protocol | section 5: "off by default, with rmail's warning" — but rao-chat has no silent defaults, so it must be written in config |
| router probe at startup | always, cannot be disabled; creates and deletes a real test mapping | uses UPnP even when the person turned it off | not decided |
| telling contacts about an open router | automatic message to every contact, and a "resolved" one | reveals network state to contacts | not decided; in rao-chat, whom, and signed how? |
| using the router to learn addresses | rejected (#353): rewards leaving UPnP on; wrong under carrier NAT | loses the one party that knows the forward | not decided |
| "detect port" | a phone-side sweep of 64,512 ports with a sealed probe | minutes of connections resembling a port scan | open (205 question 1) |
| both sides move at once | accepted limitation; sneakernet (#300, #312); rejected asking a mutual contact because it would reveal who knows whom | no automatic recovery | differs by construction: a room's members already share their lists (207), so a moved member can be re-found through any member who still reaches them |

---

## 4. EDGE CASES ALREADY HIT

| date | what happened | fix | teaches |
|---|---|---|---|
| 2026-03-25 (d9484c6, `completed/203`) | a router rewrote a discovery broadcast's source to 192.168.0.1; the peer was filed as the router | carry the home address inside the sealed packet | R2, R11 |
| 2026-03-25 (1c386c4) | hairpin rewrote TCP sources to the router | prefer discovery over connection sources | R2 |
| 2026-03-25 (c0362f3, cdaf684, 18c8820, 8c13502) | global broadcast, then directed broadcast, then ARP-cache unicast each failed on some router, within one evening | multicast **plus** a /24 sweep, both kept | no single discovery method reaches every home network; use two independent ones |
| 2026-03-25 (1bc1cbf) | NixOS keeps `ip` elsewhere; a fallback answered with the packet's source address | search known paths; remove the fallback | a fallback here produced a wrong address, not an error |
| 2026-03-27 (#300, #312) | both sides move while apart; neither can find the other | accepted limitation | rmail's pairwise design has no third party; rao-chat rooms do |
| 2026-04-13 (#353) | HTTP "what's my IP" services slow and many | DNS to three operators; router-direct rejected | R5 |
| 2026-07-12 (#347 field defect) | a contacts writer flattened `ip[N]` lines to one `ip` and lost a WAN address | writers edit lines, never serialize whole contacts | multi-address records are fragile under any "rewrite the whole entry" path |
| 2026-09-21 (#379) | public address checked only at startup; 46 days stale; 41 phone messages stranded | 24–48 h recheck | R7 |
| 2026-09-22 (#379) | `math.random` never seeded; the "random" schedule was identical each boot | draw from /dev/urandom, reseed each check | timing jitter must come from a real random source |
| 2026-09-22 (#388) | announcing one address overwrote a housemate's working home address with the public one (hairpin ~70% success on that router) | announce the whole set | R9 |
| 2026-09-22 (#388) | move-confirmation tested the wrong direction; idle pairs never confirmed; an unchanged set rewrote the file → 1,500 exchanges in 15 s | outbound confirms; claim makes traffic; set-compare guard | R8, R10 |
| 2026-09-22 (#388, f0f4814) | 172/8 counted as private; CGNAT not; home addresses sent to remote contacts | exact ranges; `local-ip` split | R3, R4 |
| 2026-09-21 (#382) | missing port fell back to 8025, which could belong to another mailbox; the second daemon died in bind with no explanation | no default; bind first, say why | R15 |
| 2026-09-23 (aad3f4c) | sorelu, reached through two routers in a row, arrived from 192.168.0.1 while this machine is on 192.168.1.x; filed as sorelu's address; every send refused | keep a connection's private source only if on own /24; log a relay once | R2 |
| (#302, #379 notes) | machine's home address changed (.0.6 → .22; .0.8 → 192.168.1.60); router forward pointed at nothing | inbox note to fix the forward | R14 |

---

## 5. REFEREE TESTS

Written from the rules, not from rmail's code or rao-chat's.  Each names a
deliberately broken version it must catch.

1. **Outside port is what is said (R1).**  Home A listens inside on 41000,
   forwarded from outside 52000 (simulate with a local port-forwarding
   relay).  A's hello to B must carry 52000; B's call-back to (A's public,
   52000) must be answered.  *Broken version*: hello carries the listening
   port.  *Second broken*: B records the source port of A's connection.
2. **Each mailbox says its own port (R1).**  Home A with two mailboxes,
   outside 52000 → inside 41000 and outside 52001 → inside 41001.  Joining a
   room in each: the two hellos carry different ports, each confirmed by a
   call-back that arrives on the right mailbox.  *Broken*: one home-wide
   port used for every hello.
3. **A relaying router is not a member (R2).**  A connection arrives from a
   private address on another /24 (or any address a call-back to the stated
   port does not answer from).  No member pair is added.  *Broken*: record
   the connection's source address.
4. **Private pairs stay home (R3).**  Room with members A (housemate of B,
   same /24) and C (elsewhere).  A's members message to C contains no
   private address; a private address that arrives at C from anyone is not
   added.  *Broken*: members list sent verbatim to all.
5. **Private-range table (R4).**  Table test: 172.15.0.1, 172.32.0.1 public;
   172.16.0.1, 172.31.255.254, 169.254.1.1, 100.64.0.1, 100.127.255.255
   private; 100.128.0.1 public.  *Broken*: the `^172%.` test.
6. **One lookup does not move you (R5).**  Fake lookups: operator X says a
   new address, operator Y says the old.  No announcement is sent.  Then X
   and Y both say the new: exactly one round of announcements.  *Broken*:
   confirm with a second resolver of the same operator (both fakes of
   operator X agree).
7. **Silence is not sameness (R6).**  All lookups time out: the stored
   address is untouched, no announcement, and the next check is scheduled
   sooner than a normal one.  *Broken*: treat nil as "unchanged" and sleep a
   full period.
8. **Rechecks happen while running (R7).**  Change the fake public address
   after startup without restarting; within one check period the change is
   seen.  *Broken*: check only at startup.
9. **A forged move changes nothing until called back (R8).**  Member M sends
   "I am now at (X, p)" where nothing listens at (X, p), or a different
   server listens there without the room key.  No pair is used for delivery;
   the old pair is kept.  *Broken*: apply on receipt (rmail's pairwise
   behaviour).
10. **No ping-pong (R10).**  Two homes, each told of the other; after the
    first exchange of members, run idle for 60 seconds: no further members
    messages.  Then reorder a member list on disk: still none.  *Broken*:
    send on any write; or compare lists in order.
11. **Discovery trusts the body (R11).**  A discovery packet whose visible
    source is the router's address but whose sealed body says (192.168.1.20,
    41000): the found pair is (192.168.1.20, 41000).  *Broken*: use the
    packet's source address or source port.
12. **Carrier NAT is named (R12).**  With the fake public address in
    100.64/10, the server reports that it cannot be reached from outside,
    rather than sending hellos that can never be confirmed silently.
    *Broken*: classify 100.64/10 as public.
13. **Granted port is read (R13).**  A fake NAT-PMP answering "mapped public
    port 52017" to a request for 41000: the hello carries 52017.  *Broken*:
    assume the asked-for number was granted.
14. **Shared port is not a collision; foreign holder is (R15).**  Two
    mailboxes configured on one port: both served, a warning each start.  A
    port held by another program: an error naming it, before any router
    work.  *Broken*: a bind per mailbox (second fails); or silently choosing
    another port.

---

## 6. A DIFFERENT FORMATION — the outside port

The question: a home server with N mailboxes, each listening on its own
inside port, each (usually) forwarded from some outside number.  The hello
must carry the outside number; there is no default; errors over fallbacks.
What rmail teaches that bears on it:

- rmail never solved it: it assumes outside = inside everywhere (R1).
- The only place rmail finds an outside port is the phone's "detect port":
  a sweep through the public address with a probe only the real server can
  answer.  That works only when the prober can reach the public address —
  from inside the house, only with hairpin support, which many routers lack
  and one measured at about 70%.
- The router knows the answer (it holds the forwards) but rmail refused to
  ask it (#353), and when it did ask for a mapping it ignored the port the
  router granted (R13).
- The public address is per home; the outside port is per mailbox.  Lookups
  for the first should run once per home; the second is N facts.

Five formations, the first four workable:

**F1. Written, then proved.**  The `mailboxes` file (planning section 4)
gets an outside-port column next to the listening port: `label, kind,
listening port (whole number), outside port (whole number)`.  Missing is an
error at startup ("this mailbox has no outside port; write the number your
router forwards to it").  The first call-back from any member (204) is the
proof; a call-back that never comes is reported against that mailbox.
*Gains*: nothing to build beyond a column; the owner already has to open
the router to make the forward, so the number is in hand; no traffic that
looks like scanning; honest about the router being the person's.  *Costs*:
N numbers the person keeps in step with the router by hand; a router reset
or edit is found only when members stop getting through.

**F2. The home sweeps itself (a "port map" pass).**  Once per start (and on
each recheck), the server connects out to its own public address on every
port 1024–65535.  Each attempt sends a one-time random value the server
just made; any connection that lands on one of its own listening sockets
carrying such a value is its own, so the server learns, in one pass, the
whole table outside port → the mailbox (socket) it arrived at.  No keys are
needed (the value is proof enough, since only this process knows it).
*Gains*: learns every forward at once, including ones the person forgot;
catches a router edit at the next recheck; no member or third party
involved.  *Costs*: requires hairpin; on a router without it the sweep finds
nothing and must end in an error ("your router does not loop back; write
the outside ports in config"), so F1 is still needed underneath; 64,512
connections to your own router every recheck (the phone sweep at 150 in
parallel and 800 ms is minutes of work); some routers rate-limit or log
this as an attack.

**F3. A member looks for you.**  Joining already sends a hello to a known
member.  The joiner may send a hello *without* a port that says "find me":
the member sweeps the joiner's public address (it saw it on the packet) with
a sealed "did you send X?" (204's ask), and the first port that answers with
the room key is the joiner's outside port for that mailbox; the member tells
the joiner the number, and the joiner records it.  This is rmail's "detect
port" moved to the side of the network that can see the outside.
*Gains*: works with no hairpin and no router cooperation; learns exactly
what outsiders see; fits 204 (the sweep *is* a call-back check at many
ports).  *Costs*: conflicts with "a hello without a port is an error" (it
becomes a distinct kind, "find me", not a hello with a missing field); a
member spends minutes of connections sweeping someone's home, which looks
like a port scan to that home's ISP; it tells a member which ports at your
address are open (TCP connects succeed on every open port, sealed answer or
not); only works for the first room in each mailbox.

**F4. The router is asked, only where the person already allowed it.**
When automatic port opening is written as on, the mapping reply's granted
outside port (NAT-PMP states it; UPnP can list mappings) becomes that
mailbox's outside port.  When off, F1.  *Gains*: exact, no sweep; fixes
rmail's ignored-granted-port gap.  *Costs*: only for people who accept an
unauthenticated router protocol; rmail's #353 argument (it rewards leaving
UPnP on) applies; wrong under carrier NAT (the router's answer is itself
behind another NAT).

**F5 (tempting and wrong). Let the receiver read it off the connection**,
e.g. by sending from the listening port.  Home routers often keep an
outgoing port number when it is free, but that is the router's *outgoing*
mapping, not the inbound forward; the two can differ, and carrier NAT
always rewrites.  Recorded so it is not rediscovered as a shortcut (R1).

**My leaning: F1 as the rule, with F2 as a separate tool that writes F1's
column.**  F1 matches the owner's "errors over fallbacks" and "every setting
written in config"; F2, run by hand (or at install) rather than by the
server on every start, proposes the numbers it found and the person keeps
or corrects them — the house rule "create the tool that creates the thing".
Where F2 finds nothing (no hairpin), the tool says so and the person writes
the numbers.  F3 is the most interesting and the only one that works with
no hairpin and no typing, but it needs a new message kind and makes members
into scanners; I would keep it as a recorded alternative.

### Other formations for the rest of the area

- **Moves through the room, not to it.**  rmail tells each contact
  directly and cannot recover when both sides move (#300, #312), and
  rejected asking a mutual contact.  In rao-chat, members already share
  lists (207); a moved home tells whichever members it can still reach,
  and they carry the new pair to the rest in their next members message,
  each receiver calling back (204) before use.  Gains: recovery from
  simultaneous moves for free.  Costs: slower spread; each new pair costs a
  call-back per receiver.
- **Address kinds as data, not position.**  rmail distinguishes kinds by
  field name (`ip`, `ip[N]`, `local-ip`) and by position (the pinned
  default).  rao-chat's member pair could carry an explicit kind (public,
  hostname, private-with-its-/24, IPv6) and a last-confirmed time, so R3's
  filter and R9's ordering read one field instead of inferring.  Gains:
  the flattening bug of #347 has nothing to flatten.  Costs: a wider record
  on disk.
- **Discovery once per home, answered per mailbox.**  rmail's daemons each
  send their own multicast and sweep.  One rao-chat home server with N
  mailboxes could send one discovery per room it shares with a housemate
  (sealed per room), to the housemate's listening port for that mailbox.
  Costs: the same 254 packets per room, which argues for asking only when a
  room has a member whose public address equals ours.

---

## 7. OPEN QUESTIONS FOR THE OWNER

Most blocking first.

1. **The outside port (blocks 205).**  Written in config per mailbox and
   proved by the first call-back (F1), found by a self-sweep through the
   router (F2, needs hairpin), found by a member's sweep (F3, needs a
   "find me" kind), read from the router when automatic port opening is on
   (F4), or a combination (my leaning: F1, with F2 as a tool that fills in
   F1's column)?
2. **Where the outside port lives.**  A column in `mailboxes` beside the
   listening port, or its own lines in `config`?  And for IPv6 (no NAT) the
   listening port is the one to say — should a mailbox list both, so a
   hello can carry (public IPv4, outside port) and (IPv6, listening port)?
3. **Private addresses in member lists (207).**  Never shared (housemates
   find each other only by discovery), or shared marked with their network
   and dropped by any receiver not on it?
4. **Many forwards per home.**  Is one forward per top-level room acceptable
   for the person to maintain by hand, knowing a change of the machine's
   home address breaks all of them at once (R14)?  Should the server warn
   when the machine's home address changes, as rmail does, naming every
   mailbox's forward?
5. **Automatic port opening.**  Planning section 5 says "off by default";
   rao-chat has no silent defaults.  Must it be written in config (on or
   off)?  If on, one mapping per mailbox?
6. **The router probe.**  rmail probes UPnP by creating a real test mapping
   at every start, even with automatic port opening off.  Keep, keep but
   without making a mapping (discovery only), or drop?
7. **The open-router warning.**  rmail messages every contact.  In rao-chat,
   to every member of every room (revealing network state to strangers of
   strangers), direct messages only, or the owner only?
8. **Public-address lookup.**  Keep rmail's rule (three DNS operators,
   confirm a change with a different one)?  The recheck interval as a
   config setting (no default), and the retry after "nobody answered"?
9. **A move.**  Planning section 3 says the new pair is added beside the
   old.  When is the old pair dropped — never, after its call-backs fail
   for some time, or when the moved home says so (itself a claim needing a
   call-back at the *old* pair, which may no longer be theirs)?
10. **Carrier NAT at home.**  When the server's own public address is in
    100.64/10, refuse to start mailboxes (they cannot be reached), or run
    them outbound-only and say so?
11. **Same-network test.**  Keep rmail's /24 assumption, or read the real
    network mask from the interface?

Where I looked and did not find: rmail has no code that distinguishes an
inside from an outside port (searched `rmail.lua` for port handling in the
announcement, `/api/myaddress`, NAT helpers, and `docs/`); rmail's daemon
has no "detect port" (only the Android setup screen does); the hairpin
success figure (~70%) appears only as a citation inside `#388`, pointing at
`#377` notes that do not contain it.
