# 087-settings.lua

The message-log module's declared setting names, for 101's config reader
(contract, "Settings: every name is declared").  Returns a plain list of
strings: every config name this module reads.

| name | read by | values |
|---|---|---|
| `log.duplicate-check` | `append`, `correct`, `delete`, `has_message` | `remembered`, `scan` (open choice, `099-options.lua`) |

Retired names (`log.record-shape`, `log.shape-mixing`, `log.who-may-edit`,
`log.same-id-new-address`) are deliberately absent: a home still holding
one is refused by 101 when opened.  101 finds this file by scanning
`src/`; nothing in this module requires it.
