# 169-signature.lua

A message's signature, read from its text by the owner's one rule (issue
214, steps 1 and 2): split at the last blank line; one following line of
at most 80 characters (code points; a final line break allowed) is the
signature; otherwise the signature is the body's last word.  `read(text)`
gives body and signature; `signature(text)` the signature alone;
`characters(text)` counts code points; `examples()` reads 170's table.
Nothing stores a signature: every reader calls this (215's text copies
now, 301's viewer later).
