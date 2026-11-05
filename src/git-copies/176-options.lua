-- 176-options.lua — the undecided choices in the text copies (issue 215),
-- written down for the options tally (scripts/tally-options, issue 106)
-- and the demos.  Plain data: nothing here runs.
--
-- The setting has no default (an unset one stops the program); the first
-- variant is what a demo home starts with.

return {
    {
        id = "git-home-name",
        question = "What is a home called in its mailbox repositories (commit author, code/<name>)?",
        waits_on = "owner",
        detail = "issue 215 (open question 4, decided 2026-11-05: a setting with no default)",
        config_key = "git.home-name",
        variants = {
            {
                name = "home",
                summary = "A name the person chooses; the demo's homes use their own letters. Commits are "
                    .. "authored '<name> <name@rao-chat.invalid>', and the program goes to code/<name>.",
                built_in = "src/git-copies/172-git.lua (check_name, identity); src/gatherer/164-home-starter.lua",
                tests = "src/git-copies/tests/175-test-git-copies.lua (the code-branch check)",
                findings = "Two homes sharing an upstream (215b) need different names: their code/ branches "
                    .. "would otherwise be one branch.",
            },
        },
        leaning = "a name the person chooses when the home is made.",
    },
    {
        id = "git-log-file-size",
        question = "How large may one file of the running log's branch grow?",
        waits_on = "owner",
        detail = "issue 215a (Intended Behavior, 'Split before the limit'; open question 2)",
        config_key = "git.log-file-size",
        variants = {
            {
                name = "100000000",
                summary = "100,000,000 bytes, written into config when a home is made: under GitHub's 100 MiB "
                    .. "refusal for a pushed file, and under 100 MB.",
                built_in = "src/git-copies/177-running-log.lua (138's numbered split, line by line); "
                    .. "src/room-folders/002-room-folders.lua (open_home writes the line)",
                tests = "src/git-copies/tests/178-test-running-log.lua (referees 1 and 4)",
                findings = "Referee 1 (2026-11-05), with the limit at 1,000 bytes: 10,000 bytes in cycles, one of "
                    .. "2,500, gave files of at most 1,000 bytes holding every line once.",
            },
        },
        leaning = "100000000, as the owner asked (\"as large as is possible to upload to github\").",
    },
    {
        id = "git-upstream-rooms",
        question = "Which rooms' copies does a shared upstream get?",
        waits_on = "owner",
        detail = "issue 215b (Intended Behavior, 'Which rooms are shared'; open question 1)",
        config_key = "git.upstream-rooms",
        variants = {
            {
                name = "only-fully-shared",
                summary = "One upstream per mailbox (the remote `upstream`); a room's folder goes to it only when "
                    .. "everyone listed as sharing it (rao.upstream-pair) is on the room's member list.",
                built_in = "src/git-copies/179-sharing.lua (plan, shared_commit)",
                tests = "src/git-copies/tests/180-test-sharing.lua (referee 5)",
                findings = "Referee 5 (2026-11-05): a top-room member fetching the upstream finds no child-room "
                    .. "folder in any ref. The issue's wording (every member listed as sharing) pushed the child room.",
            },
            {
                name = "repository-per-room",
                summary = "Each room's folder goes only to its own remote, room-<fingerprint>, so what a member can "
                    .. "fetch follows the rooms whose upstreams they can read.",
                built_in = "src/git-copies/179-sharing.lua (plan, shared_commit)",
                tests = "src/git-copies/tests/180-test-sharing.lua (referee 5)",
                findings = "Referee 5 (2026-11-05): fetching the top room's upstream finds no child-room folder. "
                    .. "One branch per room on one upstream gave it away.",
            },
        },
        leaning = "only-fully-shared: one remote to set up, and a room is shared only with people already in it.",
    },
    {
        id = "git-push-running-log",
        question = "Is the running log's branch pushed to the shared upstream?",
        waits_on = "owner",
        detail = "issue 215a open question 1; issue 215b open question 3",
        config_key = "git.push-running-log",
        variants = {
            { name = "no", summary = "Never pushed: it names every address the home talked to, and when.",
              built_in = "src/git-copies/179-sharing.lua (plan)", tests = "src/git-copies/tests/180-test-sharing.lua",
              findings = "Referee 1 (2026-11-05): with no, the upstream has no running-log branch." },
            { name = "yes", summary = "Pushed to `upstream` with the rooms and the code.",
              built_in = "src/git-copies/179-sharing.lua (plan)", tests = "src/git-copies/tests/180-test-sharing.lua",
              findings = "Referee 1 (2026-11-05): with yes, the upstream has the branch." },
        },
        leaning = "no, as 215a proposed.",
    },
    {
        id = "git-share-deadline",
        question = "How long may one fetch or push to a shared upstream take?",
        waits_on = "owner",
        detail = "issue 215b (rubric: one failing destination must not delay anything else)",
        config_key = "git.share-deadline",
        variants = {
            { name = "60", summary = "A minute, then the fetch or push is killed and reported failed.",
              built_in = "src/git-copies/179-sharing.lua (background)",
              tests = "src/git-copies/tests/180-test-sharing.lua (referee 6)",
              findings = "Referee 6 (2026-11-05): with a black-holed remote and a 3 s deadline, delivery went on "
                  .. "and the failure was reported within the deadline." },
        },
        leaning = "60.",
    },
}
