# Phase 2 Progress

## Goals
Server-to-server delivery for "a room is a contact" (planning sections
1–5 and 15), built with rmail as a rubric, not a source
(`strategems/other-peoples-software-as-a-rubric.md`,
`notes/rmail-rubric/`): every issue carries the rules it must meet, the
formation it tries that differs from rmail's, and referee tests written
from the rules and checked against deliberately broken versions.

What the phase builds:

- **Sealing** with a key made from each room's random token, every sealed
  body starting with a key-tying value, trial opening limited to one
  mailbox's keys.
- **One data-gatherer process per mailbox**, working in RAM folders as a
  pipeline (listener, openers, filer, sender), loading from disk at
  start-up and syncing back every cycle; acknowledging after a disk write
  or after a RAM write, built both ways until the owner chooses.
- **Delivery** to every address-and-port pair at once, acknowledged by id,
  retried forever with a per-pair timer; the log is the outbox.
- **Where a mailbox can be reached**: its outside port configured per
  mailbox, the home's public address looked up and rechecked, housemates
  found on the home network.
- **Joining and membership**: the hello, the call-back check, syncing
  member lists by digest, leaving with a remembered record, and the
  periodic cross-check that catches a two-faced sender and fills gaps.
- **Signatures** read from each message's text by one rule.
- **One git repository per mailbox**: a text copy of every message
  (editable, never sent), the running log committed every sync cycle in
  size-bounded files, the running source code on its own branch, and an
  optional shared upstream pulled and pushed at start-up, shut-down and
  each public-address recheck.
- **The failed-decryption log** for fail2ban, and the phase demo.

Build order (lower numbers are not always earlier; the Blocked by fields
are the authority): 201 → 201a → 211 → 202 → 203 → 204 → 212 → 205 → 213
→ 207 → 208 → 209 → 214 → 215 → 215a → 215b → 210.  214 (signatures)
needs only phase 1 and may be built at any time.

Counts: `/home/ritz/programming/ai-stuff/scripts/progress-dashboard.lua
/home/ritz/programs/rao-chat -m`.  Open questions still waiting on the
owner, most blocking first: `notes/rmail-rubric/open-questions.md`.

## Completed Issues
(None yet.)

## Under way
- **201** — built 2026-11-05 in `src/sealing/` (123–128): key from token,
  sealing and opening, frames on a connection, the inner record table,
  keyrings per mailbox, trial opening split for workers; open questions
  1–5 answered as dated decisions the owner may overturn.  Left: the
  workers and the port (211), the other kinds' rows (their issues).
- **201a** — built 2026-11-05: the tying value was already sealed,
  checked and stripped by 201's code; 201a adds its four referees
  (`src/sealing/tests/129-test-key-tying.lua`, including a frame built to
  pass GCM under two keys) and the bound beside the check.  Question 2
  answered as a dated decision the owner may overturn.
- **202** — built 2026-11-05 in `src/delivery/` (130–137) with the `ack`
  row in 126: the `delivered` file and what each pair is missing, retry
  timers (doubling, a dealt deck), one attempt per pair with answers
  bound to the room and the connection, and the receiving side.  Referees
  1–9 run in a simulation (fake clock, in-memory relay).  Open questions
  1–7 and 10 answered as dated decisions the owner may overturn.  Left:
  the stages, sockets and workers (211).
- **203** — built 2026-11-05 in `src/delivery/` (138–140), with the line
  grammar in `docs/failed-decryption-log.md` and a fail2ban filter and
  jail in `docs/fail2ban/`: one line per frame no key opens and per length
  refusal, carrying the source address and ports, in size-split files in
  the mailbox's RAM folder (138 is the split rule 215a will share).  The
  filter has been checked by a stand-in only; fail2ban was not installed
  where this was built.  Open questions 1–3 answered as dated decisions
  the owner may overturn.  Left: the opener stage and RAM folder (211).
- **204** — built 2026-11-05 in `src/delivery/` (141–144), with the
  `did-you` and `did-you-answer` rows in 126.  A home keeps its claims in
  each room's `claims` file and answers a `did-you` from it.  The asker
  calls the stated pair, never the source; a `yes` adds the pair (hello)
  or removes it (leave), a `no` ends the check, and no answer leaves it
  unconfirmed and retried on 202's timers.  Referees 1–5 run in the
  simulated world, now shared with 202's tests (143).  Open questions
  1–5 answered as dated decisions the owner may overturn.  Left: 205's
  hello and 208's leave, which carry the claims.
