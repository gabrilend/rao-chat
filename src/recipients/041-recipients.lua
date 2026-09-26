-- 041-recipients.lua — who is in a room, and who your messages there go to
-- (issue 103).
--
-- A room is kept like an rmail contact: a label, a shared token, and a list
-- of addresses — each an address with its own port (040-address-pairs).
-- Those address pairs ARE the room's members; there is no separate member
-- list and no list of names.  This file is the only thing that changes
-- that list, by the rules of rao-chat:
--
--   * Everyone hears you unless you withhold them.  Your messages go to
--     every member not on the room's `withheld` file.  Withholding is all
--     "removing someone" means, and it is yours alone: each person keeps
--     their own withheld list, and nobody can choose who hears anyone else.
--   * Addresses are added freely, with two refusals: an address on your
--     ignore list (042-ignore-list, issue 103a), and, in a child room, an
--     address that is not a member of the parent room as this home sees it
--     (the room tree's check, issue 102).  A person who moves shows up as a
--     second address, added beside the first.
--   * An address leaves only by its own say-so: phase 2 asks the address
--     "did you leave?" and only then calls confirm_leave.  A forged leave
--     notice therefore changes nothing here.  Speaking again adds the
--     address back, as any genuine message does.
--   * The home server never removes a silent member.  It records when each
--     address was last heard from (the entry's heard[N], whole seconds
--     since 1970, 0 = never) so a client can offer pruning by its own
--     rules — the owner: "we can add something in the UI to automatically
--     prune users who've been silent for a while".
--   * Your own devices are never members: they have no entry of their own
--     and read rooms through the home server, so nothing here adds them.
--   * No minimum: a room may have no members but you.
--
-- The `withheld` file (made empty by 101 when the room is made) holds one
-- "<address> <port>" per line.  A withheld line stays when its member
-- leaves, so if they come back your choice still holds.
--
-- Data-making only: nothing here prints or draws.

local rooms = require("002-room-folders")
local tree = require("021-room-tree")
local disk = require("003-disk")
local pairs_ = require("040-address-pairs")
local ignore = require("042-ignore-list")

local M = {}

-- {{{ local function member_list
-- The entry's members, read fresh: list of {address, port, heard}.
local function member_list(home, tag)
    return rooms.read_entry(home, tag).members
end
-- }}}

-- {{{ local function read_withheld
-- The withheld file as a list of {address, port}.
local function read_withheld(home, tag)
    local rows = pairs_.read_pair_file(rooms.withheld_path(home, tag), 0)
    local list = {}
    for i, row in ipairs(rows) do
        list[i] = { address = row.address, port = row.port }
    end
    return list
end
-- }}}

-- {{{ local function write_withheld
local function write_withheld(home, tag, list)
    local rows = {}
    for i, w in ipairs(list) do
        rows[i] = { address = w.address, port = w.port, words = {} }
    end
    disk.write_atomic(rooms.withheld_path(home, tag), pairs_.pair_file_text(rows))
    rooms.notify(home, tag, "withheld")
end
-- }}}

-- {{{ function M.members
-- Every member of a room: list of {address = string, port = integer,
-- heard = integer (seconds since 1970, 0 = never)}, in the entry's order.
function M.members(home, tag)
    return member_list(home, tag)
end
-- }}}

-- {{{ function M.is_member
function M.is_member(home, tag, address, port)
    pairs_.check(address, port, "is_member")
    return pairs_.index_of(member_list(home, tag), address, port) ~= 0
end
-- }}}

-- {{{ function M.add_member
-- Adds an address pair to a room.  Gives one word, because a refusal is an
-- ordinary answer (another member's list may well hold someone you ignore):
--   "added"          appended to the entry, never heard from yet (heard 0)
--   "already"        it was a member; nothing written
--   "ignored"        on your ignore list for this room (either level)
--   "not-in-parent"  a child room, and the address is not a member of the
--                    parent room as this home sees it
-- The checks run in that order: a member already in the room is not
-- re-judged (ignoring someone does not remove them; see 042).
function M.add_member(home, tag, address, port)
    pairs_.check(address, port, "add_member")
    local members = member_list(home, tag)
    -- already there: nothing to do
    if pairs_.index_of(members, address, port) ~= 0 then
        return "already"
    end
    -- on the ignore list: refused, so syncing cannot undo your choice
    if ignore.refused_as_member(home, tag, address, port) then
        return "ignored"
    end
    -- the tree's rule for child rooms (a top room always passes)
    local may, why = tree.may_join(home, tag, address, port)
    if not may then
        return "not-in-parent", why
    end
    members[#members + 1] = { address = address, port = port, heard = 0 }
    rooms.write_members(home, tag, members)
    return "added"
end
-- }}}

-- {{{ function M.withheld
-- The room's withheld list: list of {address, port}.  May hold addresses
-- that are no longer members (kept for if they come back).
function M.withheld(home, tag)
    return read_withheld(home, tag)
end
-- }}}

-- {{{ function M.withhold
-- Stops your messages in this room reaching one member.  "withheld" or
-- "already".  Withholding a non-member is an error: there is nobody there
-- to stop sending to, so the caller has the wrong room or address.
function M.withhold(home, tag, address, port)
    pairs_.check(address, port, "withhold")
    -- only members can be withheld
    if pairs_.index_of(member_list(home, tag), address, port) == 0 then
        error("recipients: " .. pairs_.key(address, port) .. " is not a member of " .. tag)
    end
    local list = read_withheld(home, tag)
    -- already withheld: no write, no bell
    if pairs_.index_of(list, address, port) ~= 0 then
        return "already"
    end
    list[#list + 1] = { address = address, port = port }
    write_withheld(home, tag, list)
    return "withheld"
end
-- }}}

-- {{{ function M.unwithhold
-- Brings a withheld address back onto the send list.  Errors when it was
-- not withheld (the caller's picture of the list is wrong).
function M.unwithhold(home, tag, address, port)
    pairs_.check(address, port, "unwithhold")
    local list = read_withheld(home, tag)
    local at = pairs_.index_of(list, address, port)
    -- not on the list: nothing to undo
    if at == 0 then
        error("recipients: " .. pairs_.key(address, port) .. " is not withheld in " .. tag)
    end
    table.remove(list, at)
    write_withheld(home, tag, list)
    return "unwithheld"
end
-- }}}

-- {{{ function M.send_list
-- Where your next message in this room goes: every member not withheld,
-- in the entry's order, as a list of {address, port}.  Phase 2 delivers to
-- exactly this list.
function M.send_list(home, tag)
    local withheld = read_withheld(home, tag)
    local list = {}
    for _, m in ipairs(member_list(home, tag)) do
        -- withheld: skipped; everyone else hears you
        if pairs_.index_of(withheld, m.address, m.port) == 0 then
            list[#list + 1] = { address = m.address, port = m.port }
        end
    end
    return list
end
-- }}}

-- {{{ function M.heard_from
-- A genuine message arrived in this room from (address, port), written at
-- `when` (whole seconds).  The address is added if it is not a member
-- (the same refusals as add_member), and its last-heard time is moved
-- forward to `when` — never backward, since a late-delivered old message
-- says nothing about how recently they spoke.  Gives add_member's word.
function M.heard_from(home, tag, address, port, when)
    pairs_.check(address, port, "heard_from")
    pairs_.whole_number(tostring(when), "heard_from (when)")
    local outcome, why = M.add_member(home, tag, address, port)
    -- refused: not a member, so there is no heard[N] to record
    if outcome ~= "added" and outcome ~= "already" then
        return outcome, why
    end
    local members = member_list(home, tag)
    local m = members[pairs_.index_of(members, address, port)]
    -- newer than what we had: record it; older or same: leave it
    if when > m.heard then
        rooms.write_heard(home, tag, address, port, when)
    end
    return outcome
end
-- }}}

-- {{{ function M.confirm_leave
-- Removes an address from the room.  Called by phase 2 ONLY after the
-- address itself confirmed it left (the call-back check, issues 204/208);
-- nothing else removes a member.  Gives "removed"; errors when the address
-- is not a member (a confirmed leave for someone not here means the caller
-- has the wrong room).  The withheld line, if any, is kept.
function M.confirm_leave(home, tag, address, port)
    pairs_.check(address, port, "confirm_leave")
    local members = member_list(home, tag)
    local at = pairs_.index_of(members, address, port)
    -- not a member: the caller has the wrong room or address
    if at == 0 then
        error("recipients: confirmed leave for " .. pairs_.key(address, port) .. ", not a member of " .. tag)
    end
    table.remove(members, at)
    rooms.write_members(home, tag, members)
    return "removed"
end
-- }}}

-- {{{ function M.silent_since
-- Members not heard from since `since` (whole seconds): those whose last
-- heard time is earlier, including those never heard (0).  What a client's
-- pruning offer is built on; nothing here removes them.
function M.silent_since(home, tag, since)
    local list = {}
    for _, m in ipairs(member_list(home, tag)) do
        -- silent longer than asked: listed; heard since: not
        if m.heard < since then
            list[#list + 1] = m
        end
    end
    return list
end
-- }}}

-- {{{ local function direct_labels
-- Labels of every direct-message room whose members include the pair.
local function direct_labels(home, address, port)
    local labels = {}
    for _, tag in ipairs(rooms.list_rooms_by_kind(home, "direct")) do
        local entry = rooms.read_entry(home, tag)
        -- this direct message holds the address: its label names the person
        if pairs_.index_of(entry.members, address, port) ~= 0 then
            labels[#labels + 1] = entry.label
        end
    end
    table.sort(labels)
    return labels
end
-- }}}

-- {{{ function M.shown_as
-- How to show a member: { text = string, how = "label" | "labels" |
-- "address" }.  One direct-message room holds the address: its label.
-- None: the address itself, "<address> <port>".  Several: an undecided
-- choice, read from config recipients.shared-address-label only when it
-- happens — "all-labels" joins them (sorted, ", "), "address" shows the
-- address, since the name is ambiguous.
local SHARED = {
    ["all-labels"] = function(labels, address, port)
        return { text = table.concat(labels, ", "), how = "labels" }
    end,
    ["address"] = function(labels, address, port)
        return { text = pairs_.key(address, port), how = "address" }
    end,
}
function M.shown_as(home, address, port)
    pairs_.check(address, port, "shown_as")
    local labels = direct_labels(home, address, port)
    -- nobody you message directly: show where it is
    if #labels == 0 then
        return { text = pairs_.key(address, port), how = "address" }
    end
    -- exactly one direct message: that is who it is
    if #labels == 1 then
        return { text = labels[1], how = "label" }
    end
    -- several: the owner's choice decides
    local mode = rooms.config_value(home, "recipients.shared-address-label")
    local shape = SHARED[mode]
    -- a value this module did not build: stop at the typo
    if shape == nil then
        error("recipients: config recipients.shared-address-label = '" .. mode .. "' is not a built variant")
    end
    return shape(labels, address, port)
end
-- }}}

return M
