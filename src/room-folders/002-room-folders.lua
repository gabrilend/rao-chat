-- 002-room-folders.lua — the home folder, its settings, and its rooms.
--
-- A rao-chat home server keeps everything in one folder, rao-home:
--
--     rao-home/
--       config                   settings, "key = value" (rmail's format)
--       mailboxes                which listening port each group of rooms uses
--                                (014-mailboxes; made empty here)
--       ignore                   addresses you ignore (the ignore list's file; made empty here)
--       rooms/<local tag>/entry     what the room is (006-entry: label, token, kind,
--                                   parent, mailbox, filed-under, member addresses)
--       rooms/<local tag>/withheld  members you do not send to (recipients'; made empty here)
--       rooms/<local tag>/flagged   members awaiting your review, private (recipients'; made empty here)
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
-- Rooms are also grouped into mailboxes, each with its own listening
-- port: a top-level group room starts a new one and every room made under
-- it joins it; all direct messages share one.  The mailbox is only named
-- in each room's entry — the folders stay side by side.
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
local mailbox_file = require("014-mailboxes")

-- The header written into a brand-new config file, so a person opening
-- it in an editor knows what it is.
local NEW_CONFIG_TEXT =
    "# rao-chat settings: one 'key = value' per line (rmail's config format).\n" ..
    "# A setting a module asks for and does not find here is an error, never\n" ..
    "# a quiet default; the error names the key to add.\n"

-- How many words a suggested token has.  Answered by the owner (six:
-- about 77.5 bits from the 7,772-word list, out of reach of an offline
-- guesser; the measurement is in 019-options.lua's history and the
-- planning document's "Answers from the tally").  No longer a setting.
local SUGGESTED_WORD_COUNT = 6

-- The config key deciding which mailbox a child room goes in when its
-- declared parent is not held here (019-options "rooms-unheld-parent-
-- mailbox", issue 102's open question).  Read only in that case.
local UNHELD_PARENT_KEY = "mailboxes.unheld-parent"

-- The fields a make_room spec must have, every one of them.
local SPEC_FIELDS = { "label", "token", "kind", "parent", "filed_under", "members", "mailbox_port" }

-- The mailbox fields make_mailbox takes.
local MAILBOX_SPEC_FIELDS = { "label", "kind", "port" }

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
    -- the mailboxes file starts with no mailboxes: each needs a port,
    -- and there is no default port to invent one from.
    if not disk.is_file(dir .. "/mailboxes") then
        disk.write_atomic(dir .. "/mailboxes", mailbox_file.mailboxes_text({}))
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

-- {{{ local function flagged_path
-- The flagged file's format is the recipients module's (103): members of
-- a child room not found in every room above it, private to this home.
local function flagged_path(home, tag)
    return room_dir(home, tag) .. "/flagged"
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

-- {{{ local function mailboxes_path
-- The mailboxes file's format is 014-mailboxes'.
local function mailboxes_path(home)
    check_home(home)
    return home.dir .. "/mailboxes"
end
-- }}}

-- Where reports of two mailboxes sharing one port go: a function taking
-- one line of text.  Sharing a port is allowed but not recommended, so it
-- is reported every time the mailboxes file is read — a warning the
-- person sees, not an error that stops the server.  Starts as a line on
-- stderr; tests and the demo set their own to count and show reports.
local warning_sink = function(text)
    io.stderr:write("rao-chat WARNING: ", text, "\n")
end

-- {{{ local function set_warning_sink
local function set_warning_sink(sink)
    -- only a function can be handed a report.
    if type(sink) ~= "function" then
        error("set_warning_sink needs a function(text), got " .. type(sink), 2)
    end
    warning_sink = sink
end
-- }}}

-- {{{ local function report_shared_ports
-- One report per port named by two or more mailboxes, naming the port and
-- each mailbox by label and tag, so the person can tell which to move.
local function report_shared_ports(list)
    local labels = {}
    for _, mailbox in ipairs(list) do labels[mailbox.tag] = mailbox.label end
    local shared = mailbox_file.shared_ports_of(list)
    for _, port_group in ipairs(shared) do
        local names = {}
        for _, tag in ipairs(port_group.mailboxes) do
            names[#names + 1] = "\"" .. labels[tag] .. "\" (" .. tag .. ")"
        end
        warning_sink("port " .. port_group.port .. " is shared by " .. #names .. " mailboxes: "
            .. table.concat(names, ", ") .. "; a message arriving there is tried against all "
            .. "their rooms' keys (allowed, not recommended: give each mailbox its own port)")
    end
    return shared
end
-- }}}

-- {{{ local function read_mailboxes
-- Every mailbox, sorted by tag: list of { tag, label, kind, port }.  Read
-- fresh each call, and a shared port is reported each call.
local function read_mailboxes(home)
    local path = mailboxes_path(home)
    local list = mailbox_file.parse_mailboxes(disk.read_all(path), path)
    report_shared_ports(list)
    return list
end
-- }}}

-- {{{ local function write_mailboxes
local function write_mailboxes(home, list)
    disk.write_atomic(mailboxes_path(home), mailbox_file.mailboxes_text(list))
end
-- }}}

-- {{{ local function find_mailbox
-- The mailbox with this tag from a list already read, or nil when the
-- list has none (callers turn nil into their own error).
local function find_mailbox(list, mailbox_tag)
    for _, mailbox in ipairs(list) do
        if mailbox.tag == mailbox_tag then
            return mailbox
        end
    end
    return nil
end
-- }}}

-- {{{ local function read_mailbox
local function read_mailbox(home, mailbox_tag)
    check_home(home)
    check_tag(mailbox_tag)
    local mailbox = find_mailbox(read_mailboxes(home), mailbox_tag)
    -- absent: callers ask for mailboxes they believe exist.
    if mailbox == nil then
        error("no such mailbox: " .. mailbox_tag, 2)
    end
    return mailbox
end
-- }}}

-- {{{ local function the_one_mailbox
-- The tag of the one mailbox of a one-per-home kind in a list, or "".
local function the_one_mailbox(list, kind)
    for _, mailbox in ipairs(list) do
        if mailbox.kind == kind then
            return mailbox.tag
        end
    end
    return ""
end
-- }}}

-- {{{ local function direct_mailbox
-- The tag of the mailbox every direct message goes in, or "" if it has
-- not been made yet (make_mailbox with kind "direct").
local function direct_mailbox(home)
    return the_one_mailbox(read_mailboxes(home), "direct")
end
-- }}}

-- {{{ local function waiting_mailbox
-- The tag of the waiting mailbox (only under mailboxes.unheld-parent =
-- waiting-mailbox), or "" if it has not been made.
local function waiting_mailbox(home)
    return the_one_mailbox(read_mailboxes(home), "waiting")
end
-- }}}

-- {{{ local function check_mailbox_spec
-- A make_mailbox spec has exactly { label, kind, port }.
local function check_mailbox_spec(spec)
    if type(spec) ~= "table" then
        error("make_mailbox needs a spec table {label, kind, port}, got " .. type(spec), 3)
    end
    local known = {}
    for _, field in ipairs(MAILBOX_SPEC_FIELDS) do
        known[field] = true
        -- absent: no field has a default (least of all the port).
        if spec[field] == nil then
            error("make_mailbox: spec." .. field .. " is missing", 3)
        end
    end
    for key in pairs(spec) do
        -- not one of the three: a misspelling.
        if not known[key] then
            error("make_mailbox: unknown spec field '" .. tostring(key) .. "'", 3)
        end
    end
end
-- }}}

-- {{{ local function add_mailbox
-- Appends one new mailbox to the file (every rule of 014 checked on the
-- whole new list, so a second direct mailbox is refused here) and returns
-- its new tag.  Rings nothing: each caller decides what to ring.
local function add_mailbox(home, list, label, kind, port)
    local mailbox = { tag = new_local_tag(), label = label, kind = kind, port = port }
    local grown = {}
    for position, existing in ipairs(list) do grown[position] = existing end
    grown[#grown + 1] = mailbox
    write_mailboxes(home, grown)
    return mailbox.tag
end
-- }}}

-- Which kinds make_mailbox may make.  A tree mailbox is made only by
-- make_room, with the top room it belongs to, so no tree mailbox is ever
-- without the room that gave it its label.
local MADE_BY_MAKE_MAILBOX = {
    ["direct"]  = true,
    ["waiting"] = true,
    ["tree"]    = false,
}

-- {{{ local function make_mailbox
-- Makes the direct-message mailbox or the waiting mailbox (at most one of
-- each per home) with its port.  Returns its tag; rings "mailbox" with "".
local function make_mailbox(home, spec)
    check_home(home)
    check_mailbox_spec(spec)
    mailbox_file.check_mailbox_kind(spec.kind)
    -- a tree mailbox: made by make_room with its top room, not here.
    if not MADE_BY_MAKE_MAILBOX[spec.kind] then
        error("make_mailbox makes only 'direct' and 'waiting' mailboxes; a tree mailbox is made by "
            .. "make_room with its top room (spec.mailbox_port)", 2)
    end
    mailbox_file.check_port(spec.port, "make_mailbox: port")
    local list = read_mailboxes(home)
    local existing = the_one_mailbox(list, spec.kind)
    -- already made: one per home, so a second would split the messages.
    if existing ~= "" then
        error("this home already has its '" .. spec.kind .. "' mailbox (" .. existing .. ")", 2)
    end
    local tag = add_mailbox(home, list, spec.label, spec.kind, spec.port)
    bell.notify(home, "", "mailbox")
    return tag
end
-- }}}

-- {{{ local function write_mailbox_port
-- Moves a mailbox to another listening port.  Rings "mailbox" with "".
local function write_mailbox_port(home, mailbox_tag, port)
    check_home(home)
    check_tag(mailbox_tag)
    mailbox_file.check_port(port, "write_mailbox_port: port")
    local list = read_mailboxes(home)
    local mailbox = find_mailbox(list, mailbox_tag)
    -- absent: nothing to move.
    if mailbox == nil then
        error("no such mailbox: " .. mailbox_tag, 2)
    end
    mailbox.port = port
    write_mailboxes(home, list)
    bell.notify(home, "", "mailbox")
end
-- }}}

-- {{{ local function mailboxes_by_port
-- The tags of every mailbox listening on this port, sorted.  Phase 2's
-- trial opening: a frame arriving on `port` is tried against the keys of
-- the rooms in these mailboxes (list_rooms_by_mailbox), and no others.
local function mailboxes_by_port(home, port)
    check_home(home)
    mailbox_file.check_port(port, "mailboxes_by_port: port")
    local tags = {}
    for _, mailbox in ipairs(read_mailboxes(home)) do
        -- on this port: one of the mailboxes to try.
        if mailbox.port == port then
            tags[#tags + 1] = mailbox.tag
        end
    end
    return tags
end
-- }}}

-- {{{ local function shared_ports
-- Every port named by two or more mailboxes: list of { port, mailboxes =
-- sorted list of tags }, sorted by port.  Reported as every read is.
local function shared_ports(home)
    check_home(home)
    local path = mailboxes_path(home)
    return report_shared_ports(mailbox_file.parse_mailboxes(disk.read_all(path), path))
end
-- }}}

-- {{{ local function list_rooms_by_mailbox
-- The rooms in one mailbox, sorted by tag.
local function list_rooms_by_mailbox(home, mailbox_tag)
    read_mailbox(home, mailbox_tag)
    local tags = {}
    for _, tag in ipairs(list_rooms(home)) do
        -- in this mailbox: keep it.  Otherwise: skip it.
        if read_entry(home, tag).mailbox == mailbox_tag then
            tags[#tags + 1] = tag
        end
    end
    return tags
end
-- }}}

-- Which mailbox kinds each room kind may be in: a direct message only in
-- the direct mailbox; a group room in a tree mailbox, or waiting.
local FITTING_MAILBOX_KINDS = {
    ["direct"] = { ["direct"] = true },
    ["group"]  = { ["tree"] = true, ["waiting"] = true },
}

-- {{{ local function check_fits
local function check_fits(room_kind, mailbox)
    -- the room's kind may not be in this mailbox's kind: a direct message
    -- would listen on a group's port, or the reverse.
    if not FITTING_MAILBOX_KINDS[room_kind][mailbox.kind] then
        error("a " .. room_kind .. " room cannot be in a '" .. mailbox.kind .. "' mailbox ("
            .. mailbox.tag .. ")", 3)
    end
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
-- A make_room spec has exactly the seven fields, no more (a misspelt one
-- would be silently ignored) and no fewer (no field has a default).
local function check_spec(spec)
    if type(spec) ~= "table" then
        error("make_room needs a spec table {label, token, kind, parent, filed_under, members, mailbox_port}, got " .. type(spec), 3)
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
        -- not one of the seven: a misspelling.
        if not known[key] then
            error("make_room: unknown spec field '" .. tostring(key) .. "'", 3)
        end
    end
end
-- }}}

-- {{{ local function check_no_port
-- The room joins an existing mailbox, so it may not name a port: a port
-- given here would be silently unused.
local function check_no_port(spec, why)
    if spec.mailbox_port ~= "" then
        error("make_room: spec.mailbox_port must be \"\" here (" .. why .. "), got "
            .. tostring(spec.mailbox_port), 4)
    end
end
-- }}}

-- {{{ local function new_tree_mailbox
-- The room starts a mailbox of its own: its port must be given (there is
-- no default), and the mailbox takes the room's label.
local function new_tree_mailbox(spec, why)
    mailbox_file.check_port(spec.mailbox_port, "make_room: spec.mailbox_port (" .. why .. ")")
    return { new = { label = spec.label, kind = "tree", port = spec.mailbox_port } }
end
-- }}}

-- {{{ local function the_one_or_error
local function the_one_or_error(list, kind, how_to_make)
    local tag = the_one_mailbox(list, kind)
    -- not made yet: the room would have nowhere to listen.  Say how to make it.
    if tag == "" then
        error("make_room: this home has no '" .. kind .. "' mailbox yet; make it first with "
            .. how_to_make, 4)
    end
    return { join = tag }
end
-- }}}

-- A child room whose declared parent is not held here (issue 102's open
-- question; 019-options "rooms-unheld-parent-mailbox").  Each variant
-- returns where the room goes: { new = {label, kind, port} } for a new
-- mailbox, { join = mailbox tag } for an existing one.
local UNHELD_PARENT_VARIANTS = {
    -- its own tree mailbox, as if it were a top room; it stays there when
    -- the parent arrives later, so the port its members use never moves.
    ["own-mailbox"] = function(spec, list)
        return new_tree_mailbox(spec, "a child of a parent not held here starts its own mailbox "
            .. "under " .. UNHELD_PARENT_KEY .. " = own-mailbox")
    end,
    -- the one waiting mailbox, until the parent arrives (settle_waiting).
    ["waiting-mailbox"] = function(spec, list)
        check_no_port(spec, "a child of a parent not held here waits in the waiting mailbox under "
            .. UNHELD_PARENT_KEY .. " = waiting-mailbox")
        return the_one_or_error(list, "waiting",
            "make_mailbox(home, {label = ..., kind = \"waiting\", port = ...})")
    end,
}

-- Where a new room goes, by what kind of room it is (see the "placement"
-- worked out in make_room).  Each returns { new = ... } or { join = tag }.
local PLACEMENTS = {
    -- a direct message: the one direct mailbox.
    ["direct"] = function(home, spec, list, index)
        check_no_port(spec, "a direct message joins the one direct mailbox")
        return the_one_or_error(list, "direct",
            "make_mailbox(home, {label = ..., kind = \"direct\", port = ...})")
    end,
    -- a top-level group room: a new tree mailbox with the port given.
    ["top"] = function(home, spec, list, index)
        return new_tree_mailbox(spec, "a top-level group room starts its own mailbox")
    end,
    -- a child whose parent is held here: the parent's mailbox, whatever
    -- kind it is (a parent still waiting takes its children with it).
    ["held-parent"] = function(home, spec, list, index)
        check_no_port(spec, "a child room joins its parent's mailbox")
        return { join = read_entry(home, index[spec.parent].tag).mailbox }
    end,
    -- a child whose parent is not held here: the owner's open choice.
    ["unheld-parent"] = function(home, spec, list, index)
        local choice = config_value(home, UNHELD_PARENT_KEY)
        local variant = UNHELD_PARENT_VARIANTS[choice]
        -- not a built variant: a typo in config, never guessed past.
        if variant == nil then
            error(UNHELD_PARENT_KEY .. " must be 'own-mailbox' or 'waiting-mailbox', got '" .. choice .. "'", 3)
        end
        return variant(spec, list)
    end,
}

-- {{{ local function placement_of
-- Which of the PLACEMENTS a new room is: a direct message; a group room
-- with no declared parent (top); or a group room whose declared parent is
-- held here, or not.
local function placement_of(spec, index)
    -- a direct message goes with the direct messages, parent or not.
    if spec.kind == "direct" then
        return "direct"
    end
    -- no declared parent: a top-level room.
    if spec.parent == "" then
        return "top"
    end
    -- the parent's fingerprint is one of ours: held.  Otherwise: unheld.
    if index[spec.parent] ~= nil then
        return "held-parent"
    end
    return "unheld-parent"
end
-- }}}

-- {{{ local function check_mailbox_port_shape
-- mailbox_port is "" or a number; which of the two is right depends on
-- where the room goes, and is checked there.
local function check_mailbox_port_shape(value)
    if value ~= "" and type(value) ~= "number" then
        error("make_room: spec.mailbox_port must be a port (whole number) or \"\", got "
            .. type(value) .. " " .. tostring(value), 3)
    end
end
-- }}}

-- {{{ local function move_room_to_mailbox
-- Rewrites one room's entry to name another mailbox and rings "mailbox"
-- with the room's tag.  The caller has checked the mailbox exists and fits.
local function move_room_to_mailbox(home, entry, mailbox_tag)
    entry.mailbox = mailbox_tag
    disk.write_atomic(entry_path(home, entry.tag), entries.entry_text(entry))
    bell.notify(home, entry.tag, "mailbox")
end
-- }}}

-- {{{ local function settle_waiting
-- Under mailboxes.unheld-parent = waiting-mailbox, a child room made while
-- its parent was not held waits in the waiting mailbox.  After anything
-- that can bring a parent here (a room made, a token changed, a parent
-- written), every waiting room whose declared parent is now held — and is
-- not itself waiting — moves into the parent's mailbox.  Repeated until
-- nothing moves, so a waiting chain settles from the top down.  With no
-- waiting mailbox (the own-mailbox variant, or none made yet) nothing
-- waits, and nothing is read but the mailboxes file.
local function settle_waiting(home)
    local waiting = waiting_mailbox(home)
    -- no waiting mailbox: nothing can be waiting.
    if waiting == "" then
        return
    end
    local moved = true
    while moved do
        moved = false
        local index = fingerprint_index(home)
        for _, tag in ipairs(list_rooms(home)) do
            local entry = read_entry(home, tag)
            local holder = entry.parent ~= "" and index[entry.parent] or nil
            -- waiting, with a parent now held: follow the parent unless the
            -- parent is itself still waiting (it moves first, next pass).
            if entry.mailbox == waiting and holder ~= nil then
                local parent_mailbox = read_entry(home, holder.tag).mailbox
                if parent_mailbox ~= waiting then
                    move_room_to_mailbox(home, entry, parent_mailbox)
                    moved = true
                end
            end
        end
    end
end
-- }}}

-- {{{ local function make_room
-- spec = { label, token, kind, parent, filed_under, members,
-- mailbox_port } (see 006-entry for the first six; mailbox_port is the
-- listening port when the room starts a new mailbox, "" when it joins
-- one — PLACEMENTS above says which).  Builds the room in a hidden folder
-- "rooms/.new-<tag>" — entry, an empty withheld, an empty flagged, an
-- empty log — and
-- renames it into place, so the room appears whole or not at all.  Rings
-- "created" once (a new mailbox is covered by it), then settles any
-- waiting rooms this room is the parent of.  Returns the new local tag.
--
-- Order: every check first (fields, token, parent, filing, mailbox), then
-- the new mailbox (if any) into the mailboxes file, then the room.  A
-- crash between those two leaves a mailbox with no room: harmless (an
-- empty mailbox), and never a room naming a mailbox that is not there.
local function make_room(home, spec)
    check_home(home)
    check_spec(spec)
    check_mailbox_port_shape(spec.mailbox_port)
    entries.check_kind(spec.kind)
    local tag = new_local_tag()
    local index = fingerprint_index(home)
    check_token_free(index, spec.token, tag)
    check_parent_placement(index, { [tokens.token_fingerprint(spec.token)] = true }, spec.parent)
    check_filing(home, tag, spec.filed_under)
    local list = read_mailboxes(home)
    local place = PLACEMENTS[placement_of(spec, index)](home, spec, list, index)
    -- a placeholder tag lets the whole entry be checked before anything
    -- is written; the real mailbox tag replaces it below.
    local entry = {
        tag = tag, label = spec.label, token = spec.token, kind = spec.kind,
        parent = spec.parent, mailbox = place.join or tag,
        filed_under = spec.filed_under, members = spec.members,
    }
    local text = entries.entry_text(entry)
    -- a new mailbox: write it now that everything else is known good.
    -- Joining one: the entry already names it.
    if place.new ~= nil then
        entry.mailbox = add_mailbox(home, list, place.new.label, place.new.kind, place.new.port)
        text = entries.entry_text(entry)
    end

    local building = home.dir .. "/rooms/.new-" .. tag
    disk.make_dir(building)
    disk.write_atomic(building .. "/entry", text)
    -- withheld, flagged and log start empty and belong to recipients and
    -- message-log from here on; they are made here so no room is ever
    -- seen without them (each treats a missing file as damage).
    disk.write_atomic(building .. "/withheld", "")
    disk.write_atomic(building .. "/flagged", "")
    disk.write_atomic(building .. "/log", "")
    disk.rename(building, room_dir(home, tag))
    bell.notify(home, tag, "created")
    settle_waiting(home)
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

-- {{{ local function write_mailbox
-- Moves a room into another mailbox by hand.  The room's kind must fit the
-- mailbox's (a direct message only in the direct mailbox).  Rings
-- "mailbox" with the room's tag.
local function write_mailbox(home, tag, mailbox_tag)
    local entry = existing_entry(home, tag)
    check_tag(mailbox_tag)
    local mailbox = find_mailbox(read_mailboxes(home), mailbox_tag)
    -- absent: the room would listen nowhere.
    if mailbox == nil then
        error("write_mailbox: no such mailbox: " .. mailbox_tag, 2)
    end
    check_fits(entry.kind, mailbox)
    move_room_to_mailbox(home, entry, mailbox_tag)
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
    -- a waiting room given a held parent follows it (waiting variant only);
    -- a room already in a mailbox keeps it (its port does not move).
    settle_waiting(home)
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
    -- the new token may be a waiting room's parent's (waiting variant).
    settle_waiting(home)
end
-- }}}

-- {{{ local function suggest_token
-- A readable random token of six words (the owner's answer).  The home is
-- still taken, and checked, so callers written for the round-2 setting
-- need not change; nothing in it is read.  Another count: suggest_token_of.
local function suggest_token(home)
    check_home(home)
    return tokens.suggest_token_of(SUGGESTED_WORD_COUNT)
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
    flagged_path = flagged_path,
    where_path = where_path,
    log_path = log_path,
    ignore_path = ignore_path,
    mailboxes_path = mailboxes_path,
    make_mailbox = make_mailbox,
    read_mailboxes = read_mailboxes,
    read_mailbox = read_mailbox,
    direct_mailbox = direct_mailbox,
    waiting_mailbox = waiting_mailbox,
    list_rooms_by_mailbox = list_rooms_by_mailbox,
    mailboxes_by_port = mailboxes_by_port,
    shared_ports = shared_ports,
    write_mailbox_port = write_mailbox_port,
    write_mailbox = write_mailbox,
    set_warning_sink = set_warning_sink,
    on_change = bell.on_change,
    notify = bell.notify,
    listener_count = bell.listener_count,
    BELL_KINDS = bell.BELL_KINDS,
    KINDS = entries.KINDS,
    MAILBOX_KINDS = mailbox_file.MAILBOX_KINDS,
    SUGGESTED_WORD_COUNT = SUGGESTED_WORD_COUNT,
    UNHELD_PARENT_KEY = UNHELD_PARENT_KEY,
}
