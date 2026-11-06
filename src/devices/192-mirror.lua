-- 192-mirror.lua — the viewer's folder as a device mirrors it (issue 304;
-- 301 decision 23: sealed catching up per room, not a synchronised
-- folder).  Shared by the home's side (187) and the device's (190), so
-- both list, check and digest the folder by one rule.
--
-- What is mirrored is 301's layout, and nothing else of the home's RAM
-- folder (never `home/`, the queues, the logs or `devices/`):
--
--   <mailbox>/state                     the gatherer's state
--   <mailbox>/inbox/.tree               the mailbox's rooms
--   <mailbox>/inbox/<room>/.room        a room's facts
--   <mailbox>/inbox/<room>/<written>-<id>   one file per message
--
-- A mailbox and a room are 32 hex; a message name is 301's
-- `<written>-<id>`: whole seconds, a dash, an id in 105's alphabet
-- (letters, digits, `-`, `_`), at most 128 characters, as 181 writes it
-- (decision 4 of issue 304).  `check_path` is the one test every path
-- from the network passes before it is used: anything else — "..", a
-- leading "/", a dot file that is not `.tree` or `.room`, a name with a
-- space — is refused.
--
-- A room's position is the name of the last message file held (names
-- sort as the room's order, 301); its digest is SHA-256 (hex) over the
-- lines "<name> <SHA-256 hex of the file>\n" of the files held up to and
-- including that position, sorted by name (304: the device digests what
-- it holds; the home, its own files up to the device's position).

local disk = require("003-disk")
local tokens = require("007-tokens")
local ram = require("161-ram-folders")

local M = {}

M.MOST_ID = 128
M.NO_FILES = "-"     -- a position before any message

-- {{{ local function hex
local function hex(bytes)
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
-- }}}

-- {{{ local function is_tag
local function is_tag(text)
    return type(text) == "string" and #text == 32 and text:match("^%x+$") ~= nil
end
M.is_tag = is_tag
-- }}}

-- {{{ function M.is_message_name
function M.is_message_name(name)
    if type(name) ~= "string" then return false end
    local written, id = name:match("^(%d+)%-([%w_%-]+)$")
    return written ~= nil and #written <= 15 and #id <= M.MOST_ID
end
-- }}}

-- {{{ function M.check_path
-- a relative path → its kind ("state", "tree", "room", "message") and
-- { mailbox, room, name }; or nil and why.
function M.check_path(path)
    if type(path) ~= "string" or #path > 300 then return nil, "not a path" end
    local parts = {}
    for part in (path .. "/"):gmatch("([^/]*)/") do parts[#parts + 1] = part end
    local mailbox = parts[1]
    if not is_tag(mailbox) then return nil, "'" .. path:sub(1, 80) .. "' does not start with a 32-hex mailbox" end
    if #parts == 2 and parts[2] == "state" then return "state", { mailbox = mailbox } end
    if parts[2] ~= "inbox" then return nil, "'" .. path:sub(1, 80) .. "' is not in 301's layout" end
    if #parts == 3 and parts[3] == ".tree" then return "tree", { mailbox = mailbox } end
    if #parts ~= 4 or not is_tag(parts[3]) then
        return nil, "'" .. path:sub(1, 80) .. "' names no 32-hex room"
    end
    local where = { mailbox = mailbox, room = parts[3], name = parts[4] }
    if parts[4] == ".room" then return "room", where end
    if M.is_message_name(parts[4]) then return "message", where end
    return nil, "'" .. path:sub(1, 80) .. "' is not a message file's name"
end
-- }}}

-- {{{ function M.hash
-- text → 64 hex of its SHA-256.
function M.hash(text) return hex(tokens.sha256(text)) end
-- }}}

-- {{{ function M.digest
-- list of {name, hash}, sorted by name → 64 hex.
function M.digest(entries)
    local lines = {}
    for i, entry in ipairs(entries) do lines[i] = entry.name .. " " .. entry.hash .. "\n" end
    return M.hash(table.concat(lines))
end
-- }}}

-- {{{ function M.read_file
function M.read_file(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end
-- }}}

-- {{{ function M.listing
-- root folder → { [relative path] = "<size> <modified>" } for every file
-- in the mirrored layout (one `find`, so a listing is cheap; a listing is
-- a hint to re-read, never the record of what changed), and the paths
-- sorted.  Temporary files (161's ".<name>.tmp") never pass check_path.
function M.listing(root)
    local found, paths = {}, {}
    local listing = io.popen("find " .. disk.shell_quote(root)
        .. " -mindepth 2 -maxdepth 4 -type f -printf '%P\\t%s %T@\\n' 2>/dev/null")
    for line in listing:lines() do
        local path, stamp = line:match("^([^\t]+)\t(.*)$")
        if path and M.check_path(path) then
            found[path] = stamp
            paths[#paths + 1] = path
        end
    end
    listing:close()
    table.sort(paths)
    return found, paths
end
-- }}}

-- {{{ function M.rooms
-- root folder → { [room] = { mailbox, names (sorted message names) } },
-- from one listing.  A room whose folder holds only `.room` has names {}.
function M.rooms(root, paths)
    if not paths then paths = select(2, M.listing(root)) end
    local rooms = {}
    for _, path in ipairs(paths) do
        local kind, where = M.check_path(path)
        if kind == "room" or kind == "message" then
            local room = rooms[where.room]
            if not room then
                room = { mailbox = where.mailbox, names = {} }
                rooms[where.room] = room
            end
            if kind == "message" then room.names[#room.names + 1] = where.name end
        end
    end
    for _, room in pairs(rooms) do table.sort(room.names) end
    return rooms
end
-- }}}

-- {{{ function M.entries
-- root, mailbox, room, names, position (nil: all) → list of {name, hash}
-- for the names up to and including the position.
function M.entries(root, mailbox, room, names, position)
    local list = {}
    for _, name in ipairs(names) do
        if position and name > position then break end
        local text = M.read_file(root .. "/" .. mailbox .. "/inbox/" .. room .. "/" .. name)
        if text then list[#list + 1] = { name = name, hash = M.hash(text) } end
    end
    return list
end
-- }}}

-- {{{ function M.positions_text
-- a device's mirror → the `rooms` field of its catch-up: one line per
-- room holding a message, "<room> <last name> <digest>", sorted by room.
function M.positions_text(root)
    local rooms = M.rooms(root)
    local tags = {}
    for tag, room in pairs(rooms) do if #room.names > 0 then tags[#tags + 1] = tag end end
    table.sort(tags)
    local lines = {}
    for _, tag in ipairs(tags) do
        local room = rooms[tag]
        local entries = M.entries(root, room.mailbox, tag, room.names)
        lines[#lines + 1] = tag .. " " .. room.names[#room.names] .. " " .. M.digest(entries)
    end
    return table.concat(lines, "\n")
end
-- }}}

-- {{{ function M.read_positions
-- the `rooms` field → { [room] = { last, digest } }, or nil and why.
function M.read_positions(text)
    local positions = {}
    if text == "" then return positions end
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local tag, last, digest = line:match("^(%x+) (%S+) (%x+)$")
        if not (tag and is_tag(tag) and M.is_message_name(last) and #digest == 64) then
            return nil, "a catch-up line is '<room> <last name> <digest>', not '" .. line:sub(1, 60) .. "'"
        end
        if positions[tag] then return nil, "a catch-up names room " .. tag .. " twice" end
        positions[tag] = { last = last, digest = digest }
    end
    return positions
end
-- }}}

-- {{{ function M.write
-- root, relative path (checked by the caller), text → true when the file
-- changed.  Written under a temporary name and renamed (161's put), so a
-- viewer reading the mirror never sees half a file (211's rule).
function M.write(root, path, text)
    local full = root .. "/" .. path
    if M.read_file(full) == text then return false end
    local folder = full:match("^(.*)/[^/]+$")
    if not disk.is_dir(folder) then os.execute("mkdir -p " .. disk.shell_quote(folder)) end
    ram.put(folder, full:match("([^/]+)$"), text)
    return true
end
-- }}}

return M
