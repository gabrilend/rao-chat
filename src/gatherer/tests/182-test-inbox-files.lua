-- 182-test-inbox-files.lua — the referees of issue 301's first two steps
-- (the viewer's inbox files, `.room`, `.tree`, and the `typed/` reader),
-- against the inbox module on a home on disk and against real gatherers
-- on loopback, each referee also against the broken version it must
-- catch.
--
-- Run it under the loopback-only wrapper (a network namespace with only
-- `lo`): the gatherers listen on 127.0.0.2 and 127.0.0.3.  Its homes and RAM folders are
-- in a folder of its own under /dev/shm (or /tmp), removed at the end.
--
-- Run: luajit src/gatherer/tests/182-test-inbox-files.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>".

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/gatherer/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local ffi = require("ffi")
local socket = require("socket")
local rooms = require("002-room-folders")
local message_log = require("081-message-log")
local ignore = require("042-ignore-list")
local ram = require("161-ram-folders")
local inbox = require("181-inbox-files")
local recipients = require("041-recipients")
local delivered = require("130-delivered")
local delivery = require("134-delivery")

ffi.cdef [[ int getpid(void); ]]

local base = os.execute("test -d /dev/shm && test -w /dev/shm") == 0 and "/dev/shm" or "/tmp"
local ROOT = base .. "/rao-chat-inbox-files-test-" .. ffi.C.getpid()
local passed, failed = 0, 0
local q = function(text) return "'" .. tostring(text):gsub("'", "'\\''") .. "'" end
local now = socket.gettime

-- {{{ local function check / must / must_fail
local ONLY = os.getenv("ONLY")
local function check(claim, test)
    if ONLY and not claim:find(ONLY, 1, true) then return end
    local ok, problem = pcall(test)
    inbox.broken = ""
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
local function must_fail(referee, broken)
    inbox.broken = broken
    local ok, caught = pcall(referee)
    inbox.broken = ""
    if ok then error("the referee passed a broken version: " .. broken, 2) end
    print("     caught (" .. broken .. "): " .. tostring(caught):gsub("^[^:]*:%d+: ", ""))
end
-- }}}

-- {{{ local function read_file / names
local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
local function names(folder)
    local list = {}
    local p = io.popen("ls -1 " .. q(folder) .. " 2>/dev/null")
    for name in p:lines() do list[#list + 1] = name end
    p:close()
    table.sort(list)
    return list
end
-- }}}

-- {{{ local function wait_until
local function wait_until(condition, seconds)
    local stop = now() + seconds
    while now() < stop do
        if condition() then return true end
        socket.sleep(0.05)
    end
    return condition()
end
-- }}}

-- {{{ local function first_variants
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
-- }}}
local START = first_variants()

local count = 0
-- {{{ local function make_home
local function make_home(name, overrides)
    count = count + 1
    local dir = ROOT .. "/homes/" .. name .. "-" .. count
    os.execute("mkdir -p " .. q(ROOT .. "/homes"))
    local h = rooms.open_home(dir)
    for key, value in pairs(START) do rooms.set_config(h, key, value) end
    for key, value in pairs(overrides or {}) do rooms.set_config(h, key, value) end
    local tag = rooms.make_room(h, { label = "the room", token = "inbox files test room " .. count,
        kind = "group", parent = "", members = {}, filed_under = "", mailbox_port = 47000 + count })
    return { dir = dir, disk = h, tag = tag, folder = ROOT .. "/ram-" .. count,
             mailbox = rooms.read_entry(h, tag).mailbox }
end
-- }}}

-- {{{ local function file_of
-- home, message id → the text of its inbox file, or nil
local function file_of(home, id)
    for _, name in ipairs(names(inbox.folder(home.folder) .. "/" .. home.tag)) do
        if name:match("%-" .. id:gsub("%-", "%%-") .. "$") then
            return read_file(inbox.folder(home.folder) .. "/" .. home.tag .. "/" .. name)
        end
    end
end
-- }}}

-- {{{ local function field
local function field(text, key)
    return text and text:match("\n" .. key .. ": ([^\n]*)") or text and text:match("^" .. key .. ": ([^\n]*)")
end
local function body(text)
    return text and text:match("\n\n(.*)$")
end
-- }}}

os.execute("rm -rf " .. q(ROOT) .. " && mkdir -p " .. q(ROOT))

-- ---------------------------------------------------------------------
-- referees on a home on disk
-- ---------------------------------------------------------------------

check("referee 1: messages filed out of order list in written-then-id order by name", function()
    local function referee()
        local h = make_home("order")
        -- filed, and arrived, in the order 300, 100, 200, then two at 100
        local filed = {
            { id = "c-three", written = 1000000300 }, { id = "a-one", written = 1000000100 },
            { id = "b-two", written = 1000000200 }, { id = "z-late", written = 1000000100 },
            { id = "m-mid", written = 1000000100 },
        }
        for i, m in ipairs(filed) do
            message_log.append(h.disk, h.tag, { id = m.id, from = "10.0.0.9 5000", written = m.written,
                arrived = 1000000000 + i, text = m.id })
        end
        inbox.write_room(h.folder, h.disk, h.tag)
        local order = {}
        for _, name in ipairs(names(inbox.folder(h.folder) .. "/" .. h.tag)) do
            order[#order + 1] = name:match("^%d+%-(.*)$")
        end
        local want = "a-one m-mid z-late b-two c-three"
        must(table.concat(order, " ") == want, "listed " .. table.concat(order, " ") .. ", want " .. want)
    end
    referee()
    must_fail(referee, "arrival-order")
end)

check("referee 2: a correction and a deletion: the corrected text, and deleted: yes with an empty body", function()
    local function referee()
        local h = make_home("edits")
        message_log.append(h.disk, h.tag, { id = "first", from = "10.0.0.9 5000", written = 1000000100,
            arrived = 1000000101, text = "helo\n\nAnn" })
        message_log.append(h.disk, h.tag, { id = "second", from = "me", written = 1000000110,
            arrived = 1000000110, text = "never mind" })
        message_log.correct(h.disk, h.tag, { id = "first-fix", from = "10.0.0.9 5000", written = 1000000120,
            arrived = 1000000121, target = "first", text = "hello\n\nAnn" })
        message_log.delete(h.disk, h.tag, { id = "second-gone", from = "me", written = 1000000130,
            arrived = 1000000130, target = "second" })
        inbox.write_room(h.folder, h.disk, h.tag)
        local first, second = file_of(h, "first"), file_of(h, "second")
        must(first and second, "a message has no file")
        must(body(first) == "hello", "the corrected body is '" .. tostring(body(first)) .. "'")
        must(field(first, "signature") == "Ann", "the signature is '" .. tostring(field(first, "signature")) .. "'")
        must(field(first, "edited") == "yes" and field(first, "deleted") == "no", "first is not marked edited")
        must(field(second, "deleted") == "yes" and body(second) == "", "second is not deleted with an empty body")
        must(field(second, "from") == "me", "from: of an own message is " .. tostring(field(second, "from")))
        must(not file_of(h, "first-fix") and not file_of(h, "second-gone"), "an edit got a file of its own")
    end
    referee()
    must_fail(referee, "raw-text")
end)

check("referee 3: a hide address has no file, a mark address's says ignored: mark", function()
    local function referee()
        local h = make_home("ignored")
        message_log.append(h.disk, h.tag, { id = "from-hidden", from = "10.0.0.5 5000", written = 1000000100,
            arrived = 1000000101, text = "hi" })
        message_log.append(h.disk, h.tag, { id = "from-marked", from = "10.0.0.6 5000", written = 1000000110,
            arrived = 1000000111, text = "hi" })
        message_log.append(h.disk, h.tag, { id = "from-plain", from = "10.0.0.7 5000", written = 1000000120,
            arrived = 1000000121, text = "hi" })
        inbox.write_room(h.folder, h.disk, h.tag)
        must(file_of(h, "from-hidden"), "before the hide, its message had no file")
        ignore.ignore(h.disk, "10.0.0.5", 5000, "hide", "*", 1000000200)
        ignore.ignore(h.disk, "10.0.0.6", 5000, "mark", "*", 1000000200)
        inbox.write_room(h.folder, h.disk, h.tag)
        must(not file_of(h, "from-hidden"), "a hidden address's message still has a file")
        must(field(file_of(h, "from-marked"), "ignored") == "mark", "the marked address's file is not ignored: mark")
        must(field(file_of(h, "from-plain"), "ignored") == "none", "a plain address's file is not ignored: none")
        must(field(file_of(h, "from-plain"), "from") == "10.0.0.7 5000", "from: is not the address and port")
    end
    referee()
    must_fail(referee, "hide-shown")
end)

check("referee 5: a reader polling the folder never sees half a file", function()
    local function referee()
        local h = make_home("half")
        local text = string.rep("a long message line\n", 4000) .. "END"
        message_log.append(h.disk, h.tag, { id = "long", from = "10.0.0.9 5000", written = 1000000100,
            arrived = 1000000101, text = text })
        local folder = inbox.folder(h.folder) .. "/" .. h.tag
        os.execute("mkdir -p " .. q(folder))
        local seen = ROOT .. "/seen-" .. count
        -- a reader, as a viewer would be: every file it can list, its last bytes
        local done = ROOT .. "/done-" .. count
        os.execute("( while [ ! -e " .. q(done) .. " ]; do for f in " .. q(folder) .. "/*; do [ -f \"$f\" ] && "
            .. "tail -c 3 \"$f\" && echo; done; done > " .. q(seen) .. " 2>/dev/null; touch " .. q(done .. ".read")
            .. " ) &")
        for _ = 1, 20 do
            os.execute("rm -f " .. q(folder) .. "/*")
            inbox.write_room(h.folder, h.disk, h.tag)
            socket.sleep(0.05)
        end
        os.execute("touch " .. q(done))
        wait_until(function() return read_file(done .. ".read") ~= nil end, 5)
        local whole, half = 0, 0
        for line in (read_file(seen) or ""):gmatch("[^\n]+") do
            if line == "END" then whole = whole + 1 else half = half + 1 end
        end
        must(whole > 0, "the reader never saw the file")
        must(half == 0, half .. " read(s) of half a file")
    end
    referee()
    must_fail(referee, "in-place")
end)

check("a file is written only when it changes, and a removed file is written again", function()
    local h = make_home("again")
    message_log.append(h.disk, h.tag, { id = "one", from = "me", written = 1000000100, arrived = 1000000100,
        text = "hi" })
    must(inbox.write_room(h.folder, h.disk, h.tag) == 2, "the first pass did not write the file and .room")
    must(inbox.write_room(h.folder, h.disk, h.tag) == 0, "an unchanged room was written again")
    local log_before = read_file(rooms.log_path(h.disk, h.tag))
    os.execute("rm -f " .. q(inbox.folder(h.folder) .. "/" .. h.tag) .. "/*")
    must(inbox.write_room(h.folder, h.disk, h.tag) == 1, "the removed file was not written again")
    must(read_file(rooms.log_path(h.disk, h.tag)) == log_before, "removing an inbox file changed the log")
end)

check("a room tag or id that cannot name a file is refused before a path is built", function()
    local h = make_home("names")
    must(not pcall(inbox.write_room, h.folder, h.disk, "../" .. h.tag:sub(4)), "a tag with a slash was taken")
    must(not pcall(inbox.file_name, { id = "../x", written = 1 }), "an id with a slash was taken")
end)

check("typed/: 301's shape and 211's are read, anything else refused; the written time and the id", function()
    local tag = string.rep("ab", 16)
    local t = ram.decode_typed("room: " .. tag .. "\nwritten: 1000000100\n\nhello\n\nMe\n")
    must(t and t.room == tag and t.written == 1000000100 and t.text == "hello\n\nMe", "301's shape misread")
    t = ram.decode_typed("room = " .. tag .. "\n\nhello\n")
    must(t and t.room == tag and t.written == nil and t.text == "hello", "211's shape misread")
    must(not ram.decode_typed("room: " .. tag .. "\nwriten: 5\n\nhi"), "a misspelt header was taken")
    must(not ram.decode_typed("room: " .. tag .. "\nwritten: soon\n\nhi"), "written: soon was taken")
    must(not ram.decode_typed("room: " .. tag .. "\nroom: " .. tag .. "\n\nhi"), "room: twice was taken")
    must(not ram.decode_typed("room: abc\n\nhi"), "a short tag was taken")
    must(not ram.decode_typed("hello"), "a file with no header was taken")
    must(ram.typed_written({ written = 100 }, 200) == 100, "an earlier written time was not kept")
    must(ram.typed_written({ written = 300 }, 200) == 200, "a written time in the future was kept")
    must(ram.typed_written({}, 200) == 200, "no written time did not take the clock")
    local bytes = "room: " .. tag .. "\nwritten: 1\n\nsame text"
    local id = ram.typed_id("0000000001-000001-aaaaaaaa", bytes)
    must(id:match("^%x+$") and #id == 32, "the id is not 32 hex: " .. id)
    must(ram.typed_id("0000000001-000001-aaaaaaaa", bytes) == id, "the same file gave another id")
    must(ram.typed_id("0000000001-000002-bbbbbbbb", bytes) ~= id, "two files with the same text gave one id")
end)

-- ---------------------------------------------------------------------
-- a room's facts (.room) and the tree (.tree)
-- ---------------------------------------------------------------------

-- {{{ local function room_facts
-- the text of .room → { key = value } (pile: a list of lines)
local function room_facts(text)
    local facts = { pile = {} }
    for line in (text or ""):gmatch("[^\n]+") do
        local key, value = line:match("^(%a+): (.*)$")
        if key == "pile" then facts.pile[#facts.pile + 1] = value elseif key then facts[key] = value end
    end
    return facts
end
-- }}}

-- {{{ local function parent_and_child
-- A disk home with "home" and its declared child "ritz" (one mailbox),
-- and a RAM home loaded with the child alone, as a gatherer whose
-- mailbox held only the child would have.
local function parent_and_child()
    local h = make_home("tree")
    rooms.write_label(h.disk, h.tag, "home")
    local child = rooms.make_room(h.disk, { label = "ritz", token = "inbox files child " .. count, kind = "group",
        parent = rooms.token_fingerprint("inbox files test room " .. count), members = {}, filed_under = "",
        mailbox_port = "" })
    recipients.add_member(h.disk, h.tag, "10.0.0.1", 5000)
    recipients.add_member(h.disk, h.tag, "10.0.0.2", 5000)
    recipients.add_member(h.disk, child, "10.0.0.1", 5000)
    -- not in the parent: added, and flagged (103)
    recipients.add_member(h.disk, child, "10.0.0.3", 5000)
    local ram_home_dir = h.folder .. "/home"
    ram.load(h.dir, ram_home_dir, { child })
    h.child, h.ram = child, rooms.open_home(ram_home_dir)
    return h
end
-- }}}

check(".room: label, kind, the parent and path from the whole home, members, flagged and the pile", function()
    local function referee()
        local h = parent_and_child()
        local word, id = delivery.write(h.ram, h.child, { kind = "message", text = "for the pile" }, 1000000500)
        inbox.write_facts(h.folder, h.ram, h.disk, { h.child })
        local facts = room_facts(read_file(inbox.folder(h.folder) .. "/" .. h.child .. "/.room"))
        must(facts.label == "ritz" and facts.kind == "group", "label/kind: " .. tostring(facts.label) .. "/" .. tostring(facts.kind))
        must(facts.parent == h.tag, "parent: " .. tostring(facts.parent) .. ", want the parent room " .. h.tag)
        must(facts.path == "home/ritz", "path: " .. tostring(facts.path))
        must(facts.members == "2" and facts.flagged == "1", "members/flagged: " .. tostring(facts.members) .. "/"
            .. tostring(facts.flagged))
        must(#facts.pile == 1 and facts.pile[1] == "10.0.0.1 5000 1 1000000500",
            "pile: " .. table.concat(facts.pile, " | ") .. " (the flagged member is sent nothing)")
        delivered.acknowledge(h.ram, h.child, { address = "10.0.0.1", port = 5000 }, { id })
        must(inbox.write_facts(h.folder, h.ram, h.disk, { h.child }) == 1, ".room was not rewritten after the ack")
        must(inbox.write_facts(h.folder, h.ram, h.disk, { h.child }) == 0, "an unchanged .room was written again")
        facts = room_facts(read_file(inbox.folder(h.folder) .. "/" .. h.child .. "/.room"))
        must(#facts.pile == 1 and facts.pile[1] == "none", "after the ack, pile: " .. table.concat(facts.pile, " | "))
    end
    referee()
    must_fail(referee, "ram-tree")
end)

check(".tree: one line per room of the mailbox, its parent from the whole home", function()
    local function referee()
        local h = parent_and_child()
        inbox.write_all(h.folder, h.ram, { h.child }, h.disk)
        local text = read_file(inbox.folder(h.folder) .. "/.tree")
        local want = h.child .. " " .. h.tag .. " group ritz\n"
        must(text == want, ".tree is '" .. tostring(text) .. "', want '" .. want .. "'")
        must(read_file(inbox.folder(h.folder) .. "/" .. h.child .. "/.room"), "write_all wrote no .room")
    end
    referee()
    must_fail(referee, "ram-tree")
end)

-- ---------------------------------------------------------------------
-- one real gatherer
-- ---------------------------------------------------------------------

-- The sync interval is a minute, so what appears within seconds was
-- written at start-up or by the filing hook, not by a sync.
check("a gatherer writes the inbox at start-up and after a typed message, from: me", function()
    local h = make_home("live", { ["gatherer.ram-root"] = ROOT .. "/ram", ["gatherer.address"] = "127.0.0.2",
        ["gatherer.sync-interval"] = "60", ["git.home-name"] = "live" })
    message_log.append(h.disk, h.tag, { id = "on-disk", from = "10.0.0.9 5000", written = 1000000100,
        arrived = 1000000101, text = "waiting since before\n\nBo" })
    local folder = ram.home_ram(ROOT .. "/ram", h.dir) .. "/" .. h.mailbox
    os.execute("mkdir -p " .. q(folder))
    local pipe = io.popen("luajit " .. q(DIR .. "/src/gatherer/163-gatherer.lua") .. " " .. q(DIR) .. " "
        .. q(h.dir) .. " " .. q(h.mailbox) .. " </dev/null >>" .. q(folder .. "/stderr") .. " 2>&1 & echo $!")
    local pid = tonumber(pipe:read("*l"))
    pipe:close()
    local room = inbox.folder(folder) .. "/" .. h.tag
    local ok, problem = pcall(function()
        must(wait_until(function() return #names(room) == 1 end, 10),
            "no inbox file at start-up: " .. tostring(read_file(folder .. "/stderr")))
        local first = read_file(room .. "/" .. names(room)[1])
        must(body(first) == "waiting since before" and field(first, "signature") == "Bo",
            "the start-up file is wrong: " .. tostring(first))
        ram.put(folder .. "/typed", ram.new_name(now()), "room = " .. h.tag .. "\n\ntyped here\n\nMe\n")
        must(wait_until(function() return #names(room) == 2 end, 10), "no inbox file for the typed message")
        local mine
        for _, name in ipairs(names(room)) do
            local text = read_file(room .. "/" .. name)
            if field(text, "from") == "me" then mine = text end
        end
        must(mine and body(mine) == "typed here" and field(mine, "signature") == "Me",
            "the typed message's file is wrong: " .. tostring(mine))
    end)
    os.execute("kill -9 " .. pid .. " 2>/dev/null")
    os.execute("pkill -9 -f " .. q(ROOT) .. " 2>/dev/null")
    if not ok then error(problem, 0) end
end)


-- ---------------------------------------------------------------------
-- referee 4: typed becomes sent (two real gatherers)
-- ---------------------------------------------------------------------

local LIVE_TOKEN = "inbox files live room"
local live_pids = {}

-- {{{ local function make_live
-- A home on its own loopback address, one room shared with the others by
-- token, a minute's sync (what appears within seconds was not a sync).
local function make_live(name, address, port)
    count = count + 1
    local dir = ROOT .. "/homes/" .. name .. "-" .. count
    local h = rooms.open_home(dir)
    for key, value in pairs(START) do rooms.set_config(h, key, value) end
    local config = {
        ["gatherer.ram-root"] = ROOT .. "/ram", ["gatherer.address"] = address,
        ["gatherer.sync-interval"] = "60", ["delivery.retry-floor"] = "1", ["delivery.retry-ceiling"] = "2",
        ["callback.answer-time"] = "2", ["git.home-name"] = name .. "-" .. count,
    }
    for key, value in pairs(config) do rooms.set_config(h, key, value) end
    local tag = rooms.make_room(h, { label = "the room", token = LIVE_TOKEN, kind = "group", parent = "",
        members = {}, filed_under = "", mailbox_port = port })
    local mailbox = rooms.read_entry(h, tag).mailbox
    return { dir = dir, disk = h, tag = tag, mailbox = mailbox, pair = { address = address, port = port },
             folder = ram.home_ram(ROOT .. "/ram", dir) .. "/" .. mailbox }
end
-- }}}

-- {{{ local function alive / start_live / kill_live / stop_live
local function alive(pid)
    local f = pid and io.open("/proc/" .. pid .. "/stat", "rb")
    if not f then return false end
    local stat = f:read("*a")
    f:close()
    return stat:match("%) (%a)") ~= "Z"
end
local function start_live(home, env)
    os.execute("mkdir -p " .. q(home.folder))
    local pipe = io.popen((env or "") .. " luajit " .. q(DIR .. "/src/gatherer/163-gatherer.lua") .. " " .. q(DIR)
        .. " " .. q(home.dir) .. " " .. q(home.mailbox) .. " </dev/null >>" .. q(home.folder .. "/stderr")
        .. " 2>&1 & echo $!")
    home.pid = tonumber(pipe:read("*l"))
    pipe:close()
    live_pids[#live_pids + 1] = home.pid
    wait_until(function() return (ram.read_state(home.folder).pid or "") == tostring(home.pid) end, 5)
end
local function stop_live()
    for _, pid in ipairs(live_pids) do if alive(pid) then os.execute("kill -9 " .. pid .. " 2>/dev/null") end end
    live_pids = {}
    os.execute("pkill -9 -f " .. q(ROOT .. "/homes") .. " 2>/dev/null")
    socket.sleep(0.2)
end
-- }}}

-- {{{ local function texts_in
-- how many messages of a home's RAM copy of its room carry this text
local function texts_in(home, text)
    local ok, list = pcall(message_log.read_ordered, rooms.open_home(home.folder .. "/home"), home.tag)
    if not ok then return 0 end
    local n = 0
    for _, view in ipairs(list) do if view.text == text then n = n + 1 end end
    return n
end
-- }}}

-- {{{ local function mine_in_inbox
-- the inbox files of a home's room that say from: me, as texts
local function mine_in_inbox(home)
    local room = inbox.folder(home.folder) .. "/" .. home.tag
    local list = {}
    for _, name in ipairs(names(room)) do
        local text = read_file(room .. "/" .. name)
        if field(text, "from") == "me" then list[#list + 1] = text end
    end
    return list
end
-- }}}

-- {{{ local function owed
local function owed(home, pair)
    local ok, list = pcall(function()
        return delivered.missing_for(rooms.open_home(home.folder .. "/home"), home.tag, pair)
    end)
    return ok and #list or math.huge
end
-- }}}

-- {{{ local function referee_typed
-- A typed file in 301's shape: filed with its own written time, sent to
-- B and acknowledged, in A's inbox once as from: me, the typed file gone,
-- and A's .room pile empty again.  With `crash`, A dies between filing
-- and removing the typed file, and is started again.
local function referee_typed(crash, broken)
    stop_live()
    local a = make_live("A", "127.0.0.2", 7612)
    local b = make_live("B", "127.0.0.3", 7613)
    recipients.add_member(a.disk, a.tag, b.pair.address, b.pair.port)
    recipients.add_member(b.disk, b.tag, a.pair.address, a.pair.port)
    local env = (crash and "RAO_GATHERER_CRASH=typed:1 " or "") .. (broken and ((broken == "stale-pile"
        and "RAO_INBOX_BROKEN=" or "RAO_GATHERER_BROKEN=") .. broken) or "")
    start_live(a, env)
    local text = "typed in a viewer " .. count .. "\n\nMe"
    local written = math.floor(now()) - 100
    ram.put(a.folder .. "/typed", ram.new_name(now()), "room: " .. a.tag .. "\nwritten: " .. written .. "\n\n"
        .. text .. "\n")
    if crash then
        must(wait_until(function() return not alive(a.pid) end, 10), "A never reached its crash point")
        start_live(a)
    end
    -- B is down: the message waits for it, and A's .room says so
    must(wait_until(function() return texts_in(a, text) >= 1 end, 10),
        "A never filed the typed message: " .. tostring(read_file(a.folder .. "/stderr")))
    must(wait_until(function()
        local pile = room_facts(read_file(inbox.folder(a.folder) .. "/" .. a.tag .. "/.room")).pile
        return pile[1] and pile[1]:match("^127%.0%.0%.3 7613 1 ") ~= nil
    end, 10), "A's .room does not show the message waiting for B: "
        .. tostring(read_file(inbox.folder(a.folder) .. "/" .. a.tag .. "/.room")))
    start_live(b)
    must(wait_until(function() return owed(a, b.pair) == 0 and texts_in(b, text) >= 1 end, 20),
        "B never acknowledged the typed message")
    socket.sleep(1)
    must(texts_in(a, text) == 1, "the typed message is in A's log " .. texts_in(a, text) .. " times")
    must(texts_in(b, text) == 1, "the typed message is in B's log " .. texts_in(b, text) .. " times")
    local mine = mine_in_inbox(a)
    must(#mine == 1, #mine .. " from: me file(s) in A's inbox")
    must(body(mine[1]) == "typed in a viewer " .. count and field(mine[1], "signature") == "Me",
        "the inbox file's body or signature is wrong: " .. tostring(mine[1]))
    must(field(mine[1], "written") == tostring(written), "written: is " .. tostring(field(mine[1], "written"))
        .. ", the typed file said " .. written)
    must(#ram.waiting(a.folder .. "/typed") == 0 and #names(a.folder .. "/typed/working") == 0,
        "the typed file is still there")
    must(wait_until(function()
        local pile = room_facts(read_file(inbox.folder(a.folder) .. "/" .. a.tag .. "/.room")).pile
        return pile[1] == "none"
    end, 5), "A's .room still shows a pile after B acknowledged")
    stop_live()
end
-- }}}

-- {{{ local function must_fail_live
local function must_fail_live(referee, broken)
    local ok, caught = pcall(referee, broken)
    stop_live()
    if ok then error("the referee passed a broken version: " .. broken, 2) end
    print("     caught (" .. broken .. "): " .. tostring(caught):gsub("^[^:]*:%d+: ", ""))
end
-- }}}

check("referee 4: a typed file is filed with its written time, sent, acknowledged, in the inbox as from: me, and gone", function()
    referee_typed(false)
end)

check("referee 4: a crash between filing a typed file and removing it files and sends it once", function()
    referee_typed(true)
    must_fail_live(function(broken) referee_typed(true, broken) end, "typed-fresh-id")
    must_fail_live(function(broken) referee_typed(true, broken) end, "typed-remove-first")
end)

check("A's .room pile empties when the sender is acknowledged, not only at the next sync", function()
    must_fail_live(function(broken) referee_typed(false, broken) end, "stale-pile")
end)

stop_live()
if not os.getenv("KEEP") then os.execute("rm -rf " .. q(ROOT)) else print("kept " .. ROOT) end
print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
