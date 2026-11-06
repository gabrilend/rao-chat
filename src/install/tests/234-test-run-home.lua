-- 234-test-run-home.lua — issue 603's referees: scripts/run-home running a
-- home made by the installer (602), on 127.0.0.2.
--
--   1. it runs a home: the starter's state names its gatherer running, and
--      the device port and the direct-message mailbox's port accept;
--   2. SIGTERM stops it cleanly: exit 0 within the wait, the gatherer's
--      state says stopped = asked, and no process of the home is left (also
--      SIGHUP, and a stop file left from before does not stop a new run);
--   3. half a home is no home: the device server killed, the launcher
--      stops the starter (its gatherer stopped = asked) and exits 1;
--   4. once per home: a second launcher exits 1 saying the home is running,
--      and the first runs on;
--   5. what is missing is said: an environment file whose PATH has no git,
--      exit 1 naming git, nothing started; a line other than PATH,
--      LUA_PATH and LUA_CPATH refused, naming the line.
--
-- The starter checks the public address, so this must not reach a
-- network: outside a loopback-only namespace it runs itself again inside
-- one (unshare -rn), as the demos do.  Its homes and RAM folders are under
-- RAO_TEST_ROOT, or /tmp; it removes them, and stops everything it started.
--
-- Run: luajit src/install/tests/234-test-run-home.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>"; exit status
-- 0 only when nothing failed.

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/install/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)
local loopback = require("168-loopback")

local function quote(text) return "'" .. text:gsub("'", "'\\''") .. "'" end

-- {{{ into a loopback-only namespace
if not loopback.only_loopback() then
    if os.getenv("RAO_234_INSIDE") then
        print("FAIL the namespace: still not loopback-only inside unshare -rn")
        print("counts 0 1")
        os.exit(1)
    end
    local this = debug.getinfo(1, "S").source:gsub("^@", "")
    local ok = os.execute("RAO_234_INSIDE=1 unshare -rn luajit " .. quote(this) .. " " .. quote(DIR))
    os.exit((ok == 0 or ok == true) and 0 or 1)
end
assert(loopback.bring_up())
-- }}}

local socket = require("socket")
local passed, failed = 0, 0

-- {{{ local function check
local function check(claim, ok, detail)
    if ok then
        passed = passed + 1
        print("PASS " .. claim)
    else
        failed = failed + 1
        print("FAIL " .. claim .. (detail and (": " .. tostring(detail):sub(1, 900)) or ""))
    end
end
-- }}}

-- {{{ small tools
local function read_all(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
local function write_file(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end
local function shell(command)
    local pipe = io.popen(command .. " 2>&1; echo \"exit=$?\"")
    local output = pipe:read("*a")
    pipe:close()
    return output:gsub("exit=%d+%s*$", ""), tonumber(output:match("exit=(%d+)%s*$"))
end
local function alive(pid)
    local f = pid and io.open("/proc/" .. pid .. "/stat", "rb")
    if not f then return false end
    local stat = f:read("*a")
    f:close()
    return stat:match("%) (%a)") ~= "Z"
end
local function wait_until(test, seconds)
    local give_up = socket.gettime() + seconds
    while socket.gettime() < give_up do
        if test() then return true end
        socket.sleep(0.1)
    end
    return test()
end
local function accepts(address, port)
    local sock = socket.tcp4()
    sock:settimeout(0.5)
    local ok = sock:connect(address, port)
    sock:close()
    return ok == 1
end
-- }}}

local ROOT = (os.getenv("RAO_TEST_ROOT") or "/tmp") .. "/234-run-home"
assert(ROOT:match("/234%-run%-home$"))
os.execute("rm -rf " .. quote(ROOT) .. " && mkdir -p " .. quote(ROOT .. "/homes") .. " " .. quote(ROOT .. "/user"))
local RAM = ROOT .. "/ram"
local HOME_A = ROOT .. "/homes/a"
local DEVICE_PORT, DIRECT_PORT = 46621, 46622
local RUN_HOME = quote(DIR .. "/scripts/run-home")

-- {{{ the home, made by the installer
do
    local output, status = shell("HOME=" .. quote(ROOT .. "/user") .. " " .. quote(DIR .. "/scripts/install-home")
        .. " --silent --no-setup-service --home=" .. quote(HOME_A) .. " --home-name=alice --device-port=" .. DEVICE_PORT
        .. " --direct-port=" .. DIRECT_PORT .. " --address=127.0.0.2 --ram-root=" .. quote(RAM))
    if status ~= 0 then
        check("the home is made by the installer", false, output)
        print(string.format("counts %d %d", passed, failed))
        os.exit(1)
    end
end
local HOME_RAM = io.popen("luajit -e " .. quote([[
    local DIR, HOME_DIR = arg[1], arg[2]
    dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)
    local rooms, ram = require("002-room-folders"), require("161-ram-folders")
    io.write(ram.home_ram(rooms.config_value(rooms.open_home(HOME_DIR), "gatherer.ram-root"), HOME_DIR))]])
    .. " /dev/null " .. quote(DIR) .. " " .. quote(HOME_A)):read("*a")
local MAILBOX = io.popen("luajit -e " .. quote([[
    local DIR, HOME_DIR = arg[1], arg[2]
    dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)
    local rooms = require("002-room-folders")
    io.write(rooms.direct_mailbox(rooms.open_home(HOME_DIR)))]])
    .. " /dev/null " .. quote(DIR) .. " " .. quote(HOME_A)):read("*a")
-- }}}

