-- 227-phase-4-demo.lua — the phase 4 demo: the web client, shown working
-- (issue 409).
--
-- Shows phase 4 (planning document section 6: "Phase 4 — the web client
-- ... ends with the clients talking to each other") on two real homes at
-- 127.0.0.2 and .3, one room between them, and a web page paired with
-- each: the page's own scripts (src/web) run by the stand-in browser (208)
-- under Node, which stands in for the browser (401 decision 4).  It
-- prints what is really in the homes' folders and what the pages printed
-- and kept after each step.  In order it:
--
--   1. reads the project's input/ folder (the owner's rule: a program's first
--      act is to read what it was given there) and shows what it found;
--   2. stops at once, with status 1, when Node is not there to stand in for
--      the browser (409 decision 2);
--   3. loads the modules the scenes use, noting any that are not there, and
--      checks that the stand-in browser is there;
--   4. makes the world of 228 (310's two homes, not yet started, and a
--      folder for each page) under tmp/shared-memory/phase-4-demo/;
--   5. runs each scene of 228, in order;
--   6. stops every process the world started and removes its folder;
--   7. says which scenes ran, which ran with a part missing, and which
--      could not run, and why;
--   8. writes a goodbye into output/ (the owner's rule: a program's last act).
--
-- A scene that fails is reported with its error and the demo goes on to the
-- next.  Exit status: 0 when every scene ran in full; 1 when any scene could
-- not run (or Node is missing); 2 when none failed but some ran with a part
-- missing.
--
-- RAO_PHASE4_DEMO_BREAK=<scene key>, for the referee test (229) only, makes
-- that scene fail on purpose, to show a failure is reported and counted.
--
-- Usage: luajit src/phase-4-demo/227-phase-4-demo.lua [project folder]
-- (normally run by issues/completed/demos/phase-4-demo, under unshare -rn)

local DIR = "/home/ritz/programs/rao-chat"
if arg[1] then
    -- a project folder was given: use it instead
    DIR = arg[1]
end
-- (no argument: the folder written above)

package.path = DIR .. "/src/phase-1-demo/?.lua;" .. DIR .. "/src/phase-3-demo/?.lua;" .. DIR .. "/src/phase-4-demo/?.lua;"
    .. package.path
local probes = require("102-demo-probes")

-- The modules, the short name the scenes know each by, and the issue that
-- builds it.
local MODULES = {
    { short = "rooms",       file = "002-room-folders",    issue = "101" },
    { short = "disk",        file = "003-disk",            issue = "101" },
    { short = "message_log", file = "081-message-log",     issue = "105" },
    { short = "recipients",  file = "041-recipients",      issue = "103" },
    { short = "ram",         file = "161-ram-folders",     issue = "211" },
    { short = "loopback",    file = "168-loopback",        issue = "211" },
    { short = "inbox",       file = "181-inbox-files",     issue = "301" },
    { short = "viewer",      file = "183-viewer",          issue = "301" },
    { short = "records",     file = "186-device-records",  issue = "302" },
    { short = "server",      file = "187-device-server",   issue = "302" },
    { short = "device",      file = "190-device",          issue = "303" },
    { short = "mirror",      file = "192-mirror",          issue = "304" },
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
            error("broken on purpose (RAO_PHASE4_DEMO_BREAK=" .. entry.key .. ")", 0)
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
    local lines = { "phase 4 demo, run at " .. os.date("!%Y-%m-%d %H:%M:%S UTC") }
    for _, outcome in ipairs(outcomes) do
        lines[#lines + 1] = string.format("  %-10s %-10s %s", outcome.state, outcome.key, first_line(outcome.reason))
    end
    lines[#lines + 1] = string.format("%d of %d scenes ran in full; %d with a part missing; %d could not run.",
        counts.ran, #outcomes, counts.gaps, counts["could not"])
    lines[#lines + 1] = "goodbye."
    local path = DIR .. "/output/phase-4-demo.goodbye"
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

    -- Node stands in for the browser (409 decision 2): without it, nothing starts
    local probe = io.popen("node --version 2>/dev/null")
    local version = probe:read("*l")
    probe:close()
    if not version or version == "" then
        say("")
        say("Node is not installed here, and it is what stands in for the browser in this demo (401 decision 4):")
        say("the page's own scripts are run by src/web/tests/208-stand-in-browser.js under Node.  Nothing was")
        say("started.  Install Node (version 22 or later, for its WebSocket), or open src/web/203-rao-chat.html")
        say("in a browser to use the page itself.")
        os.exit(1)
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

    local stand_in = DIR .. "/src/web/tests/208-stand-in-browser.js"
    local found = io.open(stand_in, "rb")
    if found then found:close() end
    say("  " .. string.format("%-22s (issue %-4s)  %s", "208-stand-in-browser", "401",
        found and ("there, run by Node " .. version) or "NOT THERE"))

    local ctx = { dir = DIR, m = loaded, break_scene = os.getenv("RAO_PHASE4_DEMO_BREAK"), node = version,
                  scratch = DIR .. "/tmp/shared-memory/phase-4-demo" }
    local scenes
    if #missing > 0 then
        -- the scenes run phase 3's and 4's pieces together: one missing
        -- would show a home or a page that is not the design
        ctx.problem = "modules did not load: " .. table.concat(missing, ", ")
    elseif not found then
        ctx.problem = "the stand-in browser (src/web/tests/208-stand-in-browser.js) is not there"
    else
        local ready, result = pcall(require, "228-phase-4-scenes")
        if ready then
            scenes = result
            local world, why = scenes.setup(ctx)
            if world then ctx.world = world else ctx.problem = "the world could not be made: " .. tostring(why) end
        else
            ctx.problem = "the scenes (228) could not be loaded: " .. first_line(result)
        end
    end
    say("")
    say("homes: two real rao-homes in " .. ctx.scratch .. ", A listening on 127.0.0.2 and B on 127.0.0.3,")
    say("  each with one gatherer process (163, started by its starter, 164) and one device server process (187),")
    say("  with one room between them (310's world).  A web page is paired with each home: page A with A, page B")
    say("  with B, each the page's own scripts run by the stand-in browser under Node, standing in for a browser.")
    say("  Everything runs on loopback, on the real clock.")

    local order = scenes and scenes.ORDER or require("228-phase-4-scenes").ORDER
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
