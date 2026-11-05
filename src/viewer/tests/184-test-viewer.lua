-- 184-test-viewer.lua — the referees of issue 301's third step, the
-- reference viewer (183): it reads only the RAM folders, joins the
-- gatherers' trees, shows what the inbox files say, and writes typed
-- files a gatherer files and sends; each referee also against the broken
-- version it must catch.
--
-- Run it under the loopback-only wrapper (a network namespace with only
-- `lo`): its two gatherers listen on 127.0.0.2 and 127.0.0.3.  Homes and
-- RAM folders are in a folder of its own under /dev/shm (or /tmp),
-- removed at the end.
--
-- Run: luajit src/viewer/tests/184-test-viewer.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>".

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/viewer/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local ffi = require("ffi")
local socket = require("socket")
local rooms = require("002-room-folders")
local message_log = require("081-message-log")
local recipients = require("041-recipients")
local ram = require("161-ram-folders")
local inbox = require("181-inbox-files")
local viewer = require("183-viewer")

ffi.cdef [[ int getpid(void); ]]

local base = os.execute("test -d /dev/shm && test -w /dev/shm") == 0 and "/dev/shm" or "/tmp"
local ROOT = base .. "/rao-chat-viewer-test-" .. ffi.C.getpid()
local VIEWER = DIR .. "/src/viewer/183-viewer.lua"
local passed, failed = 0, 0
local q = function(text) return "'" .. tostring(text):gsub("'", "'\\''") .. "'" end
local now = socket.gettime

-- {{{ local function check / must / must_fail
local ONLY = os.getenv("ONLY")
local function check(claim, test)
    if ONLY and not claim:find(ONLY, 1, true) then return end
    local ok, problem = pcall(test)
    viewer.broken = ""
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
-- referee(broken) is run with the broken version set both in this
-- process (183 as a module) and for the viewer it runs as a program
local function must_fail(referee, broken)
    viewer.broken = broken
    local ok, caught = pcall(referee, broken)
    viewer.broken = ""
    if ok then error("the referee passed a broken version: " .. broken, 2) end
    print("     caught (" .. broken .. "): " .. tostring(caught):gsub("^[^:]*:%d+: ", ""))
end
-- }}}

