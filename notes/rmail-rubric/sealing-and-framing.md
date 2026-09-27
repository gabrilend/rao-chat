# rmail as a rubric: sealing and framing

Area: how rmail turns a token into a key, the frame on the wire, nonces,
finding which contact's key opens an incoming frame (trial opening), what
happens to a frame no key opens, size limits, what travels in the clear,
and the request/record shapes inside a frame.

For rao-chat issues: **201** (the room key and sealed frames) and **203**
(the failed-decryption log).  Written 2026-09-26 under
`strategems/other-peoples-software-as-a-rubric.md`: rmail was read, not run,
and nothing in r-mail was changed.

Sources read: `rmail.lua` (the encryption helpers at 2686–2785, the request
parser at 2788–2822, the sending side at 2843–2890, the request handler at
6312–6550, LAN discovery at 6180–6300, the server loop near 7115–7135),
`rmail_crypto.c` (all 169 lines), `docs/protocol.md`, `docs/encryption.md`,
`docs/defensive-patterns.md`, the Android client's
`clients/android/app/src/main/kotlin/com/rmail/app/crypto/Crypto.kt`
(a second, independent implementation of the same frame), issues 104, 204,
327, 348, 366, 367, 393, and `git log` of r-mail.  The LuaSocket manual
consulted for one finding is
`/home/ritz/programming/ai-stuff/libs/lua/luasocket/lib/luarocks/rocks-5.1/luasocket/3.1.0-1/docs/tcp.html`.

Line numbers are as of r-mail commit at HEAD on 2026-09-26.

---

## 1. What this area does in rmail

### The pieces of data

| thing | datatype | what it holds |
|---|---|---|
| **token** | text string, any bytes, stored as `name.token = ...` in the contacts file | the secret two people share; the only thing a person ever types or sees |
| **key** | binary string, exactly 32 bytes | SHA-256 of the token's bytes, exactly as they are stored — no trimming, no salt, no stretching (`rmail.lua:2689–2691`).  The Android client hashes the token's UTF-8 encoding (`Crypto.kt:15–18`) |
| **nonce** | binary string, exactly 12 bytes | fresh random bytes from OpenSSL's random generator for every frame (`rmail_crypto.c:49–67`, called at `rmail.lua:2711`); Android uses `SecureRandom` |
| **sealed body** | binary string, same length as the plaintext | the plaintext run through AES-256 in GCM mode |
| **check value** (GCM tag) | binary string, exactly 16 bytes | computed from the key, the nonce and every byte of the sealed body; the receiver recomputes it and refuses the frame if it differs |
| **frame** (TCP) | binary string | `[length: 4-byte unsigned integer, big-endian][nonce: 12][sealed body: N][check value: 16]`.  The length counts everything after itself, so it is `N + 28` (`rmail.lua:2714`) |
| **datagram** (UDP, LAN discovery only) | binary string | the same without the length: `[nonce][sealed body][check value]` (`rmail.lua:2749–2755`) — a datagram already has a boundary |
| **plaintext request** | text | HTTP-shaped: a request line (`POST /deliver HTTP/1.1`), headers (`Host`, `Content-Type: application/json`, `Content-Length`, `Connection: close`), a blank line, and a JSON body (`rmail.lua:2843–2851`) |
| **plaintext response** | text | the same shape with a status line (`HTTP/1.1 200 OK`) and a JSON body |
| **JSON body of a delivery** | object | `type` (string: `message`, `update`, `attachment_request`, `attachment_response`, `attachment_chunk`, `chunk_failed`), `message_id` (string, a UUID), `subject` (string), `body` (string), `mtime` (integer seconds, optional).  No sender name and no token: both were removed on 2026-03-24 (commit f277d9a); the key that opened the frame is the only statement of who sent it |

There is no additional authenticated data: GCM's "associated data" input,
which would let the length or anything else be covered by the check value
without being encrypted, is not used (`rmail_crypto.c:95–101`).

### Sending, step by step

1. The sync code builds the plaintext request as text (`rmail.lua:2844–2850`).
2. It turns the contact's token into the key by hashing it — every time,
   per request (`rmail.lua:2851`).
3. It asks for 12 random bytes for the nonce and seals the request, which
   gives the sealed body with the 16-byte check value on the end
   (`rmail.lua:2852–2853`).  If sealing fails the connection is closed and
   the request is dropped for this pass.