- **205** — built 2026-11-05 in `src/delivery/` (145–146), with the
  `hello` row and a `pairs` field type in 126.  A hello states every pair
  of the mailbox under one claim id; the sender stage sends it before the
  first message to a pair never heard from, at start-up, and after a
  move, and resends it until an ack names the claim.  The receiver calls
  back each stated pair it has not heard from within the retry ceiling
  and adds it beside the pairs held; its own hello sent back adds
  nothing.  Referees 1–6 and part of 7 run in the simulated world.  Open
  questions 1–2 answered as dated decisions the owner may overturn.
  Left: the old port kept served after a merge (211).  (The mailbox's
  pairs came with 212, and the members a joiner receives with 207.)
- **208** — built 2026-11-05 in `src/delivery/` (147–148), with the
  `leave` row in 126.  Leaving sends a leave with a claim to every pair
  on the send list.  A receiver calls the leaving pair back, then removes
  it, writes its `left` line and drops its `delivered` line.  A forged
  leave is answered `no`.  The leaver's own newer message or hello
  re-adds it, and a leave older than its newest message is ignored.
  Referees 1–5 and a sixth for open question 1 run in the simulated
  world.  Open questions 1–2 answered as dated decisions the owner may
  overturn.  207's members lists call `may_add_from_list`, so a
  replayed list does not re-add a confirmed leaver.
- **212** — built 2026-11-05 in `src/delivery/` (149–151).  Each mailbox
  has an outside port, written in the home's `outside-ports` file; a
  mailbox without one refuses to state pairs, naming the line to write.
  The public address is looked up over DNS from several operators, a
  change counts only when a second operator agrees, and it is rechecked
  at random points within a configured window.  A confirmed move sends
  fresh hellos.  Hellos state public, hostname, IPv6 and home-network
  pairs, each with its kind and the right port.  Carrier-grade
  translation is named and never stated.  Referees 1–8 run, with the
  simulated homes now stating their pairs through 149.  Open questions
  1–9 answered as dated decisions the owner may overturn.  Left: the
  starter and gatherers that run it (211), and the real operators, which
  were not reachable where this was built.
- **209** — built 2026-11-05 in `src/delivery/` (156–157), with the
  `summary` and `versions` rows in 126 and two settings.  Every
  `crosscheck.interval` seconds each home runs, per pair on each send
  list that is not ignored, 207's members digest and then a summary:
  the ids and fingerprints of what it holds from the last
  `crosscheck.window` seconds, and its own pairs.  A receiver makes its
  own records the summariser lacks missing again in `delivered`, and
  202's sender resends them with their ids.  The same id with another
  fingerprint is raised on both sides with both versions.  Referees 1–5
  run in the simulated world, against broken versions.  Open questions
  1–3 answered as dated decisions the owner may overturn.  Left: the
  viewer's notice for a raised discrepancy (phase 3), and the gatherer
  that runs the stage (211).
- **213** — built 2026-11-05 in `src/delivery/` (154–155), with the
  `discover` and `here` rows in 126.  A room is searched only when a
  member is at this home's public address, or a connection in it came
  from this machine's own network: a sealed `discover` goes to the
  multicast group (time-to-live 1) and to every address of each own
  network.  The pair inside the seal is called back, and on yes kept as a
  housemate (in memory and the RAM folder), never as a member and never
  in a members list.  Connections to its stated public pairs go to its
  home-network pair.  A relaying router is logged once and kept nowhere.
  Referees 1–4 run in the simulated world, against broken versions.  Open
  questions 1–3 answered as dated decisions the owner may overturn.
  Left: the gatherer's socket and timers (211).
- **207** — built 2026-11-05 in `src/delivery/` (152–153), with the
  `members-digest`, `members-ask` and `members` rows in 126.  When a
  call-back confirms a newcomer's hello, the home sends its digest to
  every pair on the send list, the newcomer included.  A home whose
  digest differs asks, and gets the list, which carries for each pair the
  claim that pair answered yes to (the room's new `vouched` file).  Every
  pair from a list is called back before it is added; ignored, private
  and left pairs are skipped.  Anyone may ask with `ask_members`.
  Referees 1–6 run in the simulated world, each against a broken version
  where the issue names one.  Open questions 1–3 answered as dated
  decisions the owner may overturn.  Automatic asking rides on 209's
  periodic cross-check.  Pairs confirmed only from inside the house are 213's
  housemates, kept apart from the members, so no list carries them.
