-- 156-cross-check.lua — periodic cross-checking between members: each
-- home tells each member what it holds, fills its own gaps, and raises a
-- message id that two members hold with different words (issue 209).
--
-- The round (decisions of 2026-11-05; the owner may overturn each): every
-- `crosscheck.interval` seconds on the sender stage's clock (134's
-- `pass`; a quiet home still sends), each room this home has not left
-- gets one job per pair on its send list that is not ignored.  A job
-- opens one connection and runs, on it:
--   1. 207's members exchange (152's `exchange_on`, a `members-digest`):
--      this is the automatic asking 207 left to here (207's decision 1);
--   2. a `summary` (126): this home's own pairs and, for every record it
--      holds written within `crosscheck.window` seconds, its id and
--      fingerprint.
--
-- The fingerprint: the first 16 bytes of SHA-256, as 32 hex, over the
-- record's agreed part — its kind, id, written time, target and text,
-- encoded as one line by 126's own row for that kind (the part every home
-- writes identically; never `from` or `arrived`, which differ per home).
-- 215's shared text copies may take the same part.
--
-- Receiving a summary (`answer`, through 133's `on_summary` seam):
--   - gaps: each of this home's own records written since the summary's
--     window start, meant for the summariser (130's `meant_for`: written
--     after its line was made), and missing from the summary, is made
--     missing again in `delivered` (130's `forget`) for each of the
--     summariser's stated pairs that is on this room's send list and not
--     ignored; the sender stage is woken, and 202's one sending path sends
--     it again with its original id (R1).  Only an acknowledgement marks
--     it delivered again (R4).  Someone else's message is never sent;
--   - differences: an id held here with another fingerprint is answered
--     with a `versions` record holding this home's versions; otherwise an
--     ack names the summary.
-- The summariser, given versions, raises each difference (`raise`) and
-- sends its own versions back; the receiver raises them too and acks.  So
-- both homes hold both versions.
--
-- Raising (open question 2): a line in the room's `conflicts` file (one
-- per id and pair of fingerprints, kept), the stage's `conflicts` list,
-- and the stage seam `on_conflict(tag, id, mine, theirs)` when given: the
-- viewer's notice in the room and its error strip are the viewer's (phase
-- 3).  An edit is its own record with its own id, so it never raises.

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
local delivered = require("130-delivered")
local send = require("132-send")
local members = require("152-members")

local M = {}

M.KINDS = { summary = true, versions = true }

-- The most entries one summary lists (decision of 2026-11-05): the
-- newest, so a frame stays far under 124's 1 MiB cap (an entry is 66
-- bytes).  An older record past this many is not compared this round.
M.MOST_ENTRIES = 10000

-- {{{ function M.settings
-- home → interval, window (whole seconds ≥ 1), read strictly.
function M.settings(home)
    local function whole(key)
        local text = rooms.config_value(home, key)
        if not text:match("^%d+$") or tonumber(text) < 1 then
            error(key .. " must be a whole number of seconds ≥ 1, got '" .. text .. "'", 0)
        end
        return tonumber(text)
    end
    return whole("crosscheck.interval"), whole("crosscheck.window")
end
-- }}}

-- {{{ function M.agreed
-- A log record → its agreed part, one encoded line.
function M.agreed(record)
    return records.encode({ kind = record.kind, id = record.id, written = record.written,
                            target = record.target or "", text = record.text or "" })
end
-- }}}

-- {{{ function M.fingerprint
function M.fingerprint(record)
    local bytes = tokens.sha256(M.agreed(record)):sub(1, 16)
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
-- }}}

