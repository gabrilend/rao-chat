-- 119-options.lua — the undecided choices found while building the phase 1 demo,
-- written down for the options tally (scripts/tally-options).
--
-- Plain data in the contract's shape ("The options tally" in
-- docs/phase-1-module-contract.md); nothing here runs.

return {
    {
        id = "demo-baseline",
        question = "When a demo scene shows one choice's variants, what should every OTHER choice be set to "
            .. "in that scene's homes?",
        waits_on = "owner",
        detail = "issue 106 open question 1: found while building; every module refuses to run with any "
            .. "choice unset, so the demo must pick something for the choices a scene is not about",
        config_key = "",
        variants = {
            {
                name = "first-listed",
                summary = "The first variant each builder listed in their options file, replaced key by key "
                    .. "by any line in input/phase-1-demo.config.",
                built_in = "src/phase-1-demo/105-demo-baseline.lua (from_options, parse_input, apply_input)",
                tests = { "src/phase-1-demo/tests/117-test-demo-baseline.lua",
                          "src/phase-1-demo/tests/116-test-demo-run.lua" },
                findings = {
                    "Needs nothing from the builders beyond the options files they already keep; a new "
                        .. "choice reaches the demo with no edit to it. Round 2 showed this working: the "
                        .. "rewritten modules brought 9 new config keys (ignore.*, people.direct-message-link, "
                        .. "log.who-may-edit, rooms.suggested-token-words, ...) and the demo set them all "
                        .. "with no change to the baseline code (16 keys on 2026-09-25 20:21).",
                    "Round 2: 105 now lists its leaning first, so for the log keys first-listed IS the "
                        .. "leaning; other modules still list in whatever order they wrote. The unvaried "
                        .. "settings are therefore partly an accident of listing order unless input/ says "
                        .. "otherwise.",
                    "A key a module reads but no options file lists stops every scene that makes a room "
                        .. "(seen at 20:19: people.direct-message-link, read by 104 on every rebuild, was "
                        .. "not yet listed, nor was 101's rooms.suggested-token-words; only 1 of 9 scenes (the tally) ran until they were).",
                    "An input line naming an unknown key or an unbuilt value stops the demo before any "
                        .. "scene runs, naming the line.",
                },
            },
            {
                name = "builder-leaning",
                summary = "Each builder's leaning. Not built: `leaning` is prose, so the contract would need "
                    .. "a machine-readable field (for example leaning_variant = \"suffix-id\") in every "
                    .. "options file.",
                built_in = "not built",
                tests = "none",
                findings = "Would need a contract change and an edit to all five options files; "
                    .. "input/phase-1-demo.config already lets the owner run the demo under any set of "
                    .. "variants without it, and asking every builder to list their leaning first gets "
                    .. "the same effect with no new field.",
            },
        },
        leaning = "first-listed, with the owner's picks written into input/phase-1-demo.config as they "
            .. "are made; the demo then shows the decided project, and only the undecided keys fall back "
            .. "to listing order.",
    },
}
