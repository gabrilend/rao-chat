-- Sample options file for the tally's tests: two choices, one waiting on the
-- owner and one on state; `tests` written as a list, the rest as strings.
return {
    {
        id = "alpha-shape", question = "Which shape should alpha records take?",
        waits_on = "owner", detail = "open question 8", config_key = "alpha.shape",
        variants = {
            { name = "lines", summary = "One line each.", built_in = "src/alpha/002-a.lua",
              tests = { "tests/a1.lua", "tests/a2.lua" }, findings = "31 bytes per record." },
            { name = "blocks", summary = "A labelled block each.", built_in = "src/alpha/002-a.lua",
              tests = { "tests/a3.lua" }, findings = { "58 bytes per record.", "multi-line text is easy." } },
        },
        leaning = "lines, because it is half the size.",
    },
    {
        id = "alpha-wait", question = "Does alpha wait for beta?",
        waits_on = "state", detail = "issue 102: beta's listener order", config_key = "",
        variants = {
            { name = "wait", summary = "Wait.", built_in = "src/alpha/003-b.lua",
              tests = "tests/a4.lua", findings = "not measured yet" },
        },
        leaning = "wait, until beta lands.",
    },
}
