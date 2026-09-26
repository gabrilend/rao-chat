# 019-options.lua

Plain data for the options tally (issue 106's `scripts/tally-options`):
returns a list of room-folders' undecided choices, each
`{ id, question, waits_on = "owner"|"state", detail, config_key, variants = { {name, summary, built_in, tests, findings}, ... }, leaning }`
(`findings` may be a string or a list of strings).  Load with `dofile`.
The first variant listed is the phase 1 demo's starting value.

Choices (round 3):

- `rooms-unheld-parent-mailbox` — key `mailboxes.unheld-parent`: `own-mailbox`, `waiting-mailbox` (issue 102's question; built in 101's `make_room`).
- `rooms-mailbox-after-parent-change` — not switchable: `keep` built.
- `rooms-bell-failure` — not switchable: `keep-and-raise` built.
- `rooms-write-durability` — not switchable, waits on state: `rename-only` built.
- `rooms-rmail-contacts` — not switchable: `own-folders` built.
- `rooms-token-change-children` — not switchable: `repoint-held` built.
- `rooms-heard-in-entry` — not switchable: `in-entry` built.
- `rooms-one-folder-per-token` — not switchable: `refuse-second` built.

Answered and removed in round 3: `rooms-suggested-token-words` (six words, fixed).
Retired in round 2: `rooms-unknown-parent`, `rooms-slash-in-name`.
