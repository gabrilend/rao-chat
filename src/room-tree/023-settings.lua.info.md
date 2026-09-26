# 023-settings.lua

The room-tree module's declared setting names, for 101's config reader
(contract, "Settings: every name is declared").  Returns a plain list of
strings: every config name this module reads.

| name | read by | values |
|---|---|---|
| `tree.filing-loop` | `021-room-tree.lua`, only when a declared parent closes a ring with a filing | `unfile`, `refuse` (open choice, `039-options.lua`) |

Not read by anything in this module; 101 finds it by scanning `src/`.
A name read by the code but missing here makes `config_value` error.
