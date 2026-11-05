-- 161-ram-folders.lua — one mailbox's RAM folder: its layout, the
-- hand-off rule between stages, `state`, the running log, loading the
-- mailbox from disk and syncing it back (issue 211, steps 1 and 2).
--
-- Layout, under the home's RAM folder (`<gatherer.ram-root>/<home id>/`,
-- see home_ram) and then one folder per mailbox tag:
--
--   home/            a rao-home: copies of the disk home's own files
--                    (config, mailboxes, ignore, outside-ports, ...: read
--                    only, reloaded every sync cycle) and rooms/<tag>/ for
--                    this mailbox's rooms only.  Phase 1's and 2's modules
--                    run on it unchanged, through open_home(<this path>).
--   arrived/         one file per frame read off the port (listener → filer)
--   answers/         one file per answer ready, named after its arrived/
--                    file (filer → listener)
--   typed/           one file per message the person typed (viewer → filer)
--   due/             one file per (address, port) pair with something to
--                    send, rewritten after every sender pass (sender → viewer)
--   running-log      the gatherer's own lines
--   failed-decryption*  203's files (139)
--   state            `name = value` lines: pid, started, last-sync, each
--                    folder's pile, and one `problem.<name>` line per
--                    distinct problem, rewritten in place
--
-- The hand-off rule.  A file is written under a temporary name starting
-- with "." and renamed into place (put), so a stage never sees half a
-- file; a stage takes a file by renaming it into the folder's `working/`
-- (take), so two workers never take the same one; at start-up anything
-- left in a `working/` folder goes back to its queue (return_working).
-- Names sort in arrival order: <seconds>-<sequence>-<random>.
--
-- Syncing.  `load` copies the disk home into home/ and remembers what each
-- file held.  `sync` writes back every file of this mailbox's rooms that
-- changed in RAM, and reloads the read-only home-wide copies.  A disk file
-- that changed by hand since it was loaded or last synced is not written
-- over: the sync leaves it, says so in a `problem.hand-edit` line, and
-- carries on with the rest (decision of 2026-11-05 for open question 3).
-- `force_to_disk` writes one file to disk and fsyncs it and its folder
-- (gatherer.acknowledge-after = disk).

local ffi = require("ffi")
local disk = require("003-disk")
local tokens = require("007-tokens")

ffi.cdef [[
int open(const char *path, int flags, int mode);
int fsync(int fd);
int close(int fd);
]]

local M = {}

M.QUEUES = { "arrived", "answers", "typed", "due" }

-- {{{ local function hex
local function hex(bytes)
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
-- }}}

-- {{{ local function mkdir_p
local function mkdir_p(path)
    local ok = os.execute("mkdir -p " .. disk.shell_quote(path))
    if ok ~= 0 and ok ~= true then error("cannot make folder " .. path, 2) end
end
-- }}}

-- {{{ function M.home_id
-- The disk home's absolute path → the name of its RAM folder: the home
-- folder's own name and 12 hex of SHA-256 of its path, so two homes with
-- one name on one machine never share a RAM folder (R20).
function M.home_id(home_dir)
    local name = home_dir:gsub("/+$", ""):match("([^/]+)$") or "home"
    name = name:gsub("[^%w%-_.]", "-")
    return name .. "-" .. hex(tokens.sha256(home_dir)):sub(1, 12)
end
-- }}}

-- {{{ function M.home_ram
-- ram_root, home_dir → the home's RAM folder.
function M.home_ram(ram_root, home_dir)
    if os.getenv("RAO_GATHERER_BROKEN") == "fixed-folder" then
        return ram_root:gsub("/+$", "") .. "/shared"      -- referee 8's broken version
    end
    return ram_root:gsub("/+$", "") .. "/" .. M.home_id(home_dir)
end
-- }}}

