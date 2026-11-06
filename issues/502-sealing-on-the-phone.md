# 502 — Sealing on the phone

**Phase:** 5 — The Android app
**Blocked by:** 501
**Blocks:** 503 to 509

**Needs the Android toolchain on the owner's machine.**  This machine
has a JDK and Gradle but no Android SDK, no Kotlin compiler of its own
and no emulator or phone, and nothing may be installed here; so this
issue is a plan, written 2026-11-06, and none of it is built.  No Kotlin
is written until it can be compiled (501 decision 3).

## Current Behavior

The home seals and opens device frames with 123 and 124 and reads their
records with 186; the web page does the same in WebCrypto (402).  The
app has none of it.

## Intended Behavior

The same frames as the home and the page, in `crypto/` with
`javax.crypto` (AES-256-GCM) and `java.security.MessageDigest`
(SHA-256), both in Android since API 19:

- **The key and the tying value by 123's rule**: the key is SHA-256 of
  the token's bytes exactly as typed (UTF-8, nothing trimmed); the tying
  value SHA-256 of the key; a token holding a line break, or an empty
  one, refused.
- **Frames by 124's layout**: 4-byte length, a fresh 12-byte nonce from
  `SecureRandom` for every frame, the sealed body (tying value, record,
  padding of "\n" and zero bytes to the next power of two, at least
  256), GCM's 16-byte check value.
- **Opening gives the record or nothing**: the GCM check, the tying
  value, then padding that is exactly "\n" and zeros.
- **Records by 186's table**, kinds and fields in order, tab-separated,
  escaped by the log's rule; anything unknown refused.
- **Bytes stay bytes** (`ByteArray`), decoded as UTF-8 only to be shown.

## Status

Plan only (2026-11-06); not built.

## Rubric

From `notes/rmail-rubric/sealing-and-framing.md`: R1 (a random nonce for
every frame), R2 (opening is all or nothing), R5 (one rule for the key
everywhere).

## Referees

As 402's, the other side being the home's own Lua:

1. **The phone and the home agree**: a vectors file made by the home's
   code (a small Lua script, `src/devices/` or `clients/android/
   test-vectors/`, run on the owner's machine before the JVM tests:
   tokens, records of every kind, frames sealed by 124) opens in a JVM
   unit test to the same records; frames the JVM test seals open with
   124 (the test writes them, the Lua script checks them).
2. **All or nothing**: a flipped byte, another token, a body whose tying
   value is another token's, padding that is not zeros: nothing.
3. **The tables agree**: the app's kinds and fields are 186's (the
   vectors file carries 186's table).
4. **Tokens by 123's rule**: a non-ASCII token gives 123's key; a line
   break is refused.

## Suggested Implementation Steps

1. The vectors script (Lua, runs here already) and its file.
2. `crypto/` and `data/Records`; the JVM unit tests.

## Blockers that are not the owner's

- None.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **Vectors from the home's own code**, not hand-written: the referee is
   that the phone agrees with what the home actually does, as 402's page
   referee is.
2. **JVM unit tests, not instrumented ones**, for sealing: they need no
   phone, so they run on every build.

## Related documents

- issues 123, 124, 186 (the home's side), 402 (the page's)
- `notes/rmail-rubric/sealing-and-framing.md`
