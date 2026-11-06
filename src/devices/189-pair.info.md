# 189-pair.lua

Pairing on the home machine (issue 303):
`luajit src/devices/189-pair.lua <project> <disk home> add <label> | list | remove <label>`.
`add` makes a six-word token, adds `<label>.token` and `<label>.own = true`
to the home's `devices` file, and prints the lines the device's `config`
takes (port, home-network, public, token).  The file is rewritten whole
under a temporary name made private before it is written, then renamed;
the owner's other lines are kept.  `list` never shows a token.
