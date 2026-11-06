-- 243-test-running-as-a-service.lua — issue 604's referees: a home set up
-- as a service of the machine's service manager, through stand-ins for
-- the managers' commands (242), a scratch HOME and a scratch system root.
--
--   1. templates: each of the five fills with no placeholder left, naming
--      run-home, the program folder, the home and the log; a home and a
--      program folder holding a space, &, | and \ come through unchanged
--      where the syntax can carry them (read back by systemd's rules, by
--      sh and by nix's), and OpenRC, which cannot, refuses them and writes
--      nothing; a template asking for an unknown value writes nothing;
--   2. detection: nixos, process 1's name, then systemctl, sv, rc-service
--      on the path, else unknown; --service-manager overrides it;
--   3. the systemd user service: written under the scratch HOME, and
--      daemon-reload, enable, then start asked for; --no-start-service
--      asks for none;
--   4. system services: runit, OpenRC, NixOS and systemd-system each
--      write into <home>/service/ and print the commands; no sudo is run
--      and the scratch HOME holds nothing;
--   5. the clash: a service of the same name serving another home stops
--      the installer, exit 1, nothing written; one serving this home is
--      written again and said;
--   6. the service runs the home: the stand-in systemctl's start runs the
--      unit's ExecStart in a bare environment, the home answers on its
--      ports, and the stand-in's stop (SIGTERM to the launcher alone)
--      stops it cleanly: status 0, the launcher saying so, nothing left.
--
-- The home's starter checks the public address, so outside a loopback-
-- only namespace this runs itself again inside one (unshare -rn).
--
-- Run: luajit src/install/tests/243-test-running-as-a-service.lua [PROJECT_DIR]
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
    if os.getenv("RAO_243_INSIDE") then
        print("FAIL the namespace: still not loopback-only inside unshare -rn")
        print("counts 0 1")
        os.exit(1)
    end
    local this = debug.getinfo(1, "S").source:gsub("^@", "")
    local ok = os.execute("RAO_243_INSIDE=1 unshare -rn luajit " .. quote(this) .. " " .. quote(DIR))
    os.exit((ok == 0 or ok == true) and 0 or 1)
end
assert(loopback.bring_up())
-- }}}

local socket = require("socket")
local files = dofile(DIR .. "/src/install/236-service-files.lua")
local stand_in = dofile(DIR .. "/src/install/242-stand-in-service-managers.lua")
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
    local stat = pid and read_all("/proc/" .. pid .. "/stat")
    return stat ~= nil and stat:match("%) (%a)") ~= "Z"
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
local function exists(path) return os.execute("test -e " .. quote(path)) == 0 end
local function listing(folder)
    local pipe = io.popen("cd " .. quote(folder) .. " 2>/dev/null && find . -mindepth 1 | sort")
    local text = pipe:read("*a")
    pipe:close()
    return text
end
local function same_list(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
end
-- }}}

local ROOT = (os.getenv("RAO_TEST_ROOT") or "/tmp") .. "/243-service"
assert(ROOT:match("/243%-service$"))
os.execute("rm -rf " .. quote(ROOT) .. " && mkdir -p " .. quote(ROOT .. "/homes") .. " " .. quote(ROOT .. "/out"))
local FILLER = DIR .. "/src/install/236-service-files.lua"
local TEMPLATES = DIR .. "/src/install/templates/"
local KINDS = { "237-systemd-user.service", "238-systemd-system.service", "239-runit-run", "240-openrc-init",
    "241-nixos.nix" }

