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
-- in each room's entry — the folders stay side by side.  A child room
-- whose parent is not held here starts a mailbox of its own, and once the
-- parent arrives its mailbox's rooms can merge into the parent's — by
-- themselves or when the person says yes (mailboxes.merge-when-parent-
-- arrives).
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
local declared = require("017-declared-settings")

-- The header written into a brand-new config file, so a person opening
-- it in an editor knows what it is.
local NEW_CONFIG_TEXT =
    "# rao-chat settings: one 'key = value' per line (rmail's config format).\n" ..
    "# A setting a module asks for and does not find here is an error, never\n" ..
    "# a quiet default; the error names the key to add.  A line naming a\n" ..
    "# setting no module reads is an error too, naming the line.\n"

-- The settings a new home's config starts with (the owner's values, not
-- defaults: each line is in the file for the person to see and change).
-- git.log-file-size (215a): "as large as is possible to upload to github,
-- defined in a config file with that as default" (owner, 2026-09-27).
local NEW_CONFIG_LINES = "git.log-file-size = 100000000\n"

-- How many words a suggested token has.  Answered by the owner (six:
-- about 77.5 bits from the 7,772-word list, out of reach of an offline
-- guesser; the measurement is in 019-options.lua's history and the
-- planning document's "Answers from the tally").  No longer a setting.
local SUGGESTED_WORD_COUNT = 6

-- The setting deciding what happens once a child room's declared parent
-- arrives here while the child sits in a mailbox of its own: "automatic"
-- (its mailbox's rooms move into the parent's mailbox at once; the
-- owner's preference) or "ask" (they are listed by mergeable_mailboxes
-- until the person says yes with merge_mailbox).  Read only when such a
-- merge is possible.  Declared in 016-settings.lua.  (Round 3's
-- mailboxes.unheld-parent is retired: such a child always starts its own
-- mailbox.)
local MERGE_KEY = "mailboxes.merge-when-parent-arrives"

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

-- {{{ local function read_config_lines
-- The config file as a list of { key, value, number }, every line checked:
-- its shape (004) and that some module declares its name (017).  Called by
-- every read, so a line added by hand is judged the next time anything
-- reads the config, not only at open_home.
local function read_config_lines(home)
    local path = home.dir .. "/config"
    local lines = formats.parse_config_lines(disk.read_all(path), path)
    declared.check_config_lines(lines, path)
    return lines
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
        disk.write_atomic(dir .. "/config", NEW_CONFIG_TEXT .. NEW_CONFIG_LINES)
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
    local home = { dir = dir }
    -- the config must be one this program understands: a line no module
    -- reads stops the opening, naming the line (017-declared-settings).
    read_config_lines(home)
    return home
end
-- }}}

-- {{{ local function read_config
local function read_config(home)
    check_home(home)
    local config = {}
    for _, line in ipairs(read_config_lines(home)) do
        config[line.key] = line.value
    end
    return config
end
-- }}}

-- {{{ local function set_config
-- A name no module declares is refused before anything is written: the
-- line would make the next read of the config an error.
local function set_config(home, key, value)
    check_home(home)
    declared.check_name(key, "set_config")
    local path = home.dir .. "/config"
    -- read and check first: refuse to edit a file that is already broken,
    -- so the error points at the original damage rather than at this write.
    read_config_lines(home)
    disk.write_atomic(path, formats.config_with(disk.read_all(path), key, value))
end
-- }}}

-- {{{ local function config_value
-- The strict lookup: every undecided choice is read through this, so an
-- unset choice stops the program with the line to add, rather than
-- picking a variant nobody chose.
local function config_value(home, key)
    check_home(home)
    -- a name no module declares: the caller forgot its <index>-settings.lua.
    declared.check_name(key, "config_value")
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

-- {{{ local function check_mailbox_spec
-- A make_mailbox spec has exactly { label, kind, port }.  (The fifth field
-- of a mailbox, awaits_parent_of, is make_room's alone.)
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
-- its new tag.  `awaits_parent_of` is the tag of the child room the
-- mailbox is made for while that room's parent is not held here, or "".
-- Rings nothing: each caller decides what to ring.
local function add_mailbox(home, list, label, kind, port, awaits_parent_of)
    local mailbox = { tag = new_local_tag(), label = label, kind = kind, port = port,
                      awaits_parent_of = awaits_parent_of }
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
    ["tree"]    = false,
}

-- {{{ local function make_mailbox
-- Makes the direct-message mailbox (at most one per home) with its port.
-- Returns its tag; rings "mailbox" with "".
local function make_mailbox(home, spec)
    check_home(home)
    check_mailbox_spec(spec)
    mailbox_file.check_mailbox_kind(spec.kind)
    -- a tree mailbox: made by make_room with its top room, not here.
    if not MADE_BY_MAKE_MAILBOX[spec.kind] then
        error("make_mailbox makes only the 'direct' mailbox; a tree mailbox is made by "
            .. "make_room with its top room (spec.mailbox_port)", 2)
    end
    mailbox_file.check_port(spec.port, "make_mailbox: port")
    local list = read_mailboxes(home)
    local existing = the_one_mailbox(list, spec.kind)
    -- already made: one per home, so a second would split the messages.
    if existing ~= "" then
        error("this home already has its '" .. spec.kind .. "' mailbox (" .. existing .. ")", 2)
    end
    local tag = add_mailbox(home, list, spec.label, spec.kind, spec.port, "")
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
-- the direct mailbox; a group room only in a tree mailbox.
local FITTING_MAILBOX_KINDS = {
    ["direct"] = { ["direct"] = true },
    ["group"]  = { ["tree"] = true },
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
-- no default), and the mailbox takes the room's label.  `awaits` is the
-- new room's own tag when it is a child whose parent is not held here (so
-- the mailbox can merge into the parent's later), else "".
local function new_tree_mailbox(spec, why, awaits)
    mailbox_file.check_port(spec.mailbox_port, "make_room: spec.mailbox_port (" .. why .. ")")
    return { new = { label = spec.label, kind = "tree", port = spec.mailbox_port, awaits_parent_of = awaits } }
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

-- Where a new room goes, by what kind of room it is (see the "placement"
-- worked out in make_room).  Each returns { new = ... } or { join = tag };
-- `tag` is the new room's own local tag.
local PLACEMENTS = {
    -- a direct message: the one direct mailbox.
    ["direct"] = function(home, spec, list, index, tag)
        check_no_port(spec, "a direct message joins the one direct mailbox")
        return the_one_or_error(list, "direct",
            "make_mailbox(home, {label = ..., kind = \"direct\", port = ...})")
    end,
    -- a top-level group room: a new tree mailbox with the port given.
    ["top"] = function(home, spec, list, index, tag)
        return new_tree_mailbox(spec, "a top-level group room starts its own mailbox", "")
    end,
    -- a child whose parent is held here: the parent's mailbox (a parent
    -- whose own mailbox still awaits a merge takes its children with it
    -- when it merges).
    ["held-parent"] = function(home, spec, list, index, tag)
        check_no_port(spec, "a child room joins its parent's mailbox")
        return { join = read_entry(home, index[spec.parent].tag).mailbox }
    end,
    -- a child whose parent is not held here: a tree mailbox of its own
    -- (the owner's answer, round 4), remembering the room so it can merge
    -- into the parent's mailbox once the parent arrives.
    ["unheld-parent"] = function(home, spec, list, index, tag)
        return new_tree_mailbox(spec, "a child room whose parent is not held here starts its own mailbox", tag)
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

-- {{{ local function find_mergeable
-- Every mailbox whose rooms can now merge into a parent's: list of
-- { mailbox = its tag, room = the room it was made for, into = the
-- parent's mailbox tag, rooms = sorted tags of the rooms that would move },
-- sorted by mailbox tag.  A mailbox can merge when it remembers a room
-- (awaits_parent_of), that room's declared parent is now held here, and
-- the parent's mailbox is another one.  Reads no config.
local function find_mergeable(home)
    local found = {}
    local list = read_mailboxes(home)
    local index = nil
    for _, mailbox in ipairs(list) do
        -- remembers a room: see whether its parent has arrived.
        if mailbox.awaits_parent_of ~= "" then
            local room = mailbox.awaits_parent_of
            -- the remembered room is gone: nothing in phase 1 removes a
            -- room, so this is a hand edit, named rather than skipped.
            if not room_exists(home, room) then
                error("mailbox " .. mailbox.tag .. " awaits the parent of room " .. room
                    .. ", which is not held here (a hand edit?)", 3)
            end
            local entry = read_entry(home, room)
            -- the room is no longer in the mailbox made for it: write_mailbox
            -- clears the mark when that happens, so this is a hand edit.
            if entry.mailbox ~= mailbox.tag then
                error("mailbox " .. mailbox.tag .. " awaits the parent of room " .. room
                    .. ", but that room is in mailbox " .. entry.mailbox .. " (a hand edit?)", 3)
            end
            index = index or fingerprint_index(home)
            local holder = entry.parent ~= "" and index[entry.parent] or nil
            -- a declared parent, now held here: the merge is possible when
            -- the parent listens elsewhere.  No parent (written away), or
            -- not held yet: keep waiting.
            if holder ~= nil then
                local into = read_entry(home, holder.tag).mailbox
                if into ~= mailbox.tag then
                    found[#found + 1] = { mailbox = mailbox.tag, room = room, into = into,
                                          rooms = list_rooms_by_mailbox(home, mailbox.tag) }
                end
                -- (the parent was put in this very mailbox by hand: nothing
                -- would move; it stays listed nowhere.)
            end
        end
    end
    return found
end
-- }}}

-- {{{ local function clear_awaiting
-- The mailbox no longer waits to merge: its awaits_parent_of becomes "".
-- The mailbox itself stays, with its port, even when empty: phase 2 keeps
-- trying the old port for moved rooms until their members confirm the
-- new one (issue 205/202).
local function clear_awaiting(home, mailbox_tag)
    local list = read_mailboxes(home)
    find_mailbox(list, mailbox_tag).awaits_parent_of = ""
    write_mailboxes(home, list)
end
-- }}}

-- {{{ local function do_merge
-- Moves every room of one mergeable mailbox (a row of find_mergeable)
-- into the parent's mailbox — the room it was made for first, then the
-- rooms made under it, by tag — each ringing "mailbox" with its tag, then
-- clears the mark.  The same per-room move write_mailbox and round 3's
-- waiting mailbox used.
local function do_merge(home, row)
    local order = { row.room }
    for _, tag in ipairs(row.rooms) do
        if tag ~= row.room then order[#order + 1] = tag end
    end
    for _, tag in ipairs(order) do
        move_room_to_mailbox(home, read_entry(home, tag), row.into)
    end
    clear_awaiting(home, row.mailbox)
end
-- }}}

-- What each value of mailboxes.merge-when-parent-arrives does with the
-- merges that became possible.  Each returns true when it moved anything
-- (so settle_merges looks again: a merge can make another possible down a
-- chain).
local MERGE_MODES = {
    -- move them now (the owner: "I prefer automatic").
    ["automatic"] = function(home, rows)
        for _, row in ipairs(rows) do
            do_merge(home, row)
        end
        return true
    end,
    -- move nothing: mergeable_mailboxes lists them until the person says
    -- yes with merge_mailbox.
    ["ask"] = function(home, rows)
        return false
    end,
}

-- {{{ local function settle_merges
-- After anything that can bring a parent here (a room made, a token
-- changed, a parent written): when some mailbox can now merge, the setting
-- says whether it happens.  With nothing mergeable the setting is not read
-- at all (a home need not set it until a merge is possible — but then it
-- must: no default).  Repeated until nothing moves, one merge at a time,
-- because merging one mailbox can make it the parent's mailbox of another.
local function settle_merges(home)
    local rows = find_mergeable(home)
    while #rows > 0 do
        local mode = config_value(home, MERGE_KEY)
        local act = MERGE_MODES[mode]
        -- not a known value: a typo in config, never guessed past.
        if act == nil then
            error(MERGE_KEY .. " must be 'automatic' or 'ask', got '" .. mode .. "'", 3)
        end
        -- moved nothing (ask): leave them listed.  Moved: look again.
        if not act(home, { rows[1] }) then
            return
        end
        rows = find_mergeable(home)
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
-- merges this room's arrival makes possible.  Returns the new local tag.
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
    local place = PLACEMENTS[placement_of(spec, index)](home, spec, list, index, tag)
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
        entry.mailbox = add_mailbox(home, list, place.new.label, place.new.kind, place.new.port,
                                    place.new.awaits_parent_of)
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
    settle_merges(home)
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
-- "mailbox" with the room's tag.  Moving the room a mailbox was made for
-- out of it ends that mailbox's wait to merge: the person placed it.
local function write_mailbox(home, tag, mailbox_tag)
    local entry = existing_entry(home, tag)
    check_tag(mailbox_tag)
    local list = read_mailboxes(home)
    local mailbox = find_mailbox(list, mailbox_tag)
    -- absent: the room would listen nowhere.
    if mailbox == nil then
        error("write_mailbox: no such mailbox: " .. mailbox_tag, 2)
    end
    check_fits(entry.kind, mailbox)
    local leaving = find_mailbox(list, entry.mailbox)
    move_room_to_mailbox(home, entry, mailbox_tag)
    -- it left the mailbox that awaited its parent: that wait is over.
    -- (Any other move: no mark to clear.)
    if leaving ~= nil and leaving.awaits_parent_of == tag and mailbox_tag ~= leaving.tag then
        clear_awaiting(home, leaving.tag)
    end
end
-- }}}

-- {{{ local function mergeable_mailboxes
-- The merges waiting for the person's yes (under "ask"; under "automatic"
-- they happen at once, so this is empty after every write): list of
-- { mailbox, room, into, rooms } as find_mergeable gives, sorted by
-- mailbox tag.  Reads no config.
local function mergeable_mailboxes(home)
    check_home(home)
    return find_mergeable(home)
end
-- }}}

-- {{{ local function merge_mailbox
-- The person's yes: moves the rooms of one mergeable mailbox into its
-- parent's mailbox (each ringing "mailbox" with its tag).  Works under
-- either setting.  A mailbox that cannot merge (not waiting, or the parent
-- not held yet) is an error saying why.  Then settles as after any write,
-- since this merge may make another possible.
local function merge_mailbox(home, mailbox_tag)
    check_home(home)
    check_tag(mailbox_tag)
    local mailbox = read_mailbox(home, mailbox_tag)
    for _, row in ipairs(find_mergeable(home)) do
        -- the one asked for: merge it.
        if row.mailbox == mailbox_tag then
            do_merge(home, row)
            settle_merges(home)
            return
        end
    end
    -- not waiting at all, or its parent not here yet: say which.
    if mailbox.awaits_parent_of == "" then
        error("merge_mailbox: mailbox " .. mailbox_tag .. " is not waiting to merge into a parent's", 2)
    end
    error("merge_mailbox: mailbox " .. mailbox_tag .. " cannot merge yet: the declared parent of room "
        .. mailbox.awaits_parent_of .. " is not held here", 2)
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
    -- a room in a mailbox made for it while its parent was not held, now
    -- given a held parent: it can merge (by the setting).  Any other room
    -- keeps its mailbox (its port does not move; open question 9).
    settle_merges(home)
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
    -- the new token may be the parent a waiting mailbox's room declares.
    settle_merges(home)
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
    declared_settings = declared.declared_settings,
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
    mergeable_mailboxes = mergeable_mailboxes,
    merge_mailbox = merge_mailbox,
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
    MERGE_KEY = MERGE_KEY,
}
