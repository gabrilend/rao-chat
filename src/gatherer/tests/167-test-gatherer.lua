-- 167-test-gatherer.lua — the referees of issue 211 (the mailbox gatherer
-- and its RAM folders), each run against real gatherer processes on
-- loopback and, where the issue names one, against a deliberately broken
-- version it must catch.
--
-- Run it under the loopback-only wrapper (a network namespace with only
-- `lo`, brought up): the homes listen on and send from 127.0.0.2, .3, .4
-- and nothing reaches a network.  Its homes and RAM folders are in a
-- folder of its own under /dev/shm (or /tmp when there is none), removed
-- at the end.
--
-- Run: luajit src/gatherer/tests/167-test-gatherer.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>"; exit status
-- 0 only when nothing failed.

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
local recipients = require("041-recipients")
local delivered = require("130-delivered")
local delivery = require("134-delivery")
local ram = require("161-ram-folders")

ffi.cdef [[ int getpid(void); ]]

local base = os.execute("test -d /dev/shm && test -w /dev/shm") == 0 and "/dev/shm" or "/tmp"
local ROOT = base .. "/rao-chat-gatherer-test-" .. ffi.C.getpid()
local TOKEN = "gatherer test room"
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
local function must_fail(referee, broken, words)
    local ok, caught = pcall(referee, broken)
    if ok then error("the referee passed a broken version: " .. words, 2) end
    print("     caught: " .. tostring(caught):gsub("^[^:]*:%d+: ", ""))
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

