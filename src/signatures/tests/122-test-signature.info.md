# tests/122-test-signature.lua

Grades the signature reader (120) by every example in
`121-signature-examples.tsv`, checks the character count on well-formed
and malformed UTF-8, then grades the table itself: eight deliberately
broken readers (counting bytes; counting only lead bytes; splitting at
the first blank line; leaving `\r\n`; a final line break as a second
line; the blank line's breaks left on the body; a line of spaces signing;
the last word's punctuation stripped) must each get at least one example
wrong.

Usage: `luajit src/signatures/tests/122-test-signature.lua [DIR]` — `DIR`
is the project folder (default `/home/ritz/programs/rao-chat`).  Exit
status 0 when every check passed, 1 otherwise.
