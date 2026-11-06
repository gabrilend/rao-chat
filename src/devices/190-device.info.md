# 190-device.lua

The reference device (issue 303), as 183 is the reference viewer:
`luajit src/devices/190-device.lua <device folder> test [--public] | catch-up | send | live [--for <seconds>] | check-in --for <seconds>`.
Reads `<device folder>/config` (port, home-network, public, token, wait,
quick-wait),
sends a sealed ping and says exactly what happened: answered in N ms;
nothing listens (refused); cannot be reached; closed without a word (the
token is not one the home knows); said nothing within the wait; or an
answer that is not this ping's pong.  `catch-up` (304) keeps a mirror of the
home's folder in 301's layout under `<device folder>/mirror`: one
exchange of positions and digests per room, every path checked by 192
before it is written.  `send` (305) sends each file 183 wrote into the mirror's
`typed/`, removing it on `typed-ok` and keeping it with a `.refused`
reason otherwise.  `live` (306) stays connected after a catch-up: pushed files go into
the mirror, typed files are sent as they appear, and a `ping` goes when
it has sent nothing for its `keep-alive` seconds.  `catch-up`, `send` and `live` reach the home by its home-network
address first (quick-wait), then its public one (wait), and stop, said,
at an address that connects but does not answer the ping (307).  `M.deck` and `check-in` (308): the locked screen's waits, a base
(`check-in` setting) plus a card from a shuffled deck of −5 … +5 dealt
without replacement, each followed by one catch-up.
