# 215b — Sharing through a shared upstream: pull and push at start-up, shut-down and each address recheck

**Phase:** 2 — Server-to-server delivery
**Parent issue:** 215
**Blocked by:** 212, 215
**Blocks:** 210

## Current Behavior

Nothing exists.  215 keeps each mailbox's repository local; 212's home
starter rechecks the public address on a randomised clock.

## Intended Behavior

The owner (2026-09-27): edits to the git copy reach others "only if they
share an upstream. Ideally, git push when the server starts up and shuts
down, and maybe whenever it does random IP checks - it's like once every
36 hours or so".  On pulling: "yeah probs".  On the code: "it should be
freely downloadable for anyone sharing the same upstream."

- **An upstream is optional, per mailbox**: config names a remote for a
  mailbox, or none.  With none, nothing is pulled or pushed and nothing
  says it is missing.
- **Three moments**, each a pull then a push: when the gatherer starts,
  when it shuts down (after its final sync), and each time 212's home
  starter rechecks the public address (it tells every gatherer).
- **Pull**: fetch everything; merge the rooms' branch.  Members' copies of
  one message are the same bytes (215's agreed part), so the same message
  from two homes merges cleanly; two members' different hand edits of one
  copy are a merge conflict, which is left unmerged, reported to the
  person in `state` and the running log, and retried at the next moment —
  never resolved by picking a side.
- **Push**: the rooms' branch and `code/<home name>`; the running log's
  branch only if config says so (215a's open question 1).
- **Pulled code is never run or switched to.**  Other people's
  `code/<name>` branches arrive with a pull and sit there, readable and
  downloadable; running someone else's code is a choice the person makes
  by hand (owner's decision, recorded 2026-09-27).  This is how the home
  offers its running source to the people it talks with (the AGPL asks
  that network users can get the source).
- **A failed pull or push** (no network, refused, conflict) is reported and
  retried at the next moment; it never blocks delivery.
- **Which rooms are shared** — config `git.upstream-rooms` (no default),
  built both ways while open question 1 is open:
  - `repository-per-room`: each room's text copies are also kept as a
    repository of their own with their own upstream, so what a member can
    fetch follows which rooms they are in;
  - `only-fully-shared`: the mailbox repository is pushed, but a room's
    folder is included only when every pair on its member list is listed in
    config as sharing that upstream.

## Rubric

- **A read-access boundary in git hosting is the repository, not the
  branch**: anyone who can fetch a repository can fetch all its branches.
  So "a branch per room" would not keep a child room's copies from a
  top-room member who can fetch the mailbox's upstream; only a separate
  repository (or a room left out of the pushed tree) does.  This decides
  what the switch above can offer.
- **A shutdown the program cannot see cannot trigger work**: rmail's notes
  record that its daemon cannot catch its own shutdown, so cleanup happens
  at the next start (addresses note, 1g).  The shut-down push needs a
  handler for the stop signal (or the service's stop step, phase 6); a
  crash still skips it, so the start-up pull-and-push is the one that
  always happens.
- **Every periodic task is on the wake-up clock** (structure R8) — the
  recheck moment is already on 212's.
- **One failing destination must not delay anything else** (structure
  R4): a hung push is on its own worker with a deadline.
- **Nothing about a room travels in the clear** (planning section 5;
  sealing R11), and **"not a hosted service: nobody's messages pass through
  a server that none of the people in the room runs"** (planning section 1)
  — a hosted upstream breaks both, since text copies are plain text (open
  question 2).

## Where we differ

rmail has nothing of this: its mailboxes coordinate only by sealed
messages.  The formation here is **git's own merge as the coordination
layer for edits, and the network protocol left untouched by them**: the
edit channel (git) and the delivery channel (sealed frames) never mix.

- **Gains:** people who share an upstream get shared editing, review and
  history for free; nobody who does not is affected; the running code is
  offered to exactly the people who share.
- **Costs:** plaintext copies leave the home (the privacy question below);
  merge conflicts reach people; credentials for the remote live on the
  home machine.

## Referees

1. **The three moments.**  With a local bare repository as upstream: start
   a gatherer (one push), trigger a recheck (one pull, one push), stop it
   (one pull, one push).  *Broken:* push only at start-up.
2. **Same message merges clean.**  Two homes in one room share an upstream;
   both file one message; both push and pull: no conflict, one file.
3. **A conflict is reported, not resolved.**  Both edit one copy
   differently: the second pull reports a conflict and leaves both edits in
   history.  *Broken:* auto-resolving to one side.
4. **Pulled code is inert.**  Another home pushes a `code/<name>` branch
   whose program writes a marker file: after pulls, the marker never
   appears and the checked-out branch never changes.
5. **Child rooms stay private**, under each switch value: a member of the
   top room only, fetching the upstream, cannot find a child room's copies.
   *Broken:* one branch per room in one repository.
6. **No network, no stall.**  A black-holed remote: delivery continues;
   the push is reported failed within its deadline.

## Suggested Implementation Steps

1. The per-mailbox remote setting and the three moments (start-up,
   shut-down handler, recheck notice from 212).
2. Pull, merge, report conflicts; push the chosen branches.
3. `git.upstream-rooms` both ways, with its options entry for the tally.
4. The referees above.

## Blockers that are not the owner's

- Needs 212 (the recheck moment) and 215 (the repository).

## Open questions

1. **Child rooms in a shared mailbox repository** (recorded open in the
   planning document, 2026-09-27): a child room's members are a subset of
   its parent's, so one repository per mailbox shared upstream lets every
   top-room member download the text copies of child rooms they are not
   in.  A repository per room, or push only rooms whose members all share
   the upstream (built both ways above)?  A branch per room does not help
   (rubric above).
2. **A hosted upstream sees every message in plain text.**  Require that
   the upstream is run by a member (a bare repository on someone's home
   over ssh); seal the pushed copies with the room key; or allow any host
   with a warning in the viewer?
3. **Pushing the running log** (215a's question 1).
4. **Credentials**: an ssh key per home, per mailbox, or the person's own?
5. **Pulling others' hand edits into one's own copy**: after a pull, the
   copy may differ from what one's own log says the message is.  Show the
   pulled version, the logged version, or both?
6. *(answered 2026-09-27)* **Pull at the same moments as push.**  Owner:
   "yeah probs".
7. *(answered 2026-09-27)* **The running source code is in the repository
   and downloadable by anyone sharing the upstream; pulled code never runs
   automatically.**

## Decisions (2026-11-05)

Made by the builder; the owner can overturn each.  Built in
`src/git-copies/` (179 the sharing module, 180 the referees), with the
three settings declared in 174 and their options entries in 176, the
moments called from 211's gatherer (163) and the recheck notice from its
starter (164).  180 passes 7 of 7 checks (referees 1–6 and a SIGTERM
check), with real gatherers on loopback whose only upstreams are bare
repositories in the test folder, each referee catching its broken
version.

1. **Where the upstream is named.**  The issue says "config names a
   remote for a mailbox".  Built instead as the mailbox repository's own
   git remotes, which the person adds with `git remote add`: `upstream`
   for the mailbox, `room-<token fingerprint>` for one room's own
   upstream.  So the address and its credentials stay in git's (and
   ssh's) own place, a person can use every git tool on them, and
   rao-chat's config holds no secret.  A repository with no such remote
   shares nothing and says nothing (as the issue asks).
2. **Child rooms** (open question 1, the owner's): both built, as asked.
   `only-fully-shared` is built the other way round from the issue's
   wording.  The issue says a room is pushed "when every pair on its
   member list is listed as sharing"; that pushes a child room whose
   members all share, while a top-room member outside the child who also
   fetches the upstream reads it (referee 5's broken version
   `members-listed`).  Built: a room is pushed when every pair listed as
   sharing the upstream is on the room's member list, so nobody who can
   fetch is outside the room.  The pairs are listed in the repository's
   git config, `rao.upstream-pair = <address> <port>`, one line each;
   with none listed, only the person reads the upstream and every room
   goes there (each room's member list holds the person's own pair).
3. **The read boundary is the remote.**  `repository-per-room` sends each
   room's folder only to its own remote; `upstream`, if there is one,
   still gets the code and (when asked) the running log.  What is pushed
   is a commit on the remote's own tip whose tree is the remote's with
   only the shared folders replaced, so no commit of a room left out is
   reachable from it.  Once pushed, it is merged here with `-s ours`, so
   the next pull starts from it rather than meeting the home's own copies
   as a conflict.
4. **The running log** (open question 3): pushed only when
   `git.push-running-log = yes`, and only to `upstream`, never to a
   room's own remote (the log is the mailbox's, not one room's).
5. **A hosted upstream** (open question 2): any git address is allowed;
   the plain-text copies are noted here and in 174's comment.  Sealing the
   copies with the room key would make them unreadable to git's merge,
   which is the point of 215b; requiring a member-run host is not
   something the program can check.  The warning in the viewer is 301's.
   This stays an owner's question: planning section 1 ("not a hosted
   service") argues for a member-run upstream.
6. **Credentials** (open question 4): the person's own, wherever git or
   ssh finds them for that remote.  rao-chat neither makes nor stores a
   key; the tests' upstreams need none.
7. **Pulled edits** (open question 5): the working tree shows the merged
   version; the log stays as it was (215's rule that hand edits are never
   sent), so the logged version is always one `git log` away.
8. **A conflict blocks only that remote's rooms push**: the merge is
   aborted, the paths go to `state.share.conflicts` and the running log as
   a `share-conflict-…` problem, the code and log are still pushed, and
   the next moment tries again.  It is never resolved by picking a side.
9. **The three moments**: start-up (the share thread's first run),
   each `recheck` file the starter leaves in every gatherer's RAM folder
   after a public-address check (a file, as with `stop`: 211's
   gatherers and starter talk only through folders), and the stop, after
   the last sync.  SIGTERM is blocked at start and polled each second by
   the state thread, so a service manager's stop runs the same last sync
   and shut-down moment; a crash still skips it, and the start-up moment
   catches up.  A mailbox with no upstream does nothing at these moments
   (no extra sync at start-up: 211's referee 3, 500 connections arriving
   at once, timed out when one ran).
10. **The deadline**: `git.share-deadline` (seconds, options value 60).
    Fetch and push run as background processes killed when it passes,
    while the gatherer's other threads go on (structure R4); a moment
    already running makes a new request wait for the next.
11. **Pulled code**: fetched as remote-tracking refs
    (`refs/remotes/<remote>/code/<name>`); only `rooms` is ever merged,
    nothing is checked out or run (open question 7, the owner's).

## Related documents

- `notes/vision-planning.md` section 15 ("Git per mailbox, signatures
  settled, sharing edits", and its last bullets)
- `LICENSE` (the AGPL's network clause)
