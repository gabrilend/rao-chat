-- 196-test-choosing-an-address.lua — the referees of issue 307, choosing
-- an address: the reference device (190) tries its home's home-network
-- address first, with quick-wait, then its public one, with wait; and an
-- address that connects but does not answer the sealed ping (a wrong
-- token) stops the attempt, said, instead of being passed over.  Each
-- referee with a broken version also runs against it.
--
-- Run it under the loopback-only wrapper (a network namespace with only
-- `lo`): the device port listens on every address (`any`), so 127.0.0.2
-- stands for the home-network address and 127.0.0.5 for the public one;
-- 10.255.255.x has no route; 127.0.0.6 is a listener whose queue is full,
-- so a connection to it is never answered.  Its folders are under
-- RAO_TEST_ROOT when that is set, otherwise a folder of its own under
-- /dev/shm (or /tmp); removed at the end.
--
-- Run: luajit src/devices/tests/196-test-choosing-an-address.lua [PROJECT_DIR]
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
local ROOT = base .. "/rao-chat-choosing-test-" .. ffi.C.getpid()
local SERVER = DIR .. "/src/devices/187-device-server.lua"
local DEVICE = DIR .. "/src/devices/190-device.lua"
local PORT = 46307
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
local function with_broken(name, referee, broken)
    check(name, function() referee() end)
    if broken then
        check(name .. " (catches " .. broken .. ")", function()
            local ok, problem = pcall(referee, broken)
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
                              ["devices.frame-deadline"] = "2", ["devices.idle-limit"] = "5", ["devices.websocket-path"] = "/socket",
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

-- {{{ the device
local devices = 0
-- home-network, public, token → exit status, what it printed, seconds taken
local function catch_up(home_network, public, token, broken)
    devices = devices + 1
    local folder = ROOT .. "/device-" .. devices
    os.execute("mkdir -p " .. q(folder))
    write_file(folder .. "/config", "port = " .. PORT .. "\nhome-network = " .. home_network .. "\npublic = " .. public
        .. "\ntoken = " .. (token or PHONE) .. "\nwait = 2\nquick-wait = 0.5\n", "600")
    local started = socket.gettime()
    local status, said = run((broken and ("RAO_DEVICE_BROKEN=" .. q(broken) .. " ") or "") .. "luajit " .. q(DEVICE)
        .. " " .. q(folder) .. " catch-up")
    return status, said, socket.gettime() - started
end
-- }}}

os.execute("mkdir -p " .. q(ROOT))
start("any")

-- 1. Home first.
check("1. both addresses answer: the home-network one is used", function()
    local status, said = catch_up("127.0.0.2", "127.0.0.5")
    must(status == 0, "catch-up failed: " .. said)
    must(said:find("reached the home by its home-network address, 127.0.0.2 " .. PORT, 1, true),
        "not reached by the home-network address: " .. said)
end)

-- 2. Public when away.
check("2. the home-network address has no route: the public one is used", function()
    local status, said = catch_up("10.255.255.1", "127.0.0.5")
    must(status == 0, "catch-up failed: " .. said)
    must(said:find("reached the home by its public address, 127.0.0.5 " .. PORT, 1, true),
        "not reached by the public address: " .. said)
end)

-- 3. A wrong token is not hidden by trying the next address.
with_broken("3. a wrong token at the home-network address is said; the public one is not tried", function(broken)
    local status, said = catch_up("127.0.0.2", "10.255.255.2", "not-the-phone-token", broken)
    must(status ~= 0, "a wrong token caught up: " .. said)
    must(said:find("127.0.0.2 " .. PORT .. " closed the connection without a word: the token is not one this home knows",
        1, true), "the wrong token was not said: " .. said)
    must(not said:find("10.255.255.2", 1, true), "the public address was tried after the home refused: " .. said)
end, "fall-through")

check("3b. neither address answers: both are said", function()
    local status, said = catch_up("10.255.255.1", "10.255.255.2")
    must(status ~= 0 and said:find("home-network: 10.255.255.1 cannot be reached", 1, true)
        and said:find("public: 10.255.255.2 cannot be reached", 1, true), "not both said: " .. said)
end)

-- the home on 127.0.0.5 alone, so 127.0.0.6 can hold a full queue
stop()
start("127.0.0.5")
check("2b. the home-network address never answers: given up after quick-wait, then the public one", function()
    -- a listener whose queue is full: the kernel drops further connects
    local held, listener = {}, socket.tcp4()
    listener:setoption("reuseaddr", true)
    assert(listener:bind("127.0.0.6", PORT))
    assert(listener:listen(1))
    for _ = 1, 4 do
        local sock = socket.tcp4()
        sock:settimeout(0.3)
        sock:connect("127.0.0.6", PORT)
        held[#held + 1] = sock
    end
    local ok, problem = pcall(function()
        local status, said, took = catch_up("127.0.0.6", "127.0.0.5")
        must(status == 0, "catch-up failed: " .. said)
        must(said:find("reached the home by its public address", 1, true), "not reached by the public address: " .. said)
        print(string.format("     reached the public address after %.2f s (quick-wait 0.5, wait 2)", took))
        must(took >= 0.5 and took < 0.5 + 1, "took " .. took .. " s: the home-network address was not given up after quick-wait")
    end)
    for _, sock in ipairs(held) do sock:close() end
    listener:close()
    if not ok then error(problem, 0) end
end)

stop()
os.execute("rm -rf " .. q(ROOT))
print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
