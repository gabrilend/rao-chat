# 059-options.lua

The recipients module's undecided choices (issues 103 and 103a), for the
options tally (`scripts/tally-options`, issue 106) and the phase 1 demo.
`dofile` it; it returns a list of tables in the shape given in
`docs/phase-1-module-contract.md` ("The options tally"): `id`, `question`,
`waits_on` (`"owner"` or `"state"`), `detail`, `config_key` (`""` when not
switchable), `variants` (each `name`, `summary`, `built_in`, `tests`,
`findings`, all strings) and `leaning`.  The first variant of a switchable
choice is what the demo starts with.

Switchable: `ignore.hide-files`, `ignore.scope`, `ignore.match`,
`recipients.shared-address-label`.  Not switchable: two addresses for one
person (keep), withheld after a return (still withheld), what records
last-heard (the arrival path; waits on phase 2).
