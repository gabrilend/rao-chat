-- 141-claims.lua — the claims a home has made, and its answer when asked
-- about one (issue 204, steps 1 and 2).
--
-- A claim is "I am at this address, listening on this port" (a hello,
-- 205) or "I have left this room" (a leave, 208).  Every claim carries a
-- claim id, 32 hex characters from the kernel, made here when the claim
-- is made.  The claimant keeps every claim it has made in a `claims` file
-- in the room's folder, one line each, tab-separated:
--
--   kind        hello | leave
--   room        the room's local tag (the folder's own; checked on reading)
--   claim id    32 hex characters
--   address     the pair the claim states
--   port
--   made        whole seconds since 1970
--
-- Answering (204's formation, "the answer comes from where the claim was
-- written"): a `did-you` names a claim id and the pair it was asked at;
-- the answer is `yes` only if this room's `claims` file holds that id
-- stating that pair, and `no` otherwise.  The file is read each time, so
-- a restart forgets nothing, and answering changes nothing: a replayed
-- `did-you` gets the same answer (sealing R9).  How long a home can
-- answer is how long it keeps its claims: as long as the room exists.
--
-- Decision of 2026-11-05 (the owner may overturn it): a `did-you` names the
-- pair it was asked at, as well as the claim id, and a claim is confirmed
-- only for the pair it stated.  Someone holding the room's key who passes
-- on a genuine claim id with another pair gets `no` from the claimant at
-- that other pair, if it listens there at all.
--
-- Decision of 2026-11-05 (issue 205; the owner may overturn it): a hello
-- states every pair of its mailbox under one claim id, so `make_for` writes
-- one line per stated pair, all with the same id, and the answer is `yes`
-- when any line with that id states the pair asked about.  A did-you still
-- confirms one pair only.
--
-- The file lives in the room's folder (in 211's RAM copy, synced to disk
-- with the rest of the room).  It is appended to, a line per claim, by the
-- stage that makes claims (205's and 208's senders); answering only reads.

local rooms = require("002-room-folders")
local disk = require("003-disk")
local message_log = require("081-message-log")

local M = {}

-- 213 adds `discover`: the claim a discover or here datagram carries.
M.KINDS = { hello = true, leave = true, discover = true }

-- {{{ function M.path
function M.path(home, tag)
    return rooms.room_dir(home, tag) .. "/claims"
end
-- }}}

-- {{{ function M.is_claim_id
function M.is_claim_id(text)
    return type(text) == "string" and #text == 32 and text:match("^%x+$") ~= nil
end
-- }}}

-- {{{ function M.read
-- home, tag → list of {kind, room, id, address, port, made}, in the order
-- made.  A malformed line is an error naming it.
function M.read(home, tag)
    local path = M.path(home, tag)
    local list = {}
    if not disk.is_file(path) then return list end
    local number = 0
    for line in disk.read_all(path):gmatch("[^\n]+") do
        number = number + 1
        local kind, room, id, address, port, made = line:match("^(%S+)\t(%S+)\t(%S+)\t(%S+)\t(%d+)\t(%d+)$")
        if not kind or not M.KINDS[kind] or not M.is_claim_id(id) then
            error("claims: line " .. number .. " of " .. path .. " is not 'kind TAB room TAB claim id TAB "
                .. "address TAB port TAB made'", 0)
        end
        if room ~= tag then
            error("claims: line " .. number .. " of " .. path .. " names room " .. room .. ", not " .. tag, 0)
        end
        list[#list + 1] = { kind = kind, room = room, id = id, address = address,
                            port = tonumber(port), made = tonumber(made) }
    end
    return list
end
-- }}}

-- {{{ function M.make
-- home, tag, kind, pair ({address, port}: the pair the claim states), now
-- (whole seconds) → the new claim id.  The line is written before the id
-- is given back, so a claim is never sent that its maker could not answer.
function M.make(home, tag, kind, pair, now)
    if not M.KINDS[kind] then error("claims: a claim is a hello or a leave, not " .. tostring(kind), 2) end
    if type(pair.address) ~= "string" or not pair.address:match("^%S+$") or type(pair.port) ~= "number" then
        error("claims: a claim states an address and a port", 2)
    end
    local id = message_log.new_message_id()
    local file = assert(io.open(M.path(home, tag), "ab"))
    assert(file:write(string.format("%s\t%s\t%s\t%s\t%d\t%d\n", kind, tag, id, pair.address, pair.port, now)))
    assert(file:close())
    return id
end
-- }}}

-- {{{ function M.make_for
-- home, tag, kind, pairs (a list of {address, port}; more fields are
-- ignored), now → one new claim id, written once per pair before it is
-- given back.
function M.make_for(home, tag, kind, pairs, now)
    if not M.KINDS[kind] then error("claims: a claim is a hello or a leave, not " .. tostring(kind), 2) end
    if type(pairs) ~= "table" or #pairs == 0 then error("claims: a claim states at least one pair", 2) end
    local lines = {}
    local id = message_log.new_message_id()
    for _, pair in ipairs(pairs) do
        if type(pair.address) ~= "string" or not pair.address:match("^%S+$") or type(pair.port) ~= "number" then
            error("claims: a claim states an address and a port", 2)
        end
        lines[#lines + 1] = string.format("%s\t%s\t%s\t%s\t%d\t%d\n", kind, tag, id, pair.address, pair.port, now)
    end
    local file = assert(io.open(M.path(home, tag), "ab"))
    assert(file:write(table.concat(lines)))
    assert(file:close())
    return id
end
-- }}}

-- {{{ function M.find
-- home, tag, claim id → the claim, or nil.
function M.find(home, tag, id)
    for _, claim in ipairs(M.read(home, tag)) do
        if claim.id == id then return claim end
    end
    return nil
end
-- }}}

-- {{{ function M.answer
-- home, tag, claim id, pair asked at ({address, port}) → "yes" or "no".
function M.answer(home, tag, id, pair)
    if not M.is_claim_id(id) then return "no" end
    for _, claim in ipairs(M.read(home, tag)) do
        if claim.id == id and claim.address == pair.address and claim.port == pair.port then return "yes" end
    end
    return "no"
end
-- }}}

return M
