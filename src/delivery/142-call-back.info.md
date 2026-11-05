# 142-call-back.lua

Asks a stated pair "did you make claim C?", sealed with the room's key,
before a hello or a leave is trusted (issue 204, step 3).
- `heard`: takes a claim and the connection it came on, and makes a check
  in the sender stage, always at the stated pair and never the source.
- `ask`: one try. It waits up to `callback.answer-time` seconds and reads
  only a `did-you-answer` naming that claim.
- `run`: acts on the answer. On `yes`, a hello adds the pair and records
  it as heard at that moment (103's `heard_from`; 205) and clears any
  `left` line, and a leave goes through 147's `confirm`: removed, a
  `left` line written, its `delivered` line dropped (208). A confirmed
  hello that leaves the pair a member also keeps its claim in the room's
  `vouched` file (152's `vouch`; 207), so a members list can carry it. On `no`, the check ends. With no answer the check stays
  unconfirmed and is tried again on 202's timers.
- `answer_frame`: what 133 sends back for a `did-you`.
