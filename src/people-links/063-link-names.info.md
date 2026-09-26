# 063-link-names.lua

Works out what each link in a person's `people/` folder is called when two
of the rooms shared with them have the same name.  Pure: takes a list, gives
a list, touches no disk.  Loaded with `require("063-link-names")`.  Needs no
other module.

## Outward values and functions

| name | takes | gives | purpose |
|---|---|---|---|
| `MODES` | — | list of string: `"suffix-id"`, `"numbered"`, `"id-folder"` | The collision modes that are built (config `people.link-collision`). |
| `plan(rooms, mode)` | list of `{room_id = string (a room tag, or any unique id — 061 also names people's folders here), name = string}`, string | list of `{folder = string, name = string, room_id = string, path = string}`, sorted by `path` | One planned link per room.  `folder` is `""` (link straight in the person's folder) or the tag (`id-folder` mode); `path` is `name` or `folder/name`.  Errors on an unknown mode, or a room name that cannot be a file name (`""`, `.`, `..`, containing `/` or the zero byte). |

## The three modes

- `suffix-id` — rooms with a unique name keep it; each clashing room becomes
  `name~<first 4 characters of its id>`, lengthened (up to the longest id in the group) when
  4 characters do not separate them or would land on a name already used.
- `numbered` — unique names kept; each clashing group, in room-id order,
  becomes `name`, `name-2`, `name-3` …, skipping numbers already used by a
  real room's name.
- `id-folder` — every room becomes `<room id>/<name>`; nothing can clash.

The result never depends on the order the rooms were given in.
