-- 063-link-names.lua — decides what each link in a person's people/ folder
-- is called, when two of the rooms you share with them have the same name.
--
-- Room names are yours and may repeat: you can share two separate top rooms
-- both called "programming" with the same person.  A folder cannot hold two
-- entries with one name, so something has to give.  The owner has not yet
-- chosen how, so all three ways are built and the config key
-- people.link-collision picks one:
--
--   suffix-id  the rooms that clash get a tag from their room id:
--              programming~3fa9, programming~b710.  Rooms that do not clash
--              keep their plain name.
--   numbered   the clashing rooms are numbered in room-id order:
--              programming, programming-2.  Room ids never change, so the
--              same rooms always get the same numbers on every rebuild.
--   id-folder  every room gets a folder named by its room id, with the
--              named link inside: <room id>/programming.  Nothing can clash,
--              at the cost of an ls showing ids rather than names.
--
-- The same naming also serves people's folders (061): two direct-message
-- rooms may carry the same label, and people.person-folder-collision may
-- pick suffix-id or numbered for them.  Then "room_id" below is the
-- person's id (the direct message's tag, or a hex spelling of an address),
-- and a "room id" in this file means a room's tag (its local folder name).
--
-- This file only works out names.  It touches no disk: it takes a list of
-- rooms and gives back a list of planned links, so it can be tested alone
-- and the disk-writing code (061) never has to think about clashes.

local M = {}

-- how many characters of the room id a suffix starts with; grown one at a
-- time only in the rare case two clashing ids share their first four
local SUFFIX_START_LENGTH = 4

-- {{{ local function check_name
-- A room name becomes a file name, so it must be one: not empty, not "." or
-- "..", and without "/" (a folder separator) or the zero byte.  101 is
-- expected to refuse such names; this is the last line, and it errors
-- rather than inventing a replacement name.
local function check_name(name, room_id)
    local bad = name == "" or name == "." or name == ".."
             or name:find("/", 1, true) or name:find("\0", 1, true)
    -- unusable as a file name: stop and say which room
    if bad then
        error("link-names: room " .. room_id .. " has a name that cannot be a link name: "
              .. string.format("%q", name))
    end
end
-- }}}

-- {{{ local function room_id_before
-- Sort order for rooms: by room id, which never changes, so numbering and
-- order are the same on every rebuild.
local function room_id_before(a, b)
    return a.room_id < b.room_id
end
-- }}}

-- {{{ local function path_before
local function path_before(a, b)
    return a.path < b.path
end
-- }}}

