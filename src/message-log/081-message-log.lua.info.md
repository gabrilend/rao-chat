# 081-message-log.lua — the message log's front door

`require("081-message-log")` (after `001-load-path.lua` has set the search
path).  Needs `002-room-folders` (issue 101) for `config_value`,
`log_path(home, tag)` and `notify(home, tag, "log")`.

A **home** is `{ dir = string }`.  A **room** is named by its local folder
tag (string).  A **record** (what `read` gives) has every field, never nil:

| field | type | meaning |
|---|---|---|
| `id` | string | the message's own id; letters, digits, `-`, `_` |
| `from` | string | `"me"`, or the address the copy arrived from, `"<host> <port>"` (one space; port 1–65535) — proves nothing about who wrote it |
| `written` | integer | seconds since 1970 when written (the writer's clock) |
| `arrived` | integer | seconds since 1970 when it reached this home |
| `kind` | string | `"message"`, `"correction"` or `"deletion"` |
| `target` | string | id an edit changes; `""` for a message |
| `text` | string | any bytes; the signature, if any, is its last line |

Config key read (absent is an error): `log.duplicate-check`
(scan/remembered), by `append`, `correct`, `delete` and `has_message`.
`read` and `read_ordered` read no config.  The record shape is tsv, fixed
(083); anyone may edit; a repeat differing only in `from` is a duplicate.
The retired keys `log.record-shape`, `log.shape-mixing`,
`log.who-may-edit`, `log.same-id-new-address` are not read.

| function | takes | gives |
|---|---|---|
| `new_message_id()` | — | string, 32 hex characters from /dev/urandom |
| `append(home, tag, message)` | message `{id, from, written, arrived, text}` (a `kind`, if present, must be `"message"`) | `"filed"` or `"duplicate"`; rings `"log"` when filed; **error** when the id is already filed with different `written`/`kind`/`target`/`text` (naming both versions), on a bad field, or a missing room |
| `correct(home, tag, correction)` | `{id (new), from, written, arrived, target, text}` | `"filed"` / `"duplicate"`; anyone may edit any message; error when the target is missing, not a message, or already deleted |
| `delete(home, tag, deletion)` | `{id (new), from, written, arrived, target}` | as `correct`; the original text stays in the file |
| `has_message(home, tag, id)` | string id | bool — any record (message or edit) with that id |
| `read(home, tag)` | — | list of records, file order |
| `read_ordered(home, tag)` | — | list of views `{id, from, written, arrived, text, edited=bool, deleted=bool, changed_from=string}`, messages only, edits applied, sorted by written time then message id; a deleted message stays, text `""`, `deleted = true` (how it is shown is the client's setting) |
| `forget_remembered_ids(path)` | log path or `"all"` | — ; clears the remembered duplicate check's memory |

Which fields count as "contents" for a repeat: `written`, `kind`,
`target`, `text`.  `arrived` never does (every repeat arrives anew).
Nor does `from`: the same contents from another address are a
duplicate, and the first copy's `from` stays in the file.
