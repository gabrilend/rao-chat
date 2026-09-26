-- Sample: waits_on is neither "owner" nor "state"; the tally must refuse it.
return {
    { id = "x", question = "q", waits_on = "someone", detail = "d", config_key = "",
      variants = { { name = "a", summary = "s", built_in = "b", tests = "t", findings = "f" } },
      leaning = "l" },
}
