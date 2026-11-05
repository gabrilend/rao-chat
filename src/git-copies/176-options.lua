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
}
