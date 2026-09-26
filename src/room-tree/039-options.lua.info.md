# 039-options.lua

Plain data for the options tally (`scripts/tally-options`): returns a list
of the room tree's undecided choices, one table each, in the shape given in
`docs/phase-1-module-contract.md` ("The options tally").  The first variant
listed is the one the phase 1 demo starts homes with.

| id | waits on | config key |
|---|---|---|
| `tree-unheld-parent-join` | owner | `tree.unheld-parent-join` (`refuse`, `accept`) |
| `tree-filing-loop` | owner | `tree.filing-loop` (`unfile`, `refuse`) |
| `tree-member-match` | owner | — (`exact-pair` built) |
| `tree-leaving-the-parent` | owner (issue 102 open question 2) | — (`client-cleans-up` built) |
| `tree-rule-depth` | owner | — (`parent-only` built) |
| `tree-removed-shelf` | state (phase 2 leaving) | — (`unfile` built) |

Retired in round 2: `tree-parent-disclosure`, `tree-disclosure-refresh`,
`tree-where-per-recipient`, `tree-untell-on-removal`, `tree-slash-in-path`.