4. It writes the 4-byte length, then the nonce, then the sealed body and
   check value, looping until every byte has left, because a socket may
   accept only part of a large write at a time (`rmail.lua:2861–2877`,
   the fix from issue 204).
5. It waits for one frame back, opens it with the same key
   (`rmail.lua:2880–2882`), and reads the HTTP status from the plaintext.
   Status 200 means delivered.

### Receiving, step by step (`handle_request`, `rmail.lua:6312`)

1. Read exactly 4 bytes, with a 10-second wait (30 seconds while an
   already-identified connection is idle between requests, `6322`).
2. **If those 4 bytes are the text `GET `**, this is not a frame but a
   plaintext health check: the server answers in the clear with
   `{"ok":true,"name":"<the mailbox's own name>"}` and closes (`6327–6336`).
   This works only because `GET ` read as a length is 1,195,725,856, larger
   than the size cap, so no genuine frame can start with those bytes.
3. Otherwise the 4 bytes are the length.  A length under 28 (no room for a
   nonce and a check value) or over 64 MiB (67,108,864) closes the
   connection before anything else is read (`6341–6342`).
4. Read exactly that many bytes (`6343–6344`).
5. **Open it.**  If an earlier frame on this same connection was already
   identified, try that contact's key first (the "fast path",
   `6347–6352`, added 2026-03-27 with keep-alive connections).
   Otherwise, **trial opening** (`trial_decrypt`, `2770–2785`): reload the
   contacts file, and for every contact that has a token, hash the token
   into a key and try to open the frame with it.  The first key that opens
   it wins, and that contact's name becomes "who sent this".  The order in
   which contacts are tried is Lua's table order — unspecified.
6. **No key opened it:** one log line, `decryption failed: no matching
   contact key`, with the time in front (`6358`, the log format at `814`).
   The address the frame came from is not in the line.  The connection is
   closed without a reply — the sender learns nothing except that the
   connection ended.
7. **A key opened it:** the contact is recorded as heard from (their retry
   timer drops to the floor, `6365–6371`); the plaintext is parsed as an
   HTTP request (`parse_request_string`, `2788`; a declared body over
   50 MiB is refused at `2813`); the path and the JSON `type` pick a
   handler (`6424–6541`, `4441–4454`); the handler's answer is written into
   a buffer, sealed with the same key, and sent back as one frame (`6546`).
8. Loop to step 1 for the next request on the same connection.

Each incoming connection runs as a coroutine in one select loop
(`7115–7135`, issue 104), so one slow connection does not stop the others
from being read; but trial opening itself is plain computation and holds
the whole loop while it runs.

### LAN discovery uses the same seal

`RMAIL-DISCOVER <port> <lan-ip>` and `RMAIL-HERE <lan-ip>` go out as sealed
datagrams, one per contact on the same public address, each sealed with
that contact's key (`6189–6219`).  A receiver tries each contact's key in
turn (`6221–6260`).  Since issue 393 (2026-09-22) the datagrams carry no
name: the key that opens one says who it is from.

---

## 2. RULES

Each rule: what must hold, why (the mechanism), where rmail shows it, and
whether it applies to rao-chat unchanged, changed, or not at all.

### R1. A nonce must never repeat under one key.

- **Why.**  GCM encrypts by XOR-ing the plaintext with a keystream made
  from the key and the nonce.  Two frames with the same key and nonce use
  the same keystream, so XOR-ing the two sealed bodies gives the XOR of the
  two plaintexts, and known plaintext in one reveals the other.  Worse, the
  two check values together let an attacker solve for the secret
  multiplier GCM uses to compute check values, after which they can forge
  frames that pass.
- **rmail.**  12 fresh random bytes per frame from OpenSSL
  (`rmail_crypto.c:59`; `rmail.lua:2711`, `2750`, `2852`); a failure of the
  random generator is an error, not a fallback (`rmail_crypto.c:59–62`).
- **rao-chat: changed in weight.**  In rmail two people share a key.  In
  rao-chat **every member of a room shares one key**, and every member's
  server seals with it independently.  So (a) a counter-based nonce is
  unusable: members cannot coordinate a counter, and two members starting
  from the same counter value would repeat nonces at once; random nonces
  are the only safe choice without a per-sender prefix; (b) the number of
  frames sealed under one key is the sum over all members, including
  hellos, member lists and the periodic cross-check summaries.  With
  random 12-byte nonces the chance of any repeat among n frames is about
  n² / 2⁹⁷.  The usual guidance (NIST SP 800-38D) keeps n under 2³², where
  that chance is about 2⁻³³.  A cross-check that has every one of 1,000
  members send a summary to every other member every 10 minutes is
  1,000 × 1,000 × 144 ≈ 1.4 × 10⁸ frames a day, reaching 2³² in about a
  month.  Past that bound the risk rises smoothly; it is not a cliff.