-- {{{ function M.choose_root
-- The configured gatherer.ram-root, made if missing.  When it cannot be
-- made (no /dev/shm on this system), the fallback under /tmp is used and
-- the reason given back, so the caller can say so (decision of
-- 2026-11-05: the RAM folder may then be on disk).  → root, why or nil.
M.FALLBACK = "/tmp/rao-chat-ram"
function M.choose_root(configured)
    if type(configured) ~= "string" or configured:sub(1, 1) ~= "/" then
        error("gatherer.ram-root must be an absolute path, got " .. tostring(configured), 2)
    end
    if os.execute("mkdir -p " .. disk.shell_quote(configured) .. " 2>/dev/null && test -w "
                  .. disk.shell_quote(configured)) == 0 then
        return configured
    end
    mkdir_p(M.FALLBACK)
    return M.FALLBACK, "gatherer.ram-root " .. configured .. " cannot be made or written; using "
        .. M.FALLBACK .. ", which may not be in RAM"
end
-- }}}

-- {{{ function M.layout
-- home_ram, mailbox_tag → the mailbox's folder, made with its queues.
function M.layout(home_ram, mailbox_tag)
    local folder = home_ram .. "/" .. mailbox_tag
    for _, queue in ipairs(M.QUEUES) do mkdir_p(folder .. "/" .. queue .. "/working") end
    mkdir_p(folder .. "/home")
    return folder
end
-- }}}

local sequence = 0

-- {{{ function M.new_name
-- now → a name that sorts by arrival: seconds, a sequence, random.
function M.new_name(now)
    sequence = sequence + 1
    local source = assert(io.open("/dev/urandom", "rb"))
    local random = hex(source:read(4))
    source:close()
    return string.format("%010d-%06d-%s", math.floor(now), sequence % 1000000, random)
end
-- }}}

-- {{{ function M.put
-- queue folder, name, bytes: written as ".<name>.tmp", renamed to name.
function M.put(queue, name, bytes)
    local temporary = queue .. "/." .. name .. ".tmp"
    local handle = assert(io.open(temporary, "wb"))
    handle:write(bytes)
    handle:close()
    assert(os.rename(temporary, queue .. "/" .. name))
end
-- }}}

