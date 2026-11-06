-- 231-test-what-a-home-needs.lua — issue 601's referees: the check of what
-- a home needs (230), run as a program the way the installer runs it.
--
--   1. on this machine every required thing is found, each line naming the
--      version it reported, exit 0;
--   2. a missing LuaSocket is named (LUA_PATH and LUA_CPATH that find
--      nothing), with libs/, exit 1;
--   3. a missing libcrypto is named (RAO_NEEDS_BROKEN=crypto), exit 1;
--   4. a PATH holding only luajit: git, flock and the usual tools are named
--      as missing, exit 1; Node and unshare are absent, not missing;
--   5. --quiet prints nothing but missing lines, and nothing at all on a
--      whole machine.
--
-- It needs no network and writes only a scratch folder of one link (under
-- RAO_TEST_ROOT, or /tmp), which it removes.
--
-- Run: luajit src/install/tests/231-test-what-a-home-needs.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>"; exit status
-- 0 only when nothing failed.

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/install/tests/[^/]+$")
end

local passed, failed = 0, 0

-- {{{ local function check
local function check(claim, ok, detail)
    if ok then
        passed = passed + 1
        print("PASS " .. claim)
    else
        failed = failed + 1
        print("FAIL " .. claim .. (detail and (": " .. tostring(detail):sub(1, 600)) or ""))
    end
end
-- }}}

-- {{{ local function quote / run
local function quote(text) return "'" .. text:gsub("'", "'\\''") .. "'" end
-- command → its output (stdout and stderr) and exit status, run from /.
local function run(command)
    local pipe = io.popen("cd / && " .. command .. " 2>&1; echo \"exit=$?\"")
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("exit=(%d+)%s*$"))
    return output:gsub("exit=%d+%s*$", ""), status
end
-- }}}

-- {{{ local function line_of
-- The line of the check's output for one need, or nil.
local function line_of(output, name)
    for line in output:gmatch("[^\n]+") do
        local word, rest = line:match("^(%S+)%s+" .. name:gsub("%p", "%%%0") .. "%s+(.*)$")
        if word then return word, rest end
    end
    return nil
end
-- }}}

local CHECK = "luajit " .. quote(DIR .. "/src/install/230-what-a-home-needs.lua") .. " " .. quote(DIR)
local LUAJIT = io.popen("command -v luajit"):read("*l")

-- 1. this machine
do
    local output, status = run(CHECK)
    check("1: every required thing is found on this machine, exit 0", status == 0, output)
    local word, says = line_of(output, "LuaJIT")
    check("1: LuaJIT is found, with the version it reported", word == "found" and says:find(jit.version, 1, true) ~= nil,
        says)
    word, says = line_of(output, "LuaSocket")
    local socket = require("socket")
    check("1: LuaSocket is found, with its own version and where socket.core is",
        word == "found" and says:find(socket._VERSION, 1, true) ~= nil and says:find("core.so", 1, true) ~= nil, says)
    word, says = line_of(output, "libcrypto")
    check("1: libcrypto is found, SHA-256 and AES-256-GCM answering", word == "found"
        and says:find("SHA-256 and AES-256-GCM answer", 1, true) ~= nil, says)
    word, says = line_of(output, "git")
    local git_version = io.popen("git --version 2>&1"):read("*l")
    check("1: git is found, with the version git gives", word == "found" and says:find(git_version, 1, true) ~= nil,
        says)
    check("1: flock and the usual tools are found",
        line_of(output, "flock") == "found" and line_of(output, "tools") == "found", output)
    check("1: the last line says every required thing is here",
        output:match("every required thing is here%s*$") ~= nil, output)
end

-- 2. no LuaSocket
do
    local output, status = run("LUA_PATH='/nonexistent/?.lua' LUA_CPATH='/nonexistent/?.so' " .. CHECK)
    local word, says = line_of(output, "LuaSocket")
    check("2: a LuaSocket the paths cannot find is MISSING, naming libs/, exit 1",
        status == 1 and word == "MISSING" and says:find(DIR .. "/libs/", 1, true) ~= nil, output)
    check("2: the last line names it", output:find("missing: LuaSocket", 1, true) ~= nil, output)
end

-- 3. no libcrypto
do
    local output, status = run("RAO_NEEDS_BROKEN=crypto " .. CHECK)
    local word, says = line_of(output, "libcrypto")
    check("3: a libcrypto that cannot load is MISSING, saying what to install, exit 1",
        status == 1 and word == "MISSING" and says:find("OpenSSL", 1, true) ~= nil, output)
    check("3: everything else is still found", line_of(output, "LuaSocket") == "found"
        and line_of(output, "git") == "found", output)
end

-- 4. a PATH holding only luajit
do
    local root = (os.getenv("RAO_TEST_ROOT") or "/tmp") .. "/231-only-luajit-" .. tostring(os.time())
    os.execute("mkdir -p " .. quote(root) .. " && ln -s " .. quote(LUAJIT) .. " " .. quote(root .. "/luajit"))
    local output, status = run("PATH=" .. quote(root) .. " " .. CHECK)
    check("4: git is MISSING with only luajit on the PATH", line_of(output, "git") == "MISSING", output)
    check("4: flock and setsid are MISSING", line_of(output, "flock") == "MISSING"
        and line_of(output, "setsid") == "MISSING", output)
    local word, says = line_of(output, "tools")
    check("4: the usual tools are MISSING, each named",
        word == "MISSING" and says:find("find", 1, true) ~= nil and says:find("mkdir", 1, true) ~= nil, says)
    check("4: Node and unshare are absent, not missing",
        line_of(output, "Node") == "absent" and line_of(output, "unshare") == "absent", output)
    check("4: exit 1, the last line naming git and flock", status == 1
        and (output:match("missing: ([^\n]*)%s*$") or ""):find("git, flock", 1, true) ~= nil, output)
    assert(root:match("/231%-only%-luajit%-%d+$"))
    os.execute("rm -rf " .. quote(root))
end

-- 5. --quiet
do
    local output, status = run(CHECK .. " --quiet")
    local found_any = false
    for line in output:gmatch("[^\n]+") do
        if line:match("^found ") or line:match("every required thing") then found_any = true end
    end
    check("5: --quiet on this machine prints no found line and no summary, exit 0",
        status == 0 and not found_any, output)
    output, status = run("RAO_NEEDS_BROKEN=crypto " .. CHECK .. " --quiet")
    local only_missing = true
    for line in output:gmatch("[^\n]+") do
        if line:match("^found ") then only_missing = false end
    end
    check("5: --quiet with a missing thing prints its line and the count, no found line",
        status == 1 and only_missing and line_of(output, "libcrypto") == "MISSING", output)
    output, status = run(CHECK .. " --loud")
    check("5: an unknown argument is refused, exit 2", status == 2 and output:find("--loud", 1, true) ~= nil, output)
end

print(string.format("counts %d %d", passed, failed))
os.exit(failed == 0 and 0 or 1)
