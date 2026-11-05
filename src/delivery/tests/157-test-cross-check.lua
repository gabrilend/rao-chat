-- 157-test-cross-check.lua — the referees of issue 209 (periodic
-- cross-checking between members), each run against the real code and,
-- where the issue names one, against a deliberately broken version it
-- must catch.
--
-- The homes are real rao-homes on disk; between them runs 143's simulated
-- world, at documentation addresses (198.51.100.x).  Run it under the
-- loopback-only wrapper.
--
-- Run: luajit src/delivery/tests/157-test-cross-check.lua [PROJECT_DIR]
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
local rooms = require("002-room-folders")
local disk = require("003-disk")
local recipients = require("041-recipients")
local ignore = require("042-ignore-list")
local message_log = require("081-message-log")
local delivered = require("130-delivered")
local delivery = require("134-delivery")
local members = require("152-members")
local crosscheck = require("156-cross-check")

local T = dofile(DIR .. "/src/delivery/tests/143-test-world.lua")(DIR, "cross-check")
local sim, world, check, must, must_fail, swap = T.sim, T.world, T.check, T.must, T.must_fail, T.swap
local new_node, run_until = T.new_node, T.run_until

local A_PAIR = { address = "198.51.100.1", port = 7501 }
local B_PAIR = { address = "198.51.100.2", port = 7502 }
local C_PAIR = { address = "198.51.100.3", port = 7503 }
local PAIRS = { A = A_PAIR, B = B_PAIR, C = C_PAIR }

-- {{{ local function now
local function now() return math.floor(sim.now) end
-- }}}

-- {{{ local function idle
local function idle(seconds) run_until(function() return false end, seconds) end
-- }}}

-- {{{ local function from_text
local function from_text(pair) return pair.address .. " " .. pair.port end
-- }}}

-- {{{ local function room
-- The named homes, each a member of every other's room, started, their
-- hellos settled.  → the nodes, by name.
local function room(names)
    sim.reset()
    world.reset()
    local nodes = {}
    for _, name in ipairs(names) do
        local pair = PAIRS[name]
        nodes[name] = new_node(name, { pair.address }, pair.port, { announce = true })
    end
    for _, name in ipairs(names) do
        for _, other in ipairs(names) do
            if other ~= name then
                recipients.add_member(nodes[name].home, nodes[name].tag, PAIRS[other].address, PAIRS[other].port)
            end
        end
    end
    for _, name in ipairs(names) do nodes[name].stage:start(now()) end
    idle(20)
    return nodes
end
-- }}}

