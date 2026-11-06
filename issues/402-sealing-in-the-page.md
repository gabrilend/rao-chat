# 402 — Sealing in the page

**Phase:** 4 — The web client
**Blocked by:** 401
**Blocks:** 403 to 409

## Current Behavior

The home seals and opens device frames with libcrypto (123, 124) and
reads their records with 186.  The page has none of it.

## Intended Behavior

Planning section 6: the WebSocket carries "the same encrypted frames as
the phone.  The browser's built-in cryptography (WebCrypto) does
AES-GCM, so the token never leaves the browser."

- **The key and the tying value by 123's rule**: the key is SHA-256 of
  the token's bytes exactly as typed (UTF-8, nothing trimmed or
  normalised), the tying value SHA-256 of the key; a token holding a
  line break, or an empty one, is refused, never cut.
- **Frames by 124's layout**: 4-byte length, a 12-byte nonce from
  `crypto.getRandomValues` for every frame, the sealed body (tying value,
  the record, then padding: "\n" and zero bytes up to the next power of
  two, at least 256), and GCM's 16-byte check value.  The page pads as
  the home does, so a browser's frames are the same sizes as a phone's.
- **Opening gives the record or nothing**: GCM's check (WebCrypto
  refuses a wrong check value), then the tying value, then padding that
  is exactly "\n" and zeros.  Nothing of a body that fails any of them
  reaches a record.
- **Records by 186's table**: the kinds and their fields in order,
  tab-separated, escaped by the log's rule; the field rules (`id`, `at`,
  `room`); anything unknown refused.  The page's table is a copy of
  186's, and a referee holds the two equal.
- **Bytes stay bytes**: what crosses the network is held as one
  character per byte (a "byte string", as Lua holds it), so a file's
  digest (304) is taken over exactly the bytes the home sent; text is
  decoded as UTF-8 only to be shown.

## Rubric

From `notes/rmail-rubric/sealing-and-framing.md`.

- **A random nonce for every frame** (R1), never a counter.
- **Opening is all or nothing** (R2).
- **One rule for the key everywhere** (R5): a stray line ending, or one
  spelling on the phone and another in the browser, gives an unrelated
  key and every frame silently fails.

## Referees

1. **The page and the home agree.**  A frame the page seals opens with
   124 under the same token, holding the same record, at 124's padded
   size; a frame 124 seals opens in the page.  Records of every kind
   encoded by one side decode by the other to the same fields.
2. **Opening is all or nothing.**  A flipped byte in the body or the
   check value, another token, a body under the right key whose tying
   value is another token's, padding that is not zeros: nothing.
   *Broken:* not checking the tying value (`no-tie-check`).
3. **The tables agree.**  The page's kinds, fields in order and field
   rules are 186's.  *Broken:* a field missing from one kind
   (`short-kind`).
4. **Tokens by 123's rule.**  The page's key for a token with a
   non-ASCII letter is 123's; a token with a line break is refused.

## Suggested Implementation Steps

1. `rao.seal` (key pair, seal, open, padding) and `rao.records`.
2. The stand-in's `seal`, `open` and `records` commands.
3. The referees, the Lua side sealing and opening with 124 and 186.

## Blockers that are not the owner's

- Needs 401.

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **The page pads as the home does**, though 124's reader accepts an
   unpadded body: a browser's frames should not stand out by size from a
   phone's.
2. **The record table is copied, not fetched**: the page cannot read 186,
   so its table is written out again, and referee 3 keeps the copy true.
3. **Byte strings, not typed arrays, between the parts**: the escaping,
   the digests and the signature rule (214 counts characters from bytes)
   then read exactly as the Lua beside them, and an array is made only
   at WebCrypto's door.

## Related documents

- issues 201, 201a (sealing, the tying value), 302 (decision 3)
- `notes/rmail-rubric/sealing-and-framing.md`
