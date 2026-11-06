# 198-test-browsers-way-in.lua

Issue 309's referees: the upgrade is answered with RFC 6455's example
accept value and nothing naming the server; another path, a plain GET, a
wrong version or key, no Upgrade, or an endless head gets not a byte
(broken: `answer-404`); a ping in a binary message gets a pong in one,
and frames of every length encoding come back whole; an unmasked
message, a text message, a fragment, or a message not exactly one frame
closes the connection; the reference device as a browser catches up and
is pushed to; the setting is required.  Run under the loopback-only
wrapper (127.0.0.2, port 46309):
`luajit src/devices/tests/198-test-browsers-way-in.lua [project]`.
