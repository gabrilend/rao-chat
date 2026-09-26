# 024-forest-text.lua

Draws a home's forest (from 021's `forest(home)`) as plain text, one room
per line, with box-drawing branches.  Two marks may follow a label:
`   (filed)` (placed there on your own screen) and
`   (parent not held here)` (made inside a room you are not in).

| function | takes | gives |
|---|---|---|
| `lines(forest)` | a forest from `forest(home)` | list of strings, one per room |
| `text(forest)` | a forest | one string: the lines joined with line breaks, ending in one |

Example output:

    home
    ├── garden
    │   └── programming   (filed)   (parent not held here)
    └── kitchen
        └── recipes
    sam
