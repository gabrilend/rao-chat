# 105-demo-baseline.lua

Decides the config every demo home starts with.  Loaded with
`require("105-demo-baseline")`.

A **setting** is `{ key = string, value = string, choice = string (the
choice id), module = string, source = "first listed" or
"input/phase-1-demo.config" }`.

| function | takes | gives | purpose |
|---|---|---|---|
| `from_options(options)` | record from `gather.gather` | list of setting (sorted by key), table key → list of variant names | One setting per switchable choice: its first listed variant.  Two choices with one key is an error. |
| `parse_input(text)` | string: the text of `input/phase-1-demo.config` | list of `{ key, value, line = integer }` | Reads `key = value` lines; blank lines and `#` comments skipped; any other line is an error naming its number. |
| `apply_input(settings, variants_by_key, wanted)` | as above | integer: keys replaced | Replaces values in place.  A key no options file records, or a value that is not one of its built variants, is an error. |

Example `input/phase-1-demo.config`:

    # run the demo under the variants I am leaning towards
    tree.parent-disclosure = shared-only
    recipients.split-alone = record-only
