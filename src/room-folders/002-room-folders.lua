-- 002-room-folders.lua — the home folder, its settings, and its rooms.
--
-- A rao-chat home server keeps everything in one folder, rao-home:
--
--     rao-home/
--       config                   settings, "key = value" (rmail's format)
--       ignore                   addresses you ignore (the ignore list's file; made empty here)
--       rooms/<local tag>/entry     what the room is (006-entry: label, token, kind,
--                                   parent, filed-under, member addresses)
--       rooms/<local tag>/withheld  members you do not send to (recipients'; made empty here)
--       rooms/<local tag>/where     the folder's path and path of labels (room-tree's)
--       rooms/<local tag>/log       the messages (message-log's; made empty here)
--       people/                  links, kept by the people-links module
--
-- Every conversation is a room: a group room and a direct message with one
-- person are the same folder shape, made and read by the same code; the
-- entry's `kind` tells them apart.  Every room sits side by side under
-- rooms/, in a folder named by a random local tag that never leaves this
-- machine.  Rooms nest, but not by folders inside folders: a child room's
-- entry names its parent by the parent's token fingerprint (007-tokens),
-- which every member's server can work out and nobody can reverse.
--
-- This file is the front door the other modules use.  Every change it
-- makes is written whole-or-not-at-all (003-disk) and then announced on
-- the change bell (005-change-bell), so the modules that keep summaries
-- of rooms (`where`, `people/`) can bring them up to date.
--
-- Usage:
--   dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)
--   local rooms = require("002-room-folders")
--   local home  = rooms.open_home("/path/to/rao-home")

local disk    = require("003-disk")
local formats = require("004-rmail-formats")
local bell    = require("005-change-bell")
local entries = require("006-entry")
local tokens  = require("007-tokens")

-- The header written into a brand-new config file, so a person opening
-- it in an editor knows what it is.
local NEW_CONFIG_TEXT =
    "# rao-chat settings: one 'key = value' per line (rmail's config format).\n" ..
    "# A setting a module asks for and does not find here is an error, never\n" ..
    "# a quiet default; the error names the key to add.\n"

-- The config key holding how many words a suggested token has (issue 101
-- open question 3; the variants are in 019-options.lua).
local SUGGESTED_WORDS_KEY = "rooms.suggested-token-words"

-- The fields a make_room spec must have, every one of them.
local SPEC_FIELDS = { "label", "token", "kind", "parent", "filed_under", "members" }

-- {{{ local function check_home
-- Every function taking a home checks it first: a wrong argument order
-- (a tag where the home belongs) would otherwise surface as a baffling path.
local function check_home(home)
    if type(home) ~= "table" or type(home.dir) ~= "string" then
        error("expected a home {dir = string} as first argument, got " .. type(home), 3)
    end
end
-- }}}

-- {{{ local function check_tag
local function check_tag(value)
    -- not a tag: say what was given, so a label passed as a tag is obvious.
    if not entries.is_local_tag(value) then
        error("not a local tag (32 lower-case hex characters): " .. tostring(value), 3)
    end
end
-- }}}

-- {{{ local function open_home
-- Makes whatever is missing of the layout and returns the home value.
-- The folder above rao-home must already exist: a typo in a path should
-- not quietly grow a new tree of folders somewhere unexpected.
local function open_home(dir)
    -- a relative path would mean different homes from different working
    -- folders; only absolute paths name one place.
    if type(dir) ~= "string" or dir:sub(1, 1) ~= "/" then
        error("open_home needs an absolute path, got " .. tostring(dir), 2)
    end
    dir = dir:gsub("/+$", "")
    local parent = dir:match("^(.*)/[^/]+$")
    -- parent "" means the home is directly under "/", which exists.
    if parent ~= "" and not disk.is_dir(parent) then
        error("open_home: the folder above the home does not exist: " .. parent, 2)
    end
    -- absent: make it.  A plain file with that name: refuse.
    if not disk.is_dir(dir) then
        if disk.is_file(dir) then
            error("open_home: " .. dir .. " is a file, not a folder", 2)
        end
        disk.make_dir(dir)
    end
    -- each file and folder of the layout: made if missing, left alone if
    -- present (opening a home twice changes nothing).  The ignore file
    -- starts empty — nobody ignored — and its lines are the ignore
    -- list's business from then on.
    if not disk.is_file(dir .. "/config") then
        disk.write_atomic(dir .. "/config", NEW_CONFIG_TEXT)
    end
    if not disk.is_file(dir .. "/ignore") then
        disk.write_atomic(dir .. "/ignore", "")
    end
    for _, folder in ipairs({ "rooms", "people" }) do
        if not disk.is_dir(dir .. "/" .. folder) then
            disk.make_dir(dir .. "/" .. folder)
        end
    end
    return { dir = dir }
end
-- }}}

-- {{{ local function read_config
local function read_config(home)
    check_home(home)
    local path = home.dir .. "/config"
    return formats.parse_config(disk.read_all(path), path)
end
-- }}}

-- {{{ local function set_config
local function set_config(home, key, value)
    check_home(home)
    local path = home.dir .. "/config"
    local text = disk.read_all(path)
    -- parse first: refuse to edit a file that is already broken, so the
    -- error points at the original damage rather than at this write.
    formats.parse_config(text, path)
    disk.write_atomic(path, formats.config_with(text, key, value))
end
-- }}}

-- {{{ local function config_value
-- The strict lookup: every undecided choice is read through this, so an
-- unset choice stops the program with the line to add, rather than
-- picking a variant nobody chose.
local function config_value(home, key)
    check_home(home)
    local value = read_config(home)[key]
    -- absent: name the key and the file, and show the fix.
    if value == nil then
        error("config key '" .. key .. "' is not set in " .. home.dir ..
              "/config (add a line: " .. key .. " = <value>)", 2)
    end
    return value
end
-- }}}

-- {{{ local function new_local_tag
-- 16 bytes from the kernel's random source, written as 32 hex characters.
-- 128 random bits: never the same twice, and never sent anywhere, so it
-- says nothing about the room to anyone.
local function new_local_tag()
    local source, problem = io.open("/dev/urandom", "rb")
    -- no random source: refuse rather than make a guessable tag.
    if not source then
        error("cannot open /dev/urandom: " .. tostring(problem), 2)
    end
    local bytes = source:read(16)
    source:close()
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
-- }}}

-- {{{ local function room_dir
local function room_dir(home, tag)
    check_home(home)
    check_tag(tag)
    return home.dir .. "/rooms/" .. tag
end
-- }}}

-- {{{ local function entry_path
local function entry_path(home, tag)
    return room_dir(home, tag) .. "/entry"
end
-- }}}

-- {{{ local function withheld_path
-- The withheld file's format is the recipients module's (103).
local function withheld_path(home, tag)
    return room_dir(home, tag) .. "/withheld"
end
-- }}}

-- {{{ local function where_path
-- The where file's format is the room-tree module's (102).
local function where_path(home, tag)
    return room_dir(home, tag) .. "/where"
end
-- }}}

-- {{{ local function log_path
-- The log's format is the message-log module's (105).
local function log_path(home, tag)
    return room_dir(home, tag) .. "/log"
end
-- }}}

-- {{{ local function ignore_path
-- The ignore file's format is the ignore list's (103a).
local function ignore_path(home)
    check_home(home)
    return home.dir .. "/ignore"
end
-- }}}

-- {{{ local function room_exists
local function room_exists(home, tag)
    return disk.is_dir(room_dir(home, tag))
end
-- }}}

-- {{{ local function read_entry
-- Returns { tag, label, token, kind, parent, filed_under, members = list
-- of { address, port, heard } }, read fresh from disk: nothing is kept
-- in memory, so a hand edit is seen at once.
local function read_entry(home, tag)
    local dir = room_dir(home, tag)
    -- absent: callers ask for rooms they believe exist.
    if not disk.is_dir(dir) then
        error("no such room: " .. tag, 2)
    end
    local path = dir .. "/entry"
    return entries.parse_entry(disk.read_all(path), tag, path)
end
-- }}}

-- {{{ local function list_rooms
-- Every local tag in rooms/, sorted.  Hidden entries (".new-<tag>" left by
-- a crash mid-make) are skipped: they are not rooms yet.  Anything else
-- that is not a local tag is an error, so a stray file is noticed.
local function list_rooms(home)
    check_home(home)
    local tags = {}
    for _, name in ipairs(disk.list_dir(home.dir .. "/rooms")) do
        -- hidden: half-built, skip.  A local tag: keep.  Other: refuse.
        if name:sub(1, 1) == "." then
            -- skipped on purpose
        elseif entries.is_local_tag(name) then
            tags[#tags + 1] = name
        else
            error("unexpected entry in " .. home.dir .. "/rooms: " .. name, 2)
        end
    end
    return tags
end
-- }}}

-- {{{ local function list_rooms_by_kind
-- The rooms of one kind ("group" or "direct"), sorted by tag.  Direct
-- messages and group rooms are listed apart on screen but kept alike.
local function list_rooms_by_kind(home, kind)
    entries.check_kind(kind)
    local tags = {}
    for _, tag in ipairs(list_rooms(home)) do
        -- this room is of the asked kind: keep it.  Otherwise: skip it.
        if read_entry(home, tag).kind == kind then
            tags[#tags + 1] = tag
        end
    end
    return tags
end
-- }}}

-- {{{ local function fingerprint_index
-- One pass over every held room → table fingerprint → { tag, parent }.
-- Two rooms with one token cannot be made here; finding two means a hand
-- edit or a copied folder, and which one a message belongs to would be a
-- guess, so it is an error naming both.
local function fingerprint_index(home)
    local index = {}
    for _, tag in ipairs(list_rooms(home)) do
        local entry = read_entry(home, tag)
        local fingerprint = tokens.token_fingerprint(entry.token)
        -- already seen: two folders hold one room.
        if index[fingerprint] ~= nil then
            error("rooms " .. index[fingerprint].tag .. " and " .. tag .. " hold the same token; "
                .. "one room must not have two folders", 3)
        end
        index[fingerprint] = { tag = tag, parent = entry.parent }
    end
    return index
end
-- }}}

-- {{{ local function find_by_fingerprint
-- The local tag of the held room whose token has this fingerprint, or ""
-- when this home holds no such room.
local function find_by_fingerprint(home, fingerprint)
    check_home(home)
    -- not a fingerprint: a token or tag passed by mistake.
    if not tokens.is_fingerprint(fingerprint) then
        error("find_by_fingerprint needs a fingerprint (64 lower-case hex), got " .. tostring(fingerprint), 2)
    end
    local found = fingerprint_index(home)[fingerprint]
    -- held: its tag.  Not held: "".
    if found == nil then
        return ""
    end
    return found.tag
end
-- }}}

-- {{{ local function check_token_free
-- A token already held by another room is refused: one room per token
-- per home, so a token (and a fingerprint) always leads to one folder.
-- The token itself never appears in the error: errors end up in logs.
local function check_token_free(index, token, own_tag)
    local holder = index[tokens.token_fingerprint(token)]
    -- held by another room: refuse.  Free, or this room's own: fine.
    if holder ~= nil and holder.tag ~= own_tag then
        error("that token is already held here by room " .. holder.tag
            .. " (one room per token; to rejoin it, use that room)", 3)
    end
end
-- }}}

-- {{{ local function check_parent_placement
-- A room may not end up inside itself.  Walks upward from the proposed
-- parent through the held rooms' parent fingerprints; meeting the room's
-- own fingerprint (old or new, during a token change) is a loop.  A
-- parent not held here ends the walk: the room is then a top room on this
-- screen, which is allowed.  `seen` stops a loop already on disk (a hand
-- edit) from walking forever.
local function check_parent_placement(index, own_fingerprints, parent)
    entries.check_parent_shape(parent)
    local seen = {}
    local cursor = parent
    while cursor ~= "" do
        -- the walk reached this room: it would be its own ancestor.
        if own_fingerprints[cursor] then
            error("a room cannot be placed inside itself (its parent chain leads back to it)", 3)
        end
        local holder = index[cursor]
        -- not held here: the top of what this home knows.
        if holder == nil then
            return
        end
        -- visited already: rooms above already form a loop on disk.
        if seen[cursor] then
            error("the rooms above room " .. holder.tag .. " already form a loop", 3)
        end
        seen[cursor] = true
        cursor = holder.parent
    end
end
-- }}}

-- {{{ local function check_filing
-- filed_under is "" or the tag of another held room, and following the
-- filings upward may not come back to this room.
local function check_filing(home, own_tag, filed_under)
    entries.check_filed_shape(filed_under)
    local seen = {}
    local cursor = filed_under
    while cursor ~= "" do
        -- back at this room: a filing loop.
        if cursor == own_tag then
            error("a room cannot be filed inside itself (its filings lead back to it)", 3)
        end
        -- a tag with no folder here: filings are local, so this is a mistake.
        if not room_exists(home, cursor) then
            error("filed_under names room " .. cursor .. ", which is not held here", 3)
        end
        -- visited already: a filing loop already on disk.
        if seen[cursor] then
            error("the filings above room " .. cursor .. " already form a loop", 3)
        end
        seen[cursor] = true
        cursor = read_entry(home, cursor).filed_under
    end
end
-- }}}

-- {{{ local function check_spec
-- A make_room spec has exactly the six fields, no more (a misspelt one
-- would be silently ignored) and no fewer (no field has a default).
local function check_spec(spec)
    if type(spec) ~= "table" then
        error("make_room needs a spec table {label, token, kind, parent, filed_under, members}, got " .. type(spec), 3)
    end
    local known = {}
    for _, field in ipairs(SPEC_FIELDS) do
        known[field] = true
        -- absent: every field must be given; "" and {} are the "none" values.
        if spec[field] == nil then
            error("make_room: spec." .. field .. " is missing (every field is required; use \"\" or {} for none)", 3)
        end
    end
    for key in pairs(spec) do
        -- not one of the six: a misspelling.
        if not known[key] then
            error("make_room: unknown spec field '" .. tostring(key) .. "'", 3)
        end
    end
end
-- }}}

-- {{{ local function make_room
-- spec = { label, token, kind, parent, filed_under, members } (see
-- 006-entry for each).  Builds the room in a hidden folder
-- "rooms/.new-<tag>" — entry, an empty withheld, an empty log — and
-- renames it into place, so the room appears whole or not at all.  Rings
-- "created" once.  Returns the new local tag.
local function make_room(home, spec)
    check_home(home)
    check_spec(spec)
    local tag = new_local_tag()
    local entry = {
        tag = tag, label = spec.label, token = spec.token, kind = spec.kind,
        parent = spec.parent, filed_under = spec.filed_under, members = spec.members,
    }
    local text = entries.entry_text(entry)
    local index = fingerprint_index(home)
    check_token_free(index, spec.token, tag)
    check_parent_placement(index, { [tokens.token_fingerprint(spec.token)] = true }, spec.parent)
    check_filing(home, tag, spec.filed_under)

    local building = home.dir .. "/rooms/.new-" .. tag
    disk.make_dir(building)
    disk.write_atomic(building .. "/entry", text)
    -- withheld and log start empty and belong to recipients and
    -- message-log from here on; they are made here so no room is ever
    -- seen without them (both treat a missing file as damage).
    disk.write_atomic(building .. "/withheld", "")
    disk.write_atomic(building .. "/log", "")
    disk.rename(building, room_dir(home, tag))
    bell.notify(home, tag, "created")
    return tag
end
-- }}}

-- {{{ local function write_entry
-- Writes a whole changed entry over the old one (write-then-rename).
local function write_entry(home, entry)
    disk.write_atomic(entry_path(home, entry.tag), entries.entry_text(entry))
end
-- }}}

-- {{{ local function existing_entry
-- The entry of a room that must already exist, for every write_*.
local function existing_entry(home, tag)
    check_home(home)
    check_tag(tag)
    -- the room must be there to be changed.
    if not room_exists(home, tag) then
        error("no such room: " .. tag, 3)
    end
    return read_entry(home, tag)
end
-- }}}

-- {{{ local function write_label
local function write_label(home, tag, label)
    local entry = existing_entry(home, tag)
    entries.check_label(label)
    entry.label = label
    write_entry(home, entry)
    bell.notify(home, tag, "label")
end
-- }}}

-- {{{ local function write_members
-- Replaces the room's member list with `members` (list of { address,
-- port, heard }), written in the order given.  Called by recipients (103),
-- which decides who may be added; this only checks the shape.
local function write_members(home, tag, members)
    local entry = existing_entry(home, tag)
    entries.check_members(members)
    entry.members = members
    write_entry(home, entry)
    bell.notify(home, tag, "members")
end
-- }}}

-- {{{ local function write_heard
-- Records when one member address was last heard from (whole seconds
-- since 1970).  Rings "heard", not "members": nobody joined or left, so
-- the people/ links need no rebuild on every message that arrives.
local function write_heard(home, tag, address, port, when)
    local entry = existing_entry(home, tag)
    -- not a whole number of seconds: a time cannot be guessed.
    if type(when) ~= "number" or when % 1 ~= 0 or when < 0 then
        error("write_heard: when must be whole seconds since 1970, got " .. tostring(when), 2)
    end
    for _, member in ipairs(entry.members) do
        -- this is the pair: update it, write, ring, done.
        if member.address == address and member.port == port then
            member.heard = when
            write_entry(home, entry)
            bell.notify(home, tag, "heard")
            return
        end
    end
    -- not a member: hearing from an address does not make it one (adding
    -- is recipients' decision, with its refusals).
    error("write_heard: " .. tostring(address) .. " port " .. tostring(port)
        .. " is not a member of room " .. tag, 2)
end
-- }}}

-- {{{ local function write_parent
-- Sets the room's declared parent (a token fingerprint, or "").
local function write_parent(home, tag, parent)
    local entry = existing_entry(home, tag)
    local index = fingerprint_index(home)
    check_parent_placement(index, { [tokens.token_fingerprint(entry.token)] = true }, parent)
    entry.parent = parent
    write_entry(home, entry)
    bell.notify(home, tag, "parent")
end
-- }}}

-- {{{ local function write_filed_under
-- Files the room under another held room on your own screen (or "" to
-- unfile it).  What filing means for the tree is room-tree's (102).
local function write_filed_under(home, tag, filed_under)
    local entry = existing_entry(home, tag)
    check_filing(home, tag, filed_under)
    entry.filed_under = filed_under
    write_entry(home, entry)
    bell.notify(home, tag, "filed")
end
-- }}}

-- {{{ local function change_token
-- Changes a room's token by hand (the owner: "For now, let's say it's
-- manually modified"), to shut someone out.  The room keeps its folder,
-- label, members and log; only the token changes.  The new token is
-- given out by hand, through direct messages (never sealed with the old).
--
-- Child rooms held here name this room by the OLD token's fingerprint;
-- they are re-pointed to the new one so the tree on this screen stays
-- whole (019-options "rooms-token-change-children").  Order: this room's
-- entry first (so the new fingerprint is held), then each child (each
-- rings "parent" and finds its parent there), then "token".
local function change_token(home, tag, token)
    local entry = existing_entry(home, tag)
    tokens.check_token(token)
    local old_fingerprint = tokens.token_fingerprint(entry.token)
    local new_fingerprint = tokens.token_fingerprint(token)
    local index = fingerprint_index(home)
    check_token_free(index, token, tag)
    check_parent_placement(index, { [old_fingerprint] = true, [new_fingerprint] = true }, entry.parent)
    entry.token = token
    write_entry(home, entry)
    -- the same token again: nothing below needs re-pointing.
    if new_fingerprint ~= old_fingerprint then
        for _, child_tag in ipairs(list_rooms(home)) do
            local child = read_entry(home, child_tag)
            -- a child of this room: point it at the new fingerprint.
            if child.parent == old_fingerprint then
                child.parent = new_fingerprint
                write_entry(home, child)
                bell.notify(home, child_tag, "parent")
            end
        end
    end
    bell.notify(home, tag, "token")
end
-- }}}

-- {{{ local function suggest_token
-- A readable random token, with as many words as the home's config says
-- (rooms.suggested-token-words; no default — an unset key is an error).
local function suggest_token(home)
    check_home(home)
    local text = config_value(home, SUGGESTED_WORDS_KEY)
    local count = text:match("^[1-9]%d*$") and tonumber(text)
    -- not a whole number ≥ 1: the setting is wrong, say so.
    if not count then
        error(SUGGESTED_WORDS_KEY .. " must be a whole number >= 1, got '" .. text .. "'", 2)
    end
    return tokens.suggest_token_of(count)
end
-- }}}

return {
    open_home = open_home,
    read_config = read_config,
    set_config = set_config,
    config_value = config_value,
    new_local_tag = new_local_tag,
    is_local_tag = entries.is_local_tag,
    token_fingerprint = tokens.token_fingerprint,
    is_fingerprint = tokens.is_fingerprint,
    suggest_token = suggest_token,
    suggest_token_of = tokens.suggest_token_of,
    make_room = make_room,
    read_entry = read_entry,
    write_label = write_label,
    change_token = change_token,
    write_members = write_members,
    write_heard = write_heard,
    write_parent = write_parent,
    write_filed_under = write_filed_under,
    list_rooms = list_rooms,
    list_rooms_by_kind = list_rooms_by_kind,
    find_by_fingerprint = find_by_fingerprint,
    room_exists = room_exists,
    room_dir = room_dir,
    entry_path = entry_path,
    withheld_path = withheld_path,
    where_path = where_path,
    log_path = log_path,
    ignore_path = ignore_path,
    on_change = bell.on_change,
    notify = bell.notify,
    listener_count = bell.listener_count,
    BELL_KINDS = bell.BELL_KINDS,
    KINDS = entries.KINDS,
    SUGGESTED_WORDS_KEY = SUGGESTED_WORDS_KEY,
}
