-- 030-stand-in-room-folders.lua — a small copy of the room-folders module
-- (issue 101), used only by the room-tree tests while the real one is being
-- rewritten for "a room is a contact" (round 2; kept in step since).
--
-- The room tree needs somewhere to keep rooms: a home folder with a config
-- file and one folder per room, named by a random local tag, holding one
-- `entry` (the room's label, token, kind, member addresses, declared parent
-- and your own filing), plus a bell that rings when any of those change and
-- a way to turn a token into its fingerprint.  This file does just enough
-- of that, following issue 101, so the tree can be tested before the real
-- module is rewritten.  The tests can be pointed at the real module
-- instead, and should give the same answers.
--
-- Data shapes (as the contract's "The entry" describes them, unquoted
-- here because only this stand-in reads them back):
--   rooms/<tag>/entry   one entry named by the local tag:
--                         <tag>.label, .token, .kind (group | direct),
--                         .parent (fingerprint or empty),
--                         .filed-under (local tag or empty),
--                         .ip[N] / .port[N] / .heard[N], N from 1
--   rooms/<tag>/log, withheld   empty files made with the room
--   config              "key = value" lines
--
-- The fingerprint here is NOT the real one (SHA-256 twice): it is a
-- 64-bit FNV-1a hash written four times over to 64 hex characters, which
-- is deterministic and the same on every home for the same token — the
-- only properties the tree relies on.

local bit = require("bit")

local M = {}

-- listeners registered with on_change, in the order they were registered
local listeners = {}

local KINDS = {
    ["created"] = true, ["label"] = true, ["token"] = true, ["members"] = true,
    ["parent"] = true, ["filed"] = true, ["withheld"] = true, ["log"] = true,
    ["ignore"] = true, ["removed-room"] = true, ["heard"] = true,
    ["mailbox"] = true,
}

