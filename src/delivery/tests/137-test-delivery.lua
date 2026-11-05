-- 137-test-delivery.lua — the referees of issue 202, each run against the
-- real code and against a deliberately broken version it must catch.
--
-- The homes are real rao-homes on disk; what runs between them is a
-- simulation in this one process: a fake clock, coroutines for each
-- home's stages (accepting, serving a connection, sending), and an
-- in-memory relay whose connections can be delayed, refused, or have
-- their answers dropped or replaced.  No socket is opened.  211 replaces
-- the simulation with real stages; the modules under test are the same.
--
-- Broken versions are made by swapping one function of a module for the
-- run (the modules call each other through their tables for this) and
-- putting it back afterwards.
--
-- Run: luajit src/delivery/tests/137-test-delivery.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>"; exit status
-- 0 only when nothing failed.

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/delivery/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local room_key = require("123-room-key")
local seal = require("124-seal")
local records = require("126-inner-records")
local keyring = require("127-keyring")
local rooms = require("002-room-folders")
local recipients = require("041-recipients")
local message_log = require("081-message-log")
local codecs = require("083-record-codecs")
local delivered = require("130-delivered")
local timer = require("131-retry-timer")
local send = require("132-send")
local receive = require("133-receive")
local delivery = require("134-delivery")

local T = dofile(DIR .. "/src/delivery/tests/143-test-world.lua")(DIR, "delivery")
local sim, world, check, must, must_fail, swap = T.sim, T.world, T.check, T.must, T.must_fail, T.swap
local new_node, set_up, write, holds, job_of, missing = T.new_node, T.set_up, T.write, T.holds, T.job_of, T.missing
local run_until, answers_of, ROOM_PAIR, TOKEN = T.run_until, T.answers_of, T.ROOM_PAIR, T.TOKEN
local FLOOR, CEILING, SCRATCH = T.FLOOR, T.CEILING, T.SCRATCH
------------------------------------------------------------------------------
-- The delivered file on its own
------------------------------------------------------------------------------