-- {{{ local function remove_from_log
-- Removes the record with this id from node's log by hand.
local function remove_from_log(node, id)
    local path = rooms.log_path(node.home, node.tag)
    local kept = {}
    for line in disk.read_all(path):gmatch("[^\n]*\n") do
        if not line:find(id, 1, true) then kept[#kept + 1] = line end
    end
    disk.write_atomic(path, table.concat(kept))
    message_log.forget_remembered_ids(path)
end
-- }}}

-- {{{ local function round_from
-- Runs node's cross-check round now and waits until its jobs finish.
local function round_from(node)
    local jobs = node.stage:crosscheck_round(now())
    must(run_until(function()
        for _, job in ipairs(jobs) do if not job.done then return false end end
        return true
    end, 60), node.name .. "'s cross-check round never finished")
    return jobs
end
-- }}}

-- {{{ local function sends_to
-- How many connections the home at `from` made to `pair`.
local function sends_to(from, pair)
    local n = 0
    for _, a in ipairs(world.attempts) do
        if a.from == from.address and a.address == pair.address and a.port == pair.port then n = n + 1 end
    end
    return n
end
-- }}}

-- {{{ local function append
-- Files a record in node's log as if it arrived from `pair`.
local function append(node, pair, id, text, written, arrived)
    return message_log.append(node.home, node.tag, { id = id, from = from_text(pair), written = written,
        arrived = arrived or written, text = text })
end
-- }}}

------------------------------------------------------------------------------
-- The pieces
------------------------------------------------------------------------------

check("summary and versions read back", function()
    local back = records.decode(records.encode({ kind = "summary", id = "s1", since = 1730000000,
        pairs = { { kind = "public", address = A_PAIR.address, port = A_PAIR.port } },
        entries = "m1:" .. string.rep("ab", 16) }))
    must(back.since == 1730000000 and back.pairs[1].port == A_PAIR.port, "the summary did not read back")
    local line = records.encode({ kind = "message", id = "m1", written = 5, target = "", text = "a\tb" })
    back = records.decode(records.encode({ kind = "versions", id = "v1", answers = "s1", records = line .. "\n" .. line }))
    must(back.records == line .. "\n" .. line, "the versions did not read back")
    must(not pcall(crosscheck.read_entries, "m1:short"), "a short fingerprint was read")
end)

check("the fingerprint covers id, written, kind, target and text, never from or arrived", function()
    local r = { id = "m1", from = "me", written = 100, arrived = 100, kind = "message", target = "", text = "hi" }
    local fp = crosscheck.fingerprint(r)
    must(#fp == 32 and fp:match("^%x+$"), "not 32 hex")
    local copy = { id = "m1", from = "198.51.100.1 7501", written = 100, arrived = 999, kind = "message", target = "", text = "hi" }
    must(crosscheck.fingerprint(copy) == fp, "from or arrived changed the fingerprint")
    for field, value in pairs({ written = 101, text = "hj", id = "m2" }) do
        local changed = { id = r.id, written = r.written, kind = r.kind, target = r.target, text = r.text }
        changed[field] = value
        must(crosscheck.fingerprint(changed) ~= fp, field .. " did not change the fingerprint")
    end
end)

check("forget makes only the named records missing; meant_for leaves out what was written before joining", function()
    sim.reset(); world.reset()
    local a = new_node("unit", { "198.51.100.9" }, 7509)
    local p = { address = "198.51.100.8", port = 7508 }
    message_log.append(a.home, a.tag, { id = "old1", from = "me", written = 100, arrived = 100, text = "before" })
    delivered.join(a.home, a.tag, { p })
    for i, w in ipairs({ 200, 300, 400 }) do
        message_log.append(a.home, a.tag, { id = "n" .. i, from = "me", written = w, arrived = w, text = "x" })
    end
    delivered.acknowledge(a.home, a.tag, p, { "n1", "n2", "n3" })
    must(#delivered.missing_for(a.home, a.tag, p) == 0, "set-up: something is missing")
    local meant = delivered.meant_for(a.home, a.tag, p)
    must(not meant.old1 and meant.n1 and meant.n3, "meant_for counted a record written before the pair joined")
    local forgotten = delivered.forget(a.home, a.tag, p, { "n2", "theirs" })
    must(#forgotten == 1 and forgotten[1] == "n2", "forget gave " .. #forgotten .. " ids")
    local missing = delivered.missing_for(a.home, a.tag, p)
    must(#missing == 1 and missing[1].id == "n2", #missing .. " missing, not just n2")
end)

------------------------------------------------------------------------------
-- 1. Gap filling uses the old id
------------------------------------------------------------------------------

-- {{{ referee 1
local function referee_old_id(broken)
    local function run()
        local h = room({ "A", "B" })
        local a, b = h.A, h.B
        local id = T.write(a, "the gap")
        must(run_until(function() return T.holds(b, id) == 1 end, 60), "set-up: B never got A's message")
        idle(5)
        remove_from_log(b, id)
        must(T.holds(b, id) == 0, "set-up: the message is still in B's log")
        round_from(b)
        must(run_until(function() return T.holds(b, id) == 1 end, 120), "A never sent the message again with its id")
        idle(30)
        local before = sends_to(A_PAIR, B_PAIR)
        round_from(b)
        idle(60)
        must(sends_to(A_PAIR, B_PAIR) == before, "a second summary made A send again")
        must(#message_log.read(b.home, b.tag) == 1, "B holds " .. #message_log.read(b.home, b.tag) .. " records, not 1")
    end
    if not broken then return run() end
    -- Broken: the gap is filled by writing the message again, as new.
    swap(crosscheck, "fill_gaps", function(stage, tag, record, at)
        local listed = crosscheck.read_entries(record.entries)
        for _, own in ipairs(delivered.own_records(stage.home, tag)) do
            if own.written >= record.since and not listed[own.id] then
                stage:write(tag, { kind = "message", text = own.text }, at)
            end
        end
        return {}
    end, run)
end
-- }}}

check("referee 1: a message removed from B's log comes back with its own id; a second summary sends nothing", function()
    referee_old_id()
    must_fail(referee_old_id, true, "writing it again with a new id")
end)

------------------------------------------------------------------------------
-- 2. Choices are respected
------------------------------------------------------------------------------

-- {{{ referee 2
local function referee_choices(broken)
    local function run()
        local h = room({ "A", "B", "C" })
        local a, b, c = h.A, h.B, h.C
        -- withheld: A writes while B is withheld; B's summary asks nothing of A
        recipients.withhold(a.home, a.tag, B_PAIR.address, B_PAIR.port)
        local hidden = T.write(a, "not for B")
        must(run_until(function() return T.holds(c, hidden) == 1 end, 60), "set-up: C never got A's message")
        round_from(b)
        idle(60)
        must(T.holds(b, hidden) == 0, "a summary sent a withheld pair what was kept from it")
        recipients.unwithhold(a.home, a.tag, B_PAIR.address, B_PAIR.port)
        -- someone else's message: C's, lost by B, is not A's to send
        local theirs = T.write(c, "C's own")
        must(run_until(function() return T.holds(a, theirs) == 1 and T.holds(b, theirs) == 1 end, 60),
            "set-up: C's message never reached A and B")
        remove_from_log(b, theirs)
        local before = sends_to(A_PAIR, B_PAIR)
        local woken = crosscheck.fill_gaps(a.stage, a.tag, records.decode(records.encode(
            crosscheck.summary_record(b.stage, b.tag, now()))), now())
        must(#woken == 0, "A woke a delivery for a message that is not its own")
        -- ignored: A's own message lost by B, B ignored on A
        local mine = T.write(a, "A's own")
        must(run_until(function() return T.holds(b, mine) == 1 end, 60), "set-up: B never got A's message")
        idle(5)
        remove_from_log(b, mine)
        ignore.ignore(a.home, B_PAIR.address, B_PAIR.port, "hide", "*", now())
        before = sends_to(A_PAIR, B_PAIR)
        round_from(b)
        idle(60)
        must(T.holds(b, mine) == 0, "a summary from an ignored pair made A send again")
        -- B's round also went to C, the writer of C's message, which filled
        -- its own gap: the one who may
        must(T.holds(b, theirs) == 1, "C did not fill its own gap in B's round")
        local jobs = a.stage:crosscheck_round(now())
        for _, job in ipairs(jobs) do
            must(not (job.pair.address == B_PAIR.address and job.pair.port == B_PAIR.port), "A summarises to an ignored pair")
        end
    end
    if broken then swap(ignore, "how_ignored", function() return "none" end, run) else run() end
end
-- }}}

check("referee 2: withheld, ignored, and someone else's message: nothing is sent again", function()
    referee_choices()
    must_fail(referee_choices, true, "resending to an ignored pair")
end)

------------------------------------------------------------------------------
-- 3. An edit is no discrepancy
------------------------------------------------------------------------------

check("referee 3: a message and its correction, summarised both ways, raise nothing", function()
    local h = room({ "A", "B", "C" })
    local id = T.write(h.A, "a typo")
    local _, fix = h.A.stage:write(h.A.tag, { kind = "correction", target = id, text = "no typo" }, now())
    must(run_until(function() return T.holds(h.B, fix) == 1 and T.holds(h.C, fix) == 1 end, 60),
        "set-up: the correction never reached B and C")
    for _, name in ipairs({ "A", "B", "C" }) do round_from(h[name]) end
    idle(30)
    for _, name in ipairs({ "A", "B", "C" }) do
        must(#(h[name].stage.conflicts or {}) == 0, name .. " raised an edit as a discrepancy")
    end
end)

------------------------------------------------------------------------------
-- 4. A two-faced sender is caught
------------------------------------------------------------------------------

-- {{{ referee 4
local function referee_two_faced(broken)
    local function run()
        local h = room({ "A", "B", "C" })
        local b, c = h.B, h.C
        local t = now()
        -- an honest message, arriving at different times at each
        append(b, A_PAIR, "honest1", "the same words", t - 50, t - 49)
        append(c, A_PAIR, "honest1", "the same words", t - 50, t - 40)
        -- one id, two texts
        append(b, A_PAIR, "twofaced", "X, for B", t - 30)
        append(c, A_PAIR, "twofaced", "Y, for C", t - 30)
        round_from(b)
        idle(10)
        for _, node in ipairs({ b, c }) do
            local list = node.stage.conflicts or {}
            must(#list == 1, node.name .. " raised " .. #list .. " discrepancies, not 1")
            local texts = list[1].mine.text .. " | " .. list[1].theirs.text
            must(list[1].id == "twofaced" and texts:match("X, for B") and texts:match("Y, for C"),
                node.name .. " did not raise both versions: " .. texts)
            local file = disk.read_all(crosscheck.conflicts_path(node.home, node.tag))
            must(file:match("X, for B") and file:match("Y, for C"), node.name .. "'s conflicts file lacks a version")
        end
        -- raised once: a second round adds nothing
        round_from(b)
        idle(10)
        must(#b.stage.conflicts == 1 and #c.stage.conflicts == 1, "a second round raised it again")
    end
    if broken == "from" then
        local real = crosscheck.agreed
        swap(crosscheck, "agreed", function(record) return real(record) .. tostring(record.from) .. tostring(record.arrived) end, run)
    elseif broken == "ids" then
        swap(crosscheck, "fingerprint", function() return string.rep("0", 32) end, run)
    else
        run()
    end
end
-- }}}

check("referee 4: one id with two texts, to B and to C: both raise it with both versions", function()
    referee_two_faced()
    must_fail(referee_two_faced, "from", "a fingerprint over from and arrived")
    must_fail(referee_two_faced, "ids", "comparing ids only")
end)

------------------------------------------------------------------------------
-- 5. Quiet servers summarise
------------------------------------------------------------------------------

-- {{{ referee 5
local function referee_quiet(broken)
    local function run()
        local interval = tonumber(T.START_CONFIG["crosscheck.interval"])
        local heard = nil
        local real = crosscheck.answer
        swap(crosscheck, "answer", function(stage, tag, record, peer, at)
            if record.kind == "summary" and not heard then heard = sim.now end
            return real(stage, tag, record, peer, at)
        end, function()
            sim.reset()
            world.reset()
            local a = new_node("A", { A_PAIR.address }, A_PAIR.port, { announce = true })
            local b = new_node("B", { B_PAIR.address }, B_PAIR.port, { announce = true })
            recipients.add_member(a.home, a.tag, B_PAIR.address, B_PAIR.port)
            recipients.add_member(b.home, b.tag, A_PAIR.address, A_PAIR.port)
            local started = sim.now
            a.stage:start(now())
            b.stage:start(now())
            run_until(function() return heard ~= nil end, interval + 5)
            must(heard ~= nil and heard <= started + interval + 1,
                "no summary within the interval plus one second (" .. interval .. " s)")
        end)
    end
    if not broken then return run() end
    -- Broken: the round is not on the stage's wake-up clock.
    local real_next = delivery.Stage.next_due
    swap(delivery.Stage, "next_due", function(self)
        local saved = self.crosscheck
        self.crosscheck = nil
        local due = real_next(self)
        self.crosscheck = saved
        return due
    end, run)
end
-- }}}

check("referee 5: with no traffic, a summary leaves within the interval plus one second", function()
    referee_quiet()
    must_fail(referee_quiet, true, "a round off the wake-up clock")
end)

------------------------------------------------------------------------------
-- 207's digest rides on the round (207's decision 1)
------------------------------------------------------------------------------

check("A's round sends 207's digest first: B, who did not know C, learns C from it", function()
    sim.reset()
    world.reset()
    local a = new_node("A", { A_PAIR.address }, A_PAIR.port, { announce = true })
    local b = new_node("B", { B_PAIR.address }, B_PAIR.port, { announce = true })
    local c = new_node("C", { C_PAIR.address }, C_PAIR.port, { announce = true })
    for _, x in ipairs({ { a, B_PAIR }, { a, C_PAIR }, { b, A_PAIR }, { c, A_PAIR } }) do
        recipients.add_member(x[1].home, x[1].tag, x[2].address, x[2].port)
    end
    for _, n in ipairs({ a, b, c }) do n.stage:start(now()) end
    must(run_until(function()
        local v = members.read_vouched(a.home, a.tag)
        return v[B_PAIR.address .. " " .. B_PAIR.port] and v[C_PAIR.address .. " " .. C_PAIR.port]
    end, 60), "set-up: A never called B and C back")
    idle(5)
    must(not recipients.is_member(b.home, b.tag, C_PAIR.address, C_PAIR.port), "set-up: B already holds C")
    round_from(a)
    must(run_until(function() return recipients.is_member(b.home, b.tag, C_PAIR.address, C_PAIR.port) end, 60),
        "B never learned C from A's round")
end)

check("a record older than the window is not listed", function()
    local h = room({ "A" })
    local _, window = crosscheck.settings(h.A.home)
    message_log.append(h.A.home, h.A.tag, { id = "ancient", from = "me", written = now() - window - 10,
        arrived = now() - window - 10, text = "long ago" })
    local id = T.write(h.A, "today")
    local entries = crosscheck.read_entries(crosscheck.summary_record(h.A.stage, h.A.tag, now()).entries)
    must(entries[id] and not entries.ancient, "the window was not applied")
end)

T.finish()
