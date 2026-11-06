-- 197-test-check-in.lua — the referees of issue 308, the locked-screen
-- check-in: the deck (190's M.deck) deals the eleven cards -5 ... +5
-- without putting any back, so each pass through it averages exactly the
-- base wait, and is shuffled again when it runs out; and 190's
-- `check-in` catches up after each wait with no connection kept between.
-- Each referee with a broken version also runs against it.
--
-- The deck's referees need no network.  The check-in's runs under the
-- loopback-only wrapper (a network namespace with only `lo`): the device
-- port listens on 127.0.0.2.  Its folders are under RAO_TEST_ROOT when
-- that is set, otherwise a folder of its own under /dev/shm (or /tmp);
-- removed at the end.
--
-- Run: luajit src/devices/tests/197-test-check-in.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>".

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/devices/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local ffi = require("ffi")
local socket = require("socket")
local rooms = require("002-room-folders")
local disk = require("003-disk")
local ram = require("161-ram-folders")

ffi.cdef [[ int getpid(void); ]]

local base = os.getenv("RAO_TEST_ROOT")
if not base or base == "" then
    base = os.execute("test -d /dev/shm && test -w /dev/shm") == 0 and "/dev/shm" or "/tmp"
end
local ROOT = base .. "/rao-chat-check-in-test-" .. ffi.C.getpid()
local SERVER = DIR .. "/src/devices/187-device-server.lua"
local DEVICE = DIR .. "/src/devices/190-device.lua"
local PORT = 46308
local PHONE = "willow-copper-ember-saddle-lantern-quarry"
local q = disk.shell_quote
local passed, failed = 0, 0

-- {{{ local function check / must
local ONLY = os.getenv("ONLY")
local function check(claim, test)
    if ONLY and not claim:find(ONLY, 1, true) then return end
    local ok, problem = pcall(test)
    if ok then
        passed = passed + 1
        print("PASS " .. claim)
    else
        failed = failed + 1
        print("FAIL " .. claim .. ": " .. tostring(problem))
    end
end
local function must(condition, words)
    if not condition then error(words, 2) end
end
local device = dofile(DIR .. "/src/devices/190-device.lua")
local function with_broken(name, referee, broken)
    check(name, function() referee() end)
    if broken then
        check(name .. " (catches " .. broken .. ")", function()
            device.broken = broken
            local ok, problem = pcall(referee, broken)
            device.broken = ""
            must(not ok, "the referee passed the broken version " .. broken)
            print("     caught (" .. broken .. "): " .. (tostring(problem):gsub("^[^:]*:%d+: ", ""):gsub("\n+$", "")))
        end)
    end
end
-- }}}

-- {{{ local function read_file / write_file / run
local function read_file(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end
local function write_file(path, text, mode)
    local handle = assert(io.open(path, "wb"))
    handle:write(text)
    handle:close()
    if mode then os.execute("chmod " .. mode .. " " .. q(path)) end
end
local function run(command)
    local out = ROOT .. "/run-output"
    local status = os.execute(command .. " > " .. q(out) .. " 2>&1")
    return status, read_file(out) or ""
end
-- }}}

-- {{{ the home, listening on every address
local HOME = ROOT .. "/home"
local function connect(address, seconds)
    local sock = socket.tcp4()
    sock:settimeout(seconds or 2)
    local ok = sock:connect(address, PORT)
    if not ok then sock:close(); return nil end
    return sock
end
local listening
local function start(address)
    listening = address == "any" and "127.0.0.2" or address
    local h = rooms.open_home(HOME)
    for key, value in pairs({ ["devices.port"] = tostring(PORT), ["devices.address"] = address,
                              ["devices.frame-deadline"] = "2", ["devices.idle-limit"] = "5",
                              ["gatherer.ram-root"] = ROOT .. "/ram" }) do
        rooms.set_config(h, key, value)
    end
    write_file(HOME .. "/devices", 'phone.token = "' .. PHONE .. '"\nphone.own = true\n', "600")
    os.execute("luajit " .. q(SERVER) .. " " .. q(DIR) .. " " .. q(HOME) .. " > " .. q(ROOT .. "/server-output") .. " 2>&1 &")
    local give_up = socket.gettime() + 10
    while socket.gettime() < give_up do
        local sock = connect(listening, 0.2)
        if sock then sock:close(); return end
        socket.sleep(0.1)
    end
    error("the device server did not start: " .. tostring(read_file(ROOT .. "/server-output")))
end
local function stop()
    write_file(ram.home_ram(ROOT .. "/ram", HOME) .. "/devices/stop", "")
    local give_up = socket.gettime() + 5
    while socket.gettime() < give_up do
        local sock = connect(listening, 0.2)
        if not sock then break end
        sock:close()
        socket.sleep(0.1)
    end
end
-- }}}

os.execute("mkdir -p " .. q(ROOT))

-- 1. Without replacement.
with_broken("1. eleven deals from a fresh deck are the eleven cards -5 ... +5, once each", function()
    for _ = 1, 50 do
        local deck, seen = device.deck.new(), {}
        for _ = 1, 11 do
            local card = deck:deal()
            must(card >= -5 and card <= 5 and card % 1 == 0, "dealt " .. tostring(card))
            must(not seen[card], "card " .. card .. " was dealt twice in one pass")
            seen[card] = true
        end
    end
end, "replace")

-- 2. Averages exactly 30.
with_broken("2. any whole number of passes through the deck averages exactly 30 s a wait", function()
    local deck, total = device.deck.new(), 0
    for pass = 1, 20 do
        for _ = 1, 11 do total = total + 30 + deck:deal() end
        must(total == 30 * 11 * pass, "after " .. pass .. " pass(es) the waits add up to " .. total
            .. ", not " .. 30 * 11 * pass)
    end
end, "replace")

-- 3. Reshuffled.
with_broken("3. the twelfth deal starts a new deck, and decks are not always in the same order", function()
    local deck, orders = device.deck.new(), {}
    for _ = 1, 20 do
        local order = {}
        for i = 1, 11 do order[i] = deck:deal() end
        orders[table.concat(order, " ")] = true
    end
    local distinct = 0
    for _ in pairs(orders) do distinct = distinct + 1 end
    must(distinct > 1, "twenty passes through the deck came in " .. distinct .. " order(s)")
end, "no-reshuffle")

check("3b. the shuffle is fair: over 2200 fresh decks each card comes first about 200 times", function()
    local first = {}
    for _ = 1, 2200 do
        local card = device.deck.new():deal()
        first[card] = (first[card] or 0) + 1
    end
    for _, card in ipairs(device.deck.CARDS) do
        local n = first[card] or 0
        must(n > 130 and n < 270, "card " .. card .. " came first " .. n .. " times in 2200")
    end
end)

-- 4. A check-in is a catch-up, and no connection is kept.
check("4. check-in with a 6 s base: catches up after each wait, and keeps no connection between", function()
    start("127.0.0.2")
    local ok, problem = pcall(function()
        local folder = ROOT .. "/phone"
        os.execute("mkdir -p " .. q(folder))
        write_file(folder .. "/config", "port = " .. PORT .. "\nhome-network = 127.0.0.2\npublic = unknown\ntoken = "
            .. PHONE .. "\nwait = 2\nquick-wait = 0.5\ncheck-in = 6\n", "600")
        os.execute("luajit " .. q(DEVICE) .. " " .. q(folder) .. " check-in --for 25 > " .. q(folder .. "/output") .. " 2>&1 &")
        local samples, held = 0, 0
        local pattern = ":%x+ 0200007F:" .. string.format("%04X", PORT) .. " 01"
        local give_up = socket.gettime() + 27
        local said = ""
        while socket.gettime() < give_up do
            said = read_file(folder .. "/output") or ""
            if said:find("checked in %d+ time") then break end
            -- between check-ins the device holds no connection to the home
            local listing = io.popen("cat /proc/net/tcp 2>/dev/null")
            local text = listing:read("*a")
            listing:close()
            local open = 0
            for _ in text:gmatch(pattern) do open = open + 1 end
            samples = samples + 1
            if open > 0 then held = held + 1 end
            socket.sleep(0.2)
        end
        must(said:find("checked in %d+ time"), "the check-in loop did not end: " .. said)
        local times = tonumber(said:match("checked in (%d+) time"))
        must(times >= 2 and said:find("checked in %d+ time%(s%), 0 failed"), "too few check-ins: " .. said)
        local waits = {}
        for wait in said:gmatch("next check%-in in (%d+) s") do waits[#waits + 1] = tonumber(wait) end
        for _, wait in ipairs(waits) do must(wait >= 1 and wait <= 11, "a wait of " .. wait .. " s from a 6 s base") end
        must(said:find("checked in: caught up with 127.0.0.2", 1, true), "a check-in did not catch up: " .. said)
        must(samples > 20 and held < samples / 4, "a connection to the home was open in " .. held .. " of "
            .. samples .. " looks: one is kept between check-ins")
    end)
    stop()
    if not ok then error(problem, 0) end
end)

os.execute("rm -rf " .. q(ROOT))
print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
