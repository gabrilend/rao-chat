# 145-hello.lua

The hello (issue 205): one record that joins a room, re-announces at
start-up and tells the room about a move.  It states every pair of the
mailbox, with its kind, under one claim id (141's `make_for`).
- `stated_pairs`: the pairs to state to one receiver.  They come from the
  stage's `own_pairs` seam (212's), less `home-network` pairs unless the
  receiver is a housemate (`is_housemate`, 213's).  No seam, or nothing to
  state, is an error: no port is ever guessed.
- `attempt`: one try at one hello job (134's stage).  The claim is made on
  the first try and the same record is resent on retries; it succeeds
  when the receiver's `ack` names the claim.
- `receive`: what 133 hands a decoded hello to.  It adds nothing for this
  home's own hello sent back, skips ignored pairs and members heard from
  within the retry ceiling, and hands every other pair to 142's `heard`
  (a call-back to the stated pair, then the add).  It never answers with
  a hello.
- `join`: makes a room from a token and one member's pair, adds that
  pair, and makes a hello to it due now.
