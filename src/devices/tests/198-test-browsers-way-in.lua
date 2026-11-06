-- 198-test-browsers-way-in.lua — the referees of issue 309, the browser's
-- way in: the device port answers a WebSocket upgrade on
-- devices.websocket-path with the standard's accept value and nothing
-- else; any other request gets not a byte; after the upgrade a 302 frame
-- in a binary message is answered in one; an unmasked message, a text
-- message, or a message that is not exactly one frame closes the
-- connection; and the reference device, speaking as a browser, catches up
-- and is pushed to through it.  Each referee with a broken version also
-- runs against it.
--
-- The home's folder is written as its gatherers write it, with no
-- gatherer running.  Run it under the loopback-only wrapper (a network
-- namespace with only `lo`): the device port listens on 127.0.0.2.  Its
-- folders are under RAO_TEST_ROOT when that is set, otherwise a folder of
-- its own under /dev/shm (or /tmp); removed at the end.
--
-- Run: luajit src/devices/tests/198-test-browsers-way-in.lua [PROJECT_DIR]
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
local message_log = require("081-message-log")
local ram = require("161-ram-folders")
local inbox = require("181-inbox-files")
local viewer = require("183-viewer")
local mirror = require("192-mirror")

ffi.cdef [[ int getpid(void); ]]

local base = os.getenv("RAO_TEST_ROOT")
if not base or base == "" then
    base = os.execute("test -d /dev/shm && test -w /dev/shm") == 0 and "/dev/shm" or "/tmp"
end
local ROOT = base .. "/rao-chat-websocket-test-" .. ffi.C.getpid()
local SERVER = DIR .. "/src/devices/187-device-server.lua"
local DEVICE = DIR .. "/src/devices/190-device.lua"
local ADDRESS, PORT = "127.0.0.2", 46309
local PHONE = "harbor-lantern-violet-cobalt-meadow-thistle"
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
local function write_file(path, text, mode)
    local handle = assert(io.open(path, "wb"))
    handle:write(text)
    handle:close()
    if mode then os.execute("chmod " .. mode .. " " .. q(path)) end
end
-- command → exit status, what it printed (both streams)
local function run(command)
    local out = ROOT .. "/run-output"
    local status = os.execute(command .. " > " .. q(out) .. " 2>&1")
    return status, read_file(out) or ""
end
-- }}}

-- {{{ the home: two mailboxes, their inbox written as their gatherers would
local HOME = ROOT .. "/home"
local HOME_RAM
local home = {}
local function first_variants()
    local config = {}
    local listing = io.popen("ls " .. DIR .. "/src/*/[0-9][0-9][0-9]-options.lua")
    for path in listing:lines() do
        for _, choice in ipairs(dofile(path)) do
            if choice.config_key ~= "" then config[choice.config_key] = choice.variants[1].name end
        end
    end
    listing:close()
    return config
end
-- every gatherer's inbox and state written again from its RAM home
local function write_inbox()
    for mailbox, tags in pairs(home.mailboxes) do
        local folder = HOME_RAM .. "/" .. mailbox
        inbox.write_all(folder, rooms.open_home(folder .. "/home"), tags, home.disk)
        ram.write_state(folder, { pid = "1", started = "1000000000", ["last-sync"] = tostring(os.time()) })
    end
end
local function ram_home_of(tag) return rooms.open_home(HOME_RAM .. "/" .. home.mailbox_of[tag] .. "/home") end
local written = 1000000100
local function add_message(tag, text)
    written = written + 10
    local id = message_log.new_message_id()
    message_log.append(ram_home_of(tag), tag, { id = id, from = "10.0.0.9 5000", written = written,
        arrived = written + 1, text = text })
    return id
end
local function make_home()
    local h = rooms.open_home(HOME)
    for key, value in pairs(first_variants()) do rooms.set_config(h, key, value) end
    for key, value in pairs({ ["devices.port"] = tostring(PORT), ["devices.address"] = ADDRESS,
                              ["devices.frame-deadline"] = "2", ["devices.websocket-path"] = "/the-socket", ["gatherer.ram-root"] = ROOT .. "/ram" }) do
        rooms.set_config(h, key, value)
    end
    home.disk = h
    home.lobby = rooms.make_room(h, { label = "lobby", token = "browser way in lobby", kind = "group", parent = "",
        members = {}, filed_under = "", mailbox_port = 48131 })
    home.coffee = rooms.make_room(h, { label = "coffee", token = "browser way in coffee", kind = "group", parent = "",
        members = {}, filed_under = home.lobby, mailbox_port = 48132 })
    home.quiet = rooms.make_room(h, { label = "quiet", token = "browser way in quiet", kind = "group", parent = "",
        members = {}, filed_under = home.lobby, mailbox_port = 48133 })
    HOME_RAM = ram.home_ram(ROOT .. "/ram", HOME)
    home.mailboxes, home.mailbox_of = {}, {}
    for _, mailbox in ipairs(rooms.read_mailboxes(h)) do
        local tags = rooms.list_rooms_by_mailbox(h, mailbox.tag)
        home.mailboxes[mailbox.tag] = tags
        for _, tag in ipairs(tags) do home.mailbox_of[tag] = mailbox.tag end
        local folder = ram.layout(HOME_RAM, mailbox.tag)
        ram.load(HOME, folder .. "/home", tags)
    end
    home.first = add_message(home.coffee, "the first message\n\nAnn")
    add_message(home.coffee, "the second")
    add_message(home.lobby, "in the lobby")
    write_inbox()
    write_file(HOME .. "/devices", 'phone.token = "' .. PHONE .. '"\nphone.own = true\n', "600")
end
-- }}}

