# 203 — The failed-decryption log

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 201, 211
**Blocks:** 210

## Current Behavior

Nothing exists.  rmail writes one line, `decryption failed: no matching
contact key`, with the time and **without the source address**, so
fail2ban has nothing to match (sealing note, C10; structure note, R17).

## Intended Behavior

Owner: "We should also ensure that we have logs that show unsuccessful
decryption attempts, by the way, to avoid DDOSing or whatever."  And on
flooding: "the isp will notice DDOS attacks and change your IP out from
under you. And from under them. Also, fail2ban is a thing".

- **One line per frame no held key opens**, written by the opener stage
  (211) into the mailbox's `failed-decryption` file in its RAM folder:
  the time (whole seconds since 1970, and the same instant as an ISO-8601
  UTC stamp for people), the source address (text), the source port
  (integer), the mailbox's listening port (integer), and the frame's
  announced length (integer).  A frame refused for its length alone (201's
  cap) writes the same line with the reason `length`.
- **A fixed, documented line grammar** with a fail2ban filter file shipped
  beside it (`docs/` holds the filter and a `jail` example pointed at a
  glob of every mailbox's file under the home's RAM root).
- **rao-chat builds no flood defence of its own** beyond this log;
  blocking is left to the firewall and the internet provider.
- **Split by size**, by the same rule as the running log (215a): a new
  numbered file starts before a write would carry the current one past
  config `failed-decryption.file-size` (bytes, no default), and only the
  newest few files are kept in RAM (config `failed-decryption.files-kept`,
  no default) — fail2ban needs only recent lines.

## Rubric

- **A failed-opening record carries the source address** (structure note
  R17): a line with no address feeds neither fail2ban nor a person.
- **Anything that can repeat writes a bounded amount** (structure R16): a
  flood writes one line per frame, so the file must be bounded by size, not
  trusted to stay small.  rmail's week of identical "unreachable" lines hid
  every real event (its issue 371).
- **A failed opening costs work proportional to keys × size** (sealing
  R12): the line is written after the whole keyring was tried, once, not
  once per key.
- **One home per service** (structure R20): each home's RAM root is its
  own, so three homes on one machine never write one file.
- **Nothing identifying the room is written** (sealing R11): the line
  names the port (already visible on the wire), never a room.

## Where we differ

rmail writes one anonymous line into its general log.  The formation here
is **the line grammar as a contract with another program**: the file is
written for fail2ban first and people second, its grammar is versioned in
one place (`docs/`), and the referee runs fail2ban's own matcher
(`fail2ban-regex`) against real lines rather than a hand-written pattern
in the test.  The size rule is shared with 215a, not re-invented.

- **Gains:** the thing fail2ban reads is checked by fail2ban; one size-split
  rule for every growing file in the gatherer.
- **Costs:** a dependency of the test on fail2ban being installed (the
  referee says so and stops, rather than skipping); a grammar change is a
  filter change on every home.

## Referees

1. **Garbage writes one line with the address.**  A garbage frame from
   127.0.0.3 port 5555 to mailbox port P writes exactly one line;
   `fail2ban-regex` with the shipped filter matches it and extracts
   127.0.0.3.  *Broken:* rmail's line without the address; one line per
   key tried.
2. **A genuine frame writes nothing.**  *Broken:* logging every opening
   attempt.
3. **Bounded.**  A flood of 1,000,000 garbage frames (short ones, a fake
   clock) leaves at most `files-kept` files, none larger than
   `file-size`.  *Broken:* one file growing forever; a split after
   passing the size.
4. **Length refusals are counted.**  A header announcing more than the cap
   writes one line with reason `length`, having read only 4 bytes.

## Suggested Implementation Steps

1. The line grammar and the fail2ban filter, in `docs/`.
2. Writing it from the opener stage (211) after the whole keyring fails,
   and from the listener for a length refusal.
3. The size split (shared with 215a) and the settings declared.
4. The referees above.

## Blockers that are not the owner's

- Needs 201's trial opening and 211's opener stage.

## Open questions

1. **Frames that open but are refused** (an ignored address at `hide`):
   a flood of those is not a failed decryption.  Count them in this log,
   in a separate one, or not at all?  (Rubric question 23.)
2. **RAM or disk.**  In RAM, lost at reboot; fail2ban needs only recent
   lines.  Acceptable?  (Rubric question 23.)
3. **Committed to git or not?**  The running log is committed every sync
   cycle (215a).  This file is a list of addresses that attacked the home;
   proposed: never committed or pushed, since a shared upstream (215b)
   would publish it.

## Related documents

- `notes/vision-planning.md` section 14 ("The threat model, answered")
- `notes/rmail-rubric/sealing-and-framing.md` (C10, R12)
- `notes/rmail-rubric/structure-and-defences.md` (R16, R17, R20)
