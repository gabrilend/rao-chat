# 086-edits.lua — corrections and deletions (always allowed; who may edit is open)

| function | takes | gives |
|---|---|---|
| `check(who, records, edit)` | `log.who-may-edit` value (string: `"anyone"` or `"same-address"`), the room's records (list, file order), the edit record (kind correction/deletion) | — ; error when the target is missing, not a plain message, or already deleted; under `same-address` also when `edit.from ~= target.from`; error on an unknown `who` |
| `apply(records)` | records in file order | list of views `{id, from, written, arrived, text, edited=bool, deleted=bool, changed_from=string}`, messages only, file order; latest correction/deletion by (written, id) wins; deleted → text `""`; `changed_from` is the address of the edit applied, `""` when none |

Edits already in a file are applied when reading whatever
`log.who-may-edit` says now; the rule governs filing only.
