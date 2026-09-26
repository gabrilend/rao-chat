# 079-options.lua

The people-links module's undecided choices, as plain data for the options
tally (`scripts/tally-options`, issue 106).  `dofile` it; it returns a list
of choice tables in the contract's shape: `{id, question, waits_on
("owner" or "state"), detail, config_key, variants = list of {name, summary,
built_in, tests, findings}, leaning}`; `tests` may be a string or a list of
strings.  The first variant listed is the phase 1 demo's starting value.

Choices listed: `people-link-collision`, `people-slash-in-link-name`,
`people-direct-message-link`, `people-members-without-dm`,
`people-person-folder-collision` (owner, switchable); `people-own-devices`
and `people-rebuild-scope` (state, not switchable).  Retired in round 2:
`people-split-records`.  Answered and removed in round 4:
`people-flagged-members` (a flagged member counts toward the person's
rooms, as built).
