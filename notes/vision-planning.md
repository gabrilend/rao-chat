# rao-chat — planning document

A vision document.  Written 2026-09-23 from the owner's requests, from a
reading of the rmail project (`/home/ritz/programs/r-mail`) that rao-chat
borrows its look and its networking from, and from the conversation pages
of `/home/ritz/games/tq/ai-stuff/double-diaper-dungeon` (its
transcript-to-HTML tool), which the room view borrows its layout from.
Everything under "Open questions" is undecided; everything else is a
proposal the owner can overrule, except where it quotes the owner.

## The owner's words

The request:

> Can we write a planning document for an android app (and once complete,
> a patch to rmail so you can access both from the same client if you tap
> a button, a'la facebook messenger) that acts as a messaging client? It
> should have rooms, but no group messages. Every conversation is a room of
> two. It should follow the UI design of the rmail android app. Also, we
> should build a web client at the same time, so users can connect from
> their computers and talk to each other. Both of them should have similar
> connection management and networking utilities as the rmail app does.

Then, on the first draft:

> minimum two, not exactly two. And anyone can remove someone from a group,
> it just starts a new conversation for them. Think about how rmail
> addressing works - we just keep local copies of receivers of our
> messages. Nobody can control if someone else is listening to someone
> else, but we can control if they're listening to us. And new people can
> be added as easily as adding recipients.

On rooms:

> yes and they can be nested, stored in a directory tree style reference.
> Each descended folder can have different recipients, and if there's ever
> any gaps (say, for /home/ritz/programming/, maybe /home/ has everyone in
> my household, /home/ritz/ has just me, and /home/ritz/programming/ has
> anyone that I'm programming with. That's not structurally defined, that's
> just a description of who I added to each directory's recipient list.
> That means my girlfriend can access /home/ but not /home/ritz/, and some
> guy I'm doing programming with can't access /home/ or /ritz/ but he can
> access programming. If I'm writing code with my girlfriend, she sees
> /home/ and /home/ritz/programming/ as two separate trees, and to her it's
> just /home/ and /programming/ because she has no idea they're even
> connected. If however I started sharing /home/ritz/ with her then she'd
> see their connection and the full tree structure would resolve for her.
> Messages are bi-directional, we keep track of unix timestamps and order
> them accordingly and potentially dynamically if we have to. So I can be
> chatting in /home/ritz/programming/ and my friendly programmers who are
> watching will see. They can absolutely have multiple directories named
> "programming" it's just a name that we sort ourselves, it doesn't
> necessarily refer directly to the filesystem. Instead, we have symlinks
> in each person's contacts directory which point to each of the top-level
> directories they're a part of (from our perspective). These can be stored
> on disk behind the scenes as we please, and we need to do that because we
> need to be able to share filesystems by name, which can no longer imply
> structural relations. However we keep the actual file-path of the file on
> our disk right next to the file, easily accessible as easily as accessing
> the name.

On the phone's connection:

> live connection, unless the phone is slept. If the app is in the
> background but the phone is open, then it remains live, but the moment
> the screen is locked, it goes to 30 second intervals, +/- 10 seconds of 1
> second intervals, drawn from a deck with replacement, meaning after 10
> cycles it'll be the same total duration as if it was always 30 seconds.

On the look: "see an example UI design at
/home/ritz/games/tq/ai-stuff/double-diaper-dungeon/ and it's
transcript-to-html tool."

Licence: "rao-chat's license is AGPL".

---

## 1. What rao-chat is

Private chat between people who each run a small server at home.  There is
no central server: a message goes from the writer's home server straight to
each reader's, the way rmail mail does.

**A room is a contact.**  An rmail contact is a name, a shared token, and
the addresses of one person's machines.  A rao-chat room is the same thing
with the addresses of everyone in it: a label, a token its members share,
and every member's (address, port) pairs.  A message written in the room
goes to every pair.  A **direct message** is a room with one other person
in it — exactly an rmail contact.  Direct messages and group rooms are
listed apart, but are built the same way, by the same code.

- **The token is the invitation.**  Holding a room's token is being
  invited; the token makes the key every message in the room is sealed
  with.  Tokens are plain text, anything the maker likes; rao-chat
  suggests readable ones ("maple-orbit-velvet-tin") so they can be read
  aloud.  A room whose token is deliberately guessable is a public square.
- **Labels belong to the reader.**  Two rooms you call `coffee-shop` are
  simply two rooms, with different tokens.  Rename freely.
- **Rooms form a tree**, shown like a file explorer: folders that open and
  collapse.  A room made as a **child** of another carries its parent in
  its invitation; someone in it who is not in the rooms above is flagged
  for your review (nothing is enforced) — tiers
  of trust.  Owner: "The farther down in the directory structure you go,
  the more people you'll need to have invited you ... it encourages task
  focus to specialize, rather than power to hierarchicalize".  Anyone in a
  room may start a child room.
- **Mailboxes.**  Each top-level room and everything under it is one
  mailbox with its own listening port; all direct messages share one more.
  A message arriving on a port is tried only against that mailbox's keys.

Each person reaches their home server from:

- the **Android app**, which looks and behaves like the rmail app;
- the **web client**, a page served by their own home server, for talking
  from a computer.

Both show the same rooms and history, because both live on the home server.

Later, once rao-chat works, rmail's Android app gains a button that jumps to
rao-chat and back, the way Facebook's app and Messenger link to each other.

### What it is not

- **Not a hosted service.**  Nobody's messages pass through a server that
  none of the people in the room runs.
- **Not an identity system.**  Nobody can know for certain who wrote a
  message.  A message carries whatever signature its writer typed, or none
  (section 3).
- **Not a defence against betrayal.**  rao-chat protects a room from
  strangers.  Someone a member let in holds what any member holds, and what
  they do with it is a human matter (section 14, "The threat model").
- **Not a mail client.**  rmail stays the place for long, file-shaped
  messages and attachments.

---

## 2. Words used in this document

| word | meaning |
|---|---|
| **home server** | the program each person runs on a computer at home (in rmail, "the daemon").  It holds their rooms, talks to other home servers, and serves their clients. |
| **room** | a conversation: a label, a token, and the (address, port) pairs of its members.  A group room has many members; a direct message has one other. |
| **token** | a room's shared secret, plain text, chosen by whoever makes the room (readable words suggested).  It makes the key the room's messages are sealed with; holding it is being invited. |
| **label** | your own name for a room.  Never sent; rename freely. |
| **address** | where a home server can be reached: an IP address or hostname **and its own port**, always as a pair.  There is no default port.  Addresses answer "where do I send"; they never prove who wrote something. |
| **member** | an address in a room's list.  Members are added freely: whoever holds the token and says hello is added, and members share their lists. |
| **child room** | a room made inside another, whose invitation names its parent.  Your server only accepts a member into a child room if it is a member of the parent. |
| **withheld** | a member you have chosen not to send to in a room.  Everyone else keeps their own choices. |
| **ignore list** | addresses whose messages you do not want: hidden entirely, or marked ("someone you ignore spoke").  Yours alone; holds until that address changes. |
| **mailbox** | a group of rooms with its own listening port: one per top-level room (its child rooms go in it), and one for all direct messages.  A message arriving on a mailbox's port is tried only against that mailbox's keys.  Two mailboxes may share a port (not recommended; the server says so). |
| **flagged** | a member of a child room who is not a member of every room above it, as your server sees it, or whose rooms above your server does not hold.  Shown highlighted; sent nothing until you approve.  Private to your server. |
| **signature** | the last line of a message, typed by its writer in a persistent "signature" field, or nothing.  Signing as someone else is taboo, not prevented. |
| **device** | one of your own clients (a phone, a browser) paired with your home server, as in rmail (`own = true`). |
| **message** | one entry in a room: its id, the address it arrived from, when it was written and arrived, and its text (signature included). |
| **delivery** | a message moving from the writer's home server to a reader's. |
| **live connection** | a connection a client holds open to its home server, so new messages arrive the moment they land. |

---

## 3. Rooms and who hears what

- **Joining.**  Someone gives you a room's token and one member's address
  (and, for a child room, you must already be in its parent).  Your server
  says hello to that address, sealed with the token; holding the token is
  the proof, so you are added.  Members then share their lists with you,
  and yours with them.
- **You choose who hears you.**  Every member of a room hears your messages
  unless you withhold them.  Withholding someone is all removal is.
- **You cannot choose who hears anyone else.**  Each person makes their own
  choices.  To shut someone out entirely, change the token: by hand, for
  now, and give the new one to everyone else through their direct
  messages.  The room keeps its history, label and members, minus the
  person left out.
- **Ignoring** is separate from withholding.  Two levels: hide an address's
  messages entirely, or hide them but show that they spoke.  The ignore
  list also refuses that address when other members' lists bring it back.
- **Leaving** is a message: "I'm not in this room anymore."  A leave notice
  is confirmed by asking that address before it is removed, so no one can
  send it for someone else.  Speaking again brings you back.  Addresses are
  added freely: a move adds the new address beside the old.
- **Child rooms.**  Anyone in a room may make a child room and invite
  people to it.  Nothing is enforced: a member of a child room who is not
  a member of every room above it, as your server sees it, is **flagged**
  — shown highlighted, sent nothing until you approve.  Flags are private
  to your server.  Someone who leaves a parent is flagged in its children;
  nothing removes them.
- **Signatures.**  The sender of a message is unknowable by design: an
  address can change or pass through Tor.  The signature is what a message
  says about itself.
- **Edits.**  Anything may be edited.  An edit is its own message naming the
  one it changes; your server keeps the original beside it, so your own
  copy is the record.
- **Order.**  Messages carry the time they were written (whole seconds
  since 1970).  A room shows them in that order; a late message is placed
  where it belongs.  Ties are broken by message id, so every reader sees
  the same order.
- **Checking each other.**  Members periodically compare what they have
  received.  A missing message is normal; the same message id with
  different contents is an error, raised to the person.

---

## 4. Rooms on disk

Every room — group or direct message — is a folder named by a random tag
of your own, never sent.  Inside, its **entry** is written in rmail's
contacts format, so one reader serves rooms, direct messages, and rmail's
own contacts.  The folder's own path is kept beside the label.  Owner: "we
keep the actual file-path of the file on our disk right next to the file,
easily accessible as easily as accessing the name."

```
rao-home/
  config                      settings (rmail's config format)
  mailboxes                   one entry per mailbox: its label, kind (tree | direct), and port
  ignore                      one address per line, with its level (hide | mark)
  rooms/
    <local tag>/
      entry                   rmail contacts format, one entry:
                                label, token, kind (group | direct),
                                address[N] with port[N] (always paired),
                                parent (the parent room's fingerprint, or empty),
                                mailbox (the local tag of the mailbox it is in),
                                filed-under (where you placed it in your tree)
      withheld                members you do not send to here, one per line
      where                   this folder's path, and the label
      log                     the messages, appended to, never rewritten
  people/
    <direct-message label>/
      <link name> -> ../../rooms/<local tag>
                              one link per top room this person is a
                              member of, as you see it
```

- **A parent is named by a fingerprint of its token** (a one-way scramble),
  so an invitation to a child room names its parent without revealing the
  parent's token to anyone who does not already hold it.
- **`people/`** answers "what do I share with this person?" with an `ls`:
  the rooms whose members include an address of that direct-message
  contact.  The entries are the truth, the links are the view.
- **`log`** is plain text, one record per message: message id, the address
  it arrived from (or `me`), time written, time arrived, and the text.  A
  person can read a room with `cat` or `less`, back it up by copying the
  folder, and search it with `grep`.
- **Ids make delivery safe to repeat.**  A message delivered twice is
  recognised by its id and not filed again; the same id with different
  contents is an error.

---

## 5. Home server ↔ home server: what comes from rmail

rao-chat reuses rmail's way of reaching people.  Each item below is
something rmail already does and has had its bugs found in.

- **Contacts file.**  `name.field = value` lines.  Several addresses per
  contact (`ip`, `ip[N]`, `port[N]`), home-network addresses (`local-ip`),
  IPv6, hostnames, a shared token, and `own = true` for your own devices.
  An address that works moves to the front.  One change: in rmail a
  missing `port[N]` falls back to the contact's default port; in rao-chat
  every address carries its own port, and a missing one is an error
  (owner: "the current rmail design has one port for many IPs which
  doesn't really make sense tbh"; and "no default port numbers").
- **Encryption.**  Every message between servers is sealed with
  AES-256-GCM, in length-prefixed frames with a random 12-byte nonce, as
  rmail does, under a key made from the room's token (`SHA-256(token)`,
  exactly as rmail makes one from a contact's token).  Each frame ends with
  a 16-byte check value computed over every byte, so opening a frame
  either succeeds or returns nothing — the lock itself says whether it is
  genuine.  Nothing about a room travels in the clear.  There is no
  per-connection key; a room is as private as its token is hard to guess.
- **Acknowledgement.**  As in rmail, a delivery counts only when the
  receiving server confirms it; until then the message is "not yet
  delivered" to that person and is retried.
- **Finding each other at home.**  Servers on the same home network find
  each other by multicast and a sweep of the local network.  An address a
  connection merely came from is trusted only if it is on the server's own
  network (rmail's September 2026 fix: a router relaying traffic was
  mistaken for a housemate).
- **Keeping addresses current.**  Each server works out its public address
  from several independent lookups, confirms a change with a second one,
  rechecks every day or two, tells every contact when it moves, and
  announces itself at startup.
- **Backing off from people who are away.**  When a contact cannot be
  reached, retries slow down (30 seconds, then longer, up to 2 hours) and
  never give up.  Hearing from that contact makes them reachable again.
- **Router safety.**  Automatic port opening (UPnP/NAT-PMP) off by default,
  with rmail's warning; a router that accepts it is reported.

### The one change for chat

rmail notices a new message at once but can hold it until that contact's
timer comes due, up to about a minute for a healthy contact.  rao-chat
sends a new message **immediately** to every reachable recipient; the timer
governs only retries after a failure.

---

## 6. Clients ↔ their home server

- **Pairing** works as in rmail: the device goes into the contacts file with
  a token and `own = true`; the client is given address, port and token
  (rmail's setup screen, its "detect port" scan, and its connection test
  that says exactly what failed).
- **Catching up.**  On connecting, a client says the last message id it
  holds in each room; the server sends everything after.  A client away
  for a week catches up in one exchange; a new client gets the full
  history.
- **Choosing an address.**  The client tries its server's home-network
  address first (quick timeout), then its public one, as rmail's phone does.
- **Several devices at once.**  A phone and a browser can both be
  connected; each message reaches both, and one sent from either appears on
  the other.

### When the connection is live, and when it checks in

| the phone is… | the connection |
|---|---|
| showing the app | live: messages are pushed the moment they arrive |
| showing another app, screen on | still live |
| locked (screen off) | closed; the app checks in about every 30 seconds |

The locked-screen interval varies so that many phones do not all check in
together, while averaging exactly 30 seconds: each wait is 30 seconds plus
an offset dealt from a shuffled deck of whole-second cards, **without
putting cards back**; when the deck runs out it is reshuffled.  Because the
cards add up to zero, one pass through the deck takes exactly as long as
the same number of plain 30-second waits.  (Which cards are in the deck is
open question 4.)

On Android, waking every 30 seconds with the screen off needs a
**foreground service**, which shows a permanent notification; without one,
Android's battery saving delays background work to every 15 minutes or
more.  The notification can be made quiet but not invisible.

### The web client

- **Served by the home server**, so nothing is installed on the computer.
- **Live the whole time the page is open**, over a WebSocket to the home
  server carrying the same encrypted frames as the phone.  The browser's
  built-in cryptography (WebCrypto) does AES-GCM, so the token never leaves
  the browser.
- **Plain HTML, CSS and JavaScript**, no framework.
- **The one real risk:** if the page itself is fetched unencrypted from
  outside the home network, someone in between could change its code and
  steal the token as it is typed.  See open question 5.

---

## 7. How a room looks

Taken from the conversation pages of double-diaper-dungeon's
transcript-to-HTML tool, where each point was already argued out:

- **Speakers on opposite sides.**  Your messages on one side, everyone
  else's on the other, set apart by position and colour, not bubbles.
- **A name only where the speaker changes.**  Five messages in a row from
  one person carry the name once, at the top; repeating it on every line
  stops it being read.
- **Notices are neither speaker.**  Things the home server says ("sorelu
  was removed from this room by you", "3 messages could not be delivered
  yet") are centred, quieter, and boxed.
- **Every message has an anchor**, its message id, so a notice or a search
  result can link straight to it.
- **One palette, defined once**, read by every page and screen rather than
  copied (the example reads its colours from one table).  For rao-chat the
  palette is rmail's (section 8).

---

## 8. The Android app

Follows the rmail app's design so the two feel like one family.

### Look

- **Dark only**: black background, goldenrod text (`#FFD040`), dim
  goldenrod for secondary text (`#B89020`), a cyan accent for progress
  (`#00E5FF`), all adjustable in Settings as in rmail.
- **Monospace** for message text and addresses.
- **Bottom bar as a grid of text buttons**, each its own bright colour,
  filled when selected, hidden while the keyboard is open.  Proposed tabs:
  **Rooms · People · Settings**.
- **No back arrow at the top level.**  The title is the home server's name,
  underlined; tapping it goes to the list of servers.  Inside a room the
  title is the room's path of names, and tapping a name goes to that room.
- **Error strip** across the top, as in rmail, with "(retrying in Nm)".
- **Nothing is deleted by swiping**, a lesson rmail learned.

### Screens

| screen | what it shows |
|---|---|
| **Servers** | the home servers this phone is paired with; **+** to pair another (rmail's mailbox list). |
| **Setup** | address, port, token; "detect port"; a connection test that names exactly what failed. |
| **Rooms** (tab) | the room trees, folded like folders.  Each row: the room's name, the last line said in it, an unread marker.  Rooms that arrived as separate trees are separate rows at the top level. |
| **Room** | the conversation, laid out as in section 7.  The compose line at the bottom grows as you type and keeps the cursor in view (rmail's cursor-aware scrolling).  A "sending… / sent / waiting" marker under your last message, in the spirit of rmail's sending animation.  A **recipients** button lists who your messages here go to, to add or remove people. |
| **People** (tab) | contacts, edited as a form as in rmail; each person's page lists the rooms you share with them (the `people/` links). |
| **Settings** (tab) | addresses, token, colours, notification detail (sender and text / sender only / no preview / none), the locked-screen check-in, a "danger zone" to forget this server. |

---

## 9. The web client

The same palette, monospace and tabs, laid out for a wide screen:

- **Left column:** the room trees.
- **Right:** the open room (section 7), compose line at the bottom.
- **Top bar:** the server's name (click to switch servers), connection
  state, the error strip.
- **People and Settings** open over the room view.

Served from one folder of static files, so what the browser runs can be
read in full.

---

## 10. The rmail link (after rao-chat is complete)

A later patch to rmail's Android app, a'la Facebook and Messenger:

- **Two separate apps**, each installable alone.
- **A button in each app's top bar** opens the other at the matching place:
  from an rmail contact to the rooms you share with them, and from a room
  back to that person's mail.
- If the other app is not installed, the button says so and does nothing
  else.
- Pairing one app can offer to pair the other with the same home computer.

Whether they stay separate apps is open question 10.

---

## 11. Building blocks and languages

- **Home server:** Lua (LuaJIT-compatible), like rmail's daemon, with the
  same crypto, socket and JSON libraries rmail bundles.
- **Android app:** Kotlin with Jetpack Compose, like rmail's app.
- **Web client:** plain HTML, CSS and JavaScript; WebCrypto; WebSocket.
- **Shared with rmail:** the networking in section 5.  How is open
  question 6.

---

## 12. Phases (proposed)

Grouped by what builds on what.  To become a roadmap and issues once the
open questions are answered.

1. **Rooms on the home server** — room folders by local tag, each with an
   entry in rmail's contacts format (label, token, paired addresses,
   parent); group rooms and direct messages alike; the tree of child rooms
   and the parent-membership rule; withheld lists; the ignore list; the
   `people/` links; the message log and ids.
2. **Server-to-server delivery** — sealing with the room's token, sending
   at once with acknowledgement and retries, the failed-decryption log,
   the call-back check, the hello (which is also joining), contact
   syncing, leaving, and periodic cross-checking.
3. **Clients' connection** — pairing, catching up, live pushing, several
   devices, the locked-screen check-in.
4. **The web client.**
5. **The Android app.**
6. **Installation and running as a service** — as rmail's installer does.
7. **The rmail link.**

Each phase ends with a demo; phases 4 and 5 end with the clients talking to
each other.

---

## 13. Open questions

To be asked and answered one at a time before the roadmap is written.

1. *(answered; see below)*
2. *(retired 2026-09-25 with the first model: every member hears you
   unless withheld; see section 3)*  **Whom your replies go to.**  When
   someone adds you to a room and you
   reply, who receives it: only the person who added you; everyone you
   have received a message from in that room; or everyone on the adder's
   list, which would mean each message carries its sender's recipient list
   (as rmail's `to:` lines are visible to the sender only, today)?
3. *(retired 2026-09-25 with the first model: a room's place is its
   name)*  **What travels with a message to place its room in a tree.**  To let a
   reader join `programming` to `ritz` once they are in both, a message
   must say which room it is in and which room that one is inside.  Send
   the parent's id always (the reader learns that a parent exists, not its
   name); or only to people who are also in the parent (they learn nothing
   about rooms they are not in)?
4. **Which cards are in the locked-screen deck.**  The owner listed
   0, 1, 2 … 10 (eleven cards).  Those are all zero or positive, so every
   wait would be 30–40 seconds, averaging 35.  For the waits to average
   exactly 30 the cards must add up to zero.  Choices: −10 … +10 in
   one-second steps (21 cards); −10, −8 … +8, +10 in two-second steps (11
   cards); or −5 … +5 (11 cards, a ±5 second spread).
5. *(answered 2026-11-06 by the builder, issue 401 decision 1: a copy of
   the page kept on the computer and opened from there)*  **Trusting the web page.**  Serve the web client only on the home
   network; over HTTPS with a certificate (hard for a home address); or
   have people keep a copy of the page on their computer and open it from
   there, so only the encrypted connection crosses the internet?
6. *(answered 2026-09-26: rmail is a rubric; see section 15, "How rao-chat relates to rmail")*  **Sharing code with rmail.**  Lift rmail's networking into a library
   both use; copy it and let the two drift; or run rao-chat inside rmail's
   daemon on its own port?
7. *(answered by 6, to be confirmed: two programs)*  **One home server program or two?**  rmail's daemon and rao-chat's
   server side by side (separate ports and folders), or one program doing
   both?
8. **The shape of a message record in `log`.**  One line per message,
   tab-separated (compact, `grep`-friendly); a small labelled block per
   message (readable, multi-line text is easy); or one JSON object per
   line?
9. **What a message can hold.**  Text only, with pictures and files left to
   rmail; or small pictures in chat too?
10. **One app or two?**  The Messenger model is two apps and a button.
    Would you rather one Android app with a switch?
11. **Read receipts, "typing…", online status.**  Each tells others about
    you.  Which, if any, and can each person turn them off?
12. *(answered 2026-09-25; see Answered)*  **Editing and deleting sent
    messages.**  Allowed, allowed for a short
    time, or never (the log is append-only)?
13. **The name.**  What does "rao" stand for, if anything?

### Answered

- **Room size** (2026-09-23): at least two people, no upper limit; not
  exactly two.  Adding a person is adding a recipient.
- **Several rooms per pair** (2026-09-23): yes, nested like folders, each
  with its own recipients; names are the reader's own.
- **The phone's connection** (2026-09-23): live while the screen is on,
  even with the app in the background; about every 30 seconds while
  locked, the offsets dealt from a deck **without** replacement (owner:
  "oh yes, without replacement, my bad").
- **Removing someone** (2026-09-23): splits the room.  The removed
  person's copy becomes a room of its own; their messages stop reaching
  the remover there; everyone else hears both rooms.  Rooms are a
  client-side way of sorting.  *(Superseded 2026-09-25: removing is
  withholding, and ignoring is separate; see section 3.  The first model is
  kept in Appendix A.)*
- **Editing** (2026-09-25, question 12): allowed, with no time limit; an
  edit is its own message and each reader's server keeps the original.
- **A room is its name** (2026-09-25): section 14.  *(Replaced the same day
  by section 15; kept in Appendix B.)*
- **A room is a contact** (2026-09-25): section 15, now sections 1–4.
- **Licence** (2026-09-23): the GNU Affero General Public License, version
  3 or later, as rmail.  `LICENSE` holds the full text.  rmail's extra
  permission for hook scripts is not carried over; rao-chat has no hooks
  yet.

---

## 14. A second model: a room is its name (adopted, then replaced, 2026-09-25)

Raised by the owner after phase 1 was built to the first model, while
asking what that model's complexity bought over a plain conversation /
nested room / forum thread design.  Adopted 2026-09-25 (owner: "Yes
please. Let's re-write the old issues, and update the functionality
afterward."), then replaced the same day by section 15's model; the
sections 1–4 written for it are kept in Appendix B.  This section keeps the
conversation that produced it, in the owner's words, with the reasoning
and the questions as they were settled.  Much of it carries into the
current model: signatures, the sender being unknowable, withholding and
ignoring, leaving and the address rule, the call-back check, the hello and
its port, contact syncing, cross-checking, and the threat model.

### The owner's words

On whether the host model and the no-host model conflict:

> these sound compatible to me? Like, what if we shared peer-to-peer style
> with anyone we knew who was in the same room. We could share their IPs,
> or ideally, we could require or highly suggest hostnames instead. The
> system is already peer-to-peer, we'd be adding a way to share contacts
> peer-to-peer, and the shared key would just be the name of the room.
> Nesting would mean that the shared key had slashes in it, easy peasy.
> You could theoretically have separate islands of conversation that had
> the same shared key, but didn't have any contacts in common between them
> except you - for that, we'd just have to handle the sorting on our end,
> and ensure that the two contact lists don't get cross-contaminated.
>
> Then, if you wanted to block or remove someone, you could have two
> levels - hide all their messages from me because I don't want to see
> them, but maybe I do want to know that they said something, or hide them
> entirely from me. Separately, you could say who you wanted to send to.
> They would have a separate list of who they wanted to send to. If you
> start getting spam, just go to a different server after identifying who
> it was that caused it. It could only happen if someone intentionally
> sells the contact details to a spammer or whatever, and then it's just
> easy to ignore them and move on because you need shared keys to receive
> anything they send anyway. We should also ensure that we have logs that
> show unsuccessful decryption attempts, by the way, to avoid DDOSing or
> whatever.
>
> I don't think groups or forum threads need to be monolithic, we just
> send the messages when we can and they get sorted accordingly.
> Everything is edit-able by design with no record, so nothing can be
> trusted unless you make local copies yourself. Which might be something
> we want to build in, now that I think of it...!
>
> It's like the cryptocurrency version of social media. Or like NFTs,
> except instead of jpegs they're digital town squares and third spaces.
> All you need is to know someone who is in a room, and then you can be
> there. If you don't, then you can make your own at that same location
> and they layer over each other semantically, but not practically,
> because you'd never even know the other existed. You could even merge
> spaces by just, inviting everyone to both, and they would collapse into
> a single group naturally.

On tokens and nesting:

> the token is the room name. The contact details are the IP and port.

> I was thinking that the upper level rooms would be like, a discord
> server, and the lower level ones would be arbitrarily nested rooms in
> that server.

On secure names, signatures, trust and removal:

> Okay for the room names, I think it's okay. If they wanted a secure
> name, they'd have a randomized top-level domain and then they could add
> lower rooms below it that are more sanely organized. Since the client is
> open source, they might even be able to just, modify their client to
> hide the random part, and then the key could be as long as they wanted
> and impossible to guess.
>
> for the names, we could just, um, "suggest", that the last line in a
> message is the contact's name. In the chat dialogue that the users type
> into, we could have a persistent text entry field nearby that basically
> says "signature" and if there's no signature, then nobody can tell who
> left that sheet of notebook paper at the starbucks, and that's expected.
> You can also sign things by someone else but that's considered taboo for
> obvious reasons. We could even have a system that flags things that are
> signed by specific names, but, ah that's complexity for no perfect value
> because the fraudster might just ignore you and never send to you, so
> you'd have nothing to check. Unless all clients continually verified the
> received messages with each other consistently, then we could remove the
> concept of blocking people entirely and just say if you don't like
> someone, then go to a different room. Or maybe we could support both
> systems, and depending on which rmail hooks each group of clients
> enable, they could be part of various different rooms with differing
> standards... ideas?

> I don't like the idea of tokens being non-plain text. They're harder to
> share.

> also, it means that anyone can make private channels inside of servers,
> which really are just an organizational [convenience, but pronounced
> hazard] since there's no servers and everything is push-to-talk only.

> I mean, you could just... remove that person from everyone else's
> send-to contact list. Then they'd never be able to see again. And you
> could specifically ignore them, so even if they send you spam junk you
> can ignore them. Eventually, everyone's IP's will change, (unless they
> use a hostname I guess), so if you ignore people often then IPs are a
> better choice, but if you prefer reliability and trust DNS, then
> hostnames are better.

> That's not entirely true. If the top level name is something common like
> "coffee-shop" or whatever, then even if other people know the key,
> there's a discoverability problem. They won't know about each other.
> Sure, they can decode each other's messages, and their clients know how
> to sort them in their UIs, but they lack the IP and port address
> connection to anyone who is joining a coffee-shop in Baltimore or
> Timbuktu or whatever.

> People should not be liable for their words. Responsibility should be
> forged through something stronger than air.

> could just, have everyone sync their contacts list whenever they notice
> that a new person joined the room. We can't tell when someone left.
> Also, we should be able to request that others automatically send their
> contacts list to us, in the same way that the RGPL requires people to
> send their source-code if requested. Like, if we make a special type of
> message and put it in the outbox. In the UI it'll probably be tapping a
> button or something, or the user could make it auto-triggered...

> I mean, we could just keep track of our ignore list. That'll stay valid
> until they change IP addresses.

### The model

- **A room is its name.**  The whole path, as plain text
  (`coffee-shop/games/chess`), is both what people share and the room's
  key.  The program turns the text into an encryption key internally (as
  rmail turns its plain-text token into `SHA-256(token)`); people only
  ever see and share words.
- **Nesting is slashes.**  The top level is like a Discord server, the
  rooms below it like its channels.  Knowing a room's name tells you every
  name above it, and that is accepted: rooms below the top are for
  organising.  The girlfriend example (section 3) becomes separate top
  levels, not a gap in one tree.
- **Privacy has two layers.**
  - *Who you can reach.*  A common name is private in practice: two
    `coffee-shop` groups share a key but not an address list, so they
    never meet.  A room is joined by knowing someone in it, meaning their
    address and port.
  - *Who can guess the key.*  Anyone wanting a name nobody can guess uses
    a random top level (`x7q9kw…/games`); a client may hide the random
    part on screen.
- **Two facts about each message.**  *Where it came from* is the address
  of the connection that delivered it (every writer sends directly to
  every reader).  *Who signed it* is a suggested last line, typed in a
  persistent "signature" field, or nothing: an unsigned message is the
  notebook page left at the coffee shop.  Signing as someone else is
  taboo, not prevented.
- **Sending and hearing are each person's own.**  You keep who you send
  to; others keep theirs.  Removing someone is each person taking them
  off their own send list.  Ignoring has two levels: hide their messages
  but show that they spoke, or hide them entirely.  An ignore list is
  kept by address and holds until the address changes.
- **Contacts spread within a room.**  When a new person is noticed in a
  room, everyone shares their contact list for that room.  Anyone may
  also ask for it with a request message in the outbox (a button, or
  automatic), the way the licence obliges source code to be sent on
  request.  The ignore list filters incoming contacts as well as
  messages.  Leaving cannot be noticed; a person leaves by no longer
  sending.
- **Islands and merging.**  Two groups with the same name and no contact
  in common stay separate.  A person in both keeps the two apart on their
  own disk, so the two contact lists do not mix; inviting everyone to
  both merges them.
- **Edits.**  Anything may be edited, with no record kept by the sender;
  a reader who wants proof keeps their own copy.  (Phase 1's message log
  `corrections` setting already keeps the original beside every edit.)
- **Failed decryption is logged**, to notice someone flooding a server.
- **Addresses or hostnames.**  Plain addresses drop ignored people
  naturally when addresses change; hostnames keep everyone, dropped
  people included, able to find you.

### What it would retire from phase 1

The removal split and its four settings, un-telling a room's place, parent
disclosure and separate trees joining, a parent you do not hold, and the
naming and placing of rooms made on arrival.  The message log, the room
folders on disk, the people view and the options tally carry over.

### Open questions for this model

1. **Protecting the wire.**  With the room name as the only key, anyone
   who can watch traffic (an internet provider, a café's router) can
   guess a common name and read along.  Should every connection between
   two servers also get a throwaway key agreed by the two computers when
   they connect (as HTTPS does), changing nothing people share?
2. **What "something stronger than air" is.**  If people are not to be
   liable for their words, what are they answerable through: the
   connection (knowing where someone is), knowing them in person,
   something else?
3. **When is a silent contact forgotten?**  Leaving cannot be noticed, and
   rmail retries an unreachable contact forever (slowing to every 2
   hours), so every person who ever passed through a room becomes a
   permanent retry.  After how long, or on what sign, is one dropped?
4. **Keeping islands apart on your own disk.**  A message arrives
   addressed to `coffee-shop` from an address you have never seen.  If
   you are in two `coffee-shop` islands, which one is it filed in?
5. **Consent to being passed along.**  Contact syncing passes your address
   to everyone in the room, including people who join later.  Is being in
   a room consent to that?
6. **Signed-as-someone-else.**  Taboo but not prevented.  Does the client
   show anything when a signature names a contact whose address differs
   from where the message came from?
7. **Cross-checking between clients.**  Clients telling each other what
   they received from whom would catch someone showing different words to
   different people.  Wanted, as an optional hook, or not at all?
8. **Rooms with different standards.**  Filters run as rmail hooks, per
   group of clients.  Given "people should not be liable for their
   words", which kinds of filter are in keeping, if any?

### Toward question 4: strangers, vouching and the waiting pile

The owner, answering question 4:

> you send out a request to the other people in the room "hey can you send
> me your contact lists?" then you don't decrypt the untrusted message
> until you get back a response that confirms that the sender is invited.
>
> wait, hang on, if we only know a sender based on their token... How the
> heck would we validate new contacts?
>
> um. Maybe there's a different endpoint that sends a different, also
> encrypted packet, that has their, idk, IP address and port, so you know
> how to send back to? And someone else in the room has to have added them
> to their "contacts list" manually, and you have to be able to request
> their list and validate, before you decrypt any untrusted messages. The
> IP address and port of a new contact will have to be in cleartext, which
> sucks... What do you think?

Worked through (proposal, not yet agreed):

- **Nothing new in the clear.**  Every internet packet already carries its
  sender's address openly; that cannot be hidden and need not be
  repeated.  What the packet does not show is the port the sender
  *listens* on (outgoing connections use a random port), so a **hello**
  message says "call me back on port N", sealed with the room key.
- **Open freely, file only when vouched.**  Opening a message with the
  room key does not trust it.  A message from an unknown address is
  opened and put in a **waiting pile** for that room name; the server asks
  the people it knows in each island of that name whether any of them
  vouches for the address.  **The island whose member vouches is the
  island it is filed in** — this answers question 4.  Unvouched messages
  stay waiting; the client can show that they exist without showing them.
- **Inviting is vouching.**  The member who added the newcomer by hand is
  the one who answers yes.
- **The call-back check.**  Before trusting "I am at this address, port
  N", the server calls that address and port and asks "did you send
  message X?"  Only a computer really listening there can answer.  No
  keys needed; it also stops a false return address being used to aim
  replies at someone else.

New open questions:

9. **"I moved."**  Everyone in a room holds the same key, so anyone in it
   can send "I am sorelu, my new address is X" and take sorelu's place in
   every contact list that believes it.  rmail avoids this because each
   pair has its own token.  Close it with: hostnames plus the call-back
   (DNS says where a name points, and only its owner can change that); a
   personal secret per person, used only to prove "still me"; or
   re-vouching after every move?
10. **An unvouched message that never gets vouched.**  How long does the
    waiting pile keep it, and does it count toward the failed-decryption
    / flooding log?

Where the port sits, asked by the owner ("can we use a manually defined
port? ... Where in the stack would that rest?"): ports are in **TCP**,
not HTTP.  A program may choose its outgoing port (even its listening
one), but most homes sit behind a router doing address translation, which
may rewrite the outgoing port, and which reaches the server from outside
only through a forwarded port whose outside number can differ from the
inside one.  So the port worth telling others is the outside forwarded
one, and it has to be said, not read off the connection.

11. *(answered 2026-09-25)* **A default port.**  Proposed: everyone
    listens on one agreed port, so a hello only carries a port when it
    differs.  Owner: "no way. no default port numbers."  Every hello
    carries its port; a hello without one is an error, not a guess.  (It
    also leaves no well-known port for scanners to probe.)

### Answers, 2026-09-25 (questions 1–10 asked together)

The owner's words, then what follows from them.

1. **Protecting the wire.**  Owner: "the token isn't passed over the
   network ever though...?"  True; but the sealed messages are, and a
   person recording them can try guessed names against them later (the
   seal says plainly whether a key opened it, which is how leaked
   password lists are cracked).  rmail's tokens resist this by being long
   and random.  **Still open** — (a) a throwaway key per connection as
   well, or (b) accept that common names are readable by anyone who
   records the traffic?
2. **Answerable through:** "Knowing them in person, or being vouched for
   by someone who does."  Vouching governs whom you send to; it does not
   prove who wrote a message (see 6).
3. **Leaving.**  "the moment we know that the person has left the room.
   We should add messages that do so. We should assume that everyone is
   keeping a transcript log of everything that is said, so letting the
   messages pile up with unsent contacts still waiting is fine probably,
   unless it strains the rmail single-threaded messaging core engine in
   which case we'll re-assess at scale."  A **leave message** is added.
   Undelivered messages wait for their contact indefinitely; re-assess if
   the queue strains the sending engine.
4. **Strangers.**  "we should open it and only read enough of it to
   confirm that it decrypted correctly. Otherwise, yes, this design."  The
   seal's check covers every byte, so the whole message passes through
   the lock; it is then held in the waiting pile unparsed and unshown
   until vouched.  (If the body should stay sealed until then, the hello
   travels as its own small sealed piece and the body is sealed
   separately — noted, not decided.)
5. **Consent:** being in a room is consent to your address being passed
   to its members.
6. **Signatures.**  "It shows nothing: signing as someone else is taboo,
   not policed. … we can't know for sure anyway because we don't have any
   way to know who sent which message. Sure, we can see which IP address
   sent it, but IP addresses change, so we shouldn't trust or rely on
   them. Someone might even be passing it through TOR, or some other kind
   of routing protocol, so we should just assume that we can't know who
   sent something, and trust the signature, which explicitely can be
   signed however you'd like. If this turns out to be a stupid design
   decision, we'll catch it and update."  **The sender is unknowable by
   design; the signature is what a message says about itself.**
7. **Cross-checking.**  "we shouldn't syncronize on every single message,
   but like... periodically we can sync. If there's ever a discrepancy
   it's raised as an error, not a silent warning in some log somewhere
   that gets auto-corrected. But remember, we also need to be able to
   edit messages as well... Phew this is complex!"  Periodic sync.
   Because each person chooses whom they send to, people legitimately
   hold different sets of messages, so a *missing* message is normal.
   The one real discrepancy is **the same message id with different
   contents**, raised as an error.  An edit is its own record with its
   own id, so edits never cause one.  Consequence for phase 1: the
   message log currently answers "duplicate" to a repeated id without
   comparing contents (issue 105, `log-repeated-id-different-content`);
   under this answer it must become an error.
8. **Standards and filters:** "let's build these later. They are
   mentioned because they are possible, and should be considered, but the
   base platform is an open, permissive one that doesn't require complete
   trust."
9. **"I moved."**  "again we just, shouldn't trust a sender's IP address.
   So, no need to validate such a thing."  Addresses answer "where do I
   send", never "who wrote this".  Since everyone in a room can already
   read it, a false move reveals nothing; its only harm is silencing (the
   real person stops receiving), and a false leave message does the same.
   Proposed single rule: **addresses are added freely; an address is
   removed only when it says so itself or stops answering.**  A move adds
   the new address beside the old (rmail already keeps several per
   contact); a leave message is confirmed by asking the leaving address.
   A forger can add noise but cannot silence anyone.  (Proposal; not yet
   agreed.)
10. **Unvouched messages** are dropped after a set time.  Owner: "the
    user can specify in their contacts file maybe?"  A stranger has no
    contacts entry, so the setting lives in `config`, per home or per
    room, with no default.  (Where exactly: open.)

Still open after this round: 1 (the wire), the add-freely/remove-by-own-
word rule in 9, the separately-sealed hello in 4, and where 10's setting
lives.

### Follow-up, 2026-09-25

1. **The wire.**  Owner: "I don't see how this is more likely than, like,
   having an IP address and guessing which ports are open? … It feels...
   like a rare situation? Can you give me example "use-cases" that a
   hacker or malicious attacker might attempt? I don't know the exact
   term for it - threat profiles maybe?"  The term is a **threat model**.
   The attacker in question 1 does not guess: they sit on the path the
   traffic already takes (café wifi, an internet provider, a school or
   employer network, bulk surveillance), where every packet shows its
   addresses and ports in the open, and try room names against recorded
   messages later at no cost.  The threat model worked through:

   | who | already sees | does | answer |
   |---|---|---|---|
   | café wifi, open network | the phone's traffic there | records, guesses common names later | open (question 1) |
   | internet provider, school, employer | all traffic, by policy | keeps it in bulk | open (question 1) |
   | bulk surveillance | traffic across networks | runs name dictionaries automatically | open (question 1) |
   | harvester | one public room | collects every address via contact sync | accepted (being in a room is consent) |
   | flooder | an address and port | sends junk; every piece costs a try of every key | failed-decryption log; slow down failing addresses |
   | silencer | the room name | false "left" / "moved" | the address rule (2 below) |
   | two-faced sender | the room name | different contents under one id | periodic cross-check raises an error |
   | impersonator | the room name | signs as someone else | accepted by design |
   | replayer | a recorded message | re-sends it | the duplicate-id check |
   | locator | any contact list | an address gives city and provider | accepted with consent |

   The fix, if wanted, is a throwaway key agreed per connection (as HTTPS
   does), which OpenSSL — already used by rmail — provides.  **Still
   open**: is reading common-named rooms by those already on the path
   acceptable for an open, permissive platform?
2. **Addresses: agreed.**  Owner: "yeah, the address will send to everyone
   and say "hello I'm not in this room anymore" and if they receive more
   messages from them, they get re-added of course because that's how it
   works in general right?"  Rule: addresses are added freely (speaking
   re-adds you; the ignore list still overrides); an address is removed
   only by its own say-so or by going silent.  Proposed addition: a leave
   notice is confirmed by asking that address "did you leave?", so no one
   can send it for someone else.
3. **Opening without touching.**  Owner: "opened but not parsed. Not
   scanned. Not even touched. We decrypt the entire message, then scan
   through the first N bytes looking for a success code that indicates
   that the message has been successfully decrypted. That's how we do it
   for rmail, right?"  rmail (`rmail_crypto.c`) does it more strongly:
   every sealed frame ends with a 16-byte check value (the AES-GCM tag)
   computed from the key and every byte; opening recomputes it and returns
   nothing at all if one bit or the key is wrong.  So the lock itself says
   "opened" or "not", nothing reads the contents, and the opened message
   waits unparsed until vouched.  **Agreed: opened, not parsed.**  The
   separately-sealed hello is not needed.
4. **Waiting-pile time limit.**  Owner: "Um, I dunno."  Suggestion: one
   value for the whole home in `config`, no default; a per-room value can
   be added later if a room needs one.  Open.

### The threat model, answered (2026-09-25)

The owner, row by row:

- Café wifi, internet provider: "it's all encrypted, so I don't think
  that's very vulnerabilizing." / "same."
- Bulk surveillance: "good, make them work for it. Anyone who cares about
  privacy will use randomized base room names anyway."
- Harvester: "you'd need a contact in the room. rmail doesn't protect
  against being betrayed by someone you trust."
- Flooder: "the isp will notice DDOS attacks and change your IP out from
  under you. And from under them. Also, fail2ban is a thing, albiet it's
  effectiveness is mitigated by proxies and such."
- Silencer, two-faced sender, impersonator: "they need to already be
  trusted, and then they only get what any other contact would have. rmail
  does not protect against betrayal. but that's a human problem that
  software should not be designed to counteract."
- Replayer: "I struggle to see how that would be malicious. Maybe
  annoying, especially when coupled with the DDoS style attacks, but it
  doesn't even damage your hard drive through repeated use and mechanical
  wear so what's the concern aside from increased latency from the
  traffic? That's something the ISP could notice, or your dynamic firewall
  or something."
- Locator: "again, this is betrayal, and we cannot help with that. We can
  mitigate it by being as simple and secure as possible, but at the end of
  the day if you march to war and your buddy draws his sword alongside you
  but uses it on his brother, then is the sword to blame? The scabbard?
  The battlefield?"

What follows:

- **Principle: rao-chat defends against strangers, not against betrayal
  by someone you trusted.**  Harvesting, forged signatures and passing on
  a location all need a member to have let the person in; after that they
  hold only what any member holds.  The software stays as simple and
  secure as it can and does not try to counteract a human choice.
- **Question 1 answered: no per-connection key.**  Encryption under a
  guessable name makes attackers work for it; privacy is a random
  top-level name, chosen by those who want it.  A common-named room is
  like a conversation in a real café.
- **Harvester correction:** contact syncing only reaches people already
  connected to a room, so harvesting is betrayal, not a stranger's attack.
- **Replay:** harmless — dropped as a duplicate; a replayed leave notice is
  caught by the "did you leave?" call-back.
- **Flooding is left to the internet provider and the firewall.**  The
  failed-decryption log is written for fail2ban (which watches a log file
  and blocks addresses that keep appearing): one line per failure, with
  time and address, at a fixed path.  rao-chat builds no flood defence of
  its own beyond that log.

Still open from this round: where the waiting pile's time limit lives
(suggested: one value per home in `config`, no default).

---

## 15. A third model: a room is a contact (adopted 2026-09-25)

Raised by the owner after section 14 was adopted and the issues rewritten
for it.  Adopted the same day; sections 1–4 now describe it.

### The owner's words

> Yo I just had a new idea for the design, can we compare it with the
> current design?
>
> basically, instead of the token being the room name, we could have the
> contact name be the room name. Then, each contact could have several
> IPs, and we'd deliver to all of them. Each of these IP/port combinations
> (we'd have to bundle them together, the current rmail design has one
> port for many IPs which doesn't really make sense tbh) would be a
> recipient. The shared key would be a special code that is for
> authentication purposes only. Is that... somehow better or worse?

On each nested room needing its own invitation:

> I think it's okay. This way, we can have tiers of trust. The farther down
> in the directory structure you go, the more people you'll need to have
> invited you. It also guarantees that lower rooms have only members that
> exist in higher rooms. And it encourages task focus to specialize,
> rather than power to hierarchicalize, though I bet people will still use
> it the other way too, /sigh

On a leaked token: "And this can be resolved without losing the room
itself."

On rooms and people sharing the contacts file:

> We can keep them separate, so that we can communicate with people with
> direct-messaging style conversations and group chats. Though, I'd like
> if all of them used the same general architecture, with as much
> code-reuse as possible.

### The model

- **A room is a contact entry**: a label (the reader's own), a random
  plain-text token, and a list of addresses, each an (address, port) pair
  with no default port.  Every pair is a recipient.  The token makes the
  sealing key, as rmail's does; being able to seal is the proof of
  belonging.
- **A direct message is a room with one other member** — exactly an rmail
  contact today.  People and rooms are kept in two files of one format,
  read and written by the same code.
- **The token is random**, so recording traffic and guessing is useless.
  A public square is a room whose token is deliberately guessable; the
  section 14 model is the special case "token = name".
- **Two groups with the same label are simply different rooms** (different
  tokens).  Islands, vouching, the waiting pile and merging are not needed:
  holding the token is being invited.
- **Names belong to the reader again**; rename freely.
- **Nesting: each room has its own token and its own invitation.**  Tiers
  of trust: deeper rooms need more people to have invited you.
- **rmail's `ip[N]`/`port[N]` pairs** already exist, but a missing
  `port[N]` falls back to the default port; that fallback goes.

### Worked through

- **Tiers of trust need one enforced rule.**  Tokens are independent, so a
  member of a child room can hand its token to an outsider.  "Lower rooms
  hold only members of higher rooms" holds only if every server refuses a
  new address in a child room that is not a member of the parent room as
  it sees it.
- **This conflicts with the owner's first example** (the girlfriend in
  `home` and `home/ritz/programming` but not `ritz`; the programming friend
  in `programming` only).  Proposed: two kinds of "below" — *declared
  children* (the invitation names the parent; parent membership enforced;
  the trust tiers) and *your own filing* (a room placed under another on
  your own screen only; a separate room to everyone else; the first
  example).
- **Changing a leaked token** keeps the room (history, name, members minus
  the leaker).  The new token cannot be sent sealed with the old one; it
  goes to each remaining member through their direct-message contact.
  Members without one need a re-invite from someone who has one.

### Open questions for this model

1. *(answered)* **Adopt it** in place of section 14's model?  Owner: "yes".
2. **Two kinds of "below"** (declared children and your own filing), or
   declared children only (dropping the first example's shape)?  Owner:
   "in the UI we will have rooms sorted like a directory tree structure.
   Picture a filesystem that lets you open and collapse nodes to view the
   contents in the tree. Very Microsoft Windows Explorer core."  The tree
   is settled; whether a room may also be *filed* under another without
   being its declared child (the first example: the girlfriend in
   `programming` without `ritz`) is **still open**.  Sections 1–4 keep a
   `filed-under` field for it.
3. *(answered)* **Who may change a room's token?**  Owner: "Not sure. When
   it's built we'll develop usability improvements. For now, let's say
   it's manually modified."  By hand, for now; the new token is given out
   by hand through direct messages.
4. *(answered)* **Readable tokens.**  Owner: "we don't restrict what users
   use for their token, but we suggest readable tokens like that."  Any
   text is allowed; the app suggests random readable words.
5. *(answered)* **Who may start a child room?**  Owner: "Anyone. It's not
   like it's taking up space on a server somewhere, so no need to restrict
   it to certain permissions."

---

## Appendix A. The first model (built in phase 1, retired 2026-09-25)

Sections 3 and 4 as they stood when phase 1 was first built.  In this
model a room was known by a random id that travelled between servers,
names belonged to each reader, and removing someone split the room.  It
was retired for the model in section 14 (Appendix B), which needs no
split, no disclosure of parent rooms and no agreed room ids; that model was
itself replaced by section 15's (sections 1–4).  Kept so the first build
can be understood.

### A.3 Rooms and who hears what

This follows rmail's addressing: a message goes to the names on its `to:`
lines, and the sender's server remembers who it went to.  In rao-chat each
room keeps that list, and every message written in the room goes to it.

- **You choose who hears you.**  Adding someone to a room's recipient list
  means your messages there reach them from then on.  Removing them means
  they stop.  That is all adding and removing is.
- **You cannot choose who hears anyone else.**  Each person in a room has
  their own recipient list for it.  If you remove someone and a third
  person has not, the third person's messages still reach them.  Owner:
  "Nobody can control if someone else is listening to someone else, but we
  can control if they're listening to us."
- **Being removed splits the room.**  Rooms and conversations are a way of
  sorting on each person's own screen, nothing more.  When you remove
  someone, their server is told, and their copy of the room becomes a new
  room of its own, with everything they had received kept in it.  From
  then on you talk into your room and they talk into theirs; their
  messages no longer reach you there.  Everyone else stays on both lists
  unless they choose otherwise, so they now hear two rooms where there
  was one.  Owner: "yes it's a different room, no their messages don't
  reach you, because they're talking into their room with 5 people (used
  to be 6) and you're talking into your room of 5 people (used to be 6) -
  everyone else is listening eagerly."
- **Replying.**  When a message arrives in a room you have never seen, your
  server makes that room for you.  Whom your replies go to is open
  question 2.
- **Order.**  Messages carry the time they were written (whole seconds
  since 1970).  A room shows them in that order, and a message that
  arrives late is placed where it belongs, moving the ones after it down.
  Ties are broken by room id then message id, so every reader sees the
  same order.

#### Trees, and trees that look separate

Take the owner's example.  You have three rooms, one inside the next:

```
home                  recipients: everyone in your household
└── ritz              recipients: (just you)
    └── programming   recipients: the people you program with
```

- **Your girlfriend** is in `home` and `programming`, but not `ritz`.  She
  sees two separate trees: `home`, and `programming` on its own.  Nothing
  she receives tells her they are connected.
- **A programming friend** is in `programming` only.  He sees one tree,
  `programming`, and nothing above it.
- **If you add your girlfriend to `ritz`**, the gap closes: she now sees one
  tree, `home → ritz → programming`.

So a room's place in someone's tree is only as complete as the rooms of
that tree they are in.  (What travels with a message to make this work is
open question 3.)

#### Names belong to the reader

A room's name is a label each person keeps for themselves.  You can have
two rooms called `programming`; a friend can call your `programming` room
`ritz-code`.  Names are how people sort; room ids are how servers match.
Owner: "it's just a name that we sort ourselves, it doesn't necessarily
refer directly to the filesystem."



### A.4 Rooms on disk

Because names do not imply structure, the folder a room is stored in cannot
be its name.  Rooms are stored flat, by room id, and the tree is recorded
inside them.  Owner: "These can be stored on disk behind the scenes as we
please ... However we keep the actual file-path of the file on our disk
right next to the file, easily accessible as easily as accessing the name."

```
rao-home/
  config                      name, port, settings (rmail's config format)
  contacts                    people and own devices (rmail's format)
  rooms/
    <room id>/
      name                    your name for the room (one line of text)
      parent                  the parent room's id, or empty for a top room
      recipients              one contact name per line: who you send to
      where                   this room's own folder path, and its path of
                              names from the top ("home/ritz/programming"),
                              kept beside the room so either is one read away
      log                     the messages, appended to, never rewritten
  people/
    <contact>/
      <room name> -> ../../rooms/<room id>
                              one link per top room this contact is in, as
                              you see it: the highest room of each tree
                              they are a recipient of
```

- **`people/`** answers "what do I share with this person?" with an `ls`.
  The links are rebuilt from the rooms' recipient lists whenever a list
  changes; the lists are the truth, the links are the view.
- **`log`** is plain text, one record per message: message id (text,
  unique), author (text: "me" or a contact's name), time written (whole
  seconds since 1970), time arrived (the same), and the text.  Its exact
  shape is open question 8.  A person can read a room with `cat` or
  `less`, back it up by copying the folder, and search it with `grep`.
- **Ids make delivery safe to repeat.**  A delivery sent twice (the first
  answer got lost) is recognised by its message id and not filed again.
  rmail learned this in September 2026, when two daemons dialling each
  other at once filed one message eight times.

---

## Appendix B. The second model: a room is its name (adopted and replaced 2026-09-25)

Sections 1-4 as they stood while section 14's model was the design.  A
room's plain-text name was its key; same-named groups were islands told
apart by vouching; strangers' messages waited in a waiting pile.  Replaced
the same day by section 15's model, where a room is a contact with a
random token: holding the token is being invited, so islands, vouching
and the waiting pile are not needed, and a recorded message cannot be
opened by guessing a common name.

### B.1 What rao-chat is

Private chat between people who each run a small server at home.  There is
no central server: a message goes from the writer's home server straight to
each reader's, the way rmail mail does.

**A room is its name.**  A room's full name — a path of words such as
`coffee-shop/games/chess` — is both what people tell each other and the
key its messages are sealed with.  Rooms nest by the slashes in their
names: the top level is like a Discord server, the rooms below it like its
channels.  All you need to be in a room is its name and someone in it who
will vouch for you.

Two groups can use the same name without ever meeting: a `coffee-shop` in
Baltimore and one in Timbuktu share a key but no one who knows anyone in
the other, so neither ever hears the other.  Each such group is an
**island**.  Invite everyone to both, and the two islands become one room.
(Owner: "they layer over each other semantically, but not practically,
because you'd never even know the other existed.")

Each person reaches their home server from:

- the **Android app**, which looks and behaves like the rmail app;
- the **web client**, a page served by their own home server, for talking
  from a computer.

Both show the same rooms and history, because both live on the home server.

Later, once rao-chat works, rmail's Android app gains a button that jumps to
rao-chat and back, the way Facebook's app and Messenger link to each other.

#### What it is not

- **Not a hosted service.**  Nobody's messages pass through a server that
  none of the people in the room runs.
- **Not an identity system.**  Nobody can know for certain who wrote a
  message.  A message carries whatever signature its writer typed, or none
  (section 3).
- **Not a defence against betrayal.**  rao-chat protects a room from
  strangers.  Someone a member let in holds what any member holds, and what
  they do with it is a human matter (section 14, "The threat model").
- **Not a mail client.**  rmail stays the place for long, file-shaped
  messages and attachments.



### B.2 Words used in this document

| word | meaning |
|---|---|
| **home server** | the program each person runs on a computer at home (in rmail, "the daemon").  It holds their rooms, talks to other home servers, and serves their clients. |
| **room name** | a room's full path of words, as plain text (`coffee-shop/games`).  It is shared by telling people, and the program turns it into the room's encryption key.  The last word is the room's own; the words before it name the rooms it sits inside. |
| **island** | one group of people using a room name, connected to each other by knowing each other's addresses.  Two islands can share a name and never meet.  Your server tells them apart by a tag it keeps to itself, never sent. |
| **address** | where a home server can be reached: an IP address or hostname, and the port it listens on.  Addresses answer "where do I send"; they never prove who wrote something. |
| **member** | an address your server knows to be in a room, because someone in the room vouched for it. |
| **withheld** | a member you have chosen not to send to in a room.  Everyone else in the room keeps their own choices. |
| **ignore list** | addresses whose messages you do not want: hidden entirely, or marked ("someone you ignore spoke").  Yours alone; holds until that address changes. |
| **signature** | the last line of a message, typed by its writer in a persistent "signature" field, or nothing.  Signing as someone else is taboo, not prevented. |
| **vouching** | a member confirming that an address belongs in a room.  Inviting someone is vouching for them. |
| **waiting pile** | messages from addresses no one has vouched for yet: opened (so the lock has said they are genuine), but not parsed or shown. |
| **contact** | a person you have named yourself in the contacts file (rmail's format), with their addresses.  Members you have not named are shown by their address. |
| **device** | one of your own clients (a phone, a browser) paired with your home server; in the contacts file, an entry marked `own = true`, as in rmail. |
| **message** | one entry in a room: its id, the address it arrived from, when it was written and arrived, and its text (signature included). |
| **delivery** | a message moving from the writer's home server to a reader's. |
| **live connection** | a connection a client holds open to its home server, so new messages arrive the moment they land. |



### B.3 Rooms and who hears what

- **You choose who hears you.**  Every member of a room hears your messages
  there unless you withhold them.  Withholding someone means your messages
  stop reaching them; that is all removal is.
- **You cannot choose who hears anyone else.**  Each person makes their own
  choices.  To stop someone hearing a room entirely, everyone in it would
  have to withhold them.  Owner: "Nobody can control if someone else is
  listening to someone else, but we can control if they're listening to
  us."
- **Ignoring** is separate from withholding.  Two levels: hide an address's
  messages entirely, or hide them but show that they spoke.  The ignore
  list also refuses that address when other members' contact lists bring
  it back.  It holds until the address changes.
- **Joining.**  Someone in the room tells you its name and vouches for you.
  When your first message arrives at another member's server, it waits in
  their waiting pile until a member they already know vouches for your
  address.  **The island whose member vouches is the island it is filed
  in.**  Messages no one vouches for are dropped after a set time.
- **Members spread.**  When a new member is noticed, the members share
  their contact lists for the room; anyone may also ask for them, the way
  the licence obliges source code to be sent on request.  Being in a room
  is consent to your address being passed to its members.
- **Leaving** is a message: "I'm not in this room anymore."  An address is
  removed from a room only by its own say-so or by going silent; a leave
  notice is confirmed by asking that address.  Speaking again brings you
  back.  Addresses are added freely: a move adds the new address beside
  the old.
- **Signatures.**  The sender of a message is unknowable by design: an
  address can change or pass through Tor.  The signature is what a
  message says about itself.  Owner: "If this turns out to be a stupid
  design decision, we'll catch it and update."
- **Edits.**  Anything may be edited.  An edit is its own message naming the
  one it changes; your server keeps the original beside it, so your own
  copy is the record ("nothing can be trusted unless you make local copies
  yourself").
- **Order.**  Messages carry the time they were written (whole seconds
  since 1970).  A room shows them in that order, and a message that
  arrives late is placed where it belongs.  Ties are broken by message id,
  so every reader sees the same order.
- **Checking each other.**  Members periodically compare what they have
  received.  A missing message is normal, since everyone chooses whom they
  send to.  The same message id with different contents is an error,
  raised to the person, not quietly corrected.

#### Trees

A room's place in the tree is its name.  `coffee-shop/games` sits inside
`coffee-shop` in the same island.  Knowing a room's name tells you every
name above it, and that is accepted: rooms below the top are for
organising, not secrecy.  Owner: "an organizational [convenience, but
pronounced hazard] since there's no servers and everything is push-to-talk
only."  Privacy lives at the top: a random top-level name
(`x7q9kw…/games`) cannot be guessed, and a client may hide the random part
on screen.

Being in `coffee-shop/games` does not make you a member of `coffee-shop`;
you are a member of a room only when someone vouches for you in it.  If
you hold a room but not the one above it, it is a top room for you.

Because the name is the key, a room cannot be renamed or moved: a
different name is a different room.



### B.4 Rooms on disk

Rooms are stored flat, each in a folder named by a random tag of your own.
The tag is what lets two islands with the same name sit side by side; it is
never sent.  The room's name, and the folder's own path, are kept inside,
side by side.  Owner: "we keep the actual file-path of the file on our disk
right next to the file, easily accessible as easily as accessing the
name."

```
rao-home/
  config                      settings (rmail's config format)
  contacts                    people you have named, own devices (rmail's format)
  ignore                      one address per line, with its level (hide | mark)
  rooms/
    <local tag>/
      name                    the room's full name ("coffee-shop/games"); its key
      island                  the local tag of the island this room belongs to
      members                 addresses known to be in this room, one per line
                              (address, port, who vouched, when)
      withheld                members you do not send to here, one per line
      where                   this folder's path, and the room's name
      log                     the messages, appended to, never rewritten
  waiting/
    <room name, escaped>/     messages from unvouched addresses, one file each,
                              opened but not parsed, kept a set time
  people/
    <contact>/
      <link name> -> ../../rooms/<local tag>
                              one link per top room this contact is a member
                              of, as you see it
```

- **`people/`** answers "what do I share with this person?" with an `ls`.
  The links are rebuilt from the rooms' member lists whenever one changes;
  the lists are the truth, the links are the view.
- **`log`** is plain text, one record per message: message id, the address
  it arrived from (or `me`), time written, time arrived, and the text.  A
  person can read a room with `cat` or `less`, back it up by copying the
  folder, and search it with `grep`.
- **Ids make delivery safe to repeat.**  A message delivered twice is
  recognised by its id and not filed again; the same id with different
  contents is an error.  rmail learned this in September 2026, when two
  daemons dialling each other at once filed one message eight times.


### Answers, 2026-09-25 (after the rewrite for this model)

1. **Filing a room under another without it being a child.**  Owner: "I
   guess so? There isn't anything structurally to prevent it in rmail...
   What do you think?"  Yes: filing is like putting a mail folder inside
   another in a mail client — it changes nothing for anyone else, so there
   is nothing to enforce.  **A room is either a declared child (the
   parent-membership rule applies) or filed under another on your own
   screen only (the entry's `filed-under`; no rule).**  Both show in one
   tree.  The owner's first example is filing.
2. **Someone leaving a parent room.**  Owner: "This is UI work, I think
   it'll make the most sense to users if we do it that way, but it's not
   technically required in a technical sense."  Read as: the client also
   removes them from the parent's child rooms; the server only refuses them
   as new members.  (Reading to be confirmed.)
3. **A key hint in front of each frame.**  Owner: "no way. If we need more
   speed, we make the decoding multithreaded. If there's just wayyyyy too
   many rooms, then users should just have multiple rooms instead of
   cramming them all into the same room. Multiple rooms means multiple
   mailboxes, right? Which means fewer keys to check. Right?"  No hint.
   Correction recorded: the cost grows with the number of rooms a server
   holds (one key each), not the people in a room, so splitting a room adds
   keys.  What does cut the keys tried is a **separate listening port** per
   group of rooms (a "mailbox"): a frame arriving on one port is tried only
   against that port's rooms; the port is already visible on every packet.
   Each key's attempt is independent, so trial opening splits across
   threads cleanly; roughly a microsecond per attempt on a 1 KB frame with
   AES instructions, so about a millisecond per frame at 1,000 rooms on one
   thread.
4. *(still open)* Suggested token length and word list.
5. **Silent members.**  Owner: "no but we can add something in the UI to
   automatically prune users who've been silent for a while, according to
   their specifications."  The server never removes a silent member; the
   client may offer pruning after a time the person chooses.

### Answers from the tally, 2026-09-25 (round 2)

- **Words in a suggested token** (`rooms.suggested-token-words`): **6**.
  Owner: "okay" to the builder's suggestion.  (Measured: two SHA-256 per
  guess, about 775,000 guesses a second on one CPU core; at an assumed
  5 billion a second on one graphics card, 4 words ≈ 4 days, 5 ≈ 90 years,
  6 ≈ 700,000 years.)
- **The same message arriving from a second address**
  (`log.same-id-new-address`): **duplicate**.  Owner: "duplicate.
  Sometimes people say things like "okay" or "duplicate" or "duplicate" or
  "duplicate" or "duplicate" or... teehee I'm being silly :)"
- **Ignoring an address** (`ignore.match`): **the whole IP address**, every
  port.  Owner: "IP. Sucks to suck, don't room with hackers or spammers I
  guess. Does make VPNs harder though..."  Consequence recorded: ignoring
  a VPN's exit address ignores everyone using that exit.
- **Record shape of the log** (`log.record-shape`): owner "okay" —
  read as the builder's leaning, **tsv** (to be confirmed).
- **Record shape confirmed: tsv.**  Owner: "okay... wink ;)"

### The parent-membership rule becomes detection (2026-09-25)

Asked to walk through a child room whose parent a home server does not
hold, the owner:

> Oh I see... I think the issue is that the "rooms" and "servers" are
> really just UI pretty-printing. A server is expected to have rooms
> sorted with slashes, like a directory structure, but it doesn't have to
> do that. And you could invite people to rooms even if they're not in
> higher tiers. The UI might flag them and highlight them in orange or
> something, to be manually reviewed by the user before sending messages
> to them... but it's a UI thing. At the end of the day, we can't control
> who gets to be in which room, because it's just a contact list on a
> person's computer. The "server" is really just for organizational
> purposes and holds no guarantees about authentication, however, we can
> *detect* when such things aren't true, and I believe we should.

("Server" here means a top-level room — the Discord-server-like level —
not the home server program.)

What follows:

- **Nothing about the tree is enforced; mismatches are detected.**  Every
  address is accepted into every room.  An address in a declared child
  room that is not a member of the parent, as this home server sees it, is
  added but **flagged**; the client shows it highlighted (orange).
- **A flagged member receives none of your messages until you review
  it.**  Approving makes it an ordinary member; declining withholds it.
- **A child room whose parent this home does not hold** cannot be checked,
  so its newcomers are flagged "cannot check".  The refuse/accept choice
  (`tree.unheld-parent-join`) is replaced by this.
- **Someone shut out of a parent** by a token change shows up flagged in
  its children, since the check is re-run whenever the parent's members
  change.
- The declared parent's only job is now this detection; filing and
  declaring are both organisation.
- **Someone who leaves a parent room** (issue 102, open question 2):
  **only flagged** in its children; nothing removes them.  Owner: "I think
  it's fine if they're just flagged if they no longer appear in the parent
  rooms that you know of. They won't know they're flagged for you - it's a
  personal setting."  A flag is private to your own home server and never
  sent.

### Five more from the tally, 2026-09-25

1. **Who may edit or delete** (`log.who-may-edit`): **anyone**.  Owner:
   "let's make the local copies part of the UI we build. That's the "the
   room shows which address the change came from" part."  The client shows
   the original, the change, and the address the change came from.
2. **Messages from a hidden address** (`ignore.hide-files`): **not saved**.
   Owner: "Not saved, and also, anyone can delete anyone else's messages,
   so ignoring someone, removing them from your list, would cause a
   catastrophic deletion cascade. Maybe that's... not ideal actually?
   Maybe we should not send the deletion notices when ignoring someone, and
   just delete them on our end and go quiet instead. Then, if we re-add
   them, the messages can be brought back because the sender will notice
   "hey this person on the sending list doesn't have this message, I
   should send it" on their next sync cycle."
   - No cascade exists: ignoring sends nothing, and a deletion from anyone
     is only a record ("hide message X") beside an original each reader
     keeps.  Ignoring already goes quiet.
   - **New for the periodic cross-check (issue 209): resending gaps.**  A
     sender whose server sees that an address on its send list lacks one of
     the sender's *own* messages sends it again.  Only its own messages
     (passing on others' would override their choice of whom to send to),
     and only to addresses it does not withhold.
   - **Going quiet covers the cross-check**: no summaries are sent to an
     ignored address, so it cannot tell it is ignored and does not resend
     every cycle.  Un-ignoring lets the next summary show the gaps, and the
     messages come back.
3. **A deleted message** (`log-deleted-view`): **the person chooses, in the
   client.**  Owner: "This is a UI concern, the user should be able to
   choose. It doesn't matter to the backend, really."  The server keeps it
   marked (built); the client offers a marked gap or hiding it.
4. **How far up the tree the membership check looks** (`tree-rule-depth`):
   **every room above**, not only the parent.
5. **Where rooms live.**  Owner: "I think we should have one mailbox per
   top-level "server" that a person is part of. The lower level "rooms"
   should be sorted according to the rules we're working through now."
   **Open**: is a mailbox (a) a folder per top-level room and everything
   under it, organisation only, or (b) also its own listening port, so a
   frame is tried only against that tree's keys (at the cost of one
   forwarded router port per top-level room, and an observer seeing which
   tree a frame belongs to)?  And where do direct messages live: each its
   own mailbox, one mailbox for all of them, or rmail's contacts?

### Mailboxes, 2026-09-25

- **A mailbox per top-level room, with its own listening port.**  Owner:
  "listening port, but we can accept from the same port and route to the
  right location if necessary. It's not recommended though."  A frame
  arriving on a mailbox's port is tried only against that mailbox's rooms'
  keys.  Two mailboxes may share a port — the server then tries every key
  on that port — but it says so each time (not recommended, so treated as
  a warning).
- **Direct messages share one mailbox.**  Owner: "this one is just a more
  simple rmail inbox. Just one."
- On the way it was recorded: rooms stay stored flat; a mailbox is a group
  with a port, named in each room's entry, listed with its port in a
  `mailboxes` file.  A child room belongs to its declared parent's
  mailbox.

### Five more from the tally, round 3 finds (2026-09-25)

1. **A flagged member who later passes the check**
   (`recipients.flag-after-passing`): **cleared** — the flag disappears by
   itself once the member matches the tree.
2. **How long an approval lasts** (`recipients-approval-lasts`): **until
   they leave**.
3. **A flagged member in `people/`** (`people-flagged-members`): **counts**
   toward the person's rooms.
4. **A child room whose parent this home does not hold**
   (`mailboxes.unheld-parent`): **its own mailbox and port.**  Owner: "we
   should make it so that they can merge into the parent rooms later on if
   possible."  Moving a room into its parent's mailbox changes its port, so
   the move is offered once the parent arrives (phase 1, reusing the
   waiting-mailbox move), and in phase 2 the move tells every member the new
   port, the old port still being tried for that room until they confirm.
   **Open:** merge automatically when the parent arrives, or ask first?
5. **Config lines nothing reads** (`log-retired-keys-in-config`).  Owner:
   "what do you mean by "home" here? Mailbox? I think it should probably
   just give an error if it doesn't recognize a value."  ("Home" is the one
   folder a home server keeps everything in — `config`, `mailboxes`, every
   room — so config is per home server, holding many mailboxes.)  **The
   config reader knows every setting name any module uses; any line it does
   not recognise is an error** — catching retired settings, typos and
   settings from a newer version alike.  Unknown values were already errors.
- **Merging a child into its parent's mailbox when the parent arrives**
  (`mailboxes.merge-when-parent-arrives`): **a config setting**, `automatic`
  or `ask`.  Owner: "config setting. Might be confusing though. I prefer
  automatic."  `automatic` is listed first (the demo's starting value); as
  with every setting, it must be written in config — no silent default.

### How rao-chat relates to rmail (2026-09-26)

Planning questions 6 (sharing code with rmail) and 7 (one program or two)
were asked as: lift rmail's networking into a library, copy it, or run
inside rmail's server.  The owner answered with a fourth way — the
strategem `strategems/other-peoples-software-as-a-rubric.md`, copied into
this project:

> check this out: /home/ritz/games/azeroth-core/wow-chat-2026/strategems/other-peoples-software-as-a-rubric.md
>
> that's what I think we should do. Make a copy to the project directory,
> then use it as a rubric. Generate issue files. Use those that are there.
> Describe everything you build with an issue file before you build it,
> and build it to the spec of what's already built. But don't build it
> exactly the same, do it different each time. Maybe make new notes. New
> observations. Make it designed slightly differently, try out new
> formations and finds.

- **rmail is read, not called or copied.**  Its rules — what the network,
  the operating system and the cipher require, and what its bugs taught —
  are written down in `notes/rmail-rubric/`, apart from its choices.
  rao-chat writes its own phase 2 to its own question and grades it with
  referee tests written from those rules.
- **Two programs** follows: rao-chat's home server is its own program.
  (To be confirmed; it is what the strategem implies.)
- **Every phase 2 issue carries a rubric part and a "where we differ"
  part**, each trying a formation of its own rather than rmail's shape.

### The server's shape, the outside port, and rooms as git history (2026-09-27)

Answers to the first questions gathered in `notes/rmail-rubric/open-questions.md`.

**The server's shape.**  Owner:

> yes we want to have one mailbox per "server". the config and ignore list
> can be managed in one collected UI - they'll each report to the RAM
> directories as detailed in shape C. Many data gatherers, one viewer,
> which is the android app or HTML page, both simply viewers for the rmail
> inboxes located in RAM, pulled from disk by the gatherers at startup,
> and synced periodically. The user types, and it creates messages and
> puts them in the right place - the user never needs to touch the
> filesystem at all, except for pointing out where to store the mailboxes.

- One process per mailbox (one per top-level room, one for direct
  messages): a **data gatherer**.  At start-up it loads its mailbox from
  disk into RAM, works in RAM, reports into RAM folders (the pipeline of
  shape C, split per mailbox as in shape B), and syncs to disk periodically.
- **One viewer** — the Android app or the web page — reads the RAM inboxes
  and writes what the person types into the right place.  Config and the
  ignore list are managed in the same viewer.  The person never touches
  the filesystem except to say where mailboxes are stored.

**A frame opening under two rooms' keys.**  Owner: "this is impossible. One
message cannot open correctly under two different tokens. It's hashed by
the token, of course it'd resolve to nonsense if any other key was tried to
open it."  Discussed below the answers (open).

**The outside port**: configured by the person, per mailbox, in the viewer
or the mailbox's config file.  (Formation F1 of the addresses note; no sweep
tool.)

**The log, the outbox, and git.**  Owner:

> not just the outbox. We build on_receive hooks that create text files
> and store them in git history, dynamically created per room. record
> changes. encourage changes and deletions. perhaps, if desired, a shared
> upstream, so you can coordinate more. In this one, the contact entry is
> the room, and the IPs are the contacts. We don't know anything else
> except what they sign it by. The last line in the message is the
> signature. Only one 80 character line is allowed.

- **Receive hooks** turn arriving messages into text files, committed to a
  **git repository per room**, made when the room is.  Edits and
  deletions are commits, so history keeps every version.  Optionally a
  **shared upstream** repository lets members coordinate.
- **Every address-and-port pair is a recipient** ("the contact entry is the
  room, and the IPs are the contacts"): a member with two addresses gets
  the message at both.  (Settles the contradiction between section 15 and
  issue 202.)
- **The signature is the message's last line, at most one line of 80
  characters.**

### Key-tying, the log and git, signatures (2026-09-27)

**A frame opening under two rooms' keys** is possible by deliberate
construction: AES-GCM's check value is computed from the sealed bytes by
linear arithmetic, so someone holding both keys can solve for one frame that
passes under both (published: Dodis, Grubbs, Ristenpart and Woodage 2018;
Len, Grubbs and Ristenpart 2020).  Only a member of both rooms could; the
harm is a frame landing in different rooms on different servers.  Owner:

> got it, so add the token to the front of each message, before the regular
> text but after the... nonce? I think? The thing that, when unencrypted,
> validates that it was correct. Inside the encrypted payload, and strip it
> out before displaying it to the user and after validating it. Right? That
> might need an rmail patch too...

- **Every sealed body begins with a key-tying value**, checked after
  opening and stripped before anything is shown.  Proposed: the token's
  32-byte fingerprint rather than the raw token — a short token such as
  `coffee` (6 bytes) could be matched by brute force (about 2^48 tries);
  32 bytes needs about 2^256.  It also lets trial opening stop at the first
  key whose opened body starts with the right value.
- The frame, outside to inside: length (4 bytes, clear) · nonce (12 bytes,
  clear) · sealed body = key-tying value + message · check value (16 bytes,
  clear).
- No rmail patch is needed for rao-chat (its own server, its own frames);
  rmail could adopt the same fix separately.

**The log and git.**  Owner, choosing reading (b): "this one, I think. Also
the output log for while it's been running is stored in git, even though
it's in RAM, we'll make backups periodically (like every sync cycle maybe)
and that gets put in git, always and eternally, once it's large enough we
split into a new file."

- The message log stays the delivery record (append-only, duplicate
  checks); receive hooks write a human-editable text copy of each message
  into the room's git repository.
- The server's running log (in RAM) is committed to git every sync cycle,
  kept forever, starting a new file past a size (a config setting).
  Open: which repository — the mailbox's own?

**Signatures.**  Owner: "body text, newline newline, signature. If the
signature is longer than one line, then it is the body text still, and the
last word is used."  A message is body, a blank line, then a one-line
signature of at most 80 characters.  If the part after the last blank line
is more than one line, it is all body, and its last word is used as the
signature.  (To confirm: a last line over 80 characters; and that an
ordinary closing paragraph is "signed" by its last word.)

### Git per mailbox, signatures settled, sharing edits (2026-09-27)

- **Each mailbox gets one git repository** (owner: "each mailbox gets a git
  repository"), holding its rooms' text copies (a folder per room) and the
  mailbox server's running log.  **File size before a new log file starts:**
  "as large as is possible to upload to github, defined in a config file
  with that as default."  GitHub refuses files over 100 MB pushed with git
  (it warns above 50 MB; its browser upload stops at 25 MB), so the value is
  100 MB, written into config when a home is made — a stated value in the
  file, not a silent default in code.
- **Signatures.**  Owner: "last line over 80 characters is a body text, not
  a signature. Use the last word of the body text as the signature if
  there's no signature."  So every message shows a signature: the
  one-line signature after a blank line when there is one (80 characters
  or fewer), otherwise the last word of the body.
- **Edits to the git copy reach others only through a shared upstream.**
  Owner: "only if they share an upstream. Ideally, git push when the server
  starts up and shuts down, and maybe whenever it does random IP checks -
  it's like once every 36 hours or so, I forget exactly how we planned it".
  Push at start-up, at shut-down, and at each public-address recheck (rmail
  rechecks "every day or two"; rao-chat's interval is a config setting).
  Open: pulling from the upstream — at the same moments?
- **Still open:** write a message to disk before acknowledging it, or accept
  losing the last few seconds before a power cut.  Until answered, built
  both ways, switched.
- **The mailbox's git repository also carries the running source code.**
  Owner: "the git repository should also have the source-code that the
  user is running, potentially in their own branch, and it should be freely
  downloadable for anyone sharing the same upstream."  This fits the AGPL,
  which asks that people using the software over a network can get its
  source.  Consequences recorded for the issues:
  - Pulling brings other people's branches, including their code.  Pulled
    code is never run or switched to automatically: running someone
    else's code is a choice the person makes by hand.
  - **Open:** a mailbox holds a whole tree of rooms, and a child room's
    members are a subset of its parent's.  One repository per mailbox,
    shared upstream, would let every member of the top room download the
    text copies of child rooms they are not in.  A branch or repository per
    room, or pushing only the rooms whose members all share the upstream?
- **Pulling from the shared upstream** at the same moments as pushing
  (start-up, shut-down, each public-address recheck).  Owner: "yeah probs".
