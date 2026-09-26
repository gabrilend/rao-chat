-- Sample: a variant with no findings; the tally must refuse it.
return {
    { id = "x", question = "q", waits_on = "owner", detail = "d", config_key = "",
      variants = { { name = "a", summary = "s", built_in = "b", tests = "t" } },
      leaning = "l" },
}
