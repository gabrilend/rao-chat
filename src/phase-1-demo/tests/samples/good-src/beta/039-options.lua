-- Sample options file for the tally's tests: one owner choice with three variants.
return {
    {
        id = "beta-mode", question = "Which beta mode?",
        waits_on = "owner", detail = "open question 2", config_key = "beta.mode",
        variants = {
            { name = "one", summary = "First.", built_in = "x", tests = "t", findings = "f" },
            { name = "two", summary = "Second.", built_in = "x", tests = "t", findings = "f" },
            { name = "three", summary = "Third.", built_in = "x", tests = "t", findings = "f" },
        },
        leaning = "two.",
    },
}
