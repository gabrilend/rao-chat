# 203 — The failed-decryption log

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 201, 202
**Blocks:** 210

## Current Behavior

Nothing exists.

## Intended Behavior

Owner: "We should also ensure that we have logs that show unsuccessful
decryption attempts, by the way, to avoid DDOSing or whatever."  And on
flooding: "the isp will notice DDOS attacks and change your IP out from
under you. And from under them. Also, fail2ban is a thing".

- **One line per frame no held key opens**: the time and the address it
  came from, at a fixed path, in a shape fail2ban can read with a simple
  pattern.  fail2ban watches the file and blocks addresses that keep
  appearing.
- **rao-chat builds no flood defence of its own** beyond this log; blocking
  is left to the firewall and the internet provider.
- The log lives in `tmp/shared-memory/` (RAM), as the house rules ask for
  logs, at a path fail2ban can be pointed at.

## Suggested Implementation Steps

1. The line format, documented with a matching fail2ban filter example.
2. Writing it from 202's receiving path.
3. Tests: a garbage frame writes one line; a genuine frame writes none.

## Blockers that are not the owner's

- Needs 201's trial opening and 202's receiving.

## Open questions

1. **Frames that open but are refused** (an ignored address, or a child
   room's outsider): a flood of those is not a failed decryption.  Count
   them in this log too, in a separate log, or not at all?
2. **RAM or disk.**  A log in RAM is lost at reboot; fail2ban only needs
   recent lines.  Is that acceptable?

## Related documents

- `notes/vision-planning.md` section 14 ("The threat model, answered")
