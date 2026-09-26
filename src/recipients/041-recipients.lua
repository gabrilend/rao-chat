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
--   * Addresses are added freely, with one refusal: an address on your
--     ignore list (042-ignore-list, issue 103a).  A person who moves shows
--     up as a second address, added beside the first.
--   * Nothing about the room tree is enforced; mismatches are detected.
--     In a declared child room, an address the room tree (issue 102) says
--     is not a member of every room above it ("no"), or whose rooms above
--     this home does not hold ("cannot-check"), is still added — but
--     FLAGGED.  A flagged member is sent nothing until you review it:
--     approving makes it an ordinary member, declining withholds it.  The
--     owner: "The UI might flag them and highlight them in orange or
--     something, to be manually reviewed by the user before sending
--     messages to them".  Flags are private to this home and never sent:
--     "They won't know they're flagged for you".
--   * Whenever a room's members change, the members of every room declared
--     below it are checked again, so someone who leaves a parent (or is
--     shut out of it by a token change) shows up flagged in its children.
--     Nothing removes them.  This module hears those changes on 101's bell,
--     so it catches member changes made by anyone, not only its own.
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
-- The `flagged` file (also made empty by 101, beside `withheld`; private,
-- never sent, written only here) holds one line per reviewed-or-awaiting
-- member: "<address> <port> <state>", where state is
--   no            flagged: not a member of some room above, as seen here
--   cannot-check  flagged: a room above is not held here, so nobody can see
--   approved      reviewed and approved: an ordinary member.  The line is
--                 KEPT so the next re-check does not flag them again — a
--                 member of a child whose parent is not held here would
--                 otherwise come back flagged on every members change.
--                 An approval lasts until the address leaves (owner,
--                 2026-09-25): approval is about a person, not about the
--                 tree, so a later "no" does not flag them again here.
-- A flag awaiting review whose member later passes the check is deleted
-- by the next re-check (owner, 2026-09-25: the flag clears by itself).
-- Declining withholds the address and deletes its line; a confirmed leave
-- deletes its line too, so a returning address is checked afresh.
-- Changes to it ring the bell "withheld": both files only change who you
-- send to, and a new kind would trip every listener that refuses unknown
-- kinds (people-links, frozen this round, is one).
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

-- The three words a line of the `flagged` file may hold, and whether each
-- keeps the member off the send list.  A table, so the list is written once
-- and every reader agrees on it.
local FLAG_STATES = {
    ["no"] = { held_back = true },
    ["cannot-check"] = { held_back = true },
    ["approved"] = { held_back = false },
}

-- {{{ local function read_flags
-- The flagged file as a list of {address, port, state}.  A word that is
-- not one of the three is a damaged line: an error, not skipped.
local function read_flags(home, tag)
    local path = rooms.flagged_path(home, tag)
    local list = {}
    for i, row in ipairs(pairs_.read_pair_file(path, 1)) do
        local state = row.words[1]
        -- not a known state: someone wrote this file by hand, wrongly
        if FLAG_STATES[state] == nil then
            error("recipients: " .. path .. ": unknown flag state '" .. state .. "'")
        end
        list[i] = { address = row.address, port = row.port, state = state }
    end
    return list
end
-- }}}

-- {{{ local function write_flags
-- Rewrites the flagged file and rings "withheld" (who you send to changed).
local function write_flags(home, tag, list)
    local rows = {}
    for i, fl in ipairs(list) do
        rows[i] = { address = fl.address, port = fl.port, words = { fl.state } }
    end
    disk.write_atomic(rooms.flagged_path(home, tag), pairs_.pair_file_text(rows))
    rooms.notify(home, tag, "withheld")
end
-- }}}

