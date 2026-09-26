-- 044-stand-in-room-folders.lua — a small copy of the room-folders module
-- (issue 101), written only so the recipients tests can run before the real
-- one lands.
--
-- It offers the handful of 101's functions the recipients module uses, in
-- the shapes docs/phase-1-module-contract.md gives (round 2): a home with
-- config and an empty ignore file; rooms made in a folder per local tag
-- holding an entry, an empty withheld file and an empty log; members as
-- {address, port, heard}; and the change bell with the contract's kinds.
-- The entry here is kept in a simpler text shape than rmail's contacts
-- format, since nothing outside 101 reads the entry file directly.
-- The runner loads the real module instead when told "real".

local disk = require("003-disk")

local M = {}

local listeners = {}

M.BELL_KINDS = {
    created = "", label = "", token = "", members = "", heard = "", parent = "",
    filed = "", withheld = "", log = "", ignore = "", ["removed-room"] = "",
}

-- {{{ local function hex_of
-- Stand-in fingerprint: the token's bytes as hex, padded to 64.  NOT a
-- one-way scramble — good enough to name a parent inside tests only.
local function hex_of(text)
    local out = text:gsub(".", function(c) return string.format("%02x", c:byte()) end)
    return (out .. string.rep("0", 64)):sub(1, 64)
end
-- }}}
M.token_fingerprint = hex_of

-- {{{ function M.open_home
function M.open_home(dir)
    local home = { dir = dir }
    -- a new home: lay out the folders and the empty files
    if not disk.is_dir(dir) then
        disk.make_dir(dir)
        disk.make_dir(dir .. "/rooms")
        disk.make_dir(dir .. "/people")
        disk.write_atomic(dir .. "/config", "")
        disk.write_atomic(dir .. "/ignore", "")
    end
    return home
end
-- }}}

-- {{{ function M.read_config
function M.read_config(home)
    local config = {}
    for line in io.lines(home.dir .. "/config") do
        local k, v = line:match("^(%S+) = (.*)$")
        config[k] = v
    end
    return config
end
-- }}}

