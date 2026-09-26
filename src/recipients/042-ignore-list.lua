-- 042-ignore-list.lua — the ignore list (issue 103a): addresses whose
-- messages you do not want to see.
--
-- The owner asked for two levels: "hide all their messages from me because
-- I don't want to see them, but maybe I do want to know that they said
-- something, or hide them entirely from me."  So each ignored address is
-- kept with a level:
--
--   hide  their messages are dropped on arrival: not written to the room's
--         log, not shown, and nothing is sent back (ignoring is quiet);
--   mark  their messages are not shown, but the room shows that they spoke.
--
-- Ignoring is not withholding.  Withholding (041-recipients) decides whether
-- YOUR messages reach THEM; ignoring decides whether THEIRS reach YOUR
-- eyes.  An ignored address also cannot be (re-)added as a member of any
-- room it is ignored in, so another member sharing their list with you
-- cannot undo your choice.  Nothing tries to follow a person to a new
-- address: the owner, "That'll stay valid until they change IP addresses."
--
-- An entry covers the whole IP address (or hostname): every port there, not
-- only the port written on its line.  That is the owner's "until they
-- change IP addresses" taken at its word (answered 2026-09-25): changing
-- only a port does not escape the list.  The price, accepted: everyone
-- else behind that same public address is covered too.  The port is still
-- written on the line, because an address is always kept as a pair.
--
-- The list is one file for the whole home, rao-home/ignore, one line per
-- ignored address:
--
--     <address> <port> <level> <added> <scope>
--
--   address, port  the pair (see 040-address-pairs)
--   level          hide | mark
--   added          whole seconds since 1970 when it was ignored (or when its
--                  level last changed)
--   scope          "*" for the whole home, or a room's local tag for that
--                  room only (allowed only under ignore.scope = home-and-room)
--
-- One thing the owner has not settled is built both ways and chosen in
-- rao-home/config (read every time, no default):
--
--   ignore.scope       home | home-and-room — may an address be ignored in
--                      one room only?  (103a open question 2)
--
-- Two earlier switches were answered and are fixed in place: a hidden
-- address's messages are not filed (ignore.hide-files was filed |
-- not-filed), and an entry covers every port at its address (ignore.match
-- was pair | host).  Their config keys are no longer read.
--
-- Every change rings the bell with "ignore": on "" for a whole-home entry,
-- on the room's tag for a one-room entry (101's bell accepts both for this
-- kind), so a listener can tell which rooms may look different now.
--
-- Data-making only: nothing here prints or draws.

local rooms = require("002-room-folders")
local disk = require("003-disk")
local pairs_ = require("040-address-pairs")

local M = {}

-- Which level wins when two entries match the same message (two lines at
-- one address with different ports, or a whole-home entry beside a
-- one-room entry): the
-- stronger one.  Hiding entirely is stronger than marking, and "none" is
-- weakest.  A rule, written down here, so the answer never depends on the
-- order of lines in the file.
local STRENGTH = { none = 0, mark = 1, hide = 2 }
local LEVELS = { hide = true, mark = true }

-- {{{ local function ignore_path
-- 101 makes this file empty when the home is opened, so it always exists.
local function ignore_path(home)
    return rooms.ignore_path(home)
end
-- }}}

-- {{{ local function setting
-- Reads this file's one open key and refuses any value it does not know,
-- so a typo in config is caught at the first use.
local KNOWN = {
    ["ignore.scope"] = { home = true, ["home-and-room"] = true },
}
local function setting(home, key)
    local value = rooms.config_value(home, key)
    -- a value this module built: use it; anything else: a config mistake
    if not KNOWN[key][value] then
        error("ignore list: config " .. key .. " = '" .. value .. "' is not a built variant")
    end
    return value
end
-- }}}

-- {{{ local function read_entries
-- The whole list: { address, port, level, added (integer), scope } per line.
local function read_entries(home)
    local path = ignore_path(home)
    local entries = {}
    for _, row in ipairs(pairs_.read_pair_file(path, 3)) do
        local level, added, scope = row.words[1], row.words[2], row.words[3]
        -- only the two levels exist; a third word here is a damaged line
        if not LEVELS[level] then
            error("ignore list: " .. path .. ": unknown level '" .. level .. "'")
        end
        -- a one-room entry names a real room tag; "*" means the whole home
        if scope ~= "*" and not rooms.is_local_tag(scope) then
            error("ignore list: " .. path .. ": scope must be * or a room tag, got '" .. scope .. "'")
        end
        entries[#entries + 1] = {
            address = row.address,
            port = row.port,
            level = level,
            added = pairs_.whole_number(added, path),
            scope = scope,
        }
    end
    return entries
end
-- }}}

-- {{{ local function write_entries
local function write_entries(home, entries)
    local rows = {}
    for i, e in ipairs(entries) do
        rows[i] = { address = e.address, port = e.port, words = { e.level, tostring(e.added), e.scope } }
    end
    disk.write_atomic(ignore_path(home), pairs_.pair_file_text(rows))
end
-- }}}

