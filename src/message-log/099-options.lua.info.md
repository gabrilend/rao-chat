# 099-options.lua — message-log's undecided choices

Returns a list of choice tables in the contract's shape (`id`, `question`,
`waits_on`, `detail`, `config_key`, `variants` = list of `{name, summary,
built_in, tests, findings}`, `leaning`).  Read by `scripts/tally-options`
and the phase 1 demo (issue 106), which start homes on the first variant
listed.  Plain data.

Choices: `log-duplicate-check` (log.duplicate-check, waits on state), and
three that cannot be switched: `log-pictures`, `log-early-edits` (waits
on state), `log-retired-keys-in-config`.  The header comment lists the
choices removed in rounds 2 and 3 as answered.  Figures come from
`tests/095-measure.lua`.
