# 041-recipients.lua  (issue 103)

Who is in a room and who your messages there go to.  Members are the address
pairs in the room's entry (101); `withheld` (one `<address> <port>` per
line, made empty by 101) is who you do not send to.  Loads 101
(`002-room-folders`), 102 (`021-room-tree`, for `may_join`) and 103a
(`042-ignore-list`).  A **member** below is `{address = string, port =
integer, heard = integer}`; `heard` is whole seconds since 1970 when that
address was last heard from, `0` = never.  A **pair** is `{address, port}`.

| function | takes | gives | what it does |
|---|---|---|---|
| `members(home, tag)` | home, local tag | list of member | The entry's members, in order, read fresh. |
| `is_member(home, tag, address, port)` | | bool | |
| `add_member(home, tag, address, port)` | | `"added"`, `"already"`, `"ignored"`, `"not-in-parent"` (+ reason string) | Appends with `heard = 0` (rings `members`).  Refusals are ordinary answers: ignored in this room (103a), or a child room whose parent does not hold the pair (102). |
| `withheld(home, tag)` | | list of pair | May hold former members (kept for if they return). |
| `withhold(home, tag, address, port)` | | `"withheld"` or `"already"` | Rings `withheld`.  Error if not a member. |
| `unwithhold(home, tag, address, port)` | | `"unwithheld"` | Rings `withheld`.  Error if not withheld. |
| `send_list(home, tag)` | | list of pair | Members minus withheld, entry order: where your next message goes. |
| `heard_from(home, tag, address, port, when)` | …, integer seconds | `add_member`'s word | A genuine message arrived: adds the address if needed (same refusals), then records `when` through 101's `write_heard` (rings `heard`) only if newer. |
| `confirm_leave(home, tag, address, port)` | | `"removed"` | The only removal.  Phase 2 calls it after the address confirmed its own leave.  Rings `members`.  Error if not a member.  Keeps any withheld line. |
| `silent_since(home, tag, since)` | …, integer seconds | list of member | Members last heard before `since` (never-heard included), for a client's pruning offer.  Removes nothing. |
| `shown_as(home, address, port)` | | `{text = string, how = "label" \| "labels" \| "address"}` | The label of the one direct-message room holding the pair; the address when none; when several, config `recipients.shared-address-label` (`all-labels` / `address`), read only then. |
