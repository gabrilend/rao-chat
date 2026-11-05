-- 134-delivery.lua — writing your own records so they go out at once, and
-- the sender stage's bookkeeping: one job and one retry timer per pair
-- (issue 202, steps 2 and 4).
--
-- Writing.  `write` files your own message, correction or deletion
-- (105, `from` = "me") with a new id, after making sure every pair on the
-- send list has a line in `delivered` (130's join), and gives back the
-- pairs to wake.  The id is fixed here, once (R1).  Own written times
-- never go back in file order: a record written while the clock reads
-- earlier than your last record is given your last record's time (130's
-- mark relies on it; decision of 2026-11-05, the owner may overturn it).
--
-- The stage.  One timer per (room, pair) (R7).  `pass` runs every due
-- job, one attempt each (132), and moves its timer by the attempt's
-- outcome: delivered everything — back to the floor; nothing missing —
-- held, not a failure; anything else, an error in the attempt included —
-- one failure (R8, R9).  The timer never stops (R11).
--
-- What runs where is 211's: it calls `write` from the viewer's stage,
-- `pass` from a sender stage that never blocks the receiving stage (R6),
-- and may run the jobs of one pass in parallel workers, as long as one
-- room's `delivered` file has one writer at a time.  Here the jobs of a
-- pass run one after another.  The issue's `due/` entries are this
-- stage's `wake` calls: 211 decides whether the wake crosses a process
-- boundary (a file) or stays in memory.
--
-- Decisions of 2026-11-05 (the owner may overturn each):
--   open question 1  hearing a frame that opens in a room, from an
--                    address, makes every pair of that room at that
--                    address due now (`heard_at`); the interval is kept,
--                    so only a delivered attempt resets it
--   open question 2  timers are not kept across a restart: `start` makes
--                    every pair with something missing due at once, as
--                    rmail does

local rooms = require("002-room-folders")
local recipients = require("041-recipients")
local message_log = require("081-message-log")
local delivered = require("130-delivered")
local timer = require("131-retry-timer")
local send = require("132-send")

local M = {}

-- {{{ local function job_key
local function job_key(tag, pair)
    return tag .. " " .. pair.address .. " " .. tostring(pair.port)
end
-- }}}

-- {{{ function M.write
-- home, tag, record ({kind = "message" | "correction" | "deletion",
-- text, target (edits)}), now (whole seconds) → the log's word, the new
-- id, and the send list (the pairs to wake).
function M.write(home, tag, record, now)
    local send_list = recipients.send_list(home, tag)
    delivered.join(home, tag, send_list)
    local latest = 0
    for _, own in ipairs(delivered.own_records(home, tag)) do
        if own.written > latest then latest = own.written end
    end
    local written = math.max(now, latest)
    local id = message_log.new_message_id()
    local filed = { id = id, from = "me", written = written, arrived = written,
                    target = record.target, text = record.text or "" }
    local word
    if record.kind == "message" or record.kind == nil then
        word = message_log.append(home, tag, filed)
    elseif record.kind == "correction" then
        word = message_log.correct(home, tag, filed)
    elseif record.kind == "deletion" then
        word = message_log.delete(home, tag, filed)
    else
        error("delivery: write files messages, corrections and deletions, not " .. tostring(record.kind), 2)
    end
    return word, id, send_list
end
-- }}}

local Stage = {}
Stage.__index = Stage

-- {{{ function M.new_stage
-- home, seams ({connect}), floor, ceiling (omitted: read from the home's
-- config by 131) → a stage.
function M.new_stage(home, seams, floor, ceiling)
    if not floor then floor, ceiling = timer.settings(home) end
    return setmetatable({ home = home, seams = seams, floor = floor, ceiling = ceiling,
        jobs = {}, order = {} }, Stage)
end
-- }}}

-- {{{ function Stage:job
-- tag, pair → the job ({tag, pair, timer, attempts}), made on first use.
function Stage:job(tag, pair)
    local k = job_key(tag, pair)
    local job = self.jobs[k]
    if not job then
        job = { tag = tag, pair = { address = pair.address, port = pair.port },
                timer = timer.new(self.floor, self.ceiling), attempts = 0 }
        self.jobs[k] = job
        self.order[#self.order + 1] = k
    end
    return job
end
-- }}}

-- {{{ function Stage:wake
-- Something new for these pairs of a room (write's send list).
function Stage:wake(tag, pairs, now)
    for _, pair in ipairs(pairs) do self:job(tag, pair).timer:wake(now) end
end
-- }}}

-- {{{ function Stage:write
-- write, then wake the send list: what the viewer's stage calls.
function Stage:write(tag, record, now)
    local word, id, send_list = M.write(self.home, tag, record, now)
    self:wake(tag, send_list, now)
    return word, id
end
-- }}}

-- {{{ function Stage:start
-- At start-up: every pair on every send list that is missing something is
-- due now (open question 2).
function Stage:start(now)
    for _, tag in ipairs(rooms.list_rooms(self.home)) do
        for _, pair in ipairs(recipients.send_list(self.home, tag)) do
            if #delivered.missing_for(self.home, tag, pair) > 0 then
                self:job(tag, pair).timer:due_now(now)
            end
        end
    end
end
-- }}}

-- {{{ function Stage:heard_at
-- A frame for room `tag` opened from `host` (open question 1): that
-- room's pairs at that address are due now.
function Stage:heard_at(tag, host, now)
    for _, pair in ipairs(recipients.send_list(self.home, tag)) do
        if pair.address == host then self:job(tag, pair).timer:due_now(now) end
    end
end
-- }}}

-- {{{ function M.after_attempt
-- How an attempt's result moves its job's timer.
function M.after_attempt(job, result, now)
    if not result.attempted then
        job.timer:held()
    elseif result.complete then
        job.timer:succeeded()
    else
        job.timer:failed(now)
    end
end
-- }}}

-- {{{ function Stage:run_job
-- One attempt for one job, whatever happens in it: an error in the attempt
-- is one failure, and the timer moves (R9).
function Stage:run_job(job, now)
    local ok, result = pcall(send.attempt, self.home, job.tag, job.pair, self.seams)
    if not ok then
        result = { attempted = true, sent = 0, acknowledged = {}, complete = false, reason = tostring(result) }
    end
    if result.attempted then job.attempts = job.attempts + 1 end
    -- the attempt took time: the next wait counts from when it ended
    M.after_attempt(job, result, self.seams.now and self.seams.now() or now)
    job.last = result
    return result
end
-- }}}

-- {{{ function Stage:pass
-- now (whole seconds; read again after each job through seams.now, if
-- given) → the jobs run, in the order they were made.
function Stage:pass(now)
    local ran = {}
    for _, k in ipairs(self.order) do
        local job = self.jobs[k]
        local at = self.seams.now and self.seams.now() or now
        if job.timer:is_due(at) then
            self:run_job(job, at)
            ran[#ran + 1] = job
        end
    end
    return ran
end
-- }}}

-- {{{ function Stage:next_due
-- The earliest due time of any job, or nil.
function Stage:next_due()
    local earliest = nil
    for _, job in pairs(self.jobs) do
        local due = job.timer.due
        if due and (not earliest or due < earliest) then earliest = due end
    end
    return earliest
end
-- }}}

return M
