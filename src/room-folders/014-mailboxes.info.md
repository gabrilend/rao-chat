# 014-mailboxes.lua

The `rao-home/mailboxes` file: which listening port each group of rooms
uses.  Text ↔ list and every field rule; no disk access (002-room-folders
reads and writes the file and decides which mailbox a room goes in).
Load with `require("014-mailboxes")`; other modules should go through
`002-room-folders`.

A **mailbox** is a table `{ tag = string (32 lower-case hex, never sent),
label = string (one non-empty line), kind = "tree" | "direct",
port = integer 1–65535 (no default), awaits_parent_of = string (32 hex: the
child room this tree mailbox was made for while its parent was not held
here, so it can merge into the parent's later; or "") }`.

File shape (rmail's contacts format, one entry per mailbox, sorted by tag):

    // rao-chat mailboxes: rmail's contacts format, one entry per mailbox named by its local tag
    <tag>.label = "<label>"
    <tag>.kind = tree
    <tag>.port = 7777
    <tag>.awaits-parent-of = <room tag, or nothing>

| function / value | takes | gives | what it does |
|---|---|---|---|
| `mailboxes_text(list)` | list of mailbox | string | Checks every rule, then writes the file text sorted by tag; an empty list gives the header line only. |
| `parse_mailboxes(text, where)` | string, string (file name for errors) | list of mailbox, sorted by tag | Refuses an unknown or missing field, a field set twice, a malformed port, an unknown kind (`waiting` is retired), a tag twice, a second `direct` mailbox, an `awaits-parent-of` that is not `""` or a tag, or set on a non-tree mailbox; every error names `where`.  A round-3 file (no `awaits-parent-of`) is refused. |
| `shared_ports_of(list)` | list of mailbox | list of `{port = integer, mailboxes = sorted list of tags}`, sorted by port | The ports named by two or more mailboxes (allowed, reported by 002). |
| `check_mailbox(m)`, `check_mailbox_kind(kind)`, `check_port(port, what)` | | nothing | One rule each; `what` names the value in the error. |
| `is_local_tag(value)` | anything | bool | 32 lower-case hex characters. |
| `MAILBOX_KINDS` | — | table kind → `{how_many = "many" or "one", meaning = string}` | `tree` (many), `direct` (one). |
| `HEADER` | — | string | The file's first line. |
