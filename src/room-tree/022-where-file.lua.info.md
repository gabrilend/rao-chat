# 022-where-file.lua

How the `where` file inside each room folder is written and read, and how a
label is written as one step of a path of labels.  Used by 021.

The file is two `key = value` lines:

    folder = /home/you/rao-home/rooms/3f2a...e1
    labels = home/ritz/programming

| function | takes | gives | purpose |
|---|---|---|---|
| `write(room_dir, labels)` | string (the room's folder), string (path of labels) | — | writes the two lines (temporary file, then rename); `folder` is `room_dir` itself. |
| `read(room_dir)` | string | `{ folder = string, labels = string }` | reads them back; errors if the file is missing, has a line that is not `key = value`, or lacks either key. |
| `path_step(label)` | string | string | the label as it appears inside a path: `\` doubled, `/` written `\/`.  Unchanged when neither appears. |
| `split_path(path)` | string | list of strings | the reverse of joining path steps with `/`: `"home/a\/b"` gives `{ "home", "a/b" }`. |
