# 078-settings.lua

The people-links module's declared setting names, for 101's config reader
(contract, "Settings: every name is declared").  Returns a plain list of
strings: every config name this module reads.

| name | values (first = demo's start) | read |
|---|---|---|
| `people.link-collision` | `suffix-id`, `numbered`, `id-folder` | every rebuild |
| `people.slash-in-link-name` | `percent`, `division-slash` | only for a label with `/`, `.` or `..` |
| `people.direct-message-link` | `leave-out`, `include` | every rebuild |
| `people.members-without-dm` | `leave-out`, `address-folder` | every rebuild |
| `people.person-folder-collision` | `suffix-id`, `numbered`, `merge` | only when two direct messages share a label |

All five are open choices (`079-options.lua`).  The list must name the
same keys as `061-people-links.lua`'s `CHOICES` table; test
`071-test-choices.lua` checks that.  101 finds this file by scanning
`src/`; nothing in this module requires it.
