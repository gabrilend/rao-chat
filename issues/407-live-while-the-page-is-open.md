# 407 — Live while the page is open

**Phase:** 4 — The web client
**Blocked by:** 406
**Blocks:** 408, 409

## Current Behavior

The page catches up and writes (404, 406), but between catch-ups it
hears nothing, and a dropped connection stays dropped.

## Intended Behavior

Planning section 6: the web client is "live the whole time the page is
open"; section 8: an "error strip across the top, as in rmail, with
'(retrying in Nm)'".

- **After `caught-up` the connection stays open** (306): each `file` the
  home pushes goes into the mirror (192's path check) and the room on
  screen is drawn again; the tree's unread marks move.
- **Keeping it**: a `ping` when the page has sent nothing for
  `keep-alive` seconds (306 decision 4), so the home's idle limit never
  closes a page that is only listening.  A hidden tab stays live
  (section 6 asks for the page to be live the whole time it is open).
- **When the connection drops**, the error strip says so and when the
  next try is: "connection lost (retrying in 5s)", the wait doubling from
  5 seconds to at most 5 minutes, back to 5 after a connection that
  catches up; "retry now" tries at once, and so does the browser saying
  it is online again.  Each try chooses an address as 403 does and
  catches up from the mirror the page holds (404), so only what is new
  comes, and waiting typed files are sent again (406).
- **The error strip also carries the home's own problems**: each
  mailbox's `state` `problem.<name>` lines (301 decision 7), named by
  mailbox, as 183's `problems` prints them.
- **Several devices at once** needs nothing new in the page: a phone
  and the page both live hear each other's messages (306).

## Status

Built 2026-11-06: `src/web/223-live.js` (`rao.live`: the waits, the
countdown, the home's problem lines, the session that reaches, catches
up, sends, listens, pings and retries); the page's Connect starts a
session, "retry now" and the browser's `online` try at once, and the
strip's countdown moves each second (207); the stand-in's `live` and
`waits`.  Referees 1 to 6 pass, 2 and 3 catching their broken versions
(`src/web/tests/224-test-live-in-the-page.lua`).  Referee 3 also stops
the home a second time after the page came back, and sees the wait start
again at 5 seconds.

## Referees

1. **Pushed at once.**  A message filed on the home while the stand-in is
   live reaches its mirror within two seconds, without another catch-up.
2. **Kept alive.**  Live for three times the idle limit with its pings,
   the stand-in is still connected.  *Broken:* no pings
   (`no-keep-alive`), and the home closes it.
3. **Back after a drop.**  The device server stopped and started again:
   the stand-in reconnects by itself and receives a message filed while
   it was away.  *Broken:* no retry (`no-retry`).
4. **The waits double to the cap**: 5, 10, 20 … 300, 300; back to 5 after
   a catch-up.
5. **The home's problems are shown**: a `problem.` line in a mailbox's
   `state` appears in the error strip's lines, naming its mailbox.
6. **The page and a phone together**: a message the reference device
   sends reaches the live stand-in's mirror.

## Suggested Implementation Steps

1. `rao.live`: the live loop's parts (taking pushes, keep-alive, the
   retry schedule, the error strip's lines).
2. The page's error strip, its "retry now", and the `online` event.
3. The stand-in's `live`, and the referees.

## Blockers that are not the owner's

- Needs 406, and 306's home side (built).

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **Retries start at 5 seconds and double to 5 minutes.**  rmail's back
   off (30 seconds up to 2 hours) is for another person's server; this is
   the person's own home, with them watching the page, so it is tried
   sooner and never left for hours.  Never given up while the page is
   open.
2. **The countdown is shown in seconds** ("retrying in 40s") under a
   minute and in minutes above ("retrying in 4m"), as rmail's "(retrying
   in Nm)".
3. **A hidden tab is not treated as a locked phone**: section 6's
   check-in deck is the phone's battery rule, and a computer's browser
   keeps its WebSocket open in a hidden tab.

### While building, 2026-11-06

4. **The page's live connection has one reader** (the session's), which
   takes pushed files, the outbox's answers and pongs; a typed file is
   sent as soon as it is added, without waiting for the last one's
   answer.  A record not due ends the connection, said, and is retried
   like any drop.  (406's one-at-a-time sending stays for the stand-in's
   `write`.)
5. **A connection the home closes is said as "<address> closed the
   connection"**, not with 403's words about the token: a close after a
   catch-up is a drop, not a refusal.
6. **The strip lists the drop first, then the home's problem lines**, so
   what the person can act on ("retry now") is at the top.
7. **Referee 6 plays the gatherer's filer** (no gatherer runs in the
   referees' home): it files what reaches typed/ as 306's referees do;
   the demo (409) runs real gatherers.

## Related documents

- issues 306, 307, 301 (decision 7)
- `notes/vision-planning.md` sections 6, 8 ("Error strip")
