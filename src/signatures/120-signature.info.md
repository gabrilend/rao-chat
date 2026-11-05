# 120-signature.lua

Reads a message's signature out of its text, by the one rule every reader
follows (issue 214).  Pure: takes a string, gives strings, touches no disk.
Loaded with `require("120-signature")`.  Needs no other module.  The
signature is never stored: the log keeps the text as written (105), and
this is called whenever a signature is shown or copied.

## Outward values and functions

| name | takes | gives | purpose |
|---|---|---|---|
| `LONGEST` | — | number `80` | The most characters a signature line may hold. |
| `read(text)` | string, a message's text as written | body (string), signature (string, `""` for none), how (`"line"`, `"last-word"` or `"none"`) | The rule below. |
| `characters(text)` | string | number | Characters (code points) in the text read as UTF-8; a byte that is not part of a well-formed character counts as one. |
| `last_word(text)` | string | string | The last run of characters that are not spaces, tabs or line breaks; `""` when there is none. |

## The rule

1. `\r\n` reads as `\n`, and line breaks at the very end are set aside.
2. Split at the last blank line (two line breaks together).  If the part
   after it is one line, not empty and not only spaces and tabs, of at
   most 80 characters, that line is the signature, and the part before
   (without its trailing line breaks) is the body: how `"line"`.
3. Otherwise the text is the body and its last word the signature, full
   stop and all: how `"last-word"`; `"none"` with signature `""` when the
   text holds no word.

The examples every implementation is graded by are in
`121-signature-examples.tsv` (one a line: text, body, signature, how, a
note; the log's escapes plus `\xHH`).
