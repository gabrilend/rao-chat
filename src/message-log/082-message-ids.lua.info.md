# 082-message-ids.lua — message ids and field checks

| function | takes | gives |
|---|---|---|
| `new_message_id()` | — | string: 16 random bytes from /dev/urandom as 32 lower-case hex characters |
| `check_id(value, what)` | any, string label | — ; error unless a non-empty string of letters, digits, `-`, `_` |
| `check_from(value)` | any | — ; error unless `"me"` or `"<host> <port>"`: host a non-empty run of non-whitespace, one space, port a whole number 1–65535 without leading zero |
| `check_time(value, what)` | any, string label | — ; error unless a whole number ≥ 0 |

The narrow id alphabet (no tab, no newline) is what lets the log find an
id by plain text search (see 083, `id_marker`).
