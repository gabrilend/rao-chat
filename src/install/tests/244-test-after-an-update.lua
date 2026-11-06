-- 244-test-after-an-update.lua — issue 605's referees: the list of homes
-- installed as services, restarting them all after an update, and
-- following a home's logs, through the stand-in service managers (242), a
-- scratch HOME, a scratch system root and a scratch list.
--
--   1. the list: the installer lists each home it sets up as a service
--      (service, kind, log, home), none it does not, and a second install
--      of a home adds no second line; the list's default place is ignored
--      by git;
--   2. restart: a systemd user home and a runit home are each restarted
--      with their own manager's command and checked running, exit 0;
--   3. sudo: asked once for the run; "no" restarts none that need it and
--      says so (the user service still restarted), exit 1; --yes asks
--      nothing; no sudo on the PATH is said, and those are not restarted;
--   4. not installed: a listed home whose service file is not in place is
--      said by --check (exit 1) and skipped by a restart (exit 1);
--   5. logs: view-logs <service> shows and follows that service's log;
--      --running shows the home's running-log lines marked [starter] and
--      [gatherer ...]; with two homes listed and no argument it lists
--      them and asks, and input that ends is no answer;
--   6. the installer's last question: asked only when every listed
--      home's service is installed (else it says which is not); under
--      --silent nothing is restarted unless --restart-homes is given, and
--      with it every listed home is.
--
-- The homes run (their starter checks the public address), so outside a
-- loopback-only namespace this runs itself again inside one (unshare -rn).
--
-- Run: luajit src/install/tests/244-test-after-an-update.lua [PROJECT_DIR]
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

local function quote(text) return "'" .. tostring(text):gsub("'", "'\\''") .. "'" end

-- {{{ into a loopback-only namespace
if not loopback.only_loopback() then
    if os.getenv("RAO_244_INSIDE") then
        print("FAIL the namespace: still not loopback-only inside unshare -rn")
        print("counts 0 1")
        os.exit(1)
    end
    local this = debug.getinfo(1, "S").source:gsub("^@", "")
    local ok = os.execute("RAO_244_INSIDE=1 unshare -rn luajit " .. quote(this) .. " " .. quote(DIR))
    os.exit((ok == 0 or ok == true) and 0 or 1)
end
assert(loopback.bring_up())
-- }}}

local socket = require("socket")
local files = dofile(DIR .. "/src/install/236-service-files.lua")
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
local function shell(command, input)
    local pipe = io.popen("printf '%s' " .. quote(input or "") .. " | { " .. command .. " ; } 2>&1; echo \"exit=$?\"")
    local output = pipe:read("*a")
    pipe:close()
    return output:gsub("exit=%d+%s*$", ""), tonumber(output:match("exit=(%d+)%s*$"))
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
local function count(text, word)
    local n = 0
    for _ in text:gmatch(word:gsub("%p", "%%%0")) do n = n + 1 end
    return n
end
-- }}}

local ROOT = (os.getenv("RAO_TEST_ROOT") or "/tmp") .. "/244-update"
assert(ROOT:match("/244%-update$"))
os.execute("rm -rf " .. quote(ROOT) .. " && mkdir -p " .. quote(ROOT .. "/homes") .. " " .. quote(ROOT .. "/user"))
local STATE = ROOT .. "/state"
local BIN = io.popen("luajit " .. quote(DIR .. "/src/install/242-stand-in-service-managers.lua") .. " make "
    .. quote(STATE)):read("*l")
write_file(STATE .. "/user", "alice\n")         -- the stand-in whoami: not root
local SYSTEM_ROOT = STATE .. "/root"
local LIST = ROOT .. "/installed-homes"
local LOGS = ROOT .. "/logs"
local ENV = "HOME=" .. quote(ROOT .. "/user") .. " PATH=" .. quote(BIN) .. ":\"$PATH\" "
local INSTALL = ENV .. quote(DIR .. "/scripts/install-home") .. " --silent --log-dir=" .. quote(LOGS)
    .. " --system-root=" .. quote(SYSTEM_ROOT) .. " --ram-root=" .. quote(ROOT .. "/ram")
    .. " --address=127.0.0.2 --homes-list=" .. quote(LIST)
local RESTART = ENV .. quote(DIR .. "/scripts/restart-homes") .. " --homes-list=" .. quote(LIST)
    .. " --system-root=" .. quote(SYSTEM_ROOT)
local VIEW = ENV .. quote(DIR .. "/scripts/view-logs") .. " --homes-list=" .. quote(LIST)
local function calls() return read_all(STATE .. "/calls") or "" end
local function clear_calls() os.remove(STATE .. "/calls") end

local HOME_A, HOME_B, HOME_C = ROOT .. "/homes/a", ROOT .. "/homes/b", ROOT .. "/homes/c"
local SERVICE_A, SERVICE_B = files.name(HOME_A), files.name(HOME_B)
local PORTS_A = { 46671, 46672 }

