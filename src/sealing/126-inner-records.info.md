# 126-inner-records.lua

The record inside a frame: kind, then that kind's fields in a fixed order,
tab-separated, escaped by the log's rule (`\\ \t \n \r`; 083).  Decision of
2026-11-05 (issue 201, open question 1): the log's own shape.  Load with
`require("126-inner-records")`.

The table holds `message`, `correction` and `deletion` (fields `id`,
`written`, `target`, `text`: the log's record without `from` and
`arrived`), 202's `ack` (`answers`), and 204's `did-you` (`claim`,
`address`, `port`) and `did-you-answer` (`claim`, `answer`), and 205's
`hello` (`claim`, `pairs`), and 208's `leave` (`claim`, `written`,
`pairs`), and 207's `members-digest` and `members-ask` (`id`, `digest`,
`count`) and `members` (`id`, `digest`, `pairs`, `claims`), and 213's
`discover` and `here` (the hello's `claim` and `pairs`, sent as UDP
datagrams: a frame without its length).  A `pairs` field holds one "kind address
port" per line (kinds `public`, `hostname`, `ipv6`, `home-network`; port
1 to 65535); a pair without its port, an unknown kind, or no pairs is an
error.  The other kinds get their rows from the issues that define their
fields (209); until then they are unknown, and an unknown
kind is an error.

| function / value | takes | gives | what it does |
|---|---|---|---|
| `encode(record)` | `{kind, fields...}` | one line | Errors on an unknown kind, a missing field, a field the kind lacks, or a `written` that is not a whole number. |
| `decode(line)` | one line | the record | Errors on an unknown kind, a field too many or too few, an unknown escape, or a `written` that is not a whole number. |
| `kinds()` | — | sorted list | The kinds the table knows. |
| `escape(text)` | | | The log's escaping. |
| `KINDS` | — | table | The rows. |
| `PAIR_KINDS` | — | table | The kinds a `pairs` field may name. |
