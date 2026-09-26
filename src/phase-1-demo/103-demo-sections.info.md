# 103-demo-sections.lua

Builds each scene of the phase 1 demo ("a room is a contact") on real home
folders and returns a record of what is on disk.  Prints nothing
(`104-demo-view.lua` draws).  Loaded with `require("103-demo-sections")`.

## The context every scene takes

`ctx` is a table:

| field | type | meaning |
|---|---|---|
| `scratch` | string | folder the scene's homes are made under (each home's folder is cleared first) |
| `m` | table | the loaded modules: `rooms` (002), `tree` (021), `forest_text` (024), `members` (041), `ignore` (042), `people` (061), `log` (081) |
| `probes` | table | `102-demo-probes` |
| `baseline` | list of `{ key = string, value = string }` | every config key set in each new home before anything else |
| `variants_by_key` | table string → list of string | the variants a scene runs for its key; a key missing here is an error |
| `options`, `gather` | record, module | only the `tally` scene uses these |

Every home a scene makes gets its one direct-message mailbox (port 7700)
at birth; each top group room starts a tree mailbox on the next free port
from 7701; a group room whose parent is not held here also starts a tree
mailbox of its own on the next free port.

A "pair text" below is a member written `"<address> <port>"` (string), the
shape 103's `withheld` and 105's `from` use.  An "attempt" is
`{ ok = bool, answer = string }`: the call's own answer when it ran, the
error's words when it raised.

## Outward functions (each takes `ctx`, gives a record)

| function | record fields |
|---|---|
| `entries(ctx)` | `home_dir`, `seconds_to_make` (number), `folder` (list of tags), `files` (list of "path  N bytes"), `rooms` = list of `{tag, entry_text, entry_bytes, read}` (`read` is 101's entry table), `direct_list`, `group_list` (lists of tags), `unpaired_make`, `unpaired_read` (attempts), `removed_line` (string) |
| `tokens(ctx)` | `suggested` = list of 3 strings (six-word suggestions from `suggest_token`); `typed`, `typed_back` (strings); `duplicate_token` (attempt); `before`, `after` = `{token, fingerprint, label, members (integer), messages (integer), log_bytes (integer), folder}`; `seconds_to_change` |
| `tree(ctx)` | `a`, `b` = list of `{tag, label, parent, fingerprint, where}` (home→kitchen→shopping on home A, family→cooking→groceries on home B); `lines_a`, `lines_b` (drawn trees); `kitchen_members` (pair texts); `check_coder`, `check_housemate`, `check_unheld` = `{answer ("yes"/"no"/"cannot-check"), reason (string)}` (102's `check_member`); `add_coder`, `add_housemate`, `approve_coder`, `leave`, `decline`, `add_unheld` (attempts); `leaver` (pair text); room views `shopping_flagged`, `shopping_approved`, `kitchen_after_leave`, `shopping_after_leave`, `kitchen_declined`, `orphan` = `{members, send (pair texts), flagged (file text)}`; `kitchen_withheld` (file text) |
| `mailboxes(ctx)` | `home_dir`; `rooms` = list of `{label, kind, mailbox (tag), mailbox_kind, port (integer)}`; `file` (the `mailboxes` file); `table` = list of `{tag, label, kind, port, rooms (labels)}`; `warnings_before` (integer); `tried` = list of `{port, rooms (labels whose keys a frame on that port is tried against)}` for the direct port and home's port; `shared = {port, warnings (list of 101's report texts), ports (101's `shared_ports`), tried (labels), file}`; `merge` = list per `mailboxes.merge-when-parent-arrives` variant of `{variant, before, trunk_before, loft, after, trunk_after, after_yes, trunk_after_yes` (each `{kind, port, tag}` of the mailbox attic / trunk / loft is in), `mergeable_before`, `mergeable_after_yes` (integers), `mergeable` = list of `{mailbox, into (tags), rooms (integer)}` (101's `mergeable_mailboxes` after loft arrived), `said_yes` (bool: `merge_mailbox` was called), `mailboxes` (as `table`)`}`; `config = {declared = list of {name, module}, lines_before (integer: setting lines in a fresh home's config), set_made_up (attempt: set_config with a misspelt name), bytes_before_refused_set, bytes_after_refused_set (integers), hand_line (string), reopen, read (attempts after the hand-written undeclared line)}` |
| `members(ctx)` | `members_before/after`, `send_before/after`, `send_restored` (pair texts); `withheld_before/after` (file text); `chosen` (pair text) |
| `leaving(ctx)` | `forged`, `real` (pair texts); `count_start`, `count_after_forged` (integers); `entry_before`, `entry_after` (file text); `entry_unchanged`, `forged_still_member` (bool); `confirmed`, `spoke` (attempts); `members_after_leave`, `send_after_leave`, `members_after_speaking` (pair texts) |
| `ignoring(ctx)` | `delivered`, `filed`, `log_bytes` (integers); `ignore_file` (text); `levels` = list of `{who, level}`; `other_port = {who, level, files (bool)}` (the hidden address on another port); `shown` = list of `{from, text, level}`; `readd_hidden`, `readd_marked`, `readd_after_unignore` (attempts); `other_members`, `other_members_after` (pair texts) |
| `people(ctx)` | `folders` (names in people/), `links` ("path -> target"), `labels` (tag → label), `collisions` = list of `{variant, links}` for the coder per `people.link-collision` variant |
| `log(ctx)` | `t0` (integer); `answers` (list of string); `repeat_answer`, `conflict`, `edit` (attempts); `in_file` = list of `{kind, from, written offset, text}`; `shown` = list of `{id, written offset, from, text, edited}`; `raw` (text); `bytes`; `bulk = {count, seconds, bytes}` — tab-separated records, the one shape; `two_homes = {homes = list of {tag, arrival (list of positions), in_file (ids), shown}, identical (bool)}` |
| `tally(ctx)` | `record` (the gathered options), `counts` |

`ORDER` is the list of `{ key, title }` in the order the demo shows them.
`SCRIPT_T0` (integer), `PEOPLE` and `SIX` (the example's addresses) are
exposed for the tests.
