-- 180-test-sharing.lua — the referees of issue 215b (sharing through a
-- shared upstream): real gatherers on loopback with local bare
-- repositories in the test folder as their upstreams (1–4, 6), and the
-- sharing module on homes on disk (5).  Never a real remote: every
-- upstream is a bare repository under this test's own folder, or (6) a
-- listening socket on 127.0.0.9 that never answers.  Each referee runs
-- against the broken version it must catch.
--
-- Run it under the loopback-only wrapper.  Its folder is under /dev/shm
-- (or /tmp), removed at the end.
--
-- Run: luajit src/git-copies/tests/180-test-sharing.lua [PROJECT_DIR]
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
local sharing = require("179-sharing")

ffi.cdef [[ int getpid(void); ]]

local base = os.execute("test -d /dev/shm && test -w /dev/shm") == 0 and "/dev/shm" or "/tmp"
local ROOT = base .. "/rao-chat-sharing-test-" .. ffi.C.getpid()
local TOKEN = "sharing test room"
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

os.execute("rm -rf " .. q(ROOT) .. " && mkdir -p " .. q(ROOT))

local bares = 0
-- {{{ local function bare / with_upstream
-- A bare repository in the test folder: the only kind of upstream used.
local function bare()
    bares = bares + 1
    local path = ROOT .. "/upstreams/up-" .. bares .. ".git"
    os.execute("mkdir -p " .. q(ROOT .. "/upstreams"))
    git.must(nil, { "init", "-q", "--bare", "-b", "rooms", path })
    return path
end
-- home, remote name, url → the home's repository with that remote.
local function with_remote(home, remote, url)
    git.ensure(home.repo)
    git.must(home.repo, { "remote", "add", remote, url })
end
-- }}}

-- {{{ local function state_of / share_count
local function state_of(home) return ram.read_state(home.folder) end
local function shares(home)
    local s = state_of(home)
    return tonumber(s["share.pulls"] or 0), tonumber(s["share.pushes"] or 0), s["share.last"] or ""
end
-- }}}

