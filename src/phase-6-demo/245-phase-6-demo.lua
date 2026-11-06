-- 245-phase-6-demo.lua — the phase 6 demo: homes installed and run as
-- services, shown working (issue 606).
--
-- Shows phase 6 (planning document section 12: "Installation and running
-- as a service — as rmail's installer does") on two homes made by the
-- installer and run by their services, A on 127.0.0.2 and B on 127.0.0.3,
-- and prints what is really in their folders after each step.  No real
-- service manager is used: the commands the installer and the scenes call
-- are the stand-ins of 242 on a scratch PATH, which run each unit file as
-- written, because a demo installs nothing on the machine it runs on.  In
-- order it:
--
--   1. reads the project's input/ folder (the owner's rule: a program's first
--      act is to read what it was given there) and shows what it found;
--   2. loads the modules the scenes use and finds the scripts they run,
--      noting any that are not there;
--   3. makes the world of 246 (the stand-ins, a scratch HOME, nothing
--      installed yet) under tmp/shared-memory/phase-6-demo/;
--   4. runs each scene of 246, in order;
--   5. stops every process the world started and removes its folder;
--   6. says which scenes ran, which ran with a part missing, and which
--      could not run, and why;
--   7. writes a goodbye into output/ (the owner's rule: a program's last act).
--
-- A scene that fails is reported with its error and the demo goes on to the
-- next.  Exit status: 0 when every scene ran in full; 1 when any scene could
-- not run; 2 when none failed but some ran with a part missing.
--
-- RAO_PHASE6_DEMO_BREAK=<scene key>, for the referee test (247) only, makes
-- that scene fail on purpose, to show a failure is reported and counted.
--
-- Usage: luajit src/phase-6-demo/245-phase-6-demo.lua [project folder]
-- (normally run by issues/completed/demos/phase-6-demo, under unshare -rn)

local DIR = "/home/ritz/programs/rao-chat"
if arg[1] then
    -- a project folder was given: use it instead
    DIR = arg[1]
end
-- (no argument: the folder written above)

package.path = DIR .. "/src/phase-1-demo/?.lua;" .. DIR .. "/src/phase-6-demo/?.lua;" .. package.path
local probes = require("102-demo-probes")

-- The modules, the short name the scenes know each by, and the issue that
-- builds it.
local MODULES = {
    { short = "rooms",       file = "002-room-folders",    issue = "101" },
    { short = "disk",        file = "003-disk",            issue = "101" },
    { short = "recipients",  file = "041-recipients",      issue = "103" },
    { short = "ram",         file = "161-ram-folders",     issue = "211" },
    { short = "loopback",    file = "168-loopback",        issue = "211" },
    { short = "mirror",      file = "192-mirror",          issue = "304" },
    { short = "files",       file = "236-service-files",   issue = "604" },
}

-- The programs the scenes run, and the issue that builds each.
local PROGRAMS = {
    { file = "src/install/230-what-a-home-needs.lua",          issue = "601" },
    { file = "scripts/install-home",                           issue = "602" },
    { file = "src/install/232-make-home.lua",                  issue = "602" },
    { file = "scripts/run-home",                               issue = "603" },
    { file = "src/install/242-stand-in-service-managers.lua",  issue = "604" },
    { file = "scripts/restart-homes",                          issue = "605" },
    { file = "src/devices/189-pair.lua",                       issue = "303" },
    { file = "src/devices/190-device.lua",                     issue = "303" },
    { file = "src/viewer/183-viewer.lua",                      issue = "301" },
}

local RULE = string.rep("-", 78)

-- {{{ local function say / heading / first_line
local function say(line)
    io.write(line, "\n")
    io.flush()
end
local function heading(number, title)
    say("")
    say(RULE)
    say(number .. ". " .. title)
    say(RULE)
end
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
            problems[module.short] = first_line(result)
        end
    end
    return loaded, problems
end
-- }}}

-- {{{ local function run_scene
-- Runs one scene.  Gives { key, title, state = "ran" | "gaps" |
-- "could not", seconds, reason }.
local function run_scene(number, entry, scenes, ctx)
    heading(number, entry.title)
    local outcome = { key = entry.key, title = entry.title, state = "could not", seconds = 0, reason = "" }
    if ctx.problem then
        outcome.reason = ctx.problem
        say("COULD NOT RUN: " .. outcome.reason)
        return outcome
    end
    local started = probes.now()
    local built, record = pcall(function()
        if ctx.break_scene == entry.key then
            error("broken on purpose (RAO_PHASE6_DEMO_BREAK=" .. entry.key .. ")", 0)
        end
        return scenes[entry.key](ctx)
    end)
    outcome.seconds = probes.now() - started
    if not built then
        outcome.reason = "failed: " .. tostring(record)
        say("COULD NOT RUN: " .. outcome.reason)
        return outcome
    end
    for _, line in ipairs(record.lines) do say(line) end
    if #record.gaps > 0 then
        outcome.state = "gaps"
        outcome.reason = "missing a part: " .. table.concat(record.gaps, "; ")
        for _, gap in ipairs(record.gaps) do say("PART NOT RUN: " .. gap) end
    else
        outcome.state = "ran"
    end
    say(string.format("[scene ran in %.1f s of real time]", outcome.seconds))
    return outcome
end
-- }}}

