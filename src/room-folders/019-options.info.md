# 019-options.lua

Plain data for the options tally (issue 106's `scripts/tally-options`):
returns a list of room-folders' undecided choices, each
`{ id, question, waits_on = "owner"|"state", detail, config_key, variants = { {name, summary, built_in, tests, findings}, ... }, leaning }`
(`findings` may be a string or a list of strings).  Load with `dofile`.
The first variant listed is the phase 1 demo's starting value.

Choices (round 2):

- `rooms-suggested-token-words` — key `rooms.suggested-token-words`: `6`, `5`, `4`.
- `rooms-bell-failure` — not switchable: `keep-and-raise` built.
- `rooms-write-durability` — not switchable, waits on state: `rename-only` built.
- `rooms-rmail-contacts` — not switchable: `own-folders` built.
- `rooms-token-change-children` — not switchable: `repoint-held` built.
- `rooms-heard-in-entry` — not switchable: `in-entry` built.
- `rooms-one-folder-per-token` — not switchable: `refuse-second` built.

Retired (round 1 only): `rooms-unknown-parent`, `rooms-slash-in-name`.
