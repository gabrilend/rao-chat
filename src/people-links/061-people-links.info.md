# 061-people-links.lua

Keeps `rao-home/people/`: one folder per person, holding one link per top
room you share with them, so `ls people/<person>` answers "what do I share
with this person?".  The rooms' entries are the truth; the links are a view
rebuilt from them, so deleting `people/` and rebuilding gives the same
result.  Loaded with `require("061-people-links")` after the load path
(`src/room-folders/001-load-path.lua`).  Reads rooms only through
`060-neighbour-reads` (which calls 101's `config_value`/`on_change` and
102's `snapshot`).

- A **person** is a direct-message room (`kind = direct`): its label names
  the folder, its member address pairs are the person's machines.
- A group room is **theirs** when one of its members is one of those pairs
  (compared as `"<address> <port>"`, exactly as written).
- A room is a **top** for them when it is theirs and its parent in 102's
  tree (declared parent if held here, else filed-under, else none) is not
  theirs.

Types: **home** is `{dir = string}`; a **tag** is a room's local tag, 32
lower-case hex characters; a **member key** is the string
`"<address> <port>"`.

## Outward functions

| function | takes | gives | purpose |
|---|---|---|---|
| `top_rooms_for(home, dm_tag)` | home, tag of a direct-message room | sorted list of tags | The tops you share with that person.  Errors if the tag is not a direct-message room here.  Under `person-folder-collision = merge`, the pooled tops of everyone merged into that folder. |
| `top_rooms_for_addresses(home, pairs)` | home, list of `{address = string, port = integer or string}` | sorted list of tags | The top group rooms holding any of these pairs (no direct message ever counted). |
| `people(home)` | home | list of `{folder = string, id = string, dm_tags = sorted list of tags, addresses = sorted list of member keys}`, sorted by folder | Who has (or would have) a folder.  `id` is the direct message's tag, or the hex spelling of a member key for an address folder. |
| `planned_links(home, folder)` | home, string | list of `{path = string, target = string, room_id = string (tag), folder = string ("" or tag), name = string}`, sorted by path | What `people/<folder>/` should hold, without touching the disk.  Empty for a folder that is nobody's. |
| `rebuild_person(home, folder)` | home, string | nothing | Makes `people/<folder>/` hold exactly the planned links: removes this module's stale links, keeps anything else, creates missing links, removes the folder if it ends up empty.  Errors if something that is not its own link sits where a link must go, or if the name cannot be a folder name. |
| `rebuild_all(home)` | home | nothing | Rebuilds every person's folder and sweeps every folder already in `people/` that is nobody's any more. |
| `read_snapshot(home)` | home | table (below) | One read of every room, the tree and the choices, shared by a whole rebuild.  Outward for tests and the demo. |

A snapshot is `{modes = {collision, direct_message_link, members_without_dm,
person_folder_collision ("" when no clash)} (strings), tags = sorted list of
tags, rooms = tag -> {tag, label, kind, members = list of member keys,
tree_parent = tag or ""}, unsafe_mode = string ("" when no label needed
rewriting), people = list of {id, folder, addresses = set of member keys,
dm_tags = set of tags}}`.

## Config keys read

| key | when | values |
|---|---|---|
| `people.link-collision` | every rebuild | `suffix-id`, `numbered`, `id-folder` (see 063) |
| `people.direct-message-link` | every rebuild | `leave-out` (group rooms only), `include` (the person's own direct message linked too) |
| `people.members-without-dm` | every rebuild | `leave-out`, `address-folder` (a folder `host:port` / `[v6]:port` per member no direct message holds) |
| `people.person-folder-collision` | only when two people's folders would share a name | `suffix-id` (`alex~3fa9`), `numbered` (`alex`, `alex-2`), `merge` (one folder, pooled) |
| `people.slash-in-link-name` | only when some label holds `/` or is exactly `.` or `..` | `percent` (`%2F`, `%2E`, `%2E%2E`), `division-slash` (U+2215, U+2024, U+2025) |

All are read with `config_value`: a missing key is an error, never a default.

## What it listens for

Registers on 101's change bell at load: `created`, `label`, `token`,
`members`, `parent`, `filed`, `removed-room` → `rebuild_all`; `heard`,
`withheld`, `ignore`, `log` → nothing; any other kind → error.

## What it errors on

An empty label (or one holding the zero byte); a room kind other than
`group`/`direct`; the tree naming a parent that is not a room here; a folder
name that cannot be one; `people/` being a link; anything that is not this
module's link sitting where a link must go.

## What it never touches

Anything in `people/` that is not a link of exactly the shapes
`people/<p>/<name> -> ../../rooms/<32 hex>` or
`people/<p>/<32 hex>/<name> -> ../../../rooms/<32 hex>`.  A person's folder
that is itself a link is never entered.
