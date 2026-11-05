-- 146-test-hello.lua — the referees of issue 205 (the hello), each run
-- against the real code and, where the issue names one, against a
-- deliberately broken version it must catch.
--
-- The homes are real rao-homes on disk; between them runs 143's simulated
-- world.  A home made with `announce` states a `public` pair for each of
-- its hosts (standing in for 212's own_pairs, not built).
--
-- Referee 7 (a merge moves the port, and the old port is served until
-- members call back) is built only in part: a move announces the new pair
-- and it is added beside the old one.  Keeping the old port served is the
-- gatherer's (211, not built); see the issue's decisions.
--
-- Run: luajit src/delivery/tests/146-test-hello.lua [PROJECT_DIR]
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
local claims = require("141-claims")
local call_back = require("142-call-back")
local hello = require("145-hello")

local T = dofile(DIR .. "/src/delivery/tests/143-test-world.lua")(DIR, "hello")
local sim, world, check, must, must_fail, swap = T.sim, T.world, T.check, T.must, T.must_fail, T.swap
local new_node, run_until, TOKEN = T.new_node, T.run_until, T.TOKEN

local A_PAIR = { address = "127.0.0.1", port = 7501 }
local B_PAIR = { address = "127.0.0.2", port = 7502 }
local CLAIM = string.rep("5a", 16)

-- {{{ local function fresh
-- A fresh world: A and B, each announcing, in one room, neither yet a
-- member of the other's room (options per home: a and b).
local function fresh(a_options, b_options)
    sim.reset()
    world.reset()
    a_options, b_options = a_options or {}, b_options or {}
    a_options.announce, b_options.announce = true, true
    return new_node("A", { A_PAIR.address }, A_PAIR.port, a_options),
           new_node("B", { B_PAIR.address }, B_PAIR.port, b_options)
end
-- }}}

-- {{{ local function now
local function now() return math.floor(sim.now) end
-- }}}

-- {{{ local function attempts_to
-- How many connections `from` made to `pair` so far.
local function attempts_to(from, pair)
    local count = 0
    for _, attempt in ipairs(world.attempts) do
        if attempt.from == from and attempt.address == pair.address and attempt.port == pair.port then
            count = count + 1
        end
    end
    return count
end
-- }}}

-- {{{ local function adding_on_receipt
-- The broken receiver of referees 1 and 2: every stated pair added at
-- once, nobody called back.
local function adding_on_receipt(run)
    swap(call_back, "heard", function(stage, tag, claim)
        recipients.add_member(stage.home, tag, claim.address, claim.port)
        return { state = "confirmed", tries = 0 }
    end, run)
end
-- }}}

------------------------------------------------------------------------------
-- The record and the pairs stated
------------------------------------------------------------------------------

check("the hello record: a claim and every pair with its kind, read back; an empty list is refused", function()
    local list = { { kind = "public", address = "203.0.113.5", port = 7501 },
                   { kind = "ipv6", address = "2001:db8::1", port = 7501 } }
    local line = records.encode({ kind = "hello", claim = CLAIM, pairs = list })
    must(not line:find("\n", 1, true), "a hello holds a raw line break")
    local back = records.decode(line)
    must(back.claim == CLAIM and #back.pairs == 2, "the hello did not read back")
    must(back.pairs[2].kind == "ipv6" and back.pairs[2].address == "2001:db8::1" and back.pairs[2].port == 7501,
        "the second pair did not read back")
    must(not pcall(records.encode, { kind = "hello", claim = CLAIM, pairs = {} }), "a hello stating no pair was written")
    must(not pcall(records.decode, "hello\t" .. CLAIM .. "\t"), "a hello stating no pair was read")
    must(not pcall(records.decode, "hello\t" .. CLAIM .. "\tsomewhere 127.0.0.1 7501"), "an unknown kind of pair was read")
    must(not pcall(records.decode, "hello\t" .. CLAIM .. "\tpublic 127.0.0.1 70000"), "a port over 65535 was read")
end)

check("the pairs stated: home-network pairs go only to a housemate; no own_pairs is an error, not a guess", function()
    local own = { { kind = "public", address = "203.0.113.5", port = 7501 },
                  { kind = "home-network", address = "192.168.1.4", port = 7501 } }
    local seams = { own_pairs = function() return own end }
    local stated = hello.stated_pairs(seams, "t", B_PAIR)
    must(#stated == 1 and stated[1].kind == "public", "a home-network pair was stated to a stranger")
    seams.is_housemate = function() return true end
    must(#hello.stated_pairs(seams, "t", B_PAIR) == 2, "a housemate was not told the home-network pair")
    must(not pcall(hello.stated_pairs, {}, "t", B_PAIR), "a hello was stated with no pairs from 212")
    must(not pcall(hello.stated_pairs, { own_pairs = function() return { own[2] } end }, "t", B_PAIR),
        "a hello stating nothing a stranger can use was made")
end)

check("claims: one id for every pair a hello states; yes for each of them, no for any other", function()
    local a = fresh()
    local id = claims.make_for(a.home, a.tag, "hello", { A_PAIR, { address = "a.example", port = 7501 } }, now())
    must(#claims.read(a.home, a.tag) == 2, "a claim of two pairs is not two lines")
    must(claims.answer(a.home, a.tag, id, A_PAIR) == "yes", "the first pair was not confirmed")
    must(claims.answer(a.home, a.tag, id, { address = "a.example", port = 7501 }) == "yes", "the second pair was not confirmed")
    must(claims.answer(a.home, a.tag, id, { address = "a.example", port = 7502 }) == "no", "a pair not stated was confirmed")
end)

------------------------------------------------------------------------------
-- 1. Joining adds you
------------------------------------------------------------------------------

-- {{{ referee 1
local function referee_join(broken)
    local function run()
        local a, b = fresh({ no_room = true })
        a.tag = hello.join(a.home, a.stage, { label = "joined", token = TOKEN, kind = "group", parent = "",
            mailbox_port = A_PAIR.port, pair = B_PAIR }, now())
        must(recipients.is_member(a.home, a.tag, B_PAIR.address, B_PAIR.port), "the joiner did not hold the pair it was given")
        must(run_until(function() return recipients.is_member(b.home, b.tag, A_PAIR.address, A_PAIR.port) end, 60),
            "B never added the joiner")
        must(attempts_to(B_PAIR.address, A_PAIR) >= 1, "B added the joiner without calling it back")
        local job = a.stage:hello(a.tag, B_PAIR, now())
        must(job.done, "the joiner's hello was never acknowledged: " .. tostring(job.why))
        local heard = recipients.members(b.home, b.tag)[1].heard
        must(heard > 0, "a confirmed hello did not count as hearing from the pair")
    end
    if broken then adding_on_receipt(run) else run() end
end
-- }}}

check("referee 1: A joins with the token and B's pair; B calls A back, then adds A", function()
    referee_join()
    must_fail(referee_join, true, "adding without calling back")
end)

------------------------------------------------------------------------------
-- 2. A wrong port is not confirmed
------------------------------------------------------------------------------

-- {{{ referee 2
local function referee_wrong_port(broken)
    local function run()
        local a, b = fresh()
        local wrong = { kind = "public", address = A_PAIR.address, port = 7999 }
        a.stage.seams.own_pairs = function() return { wrong } end
        local job = a.stage:hello(a.tag, B_PAIR, now())
        must(run_until(function() return job.done end, 60), "A's hello was never acknowledged: " .. tostring(job.why))
        run_until(function() return false end, 120)
        must(not recipients.is_member(b.home, b.tag, wrong.address, wrong.port), "a pair where nothing listens was added")
        local stage_check = nil
        for _, c in pairs(b.stage.checks) do stage_check = c end
        must(stage_check and stage_check.state == "unconfirmed" and not stage_check.done,
            "the check of the wrong port was dropped or settled")
    end
    if broken then adding_on_receipt(run) else run() end
end
-- }}}

check("referee 2: a hello naming a port where nothing listens stays unconfirmed, and is not added", function()
    referee_wrong_port()
    must_fail(referee_wrong_port, true, "adding on receipt")
end)

------------------------------------------------------------------------------
-- 3. No port is an error
------------------------------------------------------------------------------

-- {{{ referee 3
local function referee_no_port(decode)
    must(not pcall(decode, "hello\t" .. CLAIM .. "\tpublic 127.0.0.1"), "a pair without its port was read")
    must(not pcall(decode, "hello\t" .. CLAIM .. "\tpublic 127.0.0.1 7501\\nhostname a.example"),
        "a second pair without its port was read")
    must(not pcall(records.encode, { kind = "hello", claim = CLAIM, pairs = { { kind = "public", address = "127.0.0.1" } } }),
        "a pair without its port was written")
end
-- }}}

check("referee 3: a hello with a pair missing its port fails to decode (and to encode)", function()
    referee_no_port(records.decode)
    must_fail(referee_no_port, function(line)
        return records.decode((line:gsub("(%S+ %S+)$", "%1 7501"):gsub("(%S+ %S+)\\n", "%1 7501\\n")))
    end, "a default port")
end)

------------------------------------------------------------------------------
-- 4. A child room's outsider is flagged
------------------------------------------------------------------------------

check("referee 4: a hello to a child room from a pair not in the parent is added, flagged", function()
    local CHILD = "delivery test child room"
    local a, b = fresh({ token = CHILD })
    local child = rooms.make_room(b.home, { label = "the child", token = CHILD, kind = "group",
        parent = tokens.token_fingerprint(TOKEN), members = {}, filed_under = "", mailbox_port = "" })
    local job = a.stage:hello(a.tag, B_PAIR, now())
    must(run_until(function() return recipients.is_member(b.home, child, A_PAIR.address, A_PAIR.port) end, 60),
        "B never added A to the child room: " .. tostring(job.why))
    local flagged = recipients.flagged(b.home, child)
    must(#flagged == 1 and flagged[1].address == A_PAIR.address and flagged[1].port == A_PAIR.port,
        "A was added to the child room without a flag")
    must(not recipients.is_member(b.home, b.tag, A_PAIR.address, A_PAIR.port), "A was added to the parent")
end)

------------------------------------------------------------------------------
-- 5. Idle homes are quiet
------------------------------------------------------------------------------

-- {{{ referee 5
local function referee_quiet(broken)
    local function run()
        local a, b = fresh()
        recipients.add_member(a.home, a.tag, B_PAIR.address, B_PAIR.port)
        recipients.add_member(b.home, b.tag, A_PAIR.address, A_PAIR.port)
        a.stage:start(now())
        b.stage:start(now())
        run_until(function() return false end, 30)
        local after_round = #world.attempts
        must(after_round == 4, "the first round was " .. after_round .. " connections, not a hello and a call-back each way")
        run_until(function() return false end, 60)
        must(#world.attempts == after_round, "idle homes made " .. (#world.attempts - after_round) .. " more connections in 60 s")
        -- both restart: one hello each way, and nobody is called back
        a = new_node("A", { A_PAIR.address }, A_PAIR.port, { restart = a, announce = true })
        b = new_node("B", { B_PAIR.address }, B_PAIR.port, { restart = b, announce = true })
        a.stage:start(now())
        b.stage:start(now())
        run_until(function() return false end, 30)
        must(#world.attempts == after_round + 2,
            "the restart round was " .. (#world.attempts - after_round) .. " connections, not one hello each way")
        local settled = #world.attempts
        run_until(function() return false end, 60)
        must(#world.attempts == settled, "restarted idle homes made " .. (#world.attempts - settled) .. " more connections")
    end
    if not broken then return run() end
    local real = hello.receive
    swap(hello, "receive", function(stage, tag, record, peer, at)
        for _, pair in ipairs(record.pairs) do stage:hello(tag, pair, at, true) end
        return real(stage, tag, record, peer, at)
    end, run)
end
-- }}}

check("referee 5: two idle homes: one hello round and its call-backs, then 60 s of silence, before and after a restart", function()
    referee_quiet()
    must_fail(referee_quiet, true, "answering a hello with a hello")
end)

------------------------------------------------------------------------------
-- 6. Reflection
------------------------------------------------------------------------------

-- {{{ referee 6
local function referee_reflection(broken)
    local function run()
        local a = fresh()
        local job = a.stage:hello(a.tag, A_PAIR, now())
        must(run_until(function() return job.done end, 60), "A's hello to itself was never acknowledged")
        run_until(function() return false end, 30)
        must(#recipients.members(a.home, a.tag) == 0, "A's own hello sent back made A a member of its own room")
        must(next(a.stage.checks) == nil, "A called back its own pair")
    end
    if broken then swap(claims, "find", function() return nil end, run) else run() end
end
-- }}}

check("referee 6: A's own hello sent back to A adds nothing and calls nobody back", function()
    referee_reflection()
    must_fail(referee_reflection, true, "a receiver without the reflection guard")
end)

------------------------------------------------------------------------------
-- 7 (in part). A move: the new pair is announced and added beside the old
------------------------------------------------------------------------------

check("referee 7, in part: after a move A's new pair is announced, called back and added beside the old one", function()
    local a, b = fresh()
    recipients.add_member(a.home, a.tag, B_PAIR.address, B_PAIR.port)
    recipients.add_member(b.home, b.tag, A_PAIR.address, A_PAIR.port)
    a.stage:start(now())
    run_until(function() return false end, 30)
    -- A now listens on 7601 as well (the old port is still served: 211's)
    local moved = { kind = "public", address = A_PAIR.address, port = 7601 }
    world.listeners[moved.address .. " " .. moved.port] = world.listeners[A_PAIR.address .. " " .. A_PAIR.port]
    a.stage.seams.own_pairs = function() return { moved } end
    local before = a.stage:hello(a.tag, B_PAIR, now())
    a.stage:moved(now())
    local after = a.stage:hello(a.tag, B_PAIR, now())
    must(after ~= before, "a move did not make a fresh hello")
    must(run_until(function() return recipients.is_member(b.home, b.tag, moved.address, moved.port) end, 60),
        "B never added A's new pair")
    must(recipients.is_member(b.home, b.tag, A_PAIR.address, A_PAIR.port), "the new pair replaced the old one")
    must(after.claim ~= before.claim, "the move's hello reused the old claim")
end)

------------------------------------------------------------------------------
-- When a hello is sent
------------------------------------------------------------------------------

check("a hello goes before the first message to a pair never heard from, once per run, and the message follows", function()
    local a, b = fresh()
    recipients.add_member(a.home, a.tag, B_PAIR.address, B_PAIR.port)
    local id = T.write(a, "first")
    local job = a.stage.hellos[a.tag .. " " .. B_PAIR.address .. " " .. B_PAIR.port]
    must(job ~= nil, "no hello was made before the first message")
    T.write(a, "second")
    must(#a.stage.hello_order == 1, "a second message made a second hello")
    must(run_until(function() return T.holds(b, id) == 1 end, 60), "the message never arrived")
    must(run_until(function() return recipients.is_member(b.home, b.tag, A_PAIR.address, A_PAIR.port) end, 60),
        "B never added A from its hello")
end)

check("a stage without own_pairs (212 not wired) sends no hello, and join refuses", function()
    sim.reset()
    world.reset()
    local a = new_node("A", { A_PAIR.address }, A_PAIR.port)
    recipients.add_member(a.home, a.tag, B_PAIR.address, B_PAIR.port)
    T.write(a, "plain")
    a.stage:start(now())
    must(#a.stage.hello_order == 0, "a stage without own_pairs made a hello")
    must(not pcall(hello.join, a.home, a.stage, { label = "x", token = "another token", kind = "group", parent = "",
        mailbox_port = A_PAIR.port, pair = B_PAIR }, now()), "join guessed where this mailbox can be reached")
end)

T.finish()
