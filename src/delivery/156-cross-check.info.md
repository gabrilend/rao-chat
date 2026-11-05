# 156-cross-check.lua

Periodic cross-checking between members (issue 209).
- `settings`: `crosscheck.interval` and `crosscheck.window`, read
  strictly.
- `agreed`, `fingerprint`: a record's agreed part (kind, id, written,
  target, text; never `from` or `arrived`) and the first 16 bytes of its
  SHA-256 as 32 hex.
- `summary_record`: what this home holds from the window, by id and
  fingerprint, with its own pairs.
- `fill_gaps`: this home's own records, meant for a stated pair on its
  send list that is not ignored, that the summary lacks, are made
  missing again (130's `forget`) and the stage is woken.
- `answer`: what 133 answers a `summary` or `versions` with (an ack, or
  this home's versions of the ids that differ).
- `raise`: a discrepancy, once, in the room's `conflicts` file, the
  stage's `conflicts` list, and the `on_conflict` seam.
- `attempt`: one job, run by 134's stage: 207's members digest, then the
  summary, then any versions.

Load with `require("156-cross-check")`.
