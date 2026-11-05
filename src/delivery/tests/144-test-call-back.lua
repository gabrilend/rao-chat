-- 144-test-call-back.lua — the referees of issue 204 (the call-back
-- check), each run against the real code and against a deliberately
-- broken version it must catch.
--
-- The homes are real rao-homes on disk; between them runs 143's simulated
-- world (a fake clock, coroutines for each home's stages, an in-memory
-- relay).  Claims are made with 141 directly, standing in for 205's hello
-- and 208's leave, which carry them and are not built yet; what B hears of
-- a claim is handed to 142's `heard`, as their receivers will.
--
-- Run: luajit src/delivery/tests/144-test-call-back.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>"; exit status
-- 0 only when nothing failed.

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/delivery/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local seal = require("124-seal")
local frames = require("125-frames")
local records = require("126-inner-records")
local rooms = require("002-room-folders")
local disk = require("003-disk")
local recipients = require("041-recipients")
local message_log = require("081-message-log")
local claims = require("141-claims")
local call_back = require("142-call-back")

local T = dofile(DIR .. "/src/delivery/tests/143-test-world.lua")(DIR, "call-back")
local sim, world, check, must, must_fail, swap = T.sim, T.world, T.check, T.must, T.must_fail, T.swap
local new_node, run_until, ROOM_PAIR = T.new_node, T.run_until, T.ROOM_PAIR

local A_PAIR = { address = "127.0.0.1", port = 7501 }
local SOURCE = { host = "127.0.0.9", port = 40999 }   -- a relay's address, say

-- {{{ local function world_of
-- A fresh world: A (the claimant) and B (who checks), in one room, neither
-- yet a member of the other's room; more homes as asked.
local function world_of(more)
    sim.reset()
    world.reset()
    local nodes = {
        a = new_node("A", { A_PAIR.address }, A_PAIR.port),
        b = new_node("B", { "127.0.0.2" }, 7502),
    }
    for key, spec in pairs(more or {}) do nodes[key] = new_node(spec[1], { spec[2] }, spec[3]) end
    return nodes
end
-- }}}

-- {{{ local function hello
-- A's claim to be at `pair`, made now: its id.
local function hello(a, pair)
    return claims.make(a.home, a.tag, "hello", pair or A_PAIR, math.floor(sim.now))
end
-- }}}

-- {{{ local function hear
-- B hears a hello claiming `pair` with claim id `id`, on a connection from
-- SOURCE: the check.
local function hear(b, id, pair, kind)
    return call_back.heard(b.stage, b.tag, { kind = kind or "hello", id = id, address = pair.address,
        port = pair.port }, SOURCE, math.floor(sim.now))
end
-- }}}

-- {{{ local function settled
local function settled(c) return function() return c.state ~= "unconfirmed" end end
-- }}}

------------------------------------------------------------------------------
-- The claims file and the answer on their own
------------------------------------------------------------------------------

check("claims: kept one line each in the room's folder; yes only for that claim at that pair", function()
    local n = world_of()
    local id = hello(n.a)
    must(claims.is_claim_id(id), "a claim id is not 32 hex characters: " .. tostring(id))
    local text = disk.read_all(claims.path(n.a.home, n.a.tag))
    must(text == string.format("hello\t%s\t%s\t127.0.0.1\t7501\t%d\n", n.a.tag, id, math.floor(sim.now)),
        "the claims line is not kind, room, id, address, port, made: " .. text)
    must(claims.answer(n.a.home, n.a.tag, id, A_PAIR) == "yes", "a claim made was not answered yes")
    must(claims.answer(n.a.home, n.a.tag, id, { address = "127.0.0.1", port = 7999 }) == "no",
        "a claim was confirmed for a pair it did not state")
    must(claims.answer(n.a.home, n.a.tag, string.rep("ab", 16), A_PAIR) == "no", "a claim never made was answered yes")
    must(claims.answer(n.a.home, n.a.tag, "nonsense", A_PAIR) == "no", "a malformed id was answered yes")
    must(claims.answer(n.b.home, n.b.tag, id, A_PAIR) == "no", "another home answered yes for A's claim")
    must(not pcall(claims.make, n.a.home, n.a.tag, "members", A_PAIR, 0), "a claim of an unknown kind was made")
end)

