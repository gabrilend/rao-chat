-- 132-send.lua — one attempt to bring one pair up to date (issue 202,
-- step 3).
--
-- An attempt sends everything the pair is missing (130), in log order, on
-- one connection, and counts as delivered only what the pair's answers
-- acknowledge.  Each record goes out exactly as the log holds it, with
-- the id it was filed under, so a resend after a lost answer is the same
-- record and the receiver answers `duplicate` (R1).
--
-- Answers (R5).  The receiver answers each frame with one `ack` frame
-- (126), sealed with the room's key.  An answer counts only if it opens
-- with this room's key (and so its tying value, 201a), is an `ack`, and
-- names ids sent on this connection, each with `filed` or `duplicate`.
-- Anything else on the connection acknowledges nothing: an answer sealed
-- with another room's key, an `ack` naming other ids, or an old answer
-- replayed onto a new connection that carries new ids.
--
-- Window.  Frames go out WINDOW at a time, then that many answers are
-- read, so a long backlog never has more than WINDOW answers waiting in
-- the sender's receive buffer while it is still writing (a sender that
-- wrote everything first could block against a receiver blocked writing
-- answers).  Decision of 2026-11-05; the owner may overturn it.
--
-- The connection comes from a seam: `seams.connect(pair)` gives anything
-- with LuaSocket's receive, send and close (125), or nil and why.  211
-- gives a real socket with its timeouts; the tests give an in-memory
-- relay.  This file never listens and never runs on its own: the sender
-- stage (134, run by 211) calls `attempt`.

local seal = require("124-seal")
local frames = require("125-frames")
local records = require("126-inner-records")
local room_key = require("123-room-key")
local rooms = require("002-room-folders")
local delivered = require("130-delivered")

local M = {}

M.WINDOW = 32

M.WORDS = { filed = true, duplicate = true }

-- {{{ function M.read_answers
-- The `answers` field → list of {id, word}, or nil and why.  An odd count,
-- an unknown word or an id with characters outside the id alphabet makes
-- the whole answer count for nothing.
function M.read_answers(text)
    local parts = {}
    for part in text:gmatch("[^ ]+") do parts[#parts + 1] = part end
    if #parts % 2 ~= 0 then return nil, "an id without its word" end
    local list = {}
    for i = 1, #parts, 2 do
        local id, word = parts[i], parts[i + 1]
        if not id:match("^[%w%-_]+$") then return nil, "not an id: " .. id:sub(1, 40) end
        if not M.WORDS[word] then return nil, "not an answer word: " .. word:sub(1, 20) end
        list[#list + 1] = { id = id, word = word }
    end
    return list
end
-- }}}

-- {{{ function M.write_answers
-- list of {id, word} → the `answers` field.
function M.write_answers(list)
    local parts = {}
    for _, answer in ipairs(list) do
        if not M.WORDS[answer.word] then error("send: an answer word must be filed or duplicate", 2) end
        parts[#parts + 1] = answer.id .. " " .. answer.word
    end
    return table.concat(parts, " ")
end
-- }}}

-- {{{ function M.accept_answer
-- keys (the room's {key, tie}), after_length (one answer frame), sent
-- (set of ids sent on this connection) → the ids it acknowledges (maybe
-- none).
function M.accept_answer(keys, after_length, sent)
    local opened = seal.open(keys, after_length)
    if opened == nil then return {} end
    local ok, record = pcall(records.decode, opened)
    if not ok or record.kind ~= "ack" then return {} end
    local list = M.read_answers(record.answers)
    if not list then return {} end
    local ids = {}
    for _, answer in ipairs(list) do
        if sent[answer.id] then ids[#ids + 1] = answer.id end
    end
    return ids
end
-- }}}

-- {{{ local function wire_record
-- A log record → the record a frame carries (126: the log's fields less
-- `from` and `arrived`).
local function wire_record(record)
    return { kind = record.kind, id = record.id, written = record.written,
             target = record.target, text = record.text }
end
-- }}}

-- {{{ function M.attempt
-- home, tag, pair ({address, port}), seams ({connect}) → a result:
--   attempted     false when nothing was missing (held back: not an
--                 attempt, R7); true otherwise
--   sent          frames written
--   acknowledged  ids this attempt acknowledged
--   complete      everything that was missing is now acknowledged
--   reason        why not, when not complete
function M.attempt(home, tag, pair, seams)
    local missing = delivered.missing_for(home, tag, pair)
    if #missing == 0 then return { attempted = false, sent = 0, acknowledged = {}, complete = true } end
    local keys = room_key.key_pair(rooms.read_entry(home, tag).token)
    local conn, problem = seams.connect(pair)
    if not conn then
        return { attempted = true, sent = 0, acknowledged = {}, complete = false,
                 reason = "no connection: " .. tostring(problem) }
    end
    local sent, sent_count, acked, acked_list, reason = {}, 0, {}, {}, nil
    local first = 1
    while first <= #missing and not reason do
        local last = math.min(first + M.WINDOW - 1, #missing)
        local written_here = 0
        for index = first, last do
            local record = missing[index]
            local ok, why = frames.write_frame(conn, seal.seal(keys, records.encode(wire_record(record))))
            if not ok then reason = "writing: " .. tostring(why); break end
            sent[record.id] = true
            sent_count = sent_count + 1
            written_here = written_here + 1
        end
        for _ = 1, written_here do
            local after, why = frames.read_frame(conn)
            if not after then reason = reason or ("reading an answer: " .. tostring(why)); break end
            for _, id in ipairs(M.accept_answer(keys, after, sent)) do
                if not acked[id] then
                    acked[id] = true
                    acked_list[#acked_list + 1] = id
                end
            end
        end
        first = last + 1
    end
    if conn.close then conn:close() end
    delivered.acknowledge(home, tag, pair, acked_list)
    local complete = true
    for _, record in ipairs(missing) do
        if not acked[record.id] then complete = false; break end
    end
    if not complete and not reason then reason = "not every record was acknowledged" end
    return { attempted = true, sent = sent_count, acknowledged = acked_list, complete = complete, reason = reason }
end
-- }}}

return M
