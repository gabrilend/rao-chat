-- 178-test-running-log.lua — the referees of issue 215a (the running log,
-- committed every sync cycle and split by size): 1, 2 and 4 against the
-- module on a repository in the test folder, with a fake clock writing the
-- lines; 3 and a check of the real thing against a gatherer on loopback.
-- Each referee runs against the broken version it must catch.
--
-- Run it under the loopback-only wrapper.  Its folder is under /dev/shm
-- (or /tmp), removed at the end.
--
-- Run: luajit src/git-copies/tests/178-test-running-log.lua [PROJECT_DIR]
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
local ram = require("161-ram-folders")
local git = require("172-git")
local copies_m = require("173-text-copies")
local runlog = require("177-running-log")

ffi.cdef [[ int getpid(void); ]]

local base = os.execute("test -d /dev/shm && test -w /dev/shm") == 0 and "/dev/shm" or "/tmp"
local ROOT = base .. "/rao-chat-running-log-test-" .. ffi.C.getpid()
local passed, failed = 0, 0

-- {{{ local function check / must / must_fail
local function check(claim, test)
    local ok, problem = pcall(test)
    if ok then passed = passed + 1; print("PASS " .. claim)
    else failed = failed + 1; print("FAIL " .. claim .. ": " .. tostring(problem)) end
end
local function must(condition, words)
    if not condition then error(words, 2) end
end
local function must_fail(referee, broken, words)
    runlog.broken = broken
    local ok, caught = pcall(referee)
    runlog.broken = nil
    if ok then error("the referee passed a broken version: " .. words, 2) end
    print("     caught (" .. words .. "): " .. (tostring(caught):gsub("^[^:]*:%d+: ", ""):match("^[^\n]*")))
end
-- }}}

local q = function(text) return "'" .. tostring(text):gsub("'", "'\\''") .. "'" end
local now = socket.gettime

-- {{{ local function read_file / write_file / wait_until
local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
local function write_file(path, text, mode)
    local f = assert(io.open(path, mode or "wb"))
    f:write(text)
    f:close()
end
local function wait_until(condition, seconds)
    local stop = now() + seconds
    while now() < stop do
        if condition() then return true end
        socket.sleep(0.05)
    end
    return condition()
end
-- }}}

os.execute("rm -rf " .. q(ROOT) .. " && mkdir -p " .. q(ROOT))

