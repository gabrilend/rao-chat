-- 106-phase-1-demo.lua — the phase 1 demo: rooms on the home server, shown working.
--
-- Shows the "a room is a contact" design (planning document sections 1-4)
-- through the phase 1 modules on real home folders in RAM, and prints what
-- is really on disk after each step.  In order it:
--
--   1. reads the project's input/ folder (the owner's rule: a program's first
--      act is to read what it was given there) and shows what it found;
--   2. loads each phase 1 module, noting any that are not there yet;
--   3. settles the baseline: exactly the setting names the modules declare
--      (101's declared_settings — a home's config may hold no other name),
--      each at the first variant listed for it in an options file unless
--      input/phase-1-demo.config names another built variant
--      (105-demo-baseline.lua), printing them all, so nothing about the
--      setup is hidden.  If that cannot be done (an options file records a
--      key nobody declares, a declared name has no value), every scene
--      that makes a home is reported could-not with the reason;
--   4. builds and shows each scene (103 builds, 104 draws), each variant of
--      the choice a scene is about in a home of its own;
--   5. says which scenes ran and which could not, and why;
--   6. writes a goodbye into output/ (the owner's rule: a program's last act).
--
-- A scene that fails is reported with its error and the demo goes on to the
-- next, so one unfinished module does not hide what the others can show; the
-- demo then exits with status 1, because a demo with a failed scene is not a
-- passing demo.
--
-- Usage: luajit src/phase-1-demo/106-phase-1-demo.lua [project folder]
-- (normally run by issues/completed/demos/phase-1-demo)

local DIR = "/home/ritz/programs/rao-chat"
if arg[1] then
    -- a project folder was given: use it instead
    DIR = arg[1]
end
-- (no argument: the folder written above)

package.path = DIR .. "/src/phase-1-demo/?.lua;" .. package.path
local probes = require("102-demo-probes")
local sections = require("103-demo-sections")
local view = require("104-demo-view")
local gather = require("100-gather-options")
local show = require("101-show-options")
local baseline_tool = require("105-demo-baseline")

-- The phase 1 modules, the short name each scene knows them by, and the
-- issue that builds them.
local MODULES = {
    { short = "rooms",       file = "002-room-folders", issue = "101" },
    { short = "tree",        file = "021-room-tree",    issue = "102" },
    { short = "forest_text", file = "024-forest-text",  issue = "102" },
    { short = "members",     file = "041-recipients",   issue = "103" },
    { short = "ignore",      file = "042-ignore-list",  issue = "103a" },
    { short = "people",      file = "061-people-links", issue = "104" },
    { short = "log",         file = "081-message-log",  issue = "105" },
}

-- Which modules each scene cannot run without.  Every scene that makes
-- rooms needs all of them loaded, and all of them are loaded before the
-- first scene: each module's bell listener keeps its own derived files
-- (`where`, flags, people/) current, and a home built with one of them
-- missing would be shown as if it were the design.  Loading every module
-- first also means every scene exercises every listener, so a fault in any
-- of them shows up in every scene it touches rather than only in the scene
-- about that module.  (Round 3 briefly loaded 104 only for the people
-- scene, while 104's listener refused 101's new bell kind `mailbox`; once
-- 104 was fixed that containment was dropped, since it hid how the
-- modules work together.)
local ALL_ROOM_MODULES = { "rooms", "tree", "forest_text", "members", "ignore", "people", "log" }
local NEEDS = {
    entries = ALL_ROOM_MODULES, tokens = ALL_ROOM_MODULES, tree = ALL_ROOM_MODULES,
    mailboxes = ALL_ROOM_MODULES, members = ALL_ROOM_MODULES, leaving = ALL_ROOM_MODULES,
    ignoring = ALL_ROOM_MODULES, people = ALL_ROOM_MODULES, log = ALL_ROOM_MODULES, tally = {},
}

local RULE = string.rep("-", 78)

-- {{{ local function say
local function say(line)
    io.write(line, "\n")
end
-- }}}

-- {{{ local function heading
local function heading(number, title)
    say("")
    say(RULE)
    say(number .. ". " .. title)
    say(RULE)
end
-- }}}

