# 191-test-pairing.lua

Issue 303's referees: `add` gives a device whose test is answered (broken:
`trailing-space`); `list` shows labels only and a second `add` of a label
is refused; the temporary file is mode 600 while it is written and the
result is mode 600 with nothing left behind (broken: `open-temporary`);
each failure of the device's test is told apart (broken: `one-message`);
`remove` unpairs with no server restart; the owner's own lines are kept.
Run under the loopback-only wrapper (127.0.0.2 and .3, port 46303):
`luajit src/devices/tests/191-test-pairing.lua [project]`.