-- {{{ local function held_since
-- home, tag, since → the records written at or after `since`, newest
-- MOST_ENTRIES of them, by id.
local function held_since(home, tag, since)
    local list = {}
    for _, record in ipairs(message_log.read(home, tag)) do
        if record.written >= since then list[#list + 1] = record end
    end
    table.sort(list, function(a, b)
        if a.written ~= b.written then return a.written > b.written end
        return a.id < b.id
    end)
    local by_id = {}
    for i = 1, math.min(#list, M.MOST_ENTRIES) do by_id[list[i].id] = list[i] end
    return by_id
end
-- }}}

-- {{{ function M.summary_record
-- stage, tag, now → the summary this home sends.
function M.summary_record(stage, tag, now)
    local _, window = M.settings(stage.home)
    local since = math.max(math.floor(now) - window, 0)
    local held = held_since(stage.home, tag, since)
    local ids = {}
    for id in pairs(held) do ids[#ids + 1] = id end
    table.sort(ids)
    local entries = {}
    for i, id in ipairs(ids) do entries[i] = id .. ":" .. M.fingerprint(held[id]) end
    local stated = {}
    for _, pair in ipairs(stage.seams.own_pairs(tag)) do
        if pair.kind ~= "home-network" then stated[#stated + 1] = pair end
    end
    return { kind = "summary", id = message_log.new_message_id(), since = since, pairs = stated,
             entries = table.concat(entries, " ") }
end
-- }}}

-- {{{ function M.read_entries
-- The entries text → { [id] = fingerprint }; an error when malformed.
function M.read_entries(text)
    local map = {}
    for entry in text:gmatch("%S+") do
        local id, fp = entry:match("^([%w%-_]+):(%x+)$")
        if not id or #fp ~= 32 then error("summary: '" .. entry:sub(1, 80) .. "' is not 'id:fingerprint'", 0) end
        map[id] = fp
    end
    return map
end
-- }}}

-- {{{ function M.conflicts_path
function M.conflicts_path(home, tag)
    return rooms.room_dir(home, tag) .. "/conflicts"
end
-- }}}

-- {{{ local function describe
local function describe(record)
    local text = record.text or ""
    if #text > 120 then text = text:sub(1, 120) .. "...(" .. #record.text .. " bytes)" end
    return string.format("{written %d, kind %s, target %q, text %q}", record.written, record.kind,
        record.target or "", text)
end
-- }}}

-- {{{ function M.raise
-- stage, tag, mine (this home's record), theirs (the other's version),
-- now → true when raised now, false when it was raised before.
function M.raise(stage, tag, mine, theirs, now)
    local a, b = M.fingerprint(mine), M.fingerprint(theirs)
    local key = mine.id .. "\t" .. a .. "\t" .. b
    local path = M.conflicts_path(stage.home, tag)
    local text = disk.is_file(path) and disk.read_all(path) or ""
    if text:find(key, 1, true) then return false end
    local line = string.format("%s\t%d\t%s\t%s\n", key, math.floor(now), describe(mine):gsub("[\t\n]", " "),
        (describe(theirs):gsub("[\t\n]", " ")))
    disk.write_atomic(path, text .. line)
    stage.conflicts = stage.conflicts or {}
    stage.conflicts[#stage.conflicts + 1] = { tag = tag, id = mine.id, mine = mine, theirs = theirs }
    if stage.seams.on_conflict then pcall(stage.seams.on_conflict, tag, mine.id, mine, theirs) end
    return true
end
-- }}}

-- {{{ local function versions_of
-- home, tag, ids → the versions record's `records` text.
local function versions_of(home, tag, ids)
    local held, lines = {}, {}
    for _, record in ipairs(message_log.read(home, tag)) do held[record.id] = record end
    for _, id in ipairs(ids) do
        if held[id] then lines[#lines + 1] = M.agreed(held[id]) end
    end
    return table.concat(lines, "\n")
end
-- }}}

-- {{{ local function raise_versions
-- stage, tag, the `records` text received, now → the ids raised.  A
-- version this home does not hold under that id, or holds identically,
-- raises nothing.
local function raise_versions(stage, tag, text, now)
    local held = {}
    for _, record in ipairs(message_log.read(stage.home, tag)) do held[record.id] = record end
    local raised = {}
    for line in text:gmatch("[^\n]+") do
        local ok, theirs = pcall(records.decode, line)
        if ok and theirs.id and held[theirs.id] and M.fingerprint(held[theirs.id]) ~= M.fingerprint(theirs) then
            M.raise(stage, tag, held[theirs.id], theirs, now)
            raised[#raised + 1] = theirs.id
        end
    end
    return raised
end
-- }}}

-- {{{ local function ack
local function ack(id)
    return { kind = "ack", answers = send.write_answers({ { id = id, word = "filed" } }) }
end
-- }}}

-- {{{ function M.fill_gaps
-- stage, tag, the decoded summary, now → the pairs woken, each {pair,
-- ids}.  Only this home's own records meant for that pair, written since
-- the summary's start, and never to a withheld (off the send list) or
-- ignored pair.
function M.fill_gaps(stage, tag, record, now)
    local home = stage.home
    local listed = M.read_entries(record.entries)
    local on_list = {}
    for _, pair in ipairs(recipients.send_list(home, tag)) do on_list[pair.address .. " " .. pair.port] = pair end
    local woken = {}
    for _, stated in ipairs(record.pairs) do
        local pair = on_list[stated.address .. " " .. stated.port]
        if pair and ignore.how_ignored(home, tag, pair.address, pair.port) == "none" then
            local meant = delivered.meant_for(home, tag, pair)
            local lacking = {}
            for _, own in ipairs(delivered.own_records(home, tag)) do
                if own.written >= record.since and meant[own.id] and not listed[own.id] then
                    lacking[#lacking + 1] = own.id
                end
            end
            local forgotten = delivered.forget(home, tag, pair, lacking)
            if #forgotten > 0 then
                stage:wake(tag, { pair }, now)
                woken[#woken + 1] = { pair = pair, ids = forgotten }
            end
        end
    end
    return woken
end
-- }}}

-- {{{ function M.answer
-- What 133's serve sends back for a summary or versions (its on_summary
-- seam): stage, tag, the decoded record, peer, now → the reply record.
function M.answer(stage, tag, record, peer, now)
    if record.kind == "versions" then
        raise_versions(stage, tag, record.records, now)
        return ack(record.id)
    end
    local listed = M.read_entries(record.entries)
    M.fill_gaps(stage, tag, record, now)
    local held = {}
    for _, own in ipairs(message_log.read(stage.home, tag)) do held[own.id] = own end
    local differ = {}
    for id, fp in pairs(listed) do
        if held[id] and M.fingerprint(held[id]) ~= fp then differ[#differ + 1] = id end
    end
    if #differ == 0 then return ack(record.id) end
    table.sort(differ)
    return { kind = "versions", id = message_log.new_message_id(), answers = record.id,
             records = versions_of(stage.home, tag, differ) }
end
-- }}}

-- {{{ local function exchange
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
-- One try at a cross-check job (134 runs it like a hello): job {kind =
-- "summary", tag, pair, stage}, seams, now → true when both exchanges
-- finished; or false and why.
function M.attempt(home, job, seams, now)
    local stage = job.stage
    local keys = room_key.key_pair(rooms.read_entry(home, job.tag).token)
    local conn, problem = seams.connect(job.pair)
    if not conn then return false, "no connection: " .. tostring(problem) end
    local function done(ok, why) if conn.close then conn:close() end; return ok, why end
    local ok, why = members.exchange_on(conn, keys, stage, job.tag, "members-digest", job.pair, now)
    if not ok then return done(false, "members: " .. tostring(why)) end
    local summary = M.summary_record(stage, job.tag, now)
    local reply, failed = exchange(conn, keys, summary)
    if not reply then return done(false, failed) end
    if acked(reply, summary.id) then return done(true) end
    if reply.kind ~= "versions" or reply.answers ~= summary.id then
        return done(false, "an answer that counts for nothing: " .. tostring(reply.kind))
    end
    local raised = raise_versions(stage, job.tag, reply.records, now)
    local mine = { kind = "versions", id = message_log.new_message_id(), answers = reply.id,
                   records = versions_of(home, job.tag, raised) }
    local last, lost = exchange(conn, keys, mine)
    if not last then return done(false, lost) end
    if acked(last, mine.id) then return done(true) end
    return done(false, "our versions were not acknowledged")
end
-- }}}

return M