local made = 0
-- {{{ local function new_repo
-- A mailbox repository with one commit on the rooms' branch, and a RAM
-- folder beside it.
local function new_repo()
    made = made + 1
    local repo = ROOT .. "/repo-" .. made
    git.ensure(repo)
    write_file(repo .. "/rooms/a-copy.txt", "a copy\n")
    git.must(repo, { "add", "-A" })
    local args = git.identity("tester")
    for _, w in ipairs({ "commit", "-q", "-m", "a room's copy" }) do args[#args + 1] = w end
    git.must(repo, args)
    local folder = ROOT .. "/ram-" .. made
    os.execute("mkdir -p " .. q(folder))
    return repo, folder
end
-- }}}

-- {{{ local function fake_lines
-- The fake clock's lines: `total` bytes of whole lines, each stamped and
-- numbered from `first`, as ram.log writes them.
local clock = 1793800000
local function fake_lines(total, first)
    local out, n = {}, first
    local size = 0
    while size < total do
        clock = clock + 1
        local line = os.date("!%Y-%m-%dT%H:%M:%SZ", clock) .. " line " .. n .. " " .. string.rep("x", (n * 7) % 60) .. "\n"
        if size + #line > total then line = string.rep("y", total - size - 1) .. "\n" end
        out[#out + 1] = line
        size = size + #line
        n = n + 1
    end
    return table.concat(out), n
end
-- }}}

-- {{{ local function branch_files
-- repo → list of {path, bytes} on running-log/tester, in order.
local function branch_files(repo, name)
    name = name or "tester"
    local list = {}
    local ok, names = git.run(repo, { "ls-tree", "-r", "--name-only", runlog.branch(name) })
    if not ok then return list end
    for path in names:gmatch("[^\n]+") do
        local p = io.popen(git.command(repo, { "cat-file", "blob", runlog.branch(name) .. ":" .. path }))
        list[#list + 1] = { path = path, bytes = p:read("*a") }
        p:close()
    end
    table.sort(list, function(a, b) return a.path < b.path end)
    return list
end
-- }}}

------------------------------------------------------------------------------
-- 1. Never over the limit
------------------------------------------------------------------------------

check("referee 1: limit 1,000, cycles of 10,000 bytes with one of 2,500: every file at most 1,000, every line once", function()
    local function referee()
        local repo, folder = new_repo()
        local all, n = {}, 1
        for _, size in ipairs({ 900, 300, 2500, 1200, 700, 1000, 1, 1799, 1600 }) do
            local text
            text, n = fake_lines(size, n)
            all[#all + 1] = text
            write_file(folder .. "/running-log", text, "ab")
            runlog.take_and_commit(folder, repo, "tester", 1000)
            must(read_file(folder .. "/running-log") == "", "the RAM log was not emptied after a commit")
        end
        local files = branch_files(repo)
        local joined = {}
        for i, f in ipairs(files) do
            must(#f.bytes <= 1000, f.path .. " holds " .. #f.bytes .. " bytes, over the limit of 1,000")
            must(f.path == string.format("running-log/tester/%04d.log", i), "unexpected file " .. f.path)
            joined[#joined + 1] = f.bytes
        end
        must(table.concat(joined) == table.concat(all), "the files in order are not every line once ("
            .. #table.concat(joined) .. " of " .. #table.concat(all) .. " bytes)")
        print("     " .. #files .. " files for " .. #table.concat(all) .. " bytes")
    end
    referee()
    must_fail(referee, "split-after", "a new file only after passing the limit")
    must_fail(referee, "drop-oversize", "a cycle over the limit dropped")
end)

------------------------------------------------------------------------------
-- 2. Kept on failure
------------------------------------------------------------------------------

check("referee 2: a commit that fails keeps the lines in RAM; the next cycle commits them, none lost or doubled", function()
    local function referee()
        local repo, folder = new_repo()
        local first = fake_lines(400, 1)
        write_file(folder .. "/running-log", first)
        runlog.take_and_commit(folder, repo, "tester", 100000)
        -- the branch locked, as another git process would hold it
        local lock = repo .. "/.git/refs/heads/running-log/tester.lock"
        write_file(lock, "")
        local second = fake_lines(300, 100)
        write_file(folder .. "/running-log", second, "ab")
        local ok = pcall(runlog.take_and_commit, folder, repo, "tester", 100000)
        must(not ok, "the commit did not fail with the branch locked")
        must(read_file(folder .. "/running-log") == second, "the RAM log lost its lines when the commit failed")
        os.remove(lock)
        local third = fake_lines(200, 200)
        write_file(folder .. "/running-log", third, "ab")
        runlog.take_and_commit(folder, repo, "tester", 100000)
        local files = branch_files(repo)
        must(#files == 1 and files[1].bytes == first .. second .. third,
            "the branch does not hold every line once, in order")
    end
    referee()
    must_fail(referee, "empty-first", "the RAM log emptied before the commit")
end)

------------------------------------------------------------------------------
-- 4. Stated, not defaulted
------------------------------------------------------------------------------

check("referee 4: a config without git.log-file-size is an error naming it; a new home's config states it", function()
    local function referee()
        local dir = ROOT .. "/home-without"
        os.execute("rm -rf " .. q(dir))
        local h = rooms.open_home(dir)
        local text = read_file(dir .. "/config")
        must(text:find("\ngit.log-file-size = 100000000\n", 1, true), "a new home's config does not state the size")
        write_file(dir .. "/config", (text:gsub("git%.log%-file%-size = %d+\n", "")))
        local ok, why = pcall(runlog.settings, h)
        must(not ok, "a config without the setting was read as " .. tostring(why))
        must(tostring(why):find("git.log-file-size", 1, true), "the error does not name the setting: " .. tostring(why))
    end
    referee()
    must_fail(referee, "default-size", "a missing setting quietly 100,000,000")
end)

------------------------------------------------------------------------------
-- 3. Apart from the rooms, and the real gatherer
------------------------------------------------------------------------------

check("referee 3: after cycles, the rooms' branch has no log files and the log branch no room copies", function()
    local function referee()
        local repo, folder = new_repo()
        for i = 1, 3 do
            write_file(folder .. "/running-log", fake_lines(500, i * 100), "ab")
            runlog.take_and_commit(folder, repo, "tester", 1000)
        end
        local on_rooms = git.must(repo, { "ls-tree", "-r", "--name-only", "rooms" })
        local on_log = git.must(repo, { "ls-tree", "-r", "--name-only", runlog.branch("tester") })
        must(not on_rooms:find("running-log/", 1, true), "the rooms' branch holds log files")
        must(on_log ~= "" and not on_log:find("rooms/", 1, true), "the log branch holds room copies: " .. on_log)
        must(git.must(repo, { "symbolic-ref", "--short", "HEAD" }) == "rooms", "the checked-out branch changed")
    end
    referee()
    must_fail(referee, "on-rooms-tree", "the log branch built on the rooms' tree")
end)

-- {{{ the real gatherer
check("a real gatherer commits its running log every sync cycle and keeps RAM small", function()
    local START = {}
    local listing = io.popen("ls " .. DIR .. "/src/*/[0-9][0-9][0-9]-options.lua")
    for path in listing:lines() do
        for _, choice in ipairs(dofile(path)) do
            if choice.config_key ~= "" then START[choice.config_key] = choice.variants[1].name end
        end
    end
    listing:close()
    local dir = ROOT .. "/homes/A"
    os.execute("mkdir -p " .. q(ROOT .. "/homes"))
    local h = rooms.open_home(dir)
    for key, value in pairs(START) do rooms.set_config(h, key, value) end
    for key, value in pairs({ ["gatherer.ram-root"] = ROOT .. "/ram", ["gatherer.address"] = "127.0.0.2",
            ["gatherer.sync-interval"] = "1", ["git.home-name"] = "A" }) do
        rooms.set_config(h, key, value)
    end
    local tag = rooms.make_room(h, { label = "r", token = "running log test room", kind = "group", parent = "",
        members = {}, filed_under = "", mailbox_port = 7632 })
    local mailbox = rooms.read_entry(h, tag).mailbox
    local folder = ram.home_ram(ROOT .. "/ram", dir) .. "/" .. mailbox
    local repo = copies_m.repository(dir, mailbox)
    os.execute("mkdir -p " .. q(folder))
    local p = io.popen("luajit " .. q(DIR .. "/src/gatherer/163-gatherer.lua") .. " " .. q(DIR) .. " " .. q(dir)
        .. " " .. q(mailbox) .. " </dev/null >>" .. q(folder .. "/stderr") .. " 2>&1 & echo $!")
    local pid = tonumber(p:read("*l"))
    p:close()
    must(wait_until(function() return #branch_files(repo, "A") > 0 end, 6), "no running-log branch after 6 s: "
        .. (read_file(folder .. "/stderr") or ""))
    write_file(folder .. "/stop", "")
    must(wait_until(function() return read_file("/proc/" .. pid .. "/stat") == nil
        or read_file("/proc/" .. pid .. "/stat"):match("%) Z") end, 6), "the gatherer did not stop")
    local committed = branch_files(repo, "A")[1].bytes
    must(committed:find("started: pid " .. pid, 1, true), "the branch lacks the gatherer's first line")
    must(#(read_file(folder .. "/running-log") or "") < #committed, "the RAM log was not emptied as it was committed")
    must((read_file(folder .. "/state") or ""):find("problem.running-log-commit", 1, true) == nil,
        "the state names a failed running-log commit")
    os.execute("kill -9 " .. pid .. " 2>/dev/null")
end)
-- }}}

if not os.getenv("KEEP") then os.execute("rm -rf " .. q(ROOT)) else print("kept " .. ROOT) end
print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
