-- 105-demo-baseline.lua — decides the settings every demo home starts with.
--
-- A home's config may hold only names some module declares (round 4: each
-- module lists every setting it reads in src/<module>/<index>-settings.lua,
-- and 101 refuses any config line naming something undeclared).  And every
-- module refuses to run with a setting it reads unset.  So a demo home must
-- set exactly the declared names — no more (refused), no fewer (the module
-- reading it stops).  The baseline is the value each declared name starts at:
--
--   * by default, the first variant listed for it in its module's options
--     file (the options files are the one place undecided choices and
--     their built variants are recorded, so a new choice reaches the demo
--     without editing it);
--   * then any line in input/phase-1-demo.config ("key = value", "#"
--     comments) replaces the default for that key — so the owner can run the
--     whole demo under the variants they are leaning towards by writing them
--     into input/, which is the first thing the demo reads.
--
-- Errors, each stopping the demo before any scene (never a quiet guess):
--   * an options file records a switchable choice whose key no settings
--     list declares (the contract says it must: otherwise its homes could
--     not be configured);
--   * a declared name that no options file gives variants for and that
--     input/ does not set either (there is no value to start it at);
--   * an input line naming an undeclared key, or a value its module's
--     options file does not list as built.

local baseline = {}

-- {{{ function baseline.from_options
-- options: the record from gather.gather.  declared: table name →
-- { module = string, file = string }, as 101's declared_settings() gives
-- it.  Gives
--   settings        list of { key, value (string, or nil while no value is
--                   known), choice (choice id or ""), module, source }
--                   sorted by key — exactly one per declared name
--   variants_by_key table key -> list of variant names (only keys an
--                   options file records)
-- Two choices naming one key is an error: the baseline would be ambiguous.
function baseline.from_options(options, declared)
    if type(declared) ~= "table" then
        -- the declared names are the whole point: refuse to work without them
        error("from_options needs the declared setting names (rooms.declared_settings())", 2)
    end
    -- (given: build one setting per declared name)
    local variants_by_key, choice_of = {}, {}
    for _, choice in ipairs(options.choices) do
        if choice.config_key ~= "" then
            -- switchable by config: its first variant is a candidate value
            if variants_by_key[choice.config_key] then
                -- the same key recorded twice
                error("config key " .. choice.config_key .. " is recorded by two choices", 0)
            end
            if declared[choice.config_key] == nil then
                -- recorded as switchable, but no module declares reading it:
                -- setting it would be refused, leaving it out would hide the choice
                error("config key " .. choice.config_key .. " (choice " .. choice.id .. ", " .. choice.module
                      .. ") is in an options file but no <index>-settings.lua declares it", 0)
            end
            -- (declared and seen once: record it)
            local names = {}
            for _, variant in ipairs(choice.variants) do
                names[#names + 1] = variant.name
            end
            variants_by_key[choice.config_key] = names
            choice_of[choice.config_key] = choice
        end
        -- (not switchable: nothing to set)
    end
    local settings = {}
    for key, where in pairs(declared) do
        local choice = choice_of[key]
        if choice then
            -- an undecided choice: start at its first-listed variant
            settings[#settings + 1] = { key = key, value = variants_by_key[key][1], choice = choice.id,
                                        module = choice.module, source = "first listed" }
        else
            -- declared, but no options file lists variants for it: input/
            -- must give it a value (apply_input checks that none is left nil)
            settings[#settings + 1] = { key = key, value = nil, choice = "", module = where.module,
                                        source = "no value yet" }
        end
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
-- gives the number of keys replaced.  Afterwards every setting must have a
-- value: a declared name left without one is an error naming it.
function baseline.apply_input(settings, variants_by_key, wanted)
    local by_key = {}
    for _, setting in ipairs(settings) do
        by_key[setting.key] = setting
    end
    local replaced = 0
    for _, wish in ipairs(wanted) do
        local setting = by_key[wish.key]
        if setting == nil then
            -- no module declares this key: a home would refuse the line
            error("input/phase-1-demo.config line " .. wish.line .. ": no module declares the setting "
                  .. wish.key, 0)
        end
        -- (a declared key: if its options file lists built variants, the
        -- value must be one of them; otherwise the module checks it)
        local names = variants_by_key[wish.key]
        if names then
            local built = false
            for _, name in ipairs(names) do
                if name == wish.value then
                    -- one of the variants somebody built
                    built = true
                end
                -- (any other name: keep looking)
            end
            if not built then
                -- a variant nobody built
                error("input/phase-1-demo.config line " .. wish.line .. ": " .. wish.key .. " = "
                      .. wish.value .. " is not a built variant (built: " .. table.concat(names, ", ") .. ")", 0)
            end
            -- (built: accepted below)
        end
        -- (no variants listed: the value is taken as given)
        setting.value = wish.value
        setting.source = "input/phase-1-demo.config"
        replaced = replaced + 1
    end
    for _, setting in ipairs(settings) do
        if setting.value == nil then
            -- declared, not an options-file choice, and input/ said nothing
            error("setting " .. setting.key .. " is declared by " .. setting.module .. " but no options file "
                  .. "lists variants for it; give it a value in input/phase-1-demo.config", 0)
        end
        -- (has a value: fine)
    end
    return replaced
end
-- }}}

return baseline
