# 214 — A message's signature

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 105
**Blocks:** 215, 210, 301

## Current Behavior

Nothing exists beyond storage: 105 keeps a message's text exactly as
written, signature included ("the signature, if any, is the last line of
`text`, stored as written"), and nothing reads a signature out of it.

## Intended Behavior

The sender of a message is unknowable by design; the signature is what a
message says about itself.  The owner (2026-09-27):

> body text, newline newline, signature. If the signature is longer than
> one line, then it is the body text still, and the last word is used.

> last line over 80 characters is a body text, not a signature. Use the
> last word of the body text as the signature if there's no signature.

So **every message shows a signature**, read from its text by one rule:

1. Split the text at its **last blank line** (two line breaks in a row).
2. If the part after it is **exactly one line of at most 80 characters**
   and not empty, that line is the signature and the part before is the
   body.
3. Otherwise the whole text is the body, and the signature is the
   **last word of the body** (the last run of characters that are not
   spaces, tabs or line breaks).

- **Read, never stored apart.**  The text stays as written (105); the
  signature is worked out whenever it is shown or copied, by one function
  every reader calls (the text copies, 215; the viewer's inbox, 301).
- **Writing**: the viewer keeps a persistent signature field; sending
  appends a blank line and the field.  A field longer than 80 characters
  is refused as it is typed, since it would not read back as a signature.
- **Signing as someone else is taboo, not prevented** (planning section 2).

## Rubric

This rule comes from the owner, not from rmail (rmail has subjects and
`from:` lines, and no signature).  The rubric for it is the rule's own
edges, which a reader in another language (the Android app, the web page)
must reproduce exactly:

- **Characters, not bytes**, for the 80 (open question 1): a signature in
  a script whose letters take several bytes must not lose its place.
- **Line breaks are `\n`**; a `\r\n` from a browser must read the same.
- **The reader in every language is graded by one table of examples**
  (the referees), because two implementations of one rule drift — the
  lesson of rmail's phone and daemon disagreeing about the frame cap
  (sealing note R3).

## Where we differ

There is nothing in rmail to differ from.  The formation is **derived at
read time**: no signature field in the log, the wire record or the
entry; one function, one table of examples shared by every reader.

- **Gains:** the log keeps exactly what was written; a change to the rule
  changes every display at once, old messages included.
- **Costs:** each reader must implement the rule (Lua on the server,
  Kotlin, JavaScript); the example table is the only thing keeping them
  together.

## Referees

A table of texts and their (body, signature), kept as a data file every
implementation's test reads:

1. `"hi\n\nsorelu"` → body `"hi"`, signature `"sorelu"`.
2. `"hi\n\nsorelu\nand more"` (two lines after the blank) → body is the
   whole text, signature `"more"`.
3. `"hi\n\n"` followed by 81 characters → the whole text is body, signature
   its last word.
4. `"hi\n\n"` followed by exactly 80 characters → that line is the
   signature.
5. `"no blank line here"` → signature `"here"`.
6. `"hi\r\n\r\nsorelu"` → as case 1.
7. An 80-character signature of characters that are 3 bytes each in UTF-8
   → a signature.  *Broken:* counting bytes.
8. `"hi\n\n\nsorelu"` (blank line then another) → proposed as case 1
   (the split is at the last blank line).  *Broken:* a split at the first
   blank line.

## Suggested Implementation Steps

1. The example table as a data file.
2. The Lua reader and its test against the table.
3. The viewer's signature field and the append on sending (with 301).

## Blockers that are not the owner's

- Needs 105 (texts as written).

## Open questions

1. **80 characters**: Unicode code points (proposed) or bytes?
2. **An empty message, or one of only spaces**: no last word — show no
   signature, or refuse to send it?
3. **Trailing punctuation in the last word** (`"see you, sorelu."`): keep
   the full stop (proposed, the rule says "last word") or strip it?
4. **An ordinary closing paragraph is "signed" by its last word** — the
   rule's consequence, noted by the planning document as "to confirm".
   The owner's second answer settles last-line length; confirm this too.
5. *(answered 2026-09-27)* **The signature is at most one line of 80
   characters, after a blank line; otherwise the last word of the body.**

## Related documents

- `notes/vision-planning.md` sections 2 (signature), 15 ("Key-tying, the
  log and git, signatures"; "Git per mailbox, signatures settled")