-- 1. the list, and 6. the last question while a listed home is not installed
do
    clear_calls()
    local output, status = shell(INSTALL .. " --home=" .. quote(HOME_A) .. " --home-name=ann --device-port=46671"
        .. " --direct-port=46672 --setup-service --service-manager=systemd --user-service --no-start-service")
    check("6: one home listed and installed, --silent without --restart-homes: nothing restarted, and said",
        status == 0 and output:find("keep the code they started with", 1, true) ~= nil and calls() == "",
        output .. calls())
    output, status = shell(INSTALL .. " --home=" .. quote(HOME_B) .. " --home-name=bea --device-port=46673"
        .. " --direct-port=46674 --setup-service --service-manager=runit")
    check("6: a listed home whose service is not installed yet: no question, that one named",
        status == 0 and output:find("not every one's service is installed", 1, true) ~= nil
        and output:find("not installed  " .. SERVICE_B, 1, true) ~= nil, output)
    output, status = shell(INSTALL .. " --home=" .. quote(HOME_C) .. " --home-name=cy --device-port=46675"
        .. " --direct-port=46676 --no-setup-service")
    local want = SERVICE_A .. " systemd-user " .. LOGS .. "/" .. SERVICE_A .. ".log " .. HOME_A .. "\n"
        .. SERVICE_B .. " runit " .. LOGS .. "/" .. SERVICE_B .. ".log " .. HOME_B .. "\n"
    check("1: the list holds the two homes set up as services (service, kind, log, home), not the third",
        status == 0 and read_all(LIST) == want, read_all(LIST))
    output, status = shell(INSTALL .. " --home=" .. quote(HOME_A) .. " --home-name=ann --device-port=46671"
        .. " --direct-port=46672 --setup-service --service-manager=systemd --user-service --no-start-service")
    check("1: installing a home again adds no second line, and says it was kept",
        status == 0 and read_all(LIST) == want and output:find("kept     " .. SERVICE_A, 1, true) ~= nil, output)
    local _, ignored = shell("git -C " .. quote(DIR) .. " check-ignore -q installed-homes")
    check("1: <project>/installed-homes is ignored by git", ignored == 0)
    output = shell(RESTART .. " --list")
    check("1: --list prints the list", output == want, output)
end

-- 4. not installed
do
    clear_calls()
    local output, status = shell(RESTART .. " --check")
    check("4: --check: the runit home not installed is said, exit 1",
        status == 1 and output:find("not installed  " .. SERVICE_B, 1, true) ~= nil
        and output:find("installed      " .. SERVICE_A, 1, true) ~= nil, output)
    output, status = shell(RESTART .. " --yes " .. SERVICE_B)
    check("4: restarting it: said, skipped (no sv, no sudo), exit 1",
        status == 1 and output:find("not installed  " .. SERVICE_B, 1, true) ~= nil and calls() == "",
        output .. calls())
end

-- the runit service installed, as a person runs the printed commands
os.execute("mkdir -p " .. quote(SYSTEM_ROOT .. "/etc/sv") .. " && cp -r " .. quote(HOME_B .. "/service/" .. SERVICE_B)
    .. " " .. quote(SYSTEM_ROOT .. "/etc/sv/"))

-- 3. sudo asked once; no
do
    clear_calls()
    local output, status = shell(RESTART, "n\n")
    check("3: sudo asked once for the run, naming the system service",
        count(output, "with sudo?") == 1 and output:find(SERVICE_B, 1, true) ~= nil, output)
    check("3: \"no\": the runit home not restarted and said, the user service restarted, exit 1",
        status == 1 and output:find("not restarting the system services", 1, true) ~= nil
        and not calls():find("sudo", 1, true) and calls():find("systemctl --user restart " .. SERVICE_A, 1, true) ~= nil,
        output .. calls())
end

-- 2. restart, both
do
    clear_calls()
    local output, status = shell(RESTART .. " --yes")
    check("2: --yes asks nothing", not output:find("with sudo?", 1, true), output)
    local c = calls()
    check("2: each restarted with its own manager's command (sudo for runit's only)",
        c:find("systemctl --user restart " .. SERVICE_A .. "\n", 1, true) ~= nil
        and c:find("sudo sv restart " .. SERVICE_B .. "\n", 1, true) ~= nil
        and not c:find("sudo systemctl", 1, true), c)
    check("2: each checked running with its manager's status command, exit 0",
        status == 0 and c:find("systemctl --user is-active " .. SERVICE_A, 1, true) ~= nil
        and c:find("sv status " .. SERVICE_B, 1, true) ~= nil
        and output:find("every home asked for restarted and running (2)", 1, true) ~= nil, output .. c)
    check("2: the restarted user service runs the home: it answers on its ports",
        wait_until(function() return accepts("127.0.0.2", PORTS_A[1]) and accepts("127.0.0.2", PORTS_A[2]) end, 25))
end

