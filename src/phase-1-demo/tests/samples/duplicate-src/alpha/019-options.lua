-- Sample: the id "same" is used here and in beta; the tally must refuse it.
return {
    { id = "same", question = "q", waits_on = "owner", detail = "d", config_key = "",
      variants = { { name = "a", summary = "s", built_in = "b", tests = "t", findings = "f" } },
      leaning = "l" },
}
