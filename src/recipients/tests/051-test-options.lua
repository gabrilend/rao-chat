-- 051-test-options.lua — checks the options file is in the shape the options
-- tally expects, that every switchable choice's variants are the ones the
-- module accepts, and that the first model's choices and the answered
-- ignore choices are gone.

-- {{{ local function run
local function run(h)
    local options = dofile(h.dir .. "/src/recipients/059-options.lua")

    h.check("options: every entry has the contract's fields", function()
        for _, choice in ipairs(options) do
            for _, field in ipairs({ "id", "question", "waits_on", "detail", "config_key", "leaning" }) do
                -- each field must be a string
                if type(choice[field]) ~= "string" then
                    error((choice.id or "?") .. " missing " .. field)
                end
            end
            -- waits_on is one of two words
            if choice.waits_on ~= "owner" and choice.waits_on ~= "state" then
                error(choice.id .. " waits_on is " .. choice.waits_on)
            end
            -- variants must be a non-empty list
            if #choice.variants == 0 then
                error(choice.id .. " has no variants")
            end
            for _, v in ipairs(choice.variants) do
                for _, field in ipairs({ "name", "summary", "built_in", "tests", "findings" }) do
                    -- each variant field must be a non-empty string
                    if type(v[field]) ~= "string" or v[field] == "" then
                        error(choice.id .. "/" .. tostring(v.name) .. " missing " .. field)
                    end
                end
            end
        end
    end)

    h.check("options: config keys and variants are exactly the built ones", function()
        local want = {
            ["ignore.scope"] = "home,home-and-room",
            ["recipients.shared-address-label"] = "all-labels,address",
        }
        local seen = 0
        for _, choice in ipairs(options) do
            -- switchable choices are checked; the rest have config_key ""
            if choice.config_key ~= "" then
                local names = {}
                for i, v in ipairs(choice.variants) do names[i] = v.name end
                h.equal(table.concat(names, ","), want[choice.config_key], choice.config_key)
                seen = seen + 1
            end
        end
        h.equal(seen, 2, "switchable choices")
    end)

    h.check("options: the first model's choices are retired", function()
        for _, choice in ipairs(options) do
            -- any split or arrival choice, or an answered choice, is stale
            if choice.id:find("split") or choice.id:find("arrival")
                or choice.id == "ignore-hide-files" or choice.id == "ignore-match"
                or choice.id == "recipients-flag-after-passing" or choice.id == "recipients-approval-lasts" then
                error("retired choice still listed: " .. choice.id)
            end
        end
    end)

    -- The declared setting names (043-settings) must be exactly the names
    -- this folder's source reads, found by scanning the two source files for
    -- quoted "ignore.*" / "recipients.*" names — so a name added to the code
    -- but not declared (or declared and no longer read) fails here, before
    -- 101 refuses it at run time.
    h.check("settings: the declared names are exactly the names the source reads", function()
        local declared = dofile(h.dir .. "/src/recipients/043-settings.lua")
        local read = {}
        for _, file in ipairs({ "041-recipients.lua", "042-ignore-list.lua" }) do
            local handle = assert(io.open(h.dir .. "/src/recipients/" .. file))
            for line in handle:lines() do
                local code = line:gsub("^%s*%-%-.*$", "")
                -- a quoted setting name on a code line (comments skipped)
                for name in code:gmatch('"((%a+)%.[%w%-]+)"') do
                    local prefix = name:match("^(%a+)%.")
                    if prefix == "ignore" or prefix == "recipients" then read[name] = true end
                end
            end
            handle:close()
        end
        local want = {}
        for name in pairs(read) do want[#want + 1] = name end
        table.sort(want)
        local got = {}
        for i, name in ipairs(declared) do got[i] = name end
        table.sort(got)
        h.equal(table.concat(got, ","), table.concat(want, ","), "declared vs read")
    end)

    -- Only the real room folders check declarations (stand-ins do not).
    if h.neighbours ~= "stand-in" then
        h.check("settings: the retired recipients.flag-after-passing is refused by the real config reader", function()
            local home = h.new_home("retired-setting", {})
            h.expect_error("not a setting any module reads", function()
                h.rooms.set_config(home, "recipients.flag-after-passing", "kept")
            end)
            -- a declared name of this module is accepted
            h.rooms.set_config(home, "recipients.shared-address-label", "address")
            h.equal(h.rooms.config_value(home, "recipients.shared-address-label"), "address", "declared name")
        end)
    end
end
-- }}}

return run
