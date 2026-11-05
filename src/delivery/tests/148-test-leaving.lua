-- 148-test-leaving.lua — the referees of issue 208 (leaving a room), each
-- run against the real code and, where the issue names one, against a
-- deliberately broken version it must catch.
--
-- The homes are real rao-homes on disk; between them runs 143's simulated
-- world.  Homes announce (a stand-in for 212's own_pairs).  207's members
-- lists are not built: referee 4 replays a list through a stand-in
-- receiver that calls 147's guard, as 207's will.
--
-- Run: luajit src/delivery/tests/148-test-leaving.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>"; exit status
-- 0 only when nothing failed.

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/delivery/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local records = require("126-inner-records")
local disk = require("003-disk")
local recipients = require("041-recipients")
local message_log = require("081-message-log")
local delivered = require("130-delivered")
local call_back = require("142-call-back")
local leaving = require("147-leaving")

local T = dofile(DIR .. "/src/delivery/tests/143-test-world.lua")(DIR, "leaving")
local sim, world, check, must, must_fail, swap = T.sim, T.world, T.check, T.must, T.must_fail, T.swap
local new_node, run_until = T.new_node, T.run_until

local A_PAIR = { address = "127.0.0.1", port = 7501 }
local B_PAIR = { address = "127.0.0.2", port = 7502 }
local C_PAIR = { address = "127.0.0.3", port = 7503 }
local SOURCE = { host = "127.0.0.9", port = 40999 }

-- {{{ local function now
local function now() return math.floor(sim.now) end
-- }}}

-- {{{ local function idle
local function idle(seconds) run_until(function() return false end, seconds) end
-- }}}

-- {{{ local function member
local function member(node, pair) return recipients.is_member(node.home, node.tag, pair.address, pair.port) end
-- }}}

-- {{{ local function pair_up
-- A and B, announcing, each a member of the other, each having called the
-- other back (start-up hellos), and B with a delivered line for A.
local function pair_up()
    sim.reset()
    world.reset()
    local a = new_node("A", { A_PAIR.address }, A_PAIR.port, { announce = true })
    local b = new_node("B", { B_PAIR.address }, B_PAIR.port, { announce = true })
    recipients.add_member(a.home, a.tag, B_PAIR.address, B_PAIR.port)
    recipients.add_member(b.home, b.tag, A_PAIR.address, A_PAIR.port)
    a.stage:start(now())
    b.stage:start(now())
    local id = T.write(b, "before anyone leaves")
    must(run_until(function() return T.holds(a, id) == 1 end, 60), "set-up: B's first message never reached A")
    idle(5)
    return a, b
end
-- }}}

-- {{{ local function leave_and_settle
-- A leaves; the world runs until B has no A or 60 s pass.  → A's job to B.
local function leave_and_settle(a, b)
    sim.now = sim.now + 2
    local jobs = a.stage:leave(a.tag, now())
    run_until(function() return not member(b, A_PAIR) end, 60)
    return jobs[1]
end
-- }}}

------------------------------------------------------------------------------
-- The record and the file
------------------------------------------------------------------------------

check("the leave record: a claim, the leaver's written time and its pairs, read back", function()
    local claim = string.rep("3c", 16)
    local line = records.encode({ kind = "leave", claim = claim, written = 1730000000,
        pairs = { { kind = "public", address = "127.0.0.1", port = 7501 } } })
    local back = records.decode(line)
    must(back.claim == claim and back.written == 1730000000 and back.pairs[1].port == 7501, "the leave did not read back")
    must(not pcall(records.decode, "leave\t" .. claim .. "\t1730000000\tpublic 127.0.0.1"), "a leave without a port was read")
end)

------------------------------------------------------------------------------
-- 1. A genuine leave removes
------------------------------------------------------------------------------

check("referee 1: A leaves; B calls back, A says yes, B removes A and writes its left line", function()
    local a, b = pair_up()
    must(next((delivered.read(b.home, b.tag))) ~= nil, "set-up: B has no delivered line")
    local job = leave_and_settle(a, b)
    must(not member(b, A_PAIR), "B never removed A")
    must(job.done, "A's leave was never acknowledged: " .. tostring(job.why))
    local line = leaving.find(b.home, b.tag, A_PAIR)
    must(line ~= nil, "B wrote no left line for A")
    must(line.claim == job.claim and line.written == job.written and line.confirmed >= job.written,
        "the left line is not the confirmed leave: " .. disk.read_all(leaving.path(b.home, b.tag)))
    local lines = delivered.read(b.home, b.tag)
    must(lines[A_PAIR.address .. "\t" .. A_PAIR.port] == nil and next(lines) == nil, "B kept A's delivered line")
    must(leaving.own_left(a.home, a.tag) == job.written, "A did not note its own leave")
    must(member(a, B_PAIR), "leaving removed B from A's own room (only the leaver's notice changes)")
end)

------------------------------------------------------------------------------
-- 2. A forged leave does not
------------------------------------------------------------------------------

-- {{{ referee 2
local function referee_forged(broken)
    local function run()
        local a, b = pair_up()
        sim.now = sim.now + 1
        local c = new_node("C", { C_PAIR.address }, C_PAIR.port, { announce = true })
        recipients.add_member(c.home, c.tag, B_PAIR.address, B_PAIR.port)
        -- C holds the room's key and claims A's pair is leaving
        c.stage.seams.own_pairs = function() return { { kind = "public", address = A_PAIR.address, port = A_PAIR.port } } end
        local job = c.stage:leave(c.tag, now())[1]
        must(run_until(function() return job.done end, 60), "C's forged leave was never acknowledged")
        idle(60)
        must(member(b, A_PAIR), "a forged leave removed A")
        must(leaving.find(b.home, b.tag, A_PAIR) == nil, "a forged leave wrote a left line")
        local refused = false
        for _, c2 in pairs(b.stage.checks) do
            if c2.kind == "leave" and c2.state == "refused" then refused = true end
        end
        must(refused, "B did not ask A, or A did not say no")
    end
    if not broken then return run() end
    local real = call_back.heard
    swap(call_back, "heard", function(stage, tag, claim, source, at)
        if claim.kind ~= "leave" then return real(stage, tag, claim, source, at) end
        return { state = "confirmed", written = 0,
                 done = leaving.confirm(stage.home, tag, { address = claim.address, port = claim.port }, at,
                     { claim = claim.id, written = at }) }
    end, run)
end
-- }}}

check("referee 2: C sends a leave naming A's pair; A says no; nothing changes", function()
    referee_forged()
    must_fail(referee_forged, true, "removing on receipt")
end)

------------------------------------------------------------------------------
-- 3. Speaking again re-adds
------------------------------------------------------------------------------

check("referee 3: A writes after leaving; B files it, adds A back and clears its left line", function()
    local a, b = pair_up()
    leave_and_settle(a, b)
    must(leaving.find(b.home, b.tag, A_PAIR) ~= nil, "set-up: A did not leave")
    sim.now = sim.now + 2
    local id = T.write(a, "I'm back")
    must(leaving.own_left(a.home, a.tag) == nil, "writing did not end A's own leave")
    must(run_until(function() return T.holds(b, id) == 1 end, 60), "B never filed A's new message")
    local from = nil
    for _, record in ipairs(message_log.read(b.home, b.tag)) do if record.id == id then from = record.from end end
    must(from == A_PAIR.address .. " " .. A_PAIR.port, "the message was filed from " .. tostring(from) .. ", not A's pair")
    must(member(b, A_PAIR), "B did not add A back")
    must(leaving.find(b.home, b.tag, A_PAIR) == nil, "B kept A's left line")
end)

check("a message A wrote before its leave, arriving after it, is filed but re-adds nobody", function()
    local a, b = pair_up()
    local job = leave_and_settle(a, b)
    local old = { kind = "message", id = "late1", written = job.written - 1, target = "", text = "late" }
    local receive = require("133-receive")
    local word = receive.file_record(b.home, b.tag, records.encode(old), { host = A_PAIR.address, port = 41000 }, now())
    must(word == "filed", "the late message was not filed: " .. tostring(word))
    must(not member(b, A_PAIR), "a message older than the leave re-added A")
end)

check("A's hello after its leave re-adds A and clears the left line", function()
    local a, b = pair_up()
    leave_and_settle(a, b)
    sim.now = sim.now + 2
    local job = a.stage:hello(a.tag, B_PAIR, now(), true)
    must(run_until(function() return member(b, A_PAIR) end, 60), "A's hello did not re-add A: " .. tostring(job.why))
    must(leaving.find(b.home, b.tag, A_PAIR) == nil, "B kept A's left line after A's hello")
end)

check("a home that left gets no start-up hello in that room", function()
    local a, b = pair_up()
    leave_and_settle(a, b)
    a = new_node("A", { A_PAIR.address }, A_PAIR.port, { restart = a, announce = true })
    a.stage:start(now())
    must(#a.stage.hello_order == 0, "A announced itself in a room it left")
end)

------------------------------------------------------------------------------
-- 4. A replayed list does not re-add
------------------------------------------------------------------------------

-- {{{ local function replay_list
-- A stand-in for 207's receiving of a members list: each pair is added
-- unless 147's guard says it left.
local function replay_list(node, list)
    for _, pair in ipairs(list) do
        if leaving.may_add_from_list(node.home, node.tag, pair) then
            recipients.add_member(node.home, node.tag, pair.address, pair.port)
        end
    end
end
-- }}}

-- {{{ referee 4
local function referee_replayed_list(broken)
    local function run()
        local a, b = pair_up()
        local recorded = recipients.members(b.home, b.tag)
        must(#recorded == 1 and recorded[1].address == A_PAIR.address, "set-up: the recorded list does not hold A")
        leave_and_settle(a, b)
        must(not member(b, A_PAIR), "set-up: A did not leave")
        replay_list(b, recorded)
        must(not member(b, A_PAIR), "a replayed members list re-added A")
    end
    if broken then swap(leaving, "record", function() end, run) else run() end
end
-- }}}

check("referee 4: a members list recorded before A's leave, replayed after it, leaves A out", function()
    referee_replayed_list()
    must_fail(referee_replayed_list, true, "a leave with no record")
end)

------------------------------------------------------------------------------
-- 5. Pending is dropped
------------------------------------------------------------------------------

-- {{{ referee 5
local function referee_pending(broken)
    local function run()
        local a, b = pair_up()
        local key = A_PAIR.address .. " " .. A_PAIR.port
        world.listeners[key].up = false
        local id = T.write(b, "written while A is away")
        idle(2)
        must(T.missing(b, A_PAIR.address, A_PAIR.port) == 1, "set-up: the message is not pending for A")
        world.listeners[key].up = true
        a.stage:leave(a.tag, now())
        must(run_until(function() return not member(b, A_PAIR) end, 25), "set-up: B did not take A's leave in time")
        idle(600)
        must(T.holds(a, id) == 0, "a message pending at the leave was sent to A afterwards")
        must(T.missing(b, A_PAIR.address, A_PAIR.port) == 0, "A still has something pending at B")
    end
    if broken then swap(delivered, "drop", function() return false end, run) else run() end
end
-- }}}

check("referee 5: a message pending for A when A's leave is confirmed is never sent to A", function()
    referee_pending()
    must_fail(referee_pending, true, "keeping the leaver's delivered line")
end)

------------------------------------------------------------------------------
-- 6. Open question 1: a replayed leave after the leaver came back
------------------------------------------------------------------------------

-- {{{ referee 6
local function referee_replayed_leave(broken)
    local function run()
        local a, b = pair_up()
        local job = leave_and_settle(a, b)
        sim.now = sim.now + 2
        local id = T.write(a, "back again")
        must(run_until(function() return T.holds(b, id) == 1 and member(b, A_PAIR) end, 60), "set-up: A did not come back")
        -- B restarts (its checks are forgotten), then hears the old leave again
        b = new_node("B", { B_PAIR.address }, B_PAIR.port, { restart = b, announce = true })
        local old = records.decode(records.encode({ kind = "leave", claim = job.claim, written = job.written,
            pairs = job.pairs }))
        local _, made = leaving.on_claim(b.stage, b.tag, old, SOURCE, now())
        idle(60)
        must(member(b, A_PAIR), "a leave older than A's newest message removed A")
        must(#made == 0, "B called A back about a leave older than A's newest message")
    end
    if broken then swap(leaving, "latest_from", function() return 0 end, run) else run() end
end
-- }}}

check("referee 6 (open question 1): a replayed leave older than A's newest message is ignored", function()
    referee_replayed_leave()
    must_fail(referee_replayed_leave, true, "no written-time guard")
end)

check("reflection: A's own leave sent back to A changes nothing", function()
    local a = pair_up()
    local job = a.stage:leave(a.tag, now())[1]
    must(run_until(function() return job.done end, 60), "set-up: A's leave was never acknowledged")
    local record = records.decode(records.encode({ kind = "leave", claim = job.claim, written = job.written, pairs = job.pairs }))
    local _, made = leaving.on_claim(a.stage, a.tag, record, SOURCE, now())
    must(#made == 0, "A called itself back about its own leave")
    must(member(a, B_PAIR), "A's own leave changed A's room")
end)

T.finish()
