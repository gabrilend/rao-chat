# Open questions from reading rmail as a rubric

Gathered from the four notes in this folder (2026-09-26), duplicates merged,
most blocking first.  Each names the phase 2 issues it holds and the note
that argues it.  An answered question moves to the planning document
(section 15) and to the issue it settles; this list keeps the question
with "answered" beside it.

**Status as of 2026-09-27** (after the phase 2 issues were rewritten for
the planning document's section 15): each question ends with
**Answered** (the owner's words, briefly) or **Held by** (the issue whose
Open questions section now carries it).  Issue numbers changed meaning in
places: 211 is the mailbox gatherer, 212 where a mailbox can be reached,
213 finding housemates, 214 signatures, 215/215a/215b git per mailbox,
301 the RAM inboxes as the viewer's interface.  New questions found while
writing those issues are listed at the end.

## Blocks all of phase 2

1. **The server's shape.**  (structure-and-defences, "A different
   formation")  A: one program, one wait loop over every mailbox port and
   outgoing connection (rmail's shape, its blocking fixed).  B: one small
   process per mailbox port.  C: a chain of small programs joined by
   folders in RAM — listener, a pool of key-trying workers, one writer to
   the rooms, a sender — each stage's backlog a folder anyone can list.
   D: A, with key-trying moved into the C crypto library on its own
   threads.  Reader's leaning: C, then B.  Also settles: one program or
   two (planning question 7, read as two).
   **Answered 2026-09-27**: "one mailbox per "server" ... they'll each
   report to the RAM directories as detailed in shape C. Many data
   gatherers, one viewer" — C's pipeline split per mailbox as in B (issue
   211).  Still to confirm: "two programs" (held by 211, question 11), and
   whether stages are coroutines or child processes (211, question 2).
2. **Receiving never waits on sending; who sends.**  (delivery-and-retries,
   rule 2, formation F2)  One receiving thread and a pool of sending jobs,
   one address per job, is the reader's leaning; ties to question 1, and to
   whether "the rmail single-threaded messaging core engine" was a
   requirement or a description of rmail (it was read as a description).
   **Answered in part by 1**: the sender is its own stage (211); one job
   per pair is 202's formation.  **Held by** 211 (question 2) for how the
   stages run.

## Blocks sealing, joining and delivery (201, 202, 205, 209)

3. **A frame that opens under two rooms' keys.**  (sealing-and-framing,
   rule R7)  Try every key and make two openings an error, or put a
   key-tying value at the start of every sealed body (which also lets
   trial opening stop at the first key)?
   **Answered 2026-09-27**: "add the token to the front of each message
   ... Inside the encrypted payload, and strip it out before displaying
   it."  Built as the token fingerprint (issue 201a; confirming the
   fingerprint over the raw token is 201a's question 2).
