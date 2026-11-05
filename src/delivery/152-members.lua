-- 152-members.lua — contact syncing within a room: a digest of the pairs
-- held, a list on request, and nothing from a list trusted until the pair
-- itself answers (issue 207).
--
-- What a home holds (decision of 2026-11-05; the owner may overturn it):
-- the room's members, flagged or not, plus the pairs this mailbox states
-- for itself (212's own_pairs), less every pair that is not shareable.
-- Counting its own pairs is what lets homes that know each other agree: A
-- holds B and itself, B holds A and itself, and both digests are the same
-- set.  Shareable means public IPv4, global IPv6, or a hostname: private,
-- carrier-grade, link-local and loopback addresses never go in a list
-- (open question 2: never shared; addresses R3).  Pairs confirmed only
-- from inside the house would be 213's to mark; nothing marks them yet.
--
-- The digest: SHA-256 of the held pairs as "<address> <port>" lines,
-- sorted as text, joined by "\n" — stable written fields only — and the
-- count.  Equal digests send nothing more, so idle homes cannot ping-pong
-- (structure R6).
--
-- The exchange, all on the connection the first frame opened:
--   noticing home                      the other home (133 → `answer`)
--   members-digest {id, digest, count} → same digest: ack naming id
--                                        differs: members-ask (its own)
--   members {id, digest, pairs, claims} → ack naming id, after handing the
--                                        list to `receive_list`
-- and anyone may ask (`Stage:ask_members`, the viewer's button):
--   members-ask                         → same digest: ack; differs: members
--
-- When a digest is sent (decision of 2026-11-05): when a call-back
-- confirms a hello and that adds a pair ("added" or "added-flagged", 103),
-- to every pair on the room's send list — the newcomer included, which is
-- how a joiner receives the list.  A pair added from a received list sends
-- nothing (the issue's "caused by an arrival, not by a received list"),
-- and nothing listens to the change bell, so rewriting or reordering the
-- room's entry on disk sends nothing.  Automatic asking (open question 1)
-- is not built: asking is `Stage:ask_members`, called by the viewer.
--
-- A list is a claim by one member about others (addresses R8), so a pair
-- in it is only called back, never added (142's `heard`).  To make that
-- possible a list carries, for each pair, the claim id that pair answered
-- yes to: this home keeps it in the room's `vouched` file when a hello's
-- call-back confirms (142's hello action) — one line per pair, "address TAB
-- port TAB claim id TAB confirmed".  A pair with no vouched claim is held
-- but not listed.  This home's own pairs are listed with a hello claim it
-- makes for them.  A receiver skips pairs it holds, ignored pairs, pairs
-- in its `left` file (208's guard, `may_add_from_list`: a replayed list
-- never re-adds a confirmed leaver), unshareable pairs, and its own
-- claims.

local seal = require("124-seal")
local frames = require("125-frames")
local records = require("126-inner-records")
local room_key = require("123-room-key")
local rooms = require("002-room-folders")
local disk = require("003-disk")
local tokens = require("007-tokens")
local recipients = require("041-recipients")
local ignore = require("042-ignore-list")
local message_log = require("081-message-log")
local send = require("132-send")
local claims = require("141-claims")
local call_back = require("142-call-back")
local leaving = require("147-leaving")
local reach = require("149-reach")

local M = {}

M.KINDS = { ["members-digest"] = true, ["members-ask"] = true, members = true }

-- {{{ function M.shareable
-- An address → the kind it is listed as ("public", "ipv6", "hostname"),
-- or nil when it never leaves this home.
function M.shareable(address)
    local class = reach.classify(address)
    if class == "public" then return "public" end
    if class == "ipv6-global" then return "ipv6" end
    if class == nil and type(address) == "string" and address:match("^[%w][%w%.%-]*$") and address:match("%a") then
        return "hostname"
    end
    return nil
end
-- }}}

-- {{{ function M.vouched_path
function M.vouched_path(home, tag)
    return rooms.room_dir(home, tag) .. "/vouched"
end
-- }}}

-- {{{ function M.read_vouched
-- home, tag → { ["address port"] = {address, port, claim, confirmed} }.
function M.read_vouched(home, tag)
    local path = M.vouched_path(home, tag)
    local map = {}
    if not disk.is_file(path) then return map end
    local number = 0
    for line in disk.read_all(path):gmatch("[^\n]+") do
        number = number + 1
        local address, port, claim, confirmed = line:match("^(%S+)\t(%d+)\t(%x+)\t(%d+)$")
        if not address or not claims.is_claim_id(claim) then
            error("vouched: line " .. number .. " of " .. path .. " is not 'address TAB port TAB claim id TAB confirmed'", 0)
        end
        map[address .. " " .. port] = { address = address, port = tonumber(port), claim = claim, confirmed = tonumber(confirmed) }
    end
    return map
end
-- }}}

-- {{{ function M.vouch
-- 142's hello action: home, tag, pair, the claim it answered yes to, now.
function M.vouch(home, tag, pair, claim, now)
    local map = M.read_vouched(home, tag)
    map[pair.address .. " " .. pair.port] = { address = pair.address, port = pair.port, claim = claim, confirmed = now }
    local keys = {}
    for k in pairs(map) do keys[#keys + 1] = k end
    table.sort(keys)
    local lines = {}
    for _, k in ipairs(keys) do
        local e = map[k]
        lines[#lines + 1] = string.format("%s\t%d\t%s\t%d\n", e.address, e.port, e.claim, e.confirmed)
    end
    disk.write_atomic(M.vouched_path(home, tag), table.concat(lines))
end
-- }}}

-- {{{ local function own_pairs
-- The stage's own stated pairs that are shareable (none without 212's seam).
local function own_pairs(stage, tag)
    if not stage.seams.own_pairs then return {} end
    local ok, list = pcall(stage.seams.own_pairs, tag)
    if not ok then return {} end
    local out = {}
    for _, pair in ipairs(list) do
        if pair.kind ~= "home-network" and M.shareable(pair.address) then
            out[#out + 1] = { kind = M.shareable(pair.address), address = pair.address, port = pair.port }
        end
    end
    return out
end
-- }}}

-- {{{ function M.held
-- stage, tag → the shareable pairs held, sorted as "<address> <port>",
-- each {kind, address, port, own}.
function M.held(stage, tag)
    local seen, list = {}, {}
    local function add(pair, own)
        local key = pair.address .. " " .. pair.port
        if not seen[key] and M.shareable(pair.address) then
            seen[key] = true
            list[#list + 1] = { key = key, kind = M.shareable(pair.address), address = pair.address,
                                port = pair.port, own = own }
        end
    end
    for _, member in ipairs(recipients.members(stage.home, tag)) do add(member, false) end
    for _, pair in ipairs(own_pairs(stage, tag)) do add(pair, true) end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end
-- }}}

-- {{{ function M.digest
-- held list → 64 hex, count.
function M.digest(list)
    local lines = {}
    for i, e in ipairs(list) do lines[i] = e.key or (e.address .. " " .. e.port) end
    table.sort(lines)
    local hash = tokens.sha256(table.concat(lines, "\n"))
    return (hash:gsub(".", function(c) return string.format("%02x", c:byte()) end)), #lines
end
-- }}}

-- {{{ local function own_claim
-- A hello claim stating this mailbox's own shareable pairs, made once per
-- run of the stage (again when those pairs change).
local function own_claim(stage, tag, own, now)
    stage.own_list_claims = stage.own_list_claims or {}
    local key = tag .. " " .. M.digest(own)
    local id = stage.own_list_claims[key]
    if not id then
        id = claims.make_for(stage.home, tag, "hello", own, math.floor(now))
        stage.own_list_claims[key] = id
    end
    return id
end
-- }}}

-- {{{ function M.list_record
-- stage, tag, now → the `members` record this home sends, or nil when it
-- has nothing it can list.
function M.list_record(stage, tag, now)
    local held = M.held(stage, tag)
    local vouched = M.read_vouched(stage.home, tag)
    local own = {}
    for _, e in ipairs(held) do if e.own then own[#own + 1] = e end end
    local list, ids = {}, {}
    for _, e in ipairs(held) do
        local claim = nil
        if e.own then
            claim = own_claim(stage, tag, own, now)
        elseif vouched[e.key] then
            claim = vouched[e.key].claim
        end
        if claim then
            list[#list + 1] = { kind = e.kind, address = e.address, port = e.port }
            ids[#ids + 1] = claim
        end
    end
    if #list == 0 then return nil end
    return { kind = "members", id = message_log.new_message_id(), digest = (M.digest(held)), pairs = list,
             claims = table.concat(ids, " ") }
end
-- }}}

-- {{{ function M.receive_list
-- stage, tag, the decoded `members`, peer (never called), now → the checks
-- made.  Nothing is added here: each new pair is called back.
function M.receive_list(stage, tag, record, peer, now)
    local home = stage.home
    local ids = {}
    for id in record.claims:gmatch("%S+") do ids[#ids + 1] = id end
    if #ids ~= #record.pairs then error("members: " .. #record.pairs .. " pairs but " .. #ids .. " claim ids", 0) end
    local made = {}
    for i, pair in ipairs(record.pairs) do
        local claim = ids[i]
        if claims.is_claim_id(claim) and M.shareable(pair.address)
            and not claims.find(home, tag, claim)
            and not recipients.is_member(home, tag, pair.address, pair.port)
            and not ignore.refused_as_member(home, tag, pair.address, pair.port)
            and leaving.may_add_from_list(home, tag, pair) then
            local check, new = call_back.heard(stage, tag, { kind = "hello", id = claim, address = pair.address,
                port = pair.port }, peer, now)
            -- a check this list made sends no digest when it confirms; one
            -- the pair's own hello made already keeps its own standing
            if new then
                check.from_list = true
                made[#made + 1] = check
            end
        end
    end
    return made
end
-- }}}

-- {{{ local function ack
local function ack(id)
    return { kind = "ack", answers = send.write_answers({ { id = id, word = "filed" } }) }
end
-- }}}

-- {{{ local function check_digest
local function check_digest(record)
    if type(record.digest) ~= "string" or not record.digest:match("^%x+$") or #record.digest ~= 64 then
        error("members: a digest is 64 hex characters", 0)
    end
    if not record.id:match("^[%w%-_]+$") then error("members: not an id", 0) end
end
-- }}}

-- {{{ function M.answer
-- What 133's serve sends back for one of the three (its on_members seam):
-- stage, tag, the decoded record, peer, now → the reply record.
function M.answer(stage, tag, record, peer, now)
    check_digest(record)
    local mine = M.digest(M.held(stage, tag))
    if record.kind == "members" then
        M.receive_list(stage, tag, record, peer, now)
        return ack(record.id)
    end
    if record.digest == mine then return ack(record.id) end
    if record.kind == "members-digest" then
        local _, count = M.digest(M.held(stage, tag))
        return { kind = "members-ask", id = message_log.new_message_id(), digest = mine, count = count }
    end
    return M.list_record(stage, tag, now) or ack(record.id)
end
-- }}}

-- {{{ local function exchange
-- One frame out on conn, one frame back, opened and decoded → the record,
-- or nil and why.
local function exchange(conn, keys, record)
    local ok, why = frames.write_frame(conn, seal.seal(keys, records.encode(record)))
    if not ok then return nil, "writing: " .. tostring(why) end
    local after, failed = frames.read_frame(conn)
    if not after then return nil, "no answer: " .. tostring(failed) end
    local opened = seal.open(keys, after)
    if not opened then return nil, "an answer sealed with another key" end
    local decoded, reply = pcall(records.decode, opened)
    if not decoded then return nil, "an answer that does not decode" end
    return reply
end
-- }}}

-- {{{ local function acked
local function acked(reply, id)
    if reply.kind ~= "ack" then return false end
    for _, answer in ipairs(send.read_answers(reply.answers) or {}) do
        if answer.id == id then return true end
    end
    return false
end
-- }}}

-- {{{ function M.attempt
-- One try at a members job (134's stage runs it like a hello): job {kind
-- = "members-digest" | "members-ask", tag, pair, stage}, seams, now →
-- true when the exchange finished; or false and why.
function M.attempt(home, job, seams, now)
    local stage = job.stage
    local keys = room_key.key_pair(rooms.read_entry(home, job.tag).token)
    local digest, count = M.digest(M.held(stage, job.tag))
    local first = { kind = job.kind, id = message_log.new_message_id(), digest = digest, count = count }
    local conn, problem = seams.connect(job.pair)
    if not conn then return false, "no connection: " .. tostring(problem) end
    local function done(ok, why) if conn.close then conn:close() end; return ok, why end
    local reply, why = exchange(conn, keys, first)
    if not reply then return done(false, why) end
    if acked(reply, first.id) then return done(true) end
    local ok = pcall(check_digest, reply)
    if job.kind == "members-digest" and reply.kind == "members-ask" and ok then
        local list = M.list_record(stage, job.tag, now)
        if not list then return done(true) end
        local last, failed = exchange(conn, keys, list)
        if not last then return done(false, failed) end
        if acked(last, list.id) then return done(true) end
        return done(false, "the list was not acknowledged")
    elseif job.kind == "members-ask" and reply.kind == "members" and ok then
        M.receive_list(stage, job.tag, reply, { host = job.pair.address, port = job.pair.port }, now)
        return done(true)
    end
    return done(false, "an answer that counts for nothing: " .. tostring(reply.kind))
end
-- }}}

return M