### R2. The check value must be verified before any byte of plaintext is used, and a frame that fails must yield nothing.

- **Why.**  GCM produces plaintext as it goes; only the final step says
  whether the frame was genuine.  Code that acts on plaintext before that
  step acts on forged data.  This is also what makes trial opening
  possible at all: the wrong key fails the check instead of producing
  garbage that looks like a message.
- **rmail.**  `rmail_crypto.c:147–156` returns nothing unless the final
  step succeeds; nothing is returned in pieces.
- **rao-chat: unchanged.**

### R3. The size must be checked before the body is read, against a limit, on both ends; the smallest valid size is 28.

- **Why.**  The length arrives before any authentication.  A receiver that
  reads and holds whatever length it is told can be made to hold up to
  4 GiB per connection by anyone.  The floor exists because a frame must
  at least contain a 12-byte nonce and a 16-byte check value.  The two ends
  must agree on the cap: a frame the sender considers legal and the
  receiver refuses is a delivery that fails forever and is retried
  forever.
- **rmail.**  `rmail.lua:2738` and `6342` (28 to 64 MiB).  **The Android
  client caps at 16 MiB** (`Crypto.kt`, `decryptFrame`), so a daemon
  response between 16 and 64 MiB would be refused by the phone — the two
  ends of rmail disagree.  I did not find a report of it being hit.
- **rao-chat: unchanged as a rule; the value is a choice (C4).**

### R4. Anything that shares the listening port with frames must be told apart by the first four bytes.

- **Why.**  A receiver reads 4 bytes and must decide what it has.  rmail's
  plaintext health check works only because the text `GET ` read as a
  big-endian number (1,195,725,856) is above the 64 MiB cap.  If the cap
  were ever raised above that, a frame could begin with those bytes and be
  mistaken for a health check.
- **rmail.**  `rmail.lua:6327`.
- **rao-chat: changed.**  The planning document says nothing about a room
  travels in the clear, and the health check sends the mailbox's name in
  the clear to anyone who asks.  If rao-chat keeps any plaintext probe, the
  rule stands; if it keeps none, every 4 bytes are a length and the rule
  disappears.

### R5. The token must be turned into bytes in exactly one defined way, identically on every device.

- **Why.**  The key is the hash of bytes, and a hash of different bytes is
  an unrelated key: one stray trailing newline, one letter typed as a
  different Unicode sequence (é as one code point on one keyboard and as
  "e" plus an accent mark on another), and the two servers cannot open each
  other's frames, with no error that says why — every frame is simply a
  failed decryption.
- **rmail.**  The daemon hashes the stored bytes as they are
  (`rmail.lua:2690`); the phone hashes the UTF-8 encoding of the string
  (`Crypto.kt:15–18`).  These agree for any token that is valid UTF-8 and
  typed the same way; nothing normalises either.
- **rao-chat: applies more strongly.**  rao-chat's tokens are "anything the
  maker likes" and are meant to be read aloud and typed on other people's
  phones and computers, so two ways of encoding one visible token are
  likelier than in rmail.  rao-chat already computes the key the same way
  (`src/room-folders/007-tokens.lua`: the key is SHA-256 of the token,
  and the fingerprint naming a parent is SHA-256 of that key).

### R6. One key must lead to exactly one room (or contact) on a home server.

- **Why.**  Trial opening names the room by which key opens the frame.
  Two entries holding the same token open the same frames, and which one
  "wins" then depends on the order keys are tried — in rmail, Lua's table
  order; in rao-chat with several threads, whichever thread reports first.
- **rmail.**  Does not check; two contacts with one token would be picked
  between arbitrarily (`rmail.lua:2774–2782`).
- **rao-chat: already met** — `src/room-folders/002-room-folders.lua`
  refuses a second room with a held token and treats finding two as an
  error.

### R7. A frame that opens under more than one held key must not be silently given to whichever key was tried first.