-- {{{ function M.set_config
function M.set_config(home, key, value)
    local config = M.read_config(home)
    config[key] = value
    local lines = {}
    for k, v in pairs(config) do lines[#lines + 1] = k .. " = " .. v .. "\n" end
    table.sort(lines)
    disk.write_atomic(home.dir .. "/config", table.concat(lines))
end
-- }}}

-- {{{ function M.config_value
function M.config_value(home, key)
    local value = M.read_config(home)[key]
    -- absent: the contract says error, never a default
    if value == nil then
        error("config: no value for " .. key)
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

-- {{{ function M.is_local_tag
function M.is_local_tag(value)
    return type(value) == "string" and #value == 32 and value:match("^[0-9a-f]+$") ~= nil
end
-- }}}

-- {{{ function M.room_dir
function M.room_dir(home, tag) return home.dir .. "/rooms/" .. tag end
-- }}}
-- {{{ function M.withheld_path
function M.withheld_path(home, tag) return M.room_dir(home, tag) .. "/withheld" end
-- }}}
-- {{{ function M.ignore_path
function M.ignore_path(home) return home.dir .. "/ignore" end
-- }}}
-- {{{ function M.room_exists
function M.room_exists(home, tag) return disk.is_dir(M.room_dir(home, tag)) end
-- }}}

-- {{{ local function entry_text
local function entry_text(e)
    local lines = {
        "label = " .. e.label, "token = " .. e.token, "kind = " .. e.kind,
        "parent = " .. e.parent, "filed_under = " .. e.filed_under,
    }
    for _, m in ipairs(e.members) do
        lines[#lines + 1] = "member = " .. m.address .. " " .. m.port .. " " .. m.heard
    end
    return table.concat(lines, "\n") .. "\n"
end
-- }}}

-- {{{ function M.read_entry
function M.read_entry(home, tag)
    -- no room: the contract says error
    if not M.room_exists(home, tag) then
        error("read_entry: no room " .. tostring(tag))
    end
    local e = { tag = tag, members = {} }
    for line in io.lines(M.room_dir(home, tag) .. "/entry") do
        local k, v = line:match("^(%S+) = ?(.*)$")
        -- a member line: three words; any other: one field
        if k == "member" then
            local a, p, h = v:match("^(%S+) (%d+) (%d+)$")
            e.members[#e.members + 1] = { address = a, port = tonumber(p), heard = tonumber(h) }
        else
            e[k] = v
        end
    end
    return e
end
-- }}}

-- {{{ function M.notify
function M.notify(home, tag, what)
    -- unknown kinds are errors, as in the real bell
    if M.BELL_KINDS[what] == nil then
        error("notify: unknown kind " .. tostring(what))
    end
    -- ignore rings on "" or a tag; everything else on a tag only
    if tag == "" and what ~= "ignore" then
        error("notify: kind " .. what .. " with tag '" .. tostring(tag) .. "'")
    end
    for _, listener in ipairs(listeners) do
        listener(home, tag, what)
    end
end
-- }}}

-- {{{ function M.on_change
function M.on_change(listener) listeners[#listeners + 1] = listener end
-- }}}
-- {{{ function M.listener_count
function M.listener_count() return #listeners end
-- }}}

-- {{{ function M.make_room
function M.make_room(home, spec)
    for _, field in ipairs({ "label", "token", "kind", "parent", "filed_under", "members" }) do
        -- every field is required by the contract
        if spec[field] == nil then
            error("make_room: missing " .. field)
        end
    end
    local tag = M.new_local_tag()
    local hidden = home.dir .. "/rooms/.new-" .. tag
    disk.make_dir(hidden)
    local e = { label = spec.label, token = spec.token, kind = spec.kind, parent = spec.parent,
        filed_under = spec.filed_under, members = spec.members }
    disk.write_atomic(hidden .. "/entry", entry_text(e))
    disk.write_atomic(hidden .. "/withheld", "")
    disk.write_atomic(hidden .. "/log", "")
    disk.rename(hidden, M.room_dir(home, tag))
    M.notify(home, tag, "created")
    return tag
end
-- }}}

-- {{{ function M.write_members
function M.write_members(home, tag, members)
    local e = M.read_entry(home, tag)
    e.members = members
    disk.write_atomic(M.room_dir(home, tag) .. "/entry", entry_text(e))
    M.notify(home, tag, "members")
end
-- }}}

-- {{{ function M.write_heard
function M.write_heard(home, tag, address, port, when)
    local e = M.read_entry(home, tag)
    local found = false
    for _, m in ipairs(e.members) do
        -- the pair: change its time
        if m.address == address and m.port == port then
            m.heard = when
            found = true
        end
    end
    -- not a member: the contract says error
    if not found then
        error("write_heard: " .. address .. " " .. port .. " is not a member")
    end
    disk.write_atomic(M.room_dir(home, tag) .. "/entry", entry_text(e))
    M.notify(home, tag, "heard")
end
-- }}}

-- {{{ function M.list_rooms
function M.list_rooms(home)
    local list = {}
    for _, name in ipairs(disk.list_dir(home.dir .. "/rooms")) do
        -- hidden (being made) entries are skipped
        if name:sub(1, 1) ~= "." then
            list[#list + 1] = name
        end
    end
    return list
end
-- }}}

-- {{{ function M.list_rooms_by_kind
function M.list_rooms_by_kind(home, kind)
    local list = {}
    for _, tag in ipairs(M.list_rooms(home)) do
        -- the asked kind only
        if M.read_entry(home, tag).kind == kind then
            list[#list + 1] = tag
        end
    end
    return list
end
-- }}}

-- {{{ function M.find_by_fingerprint
function M.find_by_fingerprint(home, fingerprint)
    for _, tag in ipairs(M.list_rooms(home)) do
        -- the room whose token scrambles to this: found
        if hex_of(M.read_entry(home, tag).token) == fingerprint then
            return tag
        end
    end
    return ""
end
-- }}}

return M
