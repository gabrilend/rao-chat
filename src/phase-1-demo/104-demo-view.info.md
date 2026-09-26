# 104-demo-view.lua

Draws each record made by `103-demo-sections.lua` as lines of text.  One
function per scene, same names as the scenes, each taking that scene's
record and giving a list of string; `tally` also takes the
`101-show-options` module and draws with its `summary_lines`, so the demo
and `scripts/tally-options` print the same table.  Loaded with
`require("104-demo-view")`.

An attempt is shown as `answered <word>` (the call ran; some refusals are
answers, such as 103's `added-flagged` and `ignored`) or `ERROR: <the
module's own words>` (it raised).

| function | takes | gives |
|---|---|---|
| `entries(record)` | entries record | `ls rooms/`, `find rooms -type f`, each `entry` exactly as written, what the one reader read, the lists by kind, the two unpaired-address refusals |
| `tokens(record)` | tokens record | three six-word suggestions with the words counted and bits, the typed token read back, the duplicate refusal, the room before and after its token changed |
| `tree(record)` | tree record | both homes' trees with fingerprints, shopping's `where`, the fingerprint match table; 102's check answers; each room's members, send list and `flagged` file after adding, approving, a leave from the top room, declining; the `withheld` file; the unheld-parent room |
| `mailboxes(record)` | mailboxes record | each room's mailbox, the `mailboxes` file, rooms by mailbox, the keys tried per port, the shared port with 101's reports, per `mailboxes.merge-when-parent-arrives` variant: attic and trunk's mailbox before and after loft arrives, the mergeable list, the person's yes (ask), the mailboxes afterwards; the declared setting names and the three refusals of an undeclared name |
| `members(record)` | members record | send lists and the `withheld` file before and after withholding |
| `leaving(record)` | leaving record | the unconfirmed leave, the confirmed one, speaking again, the entry with `heard[N]` |
| `ignoring(record)` | ignoring record | the `ignore` file, the hidden address on another port, each level, the room as shown (none: the text; mark: "(someone you ignore spoke)"; hide: nothing), the member filter answers |
| `people(record)` | people record | `ls people/`, every link with its room's label, the coder's links under each collision mode |
| `log(record)` | log record | answers, the file in arrival order, the screen in written order, the raw log, bytes per message; the two-homes order comparison |
| `tally(record, show)` | tally record, module | the tally summary |

An ignore level other than `none`, `mark`, `hide` is an error in
`ignoring`, not a guess.
