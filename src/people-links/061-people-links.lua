-- 061-people-links.lua — keeps the people/ folder: for each person, one link
-- per top room you share with them, so "what do I share with this person?"
-- is answered by listing their folder.
--
--   people/<direct-message label>/<room label> -> ../../rooms/<local tag>
--
-- The rooms' entries are the truth; these links are only a view of them.
-- Nothing here is ever the only copy of anything: delete the whole people/
-- folder, rebuild, and the same links come back.
--
-- How it is worked out, in plain words.  A person is a direct-message room:
-- its label is what you call them, and its addresses are their machines.
-- A group room is "theirs" when one of those addresses is among its
-- members.  Of their rooms, the ones that get a link are the tops: rooms
-- whose parent in your tree (the room tree module, issue 102, decides the
-- parent: the room it was declared a child of, or the one you filed it
-- under) is not also theirs, or that have no parent.  In the owner's
-- example — the girlfriend in "home" and "programming" but not in "ritz"
-- between them — she gets two links, home and programming; add her to ritz
-- and programming stops being a top, leaving just home.
--
-- Undecided choices, each read from rao-home/config with no default:
--   people.link-collision         two top rooms, one label: suffix-id |
--                                 numbered | id-folder (see 063); every rebuild
--   people.direct-message-link    whether the person's own direct message
--                                 is linked in their folder too:
--                                 leave-out | include; every rebuild
--   people.members-without-dm     whether a member address that belongs to
--                                 no direct message gets a folder named by
--                                 the address: leave-out | address-folder;
--                                 every rebuild
--   people.person-folder-collision  two people whose folders would have the
--                                 same name: suffix-id | numbered | merge;
--                                 read only when that happens
--   people.slash-in-link-name     a label that cannot be a file name as it
--                                 is ("/" inside, or exactly "." or ".."):
--                                 percent | division-slash; read only when
--                                 such a label exists
--
-- Loading this module registers a listener on 101's change bell, so every
-- change that can move a link rebuilds people/.
--
-- Safety promise: only links this module made are ever removed.  A link is
-- recognised as ours by its shape: it lives directly in people/<person>/
-- and points at ../../rooms/<32 hex characters>, or lives in a
-- people/<person>/<32 hex>/ folder and points at ../../../rooms/<same>.
-- Anything else found in people/ (a note, a file, someone else's link) is
-- left exactly where it is, and if it sits where a link must go, the
-- rebuild stops with an error instead of overwriting it.

local reads      = require("060-neighbour-reads")
local disk       = require("062-disk-links")
local link_names = require("063-link-names")

local M = {}

-- a room's local tag: 32 lower-case hexadecimal characters (issue 101)
local TAG_PATTERN = string.rep("[0-9a-f]", 32)

-- the link targets this module writes, by how deep the link sits under the
-- person's folder: 1 = people/<p>/<name>, 2 = people/<p>/<tag>/<name>.
-- Relative, so rao-home can be copied or moved whole.
local TARGET_PREFIX = {
    [1] = "../../rooms/",
    [2] = "../../../rooms/",
}

-- The undecided choices this module reads, and the values built for each.
local CHOICES = {
    ["people.link-collision"]           = { "suffix-id", "numbered", "id-folder" },
    ["people.direct-message-link"]      = { "leave-out", "include" },
    ["people.members-without-dm"]       = { "leave-out", "address-folder" },
    ["people.person-folder-collision"]  = { "suffix-id", "numbered", "merge" },
    ["people.slash-in-link-name"]       = { "percent", "division-slash" },
}

-- {{{ local function list_contains
local function list_contains(list, wanted)
    for _, item in ipairs(list) do
        -- found it
        if item == wanted then
            return true
        end
    end
    return false
end
-- }}}

-- {{{ local function read_choice
local function read_choice(home, key)
    local value = reads.config_value(home, key)
    -- a value somebody built: use it; anything else: say what exists
    if not list_contains(CHOICES[key], value) then
        error("people-links: unknown " .. key .. " = " .. value
              .. " (built: " .. table.concat(CHOICES[key], ", ") .. ")")
    end
    return value
end
-- }}}

-- {{{ local function check_folder_name
-- A name about to become a folder or link name under people/ must be one.
-- Labels are rewritten (see unsafe_rewrites) before they get here, so a
-- failure is either a name given by hand to rebuild_person or a bug.
local function check_folder_name(name)
    local bad = type(name) ~= "string" or name == "" or name == "." or name == ".."
             or name:find("/", 1, true) or name:find("\0", 1, true)
    -- unusable as a folder name: stop
    if bad then
        error("people-links: " .. string.format("%q", tostring(name))
              .. " cannot be a folder name under people/")
    end
end
-- }}}

-- A label is your own text and may be anything but a line break (101).
-- Three shapes of it cannot be a file name as they are: one holding "/",
-- and the exact names "." and "..".  How they are written is
-- people.slash-in-link-name:
--   percent         "/" -> %2F, "." -> %2E, ".." -> %2E%2E — plain ASCII,
--                   obviously an escape
--   division-slash  look-alike characters: "/" -> U+2215 (∕), "." ->
--                   U+2024 (․), ".." -> U+2025 (‥) — reads like the label in
--                   ls, but looks identical to a path to a human eye
-- A rewritten name can clash with a real one (a room really called
-- home%2Fritz); the collision modes then separate them like any other clash.
local unsafe_rewrites = {
    ["percent"]        = { slash = "%%2F",          dot = "%2E",          dotdot = "%2E%2E" },
    ["division-slash"] = { slash = "\226\136\149", dot = "\226\128\164", dotdot = "\226\128\165" },
}

-- {{{ local function label_needs_rewrite
local function label_needs_rewrite(label)
    return label == "." or label == ".." or label:find("/", 1, true) ~= nil
end
-- }}}

-- {{{ local function check_label
-- A label that no rewrite can make into a file name: empty (101 refuses
-- one, so an empty label on disk is damage) or holding the zero byte.
local function check_label(label, tag)
    -- empty or with a zero byte: stop and name the room
    if type(label) ~= "string" or label == "" or label:find("\0", 1, true) then
        error("people-links: room " .. tag .. " has a label that cannot name anything under people/: "
              .. string.format("%q", tostring(label)))
    end
end
-- }}}

-- {{{ local function safe_name
-- The label as a file name, under the snapshot's rewrite mode ("" when no
-- label needed one, in which case none is rewritten here either).
local function safe_name(snapshot, label)
    -- nothing to rewrite: the label is the name
    if not label_needs_rewrite(label) then
        return label
    end
    local rewrite = unsafe_rewrites[snapshot.unsafe_mode]
    -- whole-name dots first; otherwise only slashes need changing
    if label == "." then
        return rewrite.dot
    elseif label == ".." then
        return rewrite.dotdot
    end
    return (label:gsub("/", rewrite.slash))
end
-- }}}