-- {{{ local function read_file
local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
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
-- name, address, port, overrides → a home {name, dir, disk, tag, mailbox,
-- address, port, folder}, with one room (TOKEN) on its own mailbox.
local function make_home(name, address, port, overrides)
    count = count + 1
    local dir = ROOT .. "/homes/" .. name .. "-" .. count
    os.execute("mkdir -p " .. q(ROOT .. "/homes"))
    local h = rooms.open_home(dir)
    for key, value in pairs(START) do rooms.set_config(h, key, value) end
    local config = {
        ["gatherer.ram-root"] = ROOT .. "/ram", ["gatherer.address"] = address,
        ["gatherer.sync-interval"] = "2", ["delivery.retry-floor"] = "1", ["delivery.retry-ceiling"] = "4",
        ["callback.answer-time"] = "2",
    }
    for key, value in pairs(overrides or {}) do config[key] = value end
    for key, value in pairs(config) do rooms.set_config(h, key, value) end
    local tag = rooms.make_room(h, { label = "the room", token = TOKEN, kind = "group", parent = "",
        members = {}, filed_under = "", mailbox_port = port })
    local mailbox = rooms.read_entry(h, tag).mailbox
    return { name = name, dir = dir, disk = h, tag = tag, mailbox = mailbox, address = address, port = port,
             pair = { address = address, port = port },
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
-- running: there, and not a zombie waiting to be reaped
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
-- home, env (a string of NAME=value words) → the gatherer's pid.
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

-- {{{ local function kill
local function kill(home)
    if alive(home.pid) then os.execute("kill -9 " .. home.pid) end
    wait_until(function() return not alive(home.pid) end, 3)
end
-- }}}

-- {{{ local function stop_all
local function stop_all()
    for _, pid in ipairs(all_pids) do if alive(pid) then os.execute("kill -9 " .. pid .. " 2>/dev/null") end end
    all_pids = {}
    -- and every process started for this run's homes (a starter's
    -- gatherers among them)
    os.execute("pkill -9 -f " .. q(ROOT) .. " 2>/dev/null")
    socket.sleep(0.1)
end
-- }}}

-- {{{ local function type_message
local function type_message(home, text, tag)
    ram.put(home.folder .. "/typed", ram.new_name(now()), "room = " .. (tag or home.tag) .. "\n\n" .. text .. "\n")
end
-- }}}

-- {{{ local function copies
-- How many records carry this text in a log file.
local function copies(path, text)
    local n = 0
    for line in (read_file(path) or ""):gmatch("[^\n]+") do
        if line:sub(-#text - 1) == "\t" .. text then n = n + 1 end
    end
    return n
end
-- }}}

local function ram_log(home, tag) return home.folder .. "/home/rooms/" .. (tag or home.tag) .. "/log" end
local function disk_log(home, tag) return home.dir .. "/rooms/" .. (tag or home.tag) .. "/log" end

-- {{{ local function all_sent
-- Whether a home's RAM log holds each of these texts as its own, and owes
-- the pair nothing of them.
local missing
local function all_sent(home, pair, texts)
    for _, text in ipairs(texts) do
        if copies(home.folder .. "/home/rooms/" .. home.tag .. "/log", text) ~= 1 then return false end
    end
    return missing(home, pair) == 0
end
-- }}}

-- {{{ local function missing
-- What a home's RAM copy still owes a pair.
function missing(home, pair)
    local ok, list = pcall(function()
        return delivered.missing_for(rooms.open_home(home.folder .. "/home"), home.tag, pair)
    end)
    return ok and #list or math.huge
end
-- }}}

os.execute("rm -rf " .. q(ROOT) .. " && mkdir -p " .. q(ROOT))

------------------------------------------------------------------------------
-- 1. Crash between filing and answering
------------------------------------------------------------------------------

-- {{{ local function referee_crash
local function referee_crash(mode, broken)
    stop_all()
    local over = { ["gatherer.acknowledge-after"] = mode }
    local a = make_home("A", "127.0.0.2", 7602, over)
    local b = make_home("B", "127.0.0.3", 7603, over)
    link({ a, b })
    start(a)
    local env = broken and "RAO_GATHERER_BROKEN=answer-first RAO_GATHERER_CRASH=after-answer:2"
        or "RAO_GATHERER_CRASH=before-answer:2"
    start(b, env)
    for i = 1, 5 do type_message(a, "message " .. i) end
    must(wait_until(function() return not alive(b.pid) end, 15), "B never reached its crash point")
    if not broken then
        -- a second crash, at the other point
        start(b, "RAO_GATHERER_CRASH=after-answer:2")
        wait_until(function() return not alive(b.pid) end, 15)
    end
    start(b)
    local texts = {}
    for i = 1, 5 do texts[i] = "message " .. i end
    must(wait_until(function() return all_sent(a, b.pair, texts) end, 30), "A still holds something for B after 30 s")
    socket.sleep(0.3)
    for i = 1, 5 do
        local n = copies(ram_log(b, nil), "message " .. i)
        must(n == 1, "message " .. i .. " is in B's log " .. n .. " times, though A was told it was delivered")
    end
    stop_all()
end
-- }}}

check("referee 1 (disk): crashes between filing and answering file every message once", function()
    referee_crash("disk")
end)
check("referee 1 (ram): crashes between filing and answering file every message once", function()
    referee_crash("ram")
    must_fail(function(broken) referee_crash("ram", broken) end, true, "a filer that answers before filing")
end)

------------------------------------------------------------------------------
-- 2. Power cut
------------------------------------------------------------------------------

local lost_under = {}
-- {{{ local function referee_power
local function referee_power(mode, broken)
    stop_all()
    local over = { ["gatherer.acknowledge-after"] = mode, ["gatherer.sync-interval"] = "3600" }
    local a = make_home("A", "127.0.0.2", 7602, over)
    local b = make_home("B", "127.0.0.3", 7603, over)
    link({ a, b })
    start(a)
    start(b, broken and "RAO_GATHERER_BROKEN=disk-answers-first" or nil)
    for i = 1, 10 do type_message(a, "kept " .. i) end
    local texts = {}
    for i = 1, 10 do texts[i] = "kept " .. i end
    must(wait_until(function() return all_sent(a, b.pair, texts) end, 20), "A never had its 10 answers")
    -- the power cut: the process and its RAM folder gone at once
    kill(b)
    if os.getenv("KEEP") then os.execute("cp -r " .. q(b.folder) .. " " .. q(ROOT .. "/kept-b")) end
    os.execute("rm -rf " .. q(b.folder))
    local lost = 0
    for i = 1, 10 do if copies(disk_log(b), "kept " .. i) == 0 then lost = lost + 1 end end
    lost_under[mode] = lost
    stop_all()
    if mode == "disk" then must(lost == 0, lost .. " of 10 acknowledged messages are not on disk") end
    return lost
end
-- }}}

check("referee 2 (disk): after a power cut every acknowledged message is on disk", function()
    referee_power("disk")
    must_fail(function(broken) referee_power("disk", broken) end, true, "disk that answers before forcing the write")
end)
check("referee 2 (ram): the cost is measured", function()
    local lost = referee_power("ram")
    print("     under ram, " .. lost .. " of 10 acknowledged messages were lost with the RAM folder")
end)

------------------------------------------------------------------------------
-- 3. Held connections are bounded
------------------------------------------------------------------------------

-- {{{ local function referee_bounded
local function referee_bounded(broken)
    stop_all()
    local a = make_home("A", "127.0.0.2", 7602)
    local b = make_home("B", "127.0.0.3", 7603, { ["gatherer.connection-limit"] = "64" })
    link({ a, b })
    start(a)
    start(b, broken and "RAO_GATHERER_BROKEN=no-limit" or nil)
    -- 500 connections, each announcing the most a frame may be and then
    -- trickling one byte a second
    local held = {}
    for i = 1, 500 do
        local s = socket.tcp4()
        s:bind("127.0.0.9", 0)
        s:settimeout(1)
        assert(s:connect(b.address, b.port))
        s:send("\0\0\16\0x")          -- announces 4096 bytes, sends one
        s:settimeout(0)
        held[i] = s
    end
    local last_trickle = now()
    local function trickle()
        if now() - last_trickle < 1 then return end
        last_trickle = now()
        for _, s in ipairs(held) do s:send("x") end
    end
    local most = 0
    wait_until(function()
        trickle()
        most = math.max(most, tonumber(ram.read_state(b.folder).connections or 0) or 0)
        return false
    end, 2.5)
    local t0 = now()
    type_message(a, "through the crowd")
    local got = wait_until(function()
        trickle()
        most = math.max(most, tonumber(ram.read_state(b.folder).connections or 0) or 0)
        return copies(ram_log(b), "through the crowd") == 1
    end, 2)
    local took = now() - t0
    local rss = tonumber((read_file("/proc/" .. b.pid .. "/status") or ""):match("VmRSS:%s*(%d+)") or 0)
    for _, s in ipairs(held) do s:close() end
    stop_all()
    print(string.format("     the genuine frame filed after %.2f s; at most %d connections held; B's memory %d kB",
        took, most, rss))
    must(got, "a genuine frame on connection 501 was not filed within 2 s")
    must(most <= 64, "B held " .. most .. " connections, over its limit of 64")
    must(rss < 65536, "B's memory is " .. rss .. " kB, over the stated bound of 64 MB")
end
-- }}}

check("referee 3: 500 trickling connections; B holds at most 64 and files a genuine frame within 2 s", function()
    referee_bounded()
    must_fail(referee_bounded, true, "no connection limit")
end)

------------------------------------------------------------------------------
-- 4. A dead peer delays nobody
------------------------------------------------------------------------------

-- {{{ local function referee_dead_peer
local function referee_dead_peer(broken)
    stop_all()
    local a = make_home("A", "127.0.0.2", 7602)
    local b = make_home("B", "127.0.0.3", 7603)
    local c = make_home("C", "127.0.0.4", 7604)
    -- the black hole first on A's list: it accepts (the system does) and
    -- never answers
    local hole = socket.tcp4()
    hole:setoption("reuseaddr", true)
    assert(hole:bind("127.0.0.9", 7609))
    assert(hole:listen(16))
    recipients.add_member(a.disk, a.tag, "127.0.0.9", 7609)
    link({ a, b })
    recipients.add_member(c.disk, c.tag, a.address, a.port)
    recipients.add_member(a.disk, a.tag, c.address, c.port)
    start(a, broken and "RAO_GATHERER_BROKEN=single-loop" or nil)
    start(b)
    start(c)
    socket.sleep(0.5)
    type_message(a, "past the hole")
    socket.sleep(0.2)
    local t0 = now()
    type_message(c, "to A while it waits")
    local reached_b = wait_until(function() return copies(ram_log(b), "past the hole") == 1 end, 1)
    local reached_a = wait_until(function() return copies(ram_log(a), "to A while it waits") == 1 end, 1.2)
    local took = now() - t0
    hole:close()
    stop_all()
    must(reached_b, "A's message did not reach B within 1 s while A waited on the black hole")
    must(reached_a, string.format("C's frame to A was not filed within 1 s (%.2f s)", took))
end
-- }}}

check("referee 4: a black-holed member delays neither another member nor an inbound frame", function()
    referee_dead_peer()
    must_fail(referee_dead_peer, true, "a sender inside the listener's loop")
end)

------------------------------------------------------------------------------
-- 5. A throwing record
------------------------------------------------------------------------------

-- {{{ local function cpu_seconds
local function cpu_seconds(pid)
    local stat = read_file("/proc/" .. pid .. "/stat") or ""
    local after = stat:match("%) (.*)$") or ""
    local fields = {}
    for word in after:gmatch("%S+") do fields[#fields + 1] = word end
    return ((tonumber(fields[12]) or 0) + (tonumber(fields[13]) or 0)) / 100
end
-- }}}

-- {{{ local function referee_throwing
local function referee_throwing(broken)
    stop_all()
    local a = make_home("A", "127.0.0.2", 7602)
    local b = make_home("B", "127.0.0.3", 7603)
    -- a second room, in the same mailbox on each side
    local parent = require("007-tokens").token_fingerprint(TOKEN)
    local second = {}
    for _, home in ipairs({ a, b }) do
        second[home] = rooms.make_room(home.disk, { label = "the other room", token = "the throwing room",
            kind = "group", parent = parent, members = {}, filed_under = "", mailbox_port = "" })
    end
    link({ a, b })
    recipients.add_member(a.disk, second[a], b.address, b.port)
    recipients.add_member(b.disk, second[b], a.address, a.port)
    start(a)
    start(b, broken and "RAO_GATHERER_BROKEN=retry-at-once" or nil)
    -- B's RAM copy of the second room's log made a folder: filing throws
    local bad = ram_log(b, second[b])
    os.execute("rm -f " .. q(bad) .. " && mkdir -p " .. q(bad))
    type_message(a, "into the throwing room", second[a])
    socket.sleep(1)
    local cpu0 = cpu_seconds(b.pid)
    local t0 = now()
    type_message(a, "into the good room")
    local good = wait_until(function() return copies(ram_log(b), "into the good room") == 1 end, 3)
    socket.sleep(math.max(0, 5 - (now() - t0)))
    local cpu = cpu_seconds(b.pid) - cpu0
    local lines = 0
    for line in (read_file(b.folder .. "/running-log") or ""):gmatch("[^\n]+") do
        if line:find("problem filing", 1, true) or line:find("problem room-" .. second[b]:sub(1, 8), 1, true) then
            lines = lines + 1
        end
    end
    stop_all()
    print(string.format("     over 5 s: %d running-log line(s) about the throwing room; %.2f s of CPU", lines, cpu))
    must(good, "the other room stopped receiving")
    must(lines >= 1 and lines <= 4, lines .. " running-log lines for one repeated problem in 5 s (sync interval 2 s)")
    must(cpu < 1.0, string.format("B used %.2f s of CPU in 5 s: the clock is not stepping", cpu))
end
-- }}}

check("referee 5: a room whose filing throws: others still receive, the log and the wake-ups stay bounded", function()
    referee_throwing()
    must_fail(referee_throwing, true, "a guard that skips the clock step")
end)

------------------------------------------------------------------------------
-- 6. Half-written files are never read; two takers never take one file
------------------------------------------------------------------------------

-- {{{ local function referee_half_written
local function referee_half_written(broken)
    local queue = ROOT .. "/half/arrived"
    os.execute("rm -rf " .. q(ROOT .. "/half") .. " && mkdir -p " .. q(queue .. "/working"))
    -- a writer that writes byte by byte, 20 files of 40 bytes
    local script = ROOT .. "/half/slow-writer.sh"
    local f = assert(io.open(script, "w"))
    f:write([[
q="$1"; mode="$2"
for n in $(seq 10 29); do
  if [ "$mode" = broken ]; then target="$q/file-$n"; else target="$q/.file-$n.tmp"; fi
  : > "$target"
  for i in $(seq 1 40); do printf x >> "$target"; sleep 0.002; done
  if [ "$mode" != broken ]; then mv "$target" "$q/file-$n"; fi
done
]])
    f:close()
    local done_flag = ROOT .. "/half/done"
    os.execute("(sh " .. q(script) .. " " .. q(queue) .. " " .. (broken and "broken" or "fine") .. "; touch "
        .. q(done_flag) .. ") &")
    local short, taken = 0, 0
    while true do
        local finished = read_file(done_flag) ~= nil
        for _, name in ipairs(ram.waiting(queue)) do
            local bytes = ram.take(queue, name)
            if bytes then
                taken = taken + 1
                if #bytes < 40 then short = short + 1 end
            end
        end
        if finished and #ram.waiting(queue) == 0 then break end
        socket.sleep(0.005)
    end
    must(short == 0, short .. " file(s) were read before they were whole")
    must(taken == 20, "took " .. taken .. " of 20 files")
end
-- }}}

-- {{{ local function referee_two_takers
local function referee_two_takers(broken)
    local queue = ROOT .. "/two/arrived"
    os.execute("rm -rf " .. q(ROOT .. "/two") .. " && mkdir -p " .. q(queue .. "/working"))
    for i = 1, 300 do ram.put(queue, string.format("f%04d", i), tostring(i)) end
    local taker = ROOT .. "/two/taker.lua"
    local f = assert(io.open(taker, "w"))
    f:write([[
dofile(arg[1] .. "/src/room-folders/001-load-path.lua")(arg[1])
local ram = require("161-ram-folders")
local queue, out, broken = arg[2], assert(io.open(arg[3], "w")), arg[4] == "broken"
while io.open(arg[5]) == nil do end
for _, name in ipairs(ram.waiting(queue)) do
    if broken then
        -- taking by reading: read it, then remove it
        local h = io.open(queue .. "/" .. name, "rb")
        if h then out:write(h:read("*a"), "\n"); h:close(); os.remove(queue .. "/" .. name) end
    else
        local bytes = ram.take(queue, name)
        if bytes then out:write(bytes, "\n") end
    end
end
out:close()
]])
    f:close()
    local go = ROOT .. "/two/go"
    for i = 1, 2 do
        os.execute("luajit " .. q(taker) .. " " .. q(DIR) .. " " .. q(queue) .. " " .. q(ROOT .. "/two/out" .. i) .. " "
            .. (broken and "broken" or "fine") .. " " .. q(go) .. " & echo $! >" .. q(ROOT .. "/two/pid" .. i))
    end
    socket.sleep(0.3)
    io.open(go, "w"):close()
    wait_until(function()
        return read_file(ROOT .. "/two/pid1") and not alive(read_file(ROOT .. "/two/pid1"):match("%d+"))
            and not alive(read_file(ROOT .. "/two/pid2"):match("%d+"))
    end, 20)
    local seen, twice, total = {}, 0, 0
    for i = 1, 2 do
        for line in (read_file(ROOT .. "/two/out" .. i) or ""):gmatch("[^\n]+") do
            total = total + 1
            if seen[line] then twice = twice + 1 end
            seen[line] = true
        end
    end
    must(twice == 0, twice .. " file(s) were taken by both takers")
    must(total == 300, total .. " takings for 300 files")
end
-- }}}

check("referee 6: a file written slowly is never read before its rename", function()
    referee_half_written()
    must_fail(referee_half_written, true, "writing in place")
end)
check("referee 6: two takers never take one file", function()
    referee_two_takers()
    must_fail(referee_two_takers, true, "taking by reading")
end)

------------------------------------------------------------------------------
-- 7. Port first
------------------------------------------------------------------------------

-- {{{ local function referee_port_first
local function referee_port_first(broken)
    stop_all()
    local a = make_home("A", "127.0.0.2", 7602)
    local b = make_home("B", "127.0.0.3", 7603)
    -- B owes A a message, so a B that sent before claiming would connect
    recipients.add_member(b.disk, b.tag, a.address, a.port)
    delivery.write(b.disk, b.tag, { kind = "message", text = "owed to A" }, math.floor(now()))
    local other = socket.tcp4()
    other:setoption("reuseaddr", true)
    assert(other:bind(b.address, b.port))
    assert(other:listen(4))
    local watch = socket.tcp4()
    watch:setoption("reuseaddr", true)
    assert(watch:bind(a.address, a.port))
    assert(watch:listen(4))
    watch:settimeout(0)
    os.execute("mkdir -p " .. q(b.folder))
    local pipe = io.popen((broken and "RAO_GATHERER_BROKEN=other-port " or "") .. "luajit "
        .. q(DIR .. "/src/gatherer/163-gatherer.lua") .. " " .. q(DIR) .. " " .. q(b.dir) .. " " .. q(b.mailbox)
        .. " </dev/null >>" .. q(b.folder .. "/stderr") .. " 2>&1 & echo $!")
    b.pid = tonumber(pipe:read("*l"))
    pipe:close()
    all_pids[#all_pids + 1] = b.pid
    local t0 = now()
    local exited = wait_until(function() return not alive(b.pid) end, 1)
    local took = now() - t0
    socket.sleep(0.5)
    local connected = watch:accept()
    local state = ram.read_state(b.folder)
    local logged = read_file(b.folder .. "/running-log") or ""
    other:close()
    watch:close()
    stop_all()
    must(exited, "the gatherer was still running 1 s after its port was found held")
    print(string.format("     exited after %.2f s: %s", took, tostring(state["problem.port"])))
    must((state["problem.port"] or ""):find("port 7603", 1, true) and state["problem.port"]:find("mailboxes line", 1, true),
        "state does not name the port and its mailboxes line")
    must(logged:find("port 7603 cannot be claimed", 1, true), "the running log does not say so")
    must(connected == nil, "the gatherer connected out before stopping")
end
-- }}}

check("referee 7: a held port: the gatherer names it and its mailboxes line, sends nothing, exits within 1 s",
    function()
        referee_port_first()
        must_fail(referee_port_first, true, "choosing another port")
    end)

------------------------------------------------------------------------------
-- 8. Homes apart
------------------------------------------------------------------------------

-- {{{ local function referee_apart
local function referee_apart(broken)
    stop_all()
    local homes = { make_home("A", "127.0.0.2", 7602), make_home("B", "127.0.0.3", 7603),
                    make_home("C", "127.0.0.4", 7604) }
    link(homes)
    local starters = {}
    for _, home in ipairs(homes) do
        local pipe = io.popen((broken and "RAO_GATHERER_BROKEN=fixed-folder " or "") .. "luajit "
            .. q(DIR .. "/src/gatherer/164-home-starter.lua") .. " " .. q(DIR) .. " " .. q(home.dir)
            .. " </dev/null >/dev/null 2>&1 & echo $!")
        starters[#starters + 1] = tonumber(pipe:read("*l"))
        pipe:close()
        all_pids[#all_pids + 1] = starters[#starters]
    end
    local home_rams, mailbox_folders = {}, {}
    for i, home in ipairs(homes) do
        home_rams[i] = broken and (ROOT .. "/ram/shared") or ram.home_ram(ROOT .. "/ram", home.dir)
        mailbox_folders[i] = home_rams[i] .. "/" .. home.mailbox
    end
    -- garbage to each, so each has a failed-decryption file
    for _, home in ipairs(homes) do
        wait_until(function() return ram.read_state(mailbox_folders[_]).pid ~= nil end, 3)
        local s = socket.tcp4()
        s:bind("127.0.0.9", 0)
        s:settimeout(1)
        if s:connect(home.address, home.port) then s:send("\0\0\0\40" .. string.rep("\170", 40)) end
        socket.sleep(0.2)
        s:close()
    end
    socket.sleep(0.5)
    local seen = {}
    local function apart(kind, value)
        must(value ~= nil, "no " .. kind)
        must(not seen[kind .. value], "two homes share a " .. kind .. ": " .. value)
        seen[kind .. value] = true
    end
    for i in ipairs(homes) do
        local state = ram.read_state(mailbox_folders[i])
        apart("home RAM folder", home_rams[i])
        apart("running log", read_file(home_rams[i] .. "/running-log") and (home_rams[i] .. "/running-log"))
        apart("gatherer pid", state.pid)
        apart("failed-decryption file", read_file(mailbox_folders[i] .. "/failed-decryption")
            and (mailbox_folders[i] .. "/failed-decryption"))
    end
    for _, home in ipairs(homes) do
        os.execute("touch " .. q((broken and (ROOT .. "/ram/shared") or ram.home_ram(ROOT .. "/ram", home.dir)) .. "/stop"))
    end
    wait_until(function()
        for _, pid in ipairs(starters) do if alive(pid) then return false end end
        return true
    end, 12)
    stop_all()
end
-- }}}

check("referee 8: three homes on one machine share no RAM folder, log, failed-decryption file or pid", function()
    referee_apart()
    must_fail(referee_apart, true, "one fixed RAM folder for every home")
end)

------------------------------------------------------------------------------
-- 9. Phase 1 runs on RAM; a sync makes disk equal RAM
------------------------------------------------------------------------------

-- {{{ local function referee_phase1
local function referee_phase1(broken)
    stop_all()
    local a = make_home("A", "127.0.0.2", 7602)
    local b = make_home("B", "127.0.0.3", 7603)
    link({ a, b })
    start(a)
    start(b, broken and "RAO_GATHERER_BROKEN=skip-entry" or nil)
    type_message(a, "for the sync")
    must(wait_until(function() return copies(ram_log(b), "for the sync") == 1 end, 5), "never arrived")
    -- phase 1's modules on the RAM home: a token changed by hand rewrites `entry`
    local ram_home = rooms.open_home(b.folder .. "/home")
    rooms.change_token(ram_home, b.tag, "a new token, in RAM")
    must(#rooms.list_rooms(ram_home) == 1 and #recipients.members(ram_home, b.tag) == 1,
        "phase 1's modules do not read the RAM home")
    local last = ram.read_state(b.folder)["last-sync"]
    must(wait_until(function() return ram.read_state(b.folder)["last-sync"] ~= last end, 5), "no sync within 5 s")
    socket.sleep(0.3)
    stop_all()
    local listing = io.popen("cd " .. q(b.folder .. "/home/rooms/" .. b.tag) .. " && find . -type f | sort")
    local differ = {}
    for relative in listing:lines() do
        if read_file(b.folder .. "/home/rooms/" .. b.tag .. "/" .. relative)
            ~= read_file(b.dir .. "/rooms/" .. b.tag .. "/" .. relative) then
            differ[#differ + 1] = relative:sub(3)
        end
    end
    listing:close()
    must(#differ == 0, "after a sync the disk home differs from RAM in: " .. table.concat(differ, ", "))
end
-- }}}

check("referee 9: phase 1's modules run on the RAM home; after a sync disk equals RAM file for file", function()
    referee_phase1()
    must_fail(referee_phase1, true, "a sync that misses a rewritten entry")
end)

------------------------------------------------------------------------------
-- The starter and typed/, due/
------------------------------------------------------------------------------

check("the starter restarts a gatherer that dies, and says so; due/ holds the pile for a member down", function()
    stop_all()
    local a = make_home("A", "127.0.0.2", 7602)
    local b = make_home("B", "127.0.0.3", 7603)
    link({ a, b })
    local pipe = io.popen("luajit " .. q(DIR .. "/src/gatherer/164-home-starter.lua") .. " " .. q(DIR) .. " "
        .. q(a.dir) .. " </dev/null >/dev/null 2>&1 & echo $!")
    local starter = tonumber(pipe:read("*l"))
    pipe:close()
    all_pids[#all_pids + 1] = starter
    must(wait_until(function() return ram.read_state(a.folder).pid ~= nil end, 3), "the starter started no gatherer")
    local first = ram.read_state(a.folder).pid
    os.execute("kill -9 " .. first)
    must(wait_until(function()
        local pid = ram.read_state(a.folder).pid
        return pid ~= nil and pid ~= first and alive(tonumber(pid))
    end, 5), "the gatherer was not started again")
    local home_log = read_file(ram.home_ram(ROOT .. "/ram", a.dir) .. "/running-log") or ""
    must(home_log:find("is gone after", 1, true), "the starter's running log does not say the gatherer died")
    -- B is down: A's pile, in due/ and in state
    for i = 1, 3 do type_message(a, "waiting " .. i) end
    must(wait_until(function() return tonumber(ram.read_state(a.folder)["pile.due"] or 0) == 1 end, 5),
        "due/ does not hold B's pair")
    local due = read_file(a.folder .. "/due/" .. b.address .. "-" .. b.port .. "-" .. a.tag:sub(1, 8)) or ""
    must(due:find("missing = 3", 1, true), "due/ does not say 3 are missing: " .. due)
    start(b)
    must(wait_until(function() return copies(ram_log(b), "waiting 3") == 1 end, 10), "B never got the pile")
    must(wait_until(function() return tonumber(ram.read_state(a.folder)["pile.due"] or 1) == 0 end, 3),
        "due/ still holds B's pair")
    os.execute("touch " .. q(ram.home_ram(ROOT .. "/ram", a.dir) .. "/stop"))
    must(wait_until(function() return not alive(starter) end, 12), "the starter did not stop when asked")
    stop_all()
end)

stop_all()
if not os.getenv("KEEP") then os.execute("rm -rf " .. q(ROOT)) else print("kept " .. ROOT) end
print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
