-- 147-leaving.lua — leaving a room, and the tombstone a confirmed leave
-- leaves behind (issue 208).
--
-- Leaving (the leaver's side, 134's `Stage:leave`): a `leave` record (126)
-- with a claim id (141) goes to every pair on the room's send list, one
-- job per pair, resent until an ack names the claim (145's `attempt`).
-- The room stays: its `claims` file must keep answering `did-you` until
-- every member has called back.  A `left-by-me` file in the room's folder
-- holds the leave's written time; while it is there the room gets no
-- start-up hellos (a hello would undo the leave).  Writing in the room
-- again removes it: speaking again is rejoining.
--
-- Receiving (`receive`, handed a decoded leave by 133's on_claim seam):
--   - this home's own leave sent back: nothing (sealing R9);
--   - a stated pair that is not a member: nothing to remove;
--   - a leave older than the newest message filed from that pair: ignored
--     (open question 1, the proposal; decision of 2026-11-05) — it is a
--     replay from before the leaver came back;
--   - every other pair is handed to 142's `heard`: only the leaving pair
--     itself can say yes.  On yes (142's leave action, `confirm`): 103's
--     confirm_leave, a line in the `left` file, and the pair's line in
--     `delivered` dropped, so nothing pending is sent to it.
--
-- The `left` file, one line per pair, tab-separated:
--   address     text
--   port        integer
--   confirmed   whole seconds (this home's clock)
--   claim id    32 hex
--   written     the leave's written time (the leaver's clock)
-- The fifth field is a decision of 2026-11-05 (the owner may overturn
-- it): "newer than the leave" compares the leaver's own written times, as
-- the issue's Costs say, so the leave's own time is kept with it.
--
-- What undoes a leave: the leaver's own speech.  A message from the left
-- pair's address written after the leave re-adds the pair and clears its
-- line (133's file_record); a confirmed hello re-adds it and clears the
-- line (142's hello action).  A members list (207, not built) must not
-- re-add a left pair: `may_add_from_list` is the guard 207 calls.

local rooms = require("002-room-folders")
local disk = require("003-disk")
local recipients = require("041-recipients")
local message_log = require("081-message-log")
local delivered = require("130-delivered")
local claims = require("141-claims")
local call_back = require("142-call-back")
local hello = require("145-hello")

local M = {}

-- {{{ function M.path
function M.path(home, tag)
    return rooms.room_dir(home, tag) .. "/left"
end
-- }}}

-- {{{ function M.read
-- home, tag → list of {address, port, confirmed, claim, written}.  A
-- malformed line is an error naming it.
function M.read(home, tag)
    local path = M.path(home, tag)
    local list = {}
    if not disk.is_file(path) then return list end
    local number = 0
    for line in disk.read_all(path):gmatch("[^\n]+") do
        number = number + 1
        local address, port, confirmed, claim, written = line:match("^(%S+)\t(%d+)\t(%d+)\t(%x+)\t(%d+)$")
        if not address or not claims.is_claim_id(claim) then
            error("left: line " .. number .. " of " .. path .. " is not 'address TAB port TAB confirmed TAB "
                .. "claim id TAB written'", 0)
        end
        list[#list + 1] = { address = address, port = tonumber(port), confirmed = tonumber(confirmed),
                            claim = claim, written = tonumber(written) }
    end
    return list
end
-- }}}

-- {{{ local function write_list
local function write_list(home, tag, list)
    local out = {}
    for _, e in ipairs(list) do
        out[#out + 1] = string.format("%s\t%d\t%d\t%s\t%d\n", e.address, e.port, e.confirmed, e.claim, e.written)
    end
    disk.write_atomic(M.path(home, tag), table.concat(out))
end
-- }}}

-- {{{ function M.find
-- home, tag, pair → its line, or nil.
function M.find(home, tag, pair)
    for _, e in ipairs(M.read(home, tag)) do
        if e.address == pair.address and e.port == pair.port then return e end
    end
    return nil
end
-- }}}

-- {{{ function M.record
-- home, tag, pair, confirmed, claim id, written: the pair's line, replacing
-- any it had.
function M.record(home, tag, pair, confirmed, claim, written)
    local list = {}
    for _, e in ipairs(M.read(home, tag)) do
        if not (e.address == pair.address and e.port == pair.port) then list[#list + 1] = e end
    end
    list[#list + 1] = { address = pair.address, port = pair.port, confirmed = confirmed, claim = claim, written = written }
    write_list(home, tag, list)
end
-- }}}

-- {{{ function M.clear
-- home, tag, pair → true when the pair had a line and it was removed.
function M.clear(home, tag, pair)
    local list, found = {}, false
    for _, e in ipairs(M.read(home, tag)) do
        if e.address == pair.address and e.port == pair.port then found = true else list[#list + 1] = e end
    end
    if found then write_list(home, tag, list) end
    return found
end
-- }}}

-- {{{ function M.may_add_from_list
-- 207's guard: a pair named by a members list is not added while it has a
-- line here (a replayed old list must not undo a confirmed leave).
function M.may_add_from_list(home, tag, pair)
    return M.find(home, tag, pair) == nil
end
-- }}}

-- {{{ function M.at_address
-- home, tag, host → the one left pair at that address, or nil (none, or
-- several: the source port cannot say which).
function M.at_address(home, tag, host)
    local found = nil
    for _, e in ipairs(M.read(home, tag)) do
        if e.address == host then
            if found then return nil end
            found = e
        end
    end
    return found
end
-- }}}

-- {{{ function M.latest_from
-- home, tag, pair → the newest written time of a record filed from that
-- pair, or 0.
function M.latest_from(home, tag, pair)
    local from = pair.address .. " " .. pair.port
    local latest = 0
    for _, record in ipairs(message_log.read(home, tag)) do
        if record.from == from and record.written > latest then latest = record.written end
    end
    return latest
end
-- }}}

-- {{{ function M.confirm
-- 142's leave action: home, tag, pair, now, the check (its claim and the
-- leave's written time) → "removed", or "recorded" when the pair was no
-- longer a member.
function M.confirm(home, tag, pair, now, check)
    if type(check.written) ~= "number" then error("leaving: a leave check without the leave's written time", 2) end
    local word = "recorded"
    if recipients.is_member(home, tag, pair.address, pair.port) then
        recipients.confirm_leave(home, tag, pair.address, pair.port)
        word = "removed"
    end
    M.record(home, tag, pair, now, check.claim, check.written)
    delivered.drop(home, tag, pair)
    return word
end
-- }}}

-- {{{ function M.receive
-- stage (134), tag, the decoded leave, peer (never called), now → the
-- ack's word and the checks made.
function M.receive(stage, tag, record, peer, now)
    local home = stage.home
    local word = hello.word_for(stage, tag, record.claim)
    local made = {}
    -- this home's own leave, sent back
    if claims.find(home, tag, record.claim) then return word, made end
    for _, pair in ipairs(record.pairs) do
        if recipients.is_member(home, tag, pair.address, pair.port)
            and M.latest_from(home, tag, pair) <= record.written then
            local check = call_back.heard(stage, tag, { kind = "leave", id = record.claim,
                address = pair.address, port = pair.port }, peer, now)
            check.written = record.written
            made[#made + 1] = check
        end
    end
    return word, made
end
-- }}}

-- {{{ function M.on_claim
-- What 133's on_claim seam calls: a hello or a leave to its receiver.
function M.on_claim(stage, tag, record, peer, now)
    if record.kind == "leave" then return M.receive(stage, tag, record, peer, now) end
    return hello.receive(stage, tag, record, peer, now)
end
-- }}}

-- The leaver's own side: `left-by-me`.

-- {{{ function M.own_path
function M.own_path(home, tag)
    return rooms.room_dir(home, tag) .. "/left-by-me"
end
-- }}}

-- {{{ function M.mark_own
function M.mark_own(home, tag, written)
    disk.write_atomic(M.own_path(home, tag), string.format("%d\n", written))
end
-- }}}

-- {{{ function M.own_left
-- home, tag → the written time of this home's leave, or nil.
function M.own_left(home, tag)
    local path = M.own_path(home, tag)
    if not disk.is_file(path) then return nil end
    local written = disk.read_all(path):match("^(%d+)\n$")
    if not written then error("left-by-me: " .. path .. " is not one whole number", 0) end
    return tonumber(written)
end
-- }}}

-- {{{ function M.clear_own
function M.clear_own(home, tag)
    if disk.is_file(M.own_path(home, tag)) then os.remove(M.own_path(home, tag)) end
end
-- }}}

return M
