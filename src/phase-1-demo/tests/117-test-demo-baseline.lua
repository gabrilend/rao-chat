-- 117-test-demo-baseline.lua — checks how the demo picks its starting settings.
--
-- Uses the good sample options project: the first listed variant becomes
-- each key's value, and input/phase-1-demo.config text can replace it with
-- another built variant, but never with an unknown key or an unbuilt value.

return function(DIR, harness)
    local check, check_error = harness.check, harness.check_error
    local gather = require("100-gather-options")
    local tool = require("105-demo-baseline")
    local options = gather.gather(DIR .. "/src/phase-1-demo/tests/samples/good-src")

    local settings, variants = tool.from_options(options)
    check("one setting per switchable choice (2 of 3)", #settings == 2, #settings)
    check("settings sorted by key", settings[1].key == "alpha.shape" and settings[2].key == "beta.mode")
    check("first listed variant is the default", settings[1].value == "lines" and settings[2].value == "one")
    check("source says first listed", settings[1].source == "first listed")
    check("variants listed per key", #variants["beta.mode"] == 3 and variants["beta.mode"][3] == "three")
    check("a non-switchable choice sets nothing", variants[""] == nil)

    local wanted = tool.parse_input("# my leanings\n\n  beta.mode = two  \nalpha.shape=blocks\n")
    check("parse skips comments and blanks", #wanted == 2, #wanted)
    check("parse trims and keeps line numbers", wanted[1].key == "beta.mode" and wanted[1].value == "two"
          and wanted[1].line == 3)
    check("parse accepts no spaces round =", wanted[2].value == "blocks")
    check_error("parse refuses a line that is not key = value",
                function() tool.parse_input("beta.mode two\n") end, "line 1 is not 'key = value'")
    check("an empty input file wants nothing", #tool.parse_input("") == 0)

    local replaced = tool.apply_input(settings, variants, wanted)
    check("two keys replaced", replaced == 2, replaced)
    check("the input's value is taken", settings[2].value == "two" and settings[1].value == "blocks")
    check("source says input", settings[2].source == "input/phase-1-demo.config")

    check_error("an unknown key in input is refused",
                function() tool.apply_input(settings, variants, tool.parse_input("gamma.x = y")) end,
                "no options file records the key gamma.x")
    check_error("an unbuilt value in input is refused",
                function() tool.apply_input(settings, variants, tool.parse_input("beta.mode = four")) end,
                "is not a built variant (built: one, two, three)")

    local duplicate = { choices = {
        { id = "a", config_key = "k", variants = { { name = "x" } }, module = "m" },
        { id = "b", config_key = "k", variants = { { name = "y" } }, module = "n" },
    } }
    check_error("one key recorded by two choices is refused",
                function() tool.from_options(duplicate) end, "recorded by two choices")
end
