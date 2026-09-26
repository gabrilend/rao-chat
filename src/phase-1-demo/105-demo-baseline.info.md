# 105-demo-baseline.lua

Decides the config every demo home starts with: exactly the setting names
the modules declare (a home's config may hold no other name, and a module
refuses to run with a name it reads unset).  Loaded with
`require("105-demo-baseline")`.

A **setting** is `{ key = string, value = string, choice = string (the
choice id), module = string, source = "first listed" or
"input/phase-1-demo.config" }`.

| function | takes | gives | purpose |
|---|---|---|---|
| `from_options(options, declared)` | record from `gather.gather`; table name → `{module, file}` (101's `declared_settings()`) | list of setting (sorted by key), table key → list of variant names | One setting per **declared** name: its first listed variant when an options file records it, else `value = nil`, `source = "no value yet"`.  Errors: `declared` missing; two choices with one key; an options file's `config_key` that no module declares. |
| `parse_input(text)` | string: the text of `input/phase-1-demo.config` | list of `{ key, value, line = integer }` | Reads `key = value` lines; blank lines and `#` comments skipped; any other line is an error naming its number. |
| `apply_input(settings, variants_by_key, wanted)` | as above | integer: keys replaced | Replaces values in place.  An undeclared key, or a value that is not one of its built variants (when its options file lists variants), is an error.  Afterwards any setting still without a value is an error naming it. |

Example `input/phase-1-demo.config`:

    # run the demo under the variants I am leaning towards
    tree.parent-disclosure = shared-only
    recipients.split-alone = record-only
