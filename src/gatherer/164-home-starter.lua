-- 164-home-starter.lua — the home starter: one small process per home
-- that starts one gatherer per mailbox and restarts one that dies, saying
-- so, and runs the home-wide task that belongs to no mailbox: 212's
-- public-address recheck (issue 211).  It does nothing else.
--
--   luajit src/gatherer/164-home-starter.lua <project> <disk home>
--
-- Its own `state` and `running-log` are in the home's RAM folder
-- (`<gatherer.ram-root>/<home id>/`), beside one folder per mailbox.
--
--   - Each mailbox listed in `mailboxes` gets `163-gatherer.lua`, its
--     stderr appended to `<mailbox folder>/stderr`.
--   - A gatherer that is gone is started again and the running log says
--     so.  One that dies within 5 s of starting waits before the next
--     start, twice as long each time up to 60 s, so a port another program
--     holds is not fought over in a loop; its own `state` names the port.
--   - The public address (212's watcher, 150) is checked at start-up and
--     then between address.recheck-earliest and -latest seconds later; a
--     first confirmed address or a confirmed move restarts the gatherers,
--     so each states its pairs (205's fresh hellos).
--   - A `stop` file in the home's RAM folder stops it: each gatherer is
--     asked (its own `stop` file), waited for up to 10 s, and the starter
--     exits.
--   - The running source code (issue 215): before a mailbox's gatherer is
--     first started, the program folder the starter runs from is
--     committed to the branch `code/<git.home-name>` of that mailbox's
--     repository, when it changed (172's commit_folder: an index of its
--     own, nothing checked out, the folder's .gitignore applying).  git
--     is required: without it the starter says so, naming the program,
--     and exits with status 1.

local DIR, HOME_DIR = arg[1], arg[2]
if not (DIR and HOME_DIR) then
    io.stderr:write("usage: luajit 164-home-starter.lua <project> <disk home>\n")
    os.exit(2)
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local socket = require("socket")
local rooms = require("002-room-folders")
local disk = require("003-disk")
local address = require("150-public-address")
local ram = require("161-ram-folders")
local git = require("172-git")
local copies_m = require("173-text-copies")

local function now() return socket.gettime() end
local q = disk.shell_quote

local home = rooms.open_home(HOME_DIR)
local root, root_note = ram.choose_root(rooms.config_value(home, "gatherer.ram-root"))
local HOME_RAM = ram.home_ram(root, HOME_DIR)
os.execute("mkdir -p " .. q(HOME_RAM))
local state = { started = math.floor(now()) }
local function log(words) ram.log(HOME_RAM, now(), words) end
if root_note then log(root_note); state["problem.ram-root"] = root_note end

-- git, required (215)
local git_path, no_git = git.find()
if not git_path then
    log("problem git: " .. no_git)
    state["problem.git"] = no_git
    state.stopped = "git"
    ram.write_state(HOME_RAM, state)
    io.stderr:write("rao-chat starter: " .. no_git .. "\n")
    os.exit(1)
end
local HOME_NAME = git.check_name(rooms.config_value(home, "git.home-name"))

-- {{{ local function commit_code
-- The program folder, to code/<home name> of the mailbox's repository.
local function commit_code(tag)
    local ok, result = pcall(function()
        local repo = copies_m.repository(HOME_DIR, tag)
        os.execute("mkdir -p " .. q(HOME_DIR .. "/git"))
        git.ensure(repo)
        return git.commit_folder(repo, "code/" .. HOME_NAME, DIR, "the program this home runs, at start-up", HOME_NAME)
    end)
    if not ok then
        log("problem code-branch: mailbox " .. tag .. ": " .. tostring(result))
        state["problem.code-branch"] = tostring(result)
    elseif result then
        log("code/" .. HOME_NAME .. " of mailbox " .. tag .. ": the program committed (" .. result:sub(1, 12) .. ")")
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

local gatherers = {}      -- mailbox tag → {pid, port, started, wait, next_start}

-- {{{ local function start
local function start(tag, g)
    local folder = ram.layout(HOME_RAM, tag)
    local command = "luajit " .. q(DIR .. "/src/gatherer/163-gatherer.lua") .. " " .. q(DIR) .. " " .. q(HOME_DIR)
        .. " " .. q(tag) .. " </dev/null >>" .. q(folder .. "/stderr") .. " 2>&1 & echo $!"
    local pipe = io.popen(command)
    g.pid = tonumber(pipe:read("*l"))
    pipe:close()
    g.started = now()
    g.starts = (g.starts or 0) + 1
    log(string.format("gatherer for mailbox %s (port %d) started: pid %s", tag, g.port, tostring(g.pid)))
end
-- }}}

-- {{{ local function look_after
-- Starts what is not running, as its wait allows.
local function look_after()
    for _, mailbox in ipairs(rooms.read_mailboxes(home)) do
        local g = gatherers[mailbox.tag]
        if not g then
            g = { port = mailbox.port, wait = 1 }
            gatherers[mailbox.tag] = g
            commit_code(mailbox.tag)
            start(mailbox.tag, g)
        elseif not alive(g.pid) then
            if not g.next_start then
                local lasted = now() - g.started
                if lasted < 5 then g.wait = math.min(g.wait * 2, 60) else g.wait = 1 end
                g.next_start = now() + (lasted < 5 and g.wait or 0)
                log(string.format("gatherer for mailbox %s (port %d, pid %s) is gone after %.1f s; starting it again%s",
                    mailbox.tag, g.port, tostring(g.pid), lasted,
                    lasted < 5 and string.format(" in %d s (see its state)", g.wait) or ""))
            end
            if now() >= g.next_start then
                g.next_start = nil
                start(mailbox.tag, g)
            end
        end
    end
end
-- }}}

-- {{{ local function restart_all
local function restart_all(why)
    log("restarting every gatherer: " .. why)
    for tag, g in pairs(gatherers) do
        os.execute("touch " .. q(HOME_RAM .. "/" .. tag .. "/stop"))
        g.asked = now()
    end
end
-- }}}

-- 212's watcher, when the home has its settings
local watcher
do
    local ok, earliest, latest = pcall(address.settings, home)
    if ok then
        watcher = address.new_watcher({ ram_root = HOME_RAM, earliest = earliest, latest = latest,
            on_move = function(fact) restart_all("the public address moved to " .. fact.address) end })
    else
        log("no public-address recheck: " .. tostring(earliest))
    end
end

-- {{{ local function check_address
local function check_address(first)
    local had = ram.read_state(HOME_RAM)["public-address"]
    local ok, result = pcall(function()
        if first then return watcher:start(math.floor(now())) end
        return watcher:tick(math.floor(now()))
    end)
    if not ok then
        log("public-address check failed: " .. tostring(result))
        watcher.due = math.floor(now()) + 60
        return
    end
    if result then
        -- 215b: each gatherer pulls and pushes its shared upstream now
        for tag in pairs(gatherers) do os.execute("touch " .. q(HOME_RAM .. "/" .. tag .. "/recheck")) end
        log(string.format("public-address check: %s%s; next in %d s", result.outcome,
            result.address and (" " .. result.address) or "", math.floor(result.due - now())))
        state["public-address.outcome"] = result.outcome
        state["public-address.next"] = math.floor(result.due)
        if result.outcome == "first" and not had then restart_all("the public address was confirmed") end
    end
end
-- }}}

local function write_state()
    for tag, g in pairs(gatherers) do
        state["gatherer." .. tag] = string.format("pid %s, port %d, %s, started %d time(s)", tostring(g.pid), g.port,
            alive(g.pid) and "running" or "not running", g.starts or 0)
    end
    ram.write_state(HOME_RAM, state)
end

log("starter started for " .. HOME_DIR)
look_after()
if watcher then check_address(true) end
while true do
    if disk.is_file(HOME_RAM .. "/stop") then
        os.remove(HOME_RAM .. "/stop")
        for tag in pairs(gatherers) do os.execute("touch " .. q(HOME_RAM .. "/" .. tag .. "/stop")) end
        local give_up = now() + 10
        local function any_alive()
            for _, g in pairs(gatherers) do if alive(g.pid) then return true end end
            return false
        end
        while any_alive() and now() < give_up do socket.sleep(0.1) end
        log("stopped: asked to; every gatherer " .. (any_alive() and "asked, some still running" or "stopped"))
        state.stopped = "asked"
        write_state()
        os.exit(0)
    end
    look_after()
    if watcher then check_address(false) end
    write_state()
    socket.sleep(0.25)
end
