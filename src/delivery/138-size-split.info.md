# 138-size-split.lua

A growing text file kept as a series of files, each under a size limit.
A new file starts before a write would carry the current one past the
limit, never after (215a's rule).  There are two namings. In "rotate" the
newest file keeps one name, older ones are renamed `.1`, `.2` and so on,
and only `keep` files are kept; 203's failed-decryption log uses it. In
"numbered" the files are `.0001`, `.0002` and so on, and none is ever
removed; this is for 215a's running log. A write larger than the limit is
split across files when numbered and refused when rotated. Issue 203,
step 3.