-- {{{ local function check_scope
-- "*" is always allowed; a room tag only under home-and-room, and only for a
-- room held here.
local function check_scope(home, scope)
    -- the whole home: every variant allows it
    if scope == "*" then
        return
    end
    -- a single room: only when the owner's open question is answered "yes"
    if setting(home, "ignore.scope") ~= "home-and-room" then
        error("ignore list: ignoring in one room only needs ignore.scope = home-and-room")
    end
    -- the room must exist here, or the entry could never match anything
    if not rooms.room_exists(home, scope) then
        error("ignore list: no room " .. tostring(scope) .. " here")
    end
end
-- }}}

-- {{{ local function bell_tag
-- The tag the bell rings on: "" for the whole home, else the one room.
local function bell_tag(scope)
    -- whole home: no single room changed
    if scope == "*" then
        return ""
    end
    -- one room: name it
    return scope
end
-- }}}

-- {{{ local function find_exact
-- Position of the entry for exactly this pair and scope, or 0.
local function find_exact(entries, address, port, scope)
    for i, e in ipairs(entries) do
        -- one entry per (pair, scope): the key of this list
        if e.address == address and e.port == port and e.scope == scope then
            return i
        end
    end
    return 0
end
-- }}}

-- {{{ function M.entries
-- The list as it stands, for showing (a client's "ignored" screen).
function M.entries(home)
    return read_entries(home)
end
-- }}}

-- {{{ function M.ignore
-- Ignores an address at a level, in scope "*" (whole home) or one room tag.
-- Gives "ignored" (new), "level-changed" (was there at the other level) or
-- "already" (was there at this level; nothing written, no bell).
function M.ignore(home, address, port, level, scope, added)
    pairs_.check(address, port, "ignore")
    -- only hide and mark exist
    if not LEVELS[level] then
        error("ignore list: level must be hide or mark, got " .. tostring(level))
    end
    pairs_.whole_number(tostring(added), "ignore (added)")
    check_scope(home, scope)
    local entries = read_entries(home)
    local at = find_exact(entries, address, port, scope)
    local outcome
    -- new entry: append it
    if at == 0 then
        entries[#entries + 1] = { address = address, port = port, level = level, added = added, scope = scope }
        outcome = "ignored"
    -- same level already: nothing to do, and no bell for a non-change
    elseif entries[at].level == level then
        return "already"
    -- other level: change it in place and restamp the time
    else
        entries[at].level = level
        entries[at].added = added
        outcome = "level-changed"
    end
    write_entries(home, entries)
    rooms.notify(home, bell_tag(scope), "ignore")
    return outcome
end
-- }}}

-- {{{ function M.unignore
-- Takes an entry off the list.  Errors when there is no such entry: asking
-- to un-ignore something never ignored means the caller is confused about
-- what the list holds.
function M.unignore(home, address, port, scope)
    pairs_.check(address, port, "unignore")
    local entries = read_entries(home)
    local at = find_exact(entries, address, port, scope)
    -- nothing there: the caller's picture of the list is wrong
    if at == 0 then
        error("ignore list: " .. pairs_.key(address, port) .. " is not ignored in scope " .. tostring(scope))
    end
    table.remove(entries, at)
    write_entries(home, entries)
    rooms.notify(home, bell_tag(scope), "ignore")
    return "unignored"
end
-- }}}

-- {{{ local function entry_matches
-- Does entry e cover a message from (address, port) in room tag?  The port
-- plays no part: an entry covers every port at its address (see the top of
-- this file).  The parameter is kept so every caller passes the full pair.
local function entry_matches(e, tag, address, port)
    -- a one-room entry covers only its own room
    if e.scope ~= "*" and e.scope ~= tag then
        return false
    end
    return e.address == address
end
-- }}}

-- {{{ function M.how_ignored
-- "none", "hide" or "mark" for a message from (address, port) in room tag.
-- The message log's view (105) asks this per message; member adding
-- (041-recipients) asks it before adding.
function M.how_ignored(home, tag, address, port)
    pairs_.check(address, port, "how_ignored")
    local scope_setting = setting(home, "ignore.scope")
    local best = "none"
    for _, e in ipairs(read_entries(home)) do
        -- a one-room line in a home that does not allow them: hand-edited
        if e.scope ~= "*" and scope_setting ~= "home-and-room" then
            error("ignore list: a one-room entry (" .. e.scope .. ") but ignore.scope = home")
        end
        -- covering and stronger than what we have: it wins
        if entry_matches(e, tag, address, port) and STRENGTH[e.level] > STRENGTH[best] then
            best = e.level
        end
    end
    return best
end
-- }}}

-- {{{ function M.files_message
-- Should a message from this address be written to the room's log at all?
-- Everything is filed except messages from a hidden address, which are
-- dropped on arrival (owner, 2026-09-25: "Not saved").  Nothing is sent
-- back, and no cross-check summaries go to it (issue 209), so it cannot
-- tell; un-ignoring lets its server fill the gaps on the next cycle.
-- "mark" is always filed: the room must show that they spoke, so something
-- has to be there to show.
local FILES = {
    none = true,
    mark = true,
    hide = false,
}
function M.files_message(home, tag, address, port)
    return FILES[M.how_ignored(home, tag, address, port)]
end
-- }}}

-- {{{ function M.refused_as_member
-- True when an address is ignored (at either level) in this room: the
-- member filter 041-recipients applies before adding anyone.
function M.refused_as_member(home, tag, address, port)
    return M.how_ignored(home, tag, address, port) ~= "none"
end
-- }}}

return M
