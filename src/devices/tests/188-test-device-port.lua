-- 188-test-device-port.lua — the referees of issue 302, the device port:
-- a paired device's ping is answered under its own key; an unknown key
-- and clear text get nothing; a connection keeps its device; a stuck
-- connection stops nothing; the settings and the `devices` file are
-- checked before the port opens.  Each referee with a broken version also
-- runs against it (RAO_DEVICES_BROKEN, set for the server it starts).
--
-- Run it under the loopback-only wrapper (a network namespace with only
-- `lo`): the device port listens on 127.0.0.2.  Its homes and RAM folders
-- are under RAO_TEST_ROOT when that is set, otherwise a folder of its own
-- under /dev/shm (or /tmp); removed at the end.
--
-- Run: luajit src/devices/tests/188-test-device-port.lua [PROJECT_DIR]
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
local room_key = require("123-room-key")
local seal = require("124-seal")
local frames = require("125-frames")
local ram = require("161-ram-folders")
local records = require("186-device-records")

ffi.cdef [[ int getpid(void); ]]

local base = os.getenv("RAO_TEST_ROOT")
if not base or base == "" then
    base = os.execute("test -d /dev/shm && test -w /dev/shm") == 0 and "/dev/shm" or "/tmp"
end
local ROOT = base .. "/rao-chat-device-port-test-" .. ffi.C.getpid()
local SERVER = DIR .. "/src/devices/187-device-server.lua"
local ADDRESS, PORT = "127.0.0.2", 46302
local q = disk.shell_quote
local passed, failed = 0, 0

local PHONE = "tidal-ember-quilt-orchard-velvet-lantern"
local LAPTOP = "copper-meadow-sparrow-violin-granite-harbor"
local STRANGER = "a room token nobody paired as a device"