- **Why.**  GCM is not "key-committing": someone who knows two keys can
  build one frame that opens validly under both (the published attacks
  are "invisible salamanders", Dodis et al. 2018, and "partitioning oracle
  attacks", Len, Grubbs and Ristenpart 2021).  In rao-chat a member of two
  rooms on the same mailbox holds both tokens and can do this: the same
  frame would be filed as a message in room A by one reader and in room B
  by another, depending on the order their servers tried keys.
- **rmail.**  Not addressed; the first key that opens the frame wins.
  With two-person contacts this needs someone holding two of your tokens.
- **rao-chat: new and applies.**  Either every key on the mailbox is
  tried and two openings is an error, or the sealed body carries a value
  that commits it to one key (section 6, formation B).

### R8. A server that trial-opens with keys made from guessable tokens answers a question for anyone who can reach it.

- **Why.**  Success gets a reply (an acknowledgement); failure gets a
  closed connection.  That difference tells an outsider "some key here
  opened this".  Combined with R7, one crafted frame can test many guessed
  tokens at once (Len et al.'s partitioning oracle), so guessing online
  becomes faster than one guess per frame.  The key is a single unsalted
  SHA-256 of the token, so offline guessing against any captured frame is
  already cheap per guess (the planning document measured about 775,000
  guesses a second per CPU core for two hashes).
- **rmail.**  The success/failure difference is visible (`6358` vs `6546`).
- **rao-chat: applies; its defence is the token's length.**  The
  six-word suggested token already chosen (planning, "Answers from the
  tally, round 2") makes both online and offline guessing hopeless; a
  deliberately guessable token (the public square) is guessable by design.
  The rule matters for the tokens people choose by hand, which the owner
  has decided not to restrict.

### R9. A frame carries no freshness: any frame can be recorded and delivered again later, or sent back to the server that wrote it.  Every record a frame carries must therefore be safe to receive twice, late, or from the wrong direction.

- **Why.**  The key is the same for every frame of a room, forever, and
  nothing in the frame says when or to whom it was sent.  Anyone on the
  path can copy a frame and resend it.  With one shared key in both
  directions, a request A sent to B, sent back to A, opens under A's key
  for B and looks like it came from B.
- **rmail (found by reading, not hit).**  A replayed older `update`
  (`handle_deliver_update`, `rmail.lua:2258–2293`) overwrites the message's
  body with the old text: replaying an earlier edit reverts a later one.
  A reflected `/update-address` would tell A that B has moved to A's own
  address (`handle_update_address`, `rmail.lua:2500`).  Plain deliveries
  are safe to repeat because the same `message_id` from the same sender is
  recognised (`rmail.lua:2175`).  An acknowledgement ("200 OK") names
  nothing, so an old acknowledgement replayed onto a new connection would
  count as delivery of whatever was just sent.
- **rao-chat: applies; much of it is already met by design.**  Messages
  and edits each carry their own id and a repeat is recorded as
  `duplicate` (issue 105; edits are new messages naming the old one, not
  overwrites).  A reflected hello only re-adds an address, and addresses
  are added freely.  A leave notice is confirmed by the call-back check
  (issue 204), which is exactly the defence this rule asks for.  Still
  open: **an acknowledgement must name the message id(s) it acknowledges**,
  or a replayed acknowledgement can mark an undelivered message delivered.

### R10. Writing a frame must send every byte exactly once, counting correctly across partial writes.

- **Why.**  A socket may accept only part of a write.  If the loop loses
  count, the receiver gets a frame with bytes missing or doubled, which
  fails the check value, and the delivery fails with nothing to say why
  (issue 204 spent a long detour into LAN discovery before finding this).
- **rmail.**  Fixed 2026-03-25 (issue 204, commit d4f06c5), but the fixed
  loop still has a latent miscount: LuaSocket's send returns "the index of
  the last byte within [i, j] that has been sent" (manual, line 420), not
  a count, and `rmail.lua:2718–2724` and `2865–2875` add that index to the
  running total.  After one partial write, a successful retry happens to
  land correctly (it returns the final index, which ends the loop), but a
  second partial write in a row over-counts and skips bytes.  It needs two
  consecutive 30-second stalls, so it is rare.  I did not find it reported.
- **rao-chat: unchanged.**

### R11. Nothing that identifies a room, its members, or the person must travel outside the seal.

- **Why.**  Whatever is outside the seal is readable by anyone on the path
  and by anyone who connects.  rmail's own history is a sequence of
  removals of exactly this: the sender's name and token were inside every
  body until 2026-03-24; the mailbox name was inside discovery datagrams
  until 2026-09-22.
- **rmail.**  In the clear: the 4-byte length (so the plaintext size, to
  the byte — `docs/encryption.md`, issue 366, still open), the addresses
  and ports, timing, and the health check's reply with the mailbox's name
  (`6327–6336`).
- **rao-chat: applies, stricter.**  The planning document says nothing
  about a room travels in the clear.  What remains unavoidably visible in
  rao-chat: addresses, timing, the length, and — new with mailboxes — the
  port, which tells an observer which top-level room tree a frame belongs
  to (recorded in planning, "Mailboxes").  Size matters more for chat than
  for mail, because chat messages are short and patterned (C5).

### R12. A failed opening costs the receiver work proportional to the keys it holds; the frame's size multiplies that.

- **Why.**  A frame no key opens is tried against every key before it is
  called failed, and each attempt runs GHASH over the whole frame.  A
  64 MiB garbage frame against 1,000 keys is 64 GiB of hashing.
- **rmail.**  One-contact-at-a-time trial opening on the one thread that
  also runs the select loop, and the token is re-hashed into a key for
  every contact on every frame, and the contacts file re-read
  (`2773–2777`).
- **rao-chat: applies with more weight** — more keys (one per room, not
  per person), which is why mailboxes and threads were chosen.  The cap
  (R3) and the number of keys per mailbox together set the worst case.

---

## 3. CHOICES

| choice | rmail's value | what it traded | has rao-chat decided? |
|---|---|---|---|
| **C1. Key from token** | one SHA-256 of the token bytes; no salt, no stretching | quick trial opening (keys can be computed once) against cheap offline guessing | **Yes, same:** "`SHA-256(token)`, exactly as rmail makes one from a contact's token" (planning §5; issue 201).  Guessing cost handled by six suggested words |
| **C2. Cipher** | AES-256-GCM, 12-byte nonce, 16-byte check value, through OpenSSL (earlier TLS-PSK through LuaSec, replaced 2026-03-24) | a standard, fast-with-AES-instructions cipher; no key commitment (R7) | **Yes, same** (planning §5) |
| **C3. Nonce source** | random per frame | no state to keep, safe across restarts and many senders; a birthday bound instead of a hard one (R1) | Planning §5 says "random 12-byte nonce, as rmail does" |
| **C4. Size cap** | 64 MiB on the daemon, 16 MiB on the phone, 50 MiB declared body | room for 5 MiB attachment chunks, against memory and trial-opening cost per garbage frame | **Not decided.**  rao-chat carries no attachments, so its frames are small; see open question 3 |
| **C5. Padding** | none (issue 366 open since 2026-04-19: power-of-two buckets, 64-byte floor, 16 KiB cap, real length as the first 4 sealed bytes) | simplicity, against leaking each message's size to the byte | **Not decided** |
| **C6. Plaintext inside** | HTTP-style text with a JSON body; one request, one response per frame | readable with familiar tools, and a path per action; costs bytes per frame and a text parser | Issue 201 lists kinds (`message`, `hello`, `members`, `members-ask`, `leave`, `did-you`, `summary`) and "a small encode/decode table"; the shape is **not decided**.  rao-chat's log records are TSV (planning §B.4 answers) |
| **C7. Trial order** | contacts in table order, first success wins, on the loop's thread | nothing gained; order is incidental | **Decided differently:** tried only against the keys of the mailbox the port belongs to, split across threads, no hint in front of frames (planning, answers 2026-09-25, question 3; "Mailboxes") |
| **C8. Per-connection shortcut** | a connection's first identified contact is tried first on later frames | fast repeated frames on one connection | Not discussed |
| **C9. Key caching** | none: every frame re-reads contacts and re-hashes every token | always up to date with a hand-edited contacts file, at SHA-256 × contacts per frame | Not discussed; rao-chat has a change bell (`src/room-folders/005-change-bell.lua`) that could invalidate a cached keyring |
| **C10. Failed frame** | one log line with the time, no address; connection closed without reply | quiet to the sender; nothing for fail2ban to match | **Decided differently:** one line with time and address in a fail2ban-readable shape (issue 203) |
| **C11. Plaintext health check** | `GET ` on the same port answers with the mailbox's name | easy port-forward testing with curl, against announcing a name in the clear | Implicitly **refused** by "nothing about a room travels in the clear" (planning §5) — to confirm (open question 6) |
| **C12. Timeouts** | 10 s to read a frame's parts, 30 s idle between frames on a kept connection, 30 s per write | slow links against held connections | Not discussed |
| **C13. Additional authenticated data** | none | nothing covered but the sealed body | Not discussed (formation D uses it) |

---

## 4. EDGE CASES ALREADY HIT

| date | what happened | what it teaches |
|---|---|---|
| 2026-02-10 → 2026-03-24 | Encryption began as TLS with a pre-shared key via LuaSec (commit 2a6c249), was made mandatory 2026-02-25, and was replaced with the hand-rolled frame (commit 60d309e), removing LuaSec from the install. | The frame format exists to be small and dependency-light; a library that does more (TLS) was the heavier choice for a program that only needs one sealed message each way. |
| 2026-03-24 | The sender's name and the token itself were being sent **inside** every body and checked by an `auth_check`; removed (commit f277d9a). | The key that opens a frame is the identity; a name carried inside can only disagree with it.  A token must never travel, even sealed. |
| 2026-03-25 | Attachment chunks (5 MB, about 7 MB sealed) failed with "chunk failed, will retry": a single socket write sent only what fit in the kernel buffer, the receiver got a short frame, failed to open it, and said nothing (issue 204). | A truncated frame looks exactly like a forged one.  Short-write handling needs its own test.  The fix still miscounts after two partial writes in a row (R10). |
| 2026-03-27 | Keep-alive connections added the per-connection fast path (commit c563129). | Trial opening cost is paid once per connection instead of once per frame. |
| 2026-04-13 | Tokens were being copied into the outbox state file (issue 348, commit 3cd723c); replaced by the token's hex SHA-256. | The same "keep secrets in one place" rule, on disk.  Note: a hash of the token is the key itself, not a safe stand-in, unless it is hashed again — rao-chat's fingerprint hashes twice for this reason. |
| 2026-04-19/20 | `docs/encryption.md` described random padding inside the frame that the code never did (issue 366; doc corrected in commit ab27325). | A property of the wire format must be checked by a test of the wire bytes, not by the document. |
| 2026-09-22 | Discovery datagrams carried the sender's own name and filed the found address under it; when two people named each other differently, the address was filed under a name nobody looked up (issue 393). | Again: the key that opens it names the sender, in the reader's own words. |
| not hit (found reading) | The daemon caps frames at 64 MiB and the phone at 16 MiB (R3). | Two implementations of one frame drift unless one referee checks both. |
| not hit (found reading) | Replayed old edits revert newer ones; reflected address announcements (R9). | A frame's content must be safe to receive twice or backwards. |

---

## 5. REFEREE TESTS

Written from the rules, not from rmail's code or rao-chat's.  Each names a
deliberately broken version the test must catch; a referee that passes the
broken version grades nothing.

1. **Key from token (R5, C1).**  The key for token `abc` is the 32 bytes
   whose hex is
   `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`
   (the standard SHA-256 test vector); a token with a trailing newline gives
   a different key and the entry reader either strips it by one documented
   rule or refuses it.  A token typed as `é` (one code point) and as `e`
   plus a combining accent is treated by one documented rule.
   *Broken versions:* key as 64 hex characters instead of 32 bytes; token
   read with its line ending; two input paths (typed vs file) that encode
   differently.
2. **Frame layout (C2).**  For a plaintext of n bytes, the frame is n + 32
   bytes; its first 4 bytes, big-endian, equal n + 28; bytes 5–16 are the
   nonce; opening with the right key returns exactly the plaintext.
   *Broken:* little-endian length; a length that counts itself; the check
   value placed before the sealed body.
3. **Every bit counts (R2).**  Flip each bit of a small frame in turn —
   length, nonce, sealed body, check value — and every one fails to open
   and yields no plaintext.  *Broken:* a version using AES in counter mode
   without the check (every body flip opens as altered text); a version
   that returns the plaintext it produced before checking.
4. **Nonces do not repeat (R1).**  Seal the same plaintext 100,000 times,
   and in two processes started in the same second: no nonce appears twice
   and no two sealed bodies are equal.  *Broken:* a counter that starts at
   zero per process; a nonce seeded from the clock.
5. **Size before reading (R3).**  Feed a socket stand-in that announces a
   length of 27, then one above the cap, then the cap exactly: the first
   two are refused **having read only 4 bytes**; the third is read.  Run
   the same frames through every implementation that reads frames (server,
   client, and any phone code) and they agree.  *Broken:* read the body,
   then check the length; a client whose cap is smaller than the server's.
6. **Nothing in the clear (R11, R4).**  Seal frames for rooms whose token,
   label, local tag, fingerprint and member addresses are all known
   strings; none of those strings, nor their hex, appears in the wire bytes.
   A connection that sends `GET / HTTP/1.0` gets no plaintext answer.
   *Broken:* a room fingerprint sent as a hint in front of the frame; a
   health check that names the home.
7. **Trial opening finds the right room (C7, R6).**  A mailbox with 1,000
   rooms; a frame sealed for room k, for every k from first to last, opens
   as room k with 1, 2 and 8 threads; a frame of random bytes opens as no
   room; two rooms with the same label and different tokens are told
   apart.  *Broken:* a thread split that skips the last key when the count
   does not divide evenly; a combiner that returns a thread's failure while
   another thread succeeded.
8. **The port limits the keys (planning, "Mailboxes").**  A genuine frame
   for a room in mailbox 1 arriving on mailbox 2's port is a failed
   decryption on mailbox 2.  Two mailboxes deliberately given one port
   open each other's frames and produce the "shared port" warning.
   *Broken:* one keyring for the whole home.
9. **Two openings are not first-wins (R7).**  Give the trial opener two
   entries with the same key (bypassing the entry reader, which forbids
   it), or a frame constructed to open under two keys: the result is an
   error naming both rooms, the same on every run and every thread count.
   *Broken:* first success wins.
10. **The failed-frame line (C10, issue 203).**  A garbage frame from a
    known address writes exactly one line with the time and that address;
    a genuine frame writes none; the documented fail2ban pattern matches
    the line and extracts the address.  *Broken:* rmail's line without the
    address; one line per key tried.
11. **Replay and reflection are harmless (R9).**  Deliver a message frame
    twice: filed once, second recorded as duplicate.  Deliver an edit,
    then a newer edit, then replay the first: the room shows the newer
    edit's effect.  Replay an old acknowledgement onto a connection
    carrying a new message: the new message is still "not yet delivered".
    Send a server's own hello back to it: no address of its own is added
    as a member.  *Broken:* an edit that overwrites in place; an
    acknowledgement that names no id.
12. **Short writes (R10).**  A socket stand-in that accepts 1 to 7 bytes
    per write, and sometimes zero with a timeout, several times in a row:
    the receiver gets exactly the frame and it opens.  *Broken:* rmail's
    loop, which adds the returned last-byte index as if it were a count.
13. **Inner records round-trip (C6).**  Every kind encodes and decodes to
    the same fields; an unknown kind, a missing field, and an extra field
    are each an error (the house rule: errors over fallbacks).  *Broken:*
    a decoder that fills missing fields with defaults.
14. **(If padding is adopted, C5.)**  For plaintexts of every length from
    1 to the cap, the wire length is one of the documented bucket sizes and
    the opened plaintext equals the original.  *Broken:* padding appended
    after the check value, where it is visible and strippable.

---

## 6. A DIFFERENT FORMATION

rao-chat meets the same rules; these are shapes that differ from rmail's.

**A. A keyring per mailbox, built once, tried whole.**  When the rooms
change (the change bell), each mailbox's keys are computed once into a
fixed array of 32-byte keys with the room's local tag beside each.  An
incoming frame is handed to all threads, each taking a slice of the array;
every key is tried, and exactly one opening is required — zero is a failed
decryption, two or more is an error (R7).
*Gains:* deterministic whatever the thread count; R7 met without changing
the frame; the frame stays byte-for-byte rmail's, as issue 201 says.
*Costs:* every frame, genuine or not, is tried against every key in its
mailbox — no early stop — so a genuine frame costs as much as a garbage
one.

**B. Committed frames: the sealed body begins with the key's own check.**
The first bytes of the plaintext are a value derived from the room key
(for example the room's fingerprint, already computed for child-room
invitations, or a run of zero bytes).  After a key opens a frame, the
opener confirms those bytes match that key; a frame crafted to open under
two keys would have to carry each key's value in the same place.  Trial
opening can then stop at the first genuine opening.
*Gains:* early stop (half the work on average for genuine frames) and R7
met by the frame itself, not by exhaustive search.
*Costs:* the plaintext inside differs from rmail's, and 32 bytes per frame
if the fingerprint is used.  **How long such a prefix must be to actually
prevent a two-key frame is something I could not verify from here**; the
literature to read before adopting it is Albertini, Duong, Gueron, Kölbl,
Luykx and Schmieg, "How to Abuse and Fix Authenticated Encryption Without
Key Commitment" (2020), and Len, Grubbs and Ristenpart (2021).

**C. The inner record in the log's own shape.**  Instead of HTTP text with
a JSON body, the sealed plaintext is one tab-separated header line — kind,
then that kind's fields in a fixed order from the encode/decode table —
then the text.  A `message` record inside a frame is then the same record
the room's log stores, minus the arrival fields the reader adds.
*Gains:* one parser for disk and wire; a received message can be checked
against the log byte for byte (useful to the cross-check, issue 209).
*Costs:* no ready tooling for reading captured plaintext; every field must
be escaped for tabs and newlines by one documented rule.

**D. The port as associated data.**  The mailbox port the frame was sent
to is fed to GCM as associated data: covered by the check value, never
sent.  A frame moved by an observer to another of your mailbox ports then
fails even if the same key were held there (two mailboxes sharing rooms is
already impossible, so today this guards only against a future change).
*Gains:* binds a frame to where it was sent, at no wire cost.
*Costs:* a sender must know the exact port it is writing to (it always
does); a relay or port-forward that changes the port breaks every frame —
and home routers do forward one outside port to a different inside port,
so this would need the *outside* port, which the receiver may not know.
I lean against it for that reason.

**E. Fixed-size frames.**  Every frame is padded inside the seal to one
of a few fixed sizes (for chat, perhaps 256 bytes, 1 KiB, 4 KiB, 16 KiB),
with the real length as the first sealed field.
*Gains:* R11's size leak shrinks to "which bucket"; short chat messages
all look alike.  *Costs:* bandwidth; a table of sizes to agree on.

**Leaning:** A for trial opening (it keeps rmail's frame exactly, which
issue 201 promises, and makes R7 a matter of counting), with C for the
inner record and E for size.  B is the formation to measure if A's
no-early-stop cost ever matters — it is also the one that changes the
frame's inside, so it is better decided before the first frame is sealed
than after.

---

## 7. OPEN QUESTIONS FOR THE OWNER

Most blocking first.

1. **A frame that opens under two rooms' keys** (R7).  Try every key and
   treat two openings as an error (formation A), or put a key-committing
   value inside every frame so the first opening can be trusted
   (formation B)?  This decides the trial opener's shape and whether the
   inside of the frame matches rmail's.
2. **The shape of the record inside a frame** (C6).  rmail's HTTP text
   with JSON, or the log's tab-separated shape (formation C), or something
   else?  Issue 201 step 4 needs it.
3. **The size cap** (C4, R3, R12).  rmail allows 64 MiB for attachment
   chunks; rao-chat carries text.  A cap near the largest message plus a
   member list (say 1 MiB) cuts the worst-case cost of a garbage frame by
   64 times.  What is the largest thing a rao-chat frame must hold — a
   `members` list of a large room, a cross-check summary?
4. **Acknowledgements name what they acknowledge** (R9).  Confirm that an
   acknowledgement carries the message id(s), and that a bare "OK" is
   refused.  (Also relevant to issue 202.)
5. **Padding** (C5, formation E).  Pad inside the seal, and to which sizes?
   rmail has had this open since April.
6. **No plaintext health check** (C11, R4).  Confirm that a mailbox port
   answers nothing in the clear.  If a person needs to test a port forward,
   what do they use instead — a sealed "ping" kind sent by their own
   client?
7. **How a token becomes bytes** (R5).  Keep the token's bytes exactly as
   typed, or normalise (Unicode NFC, trimmed ends) before hashing?  Either
   is fine if it is one rule everywhere; normalising prevents "same words,
   different key" between a phone and a computer.  Note: rao-chat's
   fingerprints already exist in phase 1 and would change for any token
   the normalisation alters.
8. **How long to wait for the pieces of a frame** (C12).  rmail waits 10
   seconds per read; a sender that trickles one byte at a time holds a
   connection that long per byte-read.  Keep 10 seconds, or a total
   deadline per frame?
9. **The nonce budget for large rooms** (R1).  Is it worth counting frames
   sealed per room key (sent by this server only — it cannot see others'),
   and suggesting a token change past some number, or is that too far off
   to matter?  It becomes relevant only with the periodic cross-check at
   hundreds of members.
10. From issue 203, still open there and touching this area: frames that
    open but are refused — log them with the failed ones, apart, or not at
    all; and RAM or disk for the log.
