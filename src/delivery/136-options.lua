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
    {
        id = "failed-decryption-file-size",
        question = "How large may one failed-decryption file grow, in bytes, before a new one starts?",
        waits_on = "owner",
        detail = "issue 203 (Intended Behavior, 'Split by size')",
        config_key = "failed-decryption.file-size",
        variants = {
            {
                name = "1000000",
                summary = "About 1 MB: some 8,000 lines of about 125 bytes each.",
                built_in = "src/delivery/139-failed-decryption.lua (settings, open), src/delivery/138-size-split.lua",
                tests = "src/delivery/tests/140-test-failed-decryption.lua (referee 3)",
                findings = "A line is about 125 bytes for an IPv4 source. fail2ban reads only new lines, "
                    .. "and a jail's findtime is minutes, so a file holding thousands of lines is plenty; "
                    .. "with 3 files a flood costs at most about 3 MB of RAM.",
            },
        },
        leaning = "1000000: thousands of lines per file, a few MB of RAM at worst.",
    },
    {
        id = "failed-decryption-files-kept",
        question = "How many failed-decryption files are kept in RAM, the newest included?",
        waits_on = "owner",
        detail = "issue 203 (Intended Behavior, 'Split by size')",
        config_key = "failed-decryption.files-kept",
        variants = {
            {
                name = "3",
                summary = "The current file and two older ones.",
                built_in = "src/delivery/138-size-split.lua (rotate)",
                tests = "src/delivery/tests/140-test-failed-decryption.lua (referee 3)",
                findings = "fail2ban needs only the newest file; the older ones are for a person "
                    .. "looking at what happened shortly before.",
            },
        },
        leaning = "3: enough to look back over a flood, bounded at three files.",
    },
    {
        id = "callback-answer-time",
        question = "How long does a call-back check wait for the stated pair's answer, in seconds?",
        waits_on = "owner",
        detail = "issue 204 (Intended Behavior, 'No answer means not confirmed'; open question 5)",
        config_key = "callback.answer-time",
        variants = {
            {
                name = "8",
                summary = "rmail's connect timeout: about 8 seconds for the connection and the answer.",
                built_in = "src/delivery/142-call-back.lua (settings, ask)",
                tests = "src/delivery/tests/144-test-call-back.lua (referee 4)",
                findings = "A check with no answer in time is not dropped: it stays unconfirmed and is "
                    .. "tried again on 202's timers (30 s, then doubling), so a short wait costs only "
                    .. "a later retry, never a wrong confirmation.",
            },
        },
        leaning = "8: rmail's limit for one exchange; silence never confirms, so a short wait is safe.",
    },
    {
        id = "address-recheck-earliest",
        question = "How soon after a check is the home's public address checked again, at the earliest, in seconds?",
        waits_on = "owner",
        detail = "issue 212 (Intended Behavior, 'Rechecked while running'; open question 11)",
        config_key = "address.recheck-earliest",
        variants = {
            {
                name = "86400",
                summary = "rmail's window starts at 24 hours.",
                built_in = "src/delivery/150-public-address.lua (settings, Watcher:run)",
                tests = "src/delivery/tests/151-test-reach.lua (referees 4, 5)",
                findings = "After a check nobody answered, the next comes after a quarter to a half of "
                    .. "this, so 6 to 12 hours.",
            },
        },
        leaning = "86400: rmail's 24 to 48 hours, around the owner's 'once every 36 hours or so'.",
    },
    {
        id = "address-recheck-latest",
        question = "How long after a check is the home's public address checked again, at the latest, in seconds?",
        waits_on = "owner",
        detail = "issue 212 (Intended Behavior, 'Rechecked while running'; open question 11)",
        config_key = "address.recheck-latest",
        variants = {
            {
                name = "172800",
                summary = "rmail's window ends at 48 hours.",
                built_in = "src/delivery/150-public-address.lua (settings, Watcher:run)",
                tests = "src/delivery/tests/151-test-reach.lua (referee 5)",
                findings = "A move is noticed within this long; each wait is drawn from the kernel's "
                    .. "random source, so homes started together do not check together.",
            },
        },
        leaning = "172800: with 86400, an average of 36 hours.",
    },
    {
        id = "address-hostname",
        question = "Does the home have a hostname to state in hellos?",
        waits_on = "owner",
        detail = "issue 212 (Intended Behavior, the table of pairs)",
        config_key = "address.hostname",
        variants = {
            {
                name = "none",
                summary = "No hostname: hellos state the public address, IPv6 and housemate pairs.",
                built_in = "src/delivery/149-reach.lua (hostname, own_pairs)",
                tests = "src/delivery/tests/151-test-reach.lua",
                findings = "A hostname is stated with the outside port, beside the public address, "
                    .. "never instead of it.",
            },
        },
        leaning = "none, until the person has one.",
    },
}
