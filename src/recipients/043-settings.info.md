# 043-settings.lua

The recipients folder's declaration of the config names it reads (issues
103 and 103a), for 101's config reader (`src/room-folders/017-declared-
settings.lua`; contract section "Settings: every name is declared").
Returns a plain list of strings; `loadfile` / `dofile` it.

| name | read by | values |
|---|---|---|
| `ignore.scope` | `042-ignore-list.lua`, every lookup and change | `home`, `home-and-room` |
| `recipients.shared-address-label` | `041-recipients.lua` `shown_as`, only when two direct-message rooms hold one address | `all-labels`, `address` |

A config line naming anything else (for example the retired
`recipients.flag-after-passing`) is refused by 101 when the config is read.
