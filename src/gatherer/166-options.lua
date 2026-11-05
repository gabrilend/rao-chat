-- 166-options.lua — the undecided choices in the gatherer (issue 211),
-- written down for the options tally (scripts/tally-options, issue 106)
-- and the demos.  Plain data: nothing here runs.
--
-- Every setting has no default (an unset one stops the program); the
-- first variant is what a demo home starts with.

local BUILT = "src/gatherer/163-gatherer.lua"
local TESTS = "src/gatherer/tests/167-test-gatherer.lua"

return {
    {
        id = "gatherer-acknowledge-after",
        question = "Is a message written to disk before it is acknowledged, or only to RAM?",
        waits_on = "owner",
        detail = "issue 211 (Intended Behavior, 'Write before acknowledging'; open question 1)",
        config_key = "gatherer.acknowledge-after",
        variants = {
            {
                name = "disk",
                summary = "The room's log is written to disk and fsynced before the answer: nothing acknowledged "
                    .. "is ever lost.",
                built_in = BUILT .. " (filed: force_to_disk before the answer)",
                tests = TESTS .. " (referees 1 and 2)",
                findings = "Referee 2 (2026-11-05): with the RAM folder discarded right after 10 answers, 0 of 10 were "
                    .. "missing from the disk home. Each answer waits for one fsync of the room's log.",
            },
            {
                name = "ram",
                summary = "The answer follows the write to RAM; disk catches up at the next sync cycle.",
                built_in = BUILT .. " (filed: no disk write)",
                tests = TESTS .. " (referees 1 and 2)",
                findings = "Referee 2 (2026-11-05): with the RAM folder discarded right after 10 answers, 10 of 10 were "
                    .. "missing from the disk home (the sync cycle had not run), and their senders "
                    .. "believe them delivered. A gatherer crash loses nothing: RAM files outlive it.",
            },
        },
        leaning = "disk: the owner's rule that an acknowledged message is never lost costs one fsync per frame.",
    },
    {
        id = "gatherer-ram-root",
        question = "Under which folder do the homes' RAM folders go?",
        waits_on = "owner",
        detail = "issue 211 (Intended Behavior, 'The RAM folder of one mailbox'; open question 9)",
        config_key = "gatherer.ram-root",
        variants = {
            {
                name = "/dev/shm/rao-chat",
                summary = "Linux's shared-memory filesystem: in RAM, gone at a reboot. Each home gets "
                    .. "<home folder's name>-<12 hex of its path> under it.",
                built_in = "src/gatherer/161-ram-folders.lua (choose_root, home_ram)",
                tests = TESTS .. " (referee 8)",
                findings = "Three homes under one root share no folder, log, failed-decryption file or "
                    .. "process id (referee 8). Where /dev/shm cannot be written, /tmp/rao-chat-ram is "
                    .. "used and the starter says so.",
            },
        },
        leaning = "/dev/shm/rao-chat: RAM on every Linux the project targets.",
    },
    {
        id = "gatherer-sync-interval",
        question = "How often is a mailbox's RAM copy written back to disk, in seconds?",
        waits_on = "owner",
        detail = "issue 211 (Intended Behavior, 'Every sync cycle')",
        config_key = "gatherer.sync-interval",
        variants = {
            {
                name = "30",
                summary = "Every 30 seconds, only the files that changed; once more at shut-down.",
                built_in = BUILT .. " (sync thread) and src/gatherer/161-ram-folders.lua (sync)",
                tests = TESTS .. " (referee 9)",
                findings = "With acknowledge-after = ram, a power cut loses at most this many seconds of "
                    .. "arrivals. With disk, it only delays the other files (members, delivered).",
            },
        },
        leaning = "30: rmail syncs about as often, and disk writes are batched.",
    },
    {
        id = "gatherer-address",
        question = "Which address do a home's mailboxes listen on and send from?",
        waits_on = "owner",
        detail = "issue 211; issue 210's rubric ('three homes on one machine must be three homes to the network')",
        config_key = "gatherer.address",
        variants = {
            {
                name = "any",
                summary = "Every address of the machine, and whatever source the system picks.",
                built_in = BUILT .. " (claim_port, connect)",
                tests = TESTS .. " (referee 8 sets 127.0.0.2, .3, .4 instead)",
                findings = "One home per machine needs nothing else. Homes sharing a machine each need "
                    .. "their own address, as the demo's do.",
            },
        },
        leaning = "any, for one home per machine.",
    },
    {
        id = "gatherer-connection-limit",
        question = "How many connections may one gatherer hold open at once?",
        waits_on = "owner",
        detail = "issue 211 (Rubric R2; open question 6)",
        config_key = "gatherer.connection-limit",
        variants = {
            {
                name = "64",
                summary = "64 at once; a 65th closes the one held longest.",
                built_in = BUILT .. " (listener)",
                tests = TESTS .. " (referee 3)",
                findings = "Referee 3 (2026-11-05): with 500 connections trickling a byte a second, B held "
                    .. "at most 64 and filed a genuine frame on connection 501 after 0.35 s, at about "
                    .. "13 MB of memory; without the limit it held all 500. It is a bound on what a peer "
                    .. "can make the gatherer hold, not a ban, so it is not the flood defence 203 rules out.",
            },
        },
        leaning = "64: far below select()'s 1024 descriptors.",
    },
    {
        id = "gatherer-frame-deadline",
        question = "How long may a connection take to deliver one whole frame, in seconds?",
        waits_on = "owner",
        detail = "issue 211 (Rubric R2; open question 8)",
        config_key = "gatherer.frame-deadline",
        variants = {
            {
                name = "10",
                summary = "10 seconds for the whole frame (rmail's 10 s was per read).",
                built_in = BUILT .. " (listener)",
                tests = TESTS .. " (referee 3)",
                findings = "A peer trickling a byte a second is closed after 10 s however many bytes it "
                    .. "sends; a per-read deadline would hold it forever.",
            },
        },
        leaning = "10: one deadline for the whole frame.",
    },
}
