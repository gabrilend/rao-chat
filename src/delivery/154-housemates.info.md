# 154-housemates.lua

Finding housemates on the home network (issue 213): homes behind the same
router, reached by their home-network addresses.
- `read_networks`: the machine's attached private networks with their
  real masks, from `/proc/net/route`.
- `on_own_network`: whether an address is on one of them (the real mask).
- `sweep_addresses`: every host of each own network, less this machine's
  address; a network wider than /24 is swept on the /24 around it.
- `body_pair`: the home-network pair inside a discover or here, never the
  packet's source.
- `new` makes a housemates table for a home and its sender stage. Its
  methods:
  - `needs_search`, `ports`, `search`, `start`, `moved`: a room is
    searched only when a member is at this home's public address, or a
    connection came from the home network. A sealed `discover` goes to the
    multicast group (`GROUP`, time-to-live 1) and the sweep.
  - `receive`: one datagram. A discover is answered with a `here`; either
    is called back (142), and kept only on yes.
  - `keep`: 142's `discover` action; in memory and `<ram>/housemates`.
  - `list`, `is_housemate` (145's seam), `route` (connect inside the
    house), `from_connection` (a relaying router is logged once and kept
    nowhere).
- `udp_send`, `udp_listen`: the real LuaSocket sockets, for 211's
  gatherer.

Load with `require("154-housemates")`.
