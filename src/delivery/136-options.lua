-- 136-options.lua — the undecided choices in the delivery module (issue
-- 202), written down for the options tally (scripts/tally-options, issue
-- 106) and the phase 1 demo.  Plain data: nothing here runs.
--
-- The two retry settings have no default (an unset one stops the program,
-- as every undecided choice does); the values listed are rmail's, the
-- starting values the issue names, and the first variant is what a demo
-- home starts with.  Any whole number of seconds is accepted by 131; these
-- are the ones tried.

return {
    {
        id = "delivery-retry-floor",
        question = "How long after a failed delivery attempt is the first retry, in seconds?",
        waits_on = "owner",
        detail = "issue 202 (Intended Behavior, 'Retries slow down and never give up'; open question 4)",
        config_key = "delivery.retry-floor",
        variants = {
            {
                name = "30",
                summary = "rmail's floor: the first retry about 30 seconds after a failure.",
                built_in = "src/delivery/131-retry-timer.lua (settings, new, failed)",
                tests = "src/delivery/tests/137-test-delivery.lua (referees 1, 4, 5, 6)",
                findings = "With doubling, 30 s reaches a 2-hour ceiling after 8 failed attempts (rmail's "
                    .. "additive growth took about 20). A lost answer is resent about 30 s later and "
                    .. "answered 'duplicate' (referee 1). Sends are immediate, so the floor is never a "
                    .. "polling period.",
            },
        },
        leaning = "30: rmail's value, and only failures wait for it.",
    },
    {
        id = "delivery-retry-ceiling",
        question = "What is the longest wait between retries to an unreachable pair, in seconds?",
        waits_on = "owner",
        detail = "issue 202 (Intended Behavior, 'Retries slow down and never give up')",
        config_key = "delivery.retry-ceiling",
        variants = {
            {
                name = "7200",
                summary = "rmail's ceiling: an unreachable pair is tried about every 2 hours, forever.",
                built_in = "src/delivery/131-retry-timer.lua (settings, failed)",
                tests = "src/delivery/tests/137-test-delivery.lua (referee 6)",
                findings = "Twelve attempts a day per unreachable pair (11-13 in a given day, as the deck "
                    .. "is cut); after 72 hours away everything arrives within one ceiling of the pair "
                    .. "returning, or at once if it sends first (open question 1's decision).",
            },
        },
        leaning = "7200: rmail's value; one attempt per pair every two hours costs nothing.",
    },
}
