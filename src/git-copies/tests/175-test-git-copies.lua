-- 175-test-git-copies.lua — the referees of issue 215 (one git repository
-- per mailbox, with a text copy of every message), each against real
-- gatherer processes on loopback or against the copies module on a home
-- on disk, and each, where the issue names one, against a deliberately
-- broken version it must catch.
--
-- Run it under the loopback-only wrapper (a network namespace with only
-- `lo`): the homes listen on and send from 127.0.0.2 and .3.  Its homes,
-- RAM folders and repositories are in a folder of its own under /dev/shm
-- (or /tmp), removed at the end.
--
-- Run: luajit src/git-copies/tests/175-test-git-copies.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>".

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/git%-copies/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local ffi = require("ffi")
local socket = require("socket")
local rooms = require("002-room-folders")
local recipients = require("041-recipients")
local message_log = require("081-message-log")
local delivered = require("130-delivered")
local ram = require("161-ram-folders")
local git = require("172-git")
local copies_m = require("173-text-copies")

ffi.cdef [[ int getpid(void); ]]

local base = os.execute("test -d /dev/shm && test -w /dev/shm") == 0 and "/dev/shm" or "/tmp"
local ROOT = base .. "/rao-chat-git-copies-test-" .. ffi.C.getpid()
local TOKEN = "git copies test room"
local FINGERPRINT = rooms.token_fingerprint(TOKEN)
local passed, failed = 0, 0

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
local function must_fail(referee, words)
    local ok, caught = pcall(referee)
    if ok then error("the referee passed a broken version: " .. words, 2) end
    print("     caught (" .. words .. "): " .. tostring(caught):gsub("^[^:]*:%d+: ", ""))
end
-- }}}

local q = function(text) return "'" .. tostring(text):gsub("'", "'\\''") .. "'" end
local now = socket.gettime

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

