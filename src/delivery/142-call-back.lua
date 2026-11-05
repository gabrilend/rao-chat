-- 142-call-back.lua — asking a stated pair "did you make claim C?" before
-- trusting the claim (issue 204, step 3).
--
-- Before a home trusts "I am at this address, listening on port N" (a
-- hello, 205; a pair from a members list, 207) or "I have left" (208), it
-- calls that address and port and asks, sealed with the room's key, about
-- the claim's id.  Only a computer really listening there, holding the
-- room's key, and having made that claim answers `yes` (141 answers from
-- its `claims` file).  It proves where a home can be reached, never who
-- wrote anything.
--
-- The rules (addresses-and-ports R1, R2, R6, R8; sealing R9):
--   - the ask goes to the **stated** pair, never to the address or port
--     the claim's connection came from (`heard` takes the source only to
--     refuse to use it);
--   - an answer counts only if it opens with the room's key on the
--     connection made to that pair, is a `did-you-answer`, and names the
--     claim asked about; then `yes` confirms and `no` refuses;
--   - **no answer is "not confirmed"**, never "confirmed": a check with no
--     answer within `callback.answer-time` seconds stays unconfirmed and is
--     tried again by 202's timers (131), never dropped (R6, R11);
--   - a `yes` confirms that one claim and nothing else.
--
-- What a confirmed claim does (decision of 2026-11-05; the owner may
-- overturn it): a hello adds the pair as a member (103's add_member; the
-- room tree's check and the ignore list still apply there; since 205,
-- through heard_from, which also records the pair as heard), a leave
-- removes it (103's confirm_leave, "the only removal").  A `no` ends the
-- check: the home at that pair says it made no such claim, and asking
-- again will not change that.  205 and 208 make and send the claims; 207
-- passes on pairs; each hands what it hears to `heard`.
--
-- Checks run in 202's sender stage (134's `check` and `pass`), one timer
-- each.  Like 202's timers, pending checks are not kept across a restart:
-- the claim is heard again when its maker resends it.

local seal = require("124-seal")
local frames = require("125-frames")
local records = require("126-inner-records")
local room_key = require("123-room-key")
local rooms = require("002-room-folders")
local recipients = require("041-recipients")
local claims = require("141-claims")

local M = {}

M.ANSWERS = { yes = true, no = true }

-- {{{ function M.settings
-- home → the answer time (whole seconds ≥ 1), read strictly.
function M.settings(home)
    local text = rooms.config_value(home, "callback.answer-time")
    if not text:match("^%d+$") or tonumber(text) < 1 then
        error("callback.answer-time must be a whole number of seconds ≥ 1, got '" .. text .. "'", 0)
    end
    return tonumber(text)
end
-- }}}

