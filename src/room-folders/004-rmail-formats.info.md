# 004-rmail-formats.lua

rmail's two plain-text formats, as text ↔ tables (no files opened).
Stricter than rmail: a line it cannot read is an error naming the line,
and every address must carry its own port.  Load with
`require("004-rmail-formats")`.

| function | takes | gives | what it does |
|---|---|---|---|
| `parse_config(text, where)` | string, string (a name for errors) | table key (string) → value (string) | `key = value` lines; `#` comments and blank lines skipped; a key twice is an error. |
| `config_with(text, key, value)` | string, string, string | string | The config text with `key` set (replaced in place, or appended).  Refuses keys outside `[A-Za-z0-9_.-]+`, multi-line values, edge spaces. |
| `parse_contacts(text, where)` | string, string | table name → table field (string) → value (string) | `name.field = value` lines; indexed fields keep their index (`c["ip[2]"]`); one pair of surrounding double quotes is taken off; a repeated plain `ip` is numbered as rmail does; any other field twice is an error; rmail's old JSON format is refused. |
| `address_pairs(fields, where, also)` | one contact's fields table, string, list of string or nil | list of `{index = integer, address = string, port = integer, <each name in also> = string}` sorted by index | Plain `ip`/`port` is index 0; `ip[N]`/`port[N]` index N (N from 1, no leading zero).  **Every address needs its own port** and every field named in `also` (the room entry passes `{"heard"}`); a lone port is an error; ports must be 1–65535. |
| `parse_port(text)` | string | integer or nil | A port written as rmail writes one, else nil. |
| `quote_value(text)` | string | string | `"` .. text .. `"` — how free text (labels, tokens) is written. |
| `CONFIG_KEY_PATTERN`, `CONTACT_NAME_PATTERN` | — | string | Lua patterns for a config key and a contact name. |