4. **How a server learns its outside port, per mailbox.**
   (addresses-and-ports, "A different formation")  F1 written in a column
   of the mailboxes file, an error when empty, proved by the first
   call-back; F2 the home sweeps its own public address (needs a router
   that lets inside devices reach the home's public address); F3 a member
   sweeps it for you; F4 ask the router, when automatic port opening is
   on.  Reader's leaning: F1 as the rule, F2 as a tool that fills it.
   **Answered 2026-09-27**: configured by the person, per mailbox, in the
   viewer or the mailbox's config file (F1; no sweep tool) — issue 212.
5. **The log is the outbox.**  (delivery-and-retries, formation F1)  Each
   address keeps a small record of what it has acknowledged; "not yet
   delivered" is worked out from the log; retrying (202) and filling a
   member's gaps (209) become one operation.  With it: an acknowledgement
   names the message ids it confirms (confirm).
   **Answered 2026-09-27**: "not just the outbox. We build on_receive hooks
   that create text files and store them in git history" — the log stays
   the delivery record (the owner's reading (b)); text copies go to git
   (215).  **Held by** 202 (question 10): confirm that an acknowledgement
   names its ids.
6. **A member with two addresses: send to both, or the first that
   answers?**  (delivery-and-retries, question 1)  The planning document
   (section 15) says every pair is a recipient; issue 202 says the one that
   answers moves to the front.  They contradict.
   **Answered 2026-09-27**: "the contact entry is the room, and the IPs are
   the contacts" — every pair is a recipient (202).
7. **What makes a slowed-down address worth trying again?**  (delivery,
   question 2; structure, question 9)  rmail resets on hearing from the
   contact; rao-chat cannot tell which member a frame came from.
   **Held by** 202 (question 1).
8. **Replays.**  (sealing R9; structure, "three risks")  Anyone who records
   a frame can deliver it again to every member.  Ids stop repeated
   messages; a replayed members list could re-add someone whose leave was
   confirmed.  Remember confirmed leaves, call back addresses learned from
   lists too, or both?
   **Held by** 207 (question 3) and 208 (question 1); both are proposed.

## Blocks the frame's contents (201)

9. **The record inside a frame**: the log's tab-separated record, or
   rmail's HTTP text with JSON?  **Held by** 201 (question 1; proposed:
   the log's shape).  *Answered 2026-11-05 by the builder: the log's shape
   (201, decision 1); the owner may overturn.*
10. **The size limit**, and padding inside the seal to a few fixed sizes
    (yes/no, which sizes).  **Held by** 201 (question 2).  *Answered
    2026-11-05 by the builder: 1 MiB; padded to powers of two from 256
    bytes (201, decisions 2 and 3); the owner may overturn.*
11. **How a token becomes bytes**: exactly as typed, or normalised (Unicode
    NFC, ends trimmed)?  Normalising changes the fingerprint of any token it
    alters.  **Held by** 201 (question 3).  *Answered 2026-11-05 by the
    builder: exactly as stored, a line break an error (201, decision 4);
    the owner may overturn.*
12. **Waiting for a frame's pieces**: rmail's 10 seconds per read, or one
    deadline for the whole frame?  **Held by** 211 (question 8; the
    listener stage).
13. **Counting frames per room key** and suggesting a token change past a
    number (a nonce budget, about 2^32 frames for a whole room).
    **Held by** 201 (question 4) and 209 (question 3).  *For 201, answered
    2026-11-05 by the builder: not counted yet (decision 5); 209's question
    stands.*

## Addresses and joining (204, 205, 207, 208)

14. **Private home-network addresses in member lists** (207): never shared,
    or shared marked with their network and dropped by receivers elsewhere?
    **Held by** 207 (question 2).
15. **Where the outside port lives**: a mailboxes column or config lines;
    both ports for IPv6 (which has no address translation)?
    **Answered in part 2026-09-27**: per mailbox, "in the viewer or the
    mailbox's config file".  **Held by** 212 (questions 1 and 2): which
    file, and both ports for IPv6.
16. **Automatic port opening**: must be written in config; one mapping per
    mailbox?  Keep rmail's start-up router probe (which makes a real test
    mapping), probe without mapping, or drop it?  **Held by** 212
    (question 3).
17. **Carrier address translation** (a 100.64/10 public address): refuse to
    start mailboxes, or run outbound-only and say so?  **Held by** 212
    (question 4).
18. **When a superseded address is retired**, or only slowed to the
    two-hour ceiling forever.  **Held by** 212 (question 5).
19. **Tor-only members** can never be called back: accept them as never
    confirmed, or plan for onion addresses?  **Held by** 204 (question 1).
20. **Keep rmail's public-address lookup** (three DNS operators, a change
    confirmed by a different one), its intervals as config; the
    "first three numbers match" same-network test, or the real network mask?
    **Answered in part 2026-09-27**: the recheck interval is a config
    setting (planning section 15, "Git per mailbox").  **Held by** 212
    (question 6) and 213 (question 1).
21. **Who receives the open-router warning.**  **Held by** 212 (question 7).
22. **Does a new or un-withheld member get the room's past messages?**
    **Held by** 202 (question 3) and 205 (question 1).

## The failed-decryption log (203)

23. **Refused-but-opened frames**: logged there, separately, or not at all;
    and RAM or disk.  (rmail's own line has no sender address, so fail2ban
    has nothing to match.)  **Held by** 203 (questions 1 and 2).

## Running the server (phases 3 and 6)

24. **Which port phones and browsers use**; a WebSocket starts with plain
    text, which a mailbox port should not answer.  **Held by** 301
    (question 1).
25. **Hand-editing entries or config while the server runs** (the change
    bell only hears its own program).  Sharper now: a gatherer works on a
    RAM copy, so a hand edit on disk is overwritten at the next sync.
    **Held by** 211 (question 3).
