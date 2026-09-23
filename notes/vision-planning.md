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

Conversations are **rooms**, and rooms are arranged like **folders in a
tree**: a room can hold rooms inside it, to any depth.  Every room has its
own list of the people its messages go to, so a parent room and its child
can have entirely different people in them.  A room has at least two people
(you and one other); there is no upper limit.

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
- **Not a shared, agreed membership list.**  Nobody holds "the" list of a
  room's members.  Each person holds their own list of who they send to
  (section 3).
- **Not a mail client.**  rmail stays the place for long, file-shaped
  messages and attachments.

---

## 2. Words used in this document

| word | meaning |
|---|---|
| **home server** | the program each person runs on a computer at home (in rmail, "the daemon").  It holds their rooms, talks to other home servers, and serves their clients. |
| **contact** | another person, known to your home server by a name you choose, a shared secret (token), and one or more addresses.  Same idea and file format as rmail's contacts. |
| **device** | one of your own clients (a phone, a browser) paired with your home server; in the contacts file, an entry marked `own = true`, as in rmail. |
| **room** | a place messages are written, with a name, a parent room (or none), and a recipient list.  Rooms nest like folders. |
| **room id** | a long random identifier every room gets when it is made.  It is what travels between servers; names never do (section 4). |
| **recipient list** | the people *your* messages in a room go to.  Yours alone; everyone else in the room keeps their own. |
| **tree** | a room and everything nested in it.  A person may see one of your trees as several separate trees, if they are in some of its rooms and not others. |
| **message** | one entry in a room: who wrote it, when, and the text. |
| **delivery** | a message moving from the writer's home server to a reader's. |
| **live connection** | a connection a client holds open to its home server, so new messages arrive the moment they land. |

---

## 3. Rooms and who hears what

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

### Trees, and trees that look separate

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

### Names belong to the reader

A room's name is a label each person keeps for themselves.  You can have
two rooms called `programming`; a friend can call your `programming` room
`ritz-code`.  Names are how people sort; room ids are how servers match.
Owner: "it's just a name that we sort ourselves, it doesn't necessarily
refer directly to the filesystem."

---

## 4. Rooms on disk

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

## 5. Home server ↔ home server: what comes from rmail

rao-chat reuses rmail's way of reaching people.  Each item below is
something rmail already does and has had its bugs found in.

- **Contacts file.**  `name.field = value` lines.  Several addresses per
  contact (`ip`, `ip[N]`, `port[N]`), home-network addresses (`local-ip`),
  IPv6, hostnames, a shared token, and `own = true` for your own devices.
  An address that works moves to the front.
- **Encryption.**  Every message between servers is sealed with
  AES-256-GCM under a key derived from the pair's token (`SHA-256(token)`),
  in length-prefixed frames with a random 12-byte nonce.  Who sent a frame
  is known by which contact's key opens it.  No names travel in the clear.
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

1. **Rooms on the home server** — room folders, the tree, recipient lists,
   the `people/` links, the message log and ids.
2. **Server-to-server delivery** — rmail's networking, sending at once,
   acknowledgements, retries, duplicates ignored, late messages placed in
   order, rooms made on first arrival.
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
2. **Whom your replies go to.**  When someone adds you to a room and you
   reply, who receives it: only the person who added you; everyone you
   have received a message from in that room; or everyone on the adder's
   list, which would mean each message carries its sender's recipient list
   (as rmail's `to:` lines are visible to the sender only, today)?
3. **What travels with a message to place its room in a tree.**  To let a
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
5. **Trusting the web page.**  Serve the web client only on the home
   network; over HTTPS with a certificate (hard for a home address); or
   have people keep a copy of the page on their computer and open it from
   there, so only the encrypted connection crosses the internet?
6. **Sharing code with rmail.**  Lift rmail's networking into a library
   both use; copy it and let the two drift; or run rao-chat inside rmail's
   daemon on its own port?
7. **One home server program or two?**  rmail's daemon and rao-chat's
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
12. **Editing and deleting sent messages.**  Allowed, allowed for a short
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
  client-side way of sorting.  See section 3.
- **Licence** (2026-09-23): the GNU Affero General Public License, version
  3 or later, as rmail.  `LICENSE` holds the full text.  rmail's extra
  permission for hook scripts is not carried over; rao-chat has no hooks
  yet.
