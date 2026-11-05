-- 143-test-world.lua — the simulated world the delivery tests run in
-- (202's 137 and 204's 144): a fake clock, cooperative threads, an
-- in-memory relay, and homes with their stages, plus the check kit.
--
-- Taken out of 137 when 204's referees needed the same world (2026-11-05).
-- Load it with dofile and call the function it returns:
--
--   local T = dofile(DIR .. "/src/delivery/tests/143-test-world.lua")(DIR, "delivery")
--
-- `name` is the scratch folder under tmp/shared-memory/.  T holds sim,
-- world, check, must, must_fail, swap, new_node, set_up, write, holds,
-- job_of, missing, run_until, answers_of, ROOM_PAIR, TOKEN, FLOOR,
-- CEILING, SCRATCH, START_CONFIG, and `finish()`, which removes the
-- scratch folder, prints "counts <passed> <failed>" and exits.
--
-- The relay records every connection attempt in world.attempts
-- ({from, address, port}), and its connections have LuaSocket's
-- settimeout, so a reader can cut its wait (204's answer time).

return function(DIR, name)

local room_key = require("123-room-key")
local seal = require("124-seal")
local records = require("126-inner-records")
local keyring = require("127-keyring")
local rooms = require("002-room-folders")
local recipients = require("041-recipients")
local message_log = require("081-message-log")
local delivered = require("130-delivered")
local receive = require("133-receive")
local delivery = require("134-delivery")
local leaving = require("147-leaving")
local members = require("152-members")
local reach = require("149-reach")

local T = { passed = 0, failed = 0 }
-- {{{ local function check
local function check(claim, test)
    local ok, problem = pcall(test)
    if ok then
        T.passed = T.passed + 1
        print("PASS " .. claim)
    else
        T.failed = T.failed + 1
        print("FAIL " .. claim .. ": " .. tostring(problem))
    end
end
-- }}}

-- {{{ local function must / must_fail
local function must(condition, words)
    if not condition then error(words, 2) end
end
-- A referee run against a broken version must raise an error; what it
-- caught is printed, so a broken version failing for the wrong reason (a
-- setup error) is seen.
local function must_fail(referee, broken, words)
    local ok, caught = pcall(referee, broken)
    if ok then error("the referee passed a broken version: " .. words, 2) end
    print("     caught: " .. tostring(caught):gsub("^[^:]*:%d+: ", ""))
end
-- }}}

-- {{{ local function swap
-- Replaces table[name] for the length of fn, and puts it back.
local function swap(tbl, name, value, fn)
    local old = tbl[name]
    tbl[name] = value
    local ok, problem = pcall(fn)
    tbl[name] = old
    if not ok then error(problem, 0) end
end
-- }}}

------------------------------------------------------------------------------
-- The simulation: a fake clock and cooperative threads
------------------------------------------------------------------------------

local sim = {}

-- {{{ function sim.reset
function sim.reset()
    sim.now = 1730000000
    sim.threads = {}
    sim.arrivals = {}
end
-- }}}

-- {{{ function sim.spawn
function sim.spawn(name, fn)
    sim.threads[#sim.threads + 1] = { name = name, co = coroutine.create(fn) }
end
-- }}}

-- {{{ function sim.block
-- Inside a thread: wait until check() is true or the clock reaches
-- until_time.
function sim.block(check_fn, until_time)
    coroutine.yield({ check = check_fn, until_time = until_time or math.huge })
end
-- }}}

-- {{{ function sim.at
-- Something will change at time t (a byte arriving, a close): the clock
-- may stop there.
function sim.at(t)
    sim.arrivals[#sim.arrivals + 1] = t
end
-- }}}

-- {{{ local function runnable
local function runnable(thread)
    local wait = thread.wait
    if wait == nil then return true end
    if sim.now >= wait.until_time then return true end
    return wait.check ~= nil and wait.check()
end
-- }}}

-- {{{ function sim.run
-- Runs every thread that can run; when none can, moves the clock to the
-- next time something happens; stops at until_time.
function sim.run(until_time)
    while true do
        local progressed = false
        local list = {}
        for i, thread in ipairs(sim.threads) do list[i] = thread end
        for _, thread in ipairs(list) do
            if not thread.done and runnable(thread) then
                local ok, wait = coroutine.resume(thread.co)
                if not ok then error("thread " .. thread.name .. ": " .. tostring(wait), 0) end
                if coroutine.status(thread.co) == "dead" then thread.done = true else thread.wait = wait end
                progressed = true
            end
        end
        if not progressed then
            local next_time = math.huge
            for _, thread in ipairs(sim.threads) do
                if not thread.done and thread.wait.until_time < next_time then next_time = thread.wait.until_time end
            end
            local kept = {}
            for _, t in ipairs(sim.arrivals) do
                if t > sim.now then
                    kept[#kept + 1] = t
                    if t < next_time then next_time = t end
                end
            end
            sim.arrivals = kept
            if next_time > until_time then
                sim.now = math.max(sim.now, until_time)
                return
            end
            sim.now = next_time
        end
    end
end
-- }}}

------------------------------------------------------------------------------
-- The relay: in-memory connections
------------------------------------------------------------------------------

-- {{{ local function new_pipe
-- One direction of a connection: chunks arrive `delay` seconds after they
-- are sent, in order.  filter(chunk) → list of chunks to deliver instead.
local function new_pipe(delay, filter)
    return { chunks = {}, buffer = "", delay = delay, filter = filter, closed_at = nil }
end
-- }}}

-- {{{ local function settle
local function settle(pipe)
    while #pipe.chunks > 0 and pipe.chunks[1].at <= sim.now do
        pipe.buffer = pipe.buffer .. table.remove(pipe.chunks, 1).data
    end
end
-- }}}

local Conn = {}
Conn.__index = Conn

-- {{{ function Conn:receive
-- LuaSocket's receive(n) with a timeout: n bytes, or nil, "timeout" or
-- "closed", and what came.
function Conn:receive(n)
    local pipe = self.inp
    local function ready()
        settle(pipe)
        return #pipe.buffer >= n or (pipe.closed_at ~= nil and pipe.closed_at <= sim.now) or self.closed
    end
    if not ready() then sim.block(ready, sim.now + self.timeout) end
    settle(pipe)
    if #pipe.buffer >= n then
        local data = pipe.buffer:sub(1, n)
        pipe.buffer = pipe.buffer:sub(n + 1)
        return data
    end
    local partial = pipe.buffer
    pipe.buffer = ""
    if self.closed or (pipe.closed_at and pipe.closed_at <= sim.now) then return nil, "closed", partial end
    return nil, "timeout", partial
end
-- }}}

-- {{{ function Conn:send
-- Takes everything at once (short writes are 201's referee 10's).
function Conn:send(data, i, j)
    if self.closed then return nil, "closed", i - 1 end
    local chunk = data:sub(i, j)
    local pipe = self.out
    local list = pipe.filter and pipe.filter(chunk) or { chunk }
    for _, piece in ipairs(list) do
        local at = sim.now + pipe.delay
        pipe.chunks[#pipe.chunks + 1] = { at = at, data = piece }
        sim.at(at)
    end
    return j
end
-- }}}

-- {{{ function Conn:settimeout
function Conn:settimeout(seconds)
    self.timeout = seconds
end
-- }}}

-- {{{ function Conn:close
function Conn:close()
    if self.closed then return end
    self.closed = true
    self.out.closed_at = sim.now + self.out.delay
    sim.at(self.out.closed_at)
end
-- }}}

local world = {}

-- {{{ function world.reset
function world.reset()
    world.attempts = {}
    world.listeners = {}
    world.routes = {}
    world.next_port = 40000
end
-- }}}

-- {{{ function world.connect
-- from_host, pair → a client connection, or nil and why.  The server's
-- end is queued at the listener at once (the system completes the
-- handshake whether or not the program is accepting).
function world.connect(from_host, pair)
    world.attempts[#world.attempts + 1] = { from = from_host, address = pair.address, port = pair.port }
    local listener = world.listeners[pair.address .. " " .. pair.port]
    if not listener or not listener.up then return nil, "connection refused" end
    local route = world.routes[pair.address .. " " .. pair.port] or {}
    local delay = route.delay or 0.05
    local up = new_pipe(delay, route.to_server)
    local down = new_pipe(delay, route.to_client)
    world.next_port = world.next_port + 1
    local client = setmetatable({ inp = down, out = up, timeout = 2.5 }, Conn)
    local server = setmetatable({ inp = up, out = down, timeout = 2.5,
        peer = { host = from_host, port = world.next_port }, listen_port = listener.port }, Conn)
    listener.queue[#listener.queue + 1] = server
    return client
end
-- }}}

------------------------------------------------------------------------------
-- Homes in the simulation
------------------------------------------------------------------------------

local SCRATCH = DIR .. "/tmp/shared-memory/" .. name
os.execute("rm -rf '" .. SCRATCH .. "' && mkdir -p '" .. SCRATCH .. "'")
local home_count = 0
local FLOOR, CEILING = 30, 7200
local TOKEN = "delivery test room"

-- {{{ local function first_variants
-- The first variant of every switchable choice (as the phase 1 demo's
-- homes start), so the real neighbours, which refuse to guess, can run.
local function first_variants()
    local config = {}
    local listing = io.popen("ls " .. DIR .. "/src/*/[0-9][0-9][0-9]-options.lua")
    for path in listing:lines() do
        for _, choice in ipairs(dofile(path)) do
            if choice.config_key ~= "" then config[choice.config_key] = choice.variants[1].name end
        end
    end
    listing:close()
    return config
end
-- }}}
local START_CONFIG = first_variants()

-- {{{ local function new_node
-- A home with one room (TOKEN) on its own mailbox port, listening at each
-- of `hosts` on that port.  options.single_loop: a broken server that
-- sends and accepts in one loop.  options.announce: the stage states
-- where it can be reached through 212's real own_pairs (149): the home's
-- `public-address` fact (in the home's folder, `ram/`) names its first
-- host, and every mailbox's outside port is its listening port unless
-- options.outside maps a listening port to another; so it sends hellos
-- (205).  options.ports: more listening ports than `port`, each served
-- with its own keyring.  options.no_room: the home
-- starts with no room (a joiner; node.tag is nil until it joins).
-- Hellos and leaves heard are handed to 147's on_claim (205, 208);
-- members digests, asks and lists to 152's answer (207).
local function new_node(name, hosts, port, options)
    options = options or {}
    local home, tag, home_path
    if options.restart then
        -- the same home on disk, started again: nothing in memory is kept
        home, tag, home_path = options.restart.home, options.restart.tag, options.restart.home_path
        options.restart.retired = true
    else
        home_count = home_count + 1
        home_path = SCRATCH .. "/" .. name .. "-" .. home_count
        home = rooms.open_home(home_path)
        for key, value in pairs(START_CONFIG) do rooms.set_config(home, key, value) end
        rooms.set_config(home, "delivery.retry-floor", tostring(FLOOR))
        rooms.set_config(home, "delivery.retry-ceiling", tostring(CEILING))
        if not options.no_room then
            tag = rooms.make_room(home, { label = "the room", token = options.token or TOKEN, kind = "group",
                parent = "", members = {}, filed_under = "", mailbox_port = port })
        end
    end
    local node = { name = name, host = hosts[1], port = port, home = home, tag = tag, problems = {},
                   queue = {}, answers = {}, home_path = home_path, ram = home_path .. "/ram" }
    local stage_seams = {
        connect = function(pair) return world.connect(node.host, pair) end,
        now = function() return sim.now end,
    }
    if options.announce then
        os.execute("mkdir -p '" .. node.ram .. "'")
        reach.write_fact(node.ram, { address = hosts[1], confirmed = math.floor(sim.now), operators = { "test" } })
        local real = reach.seam(home, node.ram, function() return { ipv6 = {}, private = {} } end)
        stage_seams.own_pairs = function(room_tag)
            -- the person has written every mailbox's outside port
            local written = reach.read_outside_ports(home)
            for _, mailbox in ipairs(rooms.read_mailboxes(home)) do
                if not written[mailbox.tag] then
                    reach.set_outside_port(home, mailbox.tag, (options.outside or {})[mailbox.port] or mailbox.port)
                end
            end
            return real(room_tag)
        end
    end
    node.stage = delivery.new_stage(home, stage_seams)
    for _, listening in ipairs({ port, unpack(options.ports or {}) }) do
        for _, host in ipairs(hosts) do
            world.listeners[host .. " " .. listening] = { up = true, queue = node.queue, port = listening }
        end
    end
    -- {{{ local function serve_seams
    local function serve_seams(conn)
        return {
            home = home, peer = conn.peer,
            ring = function() return keyring.for_port(rooms, home, conn.listen_port or port) end,
            now = function() return math.floor(sim.now) end,
            on_problem = function(_, words) node.problems[#node.problems + 1] = words end,
            on_opened = function(room_tag, peer) node.stage:heard_at(room_tag, peer.host, sim.now) end,
            on_claim = function(room_tag, record, peer)
                return leaving.on_claim(node.stage, room_tag, record, peer, math.floor(sim.now))
            end,
            on_members = function(room_tag, record, peer)
                return members.answer(node.stage, room_tag, record, peer, math.floor(sim.now))
            end,
        }
    end
    -- }}}
    local function due_now()
        local due = node.stage:next_due()
        return due ~= nil and due <= sim.now
    end
    if options.single_loop then
        -- Broken: one loop sends (waiting for each answer) and accepts.
        sim.spawn(name .. " loop", function()
            while true do
                node.stage:pass(sim.now)
                while #node.queue > 0 do
                    local conn = table.remove(node.queue, 1)
                    receive.serve(conn, serve_seams(conn))
                end
                sim.block(function() return #node.queue > 0 or due_now() end, node.stage:next_due())
            end
        end)
    else
        sim.spawn(name .. " accept", function()
            while not node.retired do
                sim.block(function() return #node.queue > 0 or node.retired end)
                if node.retired then return end
                while #node.queue > 0 do
                    local conn = table.remove(node.queue, 1)
                    sim.spawn(name .. " serve", function() receive.serve(conn, serve_seams(conn)) end)
                end
            end
        end)
        sim.spawn(name .. " send", function()
            while not node.retired do
                node.stage:pass(sim.now)
                sim.block(function() return due_now() or node.retired end, node.stage:next_due())
            end
        end)
    end
    return node
end
-- }}}

-- {{{ local function set_up
-- A fresh world: A at 127.0.0.1 and B at the hosts given (default
-- 127.0.0.2), both on their own port, each a member of the other's room.
local function set_up(options)
    options = options or {}
    sim.reset()
    world.reset()
    local a = new_node("A", { "127.0.0.1" }, 7501, options)
    local b = new_node("B", options.b_hosts or { "127.0.0.2" }, 7502, options)
    for _, host in ipairs(options.b_hosts or { "127.0.0.2" }) do
        recipients.add_member(a.home, a.tag, host, 7502)
    end
    recipients.add_member(b.home, b.tag, "127.0.0.1", 7501)
    return a, b
end
-- }}}

-- {{{ local function write
local function write(node, text)
    local _, id = node.stage:write(node.tag, { kind = "message", text = text }, math.floor(sim.now))
    return id
end
-- }}}

-- {{{ local function holds
-- How many records with this id node's log holds.
local function holds(node, id)
    local count = 0
    for _, record in ipairs(message_log.read(node.home, node.tag)) do
        if record.id == id then count = count + 1 end
    end
    return count
end
-- }}}

-- {{{ local function job_of
local function job_of(node, host, port)
    return node.stage:job(node.tag, { address = host, port = port })
end
-- }}}

-- {{{ local function missing
local function missing(node, host, port)
    return #delivered.missing_for(node.home, node.tag, { address = host, port = port })
end
-- }}}

-- {{{ local function run_until
-- Runs the world in one-second steps until condition() or the limit.
local function run_until(condition, limit)
    local stop = sim.now + limit
    while sim.now < stop do
        if condition() then return true end
        sim.run(sim.now + 1)
    end
    return condition()
end
-- }}}

-- {{{ local function answers_of
-- An answer frame as it passes the relay → its answers field, opened with
-- the room's key (the test holds the token).
local ROOM_PAIR = room_key.key_pair(TOKEN)
local function answers_of(chunk)
    local opened = seal.open(ROOM_PAIR, chunk:sub(5))
    if not opened then return nil end
    return records.decode(opened).answers
end
-- }}}


-- {{{ function T.finish
function T.finish()
    os.execute("rm -rf '" .. SCRATCH .. "'")
    print(string.format("counts %d %d", T.passed, T.failed))
    os.exit(T.failed == 0 and 0 or 1)
end
-- }}}

T.sim, T.world, T.check, T.must, T.must_fail, T.swap = sim, world, check, must, must_fail, swap
T.new_node, T.set_up, T.write, T.holds, T.job_of, T.missing = new_node, set_up, write, holds, job_of, missing
T.run_until, T.answers_of, T.ROOM_PAIR, T.TOKEN = run_until, answers_of, ROOM_PAIR, TOKEN
T.FLOOR, T.CEILING, T.SCRATCH, T.START_CONFIG = FLOOR, CEILING, SCRATCH, START_CONFIG
return T

end
