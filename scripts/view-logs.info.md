# view-logs

Follows one home's log (issue 605).

    scripts/view-logs [--running] [--no-follow] [service | home folder]

- Without `--running`: the service's log (`tail -F`, the last 50 lines
  first), the file named in the home's line of `installed-homes`.
- `--running`: the home's own running logs in its RAM folder (found by
  161's `home_ram`): the starter's, the device server's and each
  gatherer's, each line marked `[starter]`, `[devices]` or
  `[gatherer <mailbox>]`.  A home folder not listed works here.  A
  gatherer's running log is emptied each sync cycle once committed
  (177), so it shows only the lines not yet committed; a mailbox made
  while it follows is not followed.
- No argument: the one listed home, or, with several, a numbered list
  and a question (input that ends is no answer).  Never two homes at
  once (rmail #612).
- `--no-follow` prints and stops; `--project`, `--homes-list` as
  `restart-homes`.