-- {{{ the server
local running
local function connect(address, seconds)
    local sock = socket.tcp4()
    sock:settimeout(seconds or 2)
    local ok = sock:connect(address or ADDRESS, PORT)
    if not ok then sock:close(); return nil end
    return sock
end
local function start(broken)
    os.execute((broken and ("RAO_DEVICES_BROKEN=" .. q(broken) .. " ") or "") .. "luajit " .. q(SERVER) .. " "
        .. q(DIR) .. " " .. q(HOME) .. " > " .. q(ROOT .. "/server-output") .. " 2>&1 &")
    local give_up = socket.gettime() + 10
    while socket.gettime() < give_up do
        local sock = connect(nil, 0.2)
        if sock then sock:close(); running = true; return end
        socket.sleep(0.1)
    end
    error("the device server did not start: " .. tostring(read_file(ROOT .. "/server-output")))
end
local function stop()
    if not running then return end
    write_file(HOME_RAM .. "/devices/stop", "")
    local give_up = socket.gettime() + 5
    while socket.gettime() < give_up do
        local sock = connect(nil, 0.2)
        if not sock then break end
        sock:close()
        socket.sleep(0.1)
    end
    running = false
end
-- }}}

-- {{{ the device
local devices = 0
local function new_device(address)
    devices = devices + 1
    local folder = ROOT .. "/device-" .. devices
    os.execute("mkdir -p " .. q(folder))
    write_file(folder .. "/config", "port = " .. PORT .. "\nhome-network = " .. (address or ADDRESS)
        .. "\npublic = unknown\ntoken = " .. PHONE .. "\nwait = 2\nquick-wait = 0.5\n", "600")
    return folder
end
-- folder → exit status, what it printed, {files, messages, changed, dropped}
local function catch_up(folder, broken)
    local status, said = run((broken and ("RAO_DEVICE_BROKEN=" .. q(broken) .. " ") or "") .. "luajit "
        .. q(DEVICE) .. " " .. q(folder) .. " catch-up")
    local files, messages, changed, dropped =
        said:match("(%d+) file%(s%) received %((%d+) message%(s%)%), (%d+) changed, (%d+) dropped")
    return status, said, { files = tonumber(files), messages = tonumber(messages), changed = tonumber(changed),
        dropped = tonumber(dropped) }
end
-- every file of 301's layout under a folder → { path = text }
local function layout_of(root)
    local files = {}
    for _, path in ipairs(select(2, mirror.listing(root))) do files[path] = read_file(root .. "/" .. path) end
    return files
end
local function same_as_home(folder)
    local want, have = layout_of(HOME_RAM), layout_of(folder .. "/mirror")
    for path, text in pairs(want) do
        must(have[path] ~= nil, "the mirror lacks " .. path)
        must(have[path] == text, "the mirror's " .. path .. " differs from the home's")
    end
    for path in pairs(have) do must(want[path] ~= nil, "the mirror holds " .. path .. ", which the home does not") end
end
-- }}}

