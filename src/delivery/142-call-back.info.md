# 142-call-back.lua

Asks a stated pair "did you make claim C?", sealed with the room's key,
before a hello or a leave is trusted (issue 204, step 3).
- `heard`: takes a claim and the connection it came on, and makes a check
  in the sender stage, always at the stated pair and never the source.
- `ask`: one try. It waits up to `callback.answer-time` seconds and reads
  only a `did-you-answer` naming that claim.
- `run`: acts on the answer. On `yes`, a hello adds the pair and a leave
  removes it. On `no`, the check ends. With no answer the check stays
  unconfirmed and is tried again on 202's timers.
- `answer_frame`: what 133 sends back for a `did-you`.
