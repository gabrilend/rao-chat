# 124-seal.lua

Seals one inner record into a frame and opens it (issue 201; 201a's tying
value).  AES-256-GCM from the system's OpenSSL (`libcrypto`) through
LuaJIT's ffi; nonces from the kernel (`getrandom(2)`), 12 fresh bytes per
frame.  Load with `require("124-seal")`.

Frame: `length (4, big-endian, counts what follows) · nonce (12) · sealed
body · check value (16)`.  Sealed body: `tying value (32) · record (one
line) · padding`.  Padding is absent or `"\n"` then zero bytes; by default
the body is padded to the next power of two, at least 256 bytes, at most
`BODY_MAX`.  A reader accepts padded and unpadded bodies alike, and refuses
padding that is not exactly `"\n"` and zeros.  The cap is 1 MiB.  Both are
decisions of 2026-11-05 (issue 201, open question 2).

| function / value | takes | gives | what it does |
|---|---|---|---|
| `seal(pair, record, options)` | `{key, tie}`, one-line string, `{pad = false}` or nil | the whole frame | Errors on a record holding `"\n"` or too big for the cap. |
| `open(pair, after_length)` | `{key, tie}`, the frame without its length | the record, or nil and a reason | Plaintext is read only after GCM's check passes; then the tying value and padding are checked. |
| `nonce()` | — | 12 bytes | From `getrandom`; errors on a short read. |
| `padded_size(n)` | bytes of tie + record | the body's padded size | Errors over `BODY_MAX`. |
| `gcm_encrypt(key, iv, plain)` / `gcm_decrypt(key, iv, ct, tag)` | | ciphertext, tag / plain or nil | The bare cipher, for tests. |
| `uint32_be(n)` / `read_uint32_be(bytes)` | | | The length field. |
| `CAP`, `MIN_LENGTH`, `BODY_MAX`, `PAD_FLOOR` | — | 1048576, 28, 1048548, 256 | Every reader in the project uses `CAP` from here. |