check("the records: did-you and did-you-answer have their rows and read back", function()
    local id = string.rep("0f", 16)
    local q = records.decode(records.encode({ kind = "did-you", claim = id, address = "127.0.0.1", port = 7501 }))
    must(q.kind == "did-you" and q.claim == id and q.address == "127.0.0.1" and q.port == 7501, "did-you did not read back")
    local a = records.decode(records.encode({ kind = "did-you-answer", claim = id, answer = "yes" }))
    must(a.kind == "did-you-answer" and a.answer == "yes", "did-you-answer did not read back")
end)

------------------------------------------------------------------------------
-- 1. A genuine claim is confirmed (even across a restart of the claimant)
------------------------------------------------------------------------------

-- {{{ referee 1
-- broken: a claimant that answers from memory, lost at restart.
local function referee_genuine(broken)
    local function run()
        local n = world_of()
        local id = hello(n.a)
        -- A restarts between its hello and B's ask
        if broken then broken.forget() end
        new_node("A", { A_PAIR.address }, A_PAIR.port, { restart = n.a })
        local c = hear(n.b, id, A_PAIR)
        must(run_until(settled(c), 60), "the check never settled: " .. tostring(c.why))
        must(c.state == "confirmed", "a genuine claim was " .. c.state .. ": " .. tostring(c.why))
        must(recipients.is_member(n.b.home, n.b.tag, A_PAIR.address, A_PAIR.port), "B did not add A's pair")
        must(c.tries == 1, "a confirmed claim took " .. c.tries .. " tries")
    end
    if not broken then return run() end
    local memory = {}
    broken.forget = function() memory = {} end
    swap(claims, "make", function(_, _, _, pair) local id = message_log.new_message_id(); memory[id] = pair; return id end,
        function()
            swap(claims, "answer", function(_, _, id, pair)
                local made = memory[id]
                return (made and made.address == pair.address and made.port == pair.port) and "yes" or "no"
            end, run)
        end)
end
-- }}}

check("referee 1: A claims its pair, restarts, and still answers yes; B adds the pair", function()
    referee_genuine()
    must_fail(referee_genuine, {}, "a claimant answering from memory lost at restart")
end)

------------------------------------------------------------------------------
-- 2. Someone else's address is refused
------------------------------------------------------------------------------

local C_PAIR = { address = "127.0.0.3", port = 7503 }
local NOBODY = { address = "127.0.0.4", port = 7504 }

-- {{{ referee 2
-- broken: confirming on any sealed answer.
local function referee_elsewhere(broken)
    local function run()
        local n = world_of({ c = { "C", C_PAIR.address, C_PAIR.port } })
        -- C holds the room's key and listens at C_PAIR; A claims to be there
        local at_c = hear(n.b, hello(n.a, C_PAIR), C_PAIR)
        local at_nobody = hear(n.b, hello(n.a, NOBODY), NOBODY)
        run_until(function() return at_c.state ~= "unconfirmed" end, 60)
        run_until(function() return at_nobody.tries >= 1 end, 60)
        must(at_c.state == "refused", "the home at C's pair answered: " .. at_c.state .. " (" .. tostring(at_c.why) .. ")")
        must(at_nobody.state == "unconfirmed", "a pair where nothing listens is " .. at_nobody.state)
        for _, p in ipairs({ C_PAIR, NOBODY }) do
            must(not recipients.is_member(n.b.home, n.b.tag, p.address, p.port),
                p.address .. " " .. p.port .. " was added")
        end
    end
    if broken then
        swap(call_back, "read_answer", function(keys, after)
            return seal.open(keys, after) and "yes" or nil
        end, run)
    else
        run()
    end
end
-- }}}

