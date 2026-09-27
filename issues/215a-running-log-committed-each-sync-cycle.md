# 215a — The running log, committed every sync cycle and split by size

**Phase:** 2 — Server-to-server delivery
**Parent issue:** 215
**Blocked by:** 211, 215
**Blocks:** 210

## Current Behavior

Nothing exists.  211 gives each gatherer a `running-log` file in its RAM
folder; 215 gives each mailbox a git repository.

## Intended Behavior

The owner (2026-09-27): "the output log for while it's been running is
stored in git, even though it's in RAM, we'll make backups periodically
(like every sync cycle maybe) and that gets put in git, always and
eternally, once it's large enough we split into a new file."  And on the
size: "as large as is possible to upload to github, defined in a config
file with that as default."

- **Every sync cycle** the lines the gatherer's running log gained since
  the last cycle are appended to the current numbered file in the mailbox
  repository and committed.  Kept forever.
- **On its own branch**, `running-log/<home name>`, never mixed into the
  rooms' text copies, so the rooms' history and the server's history can
  be read, pushed and pruned apart.
- **Split before the limit, never after**: a new file
  (`running-log/<home name>/<four-digit number>.log`) starts **before** an
  append would carry the current file past config `git.log-file-size`
  (bytes).  The value is written into config when a home is made:
  100,000,000 bytes — GitHub refuses files over 100 MiB pushed with git
  (it warns above 50 MiB), so a file must stay under the limit, not pass
  it.  A single cycle's lines larger than the limit are split across
  files.
- **The RAM file is emptied only after the commit succeeds**; a failed
  commit keeps the lines in RAM and says so, and the next cycle retries.
- **Each line** is as the gatherer wrote it: an ISO-8601 UTC stamp, the
  stage (`listener`, `opener`, `filer`, `sender`, `starter`), and the text.

## Rubric

- **A limit is a ceiling to stay under, not a line to cross** (GitHub's
  own rule, read as a rubric: a push containing a file over its limit is
  refused whole).  "A new file past a size" would, read literally, make
  files larger than the setting.
- **Anything that can repeat writes a bounded amount** (structure R16):
  per file, by the split; the whole history is unbounded by the owner's
  choice ("always and eternally").
- **A running log records who was talked to and when** (rmail moved its
  log into RAM for this reason, its issue 397): committing it keeps that
  forever on disk, and pushing it would share it (open question 1).
- **Record the other side has it only when it confirms** (structure R21),
  read here for git: the RAM lines are dropped only after the commit.

## Where we differ

rmail's log lives in RAM, rotated at 5 MiB keeping one old copy: bounded,
lost at reboot.  The formation here is **the log as an append-only series
of size-bounded files on a branch of its own** — nothing is ever rotated
away, and a branch keeps it apart from what may be shared.

- **Gains:** the whole running history survives reboots; files never
  exceed what the chosen host accepts; a separate branch makes "do not
  push the log" a one-line choice.
- **Costs:** disk grows forever; a git repository with many large files is
  slow to clone (GitHub documents a recommended repository size well
  below what years of logs can reach — the size tool, not this issue,
  should report it).

## Referees

1. **Never over the limit.**  With the limit set to 1,000 bytes and a fake
   clock, run cycles whose lines total 10,000 bytes, including one cycle of
   2,500 bytes: every file is at most 1,000 bytes; concatenating them in
   order gives every line once.  *Broken:* splitting after passing the
   limit; dropping the oversize cycle.
2. **Kept on failure.**  Make the commit fail (a locked index): the RAM
   lines stay, the next cycle commits them, no line lost or doubled.
3. **Apart from the rooms.**  After cycles, the rooms' branch has no log
   files and the log branch has no room copies.
4. **Stated, not defaulted.**  A config without `git.log-file-size` is an
   error naming the setting.

## Suggested Implementation Steps

1. The size split (shared with 203's failed-decryption files).
2. The branch and the append-and-commit at each sync cycle.
3. Writing the value into config when a home is made (101's home-making
   path gains the line; declared in this module's settings).
4. The referees above.

## Blockers that are not the owner's

- Needs 211 (the running log, the sync cycle) and 215 (the repository).

## Open questions

1. **Push the running log to a shared upstream?**  It names every address
   the home talked to, and when.  Proposed: the log branch is never pushed
   unless config says so (215b).
2. **Bytes or MiB**: the planning document says "100 MB"; GitHub's limit is
   100 MiB (104,857,600 bytes).  100,000,000 is under both — confirm.
3. **The failed-decryption lines** (203): in this log too, or only in
   their own file?

## Related documents

- `notes/vision-planning.md` section 15 ("Key-tying, the log and git";
  "Git per mailbox")
- `notes/rmail-rubric/structure-and-defences.md` ("Logging", R16, R21)