-- 1. templates
do
    local values = { service = "rao-chat-t", user = "alice", log_dir = "/tmp", home = "/srv/rao/alice",
        project = "/opt/rao-chat" }
    for _, kind in ipairs(KINDS) do
        local text, why = files.fill(read_all(TEMPLATES .. kind), values)
        check("1: " .. kind .. " fills with no placeholder left", text ~= nil and not text:find("@[A-Z_]+@"), why)
        text = text or ""
        check("1: " .. kind .. " names run-home, the program folder, the home and the log",
            text:find("/opt/rao-chat/scripts/run-home", 1, true) and text:find("/srv/rao/alice", 1, true)
            and text:find("/tmp/rao-chat-t.log", 1, true) and text:find("# rao-chat home: /srv/rao/alice\n", 1, true),
            text)
    end

    -- the hard paths, read back by each syntax's own rules
    local home, project = ROOT .. "/homes/a b&c|d\\e", ROOT .. "/pro ject&|\\"
    local hard = { service = "rao-chat-hard", user = "alice", log_dir = "/tmp", home = home, project = project }
    local want = { project .. "/scripts/run-home", project, home }
    local unit = files.fill(read_all(TEMPLATES .. "237-systemd-user.service"), hard) or ""
    local exec = unit:match("\nExecStart=([^\n]*)")
    check("1: systemd reads back the run-home, program folder and home holding space, &, | and \\",
        exec and same_list(stand_in.unit_words(exec), want), exec)
    local system = files.fill(read_all(TEMPLATES .. "238-systemd-system.service"), hard) or ""
    exec = system:match("\nExecStart=([^\n]*)")
    check("1: so does the systemd system service", exec and same_list(stand_in.unit_words(exec), want), exec)
    local nix = files.fill(read_all(TEMPLATES .. "241-nixos.nix"), hard) or ""
    local nix_string = nix:match('\n%s*ExecStart = "(.-[^\\])";\n')
    local read_back = nix_string and nix_string:gsub("\\(.)", "%1")
    check("1: nix's string, read back, is the same ExecStart",
        read_back and same_list(stand_in.unit_words(read_back), want), nix_string)

    -- runit: run by sh, with a chpst that writes down what it was given
    local bin, out = ROOT .. "/out/bin", ROOT .. "/out/chpst-args"
    os.execute("mkdir -p " .. quote(bin))
    write_file(bin .. "/chpst", "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\"; done > " .. quote(out) .. "\n")
    os.execute("chmod +x " .. quote(bin .. "/chpst"))
    local run_file = ROOT .. "/out/run"
    local hard_log = { service = "rao-chat-hard", user = "alice", log_dir = ROOT .. "/out", home = home,
        project = project }
    local _, status = shell("luajit " .. quote(FILLER) .. " " .. quote(DIR) .. " fill " .. quote(TEMPLATES
        .. "239-runit-run") .. " " .. quote(run_file) .. " service=rao-chat-hard user=alice log_dir="
        .. quote(hard_log.log_dir) .. " home=" .. quote(home) .. " project=" .. quote(project))
    shell("PATH=" .. quote(bin) .. ":/usr/bin:/bin sh " .. quote(run_file))
    local args = {}
    for line in (read_all(out) or ""):gmatch("[^\n]+") do args[#args + 1] = line end
    check("1: runit's run, run by sh, hands chpst the user, run-home, program folder and home unchanged",
        status == 0 and same_list(args, { "-u", "alice", want[1], want[2], want[3] }), table.concat(args, " | "))

    -- OpenRC: plain paths read back through eval; hard ones refused
    local init = ROOT .. "/out/init"
    _, status = shell("luajit " .. quote(FILLER) .. " " .. quote(DIR) .. " fill " .. quote(TEMPLATES
        .. "240-openrc-init") .. " " .. quote(init) .. " service=rao-chat-t user=alice log_dir=/tmp"
        .. " home=/srv/rao/alice project=/opt/rao-chat")
    local words = shell("sh -c " .. quote('. "$1"; eval set -- $command $command_args; for a in "$@"; do '
        .. "printf '%s\\n' \"$a\"; done") .. " sh " .. quote(init))
    check("1: OpenRC's command and command_args, through eval, are run-home, the program folder and the home",
        status == 0 and words == "/opt/rao-chat/scripts/run-home\n/opt/rao-chat\n/srv/rao/alice\n", words)
    local output
    output, status = shell("luajit " .. quote(FILLER) .. " " .. quote(DIR) .. " fill " .. quote(TEMPLATES
        .. "240-openrc-init") .. " " .. quote(init) .. " service=rao-chat-hard user=alice log_dir=/tmp home="
        .. quote(home) .. " project=" .. quote(project))
    check("1: OpenRC refuses a home holding a space, exit 1, saying why, and the file before it is removed",
        status == 1 and output:find("eval", 1, true) and not exists(init), output)

    -- an unknown placeholder, and values that may not be carried bare
    local odd = ROOT .. "/out/odd.template"
    write_file(odd, "# rao-chat home: @HOME_COMMENT@\nExecStart=@EXEC_SYSTEMD@ @NOT_A_VALUE@\n")
    output, status = shell("luajit " .. quote(FILLER) .. " " .. quote(DIR) .. " fill " .. quote(odd) .. " "
        .. quote(ROOT .. "/out/odd") .. " service=s user=u log_dir=/tmp home=/h project=/p")
    check("1: a template asking for an unknown value writes no file, exit 1, naming it",
        status == 1 and output:find("@NOT_A_VALUE@", 1, true) and not exists(ROOT .. "/out/odd"), output)
    local text, why = files.fill(read_all(TEMPLATES .. "237-systemd-user.service"),
        { service = "a b", user = "u", log_dir = "/tmp", home = "/h", project = "/p" })
    check("1: a service name with a space is refused", text == nil and why:find("service name", 1, true), why)
    text, why = files.fill(read_all(TEMPLATES .. "237-systemd-user.service"),
        { service = "s", user = "u", log_dir = "/tmp/a b", home = "/h", project = "/p" })
    check("1: a log folder with a space is refused", text == nil and why:find("log folder", 1, true), why)
    text, why = files.fill(read_all(TEMPLATES .. "237-systemd-user.service"),
        { service = "s", user = "u", log_dir = "/tmp", home = "/h\nExecStartPre=/bin/false", project = "/p" })
    check("1: a home holding a newline is refused", text == nil, why)
    check("1: the name: slashes as dashes, after rao-chat-",
        files.name("/home/ritz/rao-home") == "rao-chat-home-ritz-rao-home"
        and files.name("/srv/a b/") == "rao-chat-srv-a_b", files.name("/srv/a b/"))
end

-- 2. detection
do
    local detect = quote(DIR .. "/src/install/235-service-manager")
    local scratch = ROOT .. "/detect"
    local empty, bin = scratch .. "/empty", scratch .. "/bin"
    os.execute("mkdir -p " .. quote(empty) .. " " .. quote(bin) .. " " .. quote(scratch .. "/nix/etc") .. " "
        .. quote(scratch .. "/one/proc/1"))
    local function word(root, path)
        local out = shell("PATH=" .. quote(path) .. " /bin/bash " .. detect .. " --root=" .. quote(root))
        return out:match("^(%S+)\n$")
    end
    write_file(scratch .. "/nix/etc/NIXOS", "")
    check("2: /etc/NIXOS: nixos", word(scratch .. "/nix", empty) == "nixos")
    local first = {}
    for _, pair in ipairs({ { "systemd", "systemd" }, { "runit", "runit" }, { "openrc-init", "openrc" } }) do
        write_file(scratch .. "/one/proc/1/comm", pair[1] .. "\n")
        first[#first + 1] = word(scratch .. "/one", empty) == pair[2]
    end
    check("2: process 1 named systemd, runit, openrc-init: systemd, runit, openrc",
        first[1] and first[2] and first[3])
    write_file(scratch .. "/one/proc/1/comm", "process_api\n")
    check("2: nothing found: unknown", word(scratch .. "/one", empty) == "unknown")
    local on_path = {}
    for _, pair in ipairs({ { "rc-service", "openrc" }, { "sv", "runit" }, { "systemctl", "systemd" } }) do
        write_file(bin .. "/" .. pair[1], "#!/bin/sh\n")
        os.execute("chmod +x " .. quote(bin .. "/" .. pair[1]))
        on_path[#on_path + 1] = word(scratch .. "/one", bin) == pair[2]
    end
    check("2: rc-service, then sv, then systemctl on the path: openrc, runit, systemd (first wins)",
        on_path[1] and on_path[2] and on_path[3])
end

-- the installer, with the stand-ins first on its PATH
local STATE = ROOT .. "/state"
local BIN = io.popen("luajit " .. quote(DIR .. "/src/install/242-stand-in-service-managers.lua") .. " make "
    .. quote(STATE)):read("*l")
local USER_HOME = ROOT .. "/user"
os.execute("mkdir -p " .. quote(USER_HOME))
local SYSTEM_ROOT = STATE .. "/root"
local LOGS = ROOT .. "/logs"
local INSTALL = "HOME=" .. quote(USER_HOME) .. " PATH=" .. quote(BIN) .. ":\"$PATH\" "
    .. quote(DIR .. "/scripts/install-home") .. " --silent --setup-service --log-dir=" .. quote(LOGS)
    .. " --system-root=" .. quote(SYSTEM_ROOT) .. " --ram-root=" .. quote(ROOT .. "/ram")
    .. " --home-name=alice --address=127.0.0.2 --homes-list=" .. quote(ROOT .. "/installed-homes")
local function calls() return read_all(STATE .. "/calls") or "" end
local function clear_calls() os.remove(STATE .. "/calls") end
local function install(home, ports, more)
    return shell(INSTALL .. " --home=" .. quote(home) .. " --device-port=" .. ports[1] .. " --direct-port=" .. ports[2]
        .. " " .. more)
end

-- 4. system services
do
    local kinds = {
        { "--service-manager=runit", "/service/%s/run", "sudo ln -s /etc/sv/" },
        { "--service-manager=openrc", "/service/%s.init", "sudo rc-update add " },
        { "--service-manager=nixos", "/service/%s.nix", "sudo nixos-rebuild switch" },
        { "--service-manager=systemd --no-user-service", "/service/%s.service", "sudo systemctl enable --now " },
    }
    for i, kind in ipairs(kinds) do
        local home = ROOT .. "/homes/system-" .. i
        local service = files.name(home)
        clear_calls()
        local output, status = install(home, { 46640 + 2 * i, 46641 + 2 * i }, kind[1])
        local file = home .. kind[2]:format(service)
        check("4: " .. kind[1] .. ": the file is written into the home and the commands printed",
            status == 0 and exists(file) and output:find(kind[3], 1, true) ~= nil
            and output:find("file: " .. file, 1, true) ~= nil, output)
    end
    check("4: no sudo, systemctl or other command of a manager was run for a system service", calls() == "", calls())
    check("4: the scratch HOME holds nothing", listing(USER_HOME) == "", listing(USER_HOME))
    check("4: nothing was written under the system root", listing(SYSTEM_ROOT) == "", listing(SYSTEM_ROOT))
end

-- 3. the systemd user service, not started
local HOME_A = ROOT .. "/homes/a"
local SERVICE_A = files.name(HOME_A)
local UNIT_A = USER_HOME .. "/.config/systemd/user/" .. SERVICE_A .. ".service"
local PORTS_A = { 46631, 46632 }
do
    clear_calls()
    local output, status = install(HOME_A, PORTS_A, "--service-manager=systemd --user-service --no-start-service")
    check("3: --no-start-service: the unit is under the scratch HOME, no systemctl asked for",
        status == 0 and exists(UNIT_A) and calls() == "", output .. calls())
    check("3: the log folder is made, and the unit appends to <log folder>/<service>.log",
        exists(LOGS) and (read_all(UNIT_A) or ""):find("StandardOutput=append:" .. LOGS .. "/" .. SERVICE_A .. ".log\n",
            1, true) ~= nil, read_all(UNIT_A))
end

-- 5. the clash
do
    local home = ROOT .. "/homes/clash"
    local service = files.name(home)
    os.execute("mkdir -p " .. quote(SYSTEM_ROOT .. "/etc/systemd/system"))
    local installed = SYSTEM_ROOT .. "/etc/systemd/system/" .. service .. ".service"
    write_file(installed, "# rao-chat home: /somewhere/else\n[Service]\nExecStart=/bin/true\n")
    local output, status = install(home, { 46661, 46662 }, "--service-manager=runit")
    check("5: a service of this name installed for another home: exit 1, said, the home not made",
        status == 1 and output:find("already installed for another home", 1, true) ~= nil and not exists(home),
        output)
    write_file(installed, "# rao-chat home: " .. home .. "\n[Service]\nExecStart=/bin/true\n")
    output, status = install(home, { 46661, 46662 }, "--service-manager=runit")
    check("5: one serving this home: written, and said",
        status == 0 and exists(home .. "/service/" .. service .. "/run")
        and output:find("already served this home", 1, true) ~= nil, output)
    os.remove(installed)
    local other = USER_HOME .. "/.config/systemd/user/rao-chat-other.service"
    local held = "# rao-chat home: /somewhere/else\n[Service]\nExecStart=/bin/true\n"
    write_file(other, held)
    local config_before = read_all(HOME_A .. "/config")
    output, status = install(HOME_A, PORTS_A, "--service-manager=systemd --user-service --no-start-service"
        .. " --service-name=rao-chat-other")
    check("5: --service-name naming a user service of another home: exit 1, its file and this home untouched",
        status == 1 and read_all(other) == held and read_all(HOME_A .. "/config") == config_before, output)
    os.remove(other)
end

-- 6. (and 3) the service runs the home, started through the stand-in
do
    clear_calls()
    local output, status = install(HOME_A, PORTS_A, "--service-manager=systemd --user-service")
    local want = {
        "systemctl --user daemon-reload",
        "systemctl --user enable " .. SERVICE_A,
        "systemctl --user is-active " .. SERVICE_A,
        "systemctl --user start " .. SERVICE_A,
    }
    local got = {}
    for line in calls():gmatch("[^\n]+") do got[#got + 1] = line end
    check("3: daemon-reload, enable, then start asked for, in that order",
        status == 0 and same_list(got, want), output .. calls())
    local pid = tonumber(read_all(STATE .. "/" .. SERVICE_A .. ".pid") or "")
    local environ = pid and read_all("/proc/" .. pid .. "/environ") or ""
    check("6: the launcher runs in the stand-in's bare environment (no PATH of this shell's)",
        environ:find("PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin%z") ~= nil
        and not environ:find(BIN, 1, true), environ:gsub("%z", " "))
    local up = wait_until(function() return accepts("127.0.0.2", PORTS_A[1]) and accepts("127.0.0.2", PORTS_A[2]) end, 25)
    check("6: the home answers on its device port and its direct-message mailbox's port", up)
    output = shell("HOME=" .. quote(USER_HOME) .. " " .. quote(BIN .. "/systemctl") .. " --user is-active " .. SERVICE_A)
    check("6: is-active says active", output == "active\n", output)
    local log = LOGS .. "/" .. SERVICE_A .. ".log"
    output = shell("HOME=" .. quote(USER_HOME) .. " " .. quote(BIN .. "/systemctl") .. " --user stop " .. SERVICE_A)
    check("6: the stop (SIGTERM to the launcher alone) ends it with status 0",
        output:find("ended with status 0", 1, true) ~= nil, output .. (read_all(log) or ""))
    check("6: the launcher's log says everything stopped when asked",
        (read_all(log) or ""):find("each stopped when asked", 1, true) ~= nil, read_all(log))
    local left = shell("ps -eo args | grep -F " .. quote(HOME_A) .. " | grep -v grep")
    check("6: nothing of the home is left running", left == "", left)
    check("6: the ports are closed", not accepts("127.0.0.2", PORTS_A[1]) and not accepts("127.0.0.2", PORTS_A[2]))
    -- whatever happened, nothing outlives the referee
    if pid and alive(pid) then os.execute("kill -KILL " .. pid) end
    os.execute("pkill -KILL -f " .. quote(HOME_A) .. " 2>/dev/null")
end

os.execute("rm -rf " .. quote(ROOT))
print(string.format("counts %d %d", passed, failed))
os.exit(failed == 0 and 0 or 1)