check("referee 2: a claim of another home's pair is answered no, of an empty pair not at all; neither is added", function()
    referee_elsewhere()
    must_fail(referee_elsewhere, true, "confirming on any sealed answer")
end)

------------------------------------------------------------------------------
-- 3. The source address is never called
------------------------------------------------------------------------------

-- {{{ referee 3
-- broken: rmail-style use of the connection's source address.
local function referee_source(broken)
    local function run()
        local n = world_of()
        -- something listens at the source too, so a call there would answer
        world.listeners[SOURCE.host .. " " .. A_PAIR.port] = { up = true, queue = {} }
        local c = hear(n.b, hello(n.a), A_PAIR)
        run_until(settled(c), 60)
        for _, attempt in ipairs(world.attempts) do
            must(attempt.address ~= SOURCE.host, "B connected to the claim's source " .. SOURCE.host)
        end
        must(c.state == "confirmed", "the stated pair was not confirmed: " .. c.state)
    end
    if broken then
        swap(call_back, "target", function(claim, source) return { address = source.host, port = claim.port } end, run)
    else
        run()
    end
end
-- }}}

check("referee 3: a claim arriving through 127.0.0.9 is checked at the stated pair; nothing connects to 127.0.0.9", function()
    referee_source()
    must_fail(referee_source, true, "calling back the connection's source")
end)

------------------------------------------------------------------------------
-- 4. No answer is not confirmation
------------------------------------------------------------------------------

-- {{{ referee 4
-- broken: a timeout treated as yes.
local function referee_silence(broken)
    local function run()
        local n = world_of()
        local answer_time = n.b.stage.answer_time or call_back.settings(n.b.home)
        -- the stated pair accepts connections (the system completes the
        -- handshake) and nothing there ever reads or answers them
        local key = A_PAIR.address .. " " .. A_PAIR.port
        local listening = world.listeners[key]
        world.listeners[key] = { up = true, queue = {} }
        local started = sim.now
        local c = hear(n.b, hello(n.a), A_PAIR)
        run_until(function() return c.tries >= 1 end, 120)
        local took = sim.now - started
        must(c.state == "unconfirmed", "a black-holed pair is " .. c.state)
        must(tostring(c.why):match("timeout"), "the first try did not end in a timeout: " .. tostring(c.why))
        must(took >= answer_time and took <= answer_time + 3,
            "the first try ended after " .. took .. " s, not after the answer time of " .. answer_time .. " s")
        must(not recipients.is_member(n.b.home, n.b.tag, A_PAIR.address, A_PAIR.port), "the pair was added")
        -- retried later on 202's timers, never dropped
        run_until(function() return c.tries >= 4 end, 3600)
        must(c.tries >= 4 and c.state == "unconfirmed", "the check was not retried: " .. c.tries .. " tries")
        -- the pair comes back: the next try confirms it
        world.listeners[key] = listening
        must(run_until(settled(c), 3600), "the check never settled once the pair answered")
        must(c.state == "confirmed", "once the pair answered, the check was " .. c.state)
    end
    if broken then
        local real = call_back.ask
        swap(call_back, "ask", function(...)
            local answer, why = real(...)
            if answer == nil and tostring(why):match("timeout") then return "yes" end
            return answer, why
        end, run)
    else
        run()
    end
end
-- }}}

check("referee 4: a black-holed pair stays unconfirmed after the answer time, is retried, and is confirmed once it answers", function()
    referee_silence()
    must_fail(referee_silence, true, "a timeout treated as yes")
end)

------------------------------------------------------------------------------
-- 5. Replays change nothing
------------------------------------------------------------------------------

-- {{{ local function replay
-- From a thread: connect to A from `host`, send the recorded bytes, read
-- one frame back → the answer's word (opened with the room's key), or nil.
local function replay(bytes, host)
    local result = {}
    sim.spawn("replayer", function()
        local conn = world.connect(host, A_PAIR)
        conn:send(bytes, 1, #bytes)
        local after = frames.read_frame(conn)
        conn:close()
        local opened = after and seal.open(ROOM_PAIR, after)
        result.answer = opened and records.decode(opened).answer
        result.done = true
    end)
    return result
end
-- }}}