-- {{{ local function set_flag
-- Sets the line for one pair to `state` (adding it if absent).  Writes and
-- rings only when something changed; gives true when it did.
local function set_flag(home, tag, address, port, state)
    local list = read_flags(home, tag)
    local at = pairs_.index_of(list, address, port)
    -- no line yet: add one
    if at == 0 then
        list[#list + 1] = { address = address, port = port, state = state }
    -- a line in this very state: nothing to write
    elseif list[at].state == state then
        return false
    -- a line in another state: change it in place
    else
        list[at].state = state
    end
    write_flags(home, tag, list)
    return true
end
-- }}}

-- {{{ local function drop_flag
-- Deletes the line for one pair, if there is one.  Gives true when it did.
local function drop_flag(home, tag, address, port)
    local list = read_flags(home, tag)
    local at = pairs_.index_of(list, address, port)
    -- no line: nothing to delete
    if at == 0 then
        return false
    end
    table.remove(list, at)
    write_flags(home, tag, list)
    return true
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
--   "added-flagged"  appended, and flagged: the room tree answered "no" or
--                    "cannot-check"; also gives that answer and 102's reason
--   "already"        it was a member; nothing written
--   "ignored"        on your ignore list for this room (either level)
-- A member already in the room is not re-judged (ignoring someone does not
-- remove them; see 042), and an ignored address is never checked.
-- The flag is written BEFORE the member, so there is no moment in which a
-- new, unreviewed member sits on the send list.
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
    -- the room tree's check (a top room always answers yes)
    local answer, reason = tree.check_member(home, tag, address, port)
    local flagged = FLAG_STATES[answer] ~= nil and FLAG_STATES[answer].held_back
    -- yes: an ordinary member; no / cannot-check: flagged first
    if answer ~= "yes" then
        -- anything but the three answers is 102 breaking its promise
        if not flagged then
            error("recipients: the room tree answered '" .. tostring(answer) .. "' (yes, no or cannot-check expected)")
        end
        set_flag(home, tag, address, port, answer)
    end
    members[#members + 1] = { address = address, port = port, heard = 0 }
    rooms.write_members(home, tag, members)
    -- flagged: say so, with the tree's answer and reason; else plain added
    if flagged then
        return "added-flagged", answer, reason
    end
    return "added"
end
-- }}}

-- {{{ function M.flags
-- Every line of the room's flagged file: list of {address = string,
-- port = integer, state = "no" | "cannot-check" | "approved"}, file order.
-- May name addresses that are no longer members only if the file was
-- edited by hand (leaving deletes the line).
function M.flags(home, tag)
    return read_flags(home, tag)
end
-- }}}

-- {{{ function M.flagged
-- The members awaiting review (sent nothing): the flags whose state is
-- "no" or "cannot-check".  What a client highlights (orange).
function M.flagged(home, tag)
    local list = {}
    for _, fl in ipairs(read_flags(home, tag)) do
        -- awaiting review: listed; approved: an ordinary member now
        if FLAG_STATES[fl.state].held_back then
            list[#list + 1] = fl
        end
    end
    return list
end
-- }}}

-- {{{ local function must_be_flagged
-- The flag line for a pair awaiting review, or an error: approving or
-- declining someone who is not awaiting review means the caller's picture
-- of the room is wrong.
local function must_be_flagged(home, tag, address, port, what)
    local list = read_flags(home, tag)
    local at = pairs_.index_of(list, address, port)
    -- no line, or an approved one: nothing to review
    if at == 0 or not FLAG_STATES[list[at].state].held_back then
        error("recipients: " .. what .. ": " .. pairs_.key(address, port) .. " is not flagged in " .. tag)
    end
end
-- }}}

-- {{{ function M.approve
-- The person reviewed a flagged member and approved it: it becomes an
-- ordinary member (on the send list unless withheld).  The line is kept as
-- "approved", so a later re-check does not flag it again.  Gives
-- "approved"; errors when the pair is not awaiting review.
function M.approve(home, tag, address, port)
    pairs_.check(address, port, "approve")
    must_be_flagged(home, tag, address, port, "approve")
    set_flag(home, tag, address, port, "approved")
    return "approved"
end
-- }}}

-- {{{ function M.decline
-- The person reviewed a flagged member and declined it: the address is
-- withheld (it stays a member — only its own leave removes it — but hears
-- nothing from you), and the flag line is deleted, since withholding now
-- says everything.  Gives "declined"; errors when not awaiting review.
function M.decline(home, tag, address, port)
    pairs_.check(address, port, "decline")
    must_be_flagged(home, tag, address, port, "decline")
    local list = read_withheld(home, tag)
    -- not yet withheld: withhold now; already withheld by hand: leave it
    if pairs_.index_of(list, address, port) == 0 then
        list[#list + 1] = { address = address, port = port }
        write_withheld(home, tag, list)
    end
    drop_flag(home, tag, address, port)
    return "declined"
end
-- }}}

-- {{{ local function recheck_flagged_in
-- For each member of `tag` awaiting review: ask the tree again.  A
-- member who now passes (a cannot-check whose parent arrived and holds
-- them, or a "no" who joined the room above) has the flag line deleted:
-- a flag says "this does not match the tree", and once it matches there
-- is nothing left to review (owner, 2026-09-25: "cleared").  A member
-- still failing, maybe for the other reason, keeps its flag with the
-- word brought up to date.
local function recheck_flagged_in(home, tag)
    for _, fl in ipairs(M.flagged(home, tag)) do
        local answer = tree.check_member(home, tag, fl.address, fl.port)
        -- passes now: the flag clears itself
        if answer == "yes" then
            drop_flag(home, tag, fl.address, fl.port)
        -- still failing: keep the word current
        else
            set_flag(home, tag, fl.address, fl.port, answer)
        end
    end
end
-- }}}

-- {{{ local function flag_rows
-- Applies the room tree's failing rows ({room, address, port, answer}):
-- each member not yet flagged, not approved and not withheld is flagged
-- with the tree's answer.  Withheld members are skipped: you already send
-- them nothing, and a declined member must not come back orange.
-- Gives the number of newly flagged members.
local function flag_rows(home, rows)
    local count = 0
    for _, row in ipairs(rows) do
        local lines = read_flags(home, row.room)
        local withheld = read_withheld(home, row.room)
        local at = pairs_.index_of(lines, row.address, row.port)
        -- no line and not withheld: newly failing, so flagged now;
        -- a line already (flagged or approved), or withheld: left alone
        if at == 0 and pairs_.index_of(withheld, row.address, row.port) == 0 then
            set_flag(home, row.room, row.address, row.port, row.answer)
            count = count + 1
        end
    end
    return count
end
-- }}}

-- {{{ local function rooms_in
-- The rooms named in the tree's rows, each once, first-seen order.
local function rooms_in(rows)
    local seen, list = {}, {}
    for _, row in ipairs(rows) do
        -- first time this room appears: remember it
        if not seen[row.room] then
            seen[row.room] = true
            list[#list + 1] = row.room
        end
    end
    return list
end
-- }}}

-- {{{ function M.recheck
-- Checks again the members of every room declared below `tag` (and, when
-- `itself` is true, of `tag` too), flagging the newly failing, and
-- re-asking about every flag already awaiting review in the home (a room
-- that holds no failing member any more is not in the tree's rows, so its
-- old flags are found by walking the flagged files).  Gives the number of
-- newly flagged members.  Run from the bell (see below); callable by hand.
function M.recheck(home, tag, itself)
    local rows = tree.failing_below(home, tag)
    -- the room itself too: its own failing members first
    if itself then
        local own = tree.failing_members(home, tag)
        for _, row in ipairs(rows) do own[#own + 1] = row end
        rows = own
    end
    local count = flag_rows(home, rows)
    for _, room in ipairs(rooms.list_rooms(home)) do
        recheck_flagged_in(home, room)
    end
    return count, rooms_in(rows)
end
-- }}}
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
-- Where your next message in this room goes: every member neither withheld
-- nor flagged-awaiting-review, in the entry's order, as a list of
-- {address, port}.  Phase 2 delivers to exactly this list.
function M.send_list(home, tag)
    local withheld = read_withheld(home, tag)
    local flagged = M.flagged(home, tag)
    local list = {}
    for _, m in ipairs(member_list(home, tag)) do
        -- withheld or awaiting review: skipped; everyone else hears you
        if pairs_.index_of(withheld, m.address, m.port) == 0
            and pairs_.index_of(flagged, m.address, m.port) == 0 then
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
-- says nothing about how recently they spoke.  Gives add_member's word
-- (and, for "added-flagged", the tree's answer and reason).
-- Whether add_member's word leaves a member whose time can be recorded:
local IS_MEMBER_AFTER = {
    ["added"] = true,
    ["added-flagged"] = true,
    ["already"] = true,
    ["ignored"] = false,
}
function M.heard_from(home, tag, address, port, when)
    pairs_.check(address, port, "heard_from")
    pairs_.whole_number(tostring(when), "heard_from (when)")
    local outcome, answer, reason = M.add_member(home, tag, address, port)
    -- refused: not a member, so there is no heard[N] to record
    if not IS_MEMBER_AFTER[outcome] then
        return outcome
    end
    local members = member_list(home, tag)
    local m = members[pairs_.index_of(members, address, port)]
    -- newer than what we had: record it; older or same: leave it
    if when > m.heard then
        rooms.write_heard(home, tag, address, port, when)
    end
    return outcome, answer, reason
end
-- }}}

-- {{{ function M.confirm_leave
-- Removes an address from the room.  Called by phase 2 ONLY after the
-- address itself confirmed it left (the call-back check, issues 204/208);
-- nothing else removes a member.  Gives "removed"; errors when the address
-- is not a member (a confirmed leave for someone not here means the caller
-- has the wrong room).  The withheld line, if any, is kept (your choice
-- outlives a leave); the flag line, if any, is deleted (a returning address
-- is checked afresh).
function M.confirm_leave(home, tag, address, port)
    pairs_.check(address, port, "confirm_leave")
    local members = member_list(home, tag)
    local at = pairs_.index_of(members, address, port)
    -- not a member: the caller has the wrong room or address
    if at == 0 then
        error("recipients: confirmed leave for " .. pairs_.key(address, port) .. ", not a member of " .. tag)
    end
    table.remove(members, at)
    drop_flag(home, tag, address, port)
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

-- ---------------------------------------------------------------------
-- listening on 101's bell: re-checking when members or the tree change
-- ---------------------------------------------------------------------

-- {{{ local function recheck_below
local function recheck_below(home, tag)
    M.recheck(home, tag, false)
end
-- }}}

-- {{{ local function recheck_room_and_below
local function recheck_room_and_below(home, tag)
    M.recheck(home, tag, true)
end
-- }}}

-- {{{ local function nothing
local function nothing(home, tag)
end
-- }}}

-- What each ring means for flags:
--   members        this room's members changed: its declared descendants
--                  are checked again (someone who left, or was shut out
--                  of, a parent shows up flagged below it);
--   created,       a room arrived or its declared parent changed: its own
--   parent         members were never checked (a room is made with its
--                  members already in it), so they are checked with its
--                  descendants — a parent arriving also turns its
--                  children's cannot-check into yes or no;
--   token          the room's fingerprint changed; 101 re-points the held
--                  children (each ringing parent), so only its
--                  descendants are checked again here;
--   everything     nothing a flag depends on.  "withheld" is rung by this
--   else           module's own writes, so acting on it would loop.
-- An unknown kind is an error: the contract moved and this table must too.
local bell_actions = {
    ["created"] = recheck_room_and_below,
    ["parent"] = recheck_room_and_below,
    ["members"] = recheck_below,
    ["token"] = recheck_below,
    ["label"] = nothing,
    ["heard"] = nothing,
    ["filed"] = nothing,
    ["withheld"] = nothing,
    ["log"] = nothing,
    ["ignore"] = nothing,
    ["mailbox"] = nothing,
    ["removed-room"] = nothing,
}

-- {{{ local function on_bell
local function on_bell(home, tag, what)
    local action = bell_actions[what]
    -- a kind this module was not told about: stop and say so
    if action == nil then
        error("recipients: the change bell rang with an unknown kind '" .. tostring(what) .. "'")
    end
    action(home, tag)
end
-- }}}

rooms.on_change(on_bell)

return M
