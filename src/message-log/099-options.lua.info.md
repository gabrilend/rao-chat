# 099-options.lua — message-log's undecided choices

Returns a list of choice tables in the contract's shape (`id`, `question`,
`waits_on`, `detail`, `config_key`, `variants` = list of `{name, summary,
built_in, tests, findings}`, `leaning`).  Read by `scripts/tally-options`
and the phase 1 demo (issue 106), which start homes on the first variant
listed.  Plain data.

Choices: `log-record-shape` (log.record-shape), `log-who-may-edit`
(log.who-may-edit), `log-shape-mixing` (log.shape-mixing),
`log-duplicate-check` (log.duplicate-check, waits on state),
`log-same-id-new-address` (log.same-id-new-address), and three that cannot
be switched: `log-pictures`, `log-deleted-view`, `log-early-edits`.
Figures come from `tests/095-measure.lua`.
