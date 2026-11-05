-- 145-hello.lua — the hello: joining a room, and saying where this
-- mailbox can be called back (issue 205).
--
-- A hello is one record (126's `hello`): a claim id (141) and every pair
-- the mailbox states, each with its kind.  It is the one message that
-- joins a room, re-announces at start-up and tells the room about a move;
-- the receiving side handles all three alike: each stated pair it does
-- not already hold (or has not heard from within the retry ceiling) is
-- called back (204, 142's `heard`) and added only when the pair itself
-- answers yes.  Nothing else is ever answered to a hello but the
-- transport's `ack` (structure R6): a hello is never answered with a
-- hello.
--
-- Sending.  The sender stage (134) keeps one hello job per (room, pair),
-- with its own retry timer, tried in `pass` before the deliveries.  The
-- job makes its claim on its first try and resends the same record on
-- every retry, so a lost ack gets `duplicate` (R1).  An `ack` naming the
-- claim id ends the job.  When a hello is sent (the issue's three
-- moments, all 134's):
--   - before the first message to a pair never heard from (`write`), once
--     per run of the stage;
--   - at start-up, to every pair on every send list (`start`);
--   - when 212 reports a confirmed move (`moved`): a fresh hello, a new
--     claim, to every pair.
--
-- Where this mailbox can be reached is 212's (not built).  Decision of
-- 2026-11-05 (the owner may overturn it): the stage takes the pairs from
-- a seam, `seams.own_pairs(tag)` → list of {kind, address, port}, which
-- 212 will give; there is no default and no guessed port ("no way. no
-- default port numbers").  A stage made without that seam (202's and
-- 204's tests, or a home before 212 is wired) sends no hellos at all and
-- `join` refuses.  `home-network` pairs go only to a housemate (addresses
-- R3): `seams.is_housemate(pair)` (213's; without it, nobody is one).
--
-- Receiving (133 hands a decoded hello to `receive` through its
-- `on_claim` seam):
--   - a hello whose claim id is in this room's own `claims` file is this
--     home's own hello reflected back: nothing is added (sealing R9);
--   - a stated pair on this home's ignore list for the room is not called
--     (add_member would refuse it anyway);
--   - a pair already a member and heard from within the retry ceiling is
--     not called again;
--   - every other pair is handed to 142's `heard`, which calls the stated
--     pair (never the connection's source) and, on yes, adds it beside the
--     pairs held (103's heard_from: the ignore refusal and the room tree's
--     flag still apply), never replacing any.
--
-- Joining: `join` makes the room from a token and the one member's pair a
-- person gave (that pair is trusted as given: the person typed it), then
-- sends that pair a hello.  The member's own members list is 207's (not
-- built).

local seal = require("124-seal")
local frames = require("125-frames")
local records = require("126-inner-records")
local room_key = require("123-room-key")
local rooms = require("002-room-folders")
local recipients = require("041-recipients")
local ignore = require("042-ignore-list")
local send = require("132-send")
local claims = require("141-claims")
local call_back = require("142-call-back")

local M = {}

-- {{{ function M.stated_pairs
-- seams (the stage's), tag, the pair the hello goes to → the pairs to
-- state: every pair 212 gives, less `home-network` ones unless the
-- receiver is a housemate.  An empty result is an error: a hello that
-- says nowhere to call back says nothing.
function M.stated_pairs(seams, tag, to_pair)
    if not seams.own_pairs then
        error("hello: where this mailbox can be reached is 212's (seams.own_pairs); nothing is guessed", 2)
    end
    local housemate = seams.is_housemate and seams.is_housemate(to_pair) or false
    local list = {}
    for _, pair in ipairs(seams.own_pairs(tag)) do
        if pair.kind ~= "home-network" or housemate then
            list[#list + 1] = { kind = pair.kind, address = pair.address, port = pair.port }
        end
    end
    if #list == 0 then error("hello: this mailbox states no pair to call back for room " .. tag, 2) end
    return list
end
-- }}}

-- {{{ function M.attempt
-- home, job ({tag, pair, claim, pairs}), seams, now → true when the
-- receiver's ack named the claim; or false and why.  The claim is made on
-- the first try and kept on the job, so a retry is the same record.
function M.attempt(home, job, seams, now)
    if not job.claim then
        local stated = M.stated_pairs(seams, job.tag, job.pair)
        job.claim = claims.make_for(home, job.tag, "hello", stated, math.floor(now))
        job.pairs = stated
    end
    local keys = room_key.key_pair(rooms.read_entry(home, job.tag).token)
    local conn, problem = seams.connect(job.pair)
    if not conn then return false, "no connection: " .. tostring(problem) end
    local line = records.encode({ kind = "hello", claim = job.claim, pairs = job.pairs })
    local ok, why = frames.write_frame(conn, seal.seal(keys, line))
    if not ok then if conn.close then conn:close() end; return false, "writing: " .. tostring(why) end
    local after, failed = frames.read_frame(conn)
    if conn.close then conn:close() end
    if not after then return false, "no answer: " .. tostring(failed) end
    local acked = send.accept_answer(keys, after, { [job.claim] = true })
    if #acked == 0 then return false, "an answer that does not name the hello" end
    return true
end
-- }}}

-- {{{ local function recently_heard
-- Whether (address, port) is a member heard from within `ceiling` seconds.
local function recently_heard(home, tag, pair, ceiling, now)
    for _, member in ipairs(recipients.members(home, tag)) do
        if member.address == pair.address and member.port == pair.port then
            return member.heard > 0 and now - member.heard <= ceiling
        end
    end
    return false
end
-- }}}

-- {{{ function M.receive
-- stage (134), tag, the decoded hello, peer (the connection's {host,
-- port}: never called), now (whole seconds) → the ack's word ("filed", or
-- "duplicate" for a claim this stage has heard before) and the checks it
-- made.
function M.receive(stage, tag, record, peer, now)
    local home = stage.home
    stage.hellos_heard = stage.hellos_heard or {}
    local word = stage.hellos_heard[tag .. " " .. record.claim] and "duplicate" or "filed"
    stage.hellos_heard[tag .. " " .. record.claim] = true
    local made = {}
    -- this home's own claim, sent back: nothing of ours becomes a member
    if claims.find(home, tag, record.claim) then return word, made end
    for _, pair in ipairs(record.pairs) do
        if not ignore.refused_as_member(home, tag, pair.address, pair.port)
            and not recently_heard(home, tag, pair, stage.ceiling, now) then
            made[#made + 1] = call_back.heard(stage, tag, { kind = "hello", id = record.claim,
                address = pair.address, port = pair.port }, peer, now)
        end
    end
    return word, made
end
-- }}}

-- {{{ function M.join
-- home, stage (134; its seams give own_pairs), spec {label, token, kind,
-- parent, mailbox_port, pair = {address, port}}, now → the new room's tag.
-- Every field is required (make_room's rule).  The room is made, the pair
-- added as given, and a hello to it made due now.
function M.join(home, stage, spec, now)
    for _, field in ipairs({ "label", "token", "kind", "parent", "mailbox_port", "pair" }) do
        if spec[field] == nil then error("hello.join: spec." .. field .. " is missing", 2) end
    end
    if not stage.seams.own_pairs then
        error("hello.join: where this mailbox can be reached is 212's (seams.own_pairs); nothing is guessed", 2)
    end
    local tag = rooms.make_room(home, { label = spec.label, token = spec.token, kind = spec.kind,
        parent = spec.parent, filed_under = "", members = {}, mailbox_port = spec.mailbox_port })
    recipients.add_member(home, tag, spec.pair.address, spec.pair.port)
    stage:hello(tag, spec.pair, now)
    return tag
end
-- }}}

return M
