# 100-gather-options.lua

Collects every module's undecided choices (`src/<module>/<NNN>-options.lua`,
exactly one folder below `src/`) into one checked list.  The gathering half
of the options tally; `101-show-options.lua` is the showing half.  Loaded
with `require("100-gather-options")` once `src/phase-1-demo/` is on the
search path.

A **choice** is the contract's shape ("The options tally" in
`docs/phase-1-module-contract.md`) plus two labels:

| field | type | meaning |
|---|---|---|
| `id` | string | unique across the whole project |
| `question` | string | the question in plain English |
| `waits_on` | string, `"owner"` or `"state"` | who or what must settle it |
| `detail` | string | which open question, or what state it waits for |
| `config_key` | string | the rao-home config key, `""` when not switchable |
| `variants` | list of variant | at least one |
| `leaning` | string | the builder's suggestion and why |
| `module` | string | the module folder the file sits in (added here) |
| `file` | string | the options file's full path (added here) |

A **variant** is `{ name = string, summary = string, built_in = list of
string, tests = list of string, findings = list of string }`.  In the file,
`built_in`, `tests` and `findings` may each be one string or a list of
strings; here they are always lists.

## Outward functions

| function | takes | gives | purpose |
|---|---|---|---|
| `gather(src_dir)` | string: the project's `src` folder | record `{ files = list of { module = string, file = string, count = integer }, choices = list of choice }` | Reads every options file, in path order.  Errors (naming file and field) on a file that does not load, fails while running, or holds a choice of the wrong shape; errors when one id is used twice. |
| `read_file(file, module_name)` | string, string | list of choice | Reads and checks one options file. |
| `counts(record)` | record from `gather` | `{ total, owner, state, variants = integer, by_module = list of { module = string, owner = integer, state = integer } }` | The tally's figures, owner and state counted apart, so every view reports the same numbers. |