-- {{{ local function read_file
local function read_file(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end
-- }}}

-- {{{ local function write_file
local function write_file(path, text)
    local f = assert(io.open(path, "w"))
    f:write(text)
    f:close()
end
-- }}}

-- {{{ local function file_exists
local function file_exists(path)
    local f = io.open(path, "r")
    -- present: close it and say so; absent: say so
    if f then
        f:close()
        return true
    end
    return false
end
-- }}}

-- {{{ function M.open_home
function M.open_home(dir)
    os.execute('mkdir -p "' .. dir .. '/rooms" "' .. dir .. '/people"')
    -- no config yet: an empty one; otherwise keep it
    if not file_exists(dir .. "/config") then
        write_file(dir .. "/config", "")
    end
    return { dir = dir }
end
-- }}}

-- {{{ function M.read_config
function M.read_config(home)
    local config = {}
    for line in io.lines(home.dir .. "/config") do
        local key, value = line:match("^(.-) = (.*)$")
        -- a key = value line: keep it; anything else: damage
        if key == nil then
            error("stand-in: bad config line: " .. line)
        end
        config[key] = value
    end
    return config
end
-- }}}

-- {{{ function M.set_config
function M.set_config(home, key, value)
    local config = M.read_config(home)
    config[key] = value
    local keys = {}
    for k in pairs(config) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        out[#out + 1] = k .. " = " .. config[k] .. "\n"
    end
    write_file(home.dir .. "/config", table.concat(out))
end
-- }}}

-- {{{ function M.config_value
function M.config_value(home, key)
    local value = M.read_config(home)[key]
    -- absent: an error, never a quiet default
    if value == nil then
        error("config key '" .. key .. "' is not set in " .. home.dir .. "/config")
    end
    return value
end
-- }}}

-- {{{ function M.new_local_tag
function M.new_local_tag()
    local f = assert(io.open("/dev/urandom", "rb"))
    local bytes = f:read(16)
    f:close()
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
-- }}}

-- {{{ function M.token_fingerprint
-- FNV-1a over the token's bytes, two 32-bit halves with different seeds,
-- repeated to 64 hex characters so it has the real one's length.
function M.token_fingerprint(token)
    local a, b = 0x811c9dc5, 0x01000193
    for i = 1, #token do
        a = bit.bxor(a, token:byte(i))
        a = bit.tobit(a * 16777619)
        b = bit.bxor(b, token:byte(i) + 7)
        b = bit.tobit(b * 16777619)
    end
    local half = bit.tohex(a) .. bit.tohex(b)
    return half .. half .. half .. half
end
-- }}}

-- {{{ function M.room_dir
function M.room_dir(home, tag)
    return home.dir .. "/rooms/" .. tag
end
-- }}}

-- {{{ function M.room_exists
function M.room_exists(home, tag)
    return file_exists(M.room_dir(home, tag) .. "/entry")
end
-- }}}

-- {{{ function M.list_rooms
function M.list_rooms(home)
    local tags = {}
    local listing = io.popen('ls -1 "' .. home.dir .. '/rooms"')
    for name in listing:lines() do
        -- a 32-hex folder: a room; anything else (hidden, stray): skipped
        if name:match("^" .. string.rep("[0-9a-f]", 32) .. "$") then
            tags[#tags + 1] = name
        end
    end
    listing:close()
    table.sort(tags)
    return tags
end
-- }}}

-- {{{ local function write_entry_file
local function write_entry_file(dir, tag, entry)
    local lines = {
        tag .. ".label = " .. entry.label,
        tag .. ".token = " .. entry.token,
        tag .. ".kind = " .. entry.kind,
        tag .. ".parent = " .. entry.parent,
        tag .. ".filed-under = " .. entry.filed_under,
    }
    for i, pair in ipairs(entry.members) do
        lines[#lines + 1] = tag .. ".ip[" .. i .. "] = " .. pair.address
        lines[#lines + 1] = tag .. ".port[" .. i .. "] = " .. pair.port
        lines[#lines + 1] = tag .. ".heard[" .. i .. "] = " .. pair.heard
    end
    write_file(dir .. "/entry", table.concat(lines, "\n") .. "\n")
end
-- }}}

-- {{{ function M.read_entry
-- { tag, label, token, kind, parent, filed_under,
--   members = list of {address = string, port = integer, heard = integer} }
function M.read_entry(home, tag)
    -- no such room: a mistake in the caller
    if not M.room_exists(home, tag) then
        error("stand-in: no room " .. tag)
    end
    local fields = {}
    for line in io.lines(M.room_dir(home, tag) .. "/entry") do
        local key, value = line:match("^[0-9a-f]+%.(.-) = (.*)$")
        fields[key] = value
    end
    local members = {}
    local i = 1
    while fields["ip[" .. i .. "]"] do
        members[i] = {
            address = fields["ip[" .. i .. "]"],
            port = tonumber(fields["port[" .. i .. "]"]),
            heard = tonumber(fields["heard[" .. i .. "]"]),
        }
        i = i + 1
    end
    return {
        tag = tag, label = fields.label, token = fields.token, kind = fields.kind,
        parent = fields.parent, filed_under = fields["filed-under"], members = members,
    }
end
-- }}}

-- {{{ function M.find_by_fingerprint
function M.find_by_fingerprint(home, fingerprint)
    for _, tag in ipairs(M.list_rooms(home)) do
        -- this room's token matches: it; otherwise keep looking
        if M.token_fingerprint(M.read_entry(home, tag).token) == fingerprint then
            return tag
        end
    end
    return ""
end
-- }}}

-- {{{ function M.make_room
-- spec: { label, token, kind, parent (fingerprint or ""), filed_under (tag
-- or ""), members = list of {address, port, heard}, mailbox_port }, all
-- required.  Mailboxes (round 3) are not kept here: the tree never reads
-- them.  Only the shape of mailbox_port is checked, a whole number or "",
-- so a test that would trip the real module's check trips here too.
function M.make_room(home, spec)
    local port = spec.mailbox_port
    -- neither a whole number nor "": the test built the spec wrongly
    if not ((type(port) == "number" and port == math.floor(port)) or port == "") then
        error("stand-in: make_room needs mailbox_port, a whole number or \"\", got " .. tostring(port))
    end
    -- a token already held: refused, as 101 does
    if M.find_by_fingerprint(home, M.token_fingerprint(spec.token)) ~= "" then
        error("stand-in: token already held by another room")
    end
    local tag = M.new_local_tag()
    local dir = M.room_dir(home, tag)
    os.execute('mkdir -p "' .. dir .. '"')
    write_entry_file(dir, tag, spec)
    write_file(dir .. "/log", "")
    write_file(dir .. "/withheld", "")
    M.notify(home, tag, "created")
    return tag
end
-- }}}

-- {{{ local function rewrite
local function rewrite(home, tag, field, value, kind)
    local entry = M.read_entry(home, tag)
    entry[field] = value
    write_entry_file(M.room_dir(home, tag), tag, entry)
    M.notify(home, tag, kind)
end
-- }}}

-- {{{ function M.write_label
function M.write_label(home, tag, label)
    rewrite(home, tag, "label", label, "label")
end
-- }}}

-- {{{ function M.write_parent
function M.write_parent(home, tag, fingerprint)
    rewrite(home, tag, "parent", fingerprint, "parent")
end
-- }}}

-- {{{ function M.write_filed_under
function M.write_filed_under(home, tag, under)
    rewrite(home, tag, "filed_under", under, "filed")
end
-- }}}

-- {{{ function M.write_members
function M.write_members(home, tag, members)
    rewrite(home, tag, "members", members, "members")
end
-- }}}

-- {{{ function M.change_token
-- As 101: held children naming the old fingerprint are re-pointed first
-- (each ringing "parent"), then the token is written and "token" rung.
function M.change_token(home, tag, token)
    local old = M.token_fingerprint(M.read_entry(home, tag).token)
    local new = M.token_fingerprint(token)
    local entry = M.read_entry(home, tag)
    entry.token = token
    write_entry_file(M.room_dir(home, tag), tag, entry)
    for _, other in ipairs(M.list_rooms(home)) do
        -- a child of the old token: point it at the new one
        if M.read_entry(home, other).parent == old then
            M.write_parent(home, other, new)
        end
    end
    M.notify(home, tag, "token")
end
-- }}}

-- {{{ function M.remove_room
-- Phase 1 has no way to remove a room; this exists so the tests can ring
-- "removed-room" after a folder is really gone.
function M.remove_room(home, tag)
    os.execute('rm -rf "' .. M.room_dir(home, tag) .. '"')
    M.notify(home, tag, "removed-room")
end
-- }}}

-- {{{ function M.on_change
function M.on_change(listener)
    listeners[#listeners + 1] = listener
end
-- }}}

-- {{{ function M.notify
function M.notify(home, tag, what)
    -- an unknown kind: a typo in the ringer
    if not KINDS[what] then
        error("stand-in notify: unknown kind " .. tostring(what))
    end
    for _, listener in ipairs(listeners) do
        listener(home, tag, what)
    end
end
-- }}}

return M
