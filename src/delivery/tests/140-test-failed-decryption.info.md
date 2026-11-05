# 140-test-failed-decryption.lua

Issue 203's referees 1–4, each run against the real modules and against a
deliberately broken version that it must catch.  It also checks the line
grammar, the settings, the filter against other kinds of line, and 138's
numbered naming.

Frames reach the real reader (133's `serve`) through a stand-in
connection that counts the bytes taken.  The shipped fail2ban filter is
checked with `fail2ban-regex` when it is installed.  When it is not, that
check says STOPPED and counts as failed, and a stand-in (Python's regular
expressions, with `<HOST>` expanded as fail2ban documents it) checks the
same filter.

Run: `luajit src/delivery/tests/140-test-failed-decryption.lua [project
folder]` (about 40 s; referee 3 serves a million frames, three times).
