-- 060-neighbour-reads.lua — the only place people-links names another
-- module's functions.  Everything people-links needs to know about rooms
-- comes through here, already shaped the way 061 wants it.
--
-- In plain words: people-links is a viewer.  It never writes a room; it only
-- reads each room's label, kind (group or direct message), member addresses,
-- and where the room sits in the tree.  Those facts belong to two other
-- modules — the room folders (issue 101: label, kind, members) and the room
-- tree (issue 102: which room a room sits under).  Keeping every call to
-- them in this one small file means that when either module renames a
-- function, only this file changes.
--
-- Why one whole-home read: 102 works its answers out from one pass over
-- every room (its "snapshot").  Asking it room by room would read every
-- room once per room — measured on the real modules at 100 rooms, one
-- rebuild of people/ took 1.2 s that way.  So a rebuild asks 102 for one
-- snapshot and takes both the entries and the tree from it, which also
-- means the rooms and the tree people-links sees are the same instant's.
--
-- The shapes handed to 061:
--   a room   { tag = string (32 hex, the folder name under rooms/),
--              label = string (your own name for it),
--              kind = "group" | "direct",
--              members = list of string, each "<address> <port>"
--                        (a member key: see member_key below),
--              tree_parent = string: the tag of the room it sits under in
--                            your tree (declared parent if held here, else
--                            your own filing, as 102 decides), or "" }

local rooms = require("002-room-folders")
local tree  = require("021-room-tree")

local M = {}

-- {{{ local function member_key
-- One member as one string: "<address> <port>".  Neither half can hold a
-- space (an address is an IP or hostname, a port is digits), so the key
-- splits back unambiguously and two keys are equal exactly when both halves
-- are.  101 gives ports as integers; tostring makes integer and text ports
-- the same digits.  Addresses are compared as written: "GF.example" and
-- "gf.example" are two members to people-links, as they are to 101's entry.
local function member_key(pair)
    return pair.address .. " " .. tostring(pair.port)
end
-- }}}

-- the two kinds of room 101 writes; anything else is a damaged entry
local KNOWN_KINDS = {
    ["group"]  = true,
    ["direct"] = true,
}

-- {{{ function M.config_value
-- home: { dir = string }; key: string.  The value, or an error when the key
-- is absent (101's rule: no silent defaults).
function M.config_value(home, key)
    return rooms.config_value(home, key)
end
-- }}}

-- {{{ local function shape_room
local function shape_room(tag, entry, tree_parent)
    -- a kind 101 does not write: stop, the entry or the contract moved
    if not KNOWN_KINDS[entry.kind] then
        error("people-links: room " .. tag .. " has kind " .. tostring(entry.kind)
              .. " (expected group or direct)")
    end
    local members = {}
    for i, pair in ipairs(entry.members) do
        members[i] = member_key(pair)
    end
    return { tag = tag, label = entry.label, kind = entry.kind, members = members, tree_parent = tree_parent }
end
-- }}}

-- {{{ function M.read_all
-- Every room of the home in one read.  Gives tags (sorted list of string)
-- and rooms (tag -> room in the shape above).
function M.read_all(home)
    local snap = tree.snapshot(home)
    local tags, by_tag = {}, {}
    for tag in pairs(snap.entries) do
        tags[#tags + 1] = tag
    end
    table.sort(tags)
    for _, tag in ipairs(tags) do
        by_tag[tag] = shape_room(tag, snap.entries[tag], snap.parent[tag])
    end
    return tags, by_tag
end
-- }}}

-- {{{ function M.on_change
-- Registers listener(home, tag, what) on 101's change bell.
function M.on_change(listener)
    rooms.on_change(listener)
end
-- }}}

M.member_key = member_key

return M
