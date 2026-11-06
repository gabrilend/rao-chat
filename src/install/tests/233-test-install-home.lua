-- 233-test-install-home.lua — issue 602's referees: the installer
-- (scripts/install-home) making a home, run as a person would run it, with
-- a scratch HOME and a scratch folder for the homes.
--
--   1. unattended (--silent): a home 002 opens, holding every setting the
--      modules declare, the asked ones as given, the rest stated with their
--      questions; the direct-message mailbox on its port; the environment
--      file;
--   2. --silent missing a value stops before anything is written, naming
--      the flag;
--   3. ports: equal ports refused; a port something listens on (a stand-in
--      `ss` on the PATH) refused under --silent; asked, the suggestions are
--      free ports, not the same one;
--   4. re-run: the same answers change no byte; a hand-written comment and
--      a hand-changed setting survive; a new --device-port is written and
--      said; a new --direct-port moves the mailbox;
--   5. nothing but the home is written: the scratch HOME stays empty and
--      the program folder's git status is as it was;
--   6. a missing need (601 made to fail) stops it: exit 1, no home;
--   7. a home path holding a space, &, | and \ is made and named.
--
-- Run: luajit src/install/tests/233-test-install-home.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>"; exit status
-- 0 only when nothing failed.  Needs no network.

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/install/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)
local rooms = require("002-room-folders")

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

-- {{{ local function quote / run / read_all / write_file
local function quote(text) return "'" .. text:gsub("'", "'\\''") .. "'" end
local function run(command, input)
    -- input: what is typed at the questions; none: stdin is empty
    local feed = "printf '%s' " .. quote(input or "") .. " | "
    local pipe = io.popen("cd / && " .. feed .. "{ " .. command .. " ; } 2>&1; echo \"exit=$?\"")
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("exit=(%d+)%s*$"))
    return output:gsub("exit=%d+%s*$", ""), status
end
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
-- }}}

local ROOT = (os.getenv("RAO_TEST_ROOT") or "/tmp") .. "/233-install-home"
assert(ROOT:match("/233%-install%-home$"))
os.execute("rm -rf " .. quote(ROOT) .. " && mkdir -p " .. quote(ROOT .. "/home-of-user") .. " "
    .. quote(ROOT .. "/homes") .. " " .. quote(ROOT .. "/bin"))
local INSTALLER = quote(DIR .. "/scripts/install-home")
local ENV = "HOME=" .. quote(ROOT .. "/home-of-user") .. " "

-- {{{ local function snapshot
-- Every file under a folder with its SHA-256, sorted: one string.
local function snapshot(folder)
    local pipe = io.popen("cd " .. quote(folder) .. " 2>/dev/null && find . -type f -exec sha256sum {} + | sort")
    local text = pipe:read("*a")
    pipe:close()
    return text
end
-- }}}

-- {{{ local function settings_declared / first_variants
local declared = rooms.declared_settings()
local first = {}
do
    local listing = io.popen("ls " .. quote(DIR) .. "/src/*/[0-9][0-9][0-9]-options.lua")
    for path in listing:lines() do
        for _, choice in ipairs(dofile(path)) do
            if choice.config_key ~= "" then first[choice.config_key] = { choice.variants[1].name, choice.question } end
        end
    end
    listing:close()
end
-- }}}

local GIT_BEFORE = io.popen("git -C " .. quote(DIR) .. " status --porcelain 2>&1"):read("*a")

-- 1. unattended
local A = ROOT .. "/homes/a"
local A_ARGS = " --silent --home=" .. quote(A) .. " --home-name=alice --device-port=51234 --direct-port=52345"
    .. " --address=127.0.0.2"
