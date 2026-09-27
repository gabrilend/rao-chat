# Strategem: Other People's Software as a Rubric

A strategem is a data flow pattern that recurs across multiple areas of the
project and has been proven useful enough to standardize. This one, in the
owner's words (2026-09-26):

> we should use other people's software as a rubric, not cheat answers on a
> test

## What it means

Most of what this project builds has a neighbour that already works: the
AzerothCore server, the playerbots module, the Lua engine, the stock game
data, the client's own files. Each of them answered some question
correctly. It was rarely *our* question.

- **Cheating** is copying their answer: calling their function, pasting
  their table, adopting their rule because it is there. The answer was
  graded against their question, so it arrives carrying their assumptions,
  and those surface later as bugs nobody chose.
- **Using a rubric** is reading their answer to learn what a correct answer
  must satisfy: which steps are required, which checks guard them, which
  edge cases they already hit. Then writing our own answer to our own
  question, and grading it against those requirements.

The rubric is the part of their work that is true for everyone (the
server's rules, the client's limits). The answer is the part that was a
choice.

## The shape

1. **Find the neighbour** that solves something close. Read it, don't call
   it yet.
2. **Separate rules from choices.** Rules: what the server will refuse,
   what the client can display, what must happen in what order. Choices:
   defaults, randomness, policy, anything that could have been otherwise.
3. **Write our answer** for our question, keeping their rules and making
   our own choices.
4. **Grade it with their rules, written down independently**: a test or
   referee built from the rules, not from our code. A referee that shares
   code with the thing it checks grades nothing. The owner's comparison
   (2026-09-26): "oh, like the RGPL? 'you can copy my source-code but only
   the parts you can show me are reproducible'": what carries over is
   what can be shown to hold, checked by our own means.
5. **Teach the method, not the source.** A comment explains the rule the
   code follows and why, so it can be re-derived; where the rule was
   learned is our own detail and needn't be named. The owner, 2026-09-26:
   "the source is your own detail. you don't have to tell anyone where you
   learned something [...] instruction in methods, not exact-ids". (Naming
   the file still helps when a rule may change upstream and needs
   re-checking; then it is a pointer for the reader, not a credit.)

## Examples in the project

- **Buddy creation (617a3, `modules/mod-buddies/src/buddies_create.cpp`).**
  The bot module's character factory makes a valid character, but picks
  the faction at random: right for random bots, wrong for "a dwarf for this
  Alliance owner". Its *steps* were the rubric (a name from the module's
  name list, looks from CharSections.dbc, the server's own create, save,
  cache entry); the race is ours.
- **The buddy talent referee (617g, `scripts/test-buddy-talents`).**
  Written from the server's learn-a-talent rules (`Player::LearnTalent`)
  and basic's cap, not from the spender. It was checked against three
  deliberately broken spenders and failed each one; a referee copied from
  the spender would have passed them all.
- **The talent capstone (155g).** The bot module has its own vanilla-style
  limit (row 6, middle column only). Read as a rubric it said "row 6 is
  the line"; taken as an answer it would have been wrong for affliction,
  whose one-point talent sits right of centre. Our rule counts ranks.
- **Missing prerequisites (617g).** Two talents name prerequisites the
  client file doesn't hold. The server skips such a check; the spender
  followed the server's behaviour (the rubric), not the file's literal
  data (which would have locked both talents forever).
- **Prices and currencies (155t).** The client's price list and currency
  list are rules: they say what a vendor window and a currency tab can
  show. Designs are graded against them (1000 honor exists as a price,
  2000 does not) instead of assumed.

## Counter-pattern: trusting a precedent without grading it

B008 links a module into the build with a symbolic link. B036 (617a1)
needed the same thing, but B008's module has never existed, so its link
was never tested by a build. Taken as an answer, "B008 does it, so it
works" would have copied an untested assumption. B036 copies the folder
instead, and says why in its header.

## When NOT to use this strategem

- When the neighbour's answer *is* our answer: the question is identical
  and the choice was already ours to make the same way (stock item
  creation rolling a random suffix on a bought item, 155u). Then use it,
  and say so.
- When reading costs more than the problem: a one-line config key doesn't
  need a rubric.

## Related

- `strategems/precompute-derivable-data.md` — the other standing pattern.
- The upstream patch system (`patches/`, the `upstream-patch-system`
  skill): we change other people's software only through reversible
  patches, which is this strategem's rule for the cases where their code,
  not ours, has to move.

## In rao-chat (copied from wow-chat-2026, 2026-09-26)

Copied as written; the examples above are wow-chat's.  rao-chat adopted
the strategem for its phase 2, where rmail (`/home/ritz/programs/r-mail`)
is the neighbour: it already seals frames, acknowledges, retries, keeps
addresses current and finds housemates.  The owner, asked whether rao-chat
should share rmail's code as a library, copy it, or run inside it:

> check this out: [this file] that's what I think we should do. Make a
> copy to the project directory, then use it as a rubric. Generate issue
> files. Use those that are there. Describe everything you build with an
> issue file before you build it, and build it to the spec of what's
> already built. But don't build it exactly the same, do it different each
> time. Maybe make new notes. New observations. Make it designed slightly
> differently, try out new formations and finds.

So, for rao-chat:

- **rmail is read, not called.**  Its rules (what the network, the
  operating system and the cipher require; what its bugs taught) are
  written down in `notes/rmail-rubric/`, one note per area, apart from its
  choices (timings, defaults, policies, structure).
- **Each phase 2 issue carries its rubric** and says where rao-chat
  deliberately differs — "different each time": a new formation per issue,
  tried and recorded, not rmail's shape re-typed.
- **Referees come from the rules**, written independently of both rmail's
  code and ours, and are checked against deliberately broken versions.
