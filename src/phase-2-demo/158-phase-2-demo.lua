-- 158-phase-2-demo.lua — the phase 2 demo: rooms delivering between homes,
-- shown working (issue 210).
--
-- Shows phase 2 (planning document sections 5-9: delivery to every pair,
-- keys, joining, contact syncing, leaving, cross-checking, housemates,
-- failed decryption, the gatherer processes and their RAM folders) through
-- the phase 2 modules, on real home folders in RAM, three homes at
-- 127.0.0.2, .3 and .4, and prints what is really on disk and on the wire
-- after each step.  In order it:
--
--   1. reads the project's input/ folder (the owner's rule: a program's first
--      act is to read what it was given there) and shows what it found;
--   2. loads each phase 1 and phase 2 module, noting any that are not there;
--   3. sets up 143's test world (the same simulated clock and in-memory
--      relay the delivery tests run in: nothing reaches a network);
--   4. runs each scene of 159, in order;
--   5. says which scenes ran, which wait on an issue not built yet, which
--      ran with a part missing, and which could not run, and why;
--   6. writes a goodbye into output/ (the owner's rule: a program's last act).
--
-- A scene that fails is reported with its error and the demo goes on to the
-- next.  Exit status: 0 when every scene ran in full; 1 when any scene could
-- not run (a demo with a failed scene is not a passing demo); 2 when none
-- failed but some wait on an issue or ran with a part missing.
--
-- RAO_PHASE2_DEMO_BREAK=<scene key>, for the referee test (160) only, makes
-- that scene fail on purpose, to show a failure is reported and counted.
--
-- Usage: luajit src/phase-2-demo/158-phase-2-demo.lua [project folder]
-- (normally run by issues/completed/demos/phase-2-demo, under unshare -rn)

local DIR = "/home/ritz/programs/rao-chat"
if arg[1] then
    -- a project folder was given: use it instead
    DIR = arg[1]
end
-- (no argument: the folder written above)

package.path = DIR .. "/src/phase-1-demo/?.lua;" .. DIR .. "/src/phase-2-demo/?.lua;" .. package.path
local probes = require("102-demo-probes")

