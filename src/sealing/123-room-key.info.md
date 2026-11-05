# 123-room-key.lua

A room's sealing key and key-tying value, made from its token (issue 201,
step 1).  Load with `require("123-room-key")`; uses 007-tokens' SHA-256.

The token becomes bytes by one rule (decision of 2026-11-05, open question
3 of issue 201): its bytes exactly as the entry holds them, no Unicode
normalising and no trimming; a line break is an error.  Phase 1's
fingerprints are unchanged by it.

| function / value | takes | gives | what it does |
|---|---|---|---|
| `room_key(token)` | string (non-empty, one line) | 32 raw bytes | `SHA-256(token)`.  Errors on an empty token or one holding a line break. |
| `tying_value(token)` | string | 32 raw bytes | `SHA-256(key)`: 007's `token_fingerprint` as bytes.  Begins every sealed body (201a). |
| `key_pair(token)` | string | `{key, tie}` | Both, worked out once, as 124 and 127 use them. |
| `KEY_BYTES`, `TIE_BYTES` | — | 32, 32 | |
