# 201a — The key-tying value at the start of every sealed body

**Phase:** 2 — Server-to-server delivery
**Parent issue:** 201
**Blocked by:** 201
**Blocks:** 202, 210

## Current Behavior

Nothing exists.  201 describes the frame and leaves the first 32 bytes of
the sealed body for this value.

## Intended Behavior

AES-GCM is not "key-committing": its check value is computed from the
sealed bytes by linear arithmetic, so someone who knows two keys can solve
for one frame that opens validly under both (Dodis, Grubbs, Ristenpart and
Woodage 2018; Len, Grubbs and Ristenpart 2020–21).  In rao-chat only a
member of two rooms in one mailbox could build such a frame; the harm is
one frame filed in room A by one reader and in room B by another,
depending on which key each server tried first.

The owner's answer (2026-09-27): "add the token to the front of each
message, before the regular text but after the... nonce? ... Inside the
encrypted payload, and strip it out before displaying it to the user and
after validating it."

- **Every sealed body begins with the room's key-tying value**: the token
  fingerprint as 32 raw bytes (`SHA-256(SHA-256(token))` — the same value
  101 already stores as 64 hex characters in child rooms' `parent`
  fields), not the raw token.  A short token such as `coffee` (6 bytes)
  could be matched by brute force in about 2^48 tries; 32 bytes of hash
  cannot, and every body starts with a value of one fixed length.
- **Opening** a frame with a key succeeds only if GCM's check passes **and**
  the first 32 opened bytes equal that key's tying value.  Either failing
  is "this key does not open it".  The value is stripped before the inner
  record (201) is read.
- **Trial opening stops at the first key that passes both checks**: the
  tying value turns a first-wins search into a correct one.
- Sealing prepends the value; nothing outside the seal changes.

## Rubric

- **A frame opening under two keys must not be decided by trial order**
  (sealing note, R7).  The literature above is the rule's source; rmail
  has not met it (first key wins, Lua table order).
- **The check value is verified before any plaintext is used** (R2): the
  tying comparison runs only on a body GCM has already accepted, and a
  mismatch yields nothing, exactly as a failed check does.
- **Secrets stay in one place** (sealing note section 4, 2026-04-13): a
  hash of the token is the key itself, so the key cannot be the tying
  value; the fingerprint hashes once more, which is why phase 1 made it
  that way.
- **A property of the wire format is checked by a test of the wire bytes,
  not by a document** (2026-04-19 edge case): rmail's documents described
  padding the code never did.

## Where we differ

rmail has no key-tying value.  The formation here is **the tying value as
the trial-opening sieve**: the note's formation A (try every key, count
openings, two is an error) would meet R7 with no change to the frame, at
the price of trying every key on every frame, genuine or not.  The tying
value moves R7 into the frame itself and lets a genuine frame stop at its
own key — on average half the keys of its mailbox.

- **Gains:** early stop; correctness by construction rather than by
  exhaustive search; the fingerprint is a value phase 1 already computes.
- **Costs:** 32 bytes per frame; the inner body differs from rmail's (no
  rmail patch is needed, since rao-chat seals its own frames; rmail could
  adopt the same fix separately).

## Referees

1. **Two keys, one frame.**  Build (by the published method, in the test)
   a frame whose GCM check passes under two room keys held in one mailbox:
   the opener files it under neither and reports it — or, if the builder
   cannot construct one, a stand-in opener that bypasses GCM with two keys
   returning the same body shows the tying check refusing the wrong one.
   *Broken:* a version that checks GCM only (first key wins).
2. **The value is stripped.**  A message opened and filed holds exactly
   the text sealed; no filed record, log line or viewer file starts with
   the 32 bytes.  *Broken:* a version that forgets to strip.
3. **Early stop is correct.**  A mailbox of 1,000 rooms: for every k, a
   frame for room k opens as room k and the count of keys tried is at most
   k's position in the keyring; random bytes try all 1,000.  *Broken:* an
   early stop on GCM success alone.
4. **The raw token is never in the body.**  For a room whose token is a
   known string, the opened body contains neither the token nor the key.
   *Broken:* the owner's first phrasing taken literally (the raw token).

## Suggested Implementation Steps

1. The tying value from a token (the fingerprint's 32 raw bytes).
2. Prepending on seal; checking and stripping on open, inside 201's
   opening function, so no caller can skip it.
3. The early stop in 201's trial opening.
4. The referees above, each against its broken version.

## Blockers that are not the owner's

- Needs 201's sealing and opening.
- **A check against the literature before building:** how long a prefix
  must be to prevent a two-key frame for GCM is argued in Albertini,
  Duong, Gueron, Kölbl, Luykx and Schmieg, "How to Abuse and Fix
  Authenticated Encryption Without Key Commitment" (2020/2022).  Their fix
  prepends a fixed block and checks it; here the prefix differs per key,
  which makes a two-key frame need two 256-bit keystream blocks to match a
  chosen difference.  The builder reads the paper and writes the bound, and
  its source, into the code comment beside the check.

## Open questions

1. *(answered 2026-09-27)* **Key-tying value or try-every-key.**  Owner:
   the value, inside the sealed body, stripped after validating.
2. *(proposed, to confirm)* **The fingerprint rather than the raw token.**
   The owner said "the token"; the fingerprint is proposed for the brute-
   force reason above.  Confirm.

## Related documents

- `notes/vision-planning.md` section 15 ("Key-tying, the log and git, signatures")
- `notes/rmail-rubric/sealing-and-framing.md` (R7, formations A and B)
- `src/room-folders/007-tokens.lua` (the fingerprint)
