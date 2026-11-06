# 210-sealing.js

Sealing and opening a device frame in the browser's WebCrypto (issue
402): 123's key (SHA-256 of the token as typed) and tying value, 124's
frame (length, random nonce, AES-256-GCM body of tying value, record and
padding, check value), padded as the home pads.  Opening gives the record
or nothing: GCM's check, the tying value, zero padding.