-- {{{ local function read_file / run
local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
-- the viewer as a program → its standard output, and its exit status
local function run(broken, ...)
    local words = {}
    for _, word in ipairs({ ... }) do words[#words + 1] = q(word) end
    local p = io.popen((broken and broken ~= "" and ("RAO_VIEWER_BROKEN=" .. broken .. " ") or "") .. "luajit "
        .. q(VIEWER) .. " " .. table.concat(words, " ") .. " 2>&1; echo \"exit $?\"")
    local out = p:read("*a")
    p:close()
    local status = tonumber(out:match("exit (%d+)\n$"))
    return out:gsub("exit %d+\n$", ""), status
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

os.execute("rm -rf " .. q(ROOT) .. " && mkdir -p " .. q(ROOT .. "/homes"))

-- ---------------------------------------------------------------------
-- a home of two mailboxes, its inbox written as two gatherers would
-- ---------------------------------------------------------------------

-- {{{ local function two_mailboxes
-- "home" (mailbox 1) with a declared child "ritz" (mailbox 1, by 101's
-- rule), "coffee" in mailbox 2 filed under "home", and three more rooms
-- filed under "home", each in a mailbox of its own, whose labels run
-- against their tags' order, so an order by tag can never pass for one
-- by label.  Five gatherers' trees to join.  The inbox
-- is written for each mailbox from a RAM home holding only its rooms,
-- as each gatherer does; then the disk home is moved away.
local function two_mailboxes()
    count = count + 1
    local dir = ROOT .. "/homes/two-" .. count
    local h = rooms.open_home(dir)
    for key, value in pairs(START) do rooms.set_config(h, key, value) end
    local function room(label, token, parent, filed, port)
        return rooms.make_room(h, { label = label, token = token .. count, kind = "group", parent = parent,
            members = {}, filed_under = filed, mailbox_port = port })
    end
    local home = room("home", "viewer home ", "", "", 48000 + count * 10)
    local ritz = room("ritz", "viewer ritz ", rooms.token_fingerprint("viewer home " .. count), "", "")
    local coffee = room("coffee", "viewer coffee ", "", home, 48001 + count * 10)
    local mb2 = rooms.read_entry(h, coffee).mailbox
    local others = {}
    for i = 1, 3 do
        local tag = rooms.make_room(h, { label = "x" .. i, token = "viewer other " .. i .. " " .. count, kind = "group",
            parent = "", members = {}, filed_under = home, mailbox_port = 48001 + count * 10 + i })
        others[#others + 1] = tag
    end
    -- labels against the tags' order: the smallest tag gets the last label
    table.sort(others)
    for i, tag in ipairs(others) do rooms.write_label(h, tag, ({ "zeta", "theta", "eta" })[i]) end
    recipients.add_member(h, home, "10.0.0.1", 5000)
    recipients.add_member(h, ritz, "10.0.0.1", 5000)
    recipients.add_member(h, ritz, "10.0.0.3", 5000)   -- flagged: not in home
    message_log.append(h, coffee, { id = "first", from = "10.0.0.9 5000", written = 1000000100,
        arrived = 1000000101, text = "helo\n\nAnn" })
    message_log.correct(h, coffee, { id = "first-fix", from = "10.0.0.9 5000", written = 1000000120,
        arrived = 1000000121, target = "first", text = "hello\n\nAnn" })
    message_log.append(h, coffee, { id = "second", from = "me", written = 1000000130, arrived = 1000000130,
        text = "gone soon" })
    message_log.delete(h, coffee, { id = "second-gone", from = "me", written = 1000000140, arrived = 1000000140,
        target = "second" })
    local mb1 = rooms.read_entry(h, home).mailbox
    local home_ram = ram.home_ram(ROOT .. "/ram", dir)
    local out = { dir = dir, home_ram = home_ram, home = home, ritz = ritz, coffee = coffee, others = others,
        mb1 = mb1, mb2 = mb2 }
    for _, mailbox in ipairs(rooms.read_mailboxes(h)) do
        mailbox = mailbox.tag
        local folder = home_ram .. "/" .. mailbox
        local tags = rooms.list_rooms_by_mailbox(h, mailbox)
        os.execute("mkdir -p " .. q(folder .. "/typed"))
        ram.load(dir, folder .. "/home", tags)
        inbox.write_all(folder, rooms.open_home(folder .. "/home"), tags, h)
    end
    os.execute("mv " .. q(dir) .. " " .. q(dir .. ".away"))
    return out
end
-- }}}

check("tree: the gatherers' trees joined by tag, children by label, flagged members shown", function()
    local function referee(broken)
        local t = two_mailboxes()
        local out, status = run(broken, t.home_ram, "tree")
        must(status == 0, "the viewer failed: " .. out)
        local want = table.concat({
            "home  " .. t.home:sub(1, 8),
            "  coffee  " .. t.coffee:sub(1, 8),
            "  eta  " .. t.others[3]:sub(1, 8),
            "  ritz  " .. t.ritz:sub(1, 8) .. " [1 flagged]",
            "  theta  " .. t.others[2]:sub(1, 8),
            "  zeta  " .. t.others[1]:sub(1, 8),
        }, "\n") .. "\n"
        must(out == want, "the tree is\n" .. out .. "want\n" .. want)
    end
    referee()
    must_fail(referee, "own-order")
end)

check("room: what the inbox files say (edits applied, deleted, signature), found by path of labels", function()
    local t = two_mailboxes()
    local out, status = run(nil, t.home_ram, "room", "home/coffee")
    must(status == 0, "the viewer failed: " .. out)
    must(out:find("== home/coffee (group, 0 member(s))", 1, true), "no heading: " .. out)
    must(out:find("    hello\n    -- Ann", 1, true) and not out:find("helo\n", 1, true), "not the corrected text: " .. out)
    must(out:find("me\n    (deleted)", 1, true) and not out:find("gone soon", 1, true), "the deletion is not shown: " .. out)
    must(out:find("(edited)", 1, true), "the correction is not marked edited")
    local by_tag = run(nil, t.home_ram, "room", t.coffee:sub(1, 6))
    must(by_tag == out, "the room found by the start of its tag reads differently")
    local _, missing = run(nil, t.home_ram, "room", "nowhere/at-all")
    must(missing == 1, "an unknown room did not fail")
end)

check("write: a typed file in 301's shape in the room's own gatherer, signature checked by 214's rule", function()
    local t = two_mailboxes()
    local before = os.time()
    local out, status = run(nil, t.home_ram, "write", "home/coffee", "--signature", "Me", "see", "you", "there")
    must(status == 0, "the viewer failed: " .. out)
    local queue = t.home_ram .. "/" .. t.mb2 .. "/typed"
    local files = ram.waiting(queue)
    must(#files == 1, #files .. " typed file(s) in the coffee room's gatherer")
    must(#ram.waiting(t.home_ram .. "/" .. t.mb1 .. "/typed") == 0, "a typed file went to the other gatherer")
    local typed = ram.decode_typed(read_file(queue .. "/" .. files[1]))
    must(typed and typed.room == t.coffee and typed.text == "see you there\n\nMe", "the typed file is wrong")
    must(typed.written >= before and typed.written <= os.time(), "written: is not this clock")
    local long = string.rep("n", 81)
    local refused, refused_status = run(nil, t.home_ram, "write", "home/coffee", "--signature", long, "hi")
    must(refused_status == 1 and refused:find("would not be read as a signature", 1, true),
        "a signature 214 would not read back was taken: " .. refused)
    must(#ram.waiting(queue) == 1, "the refused message was written anyway")
end)

check("write: a gatherer polling typed/ never reads half a file", function()
    local function referee()
        local t = two_mailboxes()
        local queue = t.home_ram .. "/" .. t.mb2 .. "/typed"
        local text = string.rep("a long line of typing\n", 3000) .. "END"
        local done = ROOT .. "/done-" .. count
        local seen = ROOT .. "/seen-" .. count
        -- a reader as the filer reads: every plain name, its last bytes
        os.execute("( while [ ! -e " .. q(done) .. " ]; do for f in " .. q(queue) .. "/[0-9]*; do [ -f \"$f\" ] && "
            .. "tail -c 4 \"$f\" && echo; done; done > " .. q(seen) .. " 2>/dev/null; touch " .. q(done .. ".read")
            .. " ) &")
        for _ = 1, 3 do
            assert(viewer.write(t.home_ram, "home/coffee", text, nil, now()))
            socket.sleep(0.1)
        end
        os.execute("touch " .. q(done))
        wait_until(function() return read_file(done .. ".read") ~= nil end, 5)
        local whole, half = 0, 0
        for line in (read_file(seen) or ""):gmatch("[^\n]+") do
            if line == "END" then whole = whole + 1 elseif line ~= "" then half = half + 1 end
        end
        must(whole > 0, "the reader never saw a file")
        must(half == 0, half .. " read(s) of half a file")
    end
    referee()
    must_fail(referee, "in-place")
end)

check("problems: each gatherer's problem lines from its state", function()
    local t = two_mailboxes()
    ram.write_state(t.home_ram .. "/" .. t.mb2, { pid = 1, ["problem.typed"] = "x: a typed file is header lines" })
    local out = run(nil, t.home_ram, "problems")
    must(out == t.mb2:sub(1, 8) .. " typed: x: a typed file is header lines\n", "problems: " .. out)
end)

-- ---------------------------------------------------------------------
-- end to end: a viewer writes, two gatherers carry it, viewers read it
-- ---------------------------------------------------------------------

local pids = {}
-- {{{ local function live_home
local function live_home(name, address, port)
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
    local tag = rooms.make_room(h, { label = "together", token = "viewer live room", kind = "group", parent = "",
        members = {}, filed_under = "", mailbox_port = port })
    local mailbox = rooms.read_entry(h, tag).mailbox
    local home_ram = ram.home_ram(ROOT .. "/ram", dir)
    return { dir = dir, disk = h, tag = tag, mailbox = mailbox, address = address, port = port,
             home_ram = home_ram, folder = home_ram .. "/" .. mailbox }
end
-- }}}
-- {{{ local function start
local function start(home)
    os.execute("mkdir -p " .. q(home.folder))
    local pipe = io.popen("luajit " .. q(DIR .. "/src/gatherer/163-gatherer.lua") .. " " .. q(DIR) .. " "
        .. q(home.dir) .. " " .. q(home.mailbox) .. " </dev/null >>" .. q(home.folder .. "/stderr") .. " 2>&1 & echo $!")
    pids[#pids + 1] = tonumber(pipe:read("*l"))
    pipe:close()
end
-- }}}

check("end to end: written in A's viewer, filed and sent by A's gatherer, read in B's viewer", function()
    local a = live_home("A", "127.0.0.2", 7622)
    local b = live_home("B", "127.0.0.3", 7623)
    recipients.add_member(a.disk, a.tag, b.address, b.port)
    recipients.add_member(b.disk, b.tag, a.address, a.port)
    start(a)
    start(b)
    local ok, problem = pcall(function()
        must(wait_until(function() return read_file(a.folder .. "/inbox/.tree") ~= nil end, 10),
            "A's gatherer wrote no tree: " .. tostring(read_file(a.folder .. "/stderr")))
        local out, status = run(nil, a.home_ram, "write", "together", "--signature", "Ann", "hello", "B")
        must(status == 0, "A's viewer failed: " .. out)
        must(wait_until(function() return run(nil, b.home_ram, "room", "together"):find("    hello B\n    -- Ann",
            1, true) ~= nil end, 15), "B's viewer never showed it: " .. run(nil, b.home_ram, "room", "together"))
        local b_view = run(nil, b.home_ram, "room", "together")
        must(b_view:find("127.0.0.2 7622", 1, true), "B's viewer does not say it is from A: " .. b_view)
        local a_view = run(nil, a.home_ram, "room", "together")
        must(a_view:find("  me\n    hello B\n    -- Ann", 1, true), "A's viewer does not show it from me: " .. a_view)
        must(wait_until(function() return not run(nil, a.home_ram, "tree"):find("waiting", 1, true) end, 10),
            "A's tree still shows a message waiting: " .. run(nil, a.home_ram, "tree"))
    end)
    for _, pid in ipairs(pids) do os.execute("kill -9 " .. pid .. " 2>/dev/null") end
    os.execute("pkill -9 -f " .. q(ROOT .. "/homes") .. " 2>/dev/null")
    if not ok then error(problem, 0) end
end)

if not os.getenv("KEEP") then os.execute("rm -rf " .. q(ROOT)) else print("kept " .. ROOT) end
print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
