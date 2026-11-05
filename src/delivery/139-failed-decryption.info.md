# 139-failed-decryption.lua

The failed-decryption log (issue 203).  It writes one line for each frame
that no held key opens, and one for each frame refused for its length.
Each line gives the source address and port, the mailbox's listening port,
the announced length and the reason, in the grammar written down in
`docs/failed-decryption-log.md` (version `v1`).  It also reads lines back
(`parse`).  The file is written through 138's "rotate" split.  It reads
`failed-decryption.file-size` and `failed-decryption.files-kept`, neither
with a default.  `seams` gives the two calls 133's `serve` makes.
