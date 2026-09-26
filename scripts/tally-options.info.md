# tally-options

Lists every undecided choice across the phase modules.  Run from any folder:

| command | shows |
|---|---|
| `scripts/tally-options` | the summary table and counts (owner and state apart) |
| `scripts/tally-options --walk` | one choice per page; Enter for the next, `q` to stop; stops (and says so) if input ends |
| `scripts/tally-options --walk --no-pause` | every page straight through |
| `scripts/tally-options <project folder> [flags]` | the same for another copy of the project |

An unknown argument exits with status 2.  A badly shaped options file stops
it with an error naming the file and field.  Reading is done by
`src/phase-1-demo/100-gather-options.lua`, showing by
`src/phase-1-demo/101-show-options.lua`.
