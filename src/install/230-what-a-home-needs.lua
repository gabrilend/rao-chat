-- 230-what-a-home-needs.lua — what a home needs on this machine, found or
-- named (issue 601).  It loads each thing the way the home's programs load
-- it and prints one line for each: found (with the version it reported),
-- MISSING (required: the home cannot run without it), or absent (only some
-- tools need it, and they are named).  It fetches and builds nothing.
--
--   luajit src/install/230-what-a-home-needs.lua [project folder] [--quiet]
--
-- With --quiet only the lines of things not found are printed.  Exit
-- status: 0 when every required thing is found, 1 otherwise, 2 for a
-- mistaken argument.
--
-- What it asks for, and why each is needed:
--
--   LuaJIT       every program of the home (the check runs on it, so it is
--                found; its ffi and bit are asked for by name)
--   LuaSocket    every program's network: require("socket"), with the
--                project's libs/ searched first (001), as the home does
--   libcrypto    sealing (124) and fingerprints (007): ffi.load("crypto"),
--                SHA-256 of "abc" compared with its known digest, and
--                AES-256-GCM asked for by name
--   git          each mailbox's repository (215): the starter and every
--                gatherer exit without it
--   flock        one launcher per home (603)
--   tools        find, sort, mkdir and the rest the programs run through
--                the shell
--   a RAM folder /dev/shm written to (161 falls back to /tmp and says so)
--   ss/netstat   the installer's port check (602) — skipped without
--   Node 22+     the web page's referees and the phase 4 demo only
--   unshare      the referees and demos only (a loopback-only namespace)
--
-- RAO_NEEDS_BROKEN=crypto asks for a library that cannot load in place of
-- libcrypto: a broken version for the referees (231); nothing else reads
-- it.

local quiet = false
local DIR
for _, argument in ipairs(arg) do
    if argument == "--quiet" then
        quiet = true
    elseif argument:sub(1, 1) == "-" then
        io.stderr:write("230-what-a-home-needs: unknown argument: " .. argument .. "\n")
        os.exit(2)
    elseif not DIR then
        DIR = argument
    else
        io.stderr:write("230-what-a-home-needs: one project folder only, got also " .. argument .. "\n")
        os.exit(2)
    end
end
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/install/[^/]+$")
end
DIR = DIR:gsub("/+$", "")

local lines = {}            -- each { word, name, says }
local missing_required = {}

