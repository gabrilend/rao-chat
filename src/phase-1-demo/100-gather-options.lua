-- 100-gather-options.lua — collects every module's undecided choices into one list.
--
-- Phase 1 is built with every variant of every choice the owner has not made
-- yet.  Each module writes down its choices in a file named <index>-options.lua
-- (for example src/message-log/099-options.lua).  This file finds all of those
-- files, opens each one, checks that every choice is written in the agreed
-- shape (docs/phase-1-module-contract.md, "The options tally"), and hands back
-- one combined list, each choice labelled with the module it came from.
--
-- It only gathers.  Printing the list (a table, or one choice at a time) is
-- 101-show-options.lua's job, so that a later HTML page can reuse this half
-- without inheriting any terminal formatting.
--
-- A file written in the wrong shape stops the gathering with an error naming
-- the file and the field.  Nothing is guessed or filled in: a choice the owner
-- is asked to decide must be described completely, or not shown at all.

local gather = {}

-- The two things a choice can be waiting on.  "owner" means only the owner's
-- decision is missing; "state" means something else must happen first (a
-- neighbouring module's behaviour, a later phase, a measurement), and the
-- choice's `detail` says what.
local WAIT_KINDS = { owner = true, state = true }

-- The fields every variant carries.  `name` and `summary` are one string each.
-- `built_in`, `tests` and `findings` may be one string or a list of strings;
-- builders naturally write "one file" as a string and "three tests" as a list,
-- so both shapes are accepted and turned into a list here — that is a change
-- of spelling, not a guess, since both say exactly the same thing.
local VARIANT_TEXT_FIELDS = { "name", "summary" }
local VARIANT_LIST_FIELDS = { "built_in", "tests", "findings" }
local CHOICE_TEXT_FIELDS  = { "id", "question", "waits_on", "detail",
                              "config_key", "leaning" }

-- {{{ local function shape_error
-- Every refusal names the file and where inside it, so the builder who wrote
-- the file can go straight to the line that needs fixing.
local function shape_error(file, where, message)
    error(file .. ": " .. where .. ": " .. message, 0)
end
-- }}}

-- {{{ local function as_text_list
local function as_text_list(value, file, where)
    -- A single string becomes a list of one; a list is checked item by item;
    -- anything else is a shape error (a number or a nested table would print
    -- as nonsense in the walk-through).
    local value_type = type(value)
    if value_type == "string" then
        -- one string: the builder had one thing to say
        return { value }
    elseif value_type == "table" then
        -- a list: every entry must itself be a string
        local list = {}
        for position, item in ipairs(value) do
            if type(item) ~= "string" then
                shape_error(file, where .. "[" .. position .. "]",
                            "expected a string, found " .. type(item))
            end
            list[#list + 1] = item
        end
        return list
    else
        -- nil, number, bool, function: the field is missing or mistyped
        shape_error(file, where, "expected a string or a list of strings, found "
                    .. value_type)
    end
end
-- }}}

-- {{{ local function check_variant
local function check_variant(raw, file, where)
    if type(raw) ~= "table" then
        shape_error(file, where, "expected a table, found " .. type(raw))
    end
    local variant = {}
    for _, field in ipairs(VARIANT_TEXT_FIELDS) do
        if type(raw[field]) ~= "string" or raw[field] == "" then
            shape_error(file, where .. "." .. field, "expected a non-empty string, found "
                        .. type(raw[field]))
        end
        variant[field] = raw[field]
    end
    for _, field in ipairs(VARIANT_LIST_FIELDS) do
        variant[field] = as_text_list(raw[field], file, where .. "." .. field)
    end
    return variant
end
-- }}}

-- {{{ local function check_choice
local function check_choice(raw, file, position, module_name)
    local where = "choice " .. position
    if type(raw) ~= "table" then
        shape_error(file, where, "expected a table, found " .. type(raw))
    end
    local choice = { module = module_name, file = file }
    for _, field in ipairs(CHOICE_TEXT_FIELDS) do
        if type(raw[field]) ~= "string" then
            shape_error(file, where .. "." .. field, "expected a string, found "
                        .. type(raw[field]))
        end
        choice[field] = raw[field]
    end
    -- config_key may be "" (a choice that is not switchable by config);
    -- every other text field must say something.
    for _, field in ipairs(CHOICE_TEXT_FIELDS) do
        if field ~= "config_key" and choice[field] == "" then
            shape_error(file, where .. "." .. field, "is empty")
        end
    end
    if not WAIT_KINDS[choice.waits_on] then
        shape_error(file, where .. ".waits_on", 'must be "owner" or "state", found "'
                    .. choice.waits_on .. '"')
    end
    if type(raw.variants) ~= "table" or #raw.variants == 0 then
        shape_error(file, where .. ".variants", "expected a non-empty list")
    end
    choice.variants = {}
    for variant_position, raw_variant in ipairs(raw.variants) do
        choice.variants[variant_position] = check_variant(
            raw_variant, file, where .. ".variants[" .. variant_position .. "]")
    end
    return choice
end
-- }}}

-- {{{ local function list_options_files
-- Options files are found by searching, not by a fixed list of modules, so a
-- module added later is tallied without editing this file.  The pattern is
-- <src>/<module>/<three digits>-options.lua, exactly one folder deep: a
-- sample options file inside some module's tests/ folder is not a real
-- choice and is not picked up.  Sorted by path, so the tally reads in the
-- same order every time.
local function list_options_files(src_dir)
    local listing = io.popen('find "' .. src_dir .. '" -mindepth 2 -maxdepth 2 '
                             .. '-name "[0-9][0-9][0-9]-options.lua"')
    local found = {}
    for file in listing:lines() do
        -- the module is the folder between src_dir and the file name
        local module_name = file:sub(#src_dir + 2):match("^([^/]+)/")
        found[#found + 1] = { module = module_name, file = file }
    end
    listing:close()
    table.sort(found, function(a, b) return a.file < b.file end)
    return found
end
-- }}}

-- {{{ function gather.read_file
-- Reads one options file and returns its checked list of choices.
function gather.read_file(file, module_name)
    local chunk, load_problem = loadfile(file)
    if not chunk then
        error(file .. ": does not load: " .. load_problem, 0)
    end
    local ran, raw = pcall(chunk)
    if not ran then
        error(file .. ": fails while running: " .. tostring(raw), 0)
    end
    if type(raw) ~= "table" then
        shape_error(file, "top", "must return a list of choices, returned " .. type(raw))
    end
    local choices = {}
    for position, raw_choice in ipairs(raw) do
        choices[position] = check_choice(raw_choice, file, position, module_name)
    end
    return choices
end
-- }}}

-- {{{ function gather.gather
-- Reads every options file under src_dir and returns one record:
--   files   = list of { module = string, file = string, count = integer }
--   choices = list of choices (the contract's shape, plus module and file),
--             in file order
-- Two choices with the same id anywhere in the project are an error: the id is
-- how the owner's answer will be matched back to the choice.
function gather.gather(src_dir)
    local record = { files = {}, choices = {} }
    local seen_ids = {}
    for _, found in ipairs(list_options_files(src_dir)) do
        local choices = gather.read_file(found.file, found.module)
        record.files[#record.files + 1] = { module = found.module, file = found.file,
                                            count = #choices }
        for _, choice in ipairs(choices) do
            if seen_ids[choice.id] then
                -- the same id twice: say both places so one can be renamed
                error('choice id "' .. choice.id .. '" is used in both '
                      .. seen_ids[choice.id] .. " and " .. found.file, 0)
            end
            seen_ids[choice.id] = found.file
            record.choices[#record.choices + 1] = choice
        end
    end
    return record
end
-- }}}

-- {{{ function gather.counts
-- Figures about a gathered record, kept here (not in the showing half) so
-- every view reports the same numbers:
--   total, owner, state, variants  (integers)
--   by_module = list of { module, owner, state } in first-seen order
function gather.counts(record)
    local counts = { total = 0, owner = 0, state = 0, variants = 0, by_module = {} }
    local module_row = {}
    for _, choice in ipairs(record.choices) do
        counts.total = counts.total + 1
        counts[choice.waits_on] = counts[choice.waits_on] + 1
        counts.variants = counts.variants + #choice.variants
        local row = module_row[choice.module]
        if not row then
            -- first choice from this module: start its row
            row = { module = choice.module, owner = 0, state = 0 }
            module_row[choice.module] = row
            counts.by_module[#counts.by_module + 1] = row
        end
        -- (a module already seen simply adds to its existing row)
        row[choice.waits_on] = row[choice.waits_on] + 1
    end
    return counts
end
-- }}}

return gather