check("the delivered file: a pair joins at 'now', the mark moves over closed gaps, the list stays short", function()
    sim.reset(); world.reset()
    local a = new_node("unit", { "127.0.0.9" }, 7509)
    local p = { address = "127.0.0.8", port = 7508 }
    message_log.append(a.home, a.tag, { id = "old1", from = "me", written = 100, arrived = 100, text = "before" })
    message_log.append(a.home, a.tag, { id = "old2", from = "me", written = 200, arrived = 200, text = "before" })
    delivered.join(a.home, a.tag, { p })
    must(missing(a, p.address, p.port) == 0, "a pair joining owes nothing already written")
    -- a record written later in the same second as the newest is still missing
    message_log.append(a.home, a.tag, { id = "same", from = "me", written = 200, arrived = 200, text = "same second" })
    for i, w in ipairs({ 300, 300, 400, 500 }) do
        message_log.append(a.home, a.tag, { id = "n" .. i, from = "me", written = w, arrived = w, text = "x" })
    end
    message_log.append(a.home, a.tag, { id = "theirs", from = "127.0.0.8 7508", written = 450, arrived = 450, text = "y" })
    must(missing(a, p.address, p.port) == 5, "five own records after joining are missing, theirs is not ours to send")
    delivered.acknowledge(a.home, a.tag, p, { "n3", "n4", "nonsense" })
    local line = delivered.read(a.home, a.tag)[delivered.key(p.address, p.port)]
    must(line.mark == 199 and #line.ids == 3, "acks after a gap stay in the list: mark " .. line.mark .. ", " .. #line.ids .. " ids")
    delivered.acknowledge(a.home, a.tag, p, { "same", "n1", "n2" })
    line = delivered.read(a.home, a.tag)[delivered.key(p.address, p.port)]
    must(line.mark == 500 and #line.ids == 0, "closing the gap moves the mark to 500 and empties the list, got "
        .. line.mark .. " and " .. #line.ids)
    delivered.join(a.home, a.tag, {})
    must(next((delivered.read(a.home, a.tag))) == nil, "a pair off the send list keeps its line")
end)

check("answers: an id without its word, an unknown word or a bad id makes the whole answer count for nothing", function()
    must(send.read_answers("a1 filed b2 duplicate")[2].word == "duplicate", "a good answer did not read")
    must(send.read_answers("a1 filed b2") == nil, "an id without its word was read")
    must(send.read_answers("a1 ok") == nil, "a bare ok was read")
    must(send.read_answers("a/1 filed") == nil, "a bad id was read")
    must(#send.read_answers("") == 0, "an empty answer is not an empty list")
end)

------------------------------------------------------------------------------
-- 1. Lost answer (R1, R2)
------------------------------------------------------------------------------

-- {{{ referee 1
local function referee_lost_answer(broken)
    local a, b = set_up()
    local seen, dropped = {}, false
    world.routes["127.0.0.2 7502"] = { to_client = function(chunk)
        seen[#seen + 1] = answers_of(chunk) or "?"
        if not dropped then dropped = true; return {} end
        return { chunk }
    end }
    local function run()
        local id = write(a, "the first message")
        sim.run(sim.now + 3 * 3600)
        local text_count = 0
        for _, record in ipairs(message_log.read(b.home, b.tag)) do
            if record.text == "the first message" then text_count = text_count + 1 end
        end
        must(holds(b, id) == 1 and text_count == 1, "B holds the message " .. text_count .. " times")
        must(seen[1] == id .. " filed" and seen[2] == id .. " duplicate",
            "B's answers were " .. tostring(seen[1]) .. " / " .. tostring(seen[2]))
        must(missing(a, "127.0.0.2", 7502) == 0, "A still counts it missing")
        must(job_of(a, "127.0.0.2", 7502).attempts == 2, "A made " .. job_of(a, "127.0.0.2", 7502).attempts .. " attempts, not 2")
    end
    if broken then broken(run) else run() end
end
-- }}}

check("1. an answer lost: the resend carries the same id, B answers duplicate, A stops after two attempts", function()
    referee_lost_answer()
end)
check("1. referee catches: a new id for every attempt", function()
    must_fail(referee_lost_answer, function(run)
        local real = delivered.missing_for
        swap(delivered, "missing_for", function(...)
            local list = {}
            for i, record in ipairs(real(...)) do
                local copy = {}
                for k, v in pairs(record) do copy[k] = v end
                copy.id = message_log.new_message_id()
                list[i] = copy
            end
            return list
        end, run)
    end, "new id per attempt")
end)
check("1. referee catches: a receiver that errors on a repeat", function()
    must_fail(referee_lost_answer, function(run)
        local real = message_log.append
        swap(message_log, "append", function(...)
            local word = real(...)
            if word == "duplicate" then error("already filed", 0) end
            return word
        end, run)
    end, "error on repeat")
end)

------------------------------------------------------------------------------
-- 2. Mutual send (R6)
------------------------------------------------------------------------------

-- {{{ referee 2
local function referee_mutual(options)
    local a, b = set_up(options)
    world.routes["127.0.0.1 7501"] = { delay = 2 }
    world.routes["127.0.0.2 7502"] = { delay = 2 }
    local from_a = write(a, "hello from A")
    local from_b = write(b, "hello from B")
    sim.run(sim.now + 20)
    must(holds(b, from_a) == 1 and holds(a, from_b) == 1, "a message did not arrive")
    for _, pair in ipairs({ { a, "127.0.0.2", 7502 }, { b, "127.0.0.1", 7501 } }) do
        local node, host, port = pair[1], pair[2], pair[3]
        local job = job_of(node, host, port)
        must(missing(node, host, port) == 0, node.name .. "'s message is not acknowledged after 20 s")
        must(job.attempts == 1 and job.timer.interval == FLOOR and not job.timer.failing,
            node.name .. " backed off: " .. job.attempts .. " attempts, interval " .. job.timer.interval)
    end
end
-- }}}

check("2. A and B send to each other at once through a 2-second delay: both delivered at once, neither backs off", function()
    referee_mutual()
end)
check("2. referee catches: a server that waits for its answer before accepting", function()
    must_fail(referee_mutual, { single_loop = true }, "one loop")
end)

------------------------------------------------------------------------------
-- 3. Edit while away (R4)
------------------------------------------------------------------------------

-- {{{ referee 3
local function referee_edit_away(broken)
    local a, b = set_up()
    local function run()
        world.listeners["127.0.0.2 7502"].up = false
        local id = write(a, "teh message")
        sim.run(sim.now + 10)
        local _, edit = a.stage:write(a.tag, { kind = "correction", target = id, text = "the message" }, math.floor(sim.now))
        sim.run(sim.now + 100)
        world.listeners["127.0.0.2 7502"].up = true
        sim.run(sim.now + 3600)
        must(holds(b, id) == 1, "B lacks the message")
        must(holds(b, edit) == 1, "B lacks the correction written while it was away")
        must(missing(a, "127.0.0.2", 7502) == 0, "A still counts something missing")
    end
    if broken then broken(run) else run() end
end
-- }}}

check("3. B away while A writes a message and its correction: B holds both when it returns", function()
    referee_edit_away()
end)
check("3. referee catches: an edit marked sent when it is planned", function()
    must_fail(referee_edit_away, function(run)
        local real = delivery.write
        swap(delivery, "write", function(home, tag, record, now)
            local word, id, send_list = real(home, tag, record, now)
            if record.kind == "correction" then
                for _, pair in ipairs(send_list) do delivered.acknowledge(home, tag, pair, { id }) end
            end
            return word, id, send_list
        end, run)
    end, "edit marked sent")
end)

------------------------------------------------------------------------------
-- 4. Held back is not failed (R7)
------------------------------------------------------------------------------

-- {{{ referee 4
local function referee_held(broken)
    local a, b = set_up()
    local function run()
        write(a, "one message")
        sim.run(sim.now + 5)
        local job = job_of(a, "127.0.0.2", 7502)
        must(job.attempts == 1 and missing(a, "127.0.0.2", 7502) == 0, "the message was not delivered at once")
        for _ = 1, 6 do
            job.timer:due_now(sim.now)          -- a round in which nothing is due
            sim.run(sim.now + 60)
        end
        must(job.timer.interval == FLOOR and not job.timer.failing,
            "after rounds with nothing to send the interval is " .. job.timer.interval)
        must(job.attempts == 1, "rounds with nothing to send counted as " .. (job.attempts - 1) .. " attempts")
    end
    if broken then broken(run) else run() end
end
-- }}}

check("4. rounds with nothing to send leave the interval at the floor", function()
    referee_held()
end)
check("4. referee catches: a held-back round counted as a failure", function()
    must_fail(referee_held, function(run)
        local real = send.attempt
        swap(send, "attempt", function(...)
            local result = real(...)
            if not result.attempted then
                result = { attempted = true, sent = 0, acknowledged = {}, complete = false, reason = "nothing" }
            end
            return result
        end, run)
    end, "held counted as failure")
end)

------------------------------------------------------------------------------
-- 5. Pile of fifty (R8)
------------------------------------------------------------------------------

-- {{{ local function interval_after_round
local function interval_after_round(count)
    local a = set_up()
    world.listeners["127.0.0.2 7502"].up = false
    for i = 1, count do write(a, "pile " .. i) end
    sim.run(sim.now + 5)
    local job = job_of(a, "127.0.0.2", 7502)
    return job.timer.interval, job.attempts
end
-- }}}

-- {{{ referee 5
local function referee_pile(broken)
    local function run()
        local one, one_attempts = interval_after_round(1)
        local fifty, fifty_attempts = interval_after_round(50)
        must(one_attempts == 1 and fifty_attempts == 1, "attempts in the round: " .. one_attempts .. " and " .. fifty_attempts)
        must(fifty == one, "after one message the interval is " .. one .. ", after fifty " .. fifty)
    end
    if broken then broken(run) else run() end
end
-- }}}

check("5. fifty messages written while B is down move B's timer once, as one message does", function()
    referee_pile()
end)
check("5. referee catches: backoff per message", function()
    must_fail(referee_pile, function(run)
        local real_attempt, real_after = send.attempt, delivery.after_attempt
        swap(send, "attempt", function(home, tag, pair, seams)
            local waiting = #delivered.missing_for(home, tag, pair)
            local result = real_attempt(home, tag, pair, seams)
            result.waiting = waiting
            return result
        end, function()
            swap(delivery, "after_attempt", function(job, result, now)
                if result.attempted and not result.complete then
                    for _ = 1, result.waiting do job.timer:failed(now) end
                else
                    real_after(job, result, now)
                end
            end, run)
        end)
    end, "per message")
end)

------------------------------------------------------------------------------
-- 6. Long absence (R11)
------------------------------------------------------------------------------

-- {{{ referee 6
local function referee_absence(broken)
    local a, b = set_up()
    local function run()
        world.listeners["127.0.0.2 7502"].up = false
        local ids = {}
        for i = 1, 5 do ids[i] = write(a, "while you were away " .. i) end
        local job = job_of(a, "127.0.0.2", 7502)
        sim.run(sim.now + 48 * 3600)
        local before = job.attempts
        sim.run(sim.now + 24 * 3600)
        local last_day = job.attempts - before
        local expected = 24 * 3600 / CEILING
        -- A day cuts the decks at arbitrary cards, so the count strays
        -- from 12 by up to 2 (11-13 in 99.7% of 3,000 trial runs, 10 and
        -- 14 in the rest); a cap or a stop gives 0.
        must(math.abs(last_day - expected) <= 2, "attempts in the third day: " .. last_day .. ", expected " .. expected .. " ± 2")
        world.listeners["127.0.0.2 7502"].up = true
        sim.run(sim.now + CEILING * 2)
        for i = 1, 5 do must(holds(b, ids[i]) == 1, "message " .. i .. " never reached B") end
        must(missing(a, "127.0.0.2", 7502) == 0, "A still counts something missing")
    end
    if broken then broken(run) else run() end
end
-- }}}

check("6. B down for 72 hours: tries go on at the ceiling (12 a day ± 2) and everything arrives afterwards", function()
    referee_absence()
end)
check("6. referee catches: a retry cap", function()
    must_fail(referee_absence, function(run)
        local real = delivery.after_attempt
        swap(delivery, "after_attempt", function(job, result, now)
            real(job, result, now)
            if job.timer.failures >= 10 then job.timer.due = nil end
        end, run)
    end, "retry cap")
end)

------------------------------------------------------------------------------
-- 7. Forged answer (R5)
------------------------------------------------------------------------------

-- {{{ referee 7
local OTHER_PAIR = room_key.key_pair("another room entirely")
local function referee_forged(broken)
    local a, b = set_up()
    local function run()
        local id
        local answer_count = 0
        world.routes["127.0.0.2 7502"] = { to_client = function(chunk)
            answer_count = answer_count + 1
            if answer_count == 1 then
                return { seal.seal(OTHER_PAIR, records.encode({ kind = "ack", answers = id .. " filed" })) }
            elseif answer_count == 2 then
                return { seal.seal(ROOM_PAIR, records.encode({ kind = "ack", answers = "someotherid filed" })) }
            end
            return { chunk }
        end }
        id = write(a, "answer me properly")
        local job = job_of(a, "127.0.0.2", 7502)
        must(run_until(function() return job.attempts >= 1 and not job.timer:is_due(sim.now) end, 60), "no first attempt")
        must(missing(a, "127.0.0.2", 7502) == 1, "an answer sealed with another room's key delivered it")
        must(run_until(function() return job.attempts >= 2 end, 600), "no second attempt")
        sim.run(sim.now + 5)
        must(missing(a, "127.0.0.2", 7502) == 1, "an answer naming another id delivered it")
        must(run_until(function() return missing(a, "127.0.0.2", 7502) == 0 end, 3600), "a genuine answer never delivered it")
    end
    if broken then broken(run) else run() end
end
-- }}}

check("7. answers sealed with another room's key, or naming another id, deliver nothing", function()
    referee_forged()
end)
check("7. referee catches: any answer on the connection counts", function()
    must_fail(referee_forged, function(run)
        swap(send, "accept_answer", function(_, _, sent)
            local ids = {}
            for id in pairs(sent) do ids[#ids + 1] = id end
            return ids
        end, run)
    end, "any answer")
end)

------------------------------------------------------------------------------
-- 8. Two addresses, two copies
------------------------------------------------------------------------------

-- {{{ referee 8
local function referee_two_addresses(broken)
    local a, b = set_up({ b_hosts = { "127.0.0.2", "127.0.0.3" } })
    local function run()
        world.listeners["127.0.0.3 7502"].up = false
        local id = write(a, "to both of your addresses")
        sim.run(sim.now + 5)
        must(missing(a, "127.0.0.2", 7502) == 0, "P did not get it")
        must(missing(a, "127.0.0.3", 7502) == 1, "P's acknowledgement marked Q delivered")
        world.listeners["127.0.0.3 7502"].up = true
        sim.run(sim.now + 600)
        must(missing(a, "127.0.0.3", 7502) == 0, "Q never got it")
        must(holds(b, id) == 1, "B holds it " .. holds(b, id) .. " times")
    end
    if broken then broken(run) else run() end
end
-- }}}

check("8. a member at two addresses gets the message at both; one acknowledging does not deliver the other", function()
    referee_two_addresses()
end)
check("8. referee catches: the first address that answers counts for the member", function()
    must_fail(referee_two_addresses, function(run)
        local real = delivered.acknowledge
        swap(delivered, "acknowledge", function(home, tag, _, ids)
            for _, pair in ipairs(recipients.send_list(home, tag)) do real(home, tag, pair, ids) end
        end, run)
    end, "first that answers")
end)

------------------------------------------------------------------------------
-- 9. The deck averages exactly
------------------------------------------------------------------------------

-- {{{ referee 9
local function referee_deck(broken)
    local function run()
        for _, interval in ipairs({ 7200, 100, 30 }) do
            local t = timer.new(interval, interval)
            for deck = 1, 6 do
                local total, cards = 0, {}
                for _ = 1, #timer.CARDS do
                    local wait = t:failed(0)
                    must(wait > 0, "a wait of " .. wait)
                    total = total + wait
                end
                must(total == #timer.CARDS * interval, "deck " .. deck .. " at " .. interval .. " s summed to "
                    .. total .. ", not " .. #timer.CARDS * interval)
            end
        end
    end
    if broken then broken(run) else run() end
end
-- }}}

check("9. over each full deck the waits add up to cards × interval", function()
    referee_deck()
end)
check("9. referee catches: drawing with replacement", function()
    must_fail(referee_deck, function(run)
        swap(timer, "deal", function() return timer.CARDS[timer.random_below(#timer.CARDS) + 1] end, run)
    end, "with replacement")
end)
check("9. two timers that fail together are dealt different orders (a real random source)", function()
    local same = 0
    for _ = 1, 20 do
        local t1, t2 = timer.new(7200, 7200), timer.new(7200, 7200)
        local w1, w2 = {}, {}
        for i = 1, 11 do w1[i] = t1:failed(0); w2[i] = t2:failed(0) end
        if table.concat(w1, ",") == table.concat(w2, ",") then same = same + 1 end
    end
    must(same == 0, same .. " of 20 pairs of timers were dealt the same order")
end)

------------------------------------------------------------------------------
-- Decisions on the open questions, checked
------------------------------------------------------------------------------

check("question 1: hearing B's frame makes A's backed-off pair for B due at once", function()
    local a, b = set_up()
    world.listeners["127.0.0.2 7502"].up = false
    local id = write(a, "waiting for you")
    sim.run(sim.now + 2)
    local job = job_of(a, "127.0.0.2", 7502)
    must(job.timer.failing and job.timer.due > sim.now + 10, "setup: A is not backed off")
    world.listeners["127.0.0.2 7502"].up = true
    write(b, "I am back")
    sim.run(sim.now + 3)
    must(holds(b, id) == 1, "A waited for its timer instead of sending on hearing B")
end)
check("question 2: after a restart every pair missing something is due at once", function()
    local a = set_up()
    world.listeners["127.0.0.2 7502"].up = false
    write(a, "before the restart")
    sim.run(sim.now + 2)
    local restarted = delivery.new_stage(a.home, { connect = function() return nil, "down" end })
    restarted:start(sim.now)
    must(restarted:job(a.tag, { address = "127.0.0.2", port = 7502 }).timer:is_due(sim.now), "not due after start")
end)
check("question 7: an edit whose message has not arrived is filed nowhere and answered with no word", function()
    local _, b = set_up()
    local orphan = { kind = "correction", id = "orphanedit", written = 1730000000, target = "nosuchid", text = "x" }
    local word, id, problem = receive.file_record(b.home, b.tag, records.encode(orphan),
        { host = "127.0.0.1", port = 40001 }, 1730000001)
    must(word == nil and id == "orphanedit" and problem, "an edit before its message was answered " .. tostring(word))
    must(holds(b, "orphanedit") == 0, "the orphaned edit was filed")
end)
check("a message from an address that is not a member is filed with the source port and adds no member", function()
    local a, b = set_up()
    local record = { kind = "message", id = "stranger1", written = 1730000000, target = "", text = "hi" }
    local word = receive.file_record(b.home, b.tag, records.encode(record), { host = "127.0.0.77", port = 41234 }, 1730000001)
    must(word == "filed", tostring(word))
    must(not recipients.is_member(b.home, b.tag, "127.0.0.77", 41234), "the source port became a member")
    local last = message_log.read(b.home, b.tag)
    must(last[#last].from == "127.0.0.77 41234", "from is " .. last[#last].from)
end)
check("an error inside an attempt is one failure, and the timer moves (R9)", function()
    local a = set_up()
    local stage = delivery.new_stage(a.home, { connect = function() error("the disk is full", 0) end })
    stage:write(a.tag, { kind = "message", text = "x" }, 1730000000)
    stage:pass(1730000000)
    local job = stage:job(a.tag, { address = "127.0.0.2", port = 7502 })
    must(job.attempts == 1 and job.timer.failing and job.timer.due > 1730000000, "the timer did not move")
end)

------------------------------------------------------------------------------
-- The pile at scale (step 6): what working out "missing" costs
------------------------------------------------------------------------------

check("measure: missing and acknowledging over a log of 10,000 own messages", function()
    sim.reset(); world.reset()
    local node = new_node("measure", { "127.0.0.50" }, 7550)
    local pair = { address = "127.0.0.51", port = 7551 }
    delivered.join(node.home, node.tag, { pair })
    local lines = {}
    local tsv = codecs.get(codecs.SHAPE)
    for i = 1, 10000 do
        lines[i] = tsv.encode({ id = "m" .. i, from = "me", written = 1730000000 + i, arrived = 1730000000 + i,
            kind = "message", target = "", text = "message number " .. i })
    end
    local file = assert(io.open(rooms.log_path(node.home, node.tag), "ab"))
    file:write(table.concat(lines))
    file:close()
    local started = os.clock()
    local list = delivered.missing_for(node.home, node.tag, pair)
    local missing_seconds = os.clock() - started
    local half = {}
    for i = 1, 5000 do half[i] = "m" .. (i * 2) end
    started = os.clock()
    delivered.acknowledge(node.home, node.tag, pair, half)
    local ack_seconds = os.clock() - started
    must(#list == 10000, #list .. " missing")
    must(#delivered.missing_for(node.home, node.tag, pair) == 5000, "half acknowledged")
    print(string.format("     measured: missing of 10,000 in %.3f s; acknowledging 5,000 out of order in %.3f s",
        missing_seconds, ack_seconds))
end)

T.finish()
