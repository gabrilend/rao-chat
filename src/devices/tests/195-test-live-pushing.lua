-- 195-test-live-pushing.lua — the referees of issue 306, live pushing
-- and several devices at once: a message filed while a device is
-- connected reaches its mirror within two seconds, without a new
-- catch-up; a message typed on one device appears in another's mirror;
-- a quiet connection is closed after devices.idle-limit, a pinging one is
-- kept.  Each referee with a broken version also runs against it.
--
-- The home's folder is written as its gatherers write it (181 from a RAM
-- home of each mailbox's rooms), and the test files a typed file as the
-- gatherer's filer would; no gatherer runs.  Run it under the
-- loopback-only wrapper (a network namespace with only `lo`): the device
-- port listens on 127.0.0.2.  Its folders are under RAO_TEST_ROOT when
-- that is set, otherwise a folder of its own under /dev/shm (or /tmp);
-- removed at the end.
--
-- Run: luajit src/devices/tests/195-test-live-pushing.lua [PROJECT_DIR]
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
local ROOT = base .. "/rao-chat-live-test-" .. ffi.C.getpid()
local SERVER = DIR .. "/src/devices/187-device-server.lua"
local DEVICE = DIR .. "/src/devices/190-device.lua"
local ADDRESS, PORT = "127.0.0.2", 46306
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
                              ["devices.frame-deadline"] = "2", ["devices.idle-limit"] = "3", ["gatherer.ram-root"] = ROOT .. "/ram" }) do
        rooms.set_config(h, key, value)
    end
    home.disk = h
    home.lobby = rooms.make_room(h, { label = "lobby", token = "live pushing lobby", kind = "group", parent = "",
        members = {}, filed_under = "", mailbox_port = 48121 })
    home.coffee = rooms.make_room(h, { label = "coffee", token = "live pushing coffee", kind = "group", parent = "",
        members = {}, filed_under = home.lobby, mailbox_port = 48122 })
    home.quiet = rooms.make_room(h, { label = "quiet", token = "live pushing quiet", kind = "group", parent = "",
        members = {}, filed_under = home.lobby, mailbox_port = 48123 })
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

-- folder → exit status, what it printed
local function send(folder, broken)
    return run((broken and ("RAO_DEVICE_BROKEN=" .. q(broken) .. " ") or "") .. "luajit " .. q(DEVICE) .. " "
        .. q(folder) .. " send")
end
local function queue_of(tag) return HOME_RAM .. "/" .. home.mailbox_of[tag] .. "/typed" end
local function empty_queues()
    for mailbox in pairs(home.mailboxes) do
        for _, name in ipairs(ram.waiting(HOME_RAM .. "/" .. mailbox .. "/typed")) do
            os.remove(HOME_RAM .. "/" .. mailbox .. "/typed/" .. name)
        end
    end
end

-- {{{ a device by hand: one connection, records sealed under the phone's token
local seal, frames = require("124-seal"), require("125-frames")
local records = require("186-device-records")
local pair = require("123-room-key").key_pair(PHONE)
local function exchange(sock, record)
    assert(frames.write_frame(sock, seal.seal(pair, records.encode(record))))
    local frame, why = frames.read_frame(sock)
    if not frame then return nil, "no answer: " .. tostring(why) end
    return records.decode(assert(seal.open(pair, frame)))
end
-- }}}

local function with_broken(name, referee, broken, server_broken)
    check(name, function() empty_queues(); referee() end)
    if broken then
        check(name .. " (catches " .. broken .. ")", function()
            empty_queues()
            if server_broken then stop(); start(broken) end
            local ok, problem = pcall(referee, broken)
            if server_broken then stop(); start() end
            must(not ok, "the referee passed the broken version " .. broken)
            print("     caught (" .. broken .. "): " .. (tostring(problem):gsub("^[^:]*:%d+: ", ""):gsub("\n+$", "")))
        end)
    end
end

