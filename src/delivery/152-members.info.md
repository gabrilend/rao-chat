# 152-members.lua

Contact syncing within a room (issue 207). A digest first, the list only
when digests differ, and nothing from a list trusted until the pair
itself answers.
- `shareable`: whether an address may go in a list (public IPv4, global
  IPv6, or a hostname). Private, carrier-grade, link-local and loopback
  addresses never leave the home.
- `read_vouched`, `vouch`: the room's `vouched` file, one line per pair
  with the claim it answered yes to. 142 writes it when a hello's
  call-back confirms a member.
- `held`: the room's members, flagged or not, plus this mailbox's own
  shareable pairs, sorted as "<address> <port>".
- `digest`: SHA-256 of the held pairs as sorted text lines, and the
  count. Any order gives the same digest.
- `list_record`: the `members` list this home sends. Each pair carries a
  claim id; members with no vouched claim are not listed.
- `receive_list`: calls back each new pair of a received list (142's
  `heard`). It skips pairs held, its own claims, ignored, private and
  left pairs (208's `may_add_from_list`). Nothing is added here.
- `answer`: what 133 answers a `members-digest`, `members-ask` or
  `members` frame with (its `on_members` seam).
- `attempt`: one try at a members job, run by 134's stage like a hello.

Load with `require("152-members")`.