-- {{{ local function read_file / shell
local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
local function shell(command)
    local p = io.popen(command .. " 2>&1")
    local out = p:read("*a")
    p:close()
    return out
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
local all_pids = {}

-- {{{ local function make_home
local function make_home(name, address, port, overrides)
    count = count + 1
    local dir = ROOT .. "/homes/" .. name .. "-" .. count
    os.execute("mkdir -p " .. q(ROOT .. "/homes"))
    local h = rooms.open_home(dir)
    for key, value in pairs(START) do rooms.set_config(h, key, value) end
    local config = {
        ["gatherer.ram-root"] = ROOT .. "/ram", ["gatherer.address"] = address,
        ["gatherer.sync-interval"] = "2", ["delivery.retry-floor"] = "1", ["delivery.retry-ceiling"] = "4",
        ["callback.answer-time"] = "2", ["git.home-name"] = name .. "-" .. count,
    }
    for key, value in pairs(overrides or {}) do config[key] = value end
    for key, value in pairs(config) do rooms.set_config(h, key, value) end
    local tag = rooms.make_room(h, { label = "the room", token = TOKEN, kind = "group", parent = "",
        members = {}, filed_under = "", mailbox_port = port })
    local mailbox = rooms.read_entry(h, tag).mailbox
    return { name = name, dir = dir, disk = h, tag = tag, mailbox = mailbox, address = address, port = port,
             pair = { address = address, port = port }, repo = copies_m.repository(dir, mailbox),
             folder = ram.home_ram(ROOT .. "/ram", dir) .. "/" .. mailbox }
end
-- }}}

-- {{{ local function link
local function link(list)
    for _, a in ipairs(list) do
        for _, b in ipairs(list) do
            if a ~= b then recipients.add_member(a.disk, a.tag, b.address, b.port) end
        end
    end
end
-- }}}

-- {{{ local function alive
local function alive(pid)
    if not pid then return false end
    local f = io.open("/proc/" .. pid .. "/stat", "rb")
    if not f then return false end
    local stat = f:read("*a")
    f:close()
    return stat:match("%) (%a)") ~= "Z"
end
-- }}}

-- {{{ local function start
-- home, env (NAME=value words) → the gatherer's pid.
local function start(home, env)
    os.execute("mkdir -p " .. q(home.folder))
    local pipe = io.popen((env or "") .. " luajit " .. q(DIR .. "/src/gatherer/163-gatherer.lua") .. " " .. q(DIR)
        .. " " .. q(home.dir) .. " " .. q(home.mailbox) .. " </dev/null >>" .. q(home.folder .. "/stderr")
        .. " 2>&1 & echo $!")
    home.pid = tonumber(pipe:read("*l"))
    pipe:close()
    all_pids[#all_pids + 1] = home.pid
    wait_until(function() return (ram.read_state(home.folder).pid or "") == tostring(home.pid) end, 3)
    return home.pid
end
-- }}}

-- {{{ local function stop_all
local function stop_all()
    for _, pid in ipairs(all_pids) do if alive(pid) then os.execute("kill -9 " .. pid .. " 2>/dev/null") end end
    all_pids = {}
    os.execute("pkill -9 -f " .. q(ROOT) .. " 2>/dev/null")
    socket.sleep(0.1)
end
-- }}}

-- {{{ local function type_message
local function type_message(home, text)
    ram.put(home.folder .. "/typed", ram.new_name(now()), "room = " .. home.tag .. "\n\n" .. text .. "\n")
end
-- }}}

-- {{{ local function missing
local function missing(home, pair)
    local ok, list = pcall(function()
        return delivered.missing_for(rooms.open_home(home.folder .. "/home"), home.tag, pair)
    end)
    return ok and #list or math.huge
end
-- }}}

-- {{{ local function copies_in / commits
-- home → {name → bytes} of every file under its repository's rooms/.
local function copies_in(home)
    local list = {}
    local p = io.popen("cd " .. q(home.repo) .. " 2>/dev/null && find rooms -type f | sort")
    for path in p:lines() do list[path] = read_file(home.repo .. "/" .. path) end
    p:close()
    return list
end
local function size(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function commits(home)
    local ok, out = git.run(home.repo, { "rev-list", "--count", "HEAD" })
    return ok and tonumber(out) or 0
end
-- }}}

-- {{{ local function ram_log
local function ram_log(home) return read_file(home.folder .. "/home/rooms/" .. home.tag .. "/log") or "" end
-- }}}

os.execute("rm -rf " .. q(ROOT) .. " && mkdir -p " .. q(ROOT))

------------------------------------------------------------------------------
-- 1. Two homes, one copy
------------------------------------------------------------------------------

-- {{{ local function referee_same(broken)
local function referee_same(broken)
    stop_all()
    local a = make_home("A", "127.0.0.2", 7622)
    local b = make_home("B", "127.0.0.3", 7623)
    link({ a, b })
    local env = broken and ("RAO_COPIES_BROKEN=" .. broken) or nil
    start(a, env)
    start(b, env)
    type_message(a, "hello from A\n\nsorelu")
    must(wait_until(function() return missing(a, b.pair) == 0 and size(copies_in(b)) == 1 end, 15),
        "B never had a copy of A's message")
    local in_a, in_b = copies_in(a), copies_in(b)
    must(size(in_a) == 1, "A holds " .. size(in_a) .. " copies")
    for path, bytes in pairs(in_a) do
        must(path:match("^rooms/(%x+)/") == FINGERPRINT, "the room folder is not the token fingerprint: " .. path)
        must(in_b[path] ~= nil, "B has no copy at A's path " .. path)
        must(in_b[path] == bytes, "the two copies at " .. path .. " differ:\n" .. bytes .. "\n---\n" .. in_b[path])
        must(bytes:find("\nsignature: sorelu\n\nhello from A\n\nsorelu", 1, true), "the copy is not as agreed: " .. bytes)
    end
    stop_all()
end
-- }}}

check("referee 1: two homes holding one room have byte-identical copies at one path", function()
    referee_same()
    must_fail(function() referee_same("per-home-fields") end, "a copy carrying from and arrived")
    must_fail(function() referee_same("local-tag-folder") end, "the local tag as the room folder")
end)

------------------------------------------------------------------------------
-- 2. Every filed record gets a copy; one commit per cycle
------------------------------------------------------------------------------

-- {{{ local function referee_every(broken)
local function referee_every(broken)
    stop_all()
    local over = { ["gatherer.sync-interval"] = "3600" }
    local a = make_home("A", "127.0.0.2", 7622, over)
    local b = make_home("B", "127.0.0.3", 7623, over)
    link({ a, b })
    local env = broken and ("RAO_COPIES_BROKEN=" .. broken) or nil
    -- A alone first: its own messages, nothing received into the room
    start(a, env)
    type_message(a, "one from A")
    type_message(a, "two from A")
    must(wait_until(function() return size(copies_in(a)) == 2 end, 3),
        "A's own two messages have " .. size(copies_in(a)) .. " copies, not 2, with nothing received")
    start(b, env)
    must(wait_until(function() return missing(a, b.pair) == 0 and size(copies_in(b)) == 2 end, 15),
        "B holds " .. size(copies_in(b)) .. " copies of A's two messages")
    type_message(b, "one from B")
    must(wait_until(function() return missing(b, a.pair) == 0 and size(copies_in(a)) == 3 and size(copies_in(b)) == 3 end, 15),
        "B's message was not copied on both homes")
    -- no sync cycle has run (an hour apart): every copy came from the hook
    must(commits(a) == 0, "A committed before its first sync cycle")
    -- the stop file makes one last sync cycle
    os.execute("touch " .. q(a.folder .. "/stop"))
    must(wait_until(function() return not alive(a.pid) end, 10), "A did not stop")
    must(commits(a) == 1, "A's repository has " .. commits(a) .. " commits after one sync, not 1")
    local files = git.must(a.repo, { "show", "--name-only", "--format=%s", "HEAD" })
    local n = 0
    for _ in files:gmatch("rooms/%x+/%d+%-%x+%.txt") do n = n + 1 end
    must(n == 3, "the commit covers " .. n .. " copies, not 3: " .. files)
    must(files:find("sync: 3 copies added", 1, true), "the commit message does not count them: " .. files)
    stop_all()
end
-- }}}

check("referee 2: every filed record gets a copy, own ones included; one commit covers the cycle", function()
    referee_every()
    must_fail(function() referee_every("receive-only") end, "a hook only on receiving")
end)

------------------------------------------------------------------------------
-- 3. Edits are history (the copies module on a home on disk)
------------------------------------------------------------------------------

-- {{{ local function quiet_home
-- A home on disk with one room and its copies, no gatherer.
local function quiet_home(name)
    count = count + 1
    local dir = ROOT .. "/homes/" .. name .. "-" .. count
    os.execute("mkdir -p " .. q(ROOT .. "/homes"))
    local h = rooms.open_home(dir)
    for key, value in pairs(START) do rooms.set_config(h, key, value) end
    local tag = rooms.make_room(h, { label = "quiet", token = TOKEN, kind = "group", parent = "",
        members = {}, filed_under = "", mailbox_port = 7650 + count })
    local mailbox = rooms.read_entry(h, tag).mailbox
    return h, tag, copies_m.open(h, dir, mailbox, name)
end
-- }}}

check("referee 3: a correction then a deletion: the file is gone and git keeps three versions", function()
    local h, tag, c = quiet_home("edits")
    local id = message_log.new_message_id()
    message_log.append(h, tag, { id = id, from = "me", written = 1000, arrived = 1000, text = "first words" })
    c:sync({ tag })
    local path = "rooms/" .. FINGERPRINT .. "/1000-" .. id .. ".txt"
    must(read_file(c.repo .. "/" .. path), "no copy at " .. path)
    message_log.correct(h, tag, { id = message_log.new_message_id(), from = "192.0.2.7 7000", written = 1001,
        arrived = 1002, target = id, text = "second words" })
    c:sync({ tag })
    -- a correction written earlier that arrives later does not win (086's order)
    message_log.correct(h, tag, { id = message_log.new_message_id(), from = "192.0.2.8 7000", written = 1000,
        arrived = 1004, target = id, text = "older words" })
    c:sync({ tag })
    local corrected = read_file(c.repo .. "/" .. path) or ""
    must(corrected:find("kind: correction\ntarget: " .. id .. "\n", 1, true) and corrected:find("\n\nsecond words$"),
        "the copy does not show the latest correction: " .. corrected)
    message_log.delete(h, tag, { id = message_log.new_message_id(), from = "me", written = 1003, arrived = 1003,
        target = id })
    c:sync({ tag })
    must(read_file(c.repo .. "/" .. path) == nil, "the working tree still has the deleted copy")
    local versions = git.must(c.repo, { "log", "--follow", "--format=%h", "--", path })
    local n = select(2, versions:gsub("\n", "")) + 1
    must(n == 3, "git log --follow shows " .. n .. " versions, not 3")
    local first = git.must(c.repo, { "show", "HEAD~2:" .. path })
    must(first:find("\n\nfirst words$"), "the first version is not in history")
end)

------------------------------------------------------------------------------
-- 4. The log is untouched by hand edits
------------------------------------------------------------------------------

-- {{{ local function referee_hands(broken)
local function referee_hands(broken)
    stop_all()
    local a = make_home("A", "127.0.0.2", 7622)
    local b = make_home("B", "127.0.0.3", 7623)
    link({ a, b })
    local env = broken and ("RAO_COPIES_BROKEN=" .. broken) or nil
    start(a, env)
    start(b, env)
    type_message(a, "edit me")
    type_message(a, "delete me")
    must(wait_until(function() return missing(a, b.pair) == 0 and commits(a) >= 1 and size(copies_in(a)) == 2 end, 15),
        "A's two messages were not delivered and committed")
    local before_a, before_b = ram_log(a), ram_log(b)
    local start_commits = commits(a)
    for path, bytes in pairs(copies_in(a)) do
        if bytes:find("edit me", 1, true) then
            local f = io.open(a.repo .. "/" .. path, "wb")
            f:write((bytes:gsub("edit me$", "edited by hand")))
            f:close()
        else
            os.remove(a.repo .. "/" .. path)
        end
    end
    must(wait_until(function() return commits(a) > start_commits end, 10), "the hand edits were never committed")
    local message = git.must(a.repo, { "log", "-1", "--format=%s" })
    must(message:find("1 changed, 1 removed", 1, true), "the commit does not count the edits: " .. message)
    socket.sleep(4.5)       -- two more sync cycles
    must(ram_log(a) == before_a, "A's log changed after the hand edits")
    must(ram_log(b) == before_b, "B's log changed: something was sent")
    must(read_file(a.dir .. "/rooms/" .. a.tag .. "/log") == before_a, "A's log on disk is not the log before")
    stop_all()
end
-- }}}

check("referee 4: hand edits and deletions are committed and change no log; nothing is sent", function()
    referee_hands()
    must_fail(function() referee_hands("edits-to-corrections") end, "a watcher turning copy edits into corrections")
end)

------------------------------------------------------------------------------
-- 5. A failing hook does not stop filing
------------------------------------------------------------------------------

-- {{{ local function referee_failing(broken)
local function referee_failing(broken)
    stop_all()
    local a = make_home("A", "127.0.0.2", 7622)
    local b = make_home("B", "127.0.0.3", 7623)
    link({ a, b })
    start(a)
    start(b, "RAO_COPIES_FAIL=hook:all" .. (broken and (" RAO_COPIES_BROKEN=" .. broken) or ""))
    type_message(a, "filed despite the hook")
    must(wait_until(function() return ram_log(a):find("filed despite the hook", 1, true) and missing(a, b.pair) == 0 end, 8),
        "A's message was never acknowledged by B (the hook stopped filing)")
    local held = select(2, ram_log(b):gsub("filed despite the hook", ""))
    must(held == 1, "B's log holds the message " .. held .. " times, not once")
    must(wait_until(function() return ram.read_state(b.folder)["problem.hook-text-copy"] ~= nil end, 3),
        "B's state has no hook problem line")
    local lines = select(2, (read_file(b.folder .. "/running-log") or ""):gsub("problem hook%-text%-copy", ""))
    must(lines == 1, lines .. " running-log lines about the hook, not 1")
    must(wait_until(function() return size(copies_in(b)) == 1 and commits(b) >= 1 end, 6),
        "the copy did not appear at the next sync")
    stop_all()
end
-- }}}

check("referee 5: a hook that throws: the record is filed and acknowledged; one problem line; the copy at the next sync", function()
    referee_failing()
    must_fail(function() referee_failing("hook-unguarded") end, "the hook inside filing, unguarded")
end)

------------------------------------------------------------------------------
-- 6. Hostile ids stay inside
------------------------------------------------------------------------------

check("referee 6: an id that is not in 105's alphabet is refused before any path is built", function()
    local h, tag, c = quiet_home("hostile")
    for _, id in ipairs({ "../../../escaped", "x/../../../escaped", ".", "a b", ("x"):rep(200) }) do
        local ok = pcall(message_log.append, h, tag, { id = id, from = "me", written = 5, arrived = 5, text = "x" })
        must(not ok or #id > 128, "105 filed the id '" .. id:sub(1, 40) .. "'")
        must(not pcall(copies_m.copy_name, { id = id, written = 5 }), "the copy name was built for '" .. id:sub(1, 40) .. "'")
    end
    -- a record that reached the copies anyway is refused there too
    local ok = pcall(c.apply, c, tag, { kind = "message", id = "x/../../../escaped", written = 5, text = "x" }, nil)
    must(not ok, "the copies applied a record with a hostile id")
    local stray = shell("cd " .. q(c.repo) .. " && find . -path ./.git -prune -o -type f -print | grep -v '^./rooms/' | grep -v '^./labels$'")
    must(stray == "", "files outside rooms/: " .. stray)
    -- the broken version: no check before the path is built
    must_fail(function()
        copies_m.unchecked = true
        pcall(c.apply, c, tag, { kind = "message", id = "x/../../../escaped", written = 5, text = "x" }, nil)
        copies_m.unchecked = false
        local out = shell("cd " .. q(c.repo) .. " && find . -path ./.git -prune -o -type f -print | grep -v '^./rooms/' | grep -v '^./labels$'")
        must(out == "", "files outside rooms/: " .. out:gsub("\n", " "))
    end, "a path built without checking the id")
end)

------------------------------------------------------------------------------
-- 7. No git, no start
------------------------------------------------------------------------------

-- {{{ local function referee_no_git(broken)
local function referee_no_git(broken)
    stop_all()
    local bin = ROOT .. "/bin-without-git"
    os.execute("rm -rf " .. q(bin) .. " && mkdir -p " .. q(bin))
    -- every program on the PATH but git
    for folder in (os.getenv("PATH") or ""):gmatch("[^:]+") do
        os.execute("for f in " .. q(folder) .. "/*; do n=$(basename \"$f\"); [ \"$n\" = git ] || [ -e " .. q(bin)
            .. "/\"$n\" ] || ln -s \"$f\" " .. q(bin) .. "/\"$n\"; done 2>/dev/null")
    end
    must(shell("PATH=" .. q(bin) .. " command -v git") == "", "git is still on the PATH made without it")
    local a = make_home("A", "127.0.0.2", 7622)
    local began = now()
    start(a, "PATH=" .. q(bin) .. (broken and (" RAO_COPIES_BROKEN=" .. broken) or ""))
    must(wait_until(function() return not alive(a.pid) end, 5), "the gatherer kept running without git")
    must(now() - began < 5, "it took more than 5 s to stop")
    local said = (read_file(a.folder .. "/stderr") or "") .. (ram.read_state(a.folder)["problem.git"] or "")
    must(said:find("'git'", 1, true), "neither stderr nor state names git: " .. said)
    must(read_file(a.dir .. "/git/" .. a.mailbox .. "/.git/HEAD") == nil, "a repository was made without git")
    stop_all()
end
-- }}}

check("referee 7: without git on the PATH the gatherer exits naming it", function()
    referee_no_git()
    must_fail(function() referee_no_git("no-git") end, "running on without git")
end)

------------------------------------------------------------------------------
-- The running source code, and labels
------------------------------------------------------------------------------

check("the starter commits the program to code/<home name> once, and again only when it changed", function()
    stop_all()
    local a = make_home("A", "127.0.0.2", 7622)
    local function run_starter()
        local pipe = io.popen("luajit " .. q(DIR .. "/src/gatherer/164-home-starter.lua") .. " " .. q(DIR) .. " "
            .. q(a.dir) .. " </dev/null >/dev/null 2>&1 & echo $!")
        local pid = tonumber(pipe:read("*l"))
        pipe:close()
        all_pids[#all_pids + 1] = pid
        must(wait_until(function() return ram.read_state(a.folder).pid ~= nil end, 5), "no gatherer started")
        os.execute("touch " .. q(ram.home_ram(ROOT .. "/ram", a.dir) .. "/stop"))
        must(wait_until(function() return not alive(pid) end, 12), "the starter did not stop")
        os.remove(a.folder .. "/state")
    end
    run_starter()
    local branch = "code/A-" .. count
    local first = git.ref(a.repo, "refs/heads/" .. branch)
    must(first, "no branch " .. branch)
    local files = git.must(a.repo, { "ls-tree", "-r", "--name-only", branch })
    must(files:find("src/gatherer/163-gatherer.lua", 1, true), "the branch lacks the gatherer's source")
    must(not files:find("^tmp/") and not files:find("\ntmp/"), "the branch holds the ignored tmp/ folder")
    must(git.must(a.repo, { "symbolic-ref", "--short", "HEAD" }) == "rooms", "the checked-out branch is not rooms")
    run_starter()
    must(git.ref(a.repo, "refs/heads/" .. branch) == first, "an unchanged program was committed again")
    local labels = read_file(a.repo .. "/labels") or ""
    must(labels:find(FINGERPRINT .. " the room", 1, true), "labels does not map the fingerprint to the label: " .. labels)
    must(not git.must(a.repo, { "ls-files" }):find("labels", 1, true), "labels is tracked")
    stop_all()
end)

stop_all()
if not os.getenv("KEEP") then os.execute("rm -rf " .. q(ROOT)) else print("kept " .. ROOT) end
print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