-- The modules, the short name the scenes know each by, and the issue that
-- builds it.
local MODULES = {
    { short = "rooms",       file = "002-room-folders",    issue = "101" },
    { short = "disk",        file = "003-disk",            issue = "101" },
    { short = "tokens",      file = "007-tokens",          issue = "101" },
    { short = "tree",        file = "021-room-tree",       issue = "102" },
    { short = "forest_text", file = "024-forest-text",     issue = "102" },
    { short = "recipients",  file = "041-recipients",      issue = "103" },
    { short = "ignore",      file = "042-ignore-list",     issue = "103a" },
    { short = "people",      file = "061-people-links",    issue = "104" },
    { short = "message_log", file = "081-message-log",     issue = "105" },
    { short = "room_key",    file = "123-room-key",        issue = "201" },
    { short = "seal",        file = "124-seal",            issue = "201" },
    { short = "records",     file = "126-inner-records",   issue = "201a" },
    { short = "keyring",     file = "127-keyring",         issue = "201" },
    { short = "delivered",   file = "130-delivered",       issue = "202" },
    { short = "receive",     file = "133-receive",         issue = "202" },
    { short = "delivery",    file = "134-delivery",        issue = "202" },
    { short = "fd",          file = "139-failed-decryption", issue = "203" },
    { short = "claims",      file = "141-claims",          issue = "204" },
    { short = "call_back",   file = "142-call-back",       issue = "204" },
    { short = "hello",       file = "145-hello",           issue = "205" },
    { short = "leaving",     file = "147-leaving",         issue = "208" },
    { short = "reach",       file = "149-reach",           issue = "212" },
    { short = "public",      file = "150-public-address",  issue = "212" },
    { short = "members",     file = "152-members",         issue = "207" },
    { short = "housemates",  file = "154-housemates",      issue = "213" },
    { short = "crosscheck",  file = "156-cross-check",     issue = "209" },
    { short = "ram",         file = "161-ram-folders",     issue = "211" },
    { short = "loopback",    file = "168-loopback",        issue = "211" },
    { short = "signature",   file = "169-signature",       issue = "214" },
    { short = "git",         file = "172-git",             issue = "215" },
    { short = "copies",      file = "173-text-copies",     issue = "215" },
    { short = "runlog",      file = "177-running-log",     issue = "215a" },
    { short = "sharing",     file = "179-sharing",         issue = "215b" },
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

-- {{{ local function first_line
local function first_line(text)
    return (tostring(text):match("^([^\n]*)"))
end
-- }}}

-- {{{ local function read_input
-- The files in input/, each with its size and first line.
local function read_input()
    local found = {}
    for _, name in ipairs(probes.entries(DIR .. "/input")) do
        local text = probes.read_text(DIR .. "/input/" .. name)
        found[#found + 1] = { name = name, bytes = #text, first_line = first_line(text) }
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
            loaded[module.short] = result
        else
            -- missing or broken: keep the first line of the reason
            problems[module.short] = first_line(result)
        end
    end
    return loaded, problems
end
-- }}}

-- {{{ local function run_scene
-- Runs one scene.  Gives { key, title, state = "ran" | "gaps" | "waits" |
-- "could not", seconds, reason }.
local function run_scene(number, entry, scenes, ctx)
    heading(number, entry.title)
    local outcome = { key = entry.key, title = entry.title, state = "could not", seconds = 0, reason = "" }
    local scene = scenes[entry.key]
    if type(scene) == "table" and scene.waits then
        -- the issue this scene shows is not built: say so, do not pretend
        outcome.state, outcome.reason = "waits", "waits on " .. scene.waits
        say("WAITS: " .. outcome.reason)
        return outcome
    end
    if ctx.problem then
        -- the world or a module could not be set up: no scene can run
        outcome.reason = ctx.problem
        say("COULD NOT RUN: " .. outcome.reason)
        return outcome
    end
    local started = probes.now()
    local built, record = pcall(function()
        if ctx.break_scene == entry.key then
            -- the referee's broken version (160)
            error("broken on purpose (RAO_PHASE2_DEMO_BREAK=" .. entry.key .. ")", 0)
        end
        return scene(ctx)
    end)
    outcome.seconds = probes.now() - started
    if not built then
        outcome.reason = "failed: " .. tostring(record)
        say("COULD NOT RUN: " .. outcome.reason)
        return outcome
    end
    for _, line in ipairs(record.lines) do
        say(line)
    end
    if #record.gaps > 0 then
        -- ran, with a part that could not: name each
        outcome.state = "gaps"
        outcome.reason = "missing a part: " .. table.concat(record.gaps, "; ")
        for _, gap in ipairs(record.gaps) do say("PART NOT RUN: " .. gap) end
    else
        outcome.state = "ran"
    end
    say(string.format("[scene ran in %.1f ms of real time]", outcome.seconds * 1000))
    return outcome
end
-- }}}

-- {{{ local function write_goodbye
-- The last act: a goodbye in output/, rewritten each run.
local function write_goodbye(outcomes, counts)
    local lines = { "phase 2 demo, run at " .. os.date("!%Y-%m-%d %H:%M:%S UTC") }
    for _, outcome in ipairs(outcomes) do
        lines[#lines + 1] = string.format("  %-10s %-12s %s", outcome.state, outcome.key, first_line(outcome.reason))
    end
    lines[#lines + 1] = string.format("%d of %d scenes ran in full; %d with a part missing; %d wait on an issue; "
        .. "%d could not run.", counts.ran, #outcomes, counts.gaps, counts.waits, counts["could not"])
    lines[#lines + 1] = "goodbye."
    local path = DIR .. "/output/phase-2-demo.goodbye"
    probes.write_text(path, table.concat(lines, "\n") .. "\n")
    return path
end
-- }}}

-- {{{ local function main
local function main()
    heading(0, "What input/ holds (read first)")
    for _, file in ipairs(read_input()) do
        say(string.format("  %-24s %5d bytes   %s", file.name, file.bytes, file.first_line))
    end

    local loaded, problems = load_modules()
    say("")
    say("modules:")
    for _, module in ipairs(MODULES) do
        say(string.format("  %-22s (issue %-4s)  %s", module.file, module.issue,
                          loaded[module.short] and "loaded" or ("NOT LOADED: " .. problems[module.short])))
    end

    local ctx = { dir = DIR, m = loaded, break_scene = os.getenv("RAO_PHASE2_DEMO_BREAK") }
    local missing = {}
    for _, module in ipairs(MODULES) do
        if not loaded[module.short] then missing[#missing + 1] = module.short end
    end
    if #missing > 0 then
        -- every scene runs phase 2's stages together, so one missing module
        -- would show a world that is not the design
        ctx.problem = "modules did not load: " .. table.concat(missing, ", ")
    else
        local ready, world = pcall(dofile, DIR .. "/src/delivery/tests/143-test-world.lua")
        if ready then ready, world = pcall(world, DIR, "phase-2-demo") end
        if ready then
            ctx.T, ctx.scratch = world, world.SCRATCH
        else
            ctx.problem = "the test world (143) could not be set up: " .. first_line(world)
        end
    end
    say("")
    say("homes: real rao-homes in " .. (ctx.scratch or "(none)") .. ", each with its own RAM folder;")
    say("  each listens on and sends from its own loopback address, 127.0.0.2, .3, .4 (and .5 for a second pair),")
    say("  on ports written in its own mailboxes file.  Most scenes run the stages in 143's world: a simulated")
    say("  clock and an in-memory relay that records who connected from where, so their times are that clock's.")
    say("  The gatherers and acknowledge scenes run real gatherer processes (211) on loopback, on the real clock.")

    local scenes = require("159-phase-2-scenes")
    local outcomes = {}
    for number, entry in ipairs(scenes.ORDER) do
        outcomes[#outcomes + 1] = run_scene(number, entry, scenes, ctx)
    end

    heading(#scenes.ORDER + 1, "Which scenes ran")
    local counts = { ran = 0, gaps = 0, waits = 0, ["could not"] = 0 }
    for _, outcome in ipairs(outcomes) do
        counts[outcome.state] = counts[outcome.state] + 1
        local timing = outcome.state == "waits" and "" or string.format("%8.1f ms  ", outcome.seconds * 1000)
        say(string.format("  %-10s %-12s %s%s", outcome.state, outcome.key, timing, first_line(outcome.reason)))
    end
    say(string.format("%d of %d scenes ran in full; %d with a part missing; %d wait on an issue; %d could not run.",
                      counts.ran, #outcomes, counts.gaps, counts.waits, counts["could not"]))
    say("scratch homes: " .. tostring(ctx.scratch))

    local goodbye = write_goodbye(outcomes, counts)
    say("goodbye written to " .. goodbye)
    if counts["could not"] > 0 then
        -- something failed: the demo does not pass
        os.exit(1)
    elseif counts.gaps + counts.waits > 0 then
        -- nothing failed, but not everything phase 2 asks for was shown
        os.exit(2)
    end
    -- (every scene ran in full)
end
-- }}}

main()
