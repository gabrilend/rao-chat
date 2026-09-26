-- 064-stand-in-room-folders.lua — a small stand-in for the room-folders
-- module (issue 101), written only so the people-links tests can run before
-- the real one exists.
--
-- It keeps the part of 101's promise that people-links and its tests use,
-- in the shapes the phase 1 contract gives: a home with config, rooms
-- named by a 32-hex local tag, each room's entry (label, token, kind,
-- parent fingerprint, mailbox, filed-under, member pairs), the round-3
-- mailboxes (make_room's mailbox_port rule, the one direct mailbox), and a
-- change bell rung after every write.  The test runner uses the real module instead when it
-- has been rewritten.
--
-- Stand-in shortcuts (the real 101 differs, which is why people-links only
-- reads rooms through functions):
--   rooms/<tag>/entry  a Lua table written with string.format("%q"), not
--                      rmail's contacts format
--   token_fingerprint  64 hex from eight rounds of a 32-bit FNV-1a mix, not
--                      SHA-256 twice: same token, same fingerprint, which
--                      is all the tests need
--   rao-home/mailboxes  a Lua table too; no shared-port warnings; no
--                      waiting mailbox (a parent not held here is always
--                      treated as mailboxes.unheld-parent = own-mailbox, but
--                      the key is still read then, as the real 101 does)
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
    for _, name in ipairs({ "config", "ignore", "mailboxes" }) do
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
    return string.format("return {tag=%q,label=%q,token=%q,kind=%q,parent=%q,mailbox=%q,filed_under=%q,members={%s}}\n",
        e.tag, e.label, e.token, e.kind, e.parent, e.mailbox, e.filed_under, table.concat(members, ","))
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

-- {{{ local function read_mailboxes
-- The mailboxes file: a list of { tag, label, kind, port }.  Empty file
-- (as open_home makes it): no mailboxes.
local function read_mailboxes(home)
    local text = read_text(home.dir .. "/mailboxes")
    -- never written: none yet
    if text == "" then
        return {}
    end
    return dofile(home.dir .. "/mailboxes")
end
-- }}}

-- {{{ local function write_mailboxes
local function write_mailboxes(home, list)
    local out = {}
    for i, m in ipairs(list) do
        out[i] = string.format("{tag=%q,label=%q,kind=%q,port=%d}", m.tag, m.label, m.kind, m.port)
    end
    write_text(home.dir .. "/mailboxes", "return {" .. table.concat(out, ",") .. "}\n")
end
-- }}}

-- {{{ local function add_mailbox
-- Appends one mailbox; gives its tag.  Rings nothing (callers decide).
local function add_mailbox(home, label, kind, port)
    -- a port that is not a whole number 1-65535: the caller is wrong
    if type(port) ~= "number" or port < 1 or port > 65535 or port % 1 ~= 0 then
        error("stand-in room-folders: a mailbox port is an integer 1-65535, got " .. tostring(port))
    end
    local list = read_mailboxes(home)
    local tag = M.new_local_tag()
    list[#list + 1] = { tag = tag, label = label, kind = kind, port = port }
    write_mailboxes(home, list)
    return tag
end
-- }}}

-- {{{ function M.direct_mailbox
-- The direct mailbox's tag, or "" when none is made yet.
function M.direct_mailbox(home)
    for _, m in ipairs(read_mailboxes(home)) do
        -- the one direct mailbox
        if m.kind == "direct" then
            return m.tag
        end
    end
    return ""
end
-- }}}

-- {{{ function M.make_mailbox
-- spec { label, kind = "direct", port }; rings mailbox with "" as 101 does.
function M.make_mailbox(home, spec)
    -- the stand-in only makes the direct mailbox (no waiting mailbox)
    if spec.kind ~= "direct" then
        error("stand-in room-folders: make_mailbox makes only the direct mailbox here, got " .. tostring(spec.kind))
    end
    -- one already: refused, as 101 does
    if M.direct_mailbox(home) ~= "" then
        error("stand-in room-folders: a direct mailbox exists already")
    end
    local tag = add_mailbox(home, spec.label, spec.kind, spec.port)
    M.notify(home, "", "mailbox")
    return tag
end
-- }}}

-- {{{ function M.write_mailbox_port
-- A mailbox's port changes; rings mailbox with "".
function M.write_mailbox_port(home, mailbox_tag, port)
    local list = read_mailboxes(home)
    local found = false
    for _, m in ipairs(list) do
        -- this mailbox: new port
        if m.tag == mailbox_tag then
            m.port, found = port, true
        end
    end
    -- no such mailbox: loud
    if not found then
        error("stand-in room-folders: no mailbox " .. tostring(mailbox_tag))
    end
    write_mailboxes(home, list)
    M.notify(home, "", "mailbox")
end
-- }}}

-- {{{ local function choose_mailbox
-- make_room's mailbox rule (contract, "Mailboxes"): gives the mailbox tag
-- and checks mailbox_port is an integer exactly when a new one is made.
local function choose_mailbox(home, spec)
    local port = spec.mailbox_port
    local wants_new
    -- a direct message: the direct mailbox, which must exist
    if spec.kind == "direct" then
        wants_new = false
    -- a top group room: a new tree mailbox
    elseif spec.parent == "" then
        wants_new = true
    -- a declared parent held here: its mailbox
    elseif M.find_by_fingerprint(home, spec.parent) ~= "" then
        wants_new = false
    -- a parent not held here: read the key, as 101 does only then
    else
        local choice = M.config_value(home, "mailboxes.unheld-parent")
        -- the stand-in builds only own-mailbox
        if choice ~= "own-mailbox" then
            error("stand-in room-folders: only mailboxes.unheld-parent = own-mailbox is built here")
        end
        wants_new = true
    end
    -- a new mailbox needs an integer port; the rest need ""
    if wants_new then
        -- anything but an integer: refused
        if type(port) ~= "number" then
            error("stand-in room-folders: make_room needs spec.mailbox_port (an integer) for a room that starts a mailbox")
        end
        return add_mailbox(home, spec.label, "tree", port)
    end
    -- not "": refused
    if port ~= "" then
        error("stand-in room-folders: spec.mailbox_port must be \"\" for a room that starts no mailbox")
    end
    -- a direct message
    if spec.kind == "direct" then
        local tag = M.direct_mailbox(home)
        -- none made yet: refused, as 101 does
        if tag == "" then
            error("stand-in room-folders: no direct mailbox; make_mailbox first")
        end
        return tag
    end
    return M.read_entry(home, M.find_by_fingerprint(home, spec.parent)).mailbox
end
-- }}}

-- {{{ function M.make_room
function M.make_room(home, spec)
    local mailbox = choose_mailbox(home, spec)
    local tag = M.new_local_tag()
    os.execute('mkdir -p "' .. M.room_dir(home, tag) .. '"')
    write_entry(home, {
        tag = tag, label = spec.label, token = spec.token, kind = spec.kind,
        parent = spec.parent, mailbox = mailbox, filed_under = spec.filed_under,
        members = spec.members,
    })
    write_text(M.room_dir(home, tag) .. "/withheld", "")
    write_text(M.room_dir(home, tag) .. "/flagged", "")
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

-- {{{ function M.write_mailbox
-- Moves a room to another mailbox; rings mailbox with the room's tag.  (No
-- kind-fits check here; the real 101 has one.)
function M.write_mailbox(home, tag, mailbox_tag)
    change_field(home, tag, "mailbox", mailbox_tag, "mailbox")
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
