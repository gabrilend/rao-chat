# 201 — The room key and sealed frames

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 101
**Blocks:** 202, 203, 204, 205, 210

## Current Behavior

Nothing exists.  rmail seals every message between two servers with
AES-256-GCM under `SHA-256(token)`, in frames of `[4-byte length][12-byte
nonce][ciphertext][16-byte check value]` (`rmail_crypto.c`, and the framing
and trial-opening loop in `rmail.lua`).

## Intended Behavior

- **The room key is made from the room's token**, exactly as rmail makes a
  contact's key from its token.  Group rooms and direct messages are sealed
  the same way.  People only ever see and share the plain-text token.
- **Frames are rmail's frames**, unchanged: length, random nonce, sealed
  body, 16-byte check value over every byte.  Opening either succeeds or
  gives back nothing; the lock itself says whether a frame is genuine.
- **Finding which room a frame is for** means trying the key of every room
  this home holds (as rmail tries every contact's key).  A frame no key
  opens is a failed decryption (203).  Two rooms that share a label have
  different tokens, so the lock alone says which room a frame belongs to.
- **Inside the frame**: a kind (`message`, `hello`, `members`,
  `members-ask`, `leave`, `did-you`, `summary`), and the fields each kind
  needs.  Nothing about a room travels in the clear.
- **No per-connection key.**  A room is as private as its token is hard to
  guess; a deliberately guessable token makes a public square.

## Suggested Implementation Steps

1. Key from token, with test vectors matching rmail's.
2. Sealing and opening frames, reusing rmail's crypto library.
3. Trial opening across every held room.
4. The inner record of each kind, as a small encode/decode table.
5. Tests: a frame opens only with its room's key; one flipped bit refuses
   it; two rooms with one label are told apart; every inner kind
   round-trips.

## Blockers that are not the owner's

- Needs 101 (rooms and their tokens).

## Open questions

1. **Sharing code with rmail** (planning question 6): lift rmail's crypto
   and framing into a library both use; copy it and let them drift; or run
   inside rmail's daemon?
2. **One home server program or two** (planning question 7)?  A direct
   message is exactly an rmail contact, which makes "one program" easier
   than it was.
3. *(answered 2026-09-25)* **Trial opening at scale.**  No hint in front of
   frames (owner: "no way. If we need more speed, we make the decoding
   multithreaded").  Trial opening is split across threads (each key's
   attempt is independent).  Cost grows with the rooms a server holds, not
   their members; a separate listening port per group of rooms (a
   "mailbox") limits which keys are tried.  Whether to build per-port
   mailboxes is left for when it is measured to matter.

## Earlier design (second model, written, not built)

The key was made from the room's name, so two same-named islands shared a
key and a stranger's messages waited to be vouched for; a common name
could be guessed by anyone recording the traffic.

## Related documents

- `notes/vision-planning.md` sections 5, 15
- `/home/ritz/programs/r-mail/rmail_crypto.c`