-- {{{ local function read_input
-- The files in input/, each with its size and first line.  Gives a list of
-- { name, bytes, first_line, text }.  One of them, phase-1-demo.config, is
-- the demo's own: settings the owner wants the demo to start from.
local function read_input()
    local found = {}
    for _, name in ipairs(probes.entries(DIR .. "/input")) do
        local path = DIR .. "/input/" .. name
        local text = probes.read_text(path)
        found[#found + 1] = { name = name, bytes = #text, text = text,
                              first_line = text:match("^([^\n]*)") }
    end
    return found
end
-- }}}

-- {{{ local function load_modules
-- Loads each module, catching the error of any that is missing or broken.
-- Gives loaded (short name → module) and problems (short name → message).
local function load_modules()
    dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)
    local loaded, problems = {}, {}
    for _, module in ipairs(MODULES) do
        local ran, result = pcall(require, module.file)
        if ran then
            -- the module is there and loads
            loaded[module.short] = result
        else
            -- missing or broken: keep the first line of the reason
            problems[module.short] = tostring(result):match("^([^\n]*)")
        end
    end
    return loaded, problems
end
-- }}}

-- {{{ local function missing_modules
-- (the modules and baseline a scene cannot run without)
-- The short names a scene needs and lacks: modules that did not load, and
-- "baseline" when the settings could not be settled (problems.baseline)
-- and the scene makes homes.
local function missing_modules(key, loaded, problems)
    local missing = {}
    if #NEEDS[key] > 0 and problems.baseline ~= nil then
        -- a scene that makes homes, and no baseline to configure them with
        missing[#missing + 1] = "baseline"
    end
    -- (a baseline, or a scene that makes no homes: only modules matter)
    for _, short in ipairs(NEEDS[key]) do
        if loaded[short] == nil then
            -- this scene needs a module that did not load
            missing[#missing + 1] = short
        end
        -- (loaded: fine)
    end
    return missing
end
-- }}}

-- {{{ local function run_scene
-- Builds one scene and draws it.  Gives { key, title, ran = bool, seconds,
-- reason = string ("" when it ran) }.
local function run_scene(number, entry, ctx, problems)
    heading(number, entry.title)
    local outcome = { key = entry.key, title = entry.title, ran = false, seconds = 0, reason = "" }
    local missing = missing_modules(entry.key, ctx.m, problems)
    if #missing > 0 then
        -- a needed module is absent: say which and why, and do not try
        local reasons = {}
        for _, short in ipairs(missing) do
            reasons[#reasons + 1] = short .. " (" .. ctx.problems[short] .. ")"
        end
        outcome.reason = "missing: " .. table.concat(reasons, "; ")
        say("COULD NOT RUN: " .. outcome.reason)
        return outcome
    end
    -- (every needed module loaded: build the scene)
    local started = probes.now()
    local built, record = pcall(sections[entry.key], ctx)
    outcome.seconds = probes.now() - started
    if not built then
        -- building failed part-way: show the error, keep going
        outcome.reason = "building failed: " .. tostring(record)
        say("COULD NOT RUN: " .. outcome.reason)
        return outcome
    end
    -- (built: draw it)
    local drawn, lines = pcall(view[entry.key], record, show)
    if not drawn then
        -- the scene built but its drawing failed
        outcome.reason = "drawing failed: " .. tostring(lines)
        say("COULD NOT SHOW: " .. outcome.reason)
        return outcome
    end
    -- (drawn: print it)
    for _, line in ipairs(lines) do
        say(line)
    end
    say(string.format("[scene built and measured in %.1f ms]", outcome.seconds * 1000))
    outcome.ran = true
    return outcome
end
-- }}}

-- {{{ local function write_goodbye
-- The last act: a goodbye in output/, with what this run managed.  Rewritten
-- each run (not appended), so output/ holds one current goodbye rather
-- than a growing pile of old ones.
local function write_goodbye(outcomes)
    local ran = 0
    local lines = { "phase 1 demo, run at " .. os.date("!%Y-%m-%d %H:%M:%S UTC") }
    for _, outcome in ipairs(outcomes) do
        if outcome.ran then
            -- counted as shown
            ran = ran + 1
            lines[#lines + 1] = "  ran        " .. outcome.key
        else
            -- counted as not shown, with the reason's first line
            lines[#lines + 1] = "  could not  " .. outcome.key .. ": "
                                .. outcome.reason:match("^([^\n]*)")
        end
    end
    lines[#lines + 1] = ran .. " of " .. #outcomes .. " scenes ran."
    lines[#lines + 1] = "goodbye."
    local path = DIR .. "/output/phase-1-demo.goodbye"
    probes.write_text(path, table.concat(lines, "\n") .. "\n")
    return path
end
-- }}}

-- {{{ local function settle_baseline
-- The settings every demo home starts with: exactly the names the modules
-- declare (101's declared_settings), valued from the options files and
-- input/phase-1-demo.config (105-demo-baseline).  Gives baseline,
-- variants_by_key, and how many came from input/.  Raises when 101 did
-- not load (no declared names to read) or any name is left without a
-- value, or an options file records a key nobody declares.
local function settle_baseline(options, loaded, problems, wanted)
    if loaded.rooms == nil then
        -- without 101 there is no list of declared setting names
        error("room-folders (101) did not load, so the declared setting names cannot be read: "
              .. problems.rooms, 0)
    end
    -- (101 loaded: its list of every name any module declares is the
    -- whole of what a demo home may set)
    local baseline, variants_by_key = baseline_tool.from_options(options, loaded.rooms.declared_settings())
    local replaced = baseline_tool.apply_input(baseline, variants_by_key, wanted)
    return baseline, variants_by_key, replaced
end
-- }}}

-- {{{ local function main
local function main()
    heading(0, "What input/ holds (read first)")
    local wanted = {}
    for _, file in ipairs(read_input()) do
        say(string.format("  %-20s %5d bytes   %s", file.name, file.bytes, file.first_line))
        if file.name == "phase-1-demo.config" then
            -- the demo's own input: settings to start from
            wanted = baseline_tool.parse_input(file.text)
        end
        -- (any other file is shown, not used)
    end

    local loaded, problems = load_modules()
    say("")
    say("phase 1 modules:")
    for _, module in ipairs(MODULES) do
        say(string.format("  %-18s (issue %s)  %s", module.file, module.issue,
                          loaded[module.short] and "loaded" or ("NOT LOADED: " .. problems[module.short])))
    end

    local options = gather.gather(DIR .. "/src")
    local set_up, baseline, variants_by_key, replaced = pcall(settle_baseline, options, loaded, problems, wanted)
    say("")
    if set_up then
        -- every declared name has a value: show them all
        say("baseline config: " .. #baseline .. " settings, exactly the names the modules declare in their "
            .. "<index>-settings.lua files;")
        say("  " .. replaced .. " taken from input/phase-1-demo.config, the rest the first variant listed in "
            .. "an options file.")
        say("each scene overrides the key it is about.")
        for _, setting in ipairs(baseline) do
            say(string.format("  %-36s = %-12s (%s; %s)", setting.key, setting.value, setting.module,
                              setting.source))
        end
    else
        -- no baseline: no home can be configured, so every scene that makes
        -- one is reported as could-not with this reason; the tally still runs
        say("COULD NOT SET THE BASELINE: " .. tostring(baseline))
        problems.baseline = tostring(baseline)
        baseline, variants_by_key = {}, {}
    end

    local scratch = DIR .. "/tmp/shared-memory/phase-1-demo"
    probes.must_run("mkdir -p '" .. scratch .. "'")
    local ctx = { dir = DIR, scratch = scratch, m = loaded, problems = problems,
                  probes = probes, baseline = baseline, variants_by_key = variants_by_key,
                  options = options, gather = gather }

    local outcomes = {}
    for number, entry in ipairs(sections.ORDER) do
        outcomes[#outcomes + 1] = run_scene(number, entry, ctx, problems)
    end

    heading(#sections.ORDER + 1, "Which scenes ran")
    local ran = 0
    for _, outcome in ipairs(outcomes) do
        if outcome.ran then
            -- shown in full above
            ran = ran + 1
            say(string.format("  ran        %-10s %8.1f ms", outcome.key, outcome.seconds * 1000))
        else
            -- not shown: the first line of why
            say("  could not  " .. string.format("%-10s ", outcome.key)
                .. outcome.reason:match("^([^\n]*)"))
        end
    end
    say(ran .. " of " .. #outcomes .. " scenes ran.  scratch homes: " .. scratch)

    local goodbye = write_goodbye(outcomes)
    say("goodbye written to " .. goodbye)
    if ran < #outcomes then
        -- something could not be shown: the demo does not pass
        os.exit(1)
    end
    -- (every scene ran)
end
-- }}}

main()
