-- 111-test-gather.lua — checks the tally's gathering half on sample options files.
--
-- The samples under tests/samples/ stand in for the real modules' options
-- files: one good project (two modules, three choices, plus a decoy file one
-- folder too deep, and a retired 019-options.lua-done beside the live one,
-- as round 2 leaves them), one with no options files, and four each broken in one
-- way.  Gathering must read the good one exactly and refuse each broken one
-- with a message that names the fault.

return function(DIR, harness)
    local check, check_error = harness.check, harness.check_error
    local gather = require("100-gather-options")
    local samples = DIR .. "/src/phase-1-demo/tests/samples"

    -- the good project
    local record = gather.gather(samples .. "/good-src")
    check("two options files found", #record.files == 2, #record.files)
    check("three choices gathered", #record.choices == 3, #record.choices)
    check("files in path order (alpha first)", record.files[1].module == "alpha",
          record.files[1].module)
    check("per-file count recorded", record.files[1].count == 2 and record.files[2].count == 1)
    check("decoy two folders deep is not read", (function()
        for _, choice in ipairs(record.choices) do
            if choice.id == "must-not-appear" then return false end
        end
        return true
    end)())
    check("a retired <name>-done options file beside the live one is not read", (function()
        for _, choice in ipairs(record.choices) do
            if choice.id == "must-not-appear-done" then return false end
        end
        return true
    end)())
    local first = record.choices[1]
    check("first choice keeps its id", first.id == "alpha-shape", first.id)
    check("choice labelled with its module", first.module == "alpha", first.module)
    check("choice labelled with its file", first.file:find("good%-src/alpha/019%-options%.lua$") ~= nil,
          first.file)
    check("string tests become a list of one", type(record.choices[2].variants[1].tests) == "table"
          and #record.choices[2].variants[1].tests == 1)
    check("list findings stay a list", #first.variants[2].findings == 2, #first.variants[2].findings)
    check("empty config key is kept as empty", record.choices[2].config_key == "")

    -- counts: owner and state kept apart
    local counts = gather.counts(record)
    check("total 3", counts.total == 3, counts.total)
    check("owner 2", counts.owner == 2, counts.owner)
    check("state 1", counts.state == 1, counts.state)
    check("variants 6", counts.variants == 6, counts.variants)
    check("two module rows", #counts.by_module == 2, #counts.by_module)
    check("alpha row owner 1 state 1", counts.by_module[1].owner == 1
          and counts.by_module[1].state == 1)
    check("beta row owner 1 state 0", counts.by_module[2].owner == 1
          and counts.by_module[2].state == 0)

    -- a project with no options files is an empty tally, not an error
    local empty = gather.gather(samples .. "/empty-src")
    check("no options files: zero files", #empty.files == 0)
    check("no options files: zero choices", #empty.choices == 0)
    local empty_counts = gather.counts(empty)
    check("no options files: all counts zero", empty_counts.total == 0 and empty_counts.owner == 0
          and empty_counts.state == 0 and empty_counts.variants == 0)

    -- each broken sample is refused, naming the fault
    check_error("waits_on other than owner/state is refused",
                function() gather.gather(samples .. "/bad-waits-src") end,
                'must be "owner" or "state", found "someone"')
    check_error("a variant missing findings is refused, naming the field",
                function() gather.gather(samples .. "/bad-variant-src") end,
                "choice 1.variants[1].findings")
    check_error("the same id in two modules is refused",
                function() gather.gather(samples .. "/duplicate-src") end,
                'choice id "same" is used in both')
    check_error("a file that is not valid Lua is refused",
                function() gather.gather(samples .. "/broken-src") end,
                "does not load")

    -- read_file on its own, for a later view that reads one module
    local beta = gather.read_file(samples .. "/good-src/beta/039-options.lua", "beta")
    check("read_file returns one module's choices", #beta == 1 and beta[1].id == "beta-mode")
    check("read_file keeps three variants", #beta[1].variants == 3)
end