-- 3. no sudo on the PATH
do
    local bare = ROOT .. "/bare"
    os.execute("mkdir -p " .. quote(bare))
    for _, name in ipairs({ "systemctl", "sv", "rc-service", "whoami" }) do
        os.execute("ln -s " .. quote(BIN .. "/" .. name) .. " " .. quote(bare .. "/" .. name))
    end
    for _, name in ipairs({ "bash", "env", "grep", "sed", "sleep", "mv", "cat", "luajit", "sh" }) do
        local found = io.popen("command -v " .. name):read("*l")
        if found then os.execute("ln -s " .. quote(found) .. " " .. quote(bare .. "/" .. name)) end
    end
    clear_calls()
    local output, status = shell("HOME=" .. quote(ROOT .. "/user") .. " PATH=" .. quote(bare) .. " "
        .. quote(bare .. "/bash") .. " " .. quote(DIR .. "/scripts/restart-homes") .. " --homes-list=" .. quote(LIST)
        .. " --system-root=" .. quote(SYSTEM_ROOT) .. " " .. SERVICE_B)
    check("3: no sudo here and not root: said, the runit home not restarted, exit 1",
        status == 1 and output:find("sudo is not here", 1, true) ~= nil and not calls():find("sv restart", 1, true),
        output .. calls())
end

-- 5. logs
do
    local log = LOGS .. "/" .. SERVICE_A .. ".log"
    wait_until(function() return (read_all(log) or ""):find("starter pid", 1, true) ~= nil end, 10)
    local output, status = shell(VIEW .. " --no-follow " .. SERVICE_A)
    check("5: view-logs <service> shows that service's log (the launcher's lines)",
        status == 0 and output:find("run-home: home " .. HOME_A, 1, true) ~= nil, output)
    output, status = shell(VIEW .. " --no-follow " .. quote(HOME_A))
    check("5: a listed home's folder names it too", status == 0 and output:find("run-home: home " .. HOME_A, 1, true) ~= nil,
        output)
    -- followed: a line written after it started is shown
    local out = ROOT .. "/followed"
    os.execute("( timeout 4 sh -c " .. quote(VIEW .. " " .. SERVICE_A) .. " > " .. quote(out) .. " 2>&1 ) &")
    socket.sleep(1.5)
    local f = assert(io.open(log, "ab"))
    f:write("a line written while it followed\n")
    f:close()
    wait_until(function() return (read_all(out) or ""):find("a line written while it followed", 1, true) ~= nil end, 5)
    check("5: without --no-follow it follows: a line written later is shown",
        (read_all(out) or ""):find("a line written while it followed", 1, true) ~= nil, read_all(out))
    -- a gatherer's running log is emptied each sync cycle, once committed
    -- (177), so a line is put in it here, as the gatherer writes them
    local rooms, ram = require("002-room-folders"), require("161-ram-folders")
    local tag = rooms.direct_mailbox(rooms.open_home(HOME_A))
    local gatherer_log = ram.home_ram(ROOT .. "/ram", HOME_A) .. "/" .. tag .. "/running-log"
    f = assert(io.open(gatherer_log, "ab"))
    f:write("2026-11-06T00:00:00Z a gatherer's line\n")
    f:close()
    output, status = shell(VIEW .. " --running --no-follow " .. SERVICE_A)
    check("5: --running shows the starter's lines marked [starter]",
        status == 0 and output:find("\n%[starter%] [^\n]*starter started for") ~= nil, output)
    check("5: --running shows a gatherer's lines marked [gatherer <its mailbox>]",
        output:find("\n[gatherer " .. tag .. "] 2026-11-06T00:00:00Z a gatherer's line\n", 1, true) ~= nil, output)
    output, status = shell(VIEW .. " --no-follow", "1\n")
    check("5: two homes listed, no argument: both listed, asked, the first one's log shown alone",
        status == 0 and output:find("1. " .. SERVICE_A, 1, true) ~= nil and output:find("2. " .. SERVICE_B, 1, true) ~= nil
        and output:find("Which one?", 1, true) ~= nil and output:find("run-home: home " .. HOME_A, 1, true) ~= nil
        and not output:find("run-home: home " .. HOME_B, 1, true), output)
    output, status = shell(VIEW .. " --no-follow", "")
    check("5: input that ends is no answer: exit 1", status == 1 and output:find("input ended", 1, true) ~= nil, output)
end

-- 6. the last question, answered by flag under --silent
do
    clear_calls()
    local output, status = shell(INSTALL .. " --yes --restart-homes --home=" .. quote(HOME_C) .. " --home-name=cy"
        .. " --device-port=46675 --direct-port=46676 --no-setup-service")
    local c = calls()
    check("6: every listed home installed, --restart-homes: each restarted (sudo under --yes, unasked)",
        status == 0 and c:find("systemctl --user restart " .. SERVICE_A, 1, true) ~= nil
        and c:find("sudo sv restart " .. SERVICE_B, 1, true) ~= nil and not output:find("with sudo?", 1, true),
        output .. c)
end

-- stop everything started
shell(ENV .. quote(BIN .. "/systemctl") .. " --user stop " .. SERVICE_A)
check("the user service stops: its ports close",
    wait_until(function() return not accepts("127.0.0.2", PORTS_A[1]) end, 10))
os.execute("pkill -KILL -f " .. quote(ROOT .. "/homes/") .. " 2>/dev/null")
os.execute("rm -rf " .. quote(ROOT))
print(string.format("counts %d %d", passed, failed))
os.exit(failed == 0 and 0 or 1)
