# 019-options.lua

Plain data for the options tally (issue 106's `scripts/tally-options`):
returns a list of room-folders' undecided choices, each
`{ id, question, waits_on = "owner"|"state", detail, config_key, variants = { {name, summary, built_in, tests, findings}, ... }, leaning }`
(`findings` may be a string or a list of strings).  Load with `dofile`.
The first variant listed is the phase 1 demo's starting value.

Choices (round 4):

- `rooms-merge-when-parent-arrives` — key `mailboxes.merge-when-parent-arrives`: `automatic`, `ask` (answered as a setting kept both ways; the owner prefers automatic, listed first).
- `rooms-merge-declined` — not switchable: `stays-listed` built (new, round 4).
- `rooms-mailbox-after-parent-change` — not switchable: `keep` built.
- `rooms-bell-failure` — not switchable: `keep-and-raise` built.
- `rooms-write-durability` — not switchable, waits on state: `rename-only` built.
- `rooms-rmail-contacts` — not switchable: `own-folders` built.
- `rooms-token-change-children` — not switchable: `repoint-held` built.
- `rooms-heard-in-entry` — not switchable: `in-entry` built.
- `rooms-one-folder-per-token` — not switchable: `refuse-second` built.

Answered and removed in round 4: `rooms-unheld-parent-mailbox` (own mailbox, fixed; the waiting variant is gone).
Answered and removed in round 3: `rooms-suggested-token-words` (six words, fixed).
Retired in round 2: `rooms-unknown-parent`, `rooms-slash-in-name`.

Every `config_key` here must also be listed in `016-settings.lua`.
