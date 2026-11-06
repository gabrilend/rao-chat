# 215-test-reaching-the-home.lua

Issue 403's referees: `add --browser` gives a page lines it reads whole
and a test the home answers (a phone's lines unchanged); a wrong token, a
wrong path, a closed port and a silent listener are each named (broken:
`one-message`); home network first (broken: `public-first`), and a home
that opens but refuses is said, not passed over; a pong for another
ping is not an answer; the token is never remembered (broken:
`keep-token`); settings are checked.  Run under the loopback-only
wrapper (127.0.0.2, ports 46403 to 46473):
`luajit src/web/tests/215-test-reaching-the-home.lua [project]`.
