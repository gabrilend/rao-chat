# 007-tokens.lua

A room's token: its fingerprint and readable suggestions.  Stores nothing.
Uses the system's OpenSSL (`libcrypto`) through LuaJIT's ffi for SHA-256,
and `assets/eff-large-wordlist.txt` (origin and licence in
`assets/eff-large-wordlist.about.md`) for words.  Load with
`require("007-tokens")`; 002-room-folders re-exports the fingerprint and
suggestion functions.

| function / value | takes | gives | what it does |
|---|---|---|---|
| `token_fingerprint(token)` | string (non-empty, one line) | string, 64 lower-case hex | `SHA-256(SHA-256(token))`: the inner digest is the sealing key (raw 32 bytes, as rmail makes one); the outer is over those raw bytes.  Same on every home; not reversible. |
| `is_fingerprint(value)` | anything | bool | 64 lower-case hex characters. |
| `check_token(token)` | anything | nothing | Errors unless a non-empty one-line string. |
| `sha256(text)` | string (any bytes) | string, 32 raw bytes | Plain SHA-256; phase 2 can make the sealing key with it. |
| `suggest_token_of(n)` | integer ≥ 1 | string | n words drawn uniformly (with rejection sampling from `/dev/urandom`) from the list, joined by `-`.  Words may repeat. |
| `bits_per_word()` | — | number | log2(list size), about 12.92. |
| `word_count_in_list()` | — | integer | 7772. |
| `WORD_LIST_PATH`, `WORD_SEPARATOR` | — | string | Where the list is; `"-"`. |

The word list is read once and checked (letters a–z only, no repeats);
a damaged list is an error, never a quietly weaker suggestion.