-- {{{ local function state_of
local function state_of(node)
    local function read(path) return disk.is_file(path) and disk.read_all(path) or "" end
    return read(claims.path(node.home, node.tag)) .. "|" .. read(rooms.log_path(node.home, node.tag))
        .. "|" .. read(rooms.entry_path(node.home, node.tag))
end
-- }}}

-- {{{ referee 5
-- broken: an answerer that uses the claim up.
local function referee_replay(broken)
    local function run()
        local n = world_of()
        local recorded = {}
        world.routes[A_PAIR.address .. " " .. A_PAIR.port] = {
            to_server = function(chunk) recorded[#recorded + 1] = chunk; return { chunk } end }
        local c = hear(n.b, hello(n.a), A_PAIR)
        run_until(settled(c), 60)
        must(c.state == "confirmed", "the first ask was " .. c.state)
        local question = table.concat(recorded)
        local before = state_of(n.a)
        world.routes[A_PAIR.address .. " " .. A_PAIR.port] = nil
        local answers = {}
        for k = 1, 2 do
            local r = replay(question, "127.0.0.66")
            run_until(function() return r.done end, 30)
            answers[k] = r.answer
        end
        must(answers[1] == "yes" and answers[2] == "yes",
            "a replayed did-you was answered " .. tostring(answers[1]) .. " then " .. tostring(answers[2]))
        must(state_of(n.a) == before, "answering a replayed did-you changed A's files")
    end
    if broken then
        local real = call_back.answer_frame
        swap(call_back, "answer_frame", function(home, tag, record)
            local line = real(home, tag, record)
            -- the claim is crossed off once answered
            local kept = {}
            for _, claim in ipairs(claims.read(home, tag)) do
                if claim.id ~= record.claim then
                    kept[#kept + 1] = table.concat({ claim.kind, claim.room, claim.id, claim.address,
                        tostring(claim.port), tostring(claim.made) }, "\t") .. "\n"
                end
            end
            disk.write_atomic(claims.path(home, tag), table.concat(kept))
            return line
        end, run)
    else
        run()
    end
end
-- }}}

check("referee 5: a recorded did-you replayed twice gets the same answer and changes nothing", function()
    referee_replay()
    must_fail(referee_replay, true, "an answerer that uses the claim up")
end)

------------------------------------------------------------------------------
-- A leave, and a yes for one claim only
------------------------------------------------------------------------------

check("a confirmed leave removes the pair; a yes about one claim confirms no other", function()
    local n = world_of()
    recipients.add_member(n.b.home, n.b.tag, A_PAIR.address, A_PAIR.port)
    local leave_id = claims.make(n.a.home, n.a.tag, "leave", A_PAIR, math.floor(sim.now))
    local stranger = string.rep("5a", 16)
    local other = hear(n.b, stranger, A_PAIR, "leave")
    run_until(settled(other), 60)
    must(other.state == "refused", "a leave A never claimed was " .. other.state)
    must(recipients.is_member(n.b.home, n.b.tag, A_PAIR.address, A_PAIR.port), "an unclaimed leave removed A")
    local c = hear(n.b, leave_id, A_PAIR, "leave")
    c.written = math.floor(sim.now)   -- the leave's own time, as 208's receiver sets it
    run_until(settled(c), 60)
    must(c.state == "confirmed", "A's own leave was " .. c.state)
    must(not recipients.is_member(n.b.home, n.b.tag, A_PAIR.address, A_PAIR.port), "a confirmed leave left A a member")
end)

check("settings: callback.answer-time is read strictly, with no default", function()
    local n = world_of()
    rooms.set_config(n.b.home, "callback.answer-time", "0")
    must(not pcall(call_back.settings, n.b.home), "an answer time of 0 was accepted")
    rooms.set_config(n.b.home, "callback.answer-time", "8")
    must(call_back.settings(n.b.home) == 8, "the answer time did not read")
end)

T.finish()