-- {{{ local function write_goodbye
-- The last act: a goodbye in output/, rewritten each run.
local function write_goodbye(outcomes, counts)
    local lines = { "phase 6 demo, run at " .. os.date("!%Y-%m-%d %H:%M:%S UTC") }
    for _, outcome in ipairs(outcomes) do
        lines[#lines + 1] = string.format("  %-10s %-10s %s", outcome.state, outcome.key, first_line(outcome.reason))
    end
    lines[#lines + 1] = string.format("%d of %d scenes ran in full; %d with a part missing; %d could not run.",
        counts.ran, #outcomes, counts.gaps, counts["could not"])
    lines[#lines + 1] = "goodbye."
    local path = DIR .. "/output/phase-6-demo.goodbye"
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
    local missing = {}
    for _, module in ipairs(MODULES) do
        say(string.format("  %-22s (issue %-4s)  %s", module.file, module.issue,
                          loaded[module.short] and "loaded" or ("NOT LOADED: " .. problems[module.short])))
        if not loaded[module.short] then missing[#missing + 1] = module.short end
    end
    say("programs:")
    local absent = {}
    for _, program in ipairs(PROGRAMS) do
        local there = (pcall(probes.read_text, DIR .. "/" .. program.file))
        say(string.format("  %-46s (issue %-4s)  %s", program.file, program.issue, there and "found" or "NOT FOUND"))
        if not there then absent[#absent + 1] = program.file end
    end

    local ctx = { dir = DIR, m = loaded, break_scene = os.getenv("RAO_PHASE6_DEMO_BREAK"),
                  scratch = DIR .. "/tmp/shared-memory/phase-6-demo" }
    local scenes
    if #missing > 0 or #absent > 0 then
        -- the scenes run phase 6's pieces together: one missing would show
        -- an install that is not the design
        local parts = {}
        if #missing > 0 then parts[#parts + 1] = "modules did not load: " .. table.concat(missing, ", ") end
        if #absent > 0 then parts[#parts + 1] = "programs not found: " .. table.concat(absent, ", ") end
        ctx.problem = table.concat(parts, "; ")
    else
        local ready, result = pcall(require, "246-phase-6-scenes")
        if ready then
            scenes = result
            local world, why = scenes.setup(ctx)
            if world then ctx.world = world else ctx.problem = "the world could not be made: " .. tostring(why) end
        else
            ctx.problem = "the scenes (246) could not be loaded: " .. first_line(result)
        end
    end
    say("")
    say("homes: two rao-homes made by the installer in " .. ctx.scratch .. ", A listening on 127.0.0.2 and B on")
    say("  127.0.0.3, each set up as a systemd user service and run by it: scripts/run-home (the launcher), its")
    say("  starter (164) with a gatherer (163) per mailbox, and its device server (187).  No real service manager")
    say("  is used: the installer and the scenes call 242's stand-ins on a scratch PATH (HOME a scratch folder),")
    say("  which run each unit's ExecStart as the installer wrote it, because a demo installs nothing on the")
    say("  machine it runs on.  Everything runs on loopback, on the real clock.")
    say("  Below, <demo> is " .. ctx.scratch .. " and <project> is " .. DIR .. ".")

    local order = scenes and scenes.ORDER or require("246-phase-6-scenes").ORDER
    local outcomes = {}
    for number, entry in ipairs(order) do
        outcomes[#outcomes + 1] = run_scene(number, entry, scenes, ctx)
    end
    if scenes then scenes.finish(ctx) end
    say("")
    say("every process the demo started is stopped, and " .. ctx.scratch .. " is removed.")

    heading(#order + 1, "Which scenes ran")
    local counts = { ran = 0, gaps = 0, ["could not"] = 0 }
    for _, outcome in ipairs(outcomes) do
        counts[outcome.state] = counts[outcome.state] + 1
        say(string.format("  %-10s %-10s %6.1f s  %s", outcome.state, outcome.key, outcome.seconds,
            first_line(outcome.reason)))
    end
    say(string.format("%d of %d scenes ran in full; %d with a part missing; %d could not run.",
                      counts.ran, #outcomes, counts.gaps, counts["could not"]))

    local goodbye = write_goodbye(outcomes, counts)
    say("goodbye written to " .. goodbye)
    if counts["could not"] > 0 then
        os.exit(1)
    elseif counts.gaps > 0 then
        os.exit(2)
    end
end
-- }}}

main()
