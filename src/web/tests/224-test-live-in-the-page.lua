-- 224-test-live-in-the-page.lua — the referees of issue 407, live while
-- the page is open: a message filed on the home reaches the live page's
-- mirror within two seconds; pings keep a listening page connected past
-- the home's idle limit; after the home stops and starts again the page
-- reconnects by itself, catches up what was filed meanwhile, and its
-- next wait is 5 seconds again; the waits double to the cap; the home's
-- problem lines are in the error strip; a phone (the reference device,
-- 190) and the page live together hear each other.  Each referee with a
-- broken version also runs against it.
--
-- The page is the stand-in browser (208) under Node, speaking WebSocket
-- to a real device server (187); no gatherer runs, so where a typed file
-- must be filed the referee files it as the gatherer's filer does (as
-- 306's referees do).  Run it under the loopback-only wrapper (a network
-- namespace with only `lo`): the device port listens on 127.0.0.2.
--
-- Run: luajit src/web/tests/224-test-live-in-the-page.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>".

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/web/tests/[^/]+$")
end
local t = dofile(DIR .. "/src/web/tests/214-kit-for-page-tests.lua").new(DIR, "live-test", { port = 46407 })
local check, must, with_broken, q = t.check, t.must, t.with_broken, t.q
local rooms = require("002-room-folders")
local ram = require("161-ram-folders")
local message_log = require("081-message-log")
local mirror = require("192-mirror")
local socket = require("socket")

if not t.has_node then
    t.check("every referee", function() error("STOPPED: node is not installed, so the page's scripts cannot be run outside a browser here") end)
    t.finish()
end

local home = t.make_home()
t.start()
local SETTINGS = t.file_of(t.pair("laptop"))
local IDLE = 4   -- the kit's devices.idle-limit

