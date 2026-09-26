# 210 — Phase 2 demo: three homes talking

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 201, 202, 203, 204, 205, 207, 208, 209

## Current Behavior

Nothing exists.

## Intended Behavior

`issues/completed/demos/phase-2-demo`, found by `run-phase-demo 2`, runs
three or more home servers on one machine, each with its own `rao-home/`
under `tmp/shared-memory/`, and shows, with figures and real outputs:

- a message delivered to every member at once, with acknowledgement times;
- a member down, messages waiting, and delivery when it returns;
- joining a room with its token and one address, and a direct message
  between two homes, sealed and filed the same way;
- two rooms with the same label told apart by their tokens;
- a child room flagging an outsider of its parent, and the flag cleared by
  approving it;
- contact syncing reaching a newcomer; an ignored address refused;
- a token changed by hand and given out through direct messages, the room's
  history kept;
- a genuine leave and a forged one;
- a two-faced sender caught by the cross-check;
- the failed-decryption log after garbage is sent, with a fail2ban filter
  matching its lines;
- phase 1's tools reused: `people/`, the tree of child rooms, the tally.

It reads `input/` first and writes a goodbye into `output/` last.

## Suggested Implementation Steps

1. Starting several homes on different ports on one machine.
2. One scene per behaviour above.
3. The bash wrapper in `issues/completed/demos/`.

## Blockers that are not the owner's

- Needs 201–209.

## Related documents

- `run-phase-demo`; issue 106 (phase 1's demo, whose harness it reuses)