local function with_broken(name, referee, broken, server_broken)
    check(name, function() referee() end)
    if broken then
        check(name .. " (catches " .. broken .. ")", function()
            if server_broken then stop(); start(broken) end
            local ok, problem = pcall(referee, broken)
            if server_broken then stop(); start() end
            must(not ok, "the referee passed the broken version " .. broken)
            print("     caught (" .. broken .. "): " .. (tostring(problem):gsub("^[^:]*:%d+: ", ""):gsub("\n+$", "")))
        end)
    end
end

os.execute("mkdir -p " .. q(ROOT))
make_home()
start()

local server_module = require("187-device-server")
local seal, frames = require("124-seal"), require("125-frames")
local records = require("186-device-records")
local pair = require("123-room-key").key_pair(PHONE)

-- {{{ by hand: the request, messages, and what comes back
local function request(path, key, extra)
    return "GET " .. path .. " HTTP/1.1\r\nHost: home\r\nUpgrade: websocket\r\nConnection: keep-alive, Upgrade\r\n"
        .. "Sec-WebSocket-Key: " .. (key or "dGhlIHNhbXBsZSBub25jZQ==") .. "\r\nSec-WebSocket-Version: 13\r\n"
        .. (extra or "") .. "\r\n"
end
-- payload, {masked, opcode, fin} → one WebSocket message's bytes
local function message(payload, how)
    how = how or {}
    local opcode = how.opcode or 0x2
    local first = string.char((how.fin == false and 0 or 0x80) + opcode)
    local masked = how.masked ~= false
    local n = #payload
    local length = n < 126 and string.char((masked and 0x80 or 0) + n)
        or string.char((masked and 0x80 or 0) + 126, math.floor(n / 256), n % 256)
    if not masked then return first .. length .. payload end
    local mask = "\1\2\3\4"
    local bytes = {}
    for i = 1, n do bytes[i] = string.char(bit.bxor(payload:byte(i), mask:byte((i - 1) % 4 + 1))) end
    return first .. length .. mask .. table.concat(bytes)
end
local function upgraded()
    local sock = assert(connect())
    assert(sock:send(request("/the-socket")))
    local head = server_module.read_head(sock, "")
    must(head and head:find("^HTTP/1%.1 101 "), "the upgrade was not answered: " .. tostring(head))
    return sock
end
-- the server's answer, as a browser reads it: one unmasked binary message
local function read_message(sock)
    local ws = server_module.websocket(sock, "client")
    ws:settimeout(2)
    local frame, why = frames.read_frame(ws)
    if not frame then return nil, why end
    return records.decode(assert(seal.open(pair, frame), "the answer does not open under the phone's token"))
end
local function nothing_comes(sock, seconds)
    sock:settimeout(seconds or 4)
    local data, why, partial = sock:receive(1)
    must(data == nil and (partial or "") == "", "the server sent bytes: " .. string.format("%q", tostring(data or partial)))
    must(why == "closed", "the connection was not closed (" .. tostring(why) .. ")")
end
-- }}}

