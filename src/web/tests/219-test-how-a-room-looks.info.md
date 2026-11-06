# 219-test-how-a-room-looks.lua

Issue 405's referees: the page's tree is 183's `tree` on the same folder,
in either order of the mirror's paths (broken: `tag-order`); a name only
where the speaker (address and signature) changes, the person's own on
the other side (broken: `name-every-line`); pile and flagged notices
after the last message; an anchor per message, from its id; edited,
deleted and ignored-mark shown as such, the last two without a body
(broken: `show-ignored`); markup stays text; and 207 drawing it all on
the stand-in's paper document, with unread marks.  No server; run under
the loopback-only wrapper all the same:
`luajit src/web/tests/219-test-how-a-room-looks.lua [project]`.