-- {{{ live devices and waiting
local function wait_until(condition, seconds)
    local give_up = socket.gettime() + seconds
    while socket.gettime() < give_up do
        if condition() then return true end
        socket.sleep(0.05)
    end
    return condition()
end
-- a device folder with keep-alive, `live --for seconds` started in the
-- background; returns once it has caught up
local function go_live(seconds)
    local folder = new_device()
    local handle = assert(io.open(folder .. "/config", "ab"))
    handle:write("keep-alive = 1\n")
    handle:close()
    os.execute("luajit " .. q(DEVICE) .. " " .. q(folder) .. " live --for " .. seconds .. " > "
        .. q(folder .. "/live-output") .. " 2>&1 &")
    must(wait_until(function() return (read_file(folder .. "/live-output") or ""):find("caught up", 1, true) end, 5),
        "the device did not catch up: " .. tostring(read_file(folder .. "/live-output")))
    return folder
end
local function ended(folder, seconds)
    return wait_until(function() return (read_file(folder .. "/live-output") or ""):find("\n[^\n]*\n$") and
        ((read_file(folder .. "/live-output") or ""):find("live for", 1, true)
        or (read_file(folder .. "/live-output") or ""):find("closed the connection", 1, true)) end, seconds)
end
local function holds(folder, path)
    return read_file(folder .. "/mirror/" .. path) ~= nil and read_file(folder .. "/mirror/" .. path) == read_file(HOME_RAM .. "/" .. path)
end
local function inbox_path(tag, name) return home.mailbox_of[tag] .. "/inbox/" .. tag .. "/" .. name end
local function newest(tag)
    local names = mirror.rooms(HOME_RAM)[tag].names
    return names[#names]
end
-- }}}

os.execute("mkdir -p " .. q(ROOT))
make_home()
start()

-- 1. Pushed at once.
check("1. a message filed while a device is live reaches its mirror within two seconds", function()
    local folder = go_live(6)
    local id = add_message(home.coffee, "pushed at once")
    write_inbox()
    local name = newest(home.coffee)
    must(name:find(id, 1, true), "the new message is not the room's newest")
    local filed = socket.gettime()
    must(wait_until(function() return holds(folder, inbox_path(home.coffee, name)) end, 2),
        "the message did not reach the live device within two seconds")
    print("     reached the mirror in " .. math.floor((socket.gettime() - filed) * 1000) .. " ms")
    must(ended(folder, 8), "the live device did not end")
    local said = read_file(folder .. "/live-output")
    must(said:find("live for 6 s", 1, true), "the live device did not end well: " .. said)
    must(not said:find("caught up", said:find("caught up", 1, true) + 1, true), "the device caught up a second time")
    -- only what changed is pushed: no .tree changed
    must(not said:find("received [^\n]*%.tree"), "files that did not change were pushed: " .. said)
end)

check("1b. a message corrected while a device is live: the changed file is pushed", function()
    local folder = go_live(5)
    local names = mirror.rooms(HOME_RAM)[home.coffee].names
    message_log.correct(ram_home_of(home.coffee), home.coffee, { id = message_log.new_message_id(),
        from = "10.0.0.9 5000", written = written + 5, arrived = written + 6, target = home.first,
        text = "the first message, corrected live\n\nAnn" })
    write_inbox()
    local path = inbox_path(home.coffee, names[1])
    must((read_file(HOME_RAM .. "/" .. path) or ""):find("corrected live", 1, true), "the correction is not on the home")
    must(wait_until(function() return holds(folder, path) end, 2), "the corrected file did not reach the live device")
end)

-- 2. Both devices hear it.
with_broken("2. two devices live: a message typed on one appears in the other's mirror", function()
    local phone, laptop = go_live(10), go_live(10)
    local path, why = viewer.write(phone .. "/mirror", home.lobby, "typed on the phone, live", "Phone", os.time())
    must(path, "183 could not write into the phone's mirror: " .. tostring(why))
    -- the gatherer's filer: takes the typed file and files it as its own
    local queue = queue_of(home.lobby)
    must(wait_until(function() return #ram.waiting(queue) == 1 end, 3), "the typed file did not reach the gatherer")
    local name = ram.waiting(queue)[1]
    local bytes = assert(ram.take(queue, name))
    os.remove(queue .. "/working/" .. name)
    local typed = assert(ram.decode_typed(bytes))
    message_log.append(ram_home_of(home.lobby), home.lobby, { id = ram.typed_id(name, bytes), from = "me",
        written = typed.written, arrived = typed.written, text = typed.text })
    write_inbox()
    local filed = inbox_path(home.lobby, tostring(typed.written) .. "-" .. ram.typed_id(name, bytes))
    must(read_file(HOME_RAM .. "/" .. filed), "the test's filer did not file it")
    must(wait_until(function() return holds(phone, filed) end, 3), "the phone, which wrote it, did not get it back")
    must(wait_until(function() return holds(laptop, filed) end, 3), "the laptop did not hear the phone's message")
    must(wait_until(function() return read_file(path) == nil end, 1), "the phone's typed file was not removed")
end, "only-writer", true)

-- 3. A quiet connection is closed; a pinging one is kept.
check("3. a connection quiet past the idle limit (3 s) is closed; one pinging every second is kept", function()
    local quiet, pinging = assert(connect()), assert(connect())
    quiet:settimeout(1)
    pinging:settimeout(1)
    must((exchange(quiet, { kind = "ping", id = "quiet" }) or {}).kind == "pong", "the quiet one's first ping")
    must((exchange(pinging, { kind = "ping", id = "p0" }) or {}).kind == "pong", "the pinging one's first ping")
    for step = 1, 12 do
        socket.sleep(0.5)
        if step % 2 == 0 then
            must((exchange(pinging, { kind = "ping", id = "p" .. step }) or {}).kind == "pong",
                "the pinging connection's ping at " .. (step / 2) .. " s was not answered")
        end
        -- quiet longer than the frame deadline (2 s), within the idle limit
        if step == 5 then
            must((exchange(quiet, { kind = "ping", id = "within" }) or {}).kind == "pong",
                "a connection quiet 2.5 s, within the idle limit, was closed")
        end
    end
    quiet:settimeout(0.5)
    local data, why = quiet:receive(1)
    must(data == nil and why == "closed", "the quiet connection is still open after 6 s (" .. tostring(why) .. ")")
    quiet:close()
    pinging:close()
end)

check("3b. a live device with keep-alive 1 stays connected past the idle limit", function()
    local folder = go_live(5)
    must(ended(folder, 7), "the live device did not end")
    local said = read_file(folder .. "/live-output")
    must(said:find("live for 5 s", 1, true) and not said:find("closed the connection", 1, true),
        "the home closed a device that pinged: " .. said)
end)

check("3c. a home without devices.idle-limit: the server stops naming the line to add", function()
    local dir = ROOT .. "/no-idle"
    local h = rooms.open_home(dir)
    for key, value in pairs({ ["devices.port"] = "46399", ["devices.address"] = ADDRESS,
                              ["devices.frame-deadline"] = "2", ["gatherer.ram-root"] = ROOT .. "/ram" }) do
        rooms.set_config(h, key, value)
    end
    write_file(dir .. "/devices", "", "600")
    local status, said = run("timeout 5 luajit " .. q(SERVER) .. " " .. q(DIR) .. " " .. q(dir))
    must(status ~= 0 and said:find("devices.idle-limit = <value>", 1, true), "the server said: " .. said)
    rooms.set_config(h, "devices.idle-limit", "0")
    status, said = run("timeout 5 luajit " .. q(SERVER) .. " " .. q(DIR) .. " " .. q(dir))
    must(status ~= 0 and said:find("devices.idle-limit must be a whole number", 1, true), "the server said: " .. said)
end)

stop()
os.execute("rm -rf " .. q(ROOT))
print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
