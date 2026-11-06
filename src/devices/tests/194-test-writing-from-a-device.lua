-- 194-test-writing-from-a-device.lua — the referees of issue 305, writing
-- from a device: what the person writes into the mirror with 183 reaches
-- the room's gatherer's typed/ in 301's shape and leaves the mirror; a
-- typed file the home refuses stays, with its reason; the same typed file
-- sent twice is put once.  Each referee with a broken version also runs
-- against it.
--
-- The home's folder is written as its gatherers write it (181 from a RAM
-- home of each mailbox's rooms, as 184 does), with no gatherer running:
-- the device server reads only that folder.  Run it under the
-- loopback-only wrapper (a network namespace with only `lo`): the device
-- port listens on 127.0.0.2.  Its folders
-- are under RAO_TEST_ROOT when that is set, otherwise a folder of its own
-- under /dev/shm (or /tmp); removed at the end.
--
-- Run: luajit src/devices/tests/194-test-writing-from-a-device.lua [PROJECT_DIR]
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
local ROOT = base .. "/rao-chat-writing-test-" .. ffi.C.getpid()
local SERVER = DIR .. "/src/devices/187-device-server.lua"
local DEVICE = DIR .. "/src/devices/190-device.lua"
local ADDRESS, PORT = "127.0.0.2", 46305
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
                              ["devices.frame-deadline"] = "2", ["gatherer.ram-root"] = ROOT .. "/ram" }) do
        rooms.set_config(h, key, value)
    end
    home.disk = h
    home.lobby = rooms.make_room(h, { label = "lobby", token = "writing from a device lobby", kind = "group", parent = "",
        members = {}, filed_under = "", mailbox_port = 48111 })
    home.coffee = rooms.make_room(h, { label = "coffee", token = "writing from a device coffee", kind = "group", parent = "",
        members = {}, filed_under = home.lobby, mailbox_port = 48112 })
    home.quiet = rooms.make_room(h, { label = "quiet", token = "writing from a device quiet", kind = "group", parent = "",
        members = {}, filed_under = home.lobby, mailbox_port = 48113 })
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

os.execute("mkdir -p " .. q(ROOT))
make_home()
start()

