# 083-record-codecs.lua — the log's record shape (tsv)

A codec is a table `{ encode, decode, id_marker }`.  Records are as in
`081-message-log.lua.info.md`.  One shape, tsv (the owner's answer); the
table is kept so a shape can be added back.  The block and jsonl shapes
were retired in round 3 (git history).

| name | takes | gives |
|---|---|---|
| `codecs.SHAPE` | — | string `"tsv"`, the shape every log is written and read in |
| `codecs.SHAPES` | — | table shape name (string) → codec; only `tsv` |
| `codecs.get(shape)` | shape name (string) | the codec; error on any name not in `SHAPES` |
| `codec.encode(record)` | record | string, one line to append, newline included |
| `codec.decode(raw)` | string, one line without its newline | record; error naming the fault when damaged (wrong field count, unknown escape, bad number, unknown kind) |
| `codec.id_marker(id)` | id string | `"\n" .. id .. "\t"`, which occurs in a log only where that id's record begins |

On disk: `id\tfrom\twritten\tarrived\tkind\ttarget\ttext\n`; in text,
`\` `TAB` `LF` `CR` are written `\\` `\t` `\n` `\r`.  A line in a retired
shape (a block's `id: …`, a JSON object) has one field, not seven, and is
refused.
