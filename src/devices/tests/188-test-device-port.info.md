# 188-test-device-port.lua

Issue 302's referees: a paired device's ping answered under its own token
(broken: `wrong-key`); a frame no device opens, and clear text, answered
with not a byte (broken: `answer-unknown`); a connection keeps its device
(broken: `any-key`); a stuck connection holds up nobody; missing
settings, a devices file others may read, an entry without `own = true`,
and a device port equal to a mailbox's port each stop the server before
the port opens.  Run under the loopback-only wrapper (127.0.0.2, port
46302): `luajit src/devices/tests/188-test-device-port.lua [project]`;
set RAO_TEST_ROOT to keep its folders somewhere of your own.
