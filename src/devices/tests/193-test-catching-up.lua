-- 193-test-catching-up.lua — the referees of issue 304, catching up: a
-- new device's mirror equals the home's folder; a device away is sent
-- only what is new; an edit is caught by the digest; a path from the
-- network outside 301's layout is refused; the reference viewer (183)
-- reads the mirror as it reads the home.  Each referee with a broken
-- version also runs against it.
--
-- The home's folder is written as its gatherers write it (181 from a RAM
-- home of each mailbox's rooms, as 184 does), with no gatherer running:
-- the device server reads only that folder.  Run it under the
-- loopback-only wrapper (a network namespace with only `lo`): the device
-- port listens on 127.0.0.2, a stand-in home on 127.0.0.4.  Its folders
-- are under RAO_TEST_ROOT when that is set, otherwise a folder of its own
-- under /dev/shm (or /tmp); removed at the end.
--
-- Run: luajit src/devices/tests/193-test-catching-up.lua [PROJECT_DIR]
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
local ROOT = base .. "/rao-chat-catching-up-test-" .. ffi.C.getpid()
local SERVER = DIR .. "/src/devices/187-device-server.lua"
local DEVICE = DIR .. "/src/devices/190-device.lua"
local ADDRESS, PORT = "127.0.0.2", 46304
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
    home.lobby = rooms.make_room(h, { label = "lobby", token = "catching up lobby", kind = "group", parent = "",
        members = {}, filed_under = "", mailbox_port = 48101 })
    home.coffee = rooms.make_room(h, { label = "coffee", token = "catching up coffee", kind = "group", parent = "",
        members = {}, filed_under = home.lobby, mailbox_port = 48102 })
    home.quiet = rooms.make_room(h, { label = "quiet", token = "catching up quiet", kind = "group", parent = "",
        members = {}, filed_under = home.lobby, mailbox_port = 48103 })
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
        .. "\npublic = unknown\ntoken = " .. PHONE .. "\nwait = 2\n", "600")
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

check("0. the catch-up records and 192's path rule", function()
    local records = require("186-device-records")
    local line = records.encode({ kind = "file", path = "a/b", content = "x\ny\tz" })
    must(not line:find("\n", 1, true), "a file record is not one line")
    local back = records.decode(line)
    must(back and back.content == "x\ny\tz", "a file's content does not read back")
    must(records.decode("index\tnot-hex\t") == nil, "an index for a room that is not 32 hex was read")
    local tag = string.rep("a", 32)
    for _, good in ipairs({ tag .. "/state", tag .. "/inbox/.tree", tag .. "/inbox/" .. tag .. "/.room",
                            tag .. "/inbox/" .. tag .. "/1000000000-" .. string.rep("b", 32) }) do
        must(mirror.check_path(good), "refused " .. good)
    end
    for _, bad in ipairs({ "../../escape", "/" .. tag .. "/state", tag .. "/home/config", tag .. "/inbox/../state",
                           tag .. "/inbox/" .. tag .. "/.hidden", tag .. "/inbox/" .. tag .. "/1000-a b",
                           tag .. "/inbox/not-hex/1000-x", tag .. "/inbox/" .. tag .. "/x/1000-y",
                           "devices/state", tag .. "/inbox/" .. tag .. "/.1000-x.tmp" }) do
        must(mirror.check_path(bad) == nil, "took " .. bad)
    end
end)

-- 1. A new device gets everything.
check("1. an empty mirror after catch-up holds the home's folder, file for file, and nothing else", function()
    local folder = new_device()
    local status, said, counts = catch_up(folder)
    must(status == 0, "catch-up failed: " .. said)
    same_as_home(folder)
    must(counts.messages == 3, "3 message files were due, " .. tostring(counts.messages) .. " came: " .. said)
    must(not disk.is_dir(folder .. "/mirror/" .. next(home.mailboxes) .. "/home"),
        "the gatherer's own home/ was mirrored")
    status, said, counts = catch_up(folder)
    must(status == 0 and counts.messages == 0 and counts.changed == 0, "a second catch-up changed things: " .. said)
end)