-- {{{ function M.read_answer
-- keys (the room's), one frame from the stated pair, the claim asked
-- about → "yes" or "no", or nil (it counts for nothing).
function M.read_answer(keys, after_length, claim_id)
    local opened = seal.open(keys, after_length)
    if opened == nil then return nil end
    local ok, record = pcall(records.decode, opened)
    if not ok or record.kind ~= "did-you-answer" then return nil end
    if record.claim ~= claim_id or not M.ANSWERS[record.answer] then return nil end
    return record.answer
end
-- }}}

-- {{{ local function with_deadline
-- A connection whose reads give up at `deadline` (seams.now's clock).
-- The connection's own timeout is cut to what is left, where it has
-- LuaSocket's settimeout.
local function with_deadline(conn, deadline, now)
    return {
        receive = function(_, n)
            local left = deadline - now()
            if left <= 0 then return nil, "timeout", "" end
            if conn.settimeout then conn:settimeout(left) end
            return conn:receive(n)
        end,
        send = function(_, data, i, j) return conn:send(data, i, j) end,
        close = function() if conn.close then conn:close() end end,
    }
end
-- }}}

-- {{{ function M.ask
-- home, tag, pair (the stated one), claim id, answer time, seams
-- ({connect, now}) → "yes" / "no", or nil and why.
function M.ask(home, tag, pair, claim_id, answer_time, seams)
    local keys = room_key.key_pair(rooms.read_entry(home, tag).token)
    local raw, problem = seams.connect(pair)
    if not raw then return nil, "no connection: " .. tostring(problem) end
    local conn = with_deadline(raw, seams.now() + answer_time, seams.now)
    local question = records.encode({ kind = "did-you", claim = claim_id, address = pair.address, port = pair.port })
    local ok, why = frames.write_frame(conn, seal.seal(keys, question))
    if not ok then conn:close(); return nil, "asking: " .. tostring(why) end
    -- the first frame back is the answer; anything else on it is ignored
    local after, failed = frames.read_frame(conn)
    conn:close()
    if not after then return nil, "no answer: " .. tostring(failed) end
    local answer = M.read_answer(keys, after, claim_id)
    if not answer then return nil, "an answer that counts for nothing" end
    return answer
end
-- }}}

-- {{{ function M.answer_frame
-- What 133's serve sends back for a `did-you` (141 answers): home, tag,
-- the decoded did-you → the did-you-answer record's line.
function M.answer_frame(home, tag, record)
    local answer = claims.answer(home, tag, record.claim, { address = record.address, port = record.port })
    return records.encode({ kind = "did-you-answer", claim = record.claim, answer = answer })
end
-- }}}

-- {{{ M.ACTIONS
-- What a confirmed claim does: home, tag, pair, now (whole seconds).
-- Decision of 2026-11-05 (issue 205; the owner may overturn it): a
-- confirmed hello is hearing from that pair, so it is added and its
-- last-heard time moved to the confirmation (103's heard_from: add_member
-- with its refusals and flag, then the time).  205's receiver does not call
-- back a pair heard within the retry ceiling, so this is what keeps idle
-- homes from calling each other back on every start-up hello.
--
-- Since 208 (decision of 2026-11-05; the owner may overturn it): a leave
-- goes through 147's `confirm` (103's confirm_leave, the `left` line, the
-- `delivered` line dropped), and a confirmed hello also clears the pair's
-- `left` line: the leaver's own hello undoes its leave.  147 is required
-- when the action runs, because 147 requires this file.
--
-- Since 207 (decision of 2026-11-05; the owner may overturn it): a
-- confirmed hello that leaves the pair a member also keeps the claim it
-- answered yes to in the room's `vouched` file (152's `vouch`), so this
-- home's members list can carry it and a receiver can call the pair back
-- about it.  152 is required when the action runs, for the same reason.
M.ACTIONS = {
    hello = function(home, tag, pair, now, check)
        local word = recipients.heard_from(home, tag, pair.address, pair.port, now)
        if recipients.is_member(home, tag, pair.address, pair.port) then
            require("147-leaving").clear(home, tag, pair)
            if check and check.claim then require("152-members").vouch(home, tag, pair, check.claim, now) end
        end
        return word
    end,
    leave = function(home, tag, pair, now, check)
        return require("147-leaving").confirm(home, tag, pair, now, check)
    end,
    -- 213 (decision of 2026-11-05; the owner may overturn it): a confirmed
    -- discovery keeps the pair as a housemate (154's `keep`), never as a
    -- member.  The check carries the housemates table that made it.
    discover = function(home, tag, pair, now, check)
        if not (check and check.housemates) then error("a discover check without its housemates", 0) end
        return check.housemates:keep(tag, check, now)
    end,
}
-- }}}

-- {{{ function M.target
-- A claim heard ({kind, id, address, port}) and the connection it came on
-- ({host, port}) → the pair to call: the stated one, always.
function M.target(claim, source)
    return { address = claim.address, port = claim.port }
end
-- }}}

-- {{{ function M.heard
-- stage (134), tag, claim ({kind, id, address, port}), source (the
-- connection it came on), now → the check (made, or already there).
function M.heard(stage, tag, claim, source, now)
    if not claims.KINDS[claim.kind] then error("call-back: a claim is a hello or a leave", 2) end
    if not claims.is_claim_id(claim.id) then error("call-back: not a claim id: " .. tostring(claim.id), 2) end
    return stage:check(tag, claim.kind, claim.id, M.target(claim, source), now)
end
-- }}}

-- {{{ function M.run
-- One try at one check (the stage's): ask, then act on the answer.
-- now: when it is tried (whole seconds).  Gives "confirmed", "refused" or
-- "unconfirmed", and why.
function M.run(home, check, answer_time, seams, now)
    local answer, why = M.ask(home, check.tag, check.pair, check.claim, answer_time, seams)
    if answer == "yes" then
        local at = math.floor(seams.now and seams.now() or now)
        local ok, result = pcall(M.ACTIONS[check.kind], home, check.tag, check.pair, at, check)
        return "confirmed", ok and result or ("confirmed, but " .. tostring(result))
    elseif answer == "no" then
        return "refused", "the home at that pair made no such claim"
    end
    return "unconfirmed", why
end
-- }}}

return M