-- 1. Typed on the phone, sent by the home.
with_broken("1. written by 183 into the mirror, then send: in the gatherer's typed/ in 301's shape, gone from the mirror", function()
    local folder = new_device()
    local status, said = catch_up(folder)
    must(status == 0, "catch-up failed: " .. said)
    local path, why = viewer.write(folder .. "/mirror", home.coffee, "typed on the phone", "Phone", os.time())
    must(path, "183 could not write into the mirror: " .. tostring(why))
    local bytes = read_file(path)
    status, said = send(folder)
    must(status == 0 and said:find("sent 1 typed file", 1, true), "send: " .. said)
    must(read_file(path) == nil, "the typed file is still in the mirror")
    local waiting = ram.waiting(queue_of(home.coffee))
    must(#waiting == 1, #waiting .. " file(s) in the coffee room's gatherer's typed/")
    local put = read_file(queue_of(home.coffee) .. "/" .. waiting[1])
    must(put == bytes, "the gatherer's typed file is not what the person wrote")
    local typed = ram.decode_typed(put)
    must(typed and typed.room == home.coffee and typed.text == "typed on the phone\n\nPhone",
        "the typed file does not read in 301's shape")
    must(#ram.waiting(queue_of(home.lobby)) == 0, "a typed file went to another gatherer")
end)

check("1b. a typed-ok for another file removes nothing (a stand-in home answers so)", function()
    local ready = ROOT .. "/stand-in-ready"
    write_file(ROOT .. "/stand-in.lua", table.concat({
        "dofile(" .. string.format("%q", DIR) .. " .. '/src/room-folders/001-load-path.lua')(" .. string.format("%q", DIR) .. ")",
        "local socket, seal, frames = require('socket'), require('124-seal'), require('125-frames')",
        "local pair, records = require('123-room-key').key_pair(" .. string.format("%q", PHONE) .. "), require('186-device-records')",
        "local listener = socket.tcp4(); listener:setoption('reuseaddr', true)",
        "assert(listener:bind('127.0.0.4', " .. PORT .. ")); assert(listener:listen(1)); listener:settimeout(10)",
        "io.open(" .. string.format("%q", ready) .. ", 'w'):close()",
        "local conn = listener:accept(); if not conn then os.exit(1) end",
        "conn:settimeout(3)",
        "local ping = records.decode(seal.open(pair, frames.read_frame(conn)))",
        "frames.write_frame(conn, seal.seal(pair, records.encode({ kind = 'pong', id = ping.id, at = 1 })))",
        "frames.read_frame(conn)",
        "frames.write_frame(conn, seal.seal(pair, records.encode({ kind = 'typed-ok', id = '1000000000-000001-00000000' })))",
        "listener:close(); socket.sleep(0.5); conn:close()",
    }, "\n") .. "\n")
    os.execute("luajit " .. q(ROOT .. "/stand-in.lua") .. " > /dev/null 2>&1 &")
    local give_up = socket.gettime() + 5
    while not read_file(ready) and socket.gettime() < give_up do socket.sleep(0.05) end
    must(read_file(ready), "the stand-in home did not start")
    local folder = new_device("127.0.0.4")
    local queue = folder .. "/mirror/" .. home.mailbox_of[home.coffee] .. "/typed"
    os.execute("mkdir -p " .. q(queue))
    local name = ram.new_name(os.time())
    ram.put(queue, name, "room: " .. home.coffee .. "\nwritten: " .. os.time() .. "\n\nkept\n")
    local status, said = send(folder)
    must(read_file(queue .. "/" .. name), "the typed file was removed on another file's typed-ok")
    must(status ~= 0, "send took another file's answer quietly: " .. said)
end)

-- 2. Refused stays.
with_broken("2. a typed file for a room the home does not have: kept, with its reason beside it", function(broken)
    local folder = new_device()
    local status, said = catch_up(folder)
    must(status == 0, "catch-up failed: " .. said)
    local queue = folder .. "/mirror/" .. home.mailbox_of[home.coffee] .. "/typed"
    local name = ram.new_name(os.time())
    local unknown = string.rep("d", 32)
    ram.put(queue, name, "room: " .. unknown .. "\nwritten: " .. os.time() .. "\n\nfor nowhere\n")
    status, said = send(folder, broken)
    must(read_file(queue .. "/" .. name), "the refused file is gone from the mirror: " .. said)
    local why = read_file(queue .. "/" .. name .. ".refused") or ""
    must(why:find("this home has no room " .. unknown, 1, true), "no reason beside it: '" .. why .. "'")
    must(status ~= 0 and said:find("kept " .. name, 1, true), "send did not say it kept the file: " .. said)
    -- a later send leaves it alone until the person removes the reason
    local again, again_said = send(folder, broken)
    must(again == 0 and again_said:find("sent 0 typed file", 1, true), "the refused file was sent again: " .. again_said)
    must(#ram.waiting(queue_of(home.coffee)) == 0, "the refused file reached a gatherer")
end, "drop-refused")

check("2b. the home refuses what the filer would: a file not in 301's shape, a name not a typed file's", function()
    local sock = assert(connect())
    sock:settimeout(1)
    local name = ram.new_name(os.time())
    local reply = assert(exchange(sock, { kind = "typed", id = name, content = "room: " .. home.coffee .. "\nwhen: now\n\nhi\n" }))
    must(reply.kind == "typed-refused" and reply.id == name and reply.why:find("only room: and written:", 1, true),
        "a misspelt header was not refused as the filer would: " .. tostring(reply.why))
    reply = assert(exchange(sock, { kind = "typed", id = "not-a-name", content = "room: " .. home.coffee .. "\n\nhi\n" }))
    must(reply.kind == "typed-refused" and reply.why:find("not a typed file's name", 1, true), "an odd id was taken")
    sock:close()
    must(#ram.waiting(queue_of(home.coffee)) == 0, "a refused file reached a gatherer")
end)

-- 3. Twice is once.
with_broken("3. the same typed sent twice, after the gatherer took the first: one file", function()
    local queue = queue_of(home.lobby)
    local name = ram.new_name(os.time())
    local content = "room: " .. home.lobby .. "\nwritten: " .. os.time() .. "\n\nonly once\n"
    local sock = assert(connect())
    sock:settimeout(1)
    local reply = assert(exchange(sock, { kind = "typed", id = name, content = content }))
    must(reply.kind == "typed-ok" and reply.id == name, "the first was not taken: " .. tostring(reply.why))
    -- the gatherer takes it, as its filer does
    must(ram.take(queue, name), "the typed file is not in the gatherer's typed/")
    os.remove(queue .. "/working/" .. name)
    -- the typed-ok was lost: the device sends it again
    reply = assert(exchange(sock, { kind = "typed", id = name, content = content }))
    sock:close()
    must(reply.kind == "typed-ok", "the second was not answered typed-ok")
    must(#ram.waiting(queue) == 0, "the same typed file was put a second time")
end, "no-dedupe", true)

check("3b. after the server restarts, a typed file sent again is put under the same name and bytes, so 161 files it once", function()
    empty_queues()
    local queue = queue_of(home.lobby)
    local name = ram.new_name(os.time())
    local content = "room: " .. home.lobby .. "\nwritten: " .. os.time() .. "\n\nacross a restart\n"
    local sock = assert(connect())
    sock:settimeout(1)
    must(assert(exchange(sock, { kind = "typed", id = name, content = content })).kind == "typed-ok", "not taken")
    sock:close()
    local first = assert(ram.take(queue, name))
    os.remove(queue .. "/working/" .. name)
    stop()
    start()
    sock = assert(connect())
    sock:settimeout(1)
    must(assert(exchange(sock, { kind = "typed", id = name, content = content })).kind == "typed-ok", "not taken again")
    sock:close()
    local waiting = ram.waiting(queue)
    must(#waiting == 1 and waiting[1] == name, "put again under another name: " .. table.concat(waiting, ", "))
    local again = read_file(queue .. "/" .. name)
    must(ram.typed_id(name, again) == ram.typed_id(name, first), "161 would file it under another id")
    os.remove(queue .. "/" .. name)
end)

stop()
os.execute("rm -rf " .. q(ROOT))
print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
