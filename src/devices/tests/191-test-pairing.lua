-- 191-test-pairing.lua — the referees of issue 303, pairing a device:
-- `189-pair add` gives a device that works; `remove` unpairs at once; the
-- reference device's `test` (190) names each failure apart; the devices
-- file is private at every moment.  Each referee with a broken version
-- also runs against it.
--
-- Run it under the loopback-only wrapper (a network namespace with only
-- `lo`): the device port listens on 127.0.0.2, a silent listener on
-- 127.0.0.3.  Its folders are under RAO_TEST_ROOT when that is set,
-- otherwise a folder of its own under /dev/shm (or /tmp); removed at the
-- end.
--
-- Run: luajit src/devices/tests/191-test-pairing.lua [PROJECT_DIR]
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
local ROOT = base .. "/rao-chat-pairing-test-" .. ffi.C.getpid()
local SERVER = DIR .. "/src/devices/187-device-server.lua"
local PAIR = DIR .. "/src/devices/189-pair.lua"
local DEVICE = DIR .. "/src/devices/190-device.lua"
local ADDRESS, PORT = "127.0.0.2", 46303
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
-- }}}

-- {{{ local function read_file / write_file / run
local function read_file(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end
local function write_file(path, text)
    local handle = assert(io.open(path, "wb"))
    handle:write(text)
    handle:close()
end
-- command → exit status, what it printed (both streams)
local function run(command)
    local out = ROOT .. "/run-output"
    local status = os.execute(command .. " > " .. q(out) .. " 2>&1")
    return status, read_file(out) or ""
end
-- }}}

-- {{{ the home and its server
local HOME = ROOT .. "/home"
local function make_home()
    local home = rooms.open_home(HOME)
    for key, value in pairs({ ["devices.port"] = tostring(PORT), ["devices.address"] = ADDRESS,
                              ["devices.frame-deadline"] = "2", ["gatherer.ram-root"] = ROOT .. "/ram" }) do
        rooms.set_config(home, key, value)
    end
end
local running = false
local function connect(seconds)
    local sock = socket.tcp4()
    sock:settimeout(seconds or 2)
    local ok = sock:connect(ADDRESS, PORT)
    if not ok then sock:close(); return nil end
    return sock
end
local function start()
    os.execute("luajit " .. q(SERVER) .. " " .. q(DIR) .. " " .. q(HOME) .. " > " .. q(ROOT .. "/server-output") .. " 2>&1 &")
    local give_up = socket.gettime() + 10
    while socket.gettime() < give_up do
        local sock = connect(0.2)
        if sock then sock:close(); running = true; return end
        socket.sleep(0.1)
    end
    error("the device server did not start: " .. tostring(read_file(ROOT .. "/server-output")))
end
local function stop()
    if not running then return end
    write_file(ram.home_ram(ROOT .. "/ram", HOME) .. "/devices/stop", "")
    local give_up = socket.gettime() + 5
    while socket.gettime() < give_up do
        local sock = connect(0.2)
        if not sock then break end
        sock:close()
        socket.sleep(0.1)
    end
    running = false
end
-- }}}

-- {{{ pairing and the device
local function pair(command, label, broken)
    return run((broken and ("RAO_PAIR_BROKEN=" .. q(broken) .. " ") or "") .. "luajit " .. q(PAIR) .. " "
        .. q(DIR) .. " " .. q(HOME) .. " " .. command .. (label and (" " .. q(label)) or ""))
end
-- the lines `add` printed, plus the device's own wait → a device folder
local function device_from(printed, name, changes)
    local folder = ROOT .. "/" .. name
    os.execute("mkdir -p " .. q(folder))
    local lines = {}
    for line in printed:gmatch("[^\n]+") do
        local key = line:match("^([%w%-]+) = ")
        if key and not (changes and changes[key]) then lines[#lines + 1] = line end
    end
    for key, value in pairs(changes or {}) do lines[#lines + 1] = key .. " = " .. value end
    lines[#lines + 1] = "wait = 1"
    write_file(folder .. "/config", table.concat(lines, "\n") .. "\n")
    return folder
end
local function device_test(folder, broken, public)
    return run((broken and ("RAO_DEVICE_BROKEN=" .. q(broken) .. " ") or "") .. "luajit " .. q(DEVICE) .. " "
        .. q(folder) .. " test" .. (public and " --public" or ""))
end
-- }}}

local function with_broken(name, referee, broken)
    check(name, function() referee() end)
    if broken then
        check(name .. " (catches " .. broken .. ")", function()
            local ok, problem = pcall(referee, broken)
            must(not ok, "the referee passed the broken version " .. broken)
            print("     caught (" .. broken .. "): " .. tostring(problem):gsub("^[^:]*:%d+: ", ""))
        end)
    end
end

os.execute("mkdir -p " .. q(ROOT))
make_home()
start()
local phone_lines

-- 1. Pairing gives a working device.
with_broken("1. `add phone`, then the device's test with the printed lines: answered", function(broken)
    pair("remove", "phone")
    local status, printed = pair("add", "phone", broken)
    must(status == 0, "add failed: " .. printed)
    must(printed:find("port = " .. PORT, 1, true) and printed:find("home-network = " .. ADDRESS, 1, true)
        and printed:find("public = unknown", 1, true), "add did not print the settings: " .. printed)
    local token = printed:match("token = (%S+)")
    must(token and select(2, token:gsub("%-", "")) == 5, "the token is not six words: " .. tostring(token))
    local said
    status, said = device_test(device_from(printed, "phone"))
    must(status == 0 and said:find("^answered in %d+ ms by " .. ADDRESS:gsub("%.", "%%.")), "the test: " .. said)
    if not broken then phone_lines = printed end
end, "trailing-space")

check("1b. `list` names the devices and shows no token; a second `add phone` is refused", function()
    local status, listed = pair("list")
    must(status == 0 and listed == "phone\n", "list: " .. listed)
    local again, said = pair("add", "phone")
    must(again ~= 0 and said:find("already paired", 1, true), "a second phone: " .. said)
    local bad, why = pair("add", "has space")
    must(bad ~= 0 and why:find("a label is", 1, true), "a label with a space: " .. why)
end)

-- 4. The file is private at every moment.
with_broken("4. the devices file is mode 600, whole, and was never readable by others", function(broken)
    -- 189 as a module, its temporary file's mode looked at when it is
    -- opened for writing, before a byte of tokens is in it
    local saved_arg = arg
    arg = { DIR }
    local pairing = dofile(PAIR)
    arg = saved_arg
    pairing.broken = broken or ""
    local mode_seen
    local real_open = io.open
    io.open = function(path, how)
        if tostring(path):find(".pairing-", 1, true) and how == "wb" then
            local listing = io.popen("stat -c %a " .. q(path))
            mode_seen = listing:read("*l")
            listing:close()
        end
        return real_open(path, how)
    end
    local ok, problem = pcall(pairing.write_private, ROOT .. "/private-check", "x\n")
    io.open = real_open
    must(ok, problem)
    must(mode_seen == "600", "the temporary file was mode " .. tostring(mode_seen) .. " while it was written")
    local listing = io.popen("stat -c %a " .. q(HOME .. "/devices"))
    local mode = listing:read("*l")
    listing:close()
    must(mode == "600", "the devices file is mode " .. tostring(mode))
    local left = io.popen("ls -a " .. q(HOME) .. " " .. q(ROOT) .. " | grep -c '^[^/]*\\.pairing-'"):read("*l")
    must(left == "0", "a temporary file was left behind")
end, "open-temporary")

-- 3. Each failure is named apart.
with_broken("3. a closed port, no route, a wrong token and a silent listener are told apart", function(broken)
    local silent = socket.tcp4()
    silent:setoption("reuseaddr", true)
    assert(silent:bind("127.0.0.3", PORT))
    assert(silent:listen(8))
    local cases = {
        { { port = "46399" }, "nothing listens at " .. ADDRESS .. " 46399 (refused)" },
        { { ["home-network"] = "10.255.255.1" }, "10.255.255.1 cannot be reached" },
        { { token = "not-the-phone-token" }, "closed the connection without a word: the token is not one this home knows" },
        { { ["home-network"] = "127.0.0.3" }, "127.0.0.3 " .. PORT .. " said nothing within 1 s" },
    }
    local ok, problem = pcall(function()
        for index, case in ipairs(cases) do
            local status, said = device_test(device_from(phone_lines, "failure-" .. index, case[1]), broken)
            must(status ~= 0, "case " .. index .. " passed: " .. said)
            must(said:find(case[2], 1, true), "case " .. index .. " said: " .. said)
        end
    end)
    silent:close()
    if not ok then error(problem, 0) end
end, "one-message")

check("3c. a pong that answers another ping is not taken as an answer", function()
    -- a stand-in home on 127.0.0.4 that answers one ping with a pong for another id
    local token = phone_lines:match("token = (%S+)")
    local ready = ROOT .. "/stand-in-ready"
    write_file(ROOT .. "/stand-in.lua", table.concat({
        "dofile(" .. string.format("%q", DIR) .. " .. '/src/room-folders/001-load-path.lua')(" .. string.format("%q", DIR) .. ")",
        "local socket, seal, frames = require('socket'), require('124-seal'), require('125-frames')",
        "local pair, records = require('123-room-key').key_pair(" .. string.format("%q", token) .. "), require('186-device-records')",
        "local listener = socket.tcp4(); listener:setoption('reuseaddr', true)",
        "assert(listener:bind('127.0.0.4', " .. PORT .. ")); assert(listener:listen(1)); listener:settimeout(10)",
        "io.open(" .. string.format("%q", ready) .. ", 'w'):close()",
        "local conn = listener:accept(); if not conn then os.exit(1) end",
        "conn:settimeout(3); frames.read_frame(conn)",
        "frames.write_frame(conn, seal.seal(pair, records.encode({ kind = 'pong', id = 'another-ping', at = 1 })))",
        "conn:close(); listener:close()",
    }, "\n") .. "\n")
    os.execute("luajit " .. q(ROOT .. "/stand-in.lua") .. " > /dev/null 2>&1 &")
    local give_up = socket.gettime() + 5
    while not read_file(ready) and socket.gettime() < give_up do socket.sleep(0.05) end
    local status, said = device_test(device_from(phone_lines, "stand-in", { ["home-network"] = "127.0.0.4" }))
    must(status ~= 0, "the device took another ping's pong: " .. said)
    must(said:find("not this ping's pong", 1, true), said)
end)

check("3b. --public with no public address known says there is none to try", function()
    local status, said = device_test(device_from(phone_lines, "public"), nil, true)
    must(status ~= 0 and said:find('no address to try', 1, true), said)
end)

-- 2. Unpairing works at once.
check("2. `remove phone`, then the old settings: closed without a word, with no restart", function()
    local status, said = pair("remove", "phone")
    must(status == 0, "remove: " .. said)
    must(not (read_file(HOME .. "/devices") or ""):find("phone", 1, true), "the phone's lines are still in the file")
    status, said = device_test(device_from(phone_lines, "phone"))
    must(status ~= 0 and said:find("closed the connection without a word", 1, true), "the old phone: " .. said)
    local re, printed = pair("add", "phone")
    must(re == 0, "pairing again: " .. printed)
    status, said = device_test(device_from(printed, "phone-again"))
    must(status == 0, "the phone paired again: " .. said)
end)

check("2b. the owner's own lines in the devices file are kept by add and remove", function()
    local path = HOME .. "/devices"
    local text = read_file(path)
    write_file(path, "# the owner's note\n" .. text)
    os.execute("chmod 600 " .. q(path))
    pair("add", "tablet")
    pair("remove", "tablet")
    must(read_file(path):find("^# the owner's note\n"), "the owner's note is gone")
    must(not read_file(path):find("tablet", 1, true), "the tablet is still there")
end)

stop()
os.execute("rm -rf " .. q(ROOT))
print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