do
    local output, status = run(ENV .. INSTALLER .. A_ARGS)
    check("1: --silent with every value makes the home, exit 0", status == 0, output)
    local ok, home = pcall(rooms.open_home, A)
    check("1: the home opens", ok, home)
    local config = ok and rooms.read_config(home) or {}
    local all, missing = true, {}
    for key in pairs(declared) do
        if config[key] == nil then all = false; missing[#missing + 1] = key end
    end
    check("1: every declared setting is in the config", all, table.concat(missing, ", "))
    check("1: the asked settings are as given", config["git.home-name"] == "alice" and config["devices.port"] == "51234"
        and config["gatherer.address"] == "127.0.0.2" and config["devices.address"] == "127.0.0.2", output)
    local stated_ok, wrong = true, {}
    for key, variant in pairs(first) do
        local asked = key == "git.home-name" or key == "devices.port" or key:match("%.address$")
        if not asked and config[key] ~= variant[1] then stated_ok = false; wrong[#wrong + 1] = key end
    end
    check("1: every other setting is its options file's first variant", stated_ok, table.concat(wrong, ", "))
    local text = read_all(A .. "/config") or ""
    local question = first["delivery.retry-floor"][2]
    check("1: a stated setting is under its question", text:find("# " .. question .. "\n# (the first of", 1, true)
        ~= nil and text:find("delivery.retry-floor = ", 1, true) ~= nil, text:sub(1, 600))
    local direct = ok and rooms.read_mailbox(home, rooms.direct_mailbox(home))
    check("1: the direct-message mailbox is on its port", direct and direct.port == 52345, output)
    local env = read_all(A .. "/environment") or ""
    local luajit_dir = io.popen("dirname \"$(command -v luajit)\""):read("*l")
    check("1: the environment file holds a PATH naming luajit's folder",
        env:match("\nPATH=[^\n]*") ~= nil and env:find(luajit_dir, 1, true) ~= nil, env)
    check("1: the output names the folder, the ports and how to pair",
        output:find("51234 (your phones and browsers)", 1, true) ~= nil
        and output:find("52345 (the direct-message mailbox)", 1, true) ~= nil
        and output:find("189-pair.lua", 1, true) ~= nil, output)
end

-- 2. --silent with a value missing
do
    local B = ROOT .. "/homes/b"
    local output, status = run(ENV .. INSTALLER .. " --silent --home=" .. quote(B)
        .. " --home-name=bo --direct-port=52346 --address=any")
    check("2: --silent without --device-port stops, exit 1, naming the flag",
        status == 1 and output:find("--device-port", 1, true) ~= nil, output)
    check("2: nothing was written: no home folder", io.open(B, "rb") == nil, output)
    output, status = run(ENV .. INSTALLER .. " --silent --home-name=bo --device-port=1 --direct-port=2 --address=any")
    check("2: --silent without --home stops, naming it", status == 1 and output:find("--home=", 1, true) ~= nil, output)
    output, status = run(ENV .. INSTALLER .. " --silent --colour=blue")
    check("2: an unknown flag is refused, exit 2", status == 2 and output:find("--colour", 1, true) ~= nil, output)
end

-- 3. ports
do
    local C = ROOT .. "/homes/c"
    local output, status = run(ENV .. INSTALLER .. " --silent --home=" .. quote(C)
        .. " --home-name=cy --device-port=53000 --direct-port=53000 --address=any")
    check("3: equal ports are refused, exit 1, no home", status == 1 and io.open(C .. "/config", "rb") == nil
        and output:find("other port", 1, true) ~= nil, output)
    -- a stand-in ss: every port from 50000 to 64000 is listening
    local lines = {}
    for port = 50000, 64000 do lines[#lines + 1] = "LISTEN 0 4096 0.0.0.0:" .. port .. " 0.0.0.0:*" end
    write_file(ROOT .. "/bin/listening", table.concat(lines, "\n") .. "\n")
    write_file(ROOT .. "/bin/ss", "#!/bin/sh\ncat " .. quote(ROOT .. "/bin/listening") .. "\n")
    os.execute("chmod +x " .. quote(ROOT .. "/bin/ss"))
    local WITH_SS = "PATH=" .. quote(ROOT .. "/bin") .. ":\"$PATH\" "
    output, status = run(WITH_SS .. ENV .. INSTALLER .. " --silent --home=" .. quote(C)
        .. " --home-name=cy --device-port=55555 --direct-port=64500 --address=any")
    check("3: a port something listens on is refused under --silent, saying what holds it",
        status == 1 and output:find("already listening on port 55555", 1, true) ~= nil
        and io.open(C .. "/config", "rb") == nil, output)
    -- asked: Enter takes each suggestion
    output, status = run(WITH_SS .. ENV .. INSTALLER .. " --home=" .. quote(C) .. " --home-name=cy --address=any",
        "\n\n")
    local ok, home = pcall(rooms.open_home, C)
    local device = ok and tonumber(rooms.read_config(home)["devices.port"])
    local direct = ok and rooms.read_mailbox(home, rooms.direct_mailbox(home)).port
    check("3: asked, Enter takes free suggestions (none of the listening ones), two different ports",
        status == 0 and device and direct and device > 64000 and direct > 64000 and device <= 65000
        and direct <= 65000 and device ~= direct, output)
    output, status = run(ENV .. INSTALLER .. " --home=" .. quote(ROOT .. "/homes/d") .. " --home-name=dee", "")
    check("3: asked, input that ends is no answer: exit 1, nothing written",
        status == 1 and io.open(ROOT .. "/homes/d", "rb") == nil and output:find("input ended", 1, true) ~= nil,
        output)
end

-- 4. re-run
do
    local before = snapshot(A)
    local output, status = run(ENV .. INSTALLER .. A_ARGS)
    check("4: the same answers again: exit 0, every line kept", status == 0
        and output:find("kept     devices.port = 51234", 1, true) ~= nil and not output:find("changed", 1, true), output)
    check("4: the same answers change no byte of the home", snapshot(A) == before, snapshot(A))
    -- by hand: a comment, and a setting changed
    local text = read_all(A .. "/config")
    text = text:gsub("crosscheck%.interval = %d+", "# checked every half hour, by hand\ncrosscheck.interval = 1800")
    write_file(A .. "/config", text)
    output, status = run(ENV .. INSTALLER .. A_ARGS:gsub("51234", "51240"):gsub("52345", "52350"))
    local after = read_all(A .. "/config") or ""
    check("4: a hand-written comment and a hand-changed setting survive",
        after:find("# checked every half hour, by hand\ncrosscheck.interval = 1800", 1, true) ~= nil, after)
    check("4: a new --device-port is written and said as changed", status == 0
        and output:find("changed  devices.port 51234 -> 51240", 1, true) ~= nil
        and after:find("\ndevices.port = 51240\n", 1, true) ~= nil, output)
    local home = rooms.open_home(A)
    check("4: a new --direct-port moves the direct-message mailbox",
        rooms.read_mailbox(home, rooms.direct_mailbox(home)).port == 52350
        and output:find("moved    the direct-message mailbox from port 52345 to 52350", 1, true) ~= nil, output)
end

-- 5. nothing but the home
do
    check("5: the scratch HOME holds nothing", snapshot(ROOT .. "/home-of-user") == "", snapshot(ROOT .. "/home-of-user"))
    local after = io.popen("git -C " .. quote(DIR) .. " status --porcelain 2>&1"):read("*a")
    check("5: the program folder's git status is as it was", after == GIT_BEFORE, after)
end

-- 6. a missing need
do
    local E = ROOT .. "/homes/e"
    local output, status = run("RAO_NEEDS_BROKEN=crypto " .. ENV .. INSTALLER .. " --silent --home=" .. quote(E)
        .. " --home-name=ed --device-port=53001 --direct-port=53002 --address=any")
    check("6: a missing libcrypto stops it, exit 1, naming it, no home",
        status == 1 and output:find("MISSING  libcrypto", 1, true) ~= nil and io.open(E, "rb") == nil, output)
end

-- 7. a path holding a space, &, | and \
do
    local odd = ROOT .. "/homes/a b&c|d\\e"
    os.execute("mkdir -p " .. quote(odd))
    local F = odd .. "/home"
    local output, status = run(ENV .. INSTALLER .. " --silent --home=" .. quote(F)
        .. " --home-name=fay --device-port=53003 --direct-port=53004 --address=any")
    local ok, home = pcall(rooms.open_home, F)
    check("7: a home path holding a space, &, | and \\ is made, exit 0", status == 0 and ok
        and rooms.read_config(home)["devices.port"] == "53003", output)
    check("7: the summary names the folder as it is", output:find("folder:       " .. F .. "\n", 1, true) ~= nil, output)
end

os.execute("rm -rf " .. quote(ROOT))
print(string.format("counts %d %d", passed, failed))
os.exit(failed == 0 and 0 or 1)
