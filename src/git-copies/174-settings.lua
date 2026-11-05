-- 174-settings.lua — every config setting name the text copies read
-- (issue 215), handed to 101's config reader.  Plain data.
--
-- git.home-name — this home's name in its mailbox repositories: the
--   commit author (`<name> <name@rao-chat.invalid>`) and the code branch
--   `code/<name>` (open question 4, decided 2026-11-05).  Letters,
--   digits, '.', '_' and '-'.  No default: a name chosen by the person,
--   since a pushed author name says who ran the home (215b).

-- git.log-file-size — the most bytes one file of the running log's branch
--   may hold (issue 215a); a new file starts before a line would pass it.
--   Written into config when a home is made: 100000000 (GitHub refuses a
--   pushed file over 100 MiB and warns over 50 MiB; this is under both
--   100 MB and 100 MiB).

-- git.upstream-rooms — `only-fully-shared` or `repository-per-room`: which
--   rooms' copies a shared upstream gets (issue 215b, open question 1,
--   built both ways).  No default; read only when the mailbox's
--   repository has a remote (`upstream` or `room-<fingerprint>`).
--   The copies are plain text: whoever runs or can fetch an upstream
--   reads every room pushed there (decision 5 in 215b).
-- git.push-running-log — `yes` or `no`: whether `running-log/<home name>`
--   is pushed to `upstream` (215a's open question 1).  No default; read
--   as git.upstream-rooms is.
-- git.share-deadline — whole seconds a fetch or a push may take before it
--   is killed and reported failed (structure R4).  No default; read as
--   git.upstream-rooms is.

return {
    "git.home-name",
    "git.log-file-size",
    "git.upstream-rooms",
    "git.push-running-log",
    "git.share-deadline",
}
