# 039-options.lua

Plain data for the options tally (`scripts/tally-options`): returns a list
of the room tree's undecided choices, one table each, in the shape given in
`docs/phase-1-module-contract.md` ("The options tally").  The first variant
listed is the one the phase 1 demo starts homes with.

| id | waits on | config key |
|---|---|---|
| `tree-filing-loop` | owner | `tree.filing-loop` (`unfile`, `refuse`) |
| `tree-member-match` | owner | — (`exact-pair` built) |
| `tree-removed-shelf` | state (phase 2 leaving) | — (`unfile` built) |

The room tree's round 3 open question — which mailbox a child room made
while its declared parent is not held goes in — was answered in round 4:
its own mailbox and port, always (101's `mailboxes.unheld-parent` is
retired).  Whether that mailbox merges into the parent's by itself when
the parent arrives is the person's setting (the owner: "config setting
... I prefer automatic"): 101's choice `rooms-merge-when-parent-arrives`
(config
`mailboxes.merge-when-parent-arrives`: `automatic`, `ask`), built in 101
and listed in 101's options file, not here (ids are unique).  The tree's
`tests/028-test-mailboxes.lua` tests both values with a chain arriving
bottom-up; the tree drawn is the same either way.

The one setting this module reads, `tree.filing-loop`, is declared to
101's config reader in `023-settings.lua`.

Retired in round 2: `tree-parent-disclosure`, `tree-disclosure-refresh`,
`tree-where-per-recipient`, `tree-untell-on-removal`, `tree-slash-in-path`.
Answered and removed in round 3: `tree-unheld-parent-join` (the check now
answers `cannot-check`), `tree-rule-depth` (every room above),
`tree-leaving-the-parent` (only flagged).
