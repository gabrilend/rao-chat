-- 059-options.lua — the undecided choices in the recipients module (issues
-- 103 and 103a), written down for the options tally (scripts/tally-options,
-- issue 106) and the phase 1 demo.
--
-- Each entry is one question the owner (or some later state of the project)
-- has to settle.  Every switchable variant listed is built and tested; the
-- home's config file picks the one in use, and the first variant listed is
-- the one the demo starts with.  The "findings" are what building and
-- testing each variant actually showed, so the choice can be made on facts.
-- Plain data: nothing here runs.
--
-- Answered and fixed in place (round 3, 2026-09-25), so no longer listed:
-- ignore-hide-files (a hidden address's messages are not filed) and
-- ignore-match (an ignore entry covers every port at its address).

return {
    {
        id = "ignore-scope",
        question = "Is the ignore list only for the whole home, or may you also ignore an address in one room only?",
        waits_on = "owner",
        detail = "issue 103a open question 2",
        config_key = "ignore.scope",
        variants = {
            {
                name = "home",
                summary = "One list, every line covers every room.",
                built_in = "src/recipients/042-ignore-list.lua (check_scope, how_ignored)",
                tests = "tests/048-test-ignore.lua",
                findings = "Simplest; matches the planning document ('one address per line'). A one-room "
                    .. "request is refused with an error naming the setting; a one-room line found in the "
                    .. "file (hand-edited, or left from a switch of this setting) is reported at the next "
                    .. "lookup rather than silently applied or skipped.",
            },
            {
                name = "home-and-room",
                summary = "Lines may name one room's local tag instead of '*'.",
                built_in = "src/recipients/042-ignore-list.lua (check_scope, entry_matches)",
                tests = "tests/048-test-ignore.lua",
                findings = "Same file, one extra column (the scope, '*' or a local tag), so both variants share "
                    .. "the format and switching home -> home-and-room needs no rewrite. Refuses a tag not "
                    .. "held here. The bell rings on that room's tag (101 accepts a tag or '' for 'ignore'), so a "
                    .. "listener can tell which room changed. A person ignored "
                    .. "in one room can still be added to your other rooms.",
            },
        },
        leaning = "home: nobody has asked for per-room ignoring, and a per-room 'hide' is close to what "
            .. "withholding plus not opening the room already gives.",
    },
    {
        id = "recipients-flag-after-passing",
        question = "A flagged member later passes the check (the room above arrives and holds them, or they join it). Does the flag stay until you review it, or clear by itself?",
        waits_on = "owner",
        detail = "found while building 103 round 3 (flagged members); read only when a flagged member passes a re-check",
        config_key = "recipients.flag-after-passing",
        variants = {
            {
                name = "kept",
                summary = "The flag stays until you approve or decline; its word is not changed.",
                built_in = "src/recipients/041-recipients.lua (AFTER_PASSING, recheck_flagged_in)",
                tests = "tests/054-test-child-room.lua ('flag-after-passing = kept')",
                findings = "Nothing disappears unseen: every flag is reviewed by a person, as the owner "
                    .. "described ('manually reviewed by the user'). The cost: a member of a child room made "
                    .. "before its parent arrived stays orange and unsent-to even after the parent shows "
                    .. "they belong, until someone clicks approve.",
            },
            {
                name = "cleared",
                summary = "The flag line is deleted; they are an ordinary member again.",
                built_in = "src/recipients/041-recipients.lua (AFTER_PASSING, recheck_flagged_in)",
                tests = "tests/054-test-child-room.lua ('flag-after-passing = cleared')",
                findings = "The common case (join a child first, its parent later) fixes itself when the "
                    .. "parent arrives. A flag can then vanish without the person ever seeing it; messages "
                    .. "they wrote while it was flagged were never sent to that member (phase 2's resending "
                    .. "of gaps, issue 209, would fill them on the next cross-check).",
            },
        },
        leaning = "cleared: a flag says 'this does not match the tree'; once it matches there is nothing to review.",
    },
    {
        id = "recipients-approval-lasts",
        question = "How long does approving a flagged member last?",
        waits_on = "owner",
        detail = "found while building 103 round 3: without remembering approvals, a member of a child whose parent is not held here would be flagged again on every members change",
        config_key = "",
        variants = {
            {
                name = "until-they-leave",
                summary = "An 'approved' line is kept in the flagged file until the address's confirmed leave.",
                built_in = "src/recipients/041-recipients.lua (approve, flag_rows, confirm_leave)",
                tests = "tests/054-test-child-room.lua ('an approved member is not flagged again')",
                findings = "Re-checks skip approved members, so approval is asked once. A member who "
                    .. "later drops out of the parent too is NOT flagged again (you already said yes to "
                    .. "them here); leaving and coming back starts over, since the leave deletes the line.",
            },
            {
                name = "until-the-answer-changes",
                summary = "The approval holds only for the answer it was given against (no or cannot-check). Not built.",
                built_in = "not built",
                tests = "none",
                findings = "Would need the approved line to keep the answer it overrode; a cannot-check "
                    .. "approval would come back as a flag when the parent arrives and says no. Cheap to "
                    .. "build if wanted: the line would read '<address> <port> approved-<answer>'.",
            },
        },
        leaning = "until-they-leave: approval is a statement about a person, not about the tree.",
    },
    {
        id = "recipients-shared-address-label",
        question = "When two of your direct-message rooms hold the same address, how is that member shown in a group room?",
        waits_on = "owner",
        detail = "found while building 103 (a member is shown by the label of the direct message holding its address)",
        config_key = "recipients.shared-address-label",
        variants = {
            {
                name = "all-labels",
                summary = "Every such label, sorted, joined with ', '.",
                built_in = "src/recipients/041-recipients.lua (shown_as)",
                tests = "tests/055-test-shown-as.lua",
                findings = "Read from config only when the case happens. Honest about the ambiguity and still "
                    .. "tells you who it probably is. Happens when one person has two direct-message rooms "
                    .. "(two tokens) or two people share an address and port — the second would be a "
                    .. "configuration mistake on their side.",
            },
            {
                name = "address",
                summary = "Fall back to showing the address itself.",
                built_in = "src/recipients/041-recipients.lua (shown_as)",
                tests = "tests/055-test-shown-as.lua",
                findings = "Never shows a possibly wrong name, but a person with two direct-message rooms "
                    .. "turns into a bare address in every group, which looks like a stranger.",
            },
        },
        leaning = "all-labels: it never hides a name you gave, and the case is rare.",
    },
    {
        id = "recipients-two-addresses",
        question = "When a member moves to a new address, is the old address kept until it leaves, or dropped?",
        waits_on = "owner",
        detail = "issue 103 open question 2",
        config_key = "",
        variants = {
            {
                name = "keep",
                summary = "The new address is added beside the old; the old stays until its own confirmed leave.",
                built_in = "src/recipients/041-recipients.lua (add_member, heard_from, confirm_leave)",
                tests = "tests/049-test-members.lua ('a move adds the new address beside the old')",
                findings = "What the address rule already gives: nothing removes an address but its own "
                    .. "confirmed leave. The old address keeps being sent to until it leaves; silent_since "
                    .. "lists it once it goes quiet, so a client can offer pruning.",
            },
            {
                name = "drop-old",
                summary = "The old address is removed when the new one appears. Not built.",
                built_in = "not built",
                tests = "none",
                findings = "Cannot be built from what a group room knows: the sender of a message is "
                    .. "unknowable by design, so nothing ties the new address to the old one. The only link "
                    .. "is a direct-message room listing both, and dropping on that basis would let whoever "
                    .. "writes a direct-message entry remove members of group rooms — the very thing "
                    .. "'removed only by its own say-so' exists to stop.",
            },
        },
        leaning = "keep: it is what the rule says, and drop-old has no trustworthy trigger.",
    },
    {
        id = "recipients-withheld-after-return",
        question = "If someone you withheld leaves and later comes back, are they still withheld?",
        waits_on = "owner",
        detail = "found while building 103",
        config_key = "",
        variants = {
            {
                name = "still-withheld",
                summary = "The withheld line outlives the membership.",
                built_in = "src/recipients/041-recipients.lua (confirm_leave keeps the withheld file)",
                tests = "tests/052-test-withheld-and-send.lua ('a withheld member who leaves and comes back')",
                findings = "Your choice survives a leave-and-return, the same way the ignore list survives "
                    .. "syncing. The withheld file can hold non-members; send_list ignores them.",
            },
            {
                name = "forgotten",
                summary = "Leaving clears the withheld line. Not built.",
                built_in = "not built",
                tests = "none",
                findings = "A leave-and-rejoin (which anyone holding the token can do) would undo your "
                    .. "choice silently.",
            },
        },
        leaning = "still-withheld.",
    },
    {
        id = "recipients-last-heard-source",
        question = "What records when a member was last heard from: the arrival path calling heard_from, or this module listening to the log's bell?",
        waits_on = "state",
        detail = "found while building 103; waits on phase 2's arrival path and on 105's bell saying which message was filed",
        config_key = "",
        variants = {
            {
                name = "arrival-calls",
                summary = "Whoever files an arriving message calls heard_from(tag, address, port, written).",
                built_in = "src/recipients/041-recipients.lua (heard_from)",
                tests = "tests/053-test-leave-and-heard.lua",
                findings = "One call per message, one entry rewrite at most (none when an older message "
                    .. "arrives late: the time only moves forward). Also re-adds a returning member and "
                    .. "applies the ignore refusal and the tree flag in the same step. Needs phase 2 (or the demo) "
                    .. "to make the call.",
            },
            {
                name = "log-bell",
                summary = "Listen for 'log' and read the newest records. Not built.",
                built_in = "not built",
                tests = "none",
                findings = "The bell says only 'something was filed in this room', not which message, so the "
                    .. "listener would have to re-read the log each ring — the first model's heard-from "
                    .. "mode did exactly that and its cost grew with the log's length.",
            },
        },
        leaning = "arrival-calls.",
    },
}
