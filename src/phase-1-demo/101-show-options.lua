-- 101-show-options.lua — turns the gathered list of undecided choices into text.
--
-- 100-gather-options.lua collects every module's undecided choices into one
-- list.  This file only presents that list, two ways:
--
--   * a summary: one row per choice (who or what it waits on, its config key,
--     the variants listed, the module) with the builder's leaning under it, and
--     the counts — choices waiting on the owner kept apart from choices
--     waiting on some other state;
--   * a walk-through: one choice per page, with every variant's summary,
--     where it is built, its tests, and what building it showed, so the owner
--     can pick a variant, or suggest a new one, one choice at a time.
--
-- Every showing function returns a list of lines instead of printing, so the
-- same text can go to a terminal, a file, or a test's comparison.  The walk
-- is the one exception that talks to a person: it is given a way to read a
-- line and a way to write one, so a test can play the person.

local show = {}

local PAGE_WIDTH = 78

-- {{{ local function wrap
-- Breaks text into lines no wider than `width`, each starting with `indent`.
-- A single word longer than the width is left whole on its own line rather
-- than cut, because a cut path or config key would be misread.
local function wrap(text, indent, width)
    local lines = {}
    local line = indent
    for word in text:gmatch("%S+") do
        if line == indent then
            -- first word on a line always goes on, however long
            line = indent .. word
        elseif #line + 1 + #word > width then
            -- the word would overflow: close this line, start the next
            lines[#lines + 1] = line
            line = indent .. word
        else
            -- the word fits after a space
            line = line .. " " .. word
        end
    end
    lines[#lines + 1] = line
    return lines
end
-- }}}

-- {{{ local function append_all
local function append_all(into, lines)
    for _, line in ipairs(lines) do
        into[#into + 1] = line
    end
end
-- }}}

-- {{{ local function pad
local function pad(text, width)
    return text .. string.rep(" ", width - #text)
end
-- }}}

-- {{{ local function variant_names
local function variant_names(choice)
    local names = {}
    for _, variant in ipairs(choice.variants) do
        names[#names + 1] = variant.name
    end
    return table.concat(names, " / ")
end
-- }}}

-- The words each kind of waiting is shown with.  A table rather than an if,
-- so a third kind of waiting (should one appear) is one more row here.
local WAIT_WORDS = {
    owner = "owner",
    state = "state",
}

-- {{{ function show.counts_lines
-- The figures, owner and state counted separately.  `counts` comes from
-- gather.counts, so every view agrees on the numbers.
function show.counts_lines(counts)
    local lines = {
        "choices: " .. counts.total
            .. "    waiting on the owner: " .. counts.owner
            .. "    waiting on some other state: " .. counts.state
            .. "    variants listed: " .. counts.variants,
    }
    for _, row in ipairs(counts.by_module) do
        lines[#lines + 1] = "  " .. pad(row.module, 16) .. " owner " .. row.owner
                            .. "   state " .. row.state
    end
    return lines
end
-- }}}

-- {{{ function show.summary_lines
-- The whole tally as a table.  `record` is gather.gather's result and
-- `counts` gather.counts' result for it.
function show.summary_lines(record, counts)
    local lines = {}
    lines[#lines + 1] = "options files read: " .. #record.files
    for _, found in ipairs(record.files) do
        lines[#lines + 1] = "  " .. found.file .. "  (" .. found.count .. " choices)"
    end
    lines[#lines + 1] = ""
    if #record.choices == 0 then
        -- nothing to tabulate: say so plainly rather than print an empty grid
        lines[#lines + 1] = "no undecided choices recorded yet."
        append_all(lines, show.counts_lines(counts))
        return lines
    end
    -- (there are choices: lay them out in columns)

    -- Column widths are measured from the data, so a long id never breaks
    -- the grid and a short list does not waste the width.
    local columns = {
        { title = "#",          cell = function(c, n) return tostring(n) end },
        { title = "choice",     cell = function(c) return c.id end },
        { title = "waits on",   cell = function(c) return WAIT_WORDS[c.waits_on] end },
        { title = "config key", cell = function(c)
            return c.config_key == "" and "(not switchable)" or c.config_key end },
        { title = "variants",   cell = function(c) return variant_names(c) end },
        { title = "module",     cell = function(c) return c.module end },
    }
    for _, column in ipairs(columns) do
        column.width = #column.title
        for position, choice in ipairs(record.choices) do
            column.width = math.max(column.width, #column.cell(choice, position))
        end
    end
    local header, rule = {}, {}
    for _, column in ipairs(columns) do
        header[#header + 1] = pad(column.title, column.width)
        rule[#rule + 1] = string.rep("-", column.width)
    end
    lines[#lines + 1] = (table.concat(header, "  "):gsub("%s+$", ""))
    lines[#lines + 1] = table.concat(rule, "  ")
    for position, choice in ipairs(record.choices) do
        local cells = {}
        for _, column in ipairs(columns) do
            cells[#cells + 1] = pad(column.cell(choice, position), column.width)
        end
        lines[#lines + 1] = (table.concat(cells, "  "):gsub("%s+$", ""))
        if choice.waits_on == "state" then
            -- waiting on something other than the owner: say what, since the
            -- owner cannot settle it by answering
            append_all(lines, wrap("waits for: " .. choice.detail, "     ", PAGE_WIDTH))
        end
        -- (waiting on the owner: the question itself is on the walk page)
        append_all(lines, wrap("leaning: " .. choice.leaning, "     ", PAGE_WIDTH))
    end
    lines[#lines + 1] = ""
    append_all(lines, show.counts_lines(counts))
    return lines
end
-- }}}

-- {{{ function show.page_lines
-- One choice, fully: the question, what it waits on, and every variant with
-- its summary, where it is built, its tests and its findings.
function show.page_lines(choice, position, total)
    local lines = {}
    lines[#lines + 1] = string.rep("=", PAGE_WIDTH)
    lines[#lines + 1] = "choice " .. position .. " of " .. total .. ": " .. choice.id
                        .. "   (" .. choice.module .. ")"
    lines[#lines + 1] = string.rep("=", PAGE_WIDTH)
    append_all(lines, wrap(choice.question, "", PAGE_WIDTH))
    lines[#lines + 1] = ""
    lines[#lines + 1] = "waits on:   " .. WAIT_WORDS[choice.waits_on]
    append_all(lines, wrap("detail: " .. choice.detail, "            ", PAGE_WIDTH))
    lines[#lines + 1] = "config key: " .. (choice.config_key == "" and "(not switchable)"
                                           or choice.config_key)
    for number, variant in ipairs(choice.variants) do
        lines[#lines + 1] = ""
        lines[#lines + 1] = "  [" .. number .. "] " .. variant.name
        append_all(lines, wrap(variant.summary, "      ", PAGE_WIDTH))
        -- the three list fields, each under its own heading
        local sections = {
            { "built in", variant.built_in },
            { "tests",    variant.tests },
            { "findings", variant.findings },
        }
        for _, section in ipairs(sections) do
            lines[#lines + 1] = "      " .. section[1] .. ":"
            for _, item in ipairs(section[2]) do
                append_all(lines, wrap("- " .. item, "        ", PAGE_WIDTH))
            end
        end
    end
    lines[#lines + 1] = ""
    append_all(lines, wrap("leaning: " .. choice.leaning, "", PAGE_WIDTH))
    return lines
end
-- }}}

-- {{{ function show.walk
-- Goes through the choices one at a time.  After each page it asks for a
-- line: an empty line goes on, "q" stops.  `read_line()` returns a string, or
-- nil when the input has ended; `write(line)` shows one line.
-- `pause` is a bool: true waits between pages, false prints every page
-- straight through (for reading into a file or a pager).
-- Returns the number of pages shown.
--
-- If the input ends while pages remain, the walk stops there and says how
-- far it got, rather than carrying on as if the person had pressed Enter.
function show.walk(record, read_line, write, pause)
    local total = #record.choices
    if total == 0 then
        -- nothing to walk through
        write("no undecided choices recorded yet.")
        return 0
    end
    -- (at least one choice: show them in turn)
    for position, choice in ipairs(record.choices) do
        for _, line in ipairs(show.page_lines(choice, position, total)) do
            write(line)
        end
        if pause and position < total then
            -- waiting between pages: the person decides whether to go on
            write("")
            write("[Enter] next choice    [q] stop")
            local answer = read_line()
            if answer == nil then
                -- input ended: stop, and say so
                write("(input ended after choice " .. position .. " of " .. total .. ")")
                return position
            elseif answer == "q" then
                -- the person asked to stop
                write("(stopped after choice " .. position .. " of " .. total .. ")")
                return position
            end
            -- any other answer: go on to the next page
        end
        -- (not pausing, or this was the last page: carry straight on)
    end
    return total
end
-- }}}

return show