-- 2. A device away gets only what is new.
with_broken("2. after two new messages, a second catch-up sends exactly those two message files", function()
    local folder = new_device()
    local status, said = catch_up(folder)
    must(status == 0, "the first catch-up failed: " .. said)
    add_message(home.coffee, "new one")
    add_message(home.lobby, "new two")
    write_inbox()
    local counts
    status, said, counts = catch_up(folder)
    must(status == 0, "the second catch-up failed: " .. said)
    must(counts.messages == 2, "the second catch-up sent " .. tostring(counts.messages) .. " message files: " .. said)
    same_as_home(folder)
end, "from-start", true)

-- 3. An edit is caught.
with_broken("3. a message corrected on the home: the device's copy is replaced", function()
    local folder = new_device()
    local status, said = catch_up(folder)
    must(status == 0, "the first catch-up failed: " .. said)
    -- a correction of the first message (later in the room than the
    -- device's position is not needed: the first file itself changes)
    message_log.correct(ram_home_of(home.coffee), home.coffee, { id = message_log.new_message_id(),
        from = "10.0.0.9 5000", written = written + 5, arrived = written + 6, target = home.first,
        text = "the first message, corrected " .. devices .. "\n\nAnn" })
    write_inbox()
    status, said = catch_up(folder)
    must(status == 0, "the second catch-up failed: " .. said)
    local mailbox = home.mailbox_of[home.coffee]
    local names = mirror.rooms(folder .. "/mirror")[home.coffee].names
    local first = folder .. "/mirror/" .. mailbox .. "/inbox/" .. home.coffee .. "/" .. names[1]
    must((read_file(first) or ""):find("corrected " .. devices, 1, true), "the device still holds the uncorrected message")
    same_as_home(folder)
end, "no-digest", true)

check("3b. a file the home no longer holds is dropped, and a late message is fetched", function()
    local folder = new_device()
    local status, said = catch_up(folder)
    must(status == 0, "the first catch-up failed: " .. said)
    local mailbox = home.mailbox_of[home.lobby]
    local room_folder = HOME_RAM .. "/" .. mailbox .. "/inbox/" .. home.lobby
    local names = mirror.rooms(HOME_RAM)[home.lobby].names
    -- hidden since (301 decision 4): its file is gone on the home
    os.rename(room_folder .. "/" .. names[1], ROOT .. "/hidden-message")
    -- a late message, written before everything the device holds
    message_log.append(ram_home_of(home.coffee), home.coffee, { id = message_log.new_message_id(),
        from = "10.0.0.8 5000", written = 1000000001, arrived = written + 50, text = "late" })
    write_inbox()
    os.remove(room_folder .. "/" .. names[1])
    local counts
    status, said, counts = catch_up(folder)
    must(status == 0, "the second catch-up failed: " .. said)
    must(counts.dropped == 1, "dropped " .. tostring(counts.dropped) .. ": " .. said)
    same_as_home(folder)
    os.rename(ROOT .. "/hidden-message", room_folder .. "/" .. names[1])
end)

check("3c. a room the home has left (its mailbox's .tree no longer names it) leaves the mirror", function()
    local folder = new_device()
    local status, said = catch_up(folder)
    must(status == 0, "the first catch-up failed: " .. said)
    local mailbox = home.mailbox_of[home.quiet]
    must(disk.is_dir(folder .. "/mirror/" .. mailbox .. "/inbox/" .. home.quiet), "the quiet room was not mirrored")
    local tree = HOME_RAM .. "/" .. mailbox .. "/inbox/.tree"
    local kept = read_file(tree)
    write_file(tree, (kept:gsub(home.quiet .. "[^\n]*\n", "")))
    os.rename(HOME_RAM .. "/" .. mailbox .. "/inbox/" .. home.quiet, ROOT .. "/quiet-room")
    local counts
    status, said, counts = catch_up(folder)
    os.rename(ROOT .. "/quiet-room", HOME_RAM .. "/" .. mailbox .. "/inbox/" .. home.quiet)
    write_file(tree, kept)
    must(status == 0, "the second catch-up failed: " .. said)
    must(not disk.is_dir(folder .. "/mirror/" .. mailbox .. "/inbox/" .. home.quiet), "the room the home left is still mirrored")
    must(counts.dropped == 1, "dropped " .. tostring(counts.dropped) .. ": " .. said)
end)

-- 4. A bad path is refused.
with_broken("4. a home answering with ../../escape or a non-hex room: nothing written outside, and said", function(broken)
    -- a stand-in home on 127.0.0.4 that answers a catch-up with bad paths
    local tag = string.rep("c", 32)
    local ready = ROOT .. "/stand-in-ready"
    os.remove(ready)
    os.remove(ROOT .. "/escape")
    write_file(ROOT .. "/stand-in.lua", table.concat({
        "dofile(" .. string.format("%q", DIR) .. " .. '/src/room-folders/001-load-path.lua')(" .. string.format("%q", DIR) .. ")",
        "local socket, seal, frames = require('socket'), require('124-seal'), require('125-frames')",
        "local pair, records = require('123-room-key').key_pair(" .. string.format("%q", PHONE) .. "), require('186-device-records')",
        "local listener = socket.tcp4(); listener:setoption('reuseaddr', true)",
        "for _ = 1, 50 do if listener:bind('127.0.0.4', " .. PORT .. ") then break end socket.sleep(0.1) end",
        "assert(listener:listen(1)); listener:settimeout(10)",
        "io.open(" .. string.format("%q", ready) .. ", 'w'):close()",
        "local conn = listener:accept(); if not conn then os.exit(1) end",
        "conn:settimeout(3); frames.read_frame(conn)",
        "local function say(r) frames.write_frame(conn, seal.seal(pair, records.encode(r))) end",
        "say({ kind = 'file', path = '../../escape', content = 'out' })",
        "say({ kind = 'file', path = '" .. tag .. "/inbox/nothex/1000000000-x', content = 'out' })",
        "say({ kind = 'file', path = '" .. tag .. "/inbox/.tree', content = '' })",
        "say({ kind = 'caught-up', at = 1 })",
        "listener:close(); socket.sleep(0.5); conn:close()",
    }, "\n") .. "\n")
    os.execute("luajit " .. q(ROOT .. "/stand-in.lua") .. " > /dev/null 2>&1 &")
    local give_up = socket.gettime() + 5
    while not read_file(ready) and socket.gettime() < give_up do socket.sleep(0.05) end
    must(read_file(ready), "the stand-in home did not start")
    local folder = new_device("127.0.0.4")
    local status, said = catch_up(folder, broken)
    must(read_file(ROOT .. "/escape") == nil, "a file was written outside the mirror")
    must(not disk.is_dir(folder .. "/mirror/" .. tag .. "/inbox/nothex"), "a room that is not 32 hex was written")
    must(status ~= 0, "the device took the bad paths quietly: " .. said)
    must(said:find("refused from the home: '../../escape'", 1, true) and said:find("names no 32-hex room", 1, true),
        "the device did not say what it refused: " .. said)
    must(read_file(folder .. "/mirror/" .. tag .. "/inbox/.tree") == "", "the good path beside them was not written")
end, "no-path-check")

-- 5. The mirror reads as a folder.
check("5. 183's room and tree on the mirror show what they show on the home", function()
    local folder = new_device()
    local status, said = catch_up(folder)
    must(status == 0, "catch-up failed: " .. said)
    for _, tag in ipairs({ home.coffee, home.lobby, home.quiet }) do
        local on_home = assert(viewer.room_text(HOME_RAM, tag))
        local on_mirror = assert(viewer.room_text(folder .. "/mirror", tag))
        must(on_home == on_mirror, "the room reads differently:\n" .. on_home .. "on the mirror:\n" .. on_mirror)
    end
    must(viewer.tree_text(HOME_RAM) == viewer.tree_text(folder .. "/mirror"), "the tree reads differently")
end)

check("6. the home closes on a catch-up or a want it cannot read", function()
    local seal, frames = require("124-seal"), require("125-frames")
    local records = require("186-device-records")
    local pair = require("123-room-key").key_pair(PHONE)
    for _, record in ipairs({ { kind = "catch-up", rooms = "not a position" },
                              { kind = "want", id = "w1", room = home.coffee, names = "../escape" } }) do
        local sock = assert(connect())
        assert(sock:send(seal.seal(pair, records.encode(record))))
        sock:settimeout(4)
        local data, why = sock:receive(1)
        must(data == nil and why == "closed", "the home answered " .. record.kind .. " it should refuse")
        sock:close()
    end
end)

stop()
os.execute("rm -rf " .. q(ROOT))
print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
