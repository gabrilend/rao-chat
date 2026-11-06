# 196-test-choosing-an-address.lua

Issue 307's referees: with both addresses answering the home-network one
is used; with it unreachable, the public one; with it never answering (a
listener whose queue is full), it is given up after quick-wait; a wrong
token at the home-network address is said and the public one is not
tried (broken: `fall-through`); neither answering, both are said.  Run
under the loopback-only wrapper (the device port on every address, port
46307): `luajit src/devices/tests/196-test-choosing-an-address.lua [project]`.
