# 101-show-options.lua

Presents the gathered choices (from `100-gather-options.lua`) as text.
Every function returns a list of lines (list of string) rather than
printing, except `walk`, which is handed a way to read and a way to write.
Loaded with `require("101-show-options")`.

## Outward functions

| function | takes | gives | purpose |
|---|---|---|---|
| `summary_lines(record, counts)` | record from `gather.gather`, counts from `gather.counts` | list of string | The files read, a table with one row per choice (number, id, waits on, config key or "(not switchable)", variant names joined by " / ", module), a "waits for:" line under each state choice, a "leaning:" line under every choice, and the counts. |
| `counts_lines(counts)` | counts | list of string | "choices: N    waiting on the owner: N    waiting on some other state: N    variants listed: N", then one line per module. |
| `page_lines(choice, position, total)` | choice, integer, integer | list of string | One choice in full: question, waits on, detail, config key, and each numbered variant's summary, built in, tests and findings, then the leaning.  Lines fit 78 columns (a single over-long word is left whole). |
| `walk(record, read_line, write, pause)` | record; function giving a string or nil at end of input; function taking one string; bool | integer: pages shown | One page per choice.  With `pause` true, asks "[Enter] next choice    [q] stop" between pages: "q" stops, end of input stops and says "(input ended after choice k of n)"; any other answer goes on.  With `pause` false, prints every page straight through. |
