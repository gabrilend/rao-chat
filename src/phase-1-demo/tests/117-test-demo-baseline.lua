-- 117-test-demo-baseline.lua — checks how the demo picks its starting settings.
--
-- Uses the good sample options project with a hand-made list of declared
-- setting names (as 101's declared_settings() gives them): exactly the
-- declared names get a setting; the first listed variant becomes each
-- recorded key's value, and input/phase-1-demo.config text can replace it
-- with another built variant, but never with an undeclared key or an
-- unbuilt value.  A declared name no options file records needs input/ to
-- give it a value; a recorded key nobody declares is refused.

return function(DIR, harness)
    local check, check_error = harness.check, harness.check_error
    local gather = require("100-gather-options")
    local tool = require("105-demo-baseline")
    local options = gather.gather(DIR .. "/src/phase-1-demo/tests/samples/good-src")
    local declared = {
        ["alpha.shape"] = { module = "alpha", file = "src/alpha/018-settings.lua" },
        ["beta.mode"]   = { module = "beta",  file = "src/beta/038-settings.lua" },
    }

    check_error("the declared names are required",
                function() tool.from_options(options) end, "needs the declared setting names")

    local settings, variants = tool.from_options(options, declared)
    check("one setting per declared name (2)", #settings == 2, #settings)
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

    check_error("an undeclared key in input is refused",
                function() tool.apply_input(settings, variants, tool.parse_input("gamma.x = y")) end,
                "no module declares the setting gamma.x")
    check_error("an unbuilt value in input is refused",
                function() tool.apply_input(settings, variants, tool.parse_input("beta.mode = four")) end,
                "is not a built variant (built: one, two, three)")

    -- a recorded key that no settings list declares: the demo could not set it
    local short = { ["alpha.shape"] = declared["alpha.shape"] }
    check_error("a recorded key nobody declares is refused",
                function() tool.from_options(options, short) end,
                "beta.mode (choice")

    -- a declared name with no options entry: a setting with no value until input/ gives one
    local more = { ["alpha.shape"] = declared["alpha.shape"], ["beta.mode"] = declared["beta.mode"],
                   ["gamma.fixed"] = { module = "gamma", file = "src/gamma/058-settings.lua" } }
    local with_fixed, fixed_variants = tool.from_options(options, more)
    check("a declared name with no options entry still gets a setting", #with_fixed == 3
          and with_fixed[3].key == "gamma.fixed" and with_fixed[3].value == nil, #with_fixed)
    check_error("left without a value, it is refused, naming it",
                function() tool.apply_input(with_fixed, fixed_variants, {}) end,
                "setting gamma.fixed is declared by gamma")
    tool.apply_input(with_fixed, fixed_variants, tool.parse_input("gamma.fixed = 12\n"))
    check("input/ can give it any value", with_fixed[3].value == "12"
          and with_fixed[3].source == "input/phase-1-demo.config")

    local duplicate = { choices = {
        { id = "a", config_key = "k", variants = { { name = "x" } }, module = "m" },
        { id = "b", config_key = "k", variants = { { name = "y" } }, module = "n" },
    } }
    check_error("one key recorded by two choices is refused",
                function() tool.from_options(duplicate, { k = { module = "m", file = "f" } }) end,
                "recorded by two choices")
end