26. **A mailbox port that cannot be claimed at start-up**: stop the server,
    or only that mailbox?  **Held by** 211 (question 5).
27. **A connection limit**, and whether it counts as the flood defence 203
    rules out.  **Held by** 211 (question 6).
28. **Where server-level problems go**, since they belong to no room.
    **Held by** 211 (question 7) and 301 (question 4).
29. **No plain-text health check** on a mailbox port: then how does a person
    test a port forward?  **Held by** 201 (question 5) and 212
    (question 9).  *For 201, answered 2026-11-05 by the builder: nothing
    in the clear, a health check included; a sealed ping from the person's
    own viewer, to be built in 212 (decision 6).*
30. **Growing piles of undelivered messages**: shown to the person?  What
    number "strains the engine"?  **Held by** 202 (question 6).
31. **Force the log to disk before acknowledging?**  **Still open** (owner,
    2026-09-27: "Still open ... Until answered, built both ways,
    switched").  **Held by** 211 (question 1; the `gatherer.acknowledge-after`
    switch).
32. **Retry timers across a restart.**  **Held by** 202 (question 2).
33. **Writing a line into a room's log by hand**: a way to send?  (If not,
    no file watcher is needed.)  Read as no from "The user types, and it
    creates messages and puts them in the right place"; **to confirm**,
    held by 211 (question 4).
34. **The 30-second floor** once sends are immediate.  **Held by** 202
    (question 4).
35. **A forged acknowledgement** from another member: betrayal (outside the
    threat model), or checked?  **Held by** 202 (question 5) and 204
    (question 3).

## The phase 2 demo (210)

36. **Homes on one machine**: fixed ports in each home's config, or free
    ones from the system; a separate loopback address per home (127.0.0.2,
    .3, .4) so the call-back check and the ignore list show anything?
    **Held by** 210 (questions 1 and 2).

## New questions found while writing the issues (2026-09-27)

37. **A hosted upstream sees every message in plain text**, which breaks
    "not a hosted service": require a member-run upstream, seal the pushed
    copies, or allow with a warning?  **Held by** 215b (question 2).
38. **Child rooms in a shared mailbox repository** (recorded open by the
    owner's planning note): a repository per room, or push only rooms whose
    members all share the upstream?  A branch per room does not hide
    anything from someone who can fetch the repository.  Built both ways
    (`git.upstream-rooms`).  **Held by** 215b (question 1).
39. **Push the running log?**  It names every address the home talked to.
    **Held by** 215a (question 1) and 215b (question 3).
40. **The failed-decryption file in git**: never committed (proposed)?
    **Held by** 203 (question 3) and 215a (question 3).
41. **Custom hook scripts and their licence** (rmail's hook permission was
    not carried over).  **Held by** 215 (question 2).
42. **A hand edit to a text copy, then a correction arrives**: which wins?
    **Held by** 215 (question 3); after a pull, which version is shown:
    215b (question 5).
43. **Where the git repositories and the RAM root live** by default.
    **Held by** 215 (question 1) and 211 (question 9).
44. **Commit author and upstream credentials.**  **Held by** 215
    (question 4) and 215b (question 4).
45. **Signature edges**: 80 code points or bytes; an empty message;
    trailing punctuation; a closing paragraph "signed" by its last word.
    **Held by** 214 (questions 1–4).
46. **The key-tying value is the fingerprint, not the raw token** —
    confirm.  **Held by** 201a (question 2).
47. **A replayed leave after the leaver returned.**  **Held by** 208
    (question 1).
48. **Start-up hellos at scale.**  **Held by** 205 (question 2).
49. **The whole history in RAM for the viewer; how remote viewers mirror
    the folder.**  **Held by** 301 (questions 2 and 3).
50. **Hairpin call-backs** confirming a home-only pair.  **Held by** 204
    (question 2).

## Not rao-chat's to answer

Found in rmail by reading, never reported there: a resend draws a new
message id; an edit is marked sent while only planned; the partial-write
loop can skip bytes; phone and daemon may turn one token into different
keys (no Unicode normalising); the phone refuses frames over 16 MiB that
the daemon accepts; a state file stores the sealing key itself; the
failed-decryption line names no sender; `docs/protocol.md` still describes
the old shared sync timer.  Worth raising in rmail's own issues if the
owner wants.