-- {{{ helpers
local function wait_until(condition, seconds)
    local give_up = t.now() + seconds
    while t.now() < give_up do
        if condition() then return true end
        t.sleep(0.05)
    end
    return condition()
end
-- the page live for seconds, in the background → a function giving what it printed
local function live(seconds, broken, more)
    return t.page_background("live --settings " .. q(SETTINGS) .. " --for " .. seconds .. (more or ""), broken)
end
local function is_live(output, seconds)
    return wait_until(function() return output():find(" state live: ", 1, true) ~= nil end, seconds or 5)
end
local function ended(output, seconds)
    return wait_until(function() return output():find(" end %a+, tries %d+") ~= nil end, seconds)
end
local function newest_path(tag)
    local names = mirror.rooms(t.HOME_RAM)[tag].names
    return home.mailbox_of[tag] .. "/inbox/" .. tag .. "/" .. names[#names]
end
local function file_message(tag, text)
    t.add_message(tag, text)
    t.write_inbox()
    return newest_path(tag)
end
-- }}}

-- {{{ referee 1: pushed at once
check("1: a message filed on the home while the page is live reaches its mirror within two seconds, without another catch-up", function()
    local output = live(8)
    must(is_live(output), "the page did not go live: " .. output())
    local path = file_message(home.coffee, "pushed to the page")
    local filed = t.now()
    must(wait_until(function() return output():find(" got " .. path, 1, true) ~= nil end, 3),
        "the page did not get " .. path .. ": " .. output())
    must(t.now() - filed <= 2.2, string.format("it took %.1f s", t.now() - filed))
    must(select(2, output():gsub(" caught up: ", "")) == 1, "it caught up again: " .. output())
    must(ended(output, 10), "the page did not end: " .. output())
end)
-- }}}

-- {{{ referee 2: kept alive
local function kept_alive(broken)
    local output = live(3 * IDLE, broken)
    must(is_live(output), "the page did not go live: " .. output())
    must(ended(output, 3 * IDLE + 5), "the page did not end: " .. output())
    must(not output():find("connection lost", 1, true), "the home closed it: " .. output())
    must(output():find(" end live, tries 1, ", 1, true), "not live to the end on its first connection: " .. output())
end
with_broken("2: live for three times the home's idle limit, with its pings, the page is still connected", kept_alive,
    "no-keep-alive")
-- }}}

-- {{{ referee 3: back after a drop
local function back_after_drop(broken)
    local output = live(26, broken)
    must(is_live(output), "the page did not go live: " .. output())
    t.stop()
    must(wait_until(function() return output():find("errors retrying: connection lost: [^\n]*%(retrying in 5s%)") ~= nil end, 4),
        "the drop was not said with a retry in 5s: " .. output())
    local path = file_message(home.lobby, "filed while the page was away")
    t.start()
    must(wait_until(function() return output():find(" got " .. path, 1, true) ~= nil end, 9),
        "the page did not come back and get " .. path .. ": " .. output())
    -- the next drop starts the waits again from 5 seconds
    local lost_before = select(2, output():gsub("%(retrying in 5s%)", ""))
    t.stop()
    must(wait_until(function() return select(2, output():gsub("%(retrying in 5s%)", "")) > lost_before end, 4),
        "a drop after a catch-up did not wait 5s again: " .. output())
    t.start()
    must(wait_until(function() return select(2, output():gsub(" caught up: ", "")) == 3 end, 9),
        "the page did not catch up a third time: " .. output())
    must(ended(output, 20), "the page did not end: " .. output())
end
-- a referee stopped part way (a broken version caught) may leave the home stopped
local function home_running()
    local sock = socket.tcp4()
    sock:settimeout(0.5)
    local ok = sock:connect(t.ADDRESS, t.PORT)
    sock:close()
    if not ok then t.start() end
end
with_broken("3: the home stopped and started again: the page reconnects by itself, gets what was filed meanwhile, and waits 5s after its next drop",
    back_after_drop, "no-retry")
home_running()
-- }}}

-- {{{ referee 4: the waits
check("4: the waits double from 5 seconds to the cap of 300; the countdown is in seconds under a minute, minutes above", function()
    local status, out = t.page("waits")
    must(status == 0 and out:find("^waits 5 10 20 40 80 160 300 300 300\n"), out)
    must(out:find("\ncountdown 40 40s\n", 1, true) and out:find("\ncountdown 59 59s\n", 1, true)
        and out:find("\ncountdown 240 4m\n", 1, true), out)
end)
-- }}}

-- {{{ referee 5: the home's problems
check("5: a problem. line in a mailbox's state is in the error strip, named by its mailbox, as 183's `problems`", function()
    local mailbox = home.mailbox_of[home.coffee]
    local folder = t.HOME_RAM .. "/" .. mailbox
    local state = ram.read_state(folder)
    state["problem.copies"] = "the copy to the sharing folder failed: no space"
    ram.write_state(folder, state)
    local want = require("183-viewer").problems_text(t.HOME_RAM):gsub("\n$", "")
    must(want:find("copies: the copy", 1, true), "183 prints no problem: " .. want)
    local output = live(3)
    must(ended(output, 8), "the page did not end: " .. output())
    must(output():find("errors: " .. want, 1, true), "the strip: " .. output())
    state["problem.copies"] = nil
    ram.write_state(folder, state)
end)
-- }}}

-- {{{ referee 6: the page and a phone together
check("6: a phone and the page live together: what the phone sends reaches the page, and what the page sends reaches the phone", function()
    local status, said = t.run("luajit " .. q(t.PAIR) .. " " .. q(DIR) .. " " .. q(t.HOME) .. " add phone")
    must(status == 0, said)
    local phone = t.ROOT .. "/phone"
    os.execute("mkdir -p " .. q(phone))
    local lines = said:match("these lines:\n(.*)$")
    for _, more in ipairs({ "wait = 2", "quick-wait = 0.5", "keep-alive = 1" }) do
        if not ("\n" .. lines):find("\n" .. more:match("^%S+") .. " =", 1, true) then lines = lines .. more .. "\n" end
    end
    t.write_file(phone .. "/config", lines, "600")
    local device = DIR .. "/src/devices/190-device.lua"
    os.execute("luajit " .. q(device) .. " " .. q(phone) .. " live --for 14 > " .. q(phone .. "/live-output") .. " 2>&1 &")
    local function phone_said() return t.read_file(phone .. "/live-output") or "" end
    must(wait_until(function() return phone_said():find("caught up", 1, true) ~= nil end, 6), "the phone: " .. phone_said())
    local output = live(12, nil, " --write 1 --room " .. home.quiet .. " --text " .. q(t.file_of("from the page to the phone"))
        .. " --signature " .. q(t.file_of("Ann")))
    must(is_live(output), "the page did not go live: " .. output())
    -- the gatherer's filer (played here, as in 306's referees) files what reaches typed/
    local function file_typed(text)
        local queue = t.HOME_RAM .. "/" .. home.mailbox_of[home.quiet] .. "/typed"
        local found
        must(wait_until(function()
            for _, name in ipairs(ram.waiting(queue)) do
                local bytes = t.read_file(queue .. "/" .. name)
                if bytes and bytes:find(text, 1, true) then found = name; return true end
            end
        end, 5), "'" .. text .. "' did not reach the gatherer's typed/")
        local bytes = assert(ram.take(queue, found))
        os.remove(queue .. "/working/" .. found)
        local typed = assert(ram.decode_typed(bytes))
        message_log.append(rooms.open_home(t.HOME_RAM .. "/" .. home.mailbox_of[home.quiet] .. "/home"), home.quiet,
            { id = ram.typed_id(found, bytes), from = "me", written = typed.written, arrived = typed.written, text = typed.text })
        t.write_inbox()
        return home.mailbox_of[home.quiet] .. "/inbox/" .. home.quiet .. "/" .. typed.written .. "-" .. ram.typed_id(found, bytes)
    end
    -- the page types first (its answer comes while it listens), then the phone
    local from_page = file_typed("from the page to the phone")
    must(wait_until(function() return t.read_file(phone .. "/mirror/" .. from_page) ~= nil end, 3),
        "the phone did not hear the page: " .. phone_said())
    must(output():find(" typed ", 1, true), "the page typed nothing: " .. output())
    must(require("183-viewer").write(phone .. "/mirror", home.quiet, "from the phone to the page", "Bo", os.time()),
        "183 could not write into the phone's mirror")
    local from_phone = file_typed("from the phone to the page")
    must(wait_until(function() return output():find(" got " .. from_phone, 1, true) ~= nil end, 3),
        "the page did not hear the phone: " .. output())
    must(ended(output, 12), "the page did not end: " .. output())
    must(output():find(", pending 0\n", 1, true), "the page's typed file is still waiting: " .. output())
end)
-- }}}

t.finish()
