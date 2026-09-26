# 006-entry.lua

A room's `entry` file: one entry in rmail's contacts format, named by the
room's local tag.  Text ↔ table and every field rule; no disk access.
Load with `require("006-entry")` (002-room-folders uses it; other modules
should go through 002).

Entry table: `{ tag = string (32 hex), label = string, token = string,
kind = "group"|"direct", parent = string (64 hex fingerprint or ""),
mailbox = string (32 hex mailbox tag, never ""), filed_under = string (32 hex tag or ""), members = list of { address =
string, port = integer 1–65535, heard = integer ≥ 0 } }`.

File shape (fields always in this order; addresses numbered from 1):

    // rao-chat room entry: rmail's contacts format, one entry named by its local tag
    <tag>.label = "<label>"
    <tag>.token = "<token>"
    <tag>.kind = group
    <tag>.parent = <fingerprint or nothing>
    <tag>.mailbox = <mailbox tag>
    <tag>.filed-under = <tag or nothing>
    <tag>.ip[1] = <address>
    <tag>.port[1] = <port>
    <tag>.heard[1] = <seconds, 0 = never>

| function / value | takes | gives | what it does |
|---|---|---|---|
| `entry_text(entry)` | entry table | string | Checks every field, then writes the file text. |
| `parse_entry(text, tag, where)` | string, string (the folder's tag), string (file name for errors) | entry table | Refuses: more or fewer than one entry, an entry named by another tag, unknown fields, plain `ip`/`port`, an address missing its port or heard (or the reverse), gaps in numbering, repeated pairs, anything `entry_text` would refuse. |
| `check_entry(entry)` | entry table | nothing | Every rule, raising on the first broken one. |
| `check_members(list)`, `check_kind(kind)`, `check_label(label)`, `check_parent_shape(p)`, `check_mailbox_shape(m)`, `check_filed_shape(f)` | | nothing | One rule each. |
| `is_local_tag(value)` | anything | bool | 32 lower-case hex characters. |
| `KINDS` | — | table kind → meaning | `group`, `direct`. |
