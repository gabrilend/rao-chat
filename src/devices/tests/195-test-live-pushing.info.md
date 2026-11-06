# 195-test-live-pushing.lua

Issue 306's referees: a message filed while a device is live reaches its
mirror within two seconds, and only what changed is pushed; a corrected
message is pushed; with two devices live, a message typed on one appears
in the other's mirror (broken: `only-writer`); a connection quiet past
`devices.idle-limit` is closed while one pinging is kept, and a live
device with `keep-alive` stays; the setting is required.  The test files
typed files as the gatherer's filer would; no gatherer runs.  Run under
the loopback-only wrapper (127.0.0.2, port 46306):
`luajit src/devices/tests/195-test-live-pushing.lua [project]`.
