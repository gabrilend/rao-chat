-- 064-stand-in-room-folders.lua — a small stand-in for the room-folders
-- module (issue 101), written only so the people-links tests can run before
-- the real one exists.
--
-- It keeps the part of 101's promise that people-links and its tests use,
-- in the shapes the phase 1 contract gives: a home with config, rooms
-- named by a 32-hex local tag, each room's entry (label, token, kind,
-- parent fingerprint, filed-under, member pairs), and a change bell rung
-- after every write.  The test runner uses the real module instead when it
-- has been rewritten.
--
-- Stand-in shortcuts (the real 101 differs, which is why people-links only
-- reads rooms through functions):
--   rooms/<tag>/entry  a Lua table written with string.format("%q"), not
--                      rmail's contacts format
--   token_fingerprint  64 hex from eight rounds of a 32-bit FNV-1a mix, not
--                      SHA-256 twice: same token, same fingerprint, which
--                      is all the tests need
--   no refusals of loops, repeated tokens or bad addresses

local bit = require("bit")

local M = {}

local listeners = {}

-- {{{ local function write_text
local function write_text(path, text)
    local file = assert(io.open(path, "w"))
    file:write(text)
    file:close()
end
-- }}}

-- {{{ local function read_text
local function read_text(path)
    local file = assert(io.open(path, "r"))
    local text = file:read("*a")
    file:close()
    return text
end
-- }}}

-- {{{ local function file_exists
local function file_exists(path)
    local file = io.open(path, "r")
    -- opened: there
    if file then
        file:close()
        return true
    end
    return false
end
-- }}}

-- {{{ function M.open_home
function M.open_home(dir)
    os.execute('mkdir -p "' .. dir .. '/rooms" "' .. dir .. '/people"')
    for _, name in ipairs({ "config", "ignore" }) do
        -- absent: make it empty; present: leave it
        if not file_exists(dir .. "/" .. name) then
            write_text(dir .. "/" .. name, "")
        end
    end
    return { dir = dir }
end
-- }}}

-- {{{ function M.read_config
function M.read_config(home)
    local config = {}
    for line in read_text(home.dir .. "/config"):gmatch("[^\n]+") do
        local key, value = line:match("^%s*([^=%s]+)%s*=%s*(.-)%s*$")
        -- a key = value line: keep it; anything else: skip
        if key then
            config[key] = value
        end
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
    write_text(home.dir .. "/config", table.concat(out))
end
-- }}}

-- {{{ function M.config_value
function M.config_value(home, key)
    local value = M.read_config(home)[key]
    -- absent: loud, no default
    if value == nil then
        error("stand-in room-folders: config has no " .. key)
    end
    return value
end
-- }}}

-- {{{ function M.new_local_tag
function M.new_local_tag()
    local file = assert(io.open("/dev/urandom", "rb"))
    local bytes = file:read(16)
    file:close()
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
-- }}}

-- {{{ function M.token_fingerprint
function M.token_fingerprint(token)
    local parts = {}
    for round = 1, 8 do
        local h = 2166136261
        local text = round .. ":" .. token
        for i = 1, #text do
            h = bit.bxor(h, text:byte(i))
            h = bit.tobit(h * 16777619)
        end
        parts[round] = bit.tohex(h, 8)
    end
    return table.concat(parts)
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

-- {{{ function M.on_change
function M.on_change(listener)
    listeners[#listeners + 1] = listener
end
-- }}}

-- {{{ function M.notify
function M.notify(home, tag, what)
    for _, listener in ipairs(listeners) do
        listener(home, tag, what)
    end
end
-- }}}

-- {{{ local function serialize_entry
local function serialize_entry(e)
    local members = {}
    for i, m in ipairs(e.members) do
        members[i] = string.format("{address=%q,port=%d,heard=%d}", m.address, m.port, m.heard)
    end
    return string.format("return {tag=%q,label=%q,token=%q,kind=%q,parent=%q,filed_under=%q,members={%s}}\n",
        e.tag, e.label, e.token, e.kind, e.parent, e.filed_under, table.concat(members, ","))
end
-- }}}

-- {{{ local function write_entry
local function write_entry(home, entry)
    write_text(M.room_dir(home, entry.tag) .. "/entry", serialize_entry(entry))
end
-- }}}

-- {{{ function M.read_entry
function M.read_entry(home, tag)
    -- no room: loud, as the real one
    if not M.room_exists(home, tag) then
        error("stand-in room-folders: no room " .. tostring(tag))
    end
    return dofile(M.room_dir(home, tag) .. "/entry")
end
-- }}}

-- {{{ function M.make_room
function M.make_room(home, spec)
    local tag = M.new_local_tag()
    os.execute('mkdir -p "' .. M.room_dir(home, tag) .. '"')
    write_entry(home, {
        tag = tag, label = spec.label, token = spec.token, kind = spec.kind,
        parent = spec.parent, filed_under = spec.filed_under, members = spec.members,
    })
    write_text(M.room_dir(home, tag) .. "/withheld", "")
    write_text(M.room_dir(home, tag) .. "/log", "")
    M.notify(home, tag, "created")
    return tag
end
-- }}}

-- {{{ local function change_field
local function change_field(home, tag, field, value, what)
    local entry = M.read_entry(home, tag)
    entry[field] = value
    write_entry(home, entry)
    M.notify(home, tag, what)
end
-- }}}

-- {{{ function M.write_label
function M.write_label(home, tag, label)
    change_field(home, tag, "label", label, "label")
end
-- }}}

-- {{{ function M.write_members
function M.write_members(home, tag, members)
    change_field(home, tag, "members", members, "members")
end
-- }}}

-- {{{ function M.write_parent
function M.write_parent(home, tag, fingerprint)
    change_field(home, tag, "parent", fingerprint, "parent")
end
-- }}}

-- {{{ function M.write_filed_under
function M.write_filed_under(home, tag, other)
    change_field(home, tag, "filed_under", other, "filed")
end
-- }}}

-- {{{ function M.write_heard
function M.write_heard(home, tag, address, port, when)
    local entry = M.read_entry(home, tag)
    for _, m in ipairs(entry.members) do
        -- the pair: set its time
        if m.address == address and m.port == port then
            m.heard = when
        end
    end
    write_entry(home, entry)
    M.notify(home, tag, "heard")
end
-- }}}

-- {{{ function M.list_rooms
function M.list_rooms(home)
    local listing = io.popen('ls -1 "' .. home.dir .. '/rooms"')
    local tags = {}
    for entry in listing:lines() do
        -- hidden entries are half-built rooms: skipped
        if entry:sub(1, 1) ~= "." then
            tags[#tags + 1] = entry
        end
    end
    listing:close()
    table.sort(tags)
    return tags
end
-- }}}

-- {{{ function M.find_by_fingerprint
function M.find_by_fingerprint(home, fingerprint)
    for _, tag in ipairs(M.list_rooms(home)) do
        -- this room's token has that fingerprint
        if M.token_fingerprint(M.read_entry(home, tag).token) == fingerprint then
            return tag
        end
    end
    return ""
end
-- }}}

-- {{{ function M.change_token
-- As the contract: held children naming the old fingerprint are re-pointed
-- first (each ringing parent), then token rings.
function M.change_token(home, tag, token)
    local old = M.token_fingerprint(M.read_entry(home, tag).token)
    local new = M.token_fingerprint(token)
    for _, other in ipairs(M.list_rooms(home)) do
        -- a held child of this room: follows the new fingerprint
        if M.read_entry(home, other).parent == old then
            M.write_parent(home, other, new)
        end
    end
    change_field(home, tag, "token", token, "token")
end
-- }}}

return M