-- {{{ local function report
-- One need's line.  found: true or false; required: whether the home
-- cannot run without it; says: what was found, or why not and what to do.
local function report(name, found, required, says)
    local word = found and "found" or (required and "MISSING" or "absent")
    lines[#lines + 1] = { word = word, name = name, says = says }
    if not found and required then missing_required[#missing_required + 1] = name end
end
-- }}}

-- {{{ local function shell
-- A command's first line of output (stderr joined), or nil.
local function shell(command)
    local pipe = io.popen(command .. " 2>&1")
    if not pipe then return nil end
    local line = pipe:read("*l")
    pipe:close()
    if line == nil or line == "" then return nil end
    return line
end
-- }}}

-- {{{ local function on_path
-- Where a command is found on this PATH, or nil.
local function on_path(name)
    local found = shell("command -v " .. name)
    if found and found:sub(1, 1) == "/" then return found end
    return nil
end
-- }}}

-- {{{ LuaJIT
do
    local ok_ffi = pcall(require, "ffi")
    local ok_bit = pcall(require, "bit")
    local version = (jit and jit.version) or _VERSION
    if jit and ok_ffi and ok_bit then
        report("LuaJIT", true, true, version .. " (ffi and bit) — every program of the home")
    else
        report("LuaJIT", false, true, version .. " is running this check, and the home needs LuaJIT"
            .. " (its ffi and bit): run it with luajit")
    end
end
-- }}}

-- {{{ LuaSocket
-- Searched as the home searches: the project's libs/ first (001), then
-- whatever LUA_PATH and LUA_CPATH, or the built-in paths, give.
do
    local load_path = DIR .. "/src/room-folders/001-load-path.lua"
    local loaded = io.open(load_path, "rb")
    if loaded then
        loaded:close()
        dofile(load_path)(DIR)
    end
    package.cpath = DIR .. "/libs/?.so;" .. package.cpath
    local ok, socket = pcall(require, "socket")
    if ok and type(socket) == "table" then
        local core = package.searchpath and package.searchpath("socket.core", package.cpath) or "socket.core"
        local through = ""
        local from_env = os.getenv("LUA_CPATH") or ""
        if core and from_env ~= "" then
            local folder = core:match("^(.*)/socket/core%.so$") or core
            if from_env:find(folder, 1, true) then
                through = "; found through LUA_CPATH, which a service does not see unless the home's"
                    .. " environment file names it (602)"
            end
        end
        report("LuaSocket", true, true, tostring(socket._VERSION) .. ", socket.core at " .. tostring(core)
            .. " — every program's network" .. through)
    else
        report("LuaSocket", false, true, "require(\"socket\") found nothing: install LuaSocket built for"
            .. " LuaJIT (Lua 5.1) with your system's packages, or put its socket.lua, socket/*.lua and"
            .. " socket/core.so in " .. DIR .. "/libs/ (searched first)")
    end
end
-- }}}

-- {{{ libcrypto
do
    local name = os.getenv("RAO_NEEDS_BROKEN") == "crypto" and "rao-chat-no-such-crypto" or "crypto"
    local ffi = require("ffi")
    for _, declaration in ipairs({
        "const char *OpenSSL_version(int type);",
        "unsigned char *SHA256(const unsigned char *data, size_t length, unsigned char *digest);",
        "typedef struct evp_cipher_st EVP_CIPHER;",
        "const EVP_CIPHER *EVP_aes_256_gcm(void);",
    }) do
        local ok, problem = pcall(ffi.cdef, declaration)
        if not ok and not tostring(problem):match("redefine") then error(problem) end
    end
    local ok, library = pcall(ffi.load, name)
    if not ok then
        report("libcrypto", false, true, "ffi.load(\"" .. name .. "\") failed (" .. tostring(library)
            .. "): install OpenSSL 1.1.1 or later (its libcrypto) with your system's packages")
    else
        local version_ok, version = pcall(function() return ffi.string(library.OpenSSL_version(0)) end)
        local digest = ffi.new("unsigned char[32]")
        local sha_ok = pcall(function() library.SHA256("abc", 3, digest) end)
        local hex = sha_ok and ffi.string(digest, 32):gsub(".", function(c) return string.format("%02x", c:byte()) end)
        local gcm_ok, gcm = pcall(function() return library.EVP_aes_256_gcm() end)
        local KNOWN = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        if hex == KNOWN and gcm_ok and gcm ~= nil then
            report("libcrypto", true, true, (version_ok and version or "a version older than 1.1.0")
                .. ": SHA-256 and AES-256-GCM answer — sealing (124) and fingerprints (007)")
        else
            report("libcrypto", false, true, "libcrypto loaded but "
                .. (hex ~= KNOWN and "its SHA-256 of \"abc\" was wrong or missing" or "it has no AES-256-GCM")
                .. ": install OpenSSL 1.1.1 or later")
        end
    end
end
-- }}}

-- {{{ git
do
    local version = on_path("git") and shell("git --version")
    if version and version:match("^git version") then
        report("git", true, true, version .. " — each mailbox's repository (215)")
    else
        report("git", false, true, "git is not on this PATH; the starter and every gatherer stop without"
            .. " it (215): install git with your system's packages")
    end
end
-- }}}

-- {{{ flock
do
    local where = on_path("flock")
    if where then
        report("flock", true, true, where .. " — one launcher per home (603)")
    else
        report("flock", false, true, "flock is not on this PATH; the launcher (603) holds a lock with it so"
            .. " one home is never run twice: it is part of util-linux")
    end
end
-- }}}

-- {{{ local function runnable
-- Whether the shell can run a command: on the PATH, or built into the
-- shell (kill is, in most), which is how the programs run it.
local function runnable(name)
    return shell("command -v " .. name) ~= nil
end
-- }}}

-- {{{ the usual tools
-- The commands the home's programs run through the shell (001 lists src/
-- with find and sort; the gatherers make, move and remove files with the
-- rest).  Every Linux has them; a PATH that lost them is named.
do
    local TOOLS = { "find", "sort", "ls", "mkdir", "rm", "mv", "cp", "touch", "chmod", "stat", "kill", "sleep" }
    local gone = {}
    for _, tool in ipairs(TOOLS) do
        if not runnable(tool) then gone[#gone + 1] = tool end
    end
    if #gone == 0 then
        report("tools", true, true, table.concat(TOOLS, " ") .. " — run by the home's programs through the shell")
    else
        report("tools", false, true, table.concat(gone, " ") .. " not on this PATH; the home's programs run them"
            .. " through the shell: they are coreutils, findutils and procps")
    end
end
-- }}}

-- {{{ a RAM folder
do
    local probe = "/dev/shm/.rao-chat-needs-" .. tostring(os.time()) .. "-" .. tostring(math.random(1e9))
    local f = io.open(probe, "wb")
    if f then
        f:close()
        os.remove(probe)
        report("RAM folder", true, false, "/dev/shm can be written — the gatherers' RAM folders (211)")
    else
        report("RAM folder", false, false, "/dev/shm cannot be written: the gatherers use /tmp/rao-chat-ram"
            .. " instead and say so (161), which may be on disk")
    end
end
-- }}}

-- {{{ ss or netstat
do
    local where = on_path("ss") or on_path("netstat")
    if where then
        report("ss/netstat", true, false, where .. " — the installer's port check (602)")
    else
        report("ss/netstat", false, false, "neither is on this PATH: the installer cannot check a port"
            .. " against what is listening, and says so (602)")
    end
end
-- }}}

-- {{{ Node
do
    local version = on_path("node") and shell("node --version")
    local major = version and tonumber(version:match("^v(%d+)"))
    if major and major >= 22 then
        report("Node", true, false, version .. " — the web page's referees and the phase 4 demo only")
    else
        report("Node", false, false, (version and ("Node " .. version .. " is older than 22") or "node is not"
            .. " on this PATH") .. ": needed only by the web page's referees (src/web/tests) and the"
            .. " phase 4 demo, never by a home")
    end
end
-- }}}

-- {{{ unshare
do
    local where = on_path("unshare")
    if where then
        report("unshare", true, false, where .. " — the referees and demos only (a loopback-only namespace)")
    else
        report("unshare", false, false, "not on this PATH: needed only by the referees and demos, never by"
            .. " a home")
    end
end
-- }}}

for _, line in ipairs(lines) do
    if not quiet or line.word ~= "found" then
        print(string.format("%-8s %-11s %s", line.word, line.name, line.says))
    end
end
if #missing_required == 0 then
    if not quiet then print("every required thing is here") end
    os.exit(0)
end
print(#missing_required .. " required thing" .. (#missing_required == 1 and " is" or "s are") .. " missing: "
    .. table.concat(missing_required, ", "))
os.exit(1)
