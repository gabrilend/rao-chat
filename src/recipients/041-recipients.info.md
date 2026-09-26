# 041-recipients.lua  (issue 103)

Who is in a room and who your messages there go to.  Members are the address
pairs in the room's entry (101); `withheld` (one `<address> <port>` per
line, made empty by 101) is who you do not send to; `flagged` (one
`<address> <port> <state>` per line, made empty by 101, private, never sent)
holds members the room tree does not vouch for.  Loads 101
(`002-room-folders`), 102 (`021-room-tree`: `check_member`,
`failing_members`, `failing_below`) and 103a (`042-ignore-list`).

A **member** below is `{address = string, port = integer, heard = integer}`;
`heard` is whole seconds since 1970 when that address was last heard from,
`0` = never.  A **pair** is `{address, port}`.  A **flag** is `{address =
string, port = integer, state = string}`, state `"no"` (not a member of
some room declared above, as seen here), `"cannot-check"` (a room above is
not held here) — both **awaiting review**, sent nothing — or `"approved"`
(reviewed; an ordinary member, kept so re-checks do not flag it again).

| function | takes | gives | what it does |
|---|---|---|---|
| `members(home, tag)` | home, local tag | list of member | The entry's members, in order, read fresh. |
| `is_member(home, tag, address, port)` | | bool | |
| `add_member(home, tag, address, port)` | | `"added"`; `"added-flagged"`, answer (`"no"`/`"cannot-check"`), reason (string); `"already"`; `"ignored"` | Appends with `heard = 0` (rings `members`).  The one refusal is the ignore list (103a).  Anything the tree does not answer `yes` for is flagged first (rings `withheld`), then added. |
| `flags(home, tag)` | | list of flag | Every line of `flagged`, file order. |
| `flagged(home, tag)` | | list of flag | Only those awaiting review: what a client highlights. |
| `approve(home, tag, address, port)` | | `"approved"` | The flag becomes `approved`; the member is on the send list again (unless withheld).  Rings `withheld`.  Error if not awaiting review. |
| `decline(home, tag, address, port)` | | `"declined"` | Withholds the address (if not already) and deletes the flag.  It stays a member.  Error if not awaiting review. |
| `recheck(home, tag, itself)` | …, bool | integer (newly flagged), list of tags | Flags failing members of every room declared below `tag` (and of `tag` itself if `itself`) that have no flag line and are not withheld; then re-asks the tree about every flag awaiting review in the home: a changed answer is rewritten, a pass deletes the flag line (the flag clears by itself; no setting).  Approved lines are never re-flagged: an approval lasts until the address leaves.  Called by this module's bell listener; callable by hand. |
| `withheld(home, tag)` | | list of pair | May hold former members (kept for if they return). |
| `withhold(home, tag, address, port)` | | `"withheld"` or `"already"` | Rings `withheld`.  Error if not a member. |
| `unwithhold(home, tag, address, port)` | | `"unwithheld"` | Rings `withheld`.  Error if not withheld. |
| `send_list(home, tag)` | | list of pair | Members minus withheld minus those awaiting review, entry order: where your next message goes. |
| `heard_from(home, tag, address, port, when)` | …, integer seconds | `add_member`'s word (and answer, reason when flagged) | A genuine message arrived: adds the address if needed (flagged or not; refused only if ignored), then records `when` through 101's `write_heard` (rings `heard`) only if newer. |
| `confirm_leave(home, tag, address, port)` | | `"removed"` | The only removal.  Phase 2 calls it after the address confirmed its own leave.  Rings `members`.  Error if not a member.  Keeps any withheld line; deletes any flag line. |
| `silent_since(home, tag, since)` | …, integer seconds | list of member | Members last heard before `since` (never-heard included), for a client's pruning offer.  Removes nothing. |
| `shown_as(home, address, port)` | | `{text = string, how = "label" \| "labels" \| "address"}` | The label of the one direct-message room holding the pair; the address when none; when several, config `recipients.shared-address-label` (`all-labels` / `address`), read only then. |

**Bell listener** (registered on load): `members`, `token` on a room →
re-check its declared descendants; `created`, `parent` → the room's own
members and its descendants; every other known kind → nothing (`withheld`
is this module's own ring); an unknown kind → error.
