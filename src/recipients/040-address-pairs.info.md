# 040-address-pairs.lua

The one shape every address takes in the recipients module: an address (IP
v4, v6, or hostname; text, no spaces) always paired with its port (whole
number 1–65535, no default).  Also reads and writes the small
space-separated files the module keeps (`withheld`, `ignore`), where each
line starts `<address> <port>`.

| function | takes | gives | what it does |
|---|---|---|---|
| `check(address, port, where)` | string, integer, string (for messages) | — | Errors unless the pair is well formed.  A port given as text is an error. |
| `key(address, port)` | string, integer | string `"<address> <port>"` | The pair as one line start / table key. |
| `same(a, b)` | two tables with `address`, `port` | bool | Same address and same port. |
| `split_line(line, want, path)` | string, integer, string | list of string | The line's words; errors unless exactly `want`. |
| `whole_number(text, path)` | string | integer | Errors on anything but a whole number. |
| `read_lines(path)` | string | list of string | Non-blank lines; errors if the file is absent. |
| `read_pair_file(path, extra)` | string, integer | list of `{address=string, port=integer, words=list of string}` | Each line is the pair plus exactly `extra` words. |
| `pair_file_text(rows)` | list as above | string | The reverse, one line per row. |
| `index_of(list, address, port)` | list of tables with `address`, `port` | integer | Position, or 0 when absent. |
