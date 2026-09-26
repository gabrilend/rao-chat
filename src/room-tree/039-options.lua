-- 039-options.lua — the undecided choices in the room-tree module, written
-- down for the options tally (scripts/tally-options, issue 106).
--
-- Each entry is one question the owner (or some later state of the project)
-- has to settle.  Where a choice is switchable, every variant is built and
-- tested and the home's config file picks the one in use.  The findings
-- are what building and testing each variant showed, so the choice can be
-- made on facts.  Plain data: nothing here runs.
--
-- Round 2 ("a room is a contact") retired the first model's choices:
-- tree-parent-disclosure (tree.parent-disclosure), tree-disclosure-refresh,
-- tree-where-per-recipient, tree-untell-on-removal (nothing is disclosed
-- about a room to anyone without its token any more) and tree-slash-in-path
-- (labels may hold "/" by issue 101; the path escapes it, as answered).
--
-- Round 3 fixed three answered choices in place and removed them here:
-- tree-unheld-parent-join (config tree.unheld-parent-join, refuse /
-- accept) went when the rule became detection — a parent not held gives
-- the answer cannot-check; tree-rule-depth (parent-only was built) is
-- answered every room above, now built; tree-leaving-the-parent
-- (client-cleans-up was built, with its child_rooms_holding lookup) is
-- answered "only flagged": the re-check lookup failing_below replaces it.

return {
    {
        id = "tree-filing-loop",
        question = "You filed room A under room B. Later a declared parent arrives (you are invited to it) "
            .. "that puts B inside A. The tree now goes round in a ring. What happens?",
        waits_on = "owner",
        detail = "issue 102 open question 1 (filing), found while building; read only when a ring is found",
        config_key = "tree.filing-loop",
        variants = {
            {
                name = "unfile",
                summary = "Every room in the ring that was filed (not declared) is unfiled; declared "
                    .. "parents win, as they do everywhere else in the tree.",
                built_in = "src/room-tree/021-room-tree.lua (ring_unfile, mend_rings)",
                tests = { "tests/035-test-rings.lua" },
                findings = {
                    "In the test, home filed under programming, then ritz (declared child of home, declared "
                        .. "parent of programming) arrives: home is unfiled and the tree becomes "
                        .. "home/ritz/programming, where rewritten, no error reaches the arrival.",
                    "Unfiling happens inside the 'created' ring and rings 'filed' itself, so 104 hears it too.",
                    "Your own placement is changed without asking you; the client should say so.",
                },
            },
            {
                name = "refuse",
                summary = "The change that closed the ring raises an error; the room stays on disk and every "
                    .. "question about the tree errors until someone unfiles by hand.",
                built_in = "src/room-tree/021-room-tree.lua (ring_refuse, mend_rings)",
                tests = { "tests/035-test-rings.lua" },
                findings = {
                    "The arrival of an invitation fails because of a filing on your own screen: the error "
                        .. "reaches whoever made the room (in phase 2, the joining code), not you.",
                    "Until unfiled, tops(), forest() and check_member() all error on this home.",
                },
            },
        },
        leaning = "unfile: filing is your own screen only, and a declared parent already wins over filing "
            .. "in every other case; refusing lets a screen arrangement block joining a room.",
    },
    {
        id = "tree-member-match",
        question = "When is an address 'a member of the parent'? The same (address, port) pair as "
            .. "written, or the same machine however it is written (a hostname and its IP)?",
        waits_on = "owner",
        detail = "issue 102, found while building the parent-membership rule",
        config_key = "",
        variants = {
            {
                name = "exact-pair",
                summary = "The address as written and the port as a whole number must both be equal.",
                built_in = "src/room-tree/021-room-tree.lua (holds_pair)",
                tests = { "tests/034-test-membership.lua" },
                findings = {
                    "girlfriend.example.org 7777 is answered 'no' (and so flagged) in a child whose parent "
                        .. "holds 192.168.1.20 7777, even if one names the other.",
                    "The same address at another port is another member (another home server), as the "
                        .. "contract says.",
                    "A port passed as text is an error, not a silent mismatch.",
                },
            },
            {
                name = "resolved",
                summary = "Look hostnames up and compare the machines they reach (not built).",
                built_in = "not built",
                tests = "none",
                findings = {
                    "Would make the rule depend on the network at the moment of asking, and on DNS answers "
                        .. "that can differ by server; two servers could disagree about the same member.",
                    "Ignoring (103a) is now fixed at the whole IP address, every port (owner, round 2 "
                        .. "tally); this check still compares the port. The two differ: ignoring is about "
                        .. "a machine, membership about one home server on it.",
                },
            },
        },
        leaning = "exact-pair: every server compares the same text, so every server reaches the same answer.",
    },
    {
        id = "tree-removed-shelf",
        question = "When a room is removed from this home, where do the rooms you filed under it go?",
        waits_on = "state",
        detail = "issue 102, found while building; no room is removed in phase 1 (leaving is phase 2)",
        config_key = "",
        variants = {
            {
                name = "unfile",
                summary = "They are unfiled: each rises to its own declared parent, or the top.",
                built_in = "src/room-tree/021-room-tree.lua (unfile_orphans, on 'removed-room')",
                tests = { "tests/032-test-tree.lua" },
                findings = {
                    "The removed room's own place is gone by the time the bell rings (the folder is already "
                        .. "removed), so 'move up to where the removed room was' cannot be worked out.",
                },
            },
            {
                name = "take-its-place",
                summary = "They move to where the removed room sat (not built).",
                built_in = "not built",
                tests = "none",
                findings = {
                    "Needs the remover to ring before removing, or to pass the room's old place; the bell "
                        .. "carries only the tag.",
                },
            },
        },
        leaning = "unfile, unless phase 2's leaving wants to keep a folder's contents together.",
    },
}