-- {{{ local function upstream_files
-- bare → the files on its `rooms` branch.
local function upstream_files(path, branch)
    local ok, out = git.run(path, { "ls-tree", "-r", "--name-only", branch or "rooms" })
    local list = {}
    for line in (ok and out or ""):gmatch("[^\n]+") do list[#list + 1] = line end
    return list
end
-- }}}

-- {{{ local function recheck
-- What the starter does after each public-address check, and a wait for
-- the moment it starts to be over.
local function recheck(home)
    local _, pushes_before = shares(home)
    local pulls_before = shares(home)
    io.open(home.folder .. "/recheck", "wb"):close()
    return wait_until(function()
        local pulls, _, last = shares(home)
        return pulls > pulls_before and last:match("^recheck")
    end, 15)
end
-- }}}

local SHARED = { ["git.share-deadline"] = "10", ["git.upstream-rooms"] = "only-fully-shared",
                 ["git.push-running-log"] = "no" }

------------------------------------------------------------------------------
-- 1. The three moments
------------------------------------------------------------------------------

-- {{{ local function referee_moments(broken)
local function referee_moments(broken)
    stop_all()
    local up = bare()
    local a = make_home("A", "127.0.0.2", 7642, SHARED)
    with_remote(a, "upstream", up)
    -- a message already in the room, so the start-up moment has a copy to push
    message_log.append(a.disk, a.tag, { id = message_log.new_message_id(), from = "me", written = 3000,
        arrived = 3000, text = "written before the start" })
    start(a, broken and ("RAO_SHARE_BROKEN=" .. broken) or nil)
    must(wait_until(function() local p, s, last = shares(a) return p == 1 and s == 1 and last:match("^start") end, 15),
        "no pull and push at start-up: " .. table.concat({ shares(a) }, " "))
    type_message(a, "shared at the recheck")
    must(wait_until(function() return size(copies_in(a)) == 2 end, 5), "no copy")
    recheck(a)
    local pulls, pushes, last = shares(a)
    must(pulls == 2 and pushes == 2 and last:match("^recheck"), "after a recheck: " .. pulls .. " pulls, "
        .. pushes .. " pushes, last " .. last .. " (not 2, 2, recheck)")
    must(#upstream_files(up) == 2, "the upstream does not hold the copy after the recheck")
    type_message(a, "shared at the stop")
    must(wait_until(function() return size(copies_in(a)) == 3 end, 5), "no third copy")
    io.open(a.folder .. "/stop", "wb"):close()
    must(wait_until(function() return not alive(a.pid) end, 20), "A did not stop")
    pulls, pushes, last = shares(a)
    must(pulls == 3 and pushes == 3 and last:match("^stop"), "after the stop: " .. pulls .. " pulls, " .. pushes
        .. " pushes, last " .. last .. " (not 3, 3, stop)")
    must(#upstream_files(up) == 3, "the upstream does not hold the copy written before the stop")
    must(#upstream_files(up, "running-log/" .. a.name .. "-" .. a.dir:match("%-(%d+)$")) == 0,
        "the running log was pushed with git.push-running-log = no")
    stop_all()
end
-- }}}

check("referee 1: pull then push at start-up, at a recheck and at the stop", function()
    referee_moments()
    must_fail(function() referee_moments("start-only") end, "a push only at start-up")
end)

check("SIGTERM stops a gatherer through its last sync and the shut-down moment", function()
    stop_all()
    local up = bare()
    local a = make_home("A", "127.0.0.2", 7642, SHARED)
    with_remote(a, "upstream", up)
    message_log.append(a.disk, a.tag, { id = message_log.new_message_id(), from = "me", written = 3000,
        arrived = 3000, text = "written before the start" })
    start(a)
    must(wait_until(function() local _, s = shares(a) return s == 1 end, 15), "no push at start-up")
    type_message(a, "written just before SIGTERM")
    must(wait_until(function() return size(copies_in(a)) == 2 end, 5), "no copy")
    os.execute("kill -TERM " .. a.pid)
    must(wait_until(function() return not alive(a.pid) end, 20), "A did not stop at SIGTERM")
    local _, pushes, last = shares(a)
    must(state_of(a).stopped == "sigterm" and last:match("^stop") and pushes == 2, "stopped = "
        .. tostring(state_of(a).stopped) .. ", last share " .. last .. ", " .. pushes .. " pushes")
    must(#upstream_files(up) == 2, "the copy written before SIGTERM did not reach the upstream")
    stop_all()
end)

------------------------------------------------------------------------------
-- 2 and 3. Same message merges clean; a conflict is reported, not resolved
------------------------------------------------------------------------------

-- {{{ local function two_sharing(broken)
local function two_sharing(broken)
    stop_all()
    local up = bare()
    local a = make_home("A", "127.0.0.2", 7642, SHARED)
    local b = make_home("B", "127.0.0.3", 7643, SHARED)
    link({ a, b })
    with_remote(a, "upstream", up)
    with_remote(b, "upstream", up)
    -- A and B list each other as sharing the upstream: the room has both
    git.must(a.repo, { "config", "--add", "rao.upstream-pair", b.address .. " " .. b.port })
    git.must(b.repo, { "config", "--add", "rao.upstream-pair", a.address .. " " .. a.port })
    local env = broken and ("RAO_SHARE_BROKEN=" .. broken) or nil
    start(a, env)
    start(b, env)
    must(wait_until(function() return shares(a) >= 1 and shares(b) >= 1 end, 15),
        "the start-up moments did not run")
    type_message(a, "one message, two homes")
    must(wait_until(function()
        return size(copies_in(a)) == 1 and size(copies_in(b)) == 1 and commits(a) >= 1 and commits(b) >= 1
    end, 15), "the message was not copied and committed on both homes")
    must(recheck(a), "A's recheck did not run")
    must(recheck(b), "B's recheck did not run")
    return a, b, up
end
-- }}}

check("referee 2: two homes file one message; both push and pull: no conflict, one file", function()
    local a, b, up = two_sharing()
    must(recheck(a), "A's second recheck did not run")
    for _, h in ipairs({ a, b }) do
        must(tonumber(state_of(h)["share.conflicts"] or -1) == 0, h.name .. " reports a conflict")
    end
    local files = upstream_files(up)
    must(#files == 1, "the upstream holds " .. #files .. " files for one message")
    must(git.must(b.repo, { "rev-parse", "HEAD:" .. files[1] }) == git.must(a.repo, { "rev-parse", "HEAD:" .. files[1] }),
        "the two homes' copies differ")
    stop_all()
end)

-- {{{ local function referee_conflict(broken)
local function referee_conflict(broken)
    local a, b = two_sharing(broken)
    local path = next(copies_in(a))
    local function edit(h, words)
        local text = read_file(h.repo .. "/" .. path)
        local f = io.open(h.repo .. "/" .. path, "wb")
        f:write(text .. "\n" .. words)
        f:close()
        local before = commits(h)
        must(wait_until(function() return commits(h) > before end, 8), h.name .. "'s edit was not committed")
    end
    edit(a, "A's hand edit")
    must(recheck(a), "A's recheck did not run")
    edit(b, "B's different hand edit")
    must(recheck(b), "B's recheck did not run")
    must(tonumber(state_of(b)["share.conflicts"] or 0) == 1, "B does not report the conflict (share.conflicts = "
        .. tostring(state_of(b)["share.conflicts"]) .. ")")
    local named = false
    for key, value in pairs(state_of(b)) do
        if key:match("^problem%.share%-conflict") and value:find(path, 1, true) then named = true end
    end
    must(named, "no problem line in B's state names the copy")
    must((read_file(b.repo .. "/" .. path) or ""):find("B's different hand edit", 1, true),
        "B's own edit is gone from its working tree")
    must(git.must(b.repo, { "show", "refs/remotes/upstream/rooms:" .. path }):find("A's hand edit", 1, true),
        "A's edit is not in B's history")
    must(not (read_file(b.repo .. "/" .. path) or ""):find("A's hand edit", 1, true), "B's copy took A's edit")
    stop_all()
end
-- }}}

check("referee 3: two different edits of one copy: the conflict is reported and both edits kept", function()
    referee_conflict()
    must_fail(function() referee_conflict("auto-resolve") end, "a conflict resolved to one side")
end)

------------------------------------------------------------------------------
-- 4. Pulled code is inert
------------------------------------------------------------------------------

-- {{{ local function referee_inert(broken)
local function referee_inert(broken)
    stop_all()
    local up = bare()
    local marker = ROOT .. "/marker-" .. bares
    -- another home's program, pushed to the upstream as code/other
    local other = ROOT .. "/other-" .. bares
    git.must(nil, { "init", "-q", "-b", "code/other", other })
    local f = io.open(other .. "/run-me.sh", "wb")
    f:write("#!/bin/sh\ntouch " .. q(marker) .. "\n")
    f:close()
    os.execute("chmod +x " .. q(other .. "/run-me.sh"))
    local hooks = other .. "/.githooks"
    os.execute("mkdir -p " .. q(hooks) .. " && cp " .. q(other .. "/run-me.sh") .. " " .. q(hooks .. "/post-merge"))
    git.must(other, { "add", "-A" })
    local args = git.identity("other")
    for _, w in ipairs({ "commit", "-q", "-m", "the other home's program" }) do args[#args + 1] = w end
    git.must(other, args)
    git.must(other, { "push", "-q", up, "code/other:refs/heads/code/other" })
    local a = make_home("A", "127.0.0.2", 7642, SHARED)
    with_remote(a, "upstream", up)
    start(a, broken and ("RAO_SHARE_BROKEN=" .. broken) or nil)
    must(wait_until(function() local p = shares(a) return p >= 1 end, 15), "no pull at start-up")
    type_message(a, "a message")
    recheck(a)
    recheck(a)
    must(git.ref(a.repo, "refs/remotes/upstream/code/other"), "the other home's code is not downloadable")
    must(git.must(a.repo, { "symbolic-ref", "--short", "HEAD" }) == "rooms", "the checked-out branch changed")
    local tracked = git.must(a.repo, { "ls-files" })
    for path in tracked:gmatch("[^\n]+") do
        must(path:match("^rooms/"), "the working tree took a file from another branch: " .. path)
    end
    must(read_file(marker) == nil, "the other home's program ran")
    stop_all()
end
-- }}}

check("referee 4: another home's code/ branch arrives, readable, and never runs or is checked out", function()
    referee_inert()
    must_fail(function() referee_inert("merge-all") end, "every fetched branch merged")
end)

------------------------------------------------------------------------------
-- 5. Child rooms stay private, under each switch value
------------------------------------------------------------------------------

-- {{{ local function family
-- A home on disk with a top room (members B and C) and a child room
-- (member B only), one message in each, copied and committed.
local function family(name)
    count = count + 1
    local dir = ROOT .. "/homes/" .. name .. "-" .. count
    os.execute("mkdir -p " .. q(ROOT .. "/homes"))
    local h = rooms.open_home(dir)
    for key, value in pairs(START) do rooms.set_config(h, key, value) end
    local top_token, child_token = "the top room " .. count, "the child room " .. count
    local top = rooms.make_room(h, { label = "top", token = top_token, kind = "group", parent = "",
        members = {}, filed_under = "", mailbox_port = 7660 + count })
    local child = rooms.make_room(h, { label = "child", token = child_token, kind = "group",
        parent = rooms.token_fingerprint(top_token), members = {}, filed_under = "", mailbox_port = "" })
    recipients.add_member(h, top, "198.51.100.2", 7000)
    recipients.add_member(h, top, "198.51.100.3", 7000)
    recipients.add_member(h, child, "198.51.100.2", 7000)
    for _, tag in ipairs({ top, child }) do
        message_log.append(h, tag, { id = message_log.new_message_id(), from = "me", written = 2000, arrived = 2000,
            text = "in " .. rooms.read_entry(h, tag).label })
    end
    local mailbox = rooms.read_entry(h, top).mailbox
    must(rooms.read_entry(h, child).mailbox == mailbox, "the child room is not in the top room's mailbox")
    local c = copies_m.open(h, dir, mailbox, name)
    local tags = rooms.list_rooms_by_mailbox(h, mailbox)
    c:sync(tags)
    return { home = h, copies = c, tags = tags, top = rooms.token_fingerprint(top_token),
             child = rooms.token_fingerprint(child_token), name = name }
end
-- }}}

-- {{{ local function share_once
local function share_once(f, mode)
    local s = sharing.new({ home = f.home, repo = f.copies.repo, tags = f.tags, name = f.name,
        settings = { mode = mode, push_log = false, deadline = 10 },
        wait = function(condition, limit) wait_until(condition, limit - now()) end, now = now,
        commit = function() f.copies:sync(f.tags) end })
    return sharing.moment(s, "recheck")
end
-- }}}

-- {{{ local function what_c_finds
-- C, a member of the top room only, fetches everything from these
-- upstreams → every path and ref name it can see, as one text.
local function what_c_finds(upstreams)
    local seen = {}
    for _, up in ipairs(upstreams) do
        seen[#seen + 1] = git.must(up, { "for-each-ref", "--format=%(refname)" })
        local ok, all = git.run(up, { "log", "--all", "--name-only", "--format=" })
        if ok then seen[#seen + 1] = all end
    end
    return table.concat(seen, "\n")
end
-- }}}

-- {{{ local function referee_private(mode)
local function referee_private(mode)
    local f = family("P")
    local upstream, top_up, child_up = bare(), bare(), bare()
    git.must(f.copies.repo, { "remote", "add", "upstream", upstream })
    local readable
    if mode == "only-fully-shared" then
        -- B and C share the upstream
        git.must(f.copies.repo, { "config", "--add", "rao.upstream-pair", "198.51.100.2 7000" })
        git.must(f.copies.repo, { "config", "--add", "rao.upstream-pair", "198.51.100.3 7000" })
        readable = { upstream }
    else
        git.must(f.copies.repo, { "remote", "add", "room-" .. f.top, top_up })
        git.must(f.copies.repo, { "remote", "add", "room-" .. f.child, child_up })
        readable = { upstream, top_up }          -- C cannot read the child room's own upstream
    end
    share_once(f, mode)
    local found = what_c_finds(readable)
    must(found:find(f.top, 1, true), "the top room's copies were not shared at all")
    must(not found:find(f.child, 1, true), "C, outside the child room, can fetch its copies (" .. mode .. ")")
end
-- }}}

check("referee 5: a top-room member fetching the upstream cannot find a child room's copies, under each switch", function()
    for _, mode in ipairs({ "only-fully-shared", "repository-per-room" }) do
        referee_private(mode)
    end
    must_fail(function()
        sharing.broken = "members-listed"
        local ok, why = pcall(referee_private, "only-fully-shared")
        sharing.broken = nil
        if not ok then error(why, 0) end
    end, "the issue's wording: every member listed as sharing")
    must_fail(function()
        sharing.broken = "branch-per-room"
        local ok, why = pcall(referee_private, "repository-per-room")
        sharing.broken = nil
        if not ok then error(why, 0) end
    end, "one branch per room in one repository")
end)

------------------------------------------------------------------------------
-- 6. No network, no stall
------------------------------------------------------------------------------

-- {{{ local function referee_stall(broken)
local function referee_stall(broken)
    stop_all()
    -- a black hole: connections are taken and nothing is ever said
    local hole = socket.tcp4()
    hole:setoption("reuseaddr", true)
    assert(hole:bind("127.0.0.9", 7699))
    assert(hole:listen(16))
    local over = {}
    for k, v in pairs(SHARED) do over[k] = v end
    over["git.share-deadline"] = "3"
    local a = make_home("A", "127.0.0.2", 7642, over)
    local b = make_home("B", "127.0.0.3", 7643)
    link({ a, b })
    with_remote(a, "upstream", "git://127.0.0.9:7699/nothing.git")
    start(b)
    start(a, broken and ("RAO_SHARE_BROKEN=" .. broken) or nil)
    socket.sleep(0.5)                  -- A's start-up pull is now waiting on the black hole
    local typed = now()
    type_message(a, "while the upstream says nothing")
    local got = wait_until(function()
        return (read_file(b.folder .. "/home/rooms/" .. b.tag .. "/log") or ""):find("while the upstream says nothing", 1, true)
    end, 2.5)
    local took = now() - typed
    local reported = wait_until(function()
        return (state_of(a)["problem.share-upstream"] or ""):find("no answer within git.share-deadline", 1, true)
    end, 8)
    hole:close()
    stop_all()
    must(got, string.format("B did not receive A's message within 2.5 s while A's pull hung (%.1f s)", took))
    must(reported, "A did not report the pull as failed within its deadline")
    print(string.format("     delivered in %.2f s while the pull hung; reported failed after the 3 s deadline", took))
end
-- }}}

check("referee 6: a black-holed upstream: delivery goes on, the pull is reported failed within its deadline", function()
    referee_stall()
    must_fail(function() referee_stall("blocking") end, "the pull in the gatherer's own thread, without a deadline")
end)

stop_all()
if not os.getenv("KEEP") then os.execute("rm -rf " .. q(ROOT)) else print("kept " .. ROOT) end
print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
