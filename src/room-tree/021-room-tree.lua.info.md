# 021-room-tree.lua

The room tree: which room sits under which, worked out from the rooms'
entries (issue 101) every time it is asked, and the parent-membership
check ("does this address belong in this room, by the rooms declared above
it?" — detected, never enforced).  `require("021-room-tree")`.

A room sits under another in one of two ways:

- **declared** — made as a child: its entry's `parent` is the fingerprint
  of the parent's token.  The parent-membership check applies.  (It also
  lives in its parent's mailbox; 101 chooses and moves mailboxes.)
- **filed** — placed there on your own screen: its entry's `filed-under`
  is the parent's local tag.  Never sent; no rule.

A room with both shows under its declared parent when that parent is held
here, else under its filing, else it is a top.  A declared parent not held
here leaves the room a top, marked `parent_unheld`.

Loading the module registers a listener on 101's change bell that keeps
every room's `where` file (022) true.

## Types

- `home` — `{ dir = string }`
- `tag` — string, a local tag (32 hex characters); `""` means none
- `address` — non-empty string; `port` — whole number (a port given as
  text is an error, never a silent mismatch)

## Functions

| function | takes | gives | purpose |
|---|---|---|---|
| `check_member(home, tag, address, port)` | home, tag, string, integer | answer (string), reason (string, `""` for yes) | the parent-membership check.  Walks the declared rooms above `tag` (never filing), nearest first, as far as this home holds them.  `"yes"`: no declared parent, or every one of them holds that exact (address, port) pair.  `"no"`: some held room above lacks it (reason names each, nearest first) — wins over cannot-check.  `"cannot-check"`: every held room above holds it but the chain runs into a parent not held here.  Refuses nothing; 103 adds the member and flags it on no / cannot-check. |
| `check_member_in(snap, tag, address, port)` | snapshot, tag, string, integer | as above | the same, from a snapshot already taken (for checking many members) |
| `failing_members(home, tag)` | home, tag | list of rows | every member of `tag` itself whose answer is not yes; row = `{ room = tag, address = string, port = integer, answer = "no" \| "cannot-check", reason = string }`, in the entry's member order |
| `failing_below(home, tag)` | home, tag | list of rows (as above) | re-checking after `tag`'s members change: every failing member of every declared descendant (all levels, top-down, siblings by label then tag).  Lists all failing, not only newly failing (103 keeps its flags).  Filed rooms not included. |
| `tree_parent_of(home, tag)` | home, tag | tag or `""` | the room it shows under (declared if held, else filed, else none) |
| `declared_parent_of(home, tag)` | home, tag | tag or `""` | the held room whose token fingerprint its `parent` names |
| `placement(home, tag)` | home, tag | `{ how = "declared" \| "filed" \| "top", parent_unheld = bool }` | how it came to sit where it is |
| `children_of(home, tag)` | home, tag | list of tags | rooms showing directly under it, by label then tag |
| `tops(home)` | home | list of tags | top rooms, by label then tag |
| `ancestors(home, tag)` | home, tag | list of tags | top first, ending with `tag` |
| `path_of_labels(home, tag)` | home, tag | string | your labels from the top joined with `/`; a `/` inside a label is written `\/` and `\` as `\\` (022's `split_path` reverses it) |
| `forest(home)` | home | list of nodes | every room as trees; node = `{ tag, label, kind ("group"/"direct"), placed ("declared"/"filed"/"top"), parent_unheld (bool), children (list of nodes) }`, sorted by label then tag.  Drawn by 024. |
| `file_under(home, tag, under)` | home, tag, tag or `""` | — | files a room under another on your screen, or unfiles it (`""`).  Refuses a room not held here, itself, or a room already inside it (a ring).  Writes through 101 (`write_filed_under`, rings `filed`). |
| `snapshot(home)` | home | table | the whole tree from one read of every entry, for callers asking many questions: `tags` (list), `entries` (tag → entry), `by_print` (fingerprint → tag), `declared`, `parent` (tag → tag or `""`), `unheld` (tag → bool), `placed` (tag → string), `children` (tag → list), `tops` (list).  Every function above builds one per call, so a caller looping over rooms should take one snapshot instead. |
| `write_all_where(home)` | home | — | rewrites every room's `where` (the listener does this on its own; for a home made before the tree was loaded, or a moved home folder) |
| `read_where(home, tag)` | home, tag | `{ folder = string, labels = string }` | the room's `where` file |

Every function errors on a tag not held here, and on a ring of rooms
inside each other (naming each room in it).

## The bell listener

| kind | what the tree does |
|---|---|
| `created`, `label`, `parent`, `filed`, `token` | mends a ring if one was closed (below), rewrites every `where` |
| `removed-room` | unfiles rooms filed under the removed room, then as above |
| `members`, `heard`, `withheld`, `log`, `ignore`, `mailbox` | nothing (re-checking members is 103's listener's, through `failing_below`) |
| anything else | error |

A ring can close without anyone filing into it: a declared parent arrives
that puts a room you filed above the room it was filed under.  Config
`tree.filing-loop`, read only then: `unfile` (the filed rooms in the ring
are unfiled; declared parents win) or `refuse` (the change raises; the
tree errors until unfiled by hand).  A ring of declared parents only is
always an error.

On `token`, room-folders has already re-pointed held children to the new
fingerprint before ringing, so the tree follows by itself.
