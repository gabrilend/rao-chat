-- 153-test-members.lua — the referees of issue 207 (contact syncing within
-- a room), each run against the real code and, where the issue names one,
-- against a deliberately broken version it must catch.
--
-- The homes are real rao-homes on disk; between them runs 143's simulated
-- world.  Every home announces through 212's real own_pairs (149), at
-- public-looking documentation addresses (198.51.100.x): a loopback
-- address is never shareable, so it could never be listed.
--
-- Run: luajit src/delivery/tests/153-test-members.lua [PROJECT_DIR]
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
local tokens = require("007-tokens")
local recipients = require("041-recipients")
local ignore = require("042-ignore-list")
local delivery = require("134-delivery")
local hello = require("145-hello")
local leaving = require("147-leaving")
local members = require("152-members")

local T = dofile(DIR .. "/src/delivery/tests/143-test-world.lua")(DIR, "members")
local sim, world, check, must, must_fail, swap = T.sim, T.world, T.check, T.must, T.must_fail, T.swap
local new_node, run_until, TOKEN = T.new_node, T.run_until, T.TOKEN

local A_PAIR = { address = "198.51.100.1", port = 7501 }
local B_PAIR = { address = "198.51.100.2", port = 7502 }
local C_PAIR = { address = "198.51.100.3", port = 7503 }
local D_PAIR = { address = "198.51.100.4", port = 7504 }
local PRIVATE = { address = "192.168.1.5", port = 7509 }
local SOURCE = { host = "203.0.113.9", port = 40999 }
local CLAIM = string.rep("7e", 16)
local CHILD = "members test child room"
local PARENT = "members test parent room"

-- {{{ local function now
local function now() return math.floor(sim.now) end
-- }}}

-- {{{ local function idle
local function idle(seconds) run_until(function() return false end, seconds) end
-- }}}

-- {{{ local function member
local function member(node, pair) return recipients.is_member(node.home, node.tag, pair.address, pair.port) end
-- }}}

-- {{{ local function attempts
-- How many connections the home at `from` made to `pair` so far.
local function attempts(from, pair)
    local n = 0
    for _, a in ipairs(world.attempts) do
        if a.from == from.address and a.address == pair.address and a.port == pair.port then n = n + 1 end
    end
    return n
end
-- }}}