-- {{{ local function group_by_name
-- Splits the rooms into those whose name is unique among them (they keep it)
-- and groups of rooms sharing a name, each group in room-id order, the
-- groups themselves in name order, so the result never depends on the
-- order the rooms were handed in.
local function group_by_name(rooms)
    local by_name = {}
    for _, room in ipairs(rooms) do
        check_name(room.name, room.room_id)
        by_name[room.name] = by_name[room.name] or {}
        table.insert(by_name[room.name], room)
    end
    local unique, clashing, names = {}, {}, {}
    for name in pairs(by_name) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local group = by_name[name]
        table.sort(group, room_id_before)
        -- one room with this name: it keeps it; several: they clash
        if #group == 1 then
            unique[#unique + 1] = group[1]
        else
            clashing[#clashing + 1] = group
        end
    end
    return unique, clashing
end
-- }}}

-- {{{ local function plain_links
-- The rooms whose name is unique keep it; their names are marked taken so a
-- made-up name (programming-2, programming~3fa9) never lands on top of a
-- room someone really called that.
local function plain_links(unique, taken)
    local links = {}
    for _, room in ipairs(unique) do
        taken[room.name] = true
        links[#links + 1] = { folder = "", name = room.name, room_id = room.room_id }
    end
    return links
end
-- }}}

-- {{{ local function suffix_fits
-- Whether every room in a clashing group gets a different, untaken name
-- when tagged with the first `length` characters of its id.
local function suffix_fits(group, length, taken)
    local seen = {}
    for _, room in ipairs(group) do
        local candidate = room.name .. "~" .. room.room_id:sub(1, length)
        -- already used by another room, or by one in this group: no fit
        if taken[candidate] or seen[candidate] then
            return false
        end
        seen[candidate] = true
    end
    return true
end
-- }}}

-- {{{ local function longest_id
local function longest_id(group)
    local longest = 0
    for _, room in ipairs(group) do
        -- longer than any before: remember its length
        if #room.room_id > longest then
            longest = #room.room_id
        end
    end
    return longest
end
-- }}}

-- {{{ local function name_suffix_id
local function name_suffix_id(rooms)
    local unique, clashing = group_by_name(rooms)
    local taken = {}
    local links = plain_links(unique, taken)
    for _, group in ipairs(clashing) do
        local length = SUFFIX_START_LENGTH
        while not suffix_fits(group, length, taken) do
            length = length + 1
            -- ids are unique, so the whole longest id always fits; past it
            -- is a bug.  (Room tags are 32 hex, but 061 also names people's
            -- folders here, whose ids can be longer: see 061's address_id.)
            if length > longest_id(group) then
                error("link-names: no suffix separates rooms named " .. group[1].name)
            end
        end
        for _, room in ipairs(group) do
            local name = room.name .. "~" .. room.room_id:sub(1, length)
            taken[name] = true
            links[#links + 1] = { folder = "", name = name, room_id = room.room_id }
        end
    end
    return links
end
-- }}}

-- {{{ local function name_numbered
local function name_numbered(rooms)
    local unique, clashing = group_by_name(rooms)
    local taken = {}
    local links = plain_links(unique, taken)
    for _, group in ipairs(clashing) do
        local number = 1
        for _, room in ipairs(group) do
            local candidate
            repeat
                -- the first room of a group keeps the bare name; later ones
                -- are numbered from 2
                if number == 1 then
                    candidate = room.name
                else
                    candidate = room.name .. "-" .. number
                end
                number = number + 1
            until not taken[candidate]
            taken[candidate] = true
            links[#links + 1] = { folder = "", name = candidate, room_id = room.room_id }
        end
    end
    return links
end
-- }}}

-- {{{ local function name_id_folder
local function name_id_folder(rooms)
    local links = {}
    for _, room in ipairs(rooms) do
        check_name(room.name, room.room_id)
        links[#links + 1] = { folder = room.room_id, name = room.name, room_id = room.room_id }
    end
    return links
end
-- }}}

-- the three answers to "two rooms, one name", by config value
local namers = {
    ["suffix-id"] = name_suffix_id,
    ["numbered"]  = name_numbered,
    ["id-folder"] = name_id_folder,
}

M.MODES = { "suffix-id", "numbered", "id-folder" }

-- {{{ local function link_path
-- Where a planned link sits inside the person's folder: "name" or
-- "<room id>/name".
local function link_path(link)
    -- no folder: straight in the person's folder; else one folder down
    if link.folder == "" then
        return link.name
    end
    return link.folder .. "/" .. link.name
end
-- }}}

-- {{{ function M.plan
-- rooms: list of { room_id = string, name = string }, the person's top rooms.
-- mode:  one of M.MODES.
-- Gives a list of { folder = "" or room id, name = string, room_id = string,
-- path = string }, sorted by path.
function M.plan(rooms, mode)
    local namer = namers[mode]
    -- a mode nobody built: stop and list the ones that exist
    if namer == nil then
        error("link-names: unknown people.link-collision " .. tostring(mode)
              .. " (built: " .. table.concat(M.MODES, ", ") .. ")")
    end
    local links = namer(rooms)
    for _, link in ipairs(links) do
        link.path = link_path(link)
    end
    table.sort(links, path_before)
    return links
end
-- }}}

return M