-- {{{ local function hex_of
-- A string spelled as lower-case hex, two characters per byte.
local function hex_of(text)
    return (text:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
-- }}}

-- {{{ local function address_folder_name
-- The folder name for a member with no direct message: "host:port", or
-- "[v6 address]:port" when the address itself holds ":" (IPv6), the way
-- such addresses are written in URLs.
local function address_folder_name(key)
    local address, port = key:match("^(%S+) (%S+)$")
    -- a colon in the address: IPv6, bracket it
    if address:find(":", 1, true) then
        return "[" .. address .. "]:" .. port
    end
    return address .. ":" .. port
end
-- }}}

-- {{{ local function set_of
local function set_of(list)
    local set = {}
    for _, item in ipairs(list) do
        set[item] = true
    end
    return set
end
-- }}}

-- {{{ local function sorted_keys
local function sorted_keys(set)
    local list = {}
    for key in pairs(set) do
        list[#list + 1] = key
    end
    table.sort(list)
    return list
end
-- }}}

-- {{{ local function candidate_people
-- Everyone who could get a folder, before names are settled: one per
-- direct-message room, and (under members-without-dm = address-folder)
-- one per group-room member address that no direct message holds.
-- A candidate is { id = string (the direct message's tag, or the hex of
-- the member key), label = string, addresses = set of member keys,
-- dm_tags = set of tags }.
local function candidate_people(snapshot)
    local candidates, held_by_dm = {}, {}
    for _, tag in ipairs(snapshot.tags) do
        local room = snapshot.rooms[tag]
        -- a direct message: it is a person
        if room.kind == "direct" then
            candidates[#candidates + 1] = {
                id = tag, label = safe_name(snapshot, room.label),
                addresses = set_of(room.members), dm_tags = { [tag] = true },
            }
            for _, key in ipairs(room.members) do
                held_by_dm[key] = true
            end
        end
    end
    -- leave-out: members nobody has a direct message with get no folder
    if snapshot.modes.members_without_dm == "leave-out" then
        return candidates
    end
    local loose = {}
    for _, tag in ipairs(snapshot.tags) do
        local room = snapshot.rooms[tag]
        for _, key in ipairs(room.members) do
            -- a group member held by no direct message: an address-only person
            if room.kind == "group" and not held_by_dm[key] then
                loose[key] = true
            end
        end
    end
    for _, key in ipairs(sorted_keys(loose)) do
        candidates[#candidates + 1] = {
            id = hex_of(key), label = address_folder_name(key),
            addresses = { [key] = true }, dm_tags = {},
        }
    end
    return candidates
end
-- }}}

-- {{{ local function merge_same_names
-- people.person-folder-collision = merge: people whose folders would share
-- a name are one person — their addresses and direct messages pooled, the
-- smallest id kept so the result does not depend on reading order.
local function merge_same_names(candidates)
    local by_name, order = {}, {}
    for _, c in ipairs(candidates) do
        local person = by_name[c.label]
        -- first with this name: it stands for the name
        if person == nil then
            person = { id = c.id, folder = c.label, addresses = {}, dm_tags = {} }
            by_name[c.label] = person
            order[#order + 1] = c.label
        end
        -- a smaller id: it becomes the merged person's id
        if c.id < person.id then
            person.id = c.id
        end
        for key in pairs(c.addresses) do person.addresses[key] = true end
        for tag in pairs(c.dm_tags) do person.dm_tags[tag] = true end
    end
    local people = {}
    for _, name in ipairs(order) do
        people[#people + 1] = by_name[name]
    end
    return people
end
-- }}}

-- {{{ local function names_clash
local function names_clash(candidates)
    local seen = {}
    for _, c in ipairs(candidates) do
        -- a name met twice: a clash
        if seen[c.label] then
            return true
        end
        seen[c.label] = true
    end
    return false
end
-- }}}

-- {{{ local function name_by_063
-- suffix-id / numbered for people's folders: the same naming as links
-- (063), with the person's id in place of a room's tag.
local function name_by_063(mode)
    return function(candidates)
        local named, by_id = {}, {}
        for _, c in ipairs(candidates) do
            named[#named + 1] = { room_id = c.id, name = c.label }
            by_id[c.id] = c
        end
        local people = {}
        for _, link in ipairs(link_names.plan(named, mode)) do
            local c = by_id[link.room_id]
            people[#people + 1] = { id = c.id, folder = link.name, addresses = c.addresses, dm_tags = c.dm_tags }
        end
        return people
    end
end
-- }}}

-- how people whose folders would share a name are told apart
local person_namers = {
    ["suffix-id"] = name_by_063("suffix-id"),
    ["numbered"]  = name_by_063("numbered"),
    ["merge"]     = merge_same_names,
}

-- {{{ local function settle_people
-- Gives the final people list, sorted by folder name: each
-- { id = string, folder = string, addresses = set of member keys,
--   dm_tags = set of tags }.
local function settle_people(home, snapshot)
    local candidates = candidate_people(snapshot)
    local people
    -- a clash: the choice decides (read only now); none: names stand as they are
    if names_clash(candidates) then
        snapshot.modes.person_folder_collision = read_choice(home, "people.person-folder-collision")
        people = person_namers[snapshot.modes.person_folder_collision](candidates)
    else
        snapshot.modes.person_folder_collision = ""
        people = merge_same_names(candidates)   -- no two share a name: a plain copy
    end
    table.sort(people, function(a, b) return a.folder < b.folder end)
    return people
end
-- }}}

-- {{{ local function unsafe_mode_for
-- Reads people.slash-in-link-name only when some label needs it; gives ""
-- otherwise.
local function unsafe_mode_for(home, snapshot)
    for _, tag in ipairs(snapshot.tags) do
        -- a label that is not a file name as it is: the choice decides
        if label_needs_rewrite(snapshot.rooms[tag].label) then
            return read_choice(home, "people.slash-in-link-name")
        end
    end
    return ""
end
-- }}}

-- {{{ function M.read_snapshot
-- Reads everything a rebuild needs, once, so one rebuild of every person
-- does not re-read every room per person.  The snapshot is a table:
--   modes   { collision = string, direct_message_link = string,
--             members_without_dm = string,
--             person_folder_collision = string ("" when no clash) }
--   tags    list of room tags, sorted
--   rooms   tag -> { tag, label, kind, members = list of member key,
--                    tree_parent = tag or "" }  (see 060)
--   unsafe_mode  "" when no label needs rewriting, else the value of
--                people.slash-in-link-name
--   people  list of { id, folder, addresses = set, dm_tags = set }, sorted
--           by folder
function M.read_snapshot(home)
    local snapshot = {
        modes = {
            collision           = read_choice(home, "people.link-collision"),
            direct_message_link = read_choice(home, "people.direct-message-link"),
            members_without_dm  = read_choice(home, "people.members-without-dm"),
        },
    }
    snapshot.tags, snapshot.rooms = reads.read_all(home)
    for _, tag in ipairs(snapshot.tags) do
        check_label(snapshot.rooms[tag].label, tag)
    end
    for _, tag in ipairs(snapshot.tags) do
        local parent = snapshot.rooms[tag].tree_parent
        -- 102 names a parent that is not a room here: the tree and the
        -- rooms disagree, which no rebuild can paper over
        if parent ~= "" and snapshot.rooms[parent] == nil then
            error("people-links: the tree puts room " .. tag .. " under " .. parent
                  .. ", which is not a room here")
        end
    end
    snapshot.unsafe_mode = unsafe_mode_for(home, snapshot)
    snapshot.people = settle_people(home, snapshot)
    return snapshot
end
-- }}}

-- {{{ local function is_theirs
-- Whether a room belongs to this person: a group room holding one of their
-- addresses, or (direct-message-link = include) one of their own direct
-- messages.
local function is_theirs(snapshot, person, tag)
    local room = snapshot.rooms[tag]
    -- their own direct message: only under include
    if person.dm_tags[tag] then
        return snapshot.modes.direct_message_link == "include"
    end
    -- someone else's direct message: never theirs
    if room.kind ~= "group" then
        return false
    end
    for _, key in ipairs(room.members) do
        -- one of their addresses is a member: theirs
        if person.addresses[key] then
            return true
        end
    end
    return false
end
-- }}}

-- {{{ local function tops_of
-- The tops of this person's trees, as sorted tags: their rooms whose tree
-- parent is not theirs (or is none).  One step up is enough: a room whose
-- parent is theirs sits inside a tree whose top is found from that parent.
local function tops_of(snapshot, person)
    local tops = {}
    for _, tag in ipairs(snapshot.tags) do
        local parent = snapshot.rooms[tag].tree_parent
        -- theirs, and either no parent or a parent that is not theirs
        if is_theirs(snapshot, person, tag)
           and (parent == "" or not is_theirs(snapshot, person, parent)) then
            tops[#tops + 1] = tag
        end
    end
    return tops
end
-- }}}

-- {{{ local function person_with_dm
local function person_with_dm(snapshot, dm_tag)
    local room = snapshot.rooms[dm_tag]
    -- not a direct message here: the caller named the wrong room
    if room == nil or room.kind ~= "direct" then
        error("people-links: " .. tostring(dm_tag) .. " is not a direct-message room here")
    end
    for _, person in ipairs(snapshot.people) do
        -- the person this direct message stands for (merged or not)
        if person.dm_tags[dm_tag] then
            return person
        end
    end
    error("people-links: no person for direct message " .. dm_tag .. " (a bug in settle_people)")
end
-- }}}

-- {{{ function M.top_rooms_for
-- home: { dir = string }; dm_tag: the tag of a direct-message room.
-- Gives the sorted list of tags of the top rooms you share with that person.
function M.top_rooms_for(home, dm_tag)
    local snapshot = M.read_snapshot(home)
    return tops_of(snapshot, person_with_dm(snapshot, dm_tag))
end
-- }}}

-- {{{ function M.top_rooms_for_addresses
-- home; pairs: list of { address = string, port = integer or string }.
-- The top group rooms holding any of these addresses, whether or not a
-- direct message holds them (no direct message is ever counted).
function M.top_rooms_for_addresses(home, pairs_list)
    local snapshot = M.read_snapshot(home)
    local person = { addresses = {}, dm_tags = {} }
    for _, pair in ipairs(pairs_list) do
        person.addresses[reads.member_key(pair)] = true
    end
    return tops_of(snapshot, person)
end
-- }}}

-- {{{ function M.people
-- Who has (or would have) a folder: a list of { folder = string,
-- id = string, dm_tags = sorted list of tags, addresses = sorted list of
-- member keys "<address> <port>" }, sorted by folder.
function M.people(home)
    local out = {}
    for _, person in ipairs(M.read_snapshot(home).people) do
        out[#out + 1] = {
            folder = person.folder, id = person.id,
            dm_tags = sorted_keys(person.dm_tags), addresses = sorted_keys(person.addresses),
        }
    end
    return out
end
-- }}}

-- {{{ local function planned_for_person
local function planned_for_person(snapshot, person)
    local named = {}
    for _, tag in ipairs(tops_of(snapshot, person)) do
        named[#named + 1] = { room_id = tag, name = safe_name(snapshot, snapshot.rooms[tag].label) }
    end
    local links = link_names.plan(named, snapshot.modes.collision)
    for _, link in ipairs(links) do
        local depth = (link.folder == "") and 1 or 2
        link.target = TARGET_PREFIX[depth] .. link.room_id
    end
    return links
end
-- }}}

-- {{{ local function person_in_folder
-- The person whose folder has this name, or nil when nobody's does (a
-- leftover folder to be swept, or a name given by hand).
local function person_in_folder(snapshot, folder)
    for _, person in ipairs(snapshot.people) do
        -- this person's folder
        if person.folder == folder then
            return person
        end
    end
    return nil
end
-- }}}

-- {{{ local function planned_in_folder
local function planned_in_folder(snapshot, folder)
    local person = person_in_folder(snapshot, folder)
    -- nobody's folder: nothing belongs in it
    if person == nil then
        return {}
    end
    return planned_for_person(snapshot, person)
end
-- }}}

-- {{{ function M.planned_links
-- The links people/<folder>/ should hold, without touching the disk:
-- a list of { path = string (inside the folder), target = string,
-- room_id = string (the room's tag), folder = "" or tag, name = string },
-- sorted by path.  Empty for a folder that is nobody's.
function M.planned_links(home, folder)
    return planned_in_folder(M.read_snapshot(home), folder)
end
-- }}}

-- {{{ local function is_our_target
-- Whether a link target has the exact shape this module writes at a depth.
local function is_our_target(target, depth)
    local prefix = TARGET_PREFIX[depth]
    -- wrong start: not ours
    if target:sub(1, #prefix) ~= prefix then
        return false
    end
    return target:sub(#prefix + 1):match("^" .. TAG_PATTERN .. "$") ~= nil
end
-- }}}

-- {{{ local function sweep_link
-- Looks at one entry that might be our link.  Keeps it if it is exactly a
-- planned link; removes it if it is ours but no longer planned (or points
-- elsewhere); leaves it if it is not ours.  Gives true when kept.
local function sweep_link(path, relative, depth, wanted_by_path)
    -- not a link at all: not ours
    if not disk.is_link(path) then
        return false
    end
    local target = disk.read_link(path)
    -- a link of some other shape: not ours, leave it
    if not is_our_target(target, depth) then
        return false
    end
    local wanted = wanted_by_path[relative]
    -- ours and still exactly right: keep
    if wanted ~= nil and wanted.target == target then
        return true
    end
    -- ours and stale (room gone, renamed, moved, mode changed): remove
    disk.remove_link(path)
    return false
end
-- }}}

-- {{{ local function sweep_person
-- Removes this module's stale links from one person's folder.  Gives the
-- set of planned paths already present (relative path -> true).
local function sweep_person(person_dir, wanted_by_path, wanted_folders)
    local present = {}
    for _, entry in ipairs(disk.list_dir(person_dir)) do
        local path = person_dir .. "/" .. entry
        local is_link = disk.is_link(path)
        -- a link directly in the folder: depth 1
        if is_link then
            present[entry] = sweep_link(path, entry, 1, wanted_by_path) or nil
        -- a tag folder (id-folder mode's shape): look inside
        elseif entry:match("^" .. TAG_PATTERN .. "$") and disk.is_dir(path) then
            for _, inner in ipairs(disk.list_dir(path)) do
                local relative = entry .. "/" .. inner
                present[relative] = sweep_link(path .. "/" .. inner, relative, 2, wanted_by_path) or nil
            end
            -- no longer a wanted folder: remove it if our sweep emptied it
            if not wanted_folders[entry] then
                disk.remove_dir_if_empty(path)
            end
        end
        -- anything else is not ours: left untouched
    end
    return present
end
-- }}}

-- {{{ local function rebuild_folder
local function rebuild_folder(home, snapshot, folder)
    check_folder_name(folder)
    local people_dir = home.dir .. "/people"
    local person_dir = people_dir .. "/" .. folder
    local links = planned_in_folder(snapshot, folder)
    local wanted_by_path, wanted_folders = {}, {}
    for _, link in ipairs(links) do
        wanted_by_path[link.path] = link
        -- a link inside a tag folder: that folder is wanted
        if link.folder ~= "" then
            wanted_folders[link.folder] = true
        end
    end

    -- people/ as a link would make every relative target point somewhere
    -- else; the layout says it is a real folder
    if disk.is_link(people_dir) then
        error("people-links: " .. people_dir .. " is a link; it must be a folder in rao-home")
    end
    disk.make_dir(people_dir)

    local present = {}
    local person_is_link = disk.is_link(person_dir)
    -- a real folder: sweep our stale links out of it
    if disk.is_dir(person_dir) and not person_is_link then
        present = sweep_person(person_dir, wanted_by_path, wanted_folders)
    -- something that is not a folder where the folder goes, and links are
    -- needed: stop instead of replacing it
    elseif disk.exists(person_dir) and #links > 0 then
        error("people-links: " .. person_dir .. " is in the way (not a folder)")
    end

    -- nothing shared: remove the folder if our sweep left it empty
    if #links == 0 then
        -- a real folder: tidy it; anything else (absent, or someone's file):
        -- leave it be
        if disk.is_dir(person_dir) and not person_is_link then
            disk.remove_dir_if_empty(person_dir)
        end
        return
    end

    disk.make_dir(person_dir)
    for _, link in ipairs(links) do
        -- not already there: make it
        if not present[link.path] then
            -- id-folder mode: the tag folder first
            if link.folder ~= "" then
                disk.make_dir(person_dir .. "/" .. link.folder)
            end
            local path = person_dir .. "/" .. link.path
            -- something that is not our link sits where the link goes
            if disk.exists(path) or disk.is_link(path) then
                error("people-links: " .. path .. " is in the way; it is not a link this module made")
            end
            disk.make_link(link.target, path)
        end
    end
end
-- }}}

-- {{{ function M.rebuild_person
-- Makes people/<folder>/ hold exactly the planned links (removing stale
-- ones of ours, keeping anything not ours).  folder: string, a folder name
-- under people/ (a person's, or a leftover one to sweep).
function M.rebuild_person(home, folder)
    rebuild_folder(home, M.read_snapshot(home), folder)
end
-- }}}

-- {{{ local function folders_already_there
-- The names of the real folders already in people/ (so a person who is
-- gone, or renamed, still gets their old links swept).
local function folders_already_there(people_dir)
    local names = {}
    -- no people/ yet (first run, or deleted): nothing to sweep
    if not disk.is_dir(people_dir) then
        return names
    end
    for _, entry in ipairs(disk.list_dir(people_dir)) do
        local path = people_dir .. "/" .. entry
        -- a real folder: a person's (or someone's own folder, swept safely);
        -- files and links at this level are not ours and are skipped
        if disk.is_dir(path) and not disk.is_link(path) then
            names[#names + 1] = entry
        end
    end
    return names
end
-- }}}

-- {{{ function M.rebuild_all
-- Rebuilds every person's folder and sweeps every folder already in
-- people/ that is nobody's any more.
function M.rebuild_all(home)
    local snapshot = M.read_snapshot(home)
    local everyone, seen = {}, {}
    for _, person in ipairs(snapshot.people) do
        seen[person.folder] = true
        everyone[#everyone + 1] = person.folder
    end
    for _, name in ipairs(folders_already_there(home.dir .. "/people")) do
        -- a folder nobody owns now: swept like the rest
        if not seen[name] then
            seen[name] = true
            everyone[#everyone + 1] = name
        end
    end
    table.sort(everyone)
    for _, name in ipairs(everyone) do
        rebuild_folder(home, snapshot, name)
    end
end
-- }}}

-- {{{ local function changes_no_links
-- A bell ring that cannot change anyone's links.
local function changes_no_links(home)
end
-- }}}

-- What each ring of 101's bell means for people/.  Anything that can change
-- a label, a kind of room existing, a member list, or where a room sits in
-- the tree can change who has which tops, and a tree change can move tops
-- for everyone below it, so the whole of people/ is rebuilt.
--   token    a new token is a new fingerprint.  101 re-points the held
--            children first (each ringing parent), but a room here whose
--            parent named a fingerprint nobody held can now find its parent
--            in the new one, and the reverse, so tops can move.  (Issue 104
--            did not list it; found while building.)
--   heard    a last-heard time changed; membership did not (contract)
--   withheld, ignore  do not change membership (owner's design: withholding
--            is who you send to, ignoring is what you see), so no link moves
--   log      a new message changes none of this
local on_bell = {
    ["created"]      = M.rebuild_all,
    ["label"]        = M.rebuild_all,
    ["token"]        = M.rebuild_all,
    ["members"]      = M.rebuild_all,
    ["parent"]       = M.rebuild_all,
    ["filed"]        = M.rebuild_all,
    ["removed-room"] = M.rebuild_all,
    ["heard"]        = changes_no_links,
    ["withheld"]     = changes_no_links,
    ["ignore"]       = changes_no_links,
    ["log"]          = changes_no_links,
}

-- {{{ local function hear_bell
local function hear_bell(home, tag, what)
    local action = on_bell[what]
    -- a kind of change the contract does not list: stop, the contract moved
    if action == nil then
        error("people-links: unknown change " .. tostring(what) .. " on room " .. tostring(tag))
    end
    action(home)
end
-- }}}

reads.on_change(hear_bell)

return M