-- {{{ local function spy
-- Runs fn with every members frame a home answers recorded, in order, as
-- {at = the answering stage, kind, record}; → that list.
local function spy(fn)
    local seen = {}
    local real = members.answer
    swap(members, "answer", function(stage, tag, record, peer, at)
        seen[#seen + 1] = { at = stage, kind = record.kind, record = record }
        return real(stage, tag, record, peer, at)
    end, function() fn(seen) end)
    return seen
end
-- }}}

-- {{{ local function count
local function count(seen, kind, stage)
    local n = 0
    for _, s in ipairs(seen) do
        if s.kind == kind and (stage == nil or s.at == stage) then n = n + 1 end
    end
    return n
end
-- }}}

-- {{{ local function plain_b
local function plain_b(token)
    return new_node("B", { B_PAIR.address }, B_PAIR.port, { announce = true, token = token })
end
-- }}}

-- {{{ local function three
-- A and B, each a member of the other and each having called the other
-- back (so each vouches the other); then C joins through A with the
-- token and A's pair.  options.token: the room's token (TOKEN); options.b:
-- a function making B; options.before_join(a, b): run before C joins.
-- → a, b, c.
local function three(options)
    options = options or {}
    sim.reset()
    world.reset()
    local token = options.token or TOKEN
    local a = new_node("A", { A_PAIR.address }, A_PAIR.port, { announce = true, token = token })
    local b = (options.b or plain_b)(token)
    recipients.add_member(a.home, a.tag, B_PAIR.address, B_PAIR.port)
    recipients.add_member(b.home, b.tag, A_PAIR.address, A_PAIR.port)
    a.stage:start(now())
    b.stage:start(now())
    must(run_until(function()
        return members.read_vouched(a.home, a.tag)[B_PAIR.address .. " " .. B_PAIR.port] ~= nil
           and members.read_vouched(b.home, b.tag)[A_PAIR.address .. " " .. A_PAIR.port] ~= nil
    end, 60), "set-up: A and B never called each other back")
    idle(5)
    if options.before_join then options.before_join(a, b) end
    local c = new_node("C", { C_PAIR.address }, C_PAIR.port, { announce = true, no_room = true })
    c.tag = hello.join(c.home, c.stage, { label = "joined", token = token, kind = "group", parent = "",
        mailbox_port = C_PAIR.port, pair = A_PAIR }, now())
    return a, b, c
end
-- }}}

-- {{{ local function settled
-- Runs until B and C hold each other, or 120 s pass; → whether they do.
local function settled(b, c)
    return run_until(function() return member(b, C_PAIR) and member(c, B_PAIR) end, 120)
end
-- }}}

------------------------------------------------------------------------------
-- The records and the digest
------------------------------------------------------------------------------

check("the three records read back; a list's claims line up with its pairs", function()
    local digest = string.rep("ab", 32)
    local back = records.decode(records.encode({ kind = "members-digest", id = "m1", digest = digest, count = 3 }))
    must(back.digest == digest and back.count == 3, "the digest did not read back")
    back = records.decode(records.encode({ kind = "members-ask", id = "m2", digest = digest, count = 0 }))
    must(back.kind == "members-ask" and back.count == 0, "the ask did not read back")
    back = records.decode(records.encode({ kind = "members", id = "m3", digest = digest,
        pairs = { { kind = "public", address = A_PAIR.address, port = A_PAIR.port } }, claims = CLAIM }))
    must(back.pairs[1].port == A_PAIR.port and back.claims == CLAIM, "the list did not read back")
    must(not pcall(records.decode, "members-digest\tm1\t" .. digest), "a digest without its count was read")
end)

check("the digest is of the set: any order, the same digest; another pair, another digest", function()
    local one = members.digest({ { address = A_PAIR.address, port = A_PAIR.port }, { address = B_PAIR.address, port = B_PAIR.port } })
    local two, n = members.digest({ { address = B_PAIR.address, port = B_PAIR.port }, { address = A_PAIR.address, port = A_PAIR.port } })
    must(one == two and n == 2 and #one == 64, "the order of the pairs changed the digest")
    must(members.digest({ { address = A_PAIR.address, port = A_PAIR.port } }) ~= one, "a smaller set had the same digest")
end)

check("shareable: public, global IPv6 and hostnames; never private, carrier, link-local or loopback", function()
    must(members.shareable("198.51.100.7") == "public", "a public address was not shareable")
    must(members.shareable("2001:db8::1") == "ipv6" or members.shareable("2606:4700::1") == "ipv6",
        "a global IPv6 address was not shareable")
    must(members.shareable("home.example.org") == "hostname", "a hostname was not shareable")
    for _, address in ipairs({ "192.168.1.5", "10.0.0.2", "172.16.4.4", "100.64.0.1", "169.254.1.1", "127.0.0.1", "fe80::1" }) do
        must(members.shareable(address) == nil, address .. " was shareable")
    end
end)

------------------------------------------------------------------------------
-- 1. A newcomer reaches everyone (and the joiner receives the list: 205's
--    referee 1, second half)
------------------------------------------------------------------------------

-- {{{ referee 1
local function referee_newcomer(broken)
    local function run()
        local a, b, c = three()
        must(run_until(function() return member(a, C_PAIR) end, 60), "A never added the joiner")
        must(settled(b, c), "B and C never learned each other through A's digest")
        must(attempts(B_PAIR, C_PAIR) >= 1, "B added C without calling C back")
        must(attempts(C_PAIR, B_PAIR) >= 1, "C added B without calling B back")
        must(member(c, A_PAIR) and member(c, B_PAIR), "the joiner does not hold the room's members")
        must(#recipients.flagged(b.home, b.tag) == 0, "B flagged C in a top room")
    end
    if not broken then return run() end
    -- Broken: the digest goes only to the member who was joined through
    -- (here: the newcomer, the last pair on the send list).
    local real = delivery.Stage.notice_members
    swap(delivery.Stage, "notice_members", function(self, tag, at)
        local made = real(self, tag, at)
        for i = 1, #made - 1 do made[i].done = true end
        return { made[#made] }
    end, run)
end
-- }}}

check("referee 1: C joins through A; B learns C from A's digest, asks, calls C back, adds C; C receives the list", function()
    referee_newcomer()
    must_fail(referee_newcomer, true, "sending the digest only to the newcomer")
end)

check("anyone may ask: D, holding only A, asks A for its list and calls each pair back", function()
    local a, b, c = three()
    must(settled(b, c), "set-up: B and C never learned each other")
    local d = new_node("D", { D_PAIR.address }, D_PAIR.port, { announce = true })
    recipients.add_member(d.home, d.tag, A_PAIR.address, A_PAIR.port)
    local job = d.stage:ask_members(d.tag, A_PAIR, now())
    must(run_until(function() return member(d, B_PAIR) and member(d, C_PAIR) end, 120),
        "D never added A's members: " .. tostring(job.why))
    must(job.done, "D's ask never finished")
    must(not member(a, D_PAIR) and not member(b, D_PAIR), "asking added the asker somewhere")
end)

------------------------------------------------------------------------------
-- 2. Idle is quiet
------------------------------------------------------------------------------

-- {{{ referee 2
local function referee_quiet(broken)
    local function run()
        local seen = spy(function(seen)
            local a, b, c = three()
            must(settled(b, c), "set-up: B and C never learned each other")
            idle(30)
            local notices = (a.stage.notices or 0) + (b.stage.notices or 0) + (c.stage.notices or 0)
            must(notices == 1, notices .. " notices for one arrival")
            must(count(seen, "members-digest") == 2, count(seen, "members-digest") .. " digests for one notice to two pairs")
            -- ten idle minutes: nothing
            local frames, connections = #seen, #world.attempts
            idle(600)
            must(#seen == frames, (#seen - frames) .. " members frames in 10 idle minutes")
            must(#world.attempts == connections, (#world.attempts - connections) .. " connections in 10 idle minutes")
            -- A's entry rewritten in another order: nothing either
            local list = recipients.members(a.home, a.tag)
            local reversed = {}
            for i = #list, 1, -1 do reversed[#reversed + 1] = list[i] end
            rooms.write_members(a.home, a.tag, reversed)
            idle(600)
            must(#seen == frames and #world.attempts == connections, "rewriting A's entry in another order sent something")
            -- and a digest from A now is answered with acks: the sets agree
            a.stage:notice_members(a.tag, now())
            idle(30)
            must(count(seen, "members-digest") == 4, "A's second notice did not reach B and C")
            must(count(seen, "members") == 2, (count(seen, "members") - 2) .. " lists sent for a digest that agrees")
        end)
        return seen
    end
    if not broken then return run() end
    -- Broken: a pair added from a received list sends a digest too.
    local real = members.receive_list
    swap(members, "receive_list", function(...)
        local made = real(...)
        for _, c in ipairs(made) do c.from_list = nil end
        return made
    end, run)
end
-- }}}

check("referee 2: one digest per notice, nothing in 10 idle minutes, a reordered entry sends nothing", function()
    referee_quiet()
    must_fail(referee_quiet, true, "sending a digest for pairs added from a list")
end)

------------------------------------------------------------------------------
-- 3. Ignored stays out
------------------------------------------------------------------------------

-- {{{ referee 3
local function referee_ignored(broken)
    local function run()
        local _, b, c = three({ before_join = function(_, b)
            ignore.ignore(b.home, C_PAIR.address, C_PAIR.port, "hide", "*", now())
        end })
        must(run_until(function() return member(c, B_PAIR) end, 120), "set-up: C never learned B")
        idle(60)
        must(not member(b, C_PAIR), "B added a pair it ignores from A's list")
        must(attempts(B_PAIR, C_PAIR) == 0, "B called back a pair it ignores")
    end
    if broken then swap(ignore, "refused_as_member", function() return false end, run) else run() end
end
-- }}}

check("referee 3: a list naming a pair B ignores: B neither calls it back nor adds it", function()
    referee_ignored()
    must_fail(referee_ignored, true, "no ignore check")
end)

------------------------------------------------------------------------------
-- 4. A child room's outsider is flagged, not sent to
------------------------------------------------------------------------------

check("referee 4: B's room is a child; C, not in the parent, arrives by list flagged and is not sent to", function()
    local function child_b(token)
        local b = new_node("B", { B_PAIR.address }, B_PAIR.port, { announce = true, no_room = true })
        local parent = rooms.make_room(b.home, { label = "the parent", token = PARENT, kind = "group", parent = "",
            members = {}, filed_under = "", mailbox_port = B_PAIR.port })
        recipients.add_member(b.home, parent, A_PAIR.address, A_PAIR.port)
        b.tag = rooms.make_room(b.home, { label = "the child", token = token, kind = "group",
            parent = tokens.token_fingerprint(PARENT), members = {}, filed_under = "", mailbox_port = "" })
        return b
    end
    local a, b, c = three({ token = CHILD, b = child_b })
    must(settled(b, c), "B never learned C, or C never learned B")
    local flagged = recipients.flagged(b.home, b.tag)
    must(#flagged == 1 and flagged[1].address == C_PAIR.address and flagged[1].port == C_PAIR.port,
        "C was added to B's child room without a flag")
    for _, pair in ipairs(recipients.send_list(b.home, b.tag)) do
        must(not (pair.address == C_PAIR.address and pair.port == C_PAIR.port), "a flagged C is on B's send list")
    end
    local before = attempts(B_PAIR, C_PAIR)
    local id = T.write(b, "to the child room")
    must(run_until(function() return T.holds(a, id) == 1 end, 60), "B's message never reached A")
    idle(60)
    must(T.holds(c, id) == 0, "B's message reached a flagged C")
    must(attempts(B_PAIR, C_PAIR) == before, "B connected to a flagged C after it was added")
end)

------------------------------------------------------------------------------
-- 5. Private pairs stay home
------------------------------------------------------------------------------

-- {{{ referee 5
local function referee_private(broken)
    local function run()
        spy(function(seen)
            local a, b, c = three({ before_join = function(a)
                -- A holds a pair on its own home network, called back once
                recipients.add_member(a.home, a.tag, PRIVATE.address, PRIVATE.port)
                members.vouch(a.home, a.tag, PRIVATE, CLAIM, now())
            end })
            must(settled(b, c), "set-up: B and C never learned each other")
            for _, s in ipairs(seen) do
                if s.kind == "members" then
                    for _, pair in ipairs(s.record.pairs) do
                        must(pair.address ~= PRIVATE.address, "A's list held the private pair " .. pair.address)
                    end
                end
            end
            must(not member(c, PRIVATE) and attempts(C_PAIR, PRIVATE) == 0, "C called back or added A's private pair")
            -- one that arrives anyway is not called back
            local forged = records.decode(records.encode({ kind = "members", id = "forged", digest = string.rep("0", 64),
                pairs = { { kind = "public", address = PRIVATE.address, port = PRIVATE.port } }, claims = CLAIM }))
            local made = members.receive_list(c.stage, c.tag, forged, SOURCE, now())
            must(#made == 0, "a private pair in a received list was called back")
        end)
    end
    if broken then swap(members, "shareable", function() return "public" end, run) else run() end
end
-- }}}

check("referee 5: A's list holds no private pair; one that arrives anyway is not called back", function()
    referee_private()
    must_fail(referee_private, true, "the list sent verbatim")
end)

------------------------------------------------------------------------------
-- 6. Replay after a leave
------------------------------------------------------------------------------

-- {{{ referee 6
local function referee_replay(broken)
    local function run()
        local a, b, c = three()
        must(settled(b, c), "set-up: B and C never learned each other")
        idle(5)
        local recorded = members.list_record(b.stage, b.tag, now())
        must(recorded ~= nil, "set-up: B lists nothing")
        local holds_c = false
        for _, pair in ipairs(recorded.pairs) do
            if pair.address == C_PAIR.address and pair.port == C_PAIR.port then holds_c = true end
        end
        must(holds_c, "set-up: B's list does not hold C")
        recorded = records.decode(records.encode(recorded))
        sim.now = sim.now + 2
        c.stage:leave(c.tag, now())
        must(run_until(function() return not member(a, C_PAIR) and not member(b, C_PAIR) end, 60),
            "set-up: C's leave was never confirmed")
        must(leaving.find(a.home, a.tag, C_PAIR) ~= nil, "set-up: A wrote no left line for C")
        -- A restarts (its checks are forgotten), then hears B's old list,
        -- replayed through the members frame's seam
        a = new_node("A", { A_PAIR.address }, A_PAIR.port, { restart = a, announce = true })
        local reply = members.answer(a.stage, a.tag, recorded, SOURCE, now())
        must(reply.kind == "ack", "A did not acknowledge the replayed list")
        idle(60)
        must(not member(a, C_PAIR), "a replayed list re-added C after its confirmed leave")
    end
    if broken then swap(leaving, "may_add_from_list", function() return true end, run) else run() end
end
-- }}}

check("referee 6: B's list recorded before C leaves, replayed to A after, leaves C out", function()
    referee_replay()
    must_fail(referee_replay, true, "adding list pairs without 208's guard")
end)

check("a list's own claims and pairs already held are skipped; a malformed claims line is refused", function()
    local a, b, c = three()
    must(settled(b, c), "set-up: B and C never learned each other")
    local list = records.decode(records.encode(members.list_record(a.stage, a.tag, now())))
    must(#members.receive_list(b.stage, b.tag, list, SOURCE, now()) == 0, "B called back pairs it already holds")
    local own = records.decode(records.encode(members.list_record(b.stage, b.tag, now())))
    must(#members.receive_list(b.stage, b.tag, own, SOURCE, now()) == 0, "B called back its own list")
    own.claims = CLAIM
    must(not pcall(members.receive_list, b.stage, b.tag, own, SOURCE, now()), "a list with too few claims was read")
end)

T.finish()
