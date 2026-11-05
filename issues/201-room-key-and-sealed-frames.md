# 201 — The room key and sealed frames

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 101
**Blocks:** 201a, 202, 203, 204, 205, 210, 211, 213

## Current Behavior

**Built 2026-11-05** in `src/sealing/` (123–127, referees in
`tests/128-test-sealing.lua`, 37 checks; each referee also run against its
broken version, which it catches): the key and tying value from a token,
sealing and opening, frames read and written on a connection, the inner
record table (the log's three kinds), the keyring per mailbox dropped on
the change bell, and trial opening split into slices and combined.  Open
questions 1–5 are answered below as the builder's decisions, under the
owner's standing instruction to answer them; each may be overturned.
What waits: the workers themselves and the mailbox port (211), the other
kinds' rows (their own issues), and 201a's own referee.

*Before this:* nothing existed in phase 2.  Phase 1 already makes the two values this
issue starts from, in `src/room-folders/007-tokens.lua`: the room key's
input (the token, a text string held in each room's `entry`) and the
token fingerprint (`SHA-256(SHA-256(token))`, 64 lower-case hex
characters, 101's `token_fingerprint`).  Nothing seals or opens a frame
yet.

rmail, read as a rubric (`notes/rmail-rubric/sealing-and-framing.md`),
seals every message between two servers with AES-256-GCM under
`SHA-256(token)`, in frames of `[4-byte length][12-byte nonce][sealed
body][16-byte check value]`, and finds which contact a frame is from by
trying every contact's key until one opens it.

## Intended Behavior

- **The room key is made from the room's token**: 32 bytes,
  `SHA-256(token)`, the token turned into bytes by one documented rule
  (open question 3).  Group rooms and direct messages are sealed the same
  way.  People only ever see and share the plain-text token.
- **The frame, outside to inside:** length (4 bytes, big-endian unsigned,
  in the clear, counting everything after itself) · nonce (12 bytes, in
  the clear, fresh random bytes from the operating system for every frame)
  · sealed body · check value (16 bytes, in the clear, computed over every
  byte of the sealed body).  Opening either succeeds or gives back nothing.
- **The sealed body begins with the key-tying value** (a 32-byte value
  that ties the body to one room's key), checked after opening and
  stripped before anything else reads the body.  That value is its own
  sub-issue, 201a; this issue leaves room for it and calls 201a's check.
- **After the key-tying value comes one inner record**: a kind (`message`,
  `correction`, `deletion`, `hello`, `members`, `members-ask`, `leave`,
  `did-you`, `did-you-answer`, `summary`, `ack`, `discover`, `here`), then
  that kind's fields in a fixed order, as a small encode/decode table.  An
  unknown kind, a missing field or an extra field is an error.
- **Finding which room a frame is for** means trying the keys of the rooms
  in the mailbox whose port the frame arrived on (phase 1's mailboxes: a
  port's keys only), split across workers (the owner: "if we need more
  speed, we make the decoding multithreaded").  With 201a, trying stops
  at the first key whose opened body begins with that key's tying value.
  A frame no key opens is a failed decryption (203).
- **Nothing about a room travels in the clear**: no hint, no fingerprint,
  no name in front of a frame; a mailbox port answers nothing in the clear
  (open question 6 of the sealing note, held here as question 5).
- **No per-connection key.**  A room is as private as its token is hard to
  guess; a deliberately guessable token makes a public square.

## Rubric

The rules this issue must meet, from `notes/rmail-rubric/sealing-and-framing.md`
(section 2) unless another note is named.  Each is a rule because the
cipher, the network or a bug already hit requires it, not because rmail
chose it.

- **A nonce never repeats under one key** (R1).  GCM makes its keystream
  from key and nonce; two frames sharing both leak the XOR of their
  plaintexts and let an attacker forge check values.  In rao-chat every
  member seals with the same room key independently, so a counter cannot
  be coordinated: only random nonces are safe.
- **The check value is verified before any plaintext byte is used, and a
  failed frame yields nothing** (R2).  GCM produces plaintext before it
  knows whether the frame is genuine.
- **The length is checked before the body is read, against one cap shared
  by every reader; the smallest valid length is 28** (R3).  The length
  arrives before any proof; reading whatever it claims lets anyone make
  the server hold gigabytes.  rmail's daemon and phone disagree on the cap
  (64 MiB against 16 MiB) — two implementations of one frame drift unless
  one referee checks both.
- **One way to turn a token into bytes, everywhere** (R5).  A stray
  newline or a different Unicode spelling of the same visible letter
  gives an unrelated key and every frame silently fails.
- **One key leads to exactly one room on a home** (R6) — already met by
  101, which refuses a second room holding a held token.
- **A frame that opens under two held keys is never silently given to the
  first key tried** (R7) — met by 201a.
- **Every record a frame carries is safe to receive twice, late, or sent
  back to its writer** (R9).  Frames carry no freshness; the room key is
  the same forever.  An acknowledgement must name the ids it acknowledges.
- **A write sends every byte exactly once** (R10).  rmail's loop adds the
  "index of the last byte sent" as if it were a count; two partial writes
  in a row skip bytes.
- **Nothing that identifies a room, its members or the person travels
  outside the seal** (R11); what stays visible is the addresses, timing,
  the length and the port.
- **A failed opening costs work proportional to the keys tried times the
  frame's size** (R12), which is why the cap and the per-port keyring
  matter together.
- **A token never travels, even sealed**, and the key that opens a frame
  is the only statement of which room it is for (edge cases 2026-03-24 and
  2026-09-22 in the note's section 4).

## Where we differ

The formation this issue tries is the note's **formation C: the inner
record in the log's own shape.**  rmail puts an HTTP-shaped request with a
JSON body inside each frame.  rao-chat's inner record is one tab-separated
line — kind, then that kind's fields in a fixed order — escaped by exactly
the rule phase 1's log already uses (`\\`, `\t`, `\n`, `\r`;
`src/message-log/083-record-codecs.lua`).  A `message` record on the wire
is the log's record minus the fields the reader adds on arrival (`from`,
`arrived`).

- **Gains:** one parser for disk and wire; a received message can be
  compared with the log byte for byte, which the cross-check (209) and the
  shared text copies (215) both lean on; no text-protocol parser to
  harden.
- **Costs:** no ready tooling for reading a captured plaintext; every new
  kind needs a row in the table rather than a new path; the question of
  the inner shape is the owner's (open question 1) and this is the
  builder's proposal until answered.

The keyring is built once per mailbox from its rooms' tokens and rebuilt
on the change bell's `token`, `created` and `mailbox` rings — rmail
re-reads its contacts file and re-hashes every token for every frame.

## Referees

Written from the rules above, not from rmail's code or this issue's code.
Each names a deliberately broken version it must catch; a referee that
passes its broken version grades nothing.

1. **Key from token (R5).**  The key for token `abc` is the 32 bytes whose
   hex is the standard SHA-256 test vector
   `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad`; the
   token rule chosen in open question 3 is applied the same way by every
   reader (typed, read from an entry, pasted).  *Broken:* the key as 64
   hex characters; a token read with its line ending.
2. **Frame layout.**  For an inner record of n bytes, the frame is
   n + 32 (tying value) + 32 bytes; the first 4 bytes, big-endian, equal
   everything after them; bytes 5–16 are the nonce.  *Broken:*
   little-endian length; a length that counts itself; the check value
   placed before the sealed body.
3. **Every bit counts (R2).**  Flip each bit of a small frame in turn:
   every one fails and yields no plaintext.  *Broken:* counter mode
   without the check; returning plaintext produced before the check.
4. **Nonces do not repeat (R1).**  Seal one plaintext 100,000 times, and
   in two processes started in the same second: no nonce repeats.
   *Broken:* a counter starting at zero per process; a nonce seeded from
   the clock; workers forked after seeding one generator.
5. **Size before reading (R3).**  A socket stand-in announcing 27, then
   one above the cap, then the cap exactly: the first two are refused
   having read only 4 bytes; the same frames through every reader in the
   project agree.  *Broken:* read, then check; a client with a smaller cap.
6. **Nothing in the clear (R11).**  Frames for rooms whose token, label,
   local tag, fingerprint and member addresses are known strings: none of
   them, nor their hex, appears in the wire bytes; `GET / HTTP/1.0` on a
   mailbox port gets zero bytes back.  *Broken:* a fingerprint hint in
   front of the frame; a plaintext health check.
7. **Trial opening finds the right room.**  A mailbox of 1,000 rooms; a
   frame for room k opens as room k for every k, with 1, 2 and 8 workers;
   random bytes open as no room; two rooms with one label are told apart.
   *Broken:* a split that skips the last key when the count does not
   divide evenly; a combiner that reports one worker's failure while
   another succeeded.
8. **The port limits the keys.**  A genuine frame for mailbox 1 arriving
   on mailbox 2's port is a failed decryption there, and the count of keys
   tried equals mailbox 2's rooms.  *Broken:* one keyring for the home.
9. **Inner records round-trip.**  Every kind encodes and decodes to the
   same fields; unknown kind, missing field and extra field are each an
   error.  *Broken:* a decoder that fills missing fields with defaults.
10. **Short writes (R10).**  A socket stand-in accepting 1–7 bytes per
    write, sometimes zero with a timeout, several times in a row: the
    frame arrives whole and opens.  *Broken:* adding the returned
    last-byte index as a count.

## Suggested Implementation Steps

1. Key from token (after open question 3), with the test vectors above.
2. Sealing and opening, through the crypto library in `libs/` (the same
   primitives rmail uses, read from its rules, not its source).
3. Reading and writing frames on a socket: length check first, exact
   reads, a counted write loop.
4. The keyring per mailbox, rebuilt on the change bell.
5. Trial opening across a mailbox's keyring, split across workers, calling
   201a's check on each opening.
6. The inner record table (kinds and their fields), in the log's escaping.
7. The referees above, each run against its broken version once to show
   it fails.

## Blockers that are not the owner's

- Needs 101 (rooms and their tokens).  The trial-opening workers run
  inside the mailbox gatherer's opener stage (211).

## Decisions (2026-11-05)

Made by the builder: the owner's standing instruction is to answer open
questions rather than wait, choosing the option easiest to undo.  Each is
written so the owner can overturn it; what overturning costs is said.

1. **The record inside a frame is the log's tab-separated shape**
   (question 1, formation C): kind, then the kind's fields in a fixed
   order, escaped by exactly the log's rule.  Undo: every frame passes
   through `126-inner-records.lua`'s encode and decode, so another shape
   replaces those two functions and nothing else.
2. **The cap is 1 MiB** (question 2): the length field may be 28 to
   1,048,576.  rao-chat carries text; a `members` list or `summary` of a
   very large room is the biggest thing a frame holds, far under this.
   Every reader takes the cap from `124-seal.lua`, and no reader may be
   given a larger one.  Undo: one constant; raising it needs every reader
   updated before any writer uses it.
3. **Padding: inside the seal, to the next power of two, at least 256
   bytes** (question 2): the sealed body (tying value, record, padding) is
   256, 512, 1024 ... bytes; one that would pass 512 KiB is padded to the
   largest body the cap allows.  Padding is `"\n"` and zero bytes: the
   log's escaping keeps raw line breaks out of a record, so the first
   `"\n"` ends it with no length field.  Readers accept padded and
   unpadded bodies alike, so turning padding off or changing the sizes is
   a change to the writer only.  Padding that is not exactly `"\n"` and
   zeros is refused.
4. **A token becomes bytes exactly as the entry holds it** (question 3):
   no Unicode normalising, no trimming; a line break is an error, never
   quietly cut off.  This is phase 1's rule for the fingerprint, so no
   fingerprint changes.  Undo: normalising later changes the key and
   fingerprint of exactly the tokens it alters, the same cost as choosing
   it now, so waiting costs nothing.
5. **The nonce budget is not counted** (question 4): nonces are 12 random
   bytes from the kernel (`getrandom`) per frame; the usual bound is about
   2^32 frames per key before a repeat becomes a real risk, and a room
   seals nowhere near that.  Revisit with 209's cross-check at hundreds of
   members.  Undo: adding a counter later changes nothing on the wire.
6. **A mailbox port answers nothing in the clear, a health check
   included** (question 5).  A person tests a port forward with a sealed
   ping from their own viewer; building that is 212's.
7. **The tying value is filled in now** (201a's intended behaviour):
   sealing puts the room's fingerprint bytes first and opening checks it,
   because 201's frame layout counts those 32 bytes and trial opening
   needs them to stop at the first key.  201a keeps its own referee (a
   frame made to pass GCM under two keys).
8. **The table holds the log's three kinds** (`message`, `correction`,
   `deletion`: `id`, `written`, `target`, `text`).  The other kinds' fields
   are defined by their own issues (202 `ack`, 204 `did-you`, 205 `hello`,
   207 `members`/`members-ask`, 208 `leave`, 209 `summary`, 213
   `discover`/`here`), each of which adds its row; until then each is an
   unknown kind, which is an error.
9. **Workers: split and combine here, run in 211.**  `127-keyring.lua`
   splits a keyring into one slice per worker (every key once, sizes
   differing by at most one) and combines the answers (an opening in any
   slice wins; two is an error); the slices run one after another until
   the gatherer runs each in its own worker.
10. **Nonces come from `getrandom(2)` on every frame**, not a buffered read
    of `/dev/urandom`: a forked worker copies a read buffer and would
    repeat its parent's nonces (referee 4 shows this).  Linux only for
    now; macOS would use `getentropy`.
11. **A slow connection**: reading and writing give up after 3 timeouts in
    a row that moved no bytes; how long each timeout is belongs to the
    connection and the gatherer's deadline (211), which is where the
    sealing note's question 8 (10 s per read or a deadline per frame) is
    answered.

## Open questions

1. *(answered 2026-11-05 by the builder, decision 1; the owner may
   overturn)* **The shape of the record inside a frame** (sealing note C6): the
   log's tab-separated shape (proposed, formation C above) or rmail's HTTP
   text with a JSON body?
2. *(answered 2026-11-05 by the builder, decisions 2 and 3)* **The size
   cap, and padding** (C4, C5): rao-chat carries text, so a cap
   near the largest `members` list or `summary` (say 1 MiB) cuts the cost
   of a garbage frame 64 times against rmail's 64 MiB.  Pad inside the seal
   to a few fixed sizes (which?) so short chat lines all look alike?
3. *(answered 2026-11-05 by the builder, decision 4)* **How a token
   becomes bytes** (R5): exactly as typed, or normalised
   (Unicode NFC, ends trimmed)?  Normalising changes the fingerprint of any
   phase 1 token it alters.
4. *(answered 2026-11-05 by the builder, decision 5)* **The nonce
   budget** (R1): count frames sealed per room key on this
   server and suggest a token change past a number (about 2^32 frames for
   a whole room), or too far off to matter?
5. *(answered 2026-11-05 by the builder, decision 6)* **No plaintext
   answer on a mailbox port** (C11): confirm it covers a
   health check too.  How does a person then test a port forward — a
   sealed "ping" from their own viewer (see 212)?
6. *(answered 2026-09-26)* **Sharing code with rmail.**  Owner: rmail is a
   rubric — "don't build it exactly the same, do it different each time."
   Read, not called or copied.
7. *(answered 2026-09-27, to be confirmed as "two programs")* **One home
   server program or two.**  rao-chat's server is its own program: one
   data gatherer per mailbox (211).
8. *(answered 2026-09-27)* **A frame that opens under two rooms' keys.**
   Owner: "add the token to the front of each message ... Inside the
   encrypted payload, and strip it out before displaying it."  Built as
   the fingerprint, in 201a.
9. *(answered 2026-09-25)* **Trial opening at scale.**  No hint in front
   of frames (owner: "no way. If we need more speed, we make the decoding
   multithreaded"); a port's keys only (mailboxes).

## Earlier design (second model, written, not built)

The key was made from the room's name, so two same-named islands shared a
key and a stranger's messages waited to be vouched for; a common name
could be guessed by anyone recording the traffic.

## Related documents

- `notes/vision-planning.md` sections 5, 15 ("Key-tying, the log and git")
- `notes/rmail-rubric/sealing-and-framing.md`
- `strategems/other-peoples-software-as-a-rubric.md`
- `docs/phase-1-module-contract.md` ("The entry", "Mailboxes", "The change bell")