-- 1. The upgrade is answered.
check("1. the upgrade is answered with RFC 6455's own example accept value, and nothing naming the server", function()
    local sock = assert(connect())
    assert(sock:send(request("/the-socket")))
    sock:settimeout(2)
    local head = server_module.read_head(sock, "")
    sock:close()
    must(head == "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        .. "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", "the answer was: " .. tostring(head))
end)

-- 2. A wrong path, or a plain GET, gets nothing.
with_broken("2. another path, a plain GET, a wrong version or key, no Upgrade, and an endless head get not a byte", function()
    for _, text in ipairs({ request("/"), request("/the-socket/"), "GET /the-socket HTTP/1.1\r\nHost: home\r\n\r\n",
                            request("/the-socket"):gsub("Version: 13", "Version: 8"),
                            request("/the-socket", "short"),
                            (request("/the-socket"):gsub("Upgrade: websocket\r\n", "")),
                            (request("/the-socket"):gsub("keep%-alive, Upgrade", "keep-alive")),
                            "GET /the-socket HTTP/1.1\r\n" .. string.rep("X-Padding: aaaaaaaa\r\n", 300) }) do
        local sock = assert(connect())
        assert(sock:send(text))
        nothing_comes(sock)
        sock:close()
    end
end, "answer-404", true)

-- 3. A ping in a WebSocket message gets a pong in one.
check("3. a ping in a binary message gets a pong in one, under the phone's token", function()
    local sock = upgraded()
    assert(sock:send(message(seal.seal(pair, records.encode({ kind = "ping", id = "through-the-socket" })))))
    local reply, why = read_message(sock)
    must(reply, "no answer: " .. tostring(why))
    must(reply.kind == "pong" and reply.id == "through-the-socket", "not the ping's pong")
    -- frames of every length encoding the other way (under 126, under
    -- 65536, and more): a catch-up that holds a message of 70000 bytes
    add_message(home.quiet, string.rep("long ", 14000))
    write_inbox()
    assert(sock:send(message(seal.seal(pair, records.encode({ kind = "catch-up", rooms = "" })))))
    local files, longest = 0, 0
    while true do
        local record = assert(read_message(sock))
        if record.kind == "caught-up" then break end
        files = files + 1
        if #record.content > longest then longest = #record.content end
    end
    must(files > 5 and longest > 70000, "the catch-up through the socket brought " .. files
        .. " files, the longest " .. longest .. " bytes")
    sock:close()
end)

-- 4. An unmasked message closes the connection.
check("4. an unmasked message, a text message, a fragment, two frames in one message: closed", function()
    local ping = seal.seal(pair, records.encode({ kind = "ping", id = "p" }))
    for _, bad in ipairs({ message(ping, { masked = false }), message(ping, { opcode = 0x1 }),
                           message(ping, { fin = false }), message(ping .. ping), message(ping:sub(1, -2)) }) do
        local sock = upgraded()
        assert(sock:send(bad))
        nothing_comes(sock)
        sock:close()
    end
end)

check("5. the reference device as a browser: catch-up and live pushing through the upgrade", function()
    local folder = new_device()
    local handle = assert(io.open(folder .. "/config", "ab"))
    handle:write("websocket-path = /the-socket\nkeep-alive = 1\n")
    handle:close()
    local status, said = catch_up(folder)
    must(status == 0, "catch-up through the socket failed: " .. said)
    same_as_home(folder)
    os.execute("luajit " .. q(DEVICE) .. " " .. q(folder) .. " live --for 4 > " .. q(folder .. "/live-output") .. " 2>&1 &")
    local give_up = socket.gettime() + 5
    while not (read_file(folder .. "/live-output") or ""):find("caught up", 1, true) and socket.gettime() < give_up do
        socket.sleep(0.05)
    end
    add_message(home.coffee, "pushed through the socket")
    write_inbox()
    give_up = socket.gettime() + 6
    while not (read_file(folder .. "/live-output") or ""):find("live for", 1, true) and socket.gettime() < give_up do
        socket.sleep(0.1)
    end
    said = read_file(folder .. "/live-output") or ""
    must(said:find("live for 4 s", 1, true), "the live browser did not end well: " .. said)
    same_as_home(folder)
end)

check("6. a home without devices.websocket-path: the server stops naming the line to add", function()
    local dir = ROOT .. "/no-path"
    local h = rooms.open_home(dir)
    for key, value in pairs({ ["devices.port"] = "46398", ["devices.address"] = ADDRESS, ["devices.idle-limit"] = "5",
                              ["devices.frame-deadline"] = "2", ["gatherer.ram-root"] = ROOT .. "/ram" }) do
        rooms.set_config(h, key, value)
    end
    write_file(dir .. "/devices", "", "600")
    local status, said = run("timeout 5 luajit " .. q(SERVER) .. " " .. q(DIR) .. " " .. q(dir))
    must(status ~= 0 and said:find("devices.websocket-path = <value>", 1, true), "the server said: " .. said)
end)

stop()
os.execute("rm -rf " .. q(ROOT))
print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
