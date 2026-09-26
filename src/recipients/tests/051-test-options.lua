-- 051-test-options.lua — checks the options file is in the shape the options
-- tally expects, that every switchable choice's variants are the ones the
-- module accepts, and that the first model's choices are gone.

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
            ["ignore.hide-files"] = "filed,not-filed",
            ["ignore.scope"] = "home,home-and-room",
            ["ignore.match"] = "pair,host",
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
        h.equal(seen, 4, "switchable choices")
    end)

    h.check("options: the first model's choices are retired", function()
        for _, choice in ipairs(options) do
            -- any split or arrival choice left over is stale
            if choice.id:find("split") or choice.id:find("arrival") then
                error("retired choice still listed: " .. choice.id)
            end
        end
    end)
end
-- }}}

return run