-- {{{ local function check / must / must_fail
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

-- {{{ local function write_file / read_file
local function write_file(path, text, mode)
    local handle = assert(io.open(path, "wb"))
    handle:write(text)
    handle:close()
    if mode then os.execute("chmod " .. mode .. " " .. q(path)) end
end
local function read_file(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end
-- }}}

-- {{{ local function make_home
-- name, {devices text, mode, settings to leave out} → the home folder.
local function make_home(name, options)
    options = options or {}
    local dir = ROOT .. "/" .. name
    local home = rooms.open_home(dir)
    local values = {
        ["devices.port"] = tostring(PORT), ["devices.address"] = ADDRESS,
        ["devices.frame-deadline"] = "2", ["devices.idle-limit"] = "5", ["devices.websocket-path"] = "/socket", ["gatherer.ram-root"] = ROOT .. "/ram",
    }
    for key, value in pairs(values) do
        if not (options.leave_out and options.leave_out[key]) then rooms.set_config(home, key, value) end
    end
    local devices = options.devices or ('phone.token = "' .. PHONE .. '"\nphone.own = true\n'
        .. 'laptop.token = "' .. LAPTOP .. '"\nlaptop.own = true\n')
    write_file(dir .. "/devices", devices, options.mode or "600")
    return dir
end
-- }}}

-- {{{ server start and stop
local running
local function connect(seconds)
    local sock = socket.tcp4()
    sock:settimeout(seconds or 2)
    local ok, why = sock:connect(ADDRESS, PORT)
    if not ok then sock:close(); return nil, why end
    return sock
end
local function start(home_dir, broken)
    local log = home_dir .. "/server-output"
    os.execute((broken and ("RAO_DEVICES_BROKEN=" .. q(broken) .. " ") or "")
        .. "luajit " .. q(SERVER) .. " " .. q(DIR) .. " " .. q(home_dir) .. " > " .. q(log) .. " 2>&1 &")
    local give_up = socket.gettime() + 10
    while socket.gettime() < give_up do
        local sock = connect(0.2)
        if sock then sock:close(); running = home_dir; return true end
        socket.sleep(0.1)
    end
    error("the device server did not start: " .. tostring(read_file(log)))
end
local function stop()
    if not running then return end
    local folder = ram.home_ram(ROOT .. "/ram", running) .. "/devices"
    write_file(folder .. "/stop", "")
    local give_up = socket.gettime() + 5
    while socket.gettime() < give_up do
        local sock = connect(0.2)
        if not sock then break end
        sock:close()
        socket.sleep(0.1)
    end
    running = nil
end
-- }}}

-- {{{ local function ping / read_reply / nothing_comes
local function frame_of(token, record)
    return seal.seal(room_key.key_pair(token), records.encode(record))
end
local function read_reply(sock, token)
    local frame, why = frames.read_frame(sock)
    if not frame then return nil, "no frame: " .. tostring(why) end
    local line = seal.open(room_key.key_pair(token), frame)
    if not line then return nil, "the answer does not open under the device's token" end
    return records.decode(line)
end
local function ping(sock, token, id)
    assert(sock:send(frame_of(token, { kind = "ping", id = id })))
    return read_reply(sock, token)
end
-- the connection is closed by the server with not one byte sent
local function nothing_comes(sock, seconds)
    sock:settimeout(seconds or 4)
    local data, why, partial = sock:receive(1)
    must(data == nil and (partial or "") == "", "the server sent bytes: " .. string.format("%q", tostring(data or partial)))
    must(why == "closed", "the connection was not closed (" .. tostring(why) .. ")")
end
-- }}}

local function run_server_referee(name, home, referee, broken)
    check(name, function()
        start(home)
        local ok, problem = pcall(referee)
        stop()
        if not ok then error(problem, 0) end
    end)
    if broken then
        check(name .. " (catches " .. broken .. ")", function()
            start(home, broken)
            local ok, problem = pcall(referee)
            stop()
            must(not ok, "the referee passed the broken version " .. broken)
            print("     caught (" .. broken .. "): " .. tostring(problem):gsub("^[^:]*:%d+: ", ""))
        end)
    end
end

-- 0. The record table refuses what it was not written for.
check("0. a device record is one line, and anything else is refused", function()
    local line = records.encode({ kind = "ping", id = "a-b-1" })
    must(line == "ping\ta-b-1", "a ping is not 'ping<tab>id': " .. line)
    local back = records.decode(line)
    must(back and back.kind == "ping" and back.id == "a-b-1", "a ping does not read back")
    must(records.decode("pong\tx\t12").at == "12", "a pong does not read back")
    for _, bad in ipairs({ "hello\tx", "ping", "ping\tx\ty", "ping\ta\\q", "ping\ta b",
                           "ping\t", "pong\tx\tsoon", "message\tx" }) do
        must(records.decode(bad) == nil, "decoded what it should refuse: " .. bad:gsub("\t", "<tab>"))
    end
    must(not pcall(records.encode, { kind = "ping", id = "two words" }), "encoded an id with a space")
    must(not pcall(records.encode, { kind = "ping" }), "encoded a ping without its id")
end)

os.execute("mkdir -p " .. q(ROOT))
local HOME = make_home("home")

-- 1. A paired device is answered, under its own key.
run_server_referee("1. a paired device's ping gets a pong under its own token", HOME, function()
    local sock = assert(connect())
    local reply, why = ping(sock, PHONE, "first-ping")
    must(reply, why)
    must(reply.kind == "pong" and reply.id == "first-ping", "the answer is not the ping's pong")
    must(math.abs(tonumber(reply.at) - socket.gettime()) < 5, "the pong's clock is not the home's")
    local again = ping(sock, PHONE, "second-ping")
    must(again and again.id == "second-ping", "a second ping on the connection was not answered")
    sock:close()
end, "wrong-key")

-- 1b. A record the home does not answer closes the connection.
run_server_referee("1b. a pong from a device, or a line that is no record, closes the connection unanswered", HOME, function()
    for _, line in ipairs({ records.encode({ kind = "pong", id = "x", at = 1 }), "not a record" }) do
        local sock = assert(connect())
        must((ping(sock, PHONE, "before") or {}).kind == "pong", "the ping before was not answered")
        assert(sock:send(seal.seal(room_key.key_pair(PHONE), line)))
        nothing_comes(sock)
        sock:close()
    end
end)

-- 2. An unknown key gets nothing.
run_server_referee("2. a frame no device's token opens gets not a byte", HOME, function()
    local sock = assert(connect())
    assert(sock:send(frame_of(STRANGER, { kind = "ping", id = "who" })))
    nothing_comes(sock)
    sock:close()
    local state = ram.read_state(ram.home_ram(ROOT .. "/ram", HOME) .. "/devices")
    must(state.refused == "1", "the refused frame was not counted (refused = " .. tostring(state.refused) .. ")")
end, "answer-unknown")

-- 3. Clear text gets nothing.
run_server_referee("3. clear text (an HTTP request, a health check, a short line) gets not a byte", HOME, function()
    for _, text in ipairs({ "GET / HTTP/1.1\r\nHost: home\r\n\r\n", "status\n", "hi\n" }) do
        local sock = assert(connect())
        assert(sock:send(text))
        nothing_comes(sock)
        sock:close()
    end
end)

-- 4. A connection keeps its device.
run_server_referee("4. after a ping as the phone, a frame as the laptop closes the connection", HOME, function()
    local sock = assert(connect())
    local reply = ping(sock, PHONE, "as-phone")
    must(reply and reply.kind == "pong", "the phone's ping was not answered")
    assert(sock:send(frame_of(LAPTOP, { kind = "ping", id = "as-laptop" })))
    nothing_comes(sock)
    sock:close()
    local fresh = assert(connect())
    must((ping(fresh, LAPTOP, "own-connection") or {}).kind == "pong", "the laptop on its own connection was not answered")
    fresh:close()
end, "any-key")

-- 5. A stuck connection stops nothing.
run_server_referee("5. a connection stuck mid-frame does not hold up another device", HOME, function()
    local stuck = assert(connect())
    assert(stuck:send("\0\0"))
    local sock = assert(connect())
    local started = socket.gettime()
    local reply = ping(sock, LAPTOP, "past-the-stuck-one")
    must(reply and reply.kind == "pong", "the laptop was not answered")
    must(socket.gettime() - started < 1, "the answer waited for the stuck connection")
    nothing_comes(stuck, 4)
    stuck:close()
    sock:close()
end)

-- 6. Settings and the devices file are checked before the port opens.
-- {{{ local function refuses
local function refuses(home_dir, words)
    local log = home_dir .. "/server-output"
    local status = os.execute("timeout 5 luajit " .. q(SERVER) .. " " .. q(DIR) .. " " .. q(home_dir) .. " > " .. q(log) .. " 2>&1")
    must(status ~= 0, "the server started")
    local said = read_file(log) or ""
    must(said:find(words, 1, true), "the refusal does not say '" .. words .. "': " .. said)
    local sock = connect(0.3)
    must(sock == nil, "something listens on the device port")
end
-- }}}
check("6a. no devices.port: the server stops naming the line to add", function()
    refuses(make_home("no-port", { leave_out = { ["devices.port"] = true } }), "devices.port = <value>")
end)
check("6b. a devices file others may read: refused, naming chmod 600", function()
    refuses(make_home("open-file", { mode = "644" }), "chmod 600")
end)
check("6c. an entry without own = true: refused, naming the entry", function()
    refuses(make_home("not-own", { devices = 'phone.token = "' .. PHONE .. '"\nphone.own = true\nfriend.token = "' .. LAPTOP .. '"\n' }),
        "friend has no own = true")
end)
check("6d. the device port is a mailbox's port: refused", function()
    local dir = make_home("same-port")
    local home = rooms.open_home(dir)
    rooms.make_mailbox(home, { label = "direct", kind = "direct", port = PORT })
    refuses(dir, "is a mailbox's port")
end)

stop()
os.execute("rm -rf " .. q(ROOT))
print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
