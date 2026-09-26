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

return {
    {
        id = "tree-unheld-parent-join",
        question = "A child room whose declared parent you do not hold (you were invited to the child "
            .. "but not the parent): may anyone holding the child's token join it here, or nobody, since "
            .. "this server cannot see the parent's members to apply the tiers-of-trust rule?",
        waits_on = "owner",
        detail = "issue 102, found while building the parent-membership rule; read only when the case happens",
        config_key = "tree.unheld-parent-join",
        variants = {
            {
                name = "refuse",
                summary = "Nobody new is added to such a room on this server until the parent is held here.",
                built_in = "src/room-tree/021-room-tree.lua (unheld_refuse, may_join)",
                tests = { "tests/034-test-membership.lua", "tests/036-test-with-neighbours.lua" },
                findings = {
                    "Keeps 'lower rooms have only members that exist in higher rooms' true on this server "
                        .. "without exception.",
                    "The owner's programming friend (in programming, not in ritz or home) could never add "
                        .. "anyone to programming from their own server: every hello would be refused there, "
                        .. "though the others' servers accept it. Members' lists then differ by server.",
                    "103's add_member passes the refusal on as 'not-in-parent' with the reason 'the parent "
                        .. "of <label> is not held here'.",
                },
            },
            {
                name = "accept",
                summary = "Anyone holding the child's token is added, as in a top room; the tier above is "
                    .. "enforced only by servers that hold the parent.",
                built_in = "src/room-tree/021-room-tree.lua (unheld_accept, may_join)",
                tests = { "tests/034-test-membership.lua" },
                findings = {
                    "The room stays usable for someone invited to it alone (the friend in programming).",
                    "The rule still holds on every server that holds the parent, so an outsider added here "
                        .. "is still refused by the parent's members' servers: they would hear the outsider "
                        .. "only through servers like this one.",
                },
            },
        },
        leaning = "accept: the invitation to the child is itself someone's judgement, and refusing makes "
            .. "the room one-way for exactly the people the owner's first example describes. The servers "
            .. "that can see the parent still hold the line.",
    },
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
                    "Until unfiled, tops(), forest() and may_join() all error on this home.",
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
                    "girlfriend.example.org 7777 is refused in a child whose parent holds 192.168.1.20 7777, "
                        .. "even if one names the other.",
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
                    "103a's ignore.match has a 'host' variant (same address, any port); the two rules "
                        .. "should probably agree.",
                },
            },
        },
        leaning = "exact-pair: every server compares the same text, so every server reaches the same answer.",
    },
    {
        id = "tree-leaving-the-parent",
        question = "When a member leaves (or is shut out of) a parent room, who removes them from the "
            .. "child rooms below it?",
        waits_on = "owner",
        detail = "issue 102 open question 2 (reading to be confirmed by the owner: 'This is UI work')",
        config_key = "",
        variants = {
            {
                name = "client-cleans-up",
                summary = "The server only refuses them as new members of the children; the client asks "
                    .. "which child rooms hold them and offers to remove them.",
                built_in = "src/room-tree/021-room-tree.lua (child_rooms_holding)",
                tests = { "tests/034-test-membership.lua", "tests/036-test-with-neighbours.lua" },
                findings = {
                    "child_rooms_holding walks declared children only (filing carries no rule), all levels, "
                        .. "top-down, and also finds a grandchild holding someone the child no longer does.",
                    "Until the client acts, a member who left the parent keeps receiving the child's "
                        .. "messages from this server; members are removed only by their own confirmed leave "
                        .. "(103), so the client's removal would be withholding.",
                },
            },
            {
                name = "server-withholds",
                summary = "On a member leaving a parent, the server withholds them in every child room "
                    .. "(not built).",
                built_in = "not built",
                tests = "none",
                findings = {
                    "Needs a leave to reach the tree (a bell kind for it, phase 2's confirmed leave).",
                },
            },
        },
        leaning = "client-cleans-up: it is what the owner said; the lookup the client needs is built.",
    },
    {
        id = "tree-rule-depth",
        question = "Does the parent-membership rule check only the direct parent, or every room above?",
        waits_on = "owner",
        detail = "issue 102, found while building",
        config_key = "",
        variants = {
            {
                name = "parent-only",
                summary = "Only the declared parent's members are checked; its members were checked against "
                    .. "its own parent when they joined.",
                built_in = "src/room-tree/021-room-tree.lua (may_join)",
                tests = { "tests/034-test-membership.lua" },
                findings = {
                    "The sister (in home, not ritz) is refused in programming because ritz does not hold "
                        .. "her; after she joins ritz she is accepted, without programming consulting home.",
                    "If someone leaves home but stays in ritz (nobody cleaned up), they can still be added "
                        .. "to programming: the chain holds only as well as the clean-up above.",
                },
            },
            {
                name = "every-ancestor",
                summary = "Every held declared ancestor must hold the member (not built).",
                built_in = "not built",
                tests = "none",
                findings = {
                    "Cheap to build (the snapshot has the chain), but an unheld room in the middle of the "
                        .. "chain stops the walk, so it can only be as strict as the rooms you hold.",
                },
            },
        },
        leaning = "parent-only, until the clean-up question above is settled; every-ancestor is the answer "
            .. "if the owner wants the server, not the client, to keep the tiers true.",
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
