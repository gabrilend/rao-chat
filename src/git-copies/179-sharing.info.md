# 179-sharing.lua

Sharing a mailbox's text copies through a shared upstream (issue 215b).
Upstreams are the mailbox repository's own git remotes, added by the
person with `git remote add`: `upstream` for the mailbox, and
`room-<fingerprint>` for one room's own upstream.  A repository with no
such remote shares nothing.  `moment(s, why)` is one pull-then-push per
remote: fetch (in the background, killed after `git.share-deadline`
seconds, while the gatherer's other threads run), merge the remote's
`rooms` (a conflict is aborted, reported and retried at the next moment,
and nothing of the rooms goes to that remote while it stands), then push
a commit on the remote's tip carrying only the room folders this home may
share there, plus `code/<home name>`, and `running-log/<home name>` to
`upstream` only with `git.push-running-log = yes`.  Which folders:
`git.upstream-rooms` = `only-fully-shared` (a room whose member list holds
every pair listed in the repository's `rao.upstream-pair` lines) or
`repository-per-room` (each room only to its own remote).  Pulled code is
a remote-tracking ref, never merged, checked out or run.  `settings(home)`
reads the three settings strictly, only when a remote exists.
`RAO_SHARE_BROKEN` selects 180's broken versions.
