# 149-reach.lua

Where a mailbox can be reached (issue 212).
- `outside_port`, `set_outside_port`, `read_outside_ports`: the number the
  router forwards to each mailbox. It is kept in the home's
  `outside-ports` file as `<mailbox tag>.outside-port = N`. A mailbox
  without one is an error naming the line to write.
- `check_mailboxes`: every mailbox without an outside port, for the
  starter.
- `classify`: the exact address table. Private is 10/8, 172.16/12 and
  192.168/16. Carrier-grade is 100.64/10. Link-local is 169.254/16.
  Loopback, public and IPv6 are told apart too.
- `read_fact`, `write_fact`: the home's `public-address` file in its RAM
  root.
- `read_ipv6_global`, `read_private_ipv4`: the machine's own addresses,
  read from `/proc`.
- `own_pairs`, `seam`: the pairs a room's mailbox states in a hello.
  Public and hostname pairs carry the outside port. IPv6 and home-network
  pairs carry the listening port. `seam` is the `own_pairs` seam 134's
  stage takes.
- `state`: what the viewer shows. It names carrier-grade translation.
