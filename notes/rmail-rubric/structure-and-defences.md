# rmail as a rubric: the server's shape and its defences

Written 2026-09-26 for rao-chat's phase 2 (issues 201–210, read as a whole,
especially 210), following `strategems/other-peoples-software-as-a-rubric.md`.
rmail (`/home/ritz/programs/r-mail`) was read, not run, called or copied.
Line numbers are for `rmail.lua` at commit `409c7c6` unless another file is
named.

Covers: how rmail's home server ("the daemon") is laid out — startup, the
main loop, what it watches, how it serves its owner's devices and other
servers, logging, where state lives; `docs/defensive-patterns.md` in full;
`docs/service.md` and `docs/thin-client.md` (for rao-chat's phases 3 and 6);
how rmail treats bad input and failed peers; and the history of its bugs
(`issues/`, `issues/completed/`, `git log`).

---

## 1. What this area does in rmail

### One program, one mailbox, one port

An rmail daemon is started with exactly one argument: the path of a config
file.  The mailbox it serves is the folder that file sits in; nothing else
names it (rmail.lua:10–103).  A folder given instead of a file is refused
with the file path it should have been (80–90), because the older
folder-argument form once served the wrong mailbox on a machine with two
(issue 381).

The config is `key = value` lines.  rmail's reader skips any line it cannot
read without saying so (35–54: a line that is not `key = value` is simply
not stored).  Two settings are required and have no default: `name`
(6733–6735) and `port` (6737–6759; a default of 8025 was removed after it put
two mailboxes on one port, issue 382).

A machine with several mailboxes runs several daemons, one per mailbox, each
its own service with its own port, log and process-id file, all named after
the mailbox path (`docs/service.md`, "Running multiple instances"; commit
`fd980a5`).

### Where state lives

| place | holds | medium |
|---|---|---|
| `<mailbox>/config` | settings | disk |
| `<mailbox>/contacts` | `name.field = value` lines: token, addresses, ports, `own = true` for the owner's devices | disk |
| `<mailbox>/inbox/`, `outbox/` | one plain-text file per message; the daemon also writes **problem notices** here (below) | disk |
| `<mailbox>/.state/*.json` | bookkeeping as JSON: `inbox.json` (file name → `{from = string, message_id = string, attachments = table}`), `outbox.json`, `pending-address.json` (contact name → `{ip = string, port = integer}`), `chunks-outgoing.json`, `consent-pending.json`, `consent-responses.json`, `uploads.json`, `nat_mapping.json`, `nat_security_warned.json`; plain files `public_ip`, `public_ipv6`, `lan_ip` | disk (read and written whole each time, 1777–1785) |
| `<mailbox>/attachments/`, `transfers` | received files, transfer list | disk |
| `/tmp/rmail-progress/log-<mailbox path, slashes as dashes>` | the daemon's own log copy | RAM (moved there 2026-09-23 because it records who was talked to and when, 127–147, issue 397) |
| `/tmp/<service name>.log` | the service manager's capture of the same lines | RAM |

In memory only: the per-contact retry timers (below), the home-network
addresses learned this run (`rt.lan.peers`: contact name (string) → address
(string)), and the table of open connections.

### Startup, in order (`init_runtime`, 6730–6950)

1. Make the mailbox folders; refuse to start without `name` or a valid
   `port`; refuse without `zip`/`unzip`.
2. Tidy the contacts file (`align_contacts`).
3. Start two kernel file watchers: one on `outbox/`, one on `contacts`
   (inotify on Linux, kqueue on BSD/macOS; a machine with neither stops
   rather than falling back to polling, 327–359).
4. **Claim the port before anything slow** (6794–6846).  If the port is
   taken, write a notice named `CANNOT-LISTEN` into the inbox explaining what
   to check, log it, exit.  On success, delete any old `CANNOT-LISTEN`
   notice.  The notice is named for the problem, not the port, so fixing the
   port does not leave a stale complaint behind (6815–6819).
5. Also listen on IPv6 (IPv6-only socket, so it does not clash, 6848–6865)
   and on UDP at the same port number for home-network discovery (6867–6869).
6. Only now talk to the router (port-forward checks, 6873–6887), work out the
   public and home-network addresses, and queue an address announcement to
   every contact ("I'm still here, at this address", 6892–6921).
7. Make every contact's retry timer due now, and schedule the next address
   re-check 24–48 hours away (6923–6937).

### The main loop (`main`, 7035–7255)

One operating-system thread.  Each incoming connection gets its own
**coroutine** (a function that can pause itself and be resumed later).  The
loop asks the operating system, through `socket.select`, to wait until one
of these is ready: a listening socket has a new connection; a connection a
coroutine is waiting on can be read or written; either file watcher fired;
or a timer comes due (7089–7112).  The wait is the shortest of: the soonest
contact timer, the address re-check, and 3 seconds (for the two exit checks
below).

When something is ready:

- **New connection** → wrap the socket so a read or write that would block
  pauses the coroutine instead of the whole program (`make_async_socket`,
  6960–7023; read deadline 10 s, write deadline 30 s), start
  `handle_request` in a new coroutine (7125–7149).  An error thrown inside a
  request ends only that connection and is logged (7061–7064, 7138–7141).
- **Connection ready** → resume its coroutine.
- **Watcher fired** → note "outbox changed" or "contacts changed".
- Every 3 s: stop if the mailbox folder has vanished twice in a row (a
  pulled USB drive), or if a one-visit (`--once`) window has passed
  (7176–7197).

Then, if the outbox or contacts changed or any contact timer is due, run
**one sync cycle inline** (7214–7253): close connections idle for more than
30 s, read any waiting UDP discovery packets, run `run_sync_cycle` inside
one protected call, renew a router mapping if due, and finally **drain**
(read and discard) every file-watcher notice that arrived during the cycle,
so the daemon's own writes do not wake it again.

### A request from outside (`handle_request`, 6312–6550)

Every connection, from another server or from the owner's phone, arrives on
the same port and speaks the same framing:

- Read 4 bytes.  If they are the text `GET `, answer a **plaintext** health
  check naming the mailbox (`{"ok":true,"name":...}`) and close
  (6326–6337).
- Otherwise the 4 bytes are a big-endian length (32-bit unsigned integer).
  Refuse anything under 28 (12-byte nonce + 16-byte check value) or over
  64 MiB, then read exactly that many bytes (6340–6344).
- **Trial opening**: try the key of the contact already known on this
  connection first; otherwise try every contact's key in turn, re-reading
  the contacts file from disk for the attempt (2770–2785, 6346–6357).  A
  frame nobody's key opens logs `decryption failed: no matching contact
  key` — **with no source address** — and the connection is closed (6358).
- The key that opened it says who sent it (rmail's per-pair tokens make
  that true).  Their retry timer is reset to "due now", so a reply goes out
  quickly (6360–6370).  This is placed after opening on purpose: a forged
  frame cannot reset anyone's timer.
- On the first frame of a connection, if the sender is a housemate (their
  stored public address equals ours) and the connection came from a private
  address, the address is learned only if it is on our own /24; otherwise it
  is a router relaying the traffic and is logged once, never kept
  (6381–6423; the September 2026 bug).
- Inside the frame is a small HTTP request (method, path, headers, JSON
  body).  Paths starting `/api/` are only served when the opening key belongs
  to an `own = true` contact (the owner's devices, 6453–6456).  Peers use
  `/deliver`, `/delete`, `/update-address`.
- The answer is sealed with the same key and sent back **on the same
  connection** (6546).  That answer is the acknowledgement: the sender marks
  a delivery done only when it arrives.
- The connection stays open for another request (keep-alive, 30 s idle).

### Sending (`run_sync_cycle`, 6556–6638; `http_post_batch`, 2909 onward)

Seven builders run in fixed order (outbox, inbox deletions, address notices,
two consent steps, attachment pieces, cancellations).  Each decides what to
send **and** sends it.  Sending opens every connection of a batch at once,
non-blocking, and waits on them together — for up to 8 seconds — but the
cycle as a whole waits for the batch, so nothing inbound is served
meanwhile (issue 387).

After all seven, bookkeeping moves each contact's **retry timer**:

- a timer is `{interval = integer seconds, next_due = number (seconds since
  1970)}`, one per contact (907–1003);
- reached this cycle → interval back to 30 s; not reached → interval grows
  by 360 s up to 2 hours; every due time gets ±30 s of jitter drawn from
  `/dev/urandom`;
- a contact with nothing queued is simply moved on by 30 s (not backed off);
- one line per cycle names the contacts every attempt failed for (1014–1042);
  a contact's back-off is logged only when its interval moves (975–981);
- nothing is ever dropped: no time limit on a queued item.

### Home-network discovery (6181–6268)

Encrypted UDP packets (`RMAIL-DISCOVER <port> <address>` and `RMAIL-HERE
<address>`, sealed per contact, no name inside since 2026-09-22) are sent by
multicast and to all 254 neighbours on the /24.  They are read only when a
sync cycle runs (7224), not by the main wait.  A UDP packet no key opens is
dropped silently.

### Problems reach the owner as mail (851–874)

`report_problem(direction, id, text)` writes one file per distinct problem —
inbound problems into `inbox/`, outbound into `outbox/` — rewritten in place,
never appended, and `clear_problem` removes it when the problem goes away.
A restart loop therefore cannot fill the inbox with copies.

### Logging (779–828)

Every line goes to standard error first (the service manager's journal),
then to the RAM log file.  The file is rotated at 5 MiB keeping one old copy,
so it is bounded at 10 MiB.  If the file cannot be opened, the daemon says
so once and keeps the journal copy.

### Clients: `docs/thin-client.md` and `docs/service.md`

- **A client is a contact.**  Pairing a device is adding a contacts entry
  with a token and `own = true`; the device connects to the same port with
  the same framing and reaches `/api/`.
- **The server cannot push.**  rmail's thin client polls every 5 minutes
  (and on local file change); "the daemon can't push to you".  rao-chat's
  phase 3 asks for the opposite (a live connection).
- **A service is one mailbox.**  One checkout serves every mailbox; the
  service name, log and process-id file are derived from the mailbox path;
  the installer refuses a service name or port already used by another
  mailbox, and refuses a mailbox name equal to a contact's name (the daemon
  once filed such mail into the sender's own inbox, logged it as delivered,
  and said nothing; `docs/service.md` item 3).  Services restart on failure
  after 5 s.

### `docs/defensive-patterns.md`, in full

Everything in it is an **opt-in hook script**; nothing is in the daemon.  It
separates what the cipher already gives (sealed contents, tamper detection,
no identity in the clear) from what leaks anyway (timing, size, who talks to
whom, connection counts, rhythms), then offers, each with its cost:

| pattern | what it hides or stops | cost it names |
|---|---|---|
| cover traffic (a heartbeat to every contact each cycle) | whether anything real was sent | one packet per contact per cycle; both sides must run it |
| size padding into buckets (1, 4, 16, 64, 128 KiB) | message length | bandwidth; heartbeats must be padded to the same bucket |
| timing jitter (0–30 s sleep before sending) | alignment of send and receive | latency — "makes real-time conversations awkward" |
| decoy recipients | which endpoint is the real reader | bandwidth, linear in decoys |
| Tor (`torsocks`) | your address from contacts and watchers | hundreds of ms; contacts need a hostname for you |
| rate limit per sender | loops and floods | a file per sender |
| attachment type filtering | executables | — |
| hash-chained audit log | undetected tampering with history | off-host backups needed |
| encrypted backup on receipt | plaintext history on a stolen disk | a passphrase file |

"What none of this fixes": the relationship itself (every packet declares
"I know this address"), a compromised endpoint, a disclosed token, and an
observer who sees the whole internet.

---

## 2. RULES

Each rule is something the network, the operating system, the cipher, the
language, or a bug rmail already hit requires.  "Applies" says how it
carries to rao-chat.

| # | rule | why it holds (mechanism) | where rmail shows it | applies to rao-chat |
|---|---|---|---|---|
| R1 | **Acknowledge on the connection the frame arrived on, and only after the message is written to disk.** | The sender keeps retrying until it hears back; an acknowledgement given before the write can be followed by a crash, and the message is lost with the sender believing it delivered.  In rao-chat the receiver *cannot* answer anywhere else: the sender is unknowable, and a connection's source port is a throwaway number the operating system picked, not the sender's listening port. | answer sent after the handler returns, on the same connection (6546); `handle_deliver_message` writes before returning 200 (2238–2255) | **Changed and stronger**: the same-connection answer is not a convenience but the only route.  Filing must be repeat-safe (105's ids already are), because a lost acknowledgement means a repeat. |
| R2 | **Bound everything an unauthenticated peer can make the server hold** — frame length (minimum 28, a maximum), read time, the number of open connections, total bytes buffered. | Before the lock is checked, anyone on the internet can connect.  A length header is read before any proof; whatever it claims is what the server may try to hold. | length 28..64 MiB (2738, 6342); 10 s reads (6313, 6961); **no** cap on open connections, and idle ones are closed only when a sync runs (7216–7221), so N connections each claiming 64 MiB can ask for N × 64 MiB | **Unchanged**, with a limit on connections rmail lacks.  rao-chat's frames are chat lines, so its maximum can be far smaller (open question 4). |
| R3 | **Loop until every byte is sent; read exactly the stated length.** | A non-blocking or large send hands over only what fits in the kernel's buffer and says how much. | the partial-send bug, 2026-03-25 (completed issue 204; 2715–2727, 6997–7016) | **Unchanged.** |
| R4 | **One slow or dead peer must not delay any other peer, nor the listening side.** | A connect to a silent address waits for its full timeout; anything waiting in line behind it waits too. | issue 387 (open): the sync cycle blocks the loop — "94% of every cycle" waiting on a contact gone four months; this caused issue 386's duplicate uploads | **Unchanged, and sharper**: rao-chat sends immediately to every member, so a room with one dead member must not hold up the rest. |
| R5 | **A code error in one piece of work ends that piece only, and the loop's timers still move.** | If an error skips the step that pushes timers forward, everything stays due, the wait before the next pass is zero, and the same error repeats as fast as the machine can run. | commit `52d8583` and issue 397 (2026-09-22 → 23): 1,091,617 identical lines, 200 MB of RAM log, all outbound mail stopped.  Requests already contain errors per connection (7061–7064). | **Unchanged.** |
| R6 | **The server's own writes must not wake the server, and a message that tells a peer nothing new must not produce a reply.** | A write fires the file watcher (or the change bell); if that starts work that writes again, or tells a peer who answers in kind, two servers feed each other forever. | rewriting an unchanged contacts file → watcher → sync → announce → peer rewrites → announces back: "1,500 exchanges in 15 seconds", "374KB of log in seconds" (2570–2576, 2592–2621); the drain after each cycle (7237–7252) and its own bug, that it also eats *other* people's notices (issue 396) | **Unchanged and central to 207**: "sync members whenever a new member is noticed" must send only when the set actually grew, and receiving a list that adds nothing must send nothing. |
| R7 | **Back off per destination, advance once per round no matter how many items are queued, and draw jitter from a real random source.** | Six queued messages to one silent address are one failure, not six.  A fixed-seed generator produces the same "random" schedule every start, so many servers stay in step. | per-contact timers (issue 377: 5,700 attempts a day at a superseded address); commit `2ed6129` (backoff multiplied per message, 30 s → 2,190 s in one cycle); `/dev/urandom` jitter because the seeded one was deterministic (942–946, 6689–6699) | **Changed**: the destination is an (address, port) pair, not a person.  rmail resets a contact's timer when that contact is heard from; rao-chat can't — an opened frame proves room membership, not which pair sent it (open question 9). |
| R8 | **Every periodic task must be part of the loop's wake-up calculation.** | An idle server sleeps in the wait; a check that runs only "when something else happens" never runs on a quiet machine. | issue 379: the address check ran only at startup; a moved address went unnoticed 46 days, 41 notes stranded (6653–6663); now in the wait calculation (7105–7107).  Same class: discovery packets are still read only when a sync runs (7224). | **Unchanged**: 209's summaries, 202's retries and any address re-check all go on the same clock. |
| R9 | **Claim the listening ports first; if one cannot be claimed, say so where the owner looks, named by the problem.** | Router probing and address lookups can take seconds; a collision found after them wastes that time and hides the cause. | 6794–6846 | **Changed**: rao-chat claims one port per mailbox, so "one port failed" needs an answer (open question 3). |
| R10 | **No default port, no default identity; a missing or unreadable setting stops the program.** | A default can only fire on a mistake, and then it silently collides with something real. | 8025 fallback removed (6737–6754, issue 382); folder argument refused (80–90) | **Already rao-chat's** (strict config, declared settings). |
| R11 | **The address a connection came from is the sender's own only if it came straight across the home network; private ranges are exactly 10/8, 172.16/12, 192.168/16, plus 100.64/10 and 169.254/16.** | Through a router's loop-back the source is the router.  172/8 is mostly public addresses. | commit `f0f4814` (172/8), `aad3f4c` and 6381–6423 (router mistaken for a housemate, September 2026) | **Unchanged, and it meets 204**: a call-back to a router's address may be forwarded to the right machine and "confirm" an address that only works inside the house (section 4). |
| R12 | **A fresh random 12-byte nonce for every frame, from the operating system's random source.** | Two frames sealed under one key with one nonce expose both.  In rao-chat, many servers seal with one room key, so a counter cannot be coordinated; only randomness works.  A forked worker that copies a seeded generator repeats its parent's numbers. | `crypto.random_bytes(12)` per frame (2711, 2750) | **Unchanged**; matters for any formation that uses several processes or threads. |
| R13 | **Every effect of a frame must be safe if the same frame is delivered again later, to any member, by anyone who recorded it.** | A sealed frame stays valid forever; the room key opens it at every member's server, and nothing in the frame says when or to whom it was meant. | **Not found in rmail**: no replay defence in `rmail.lua` or `docs/encryption.md`.  rmail's per-pair keys limit a replay to the same pair; a replayed `/update-address` would, as far as I can read (2500–2682), be applied again. | **Changed and stronger**: rao-chat's shared room key widens the replay to every member.  Messages are safe (ids); `hello` and `leave` are safe (call-back); a replayed **members** list can re-add a member who has left (open question 7). |
| R14 | **Nothing learned from the network becomes a file path without cleaning.** | `../` in a received name escapes the folder. | commit `8534c84`, 2026-02-16 | **Met by construction**: rao-chat's folders are random local tags, never sent.  Keep it so. |
| R15 | **Write only the fields that belong on disk.** | A table written with `tostring` becomes `table: 0x…`, a fresh pointer each time: the file is corrupted and any hash of it never settles. | commit `7e765de`, 2026-08-03 | **Already met**: 006's entry writer checks every field. |
| R16 | **Anything that can repeat must write a bounded amount.** | A stuck condition logs every cycle forever; real events drown (issue 371). | log rotation at 5 MiB (779–828); problem files rewritten in place (851–874); back-off logged only on change (975–981) | **Unchanged**; includes 203's failed-decryption log (a flood writes one line per frame). |
| R17 | **A failed-opening record must carry the source address.** | A line with no address cannot feed fail2ban or any person. | rmail's does not (6358); UDP failures are not logged at all | **Changed**: 203 needs it. |
| R18 | **LuaJIT limits: at most 60 upvalues per function and 200 locals per function.** | Language limits; exceeding them fails to load. | commit `579e860` (the 540-line main crashed LuaJIT); comments at 904–906, 6681–6682 | **Unchanged**; rao-chat's many small modules already avoid it. |
| R19 | **`select` has a descriptor ceiling.** | LuaSocket's `select` rests on the system `select`, which on Linux handles at most 1024 descriptors.  I did not find LuaSocket's source on this machine to confirm its exact check. | rmail has one port, so never near it | **New for rao-chat**: each mailbox costs 2–3 sockets (IPv4, IPv6, maybe UDP); a home in 300 top-level rooms is near 900 before a single connection. |
| R20 | **One home per service, and everything per home named after its path.** | Two services with one name replace each other; two daemons appending to one log interleave. | commit `fd980a5`; `docs/service.md` | **Unchanged**, and needed by 210: three homes on one machine must not share a log, RAM folder or failed-decryption file. |
| R21 | **Record "the other side has it" per item, when it confirms, not at the end of a batch.** | An error late in a batch otherwise throws away the record of work that succeeded, and it is all redone. | issue 386: 44 files, 65 uploads | **Unchanged**: 202's per-address "not yet delivered" state moves item by item. |

**Owner-made rule (rao-chat only):** *nothing is answered in the clear.*
rmail answers a plaintext `GET ` with its name (6326–6337), which tells any
port scanner "rmail lives here, and is called X".  rao-chat's planning
document, section 5: "Nothing about a room travels in the clear."  A mailbox
port should close on anything that does not open.

### rmail's defensive patterns: rules or choices?

| pattern | rule or choice | reason |
|---|---|---|
| sealed contents, tamper check | **rule** | the cipher's job (201) |
| no identity in the clear; the lock says which key | **rule** for rao-chat | owner's decision; and rmail removed `from`/token fields for the same reason (`f277d9a`) |
| bounded reads, timeouts | **rule** | R2 |
| cleaning names from the network | **rule** where names become paths; rao-chat avoids it | R14 |
| rate limit per sender | **choice**, and "per sender" cannot exist in rao-chat; only per source address | owner (203): "rao-chat builds no flood defence of its own beyond this log" |
| cover traffic, padding, decoys | **choice** | costs bandwidth; hides metadata the owner has not asked to hide |
| timing jitter / batching | **choice**, and in conflict | planning section 5: rao-chat sends "immediately" |
| Tor | **choice**, and in conflict with 204 | a Tor exit cannot be called back (section 4) |
| hash-chained audit log | **choice** | fits rao-chat's append-only `log`; not asked for |
| encrypted backup | **choice** | not asked for |
| attachment filtering, auto-consent | not applicable | rao-chat is text only (planning question 9 open) |

---

## 3. CHOICES

| choice | rmail's value | what it traded | rao-chat already decided? |
|---|---|---|---|
| threads | one OS thread, coroutines + `select` (completed issue 104) | no locks around state files, versus no use of a second core and head-of-line blocking (issue 387) | owner, 201: "if we need more speed, we make the decoding multithreaded" |
| sending | inline sync cycle, batch waits ≤ 8 s | simple state; inbound stalls | 202: send **immediately** on filing |
| unit of retry | per contact | one timer per person | per (address, port) pair (202) |
| back-off numbers | 30 s floor, +360 s steps, 2 h ceiling, ±30 s, never dropped | ~12 tries a day to a dead peer | planning section 5 quotes "30 seconds … up to 2 hours … never give up"; 202 keeps "never give up" |
| ports | one port for peers, devices and UDP discovery | one router forward; no separation | a port **per mailbox** (planning "Mailboxes, 2026-09-25"); device port undecided (open question 1) |
| request format | an HTTP request with JSON inside each frame, dispatched by path | readable, extensible; bigger | 201: an inner **kind** (`message`, `hello`, `members`, `members-ask`, `leave`, `did-you`, `summary`) |
| keep-alive | 30 s idle; known sender's key tried first | fewer trial openings | not decided |
| frame size | ≤ 64 MiB (body ≤ 50 MiB, 128 KiB for hook bodies) | attachments in one frame | not decided (open question 4) |
| key lookup | contacts file re-read from disk on each trial opening (2774) | always current; cost grows with file size per frame | not decided; 002 reads entries fresh each call |
| outside edits | kernel watchers on `outbox/` and `contacts`, and a drain | a hand edit takes effect at once; own writes must be drained | rao-chat has an in-process change bell (005), which hears only its own program; outside edits undecided (open question 2) |
| config reading | skips unreadable lines silently (35–54) | lenient | **decided otherwise**: every unknown line or value is an error (round 4) |
| missing message id | a new random id is invented (2167) — a fallback | old senders keep working | **decided otherwise**: ids required (105) |
| where problems go | notices in `inbox/` / `outbox/`, rewritten in place | the owner sees them where they look | not decided; a room notice is the nearest (planning section 7), but a server-level problem belongs to no room (open question 10) |
| log | stderr + RAM file, 5 MiB × 2 | bounded; lost at reboot | house rule: `tmp/shared-memory/`; 203 asks RAM or disk |
| address re-check | 24–48 h, redrawn each time; 1 h after no answer | drifts through the day, not a fingerprint | planning section 5: "every day or two" |
| startup announce | address to every contact at boot | a restart repairs stale addresses | not decided |
| discovery | UDP on the same port, read at sync time | one port | planning section 5 keeps discovery |
| health check | plaintext `GET ` answered with the name | easy probing | **decided otherwise** (nothing in the clear) |
| vanished mailbox | exit after two misses 3 s apart | USB drives | not decided |
| defences | all opt-in hooks | the daemon stays small | 203: a log for fail2ban, nothing else |
| service | one per mailbox | isolation between mailboxes | rao-chat: one home server holds many mailboxes, so one service per **home** (phase 6) |

---

## 4. EDGE CASES ALREADY HIT

| date | what happened | what it teaches rao-chat |
|---|---|---|
| 2026-02-16 | received subjects and file names escaped their folder (`8534c84`) | names from the network never become paths (R14) |
| 2026-03-24 | identity was sent inside the body as well as proved by the key; removed (`f277d9a`) | the lock is the only identity; in rao-chat it names a room, never a person |
| 2026-03-25 | partial sends truncated big frames; the hunt went through three wrong fixes to home-network discovery first (completed issue 204) | R3; and a failure shaped like "the network" was a local bug |
| 2026-03-25 | a discovery reply fell back to answering the sender's address when its own was unknown; removed as "nonsensical" (`1bc1cbf`) | an early instance of the house rule against fallbacks |
| 2026-03-25 | deletes that both ends made at once stuck forever until "not found" was treated as done (`db58060`) | a repeated request whose goal is already reached succeeds |
| 2026-03-25/27 | Lua 5.4 and LuaJIT upvalue limits crashed `main` (`3ff8117`, `579e860`) | R18 |
| 2026-03-27 | one connection at a time: a long transfer blocked every other request (completed issue 104) | the coroutine loop; the rest of the lesson is 387 |
| 2026-04-12 | a 0.5 s polling loop replaced by waiting on sockets and file watchers (`c3f1f93`) | sleep until there is work |
| 2026-08-03 | runtime tables written into contacts as `table: 0x…`; contact sync thrashed forever on a hash that never settled (`7e765de`) | R15; anything hashed for comparison (209's fingerprints) must be of stable, written fields |
| near 2026-09-22 (issue 388 work; the date is not in the comment) | two idle daemons re-announced unchanged addresses to each other, 1,500 exchanges in 15 s (2570–2621) | R6 |
| 2026-08-06 → 09-21 | the address check never re-ran; 46 days unreachable (issue 379) | R8 |
| 2026-09-21 | a second install replaced the first mailbox's service; a mailbox named like a contact filed mail into its own inbox, "delivered", silently (`fd980a5`) | R20; one name must never mean two things |
| 2026-09-22 | 5,700 attempts a day to an address its owner had replaced months before (issue 377) | R7; and a superseded address should stop being tried — rao-chat's "addresses are added freely" has the same risk (open question 8) |
| 2026-09-22 | back-off stepped once per queued message: 30 s → 2,190 s in one cycle (`2ed6129`) | R7 |
| 2026-09-22 | 172/8 counted as private; CGNAT and link-local missing (`f0f4814`) | R11, with boundary tests |
| 2026-09-22 | the sync cycle held the phone off 94% of the time (issue 387, open) | R4 |
| 2026-09-22 | the phone lost the record of 44 successful uploads and sent 65 (issue 386) | R21 |
| 2026-09-22 | a mailbox with no contacts had no timer at all, so it only noticed its outbox by luck (`12861e4`) | every state, including "empty", needs something on the clock (R8) |
| 2026-09-22/23 | file-change notices from people were thrown away with the daemon's own (issue 396) | "was this my own write?" must be answered per write, not by draining everything |
| 2026-09-23 | one old attachment record made every sync throw; 1,091,617 lines, 200 MB, all mail stopped (`52d8583`, issue 397) | R5; and "a pass that plans the same list twice is a bug, not a cap" (397) |
| 2026-09 | a router's loop-back address filed as a housemate's; every send refused (`aad3f4c`, 6381–6423) | R11; call-backs through a hairpin (below) |
| undated (comments 942–946, 6678–6680) | `math.random` with a fixed seed made "random" schedules identical on every boot | R7, R12 |
| 2026-07-10 (issue 371) | a week of identical "unreachable" lines hid every real event | R16 |

**Three rao-chat edge cases rmail's history points at but never hit:**

- **Hairpin call-backs.**  A housemate's server reaches ours through the
  router; the connection's source is the router.  If 205 calls back "the
  address the hello came from", it calls the router, which may forward the
  port to the right machine — confirming an address that works only inside
  the house, and that outsiders will be told about by 207.
- **Tor and call-backs.**  The planning document names Tor as a reason the
  sender is unknowable.  A Tor exit address cannot be called back, so under
  204 a member who only sends through Tor is never confirmed.
- **Three homes on one machine all come from 127.0.0.1.**  For 210, each home
  must listen on **and send from** its own loopback address (Linux accepts
  all of 127.0.0.0/8), or every frame appears to come from one address and
  neither the call-back check nor the ignore list can be shown working.

---

## 5. REFEREE TESTS

Written from the rules above, not from rmail's code or rao-chat's.  Each
names a deliberately broken server it must catch.

| # | rule | test | broken version it must fail |
|---|---|---|---|
| T1 | R1 | Kill the receiving server at random points between reading a frame and answering; restart it.  Every message is filed exactly once, and the sender stops retrying only after a real answer. | answers before appending to `log` |
| T2 | R2 | Open 500 connections that each send a 4-byte header claiming the maximum length, then trickle one byte a second.  The server's memory stays under a stated bound, and a genuine frame on connection 501 is filed within 2 s. | no connection limit; or reads the claimed length into memory before any cap |
| T3 | R3 | Deliver a maximum-size frame over a socket whose send buffer is shrunk to 4 KiB.  It opens. | one `send` call per frame |
| T4 | R4 | One member address is a black hole (a firewall drop, or a listening socket that never accepts).  A message reaches every other member within 1 s; an inbound frame arriving meanwhile is answered within 1 s. | connects to members one after another, waiting each out |
| T5 | R5 | Plant a room whose entry makes filing throw.  Other rooms keep receiving; the log gains one entry (with the calling chain) per ordinary cadence; loop wake-ups per minute stay bounded. | a protected call around the whole round that skips the timer step |
| T6 | R6 | Two idle homes with identical member lists run 10 minutes: frames exchanged ≤ what the summary timer alone produces.  Then one newcomer joins a room of five homes: the total `members` frames are bounded (at most one per home per new member) and every home's list converges. | sends `members` on every change-bell ring, including rings caused by writing a received list |
| T7 | R7 | Queue six messages to a dead address; after one round its retry interval has advanced by exactly one step.  Start two servers with the same config: their jitter sequences differ. | one step per queued message; `math.randomseed(0)` |
| T8 | R8 | A quiet server (no traffic) with a summary timer of T seconds sends its summary within T + 1 s. | runs periodic work only after handling a connection |
| T9 | R9, R10 | Start with a mailbox port already taken: the server exits non-zero within 1 s, writes a report naming the port and the config line, and makes no outbound connection first.  Start with `port` missing: exits naming the missing line. | probes the router or announces before binding; picks another port |
| T10 | owner rule, R17 | Send `GET / HTTP/1.0` and then random bytes to a mailbox port: zero bytes come back, the connection closes, and the failed-decryption log gains one line per attempt with the source address. | a plaintext health check; a log line with no address |
| T11 | R11 | The private-range test against 172.15.0.1, 172.16.0.1, 172.31.255.255, 172.32.0.1, 100.63.255.255, 100.64.0.1, 100.127.255.255, 100.128.0.1, 169.254.1.1, 127.0.0.1, a hostname. | `^172%.` |
| T12 | R13 | Record every frame on the wire during the demo; later replay each one to every member, including after a confirmed leave.  No room's members, flags or log change, except duplicates counted. | a received `members` list re-adds a member whose leave was confirmed; or a message's source address is recorded as heard before the duplicate check |
| T13 | R12 | Over 100,000 frames from several workers (whatever the formation), no nonce repeats under one room key. | workers forked after seeding one generator |
| T14 | mailboxes | A frame sealed for a room in mailbox A, sent to mailbox B's port (B not sharing A's port), is a failed decryption; a counter of keys tried equals B's key count. | tries every key the home holds on every port |
| T15 | R20 | Three homes on one machine: no two share a log, RAM folder, failed-decryption file, or process-id file. | a fixed `/tmp/rao-chat.log` |
| T16 | R21 | Deliver to five members, make the fourth answer with an error; the first three are recorded delivered, and a restart resends only to the last two. | records delivery state at the end of the round |

---

## 6. A DIFFERENT FORMATION

All four meet the rules above; they differ in shape.  How phase 1's modules
would sit in each is given for all of them at the end.

### A. One wait for everything (rmail's shape, with 387 fixed)

One process, one loop.  Every mailbox's listening sockets, every inbound
connection **and every outbound connection** wait in the same `select`
(or `epoll`) call; nothing ever waits outside it.  Work is split, as
issue 397 designs, into check → record plan → act → check results → record
outcome, so a thrown error ends one pass's acting and the timers still move.

- **Gains**: no locks; the change bell (005) works unchanged, because
  everything is one program; the closest to what is already proven.
- **Costs**: trial opening is on the one thread, so cost grows with rooms
  held; the descriptor ceiling (R19) is shared by every mailbox; one bug in
  the loop stops every mailbox.  And it is rmail's shape — the owner asked for
  "different each time".

### B. One loop per mailbox

Each mailbox (each listening port) is its own small process with its own
loop, its own keys, its own retry timers and its own log.  A thin parent
starts one per line of `mailboxes`, restarts one that dies, and does
nothing else.

- **Gains**: a mailbox that crashes or floods cannot touch another (R4, R5
  by construction); trial opening is naturally split (each process holds
  one mailbox's keys — the owner's "multithreaded decoding" for free, across
  cores); the descriptor ceiling is per process; a flood on one port is
  visible as one process's load.
- **Costs**: some state is per **home**, not per mailbox — `config`, the
  `ignore` list, `people/` links, and the tree checks when a child room's
  parent sits in another mailbox (the waiting-mailbox case, and merging).
  Those must be read from disk, and a change in one process must reach the
  others: the change bell rings only inside one process, so a watcher or a
  pipe between them is needed.  Merging a mailbox into its parent's (planning
  "Five more … round 3", item 4) becomes moving a room between processes.
  Many top-level rooms mean many processes.

### C. A pipeline of small programs joined by RAM spools

Four stages, each a program (or a thread), passing records through folders
under `tmp/shared-memory/`:

1. **Listener** — holds every mailbox port; reads bounded frames (R2);
   writes each raw frame to a spool as `{mailbox tag = string, source
   address = string, source port = integer, arrived = integer, bytes =
   string}` and holds the connection open waiting for its answer.
2. **Openers** — a pool of workers, each taking spooled frames and trying
   that mailbox's keys; a failure writes the failed-decryption line (203); a
   success writes `{room tag, kind, fields}`.  This is where the owner's
   multithreaded decoding lives, and the only CPU-heavy stage.
3. **Filer** — the single writer to `rao-home`: files messages (105),
   members (103), flags (102), rings the change bell, and marks the spool
   entry "filed", which lets the listener send the answer (R1).
4. **Sender** — the per-address outboxes, retry timers, call-backs (204),
   all non-blocking.

- **Gains**: each stage's failure is contained and visible as a pile-up in
  its spool (a figure the demo can show); one writer means no locks on
  `rao-home`; the house preference for separating data generation from its
  use holds stage by stage; the pool matches "a thread pool is distributed
  resolving of a stack of coroutines".  A crash anywhere loses nothing: an
  unanswered frame is retried by its sender.
- **Costs**: more parts and more process management; the answer's latency is
  the sum of four hand-offs; the spool is itself untrusted input for the next
  stage and needs its own format checks; the listener must still hold
  connections while waiting (so R2's connection limit matters more).

### D. Trial opening moved into the C library

Keep A's single loop, but give the crypto library (the C part, as
`rmail_crypto.c` is to rmail) one call: "here is a frame and a list of keys;
say which opens it", done in C across a small pool of operating-system
threads.  Lua never loops over keys.

- **Gains**: the smallest change that answers "if we need more speed";
  no Lua-level concurrency at all.
- **Costs**: C to write and test; keys must be handed to C (a copy of every
  room key in native memory); leaves A's one-loop failure and descriptor
  costs.

### Where phase 1's modules sit, in any formation

- **One entry per room in rmail's contacts format** (006) is the key store:
  a mailbox's keys are its rooms' `token` fields (made into keys once, then
  kept until the `token` bell rings).  rmail re-reads its contacts file on
  every frame (2774); rao-chat can instead cache and refresh on the bell —
  but only if outside edits also reach it (open question 2).
- **The change bell** (005) is the server's "something changed" signal.  It
  is in-process: formations A, C (inside the filer) and D keep it as is; B
  needs it carried between processes.  R6 applies to it directly: a listener
  that sends `members` on a `members` ring will answer its own writes.
- **Strict config and declared settings** (016, 017) mean every phase 2
  timing (retry floor and ceiling, answer time limit for 204, summary
  interval for 209, maximum frame size, connection limit) must be a declared
  setting with no default — so rmail's numbers above are starting values to
  write into config, not constants.
- **The mailboxes file** (014) is the list of ports to claim at startup
  (R9); `shared_ports_of` names the ports where trial opening must span
  several mailboxes (and the warning the owner asked for).
- **The message log** (105) gives R1's repeat safety and R13's safety for
  message frames.

**My leaning: C, the pipeline**, with the openers as the pool.  rmail's
recurring class of bug (issues 104, 387, 386, 397, commit `52d8583`) is one
stuck piece of work stopping everything else; C makes each piece a separate
program whose stuck state is a growing folder anyone can `ls`.  B is the
close second, and would be first if the owner prefers one process per
router forward.

---

## 7. OPEN QUESTIONS FOR THE OWNER

Most blocking first.

1. **Which port do the owner's devices (phase 3) and the web client
   (phase 4) connect to?**  rmail uses one port for peers and devices.
   rao-chat's mailbox ports should answer nothing in the clear, but a
   WebSocket starts with a plaintext HTTP request, and a browser must fetch
   the page itself.  A separate device port per home, or devices on a
   mailbox port?  This shapes every formation's listener.
2. **Hand edits while the server runs.**  The change bell hears only its own
   program.  May a person edit a room's `entry`, `config`, `mailboxes` or
   `ignore` with a text editor while the server runs?  If yes, the server
   needs a file watcher and a per-write "was this mine?" test (rmail's
   drain lost other people's changes, issue 396).  If no, the server should
   say so when it notices.
3. **One mailbox port cannot be claimed at startup.**  Stop the whole home
   server (errors over fallbacks), or report that mailbox and run the rest?
4. **Maximum frame size**, and **a limit on open connections** — and does
   such a limit count as the "flood defence of its own" that 203 rules out?
5. **Formation**: A, B, C (my leaning) or D?
6. **Tor.**  A member reachable only through Tor cannot be called back
   (204).  Accept that such members are never confirmed, or plan for onion
   addresses?
7. **A replayed members list** can re-add a member whose leave was
   confirmed (R13).  Should addresses learned from a `members` list also be
   called back before they are added, or should a confirmed leave be
   remembered so an old list cannot undo it?
8. **Superseded addresses.**  "A move adds the new address beside the old."
   rmail spent months dialling an address its owner had replaced.  Is an
   address ever retired (for example, once the new one has answered), or
   only backed off to the 2-hour ceiling forever?
9. **What resets an address's back-off?**  rmail resets a contact's timer
   when the contact is heard from.  In rao-chat an opened frame names the
   room, not the pair.  Reset only on a successful send to that pair?
10. **Where server-level problems go** (a port that will not bind, a spool
    piling up): rmail writes notices into the inbox.  rao-chat's notices are
    per room; a problem belonging to no room needs a place.
11. **The demo's ports and addresses** (210): with no default ports, does
    the demo write fixed ports into each demo home's config, or ask the
    system for free ones and write those in?  And may it give each home its
    own loopback address (127.0.0.2, .3, .4) so source addresses differ?
12. **Is the plaintext-answer rule absolute?**  I have written "nothing is
    answered in the clear on a mailbox port" as a rule from planning section
    5; confirm it also covers a health check.

## Where I looked and did not find

- **Replay protection**: `rmail.lua`, `docs/encryption.md`,
  `docs/protocol.md` (searched for replay, fresh, timestamp, captur).  None.
- **A limit on simultaneous connections**: `rmail.lua` main loop and
  `handle_request`.  None.
- **LuaSocket's own `select` source**, to confirm the descriptor ceiling:
  not in `r-mail/deps`; the whole-machine search did not finish.
- **The date of the address ping-pong bug**: only the code comments
  (2570–2621) describe it; I tied it to the issue 388 work by proximity.
