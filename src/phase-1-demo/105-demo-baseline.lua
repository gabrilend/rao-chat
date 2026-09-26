-- 105-demo-baseline.lua — decides the settings every demo home starts with.
--
-- Every undecided choice has a config key, and the phase 1 modules refuse to
-- run with any key unset.  A demo scene varies the one key it is about and
-- needs every other key set to something.  That something is the baseline:
--
--   * by default, the first variant each builder listed in their options
--     file (their files are the one place every choice is recorded, so a new
--     choice reaches the demo without editing it);
--   * then any line in input/phase-1-demo.config ("key = value", "#"
--     comments) replaces the default for that key — so the owner can run the
--     whole demo under the variants they are leaning towards by writing them
--     into input/, which is the first thing the demo reads.
--
-- An input line naming a key no options file records, or a value no builder
-- built, is an error: it would otherwise quietly run something else.

local baseline = {}

-- {{{ function baseline.from_options
-- options: the record from gather.gather.  Gives
--   settings        list of { key, value, choice, module, source = "first listed" }
--                   sorted by key
--   variants_by_key table key -> list of variant names
-- Two choices naming one key is an error: the baseline would be ambiguous.
function baseline.from_options(options)
    local settings, variants_by_key = {}, {}
    for _, choice in ipairs(options.choices) do
        if choice.config_key ~= "" then
            -- switchable by config: part of the baseline
            if variants_by_key[choice.config_key] then
                -- the same key recorded twice
                error("config key " .. choice.config_key .. " is recorded by two choices", 0)
            end
            -- (first time this key is seen: record it)
            local names = {}
            for _, variant in ipairs(choice.variants) do
                names[#names + 1] = variant.name
            end
            variants_by_key[choice.config_key] = names
            settings[#settings + 1] = { key = choice.config_key, value = names[1],
                                        choice = choice.id, module = choice.module,
                                        source = "first listed" }
        end
        -- (not switchable: nothing to set)
    end
    table.sort(settings, function(a, b) return a.key < b.key end)
    return settings, variants_by_key
end
-- }}}

-- {{{ function baseline.parse_input
-- The text of input/phase-1-demo.config → list of { key, value, line }.
-- Blank lines and lines starting with "#" are skipped; any other line
-- without " = " is an error naming its line number.
function baseline.parse_input(text)
    local wanted = {}
    local number = 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
        number = number + 1
        local key, value = line:match("^%s*([%w_%.%-]+)%s*=%s*(%S+)%s*$")
        if line:match("^%s*$") or line:match("^%s*#") then
            -- blank or a comment: nothing to read
        elseif key then
            -- a setting
            wanted[#wanted + 1] = { key = key, value = value, line = number }
        else
            -- neither: a mistake worth stopping for
            error("input/phase-1-demo.config line " .. number .. " is not 'key = value': " .. line, 0)
        end
    end
    return wanted
end
-- }}}

-- {{{ function baseline.apply_input
-- Replaces baseline values with the owner's wishes from input.  settings and
-- variants_by_key come from from_options; wanted from parse_input.  Changes
-- `settings` in place (value, and source = "input/phase-1-demo.config") and
-- gives the number of keys replaced.
function baseline.apply_input(settings, variants_by_key, wanted)
    local by_key = {}
    for _, setting in ipairs(settings) do
        by_key[setting.key] = setting
    end
    local replaced = 0
    for _, wish in ipairs(wanted) do
        local setting = by_key[wish.key]
        if setting == nil then
            -- no options file records this key
            error("input/phase-1-demo.config line " .. wish.line .. ": no options file records the key "
                  .. wish.key, 0)
        end
        -- (a recorded key: its value must be one of its built variants)
        local built = false
        for _, name in ipairs(variants_by_key[wish.key]) do
            if name == wish.value then
                -- one of the variants somebody built
                built = true
            end
            -- (any other name: keep looking)
        end
        if not built then
            -- a variant nobody built
            error("input/phase-1-demo.config line " .. wish.line .. ": " .. wish.key .. " = "
                  .. wish.value .. " is not a built variant (built: "
                  .. table.concat(variants_by_key[wish.key], ", ") .. ")", 0)
        end
        -- (valid: take it)
        setting.value = wish.value
        setting.source = "input/phase-1-demo.config"
        replaced = replaced + 1
    end
    return replaced
end
-- }}}

return baseline
