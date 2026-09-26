# 099-options.lua — message-log's undecided choices

Returns a list of choice tables in the contract's shape (`id`, `question`,
`waits_on`, `detail`, `config_key`, `variants` = list of `{name, summary,
built_in, tests, findings}`, `leaning`).  Read by `scripts/tally-options`
and the phase 1 demo (issue 106), which start homes on the first variant
listed.  Plain data.

Choices: `log-duplicate-check` (log.duplicate-check, waits on state), and
two that cannot be switched: `log-pictures`, `log-early-edits` (waits
on state).  The header comment lists the choices removed in rounds 2, 3
and 4 as answered (round 4: `log-retired-keys-in-config` — 101's config
reader refuses any line no module declares).  Figures come from
`tests/095-measure.lua`.