-- {{{ local function state_of(folder) → name → value
local function state_of(folder)
    local state = {}
    for line in (read_all(folder .. "/state") or ""):gmatch("[^\n]+") do
        local name, value = line:match("^(%S+) = (.*)$")
        if name then state[name] = value end
    end
    return state
end
-- }}}

local launched = {}     -- every launcher pid, stopped at the end

-- {{{ local function pids_in(log) → starter pid, device server pid
local function pids_in(log)
    local text = read_all(log) or ""
    return tonumber(text:match("starter pid (%d+)")), tonumber(text:match("device server pid (%d+)"))
end
-- }}}

-- {{{ local function home_up(log) → running, starter, server, gatherer pid
local function home_up(log)
    local starter, server, gatherer
    local up = wait_until(function()
        starter, server = pids_in(log)
        gatherer = tonumber(state_of(HOME_RAM .. "/" .. MAILBOX).pid or "")
        return starter and server and alive(gatherer) and accepts("127.0.0.2", DEVICE_PORT)
            and accepts("127.0.0.2", DIRECT_PORT)
    end, 20)
    return up, starter, server, gatherer
end
-- }}}

-- {{{ local function finished(pid, seconds) → whether it ended in time
local function finished(pid, seconds)
    return wait_until(function() return not alive(pid) end, seconds)
end
-- }}}

