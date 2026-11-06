# 193-test-catching-up.lua

Issue 304's referees: an empty mirror after `catch-up` equals the home's
folder; a device away is sent only the new message files (broken:
`from-start`); an edit is caught by the digest (broken: `no-digest`); a
file the home no longer holds is dropped and a late one fetched; a room
the home left leaves the mirror; a path outside 301's layout is refused
and said (broken: `no-path-check`); 183 reads the mirror as the home.
The home's folder is written as its gatherers write it, with none
running.  Run under the loopback-only wrapper (127.0.0.2 and .4, port
46304): `luajit src/devices/tests/193-test-catching-up.lua [project]`.