-- {{{ function M.waiting
-- queue folder → the names ready to take, oldest first (temporary names,
-- which start with ".", and working/ are left out).
function M.waiting(queue)
    local names = {}
    local listing = io.popen("ls -1 " .. disk.shell_quote(queue) .. " 2>/dev/null")
    for name in listing:lines() do
        if name:sub(1, 1) ~= "." and name ~= "working" then names[#names + 1] = name end
    end
    listing:close()
    table.sort(names)
    return names
end
-- }}}

-- {{{ function M.take
-- queue, name → the bytes and the path it now has under working/, or nil
-- when another worker took it first (its rename failed).
function M.take(queue, name)
    local taken = queue .. "/working/" .. name
    if not os.rename(queue .. "/" .. name, taken) then return nil end
    local handle = assert(io.open(taken, "rb"))
    local bytes = handle:read("*a")
    handle:close()
    return bytes, taken
end
-- }}}

-- {{{ function M.return_working
-- queue → how many files left in working/ went back to the queue (at
-- start-up: the process that took them is gone).
function M.return_working(queue)
    local count = 0
    for _, name in ipairs(M.waiting(queue .. "/working")) do
        assert(os.rename(queue .. "/working/" .. name, queue .. "/" .. name))
        count = count + 1
    end
    return count
end
-- }}}

-- {{{ function M.pile
-- queue → how many files wait in it, working/ included.
function M.pile(queue)
    return #M.waiting(queue) + #M.waiting(queue .. "/working")
end
-- }}}

------------------------------------------------------------------------------
-- Arrived frames: mailbox tag, source address, source port, arrival time,
-- frame bytes (the frame without its 4 length bytes).
------------------------------------------------------------------------------

-- {{{ function M.encode_arrived
function M.encode_arrived(mailbox, host, port, at, after)
    return string.format("%s\n%s\n%d\n%d\n", mailbox, host, port, at) .. after
end
-- }}}

-- {{{ function M.decode_arrived
-- bytes → {mailbox, host, port, at, after}, or nil and why: each field
-- checked, since the folder is input from another stage.
function M.decode_arrived(bytes)
    local mailbox, host, port, at, rest = bytes:match("^(%x+)\n([^\n]+)\n(%d+)\n(%d+)\n()")
    if not mailbox then return nil, "not an arrived file" end
    if #mailbox ~= 32 then return nil, "the mailbox tag is not 32 hex" end
    if #host > 255 or host:find("[%s%c]") then return nil, "the source address is not one" end
    port, at = tonumber(port), tonumber(at)
    if port < 1 or port > 65535 then return nil, "the source port is out of range" end
    return { mailbox = mailbox, host = host, port = port, at = at, after = bytes:sub(rest) }
end
-- }}}

------------------------------------------------------------------------------
-- Typed messages: "room = <local tag>", a blank line, the text (until
-- 301 sets the viewer's format; decision of 2026-11-05).
------------------------------------------------------------------------------

-- {{{ function M.decode_typed
function M.decode_typed(bytes)
    local tag, text = bytes:match("^room = (%x+)\n\n(.*)$")
    if not tag or #tag ~= 32 then return nil, "a typed file starts with \"room = <local tag>\" and a blank line" end
    return { room = tag, text = text:gsub("\n$", "") }
end
-- }}}

------------------------------------------------------------------------------
-- state and the running log
------------------------------------------------------------------------------

-- {{{ function M.read_state
-- folder → {name = value} from its state file (empty when there is none).
function M.read_state(folder)
    local values = {}
    local handle = io.open(folder .. "/state", "rb")
    if not handle then return values end
    for line in handle:lines() do
        local name, value = line:match("^([%w%.%-_]+) = (.*)$")
        if name then values[name] = value end
    end
    handle:close()
    return values
end
-- }}}

-- {{{ function M.write_state
-- folder, values: the whole file rewritten in one step, names sorted.
function M.write_state(folder, values)
    local names = {}
    for name in pairs(values) do names[#names + 1] = name end
    table.sort(names)
    local lines = {}
    for _, name in ipairs(names) do
        lines[#lines + 1] = name .. " = " .. tostring(values[name]):gsub("\n", " ")
    end
    disk.write_atomic(folder .. "/state", table.concat(lines, "\n") .. "\n")
end
-- }}}

-- {{{ function M.log
-- folder, now, words: one line appended to the running log.
function M.log(folder, now, words)
    local handle = io.open(folder .. "/running-log", "ab")
    if not handle then return end
    handle:write(os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(now)), " ", (tostring(words):gsub("\n", " ")), "\n")
    handle:close()
end
-- }}}

------------------------------------------------------------------------------
-- Loading and syncing
------------------------------------------------------------------------------

-- {{{ local function read_file
local function read_file(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end
-- }}}

-- {{{ local function files_under
-- folder → every plain file under it, as paths relative to it, sorted.
local function files_under(folder)
    local list = {}
    local listing = io.popen("cd " .. disk.shell_quote(folder) .. " 2>/dev/null && find . -type f ! -name '*.tmp-*' | sort")
    for line in listing:lines() do list[#list + 1] = line:sub(3) end
    listing:close()
    return list
end
-- }}}

-- {{{ local function top_files
-- folder → its own plain files (not those in sub-folders).
local function top_files(folder)
    local list = {}
    local listing = io.popen("find " .. disk.shell_quote(folder) .. " -mindepth 1 -maxdepth 1 -type f ! -name '*.tmp-*' -printf '%f\\n' | sort")
    for line in listing:lines() do list[#list + 1] = line end
    listing:close()
    return list
end
-- }}}

-- {{{ local function copy_into
local function copy_into(from, to, text)
    mkdir_p(to:match("^(.*)/[^/]+$"))
    disk.write_atomic(to, text or read_file(from) or "")
end
-- }}}

-- {{{ function M.load
-- disk_dir (the disk home), ram_home (home/ in the mailbox folder),
-- room_tags (this mailbox's rooms) → a sync record {disk_dir, ram_home,
-- known = {relative path → what the disk held}, wide = {home-wide name →
-- contents}}, and whether RAM was kept.
--
-- A RAM home a previous process of this mailbox loaded (it has `.loaded`)
-- is kept: it is newer than disk, and a gatherer crash must lose nothing
-- (RAM files outlive the process).  Only the home-wide copies are
-- reloaded, and the disk's contents become what a later sync compares
-- against.  Otherwise (a fresh boot: RAM empty) the rooms are copied in.
function M.load(disk_dir, ram_home, room_tags)
    local record = { disk_dir = disk_dir, ram_home = ram_home, rooms = room_tags, known = {}, wide = {} }
    local kept = read_file(ram_home .. "/.loaded") ~= nil
    if not kept then
        os.execute("rm -rf " .. disk.shell_quote(ram_home) .. " && mkdir -p " .. disk.shell_quote(ram_home .. "/rooms"))
    end
    for _, name in ipairs(top_files(disk_dir)) do
        local text = read_file(disk_dir .. "/" .. name) or ""
        copy_into(nil, ram_home .. "/" .. name, text)
        record.wide[name] = text
    end
    for _, tag in ipairs(room_tags) do
        local base = "rooms/" .. tag
        mkdir_p(ram_home .. "/" .. base)
        for _, relative in ipairs(files_under(disk_dir .. "/" .. base)) do
            local text = read_file(disk_dir .. "/" .. base .. "/" .. relative) or ""
            if not kept then copy_into(nil, ram_home .. "/" .. base .. "/" .. relative, text) end
            record.known[base .. "/" .. relative] = text
        end
    end
    copy_into(nil, ram_home .. "/.loaded", "")
    return record, kept
end
-- }}}

-- {{{ function M.force_to_disk
-- path, text: written under a temporary name, fsynced, renamed, and the
-- folder fsynced, so it survives a power cut once this returns.
function M.force_to_disk(path, text)
    local folder = path:match("^(.*)/[^/]+$")
    mkdir_p(folder)
    local temporary = path .. ".tmp-sync"
    local handle = assert(io.open(temporary, "wb"))
    handle:write(text)
    handle:close()
    local fd = ffi.C.open(temporary, 2, 0)            -- O_RDWR
    if fd >= 0 then ffi.C.fsync(fd); ffi.C.close(fd) end
    assert(os.rename(temporary, path))
    fd = ffi.C.open(folder, 0, 0)                      -- O_RDONLY
    if fd >= 0 then ffi.C.fsync(fd); ffi.C.close(fd) end
end
-- }}}

-- {{{ function M.sync_file
-- record, relative path → "written", "same", or "hand-edit" (the disk
-- copy changed since it was loaded or last synced: left as it is).
function M.sync_file(record, relative, force)
    local ram_text = read_file(record.ram_home .. "/" .. relative)
    if ram_text == nil then return "same" end
    local disk_path = record.disk_dir .. "/" .. relative
    local disk_text = read_file(disk_path)
    if ram_text == disk_text then
        record.known[relative] = ram_text
        return "same"
    end
    if disk_text ~= record.known[relative] then return "hand-edit" end
    if force then M.force_to_disk(disk_path, ram_text) else copy_into(nil, disk_path, ram_text) end
    record.known[relative] = ram_text
    return "written"
end
-- }}}

-- {{{ function M.sync
-- record → {written = n, hand_edits = {relative paths}, reloaded = {names}}.
-- RAM → disk for this mailbox's rooms; disk → RAM for the home-wide files.
function M.sync(record)
    local result = { written = 0, hand_edits = {}, reloaded = {} }
    -- every room in RAM: those loaded, and any made since (a join)
    local tags = {}
    local listing = io.popen("ls -1 " .. disk.shell_quote(record.ram_home .. "/rooms") .. " 2>/dev/null")
    for tag in listing:lines() do tags[#tags + 1] = tag end
    listing:close()
    for _, tag in ipairs(tags) do
        for _, relative in ipairs(files_under(record.ram_home .. "/rooms/" .. tag)) do
            local outcome = "same"
            if not (relative == "entry" and os.getenv("RAO_GATHERER_BROKEN") == "skip-entry") then
                -- (skip-entry: referee 9's broken version)
                outcome = M.sync_file(record, "rooms/" .. tag .. "/" .. relative)
            end
            if outcome == "written" then result.written = result.written + 1 end
            if outcome == "hand-edit" then result.hand_edits[#result.hand_edits + 1] = "rooms/" .. tag .. "/" .. relative end
        end
    end
    for _, name in ipairs(top_files(record.disk_dir)) do
        local text = read_file(record.disk_dir .. "/" .. name) or ""
        if text ~= record.wide[name] then
            copy_into(nil, record.ram_home .. "/" .. name, text)
            record.wide[name] = text
            result.reloaded[#result.reloaded + 1] = name
        end
    end
    return result
end
-- }}}

return M