-- {{{ local function launch_with_status(home, log, status_file) → pid
-- The launcher in the background; a wrapper shell writes its pid, then
-- its exit status, each into a file.  (A command run in the background by
-- a shell ignores SIGINT, and an ignored signal cannot be trapped, so the
-- referees stop it with SIGTERM and SIGHUP.)
local function launch_with_status(home, log, status_file)
    local pid_file = status_file .. ".pid"
    os.execute("( " .. RUN_HOME .. " " .. quote(DIR) .. " " .. quote(home) .. " --stop-wait=15 </dev/null >"
        .. quote(log) .. " 2>&1 & echo $! >" .. quote(pid_file) .. "; wait $!; echo $? >" .. quote(status_file)
        .. " ) >/dev/null 2>&1 </dev/null &")
    wait_until(function() return (read_all(pid_file) or ""):match("%d+\n") ~= nil end, 5)
    local pid = tonumber((read_all(pid_file) or ""):match("%d+"))
    launched[#launched + 1] = pid
    return pid
end
-- }}}

-- 1 and 2: running, then SIGTERM
do
    local log, status_file = ROOT .. "/log-1", ROOT .. "/status-1"
    local pid = launch_with_status(HOME_A, log, status_file)
    local up, starter, server, gatherer = home_up(log)
    check("1: the home runs: the gatherer is running and both ports accept", up, read_all(log))
    local starter_state = state_of(HOME_RAM)
    check("1: the starter's state names its gatherer running",
        (starter_state["gatherer." .. MAILBOX] or ""):find("running", 1, true) ~= nil, read_all(HOME_RAM .. "/state"))
    -- 4: a second launcher
    local output, status = shell(RUN_HOME .. " " .. quote(DIR) .. " " .. quote(HOME_A))
    check("4: a second run-home for the home exits 1, saying it is running",
        status == 1 and output:find("already running", 1, true) ~= nil, output)
    check("4: the first runs on", alive(starter) and alive(server) and alive(gatherer) and pid and alive(pid))
    -- 2: SIGTERM
    os.execute("kill -TERM " .. tostring(pid))
    local gone = finished(pid, 25)
    check("2: SIGTERM: the launcher ends within the wait", gone, read_all(log))
    wait_until(function() return read_all(status_file) ~= nil end, 5)
    check("2: ... with exit 0", (read_all(status_file) or ""):match("^0") ~= nil, read_all(log))
    check("2: the gatherer synced and stopped when asked",
        state_of(HOME_RAM .. "/" .. MAILBOX).stopped == "asked", read_all(HOME_RAM .. "/" .. MAILBOX .. "/state"))
    check("2: no process of the home is left (starter, device server, gatherer)",
        not alive(starter) and not alive(server) and not alive(gatherer))
    check("2: its lines say it was asked and stopped cleanly",
        (read_all(log) or ""):find("run%-home: stopping %(SIGTERM%)") ~= nil
        and (read_all(log) or ""):find("each stopped when asked", 1, true) ~= nil, read_all(log))
end

-- 2: SIGHUP, with a stop file left from before
do
    write_file(HOME_RAM .. "/stop", "")
    local log, status_file = ROOT .. "/log-2", ROOT .. "/status-2"
    local pid = launch_with_status(HOME_A, log, status_file)
    local up, starter, server, gatherer = home_up(log)
    socket.sleep(2)     -- the starter reads its stop file in its loop, after its first address check
    check("2: a stop file left from before does not stop a new run (still running 2 s later)",
        up and alive(pid) and alive(starter) and alive(server) and alive(gatherer), read_all(log))
    os.execute("kill -HUP " .. tostring(pid))
    finished(pid, 25)
    wait_until(function() return read_all(status_file) ~= nil end, 5)
    check("2: SIGHUP stops it the same way, exit 0", (read_all(status_file) or ""):match("^0") ~= nil
        and (read_all(log) or ""):find("stopping (SIGHUP)", 1, true) ~= nil, read_all(log))
end

-- 3: half a home
do
    local log, status_file = ROOT .. "/log-3", ROOT .. "/status-3"
    local pid = launch_with_status(HOME_A, log, status_file)
    local up, starter, server, gatherer = home_up(log)
    check("3: (the home runs again)", up, read_all(log))
    os.execute("kill -KILL " .. tostring(server))
    finished(pid, 25)
    wait_until(function() return read_all(status_file) ~= nil end, 5)
    check("3: the device server killed: the launcher exits 1",
        (read_all(status_file) or ""):match("^1") ~= nil, read_all(log))
    check("3: ... saying the device server ended without being asked",
        (read_all(log) or ""):find("the device server %(pid " .. server .. "%) ended without being asked") ~= nil,
        read_all(log))
    check("3: the starter was stopped, its gatherer synced (stopped = asked)",
        not alive(starter) and not alive(gatherer) and state_of(HOME_RAM .. "/" .. MAILBOX).stopped == "asked",
        read_all(HOME_RAM .. "/" .. MAILBOX .. "/state"))
end

-- 5: what is missing
do
    local env_path = HOME_A .. "/environment"
    local kept = read_all(env_path)
    local bin = ROOT .. "/only-luajit"
    os.execute("mkdir -p " .. quote(bin))
    for _, tool in ipairs({ "luajit", "flock", "setsid", "bash", "env", "date", "sed", "dirname", "grep", "mkdir",
                            "rm", "touch", "sleep" }) do
        local where = io.popen("command -v " .. tool):read("*l")
        if where then os.execute("ln -sf " .. quote(where) .. " " .. quote(bin .. "/" .. tool)) end
    end
    write_file(env_path, "# no git here\nPATH=" .. bin .. "\n")
    local output, status = shell(RUN_HOME .. " " .. quote(DIR) .. " " .. quote(HOME_A))
    check("5: a PATH without git: exit 1, naming git, nothing started",
        status == 1 and output:find("not on this PATH: git", 1, true) ~= nil
        and not output:find("starter pid", 1, true), output)
    write_file(env_path, kept .. "HOME=/elsewhere\n")
    output, status = shell(RUN_HOME .. " " .. quote(DIR) .. " " .. quote(HOME_A))
    check("5: a line other than PATH, LUA_PATH and LUA_CPATH is refused, naming it",
        status == 1 and output:find("HOME=/elsewhere", 1, true) ~= nil and not output:find("starter pid", 1, true),
        output)
    write_file(env_path, kept)
    output, status = shell(RUN_HOME .. " " .. quote(DIR) .. " " .. quote(ROOT .. "/homes/none"))
    check("5: a folder that is no home: exit 1, saying so", status == 1 and output:find("no home at", 1, true) ~= nil,
        output)
end

-- everything started here is stopped, whatever happened above
for _, pid in ipairs(launched) do
    if alive(pid) then os.execute("kill -TERM " .. pid); finished(pid, 25) end
end
for _, folder in ipairs({ HOME_RAM, HOME_RAM .. "/" .. MAILBOX, HOME_RAM .. "/devices" }) do
    local pid = tonumber(state_of(folder).pid or "")
    if alive(pid) then os.execute("kill -KILL " .. pid) end
end
os.execute("rm -rf " .. quote(ROOT))
print(string.format("counts %d %d", passed, failed))
os.exit(failed == 0 and 0 or 1)
