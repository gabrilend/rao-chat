-- 155-test-housemates.lua — the referees of issue 213 (finding housemates
-- on the home network), each run against the real code and, where the
-- issue names one, against a deliberately broken version it must catch.
--
-- Two homes behind one router share the public address 203.0.113.5 and
-- sit at 192.168.1.10 and 192.168.1.20 on the home network "home"
-- (192.168.1.0/24).  The router cannot loop a connection back in through
-- its public address (world.refuse).  Datagrams travel only inside 143's
-- simulated world; the one real datagram goes to 127.0.0.1.  Run it
-- under the loopback-only wrapper.
--
-- Run: luajit src/delivery/tests/155-test-housemates.lua [PROJECT_DIR]
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
local records = require("126-inner-records")
local room_key = require("123-room-key")
local rooms = require("002-room-folders")
local recipients = require("041-recipients")
local call_back = require("142-call-back")
local hello = require("145-hello")
local members = require("152-members")
local housemates = require("154-housemates")

local T = dofile(DIR .. "/src/delivery/tests/143-test-world.lua")(DIR, "housemates")
local sim, world, check, must, must_fail, swap = T.sim, T.world, T.check, T.must, T.must_fail, T.swap
local new_node, run_until, TOKEN = T.new_node, T.run_until, T.TOKEN

local PUBLIC = "203.0.113.5"
local NETWORK = { { network = "192.168.1.0", bits = 24, iface = "eth0" } }
local A_HOME = { address = "192.168.1.10", port = 7501 }
local B_HOME = { address = "192.168.1.20", port = 41000 }
local A_PUBLIC = { address = PUBLIC, port = 7501 }
local B_PUBLIC = { address = PUBLIC, port = 41000 }
local ROUTER = "192.168.1.1"
local CLAIM = string.rep("4d", 16)

-- {{{ local function now
local function now() return math.floor(sim.now) end
-- }}}

-- {{{ local function idle
local function idle(seconds) run_until(function() return false end, seconds) end
-- }}}

-- {{{ local function at_home
-- A home behind the router: public PUBLIC, home address `home`.
local function at_home(name, home)
    return new_node(name, { PUBLIC, home.address }, home.port, { announce = true, lan = "home",
        private = home.address, networks = NETWORK })
end
-- }}}

-- {{{ local function attempts
local function attempts(from, pair)
    local n = 0
    for _, a in ipairs(world.attempts) do
        if a.from == from and a.address == pair.address and a.port == pair.port then n = n + 1 end
    end
    return n
end
-- }}}

-- {{{ local function kept
local function kept(node, pair)
    for _, e in ipairs(node.housemates:list(node.tag)) do
        if e.home.address == pair.address and e.home.port == pair.port then return e end
    end
    return nil
end
-- }}}

-- {{{ local function behind_one_router
-- A and B behind one router, each a member of the other's room by public
-- pair; the router refuses to loop back.  Nothing searched yet.
local function behind_one_router()
    sim.reset()
    world.reset()
    local a, b = at_home("A", A_HOME), at_home("B", B_HOME)
    world.refuse = function(from, pair) return from:match("^192%.168%.1%.") ~= nil and pair.address == PUBLIC end
    recipients.add_member(a.home, a.tag, B_PUBLIC.address, B_PUBLIC.port)
    recipients.add_member(b.home, b.tag, A_PUBLIC.address, A_PUBLIC.port)
    return a, b
end
-- }}}

------------------------------------------------------------------------------
-- The pieces
------------------------------------------------------------------------------

check("discover and here read back with the hello's fields", function()
    local pairs_ = { { kind = "public", address = PUBLIC, port = 7501 }, { kind = "home-network", address = "192.168.1.10", port = 7501 } }
    for _, kind in ipairs({ "discover", "here" }) do
        local back = records.decode(records.encode({ kind = kind, claim = CLAIM, pairs = pairs_ }))
        must(back.kind == kind and back.claim == CLAIM and back.pairs[2].kind == "home-network", kind .. " did not read back")
    end
end)

check("the kernel's routing table gives attached private networks with their real masks", function()
    local path = T.SCRATCH .. "/route"
    local f = assert(io.open(path, "w"))
    f:write("Iface\tDestination\tGateway \tFlags\tRefCnt\tUse\tMetric\tMask\t\tMTU\tWindow\tIRTT\n",
        "eth0\t00000000\t0101A8C0\t0003\t0\t0\t100\t00000000\t0\t0\t0\n",       -- default route: left out
        "eth0\t0001A8C0\t00000000\t0001\t0\t0\t100\t00FFFFFF\t0\t0\t0\n",       -- 192.168.1.0/24
        "wlan0\t0000000A\t00000000\t0001\t0\t0\t600\t00F0FFFF\t0\t0\t0\n",      -- 10.0.0.0/20
        "docker0\t000011AC\t00000000\t0001\t0\t0\t0\t0000FFFF\t0\t0\t0\n",      -- 172.17.0.0/16
        "eth0\t00000A0A\t0101A8C0\t0003\t0\t0\t0\t00FFFFFF\t0\t0\t0\n",         -- via a gateway: left out
        "eth1\t00710033\t00000000\t0001\t0\t0\t0\t00FFFFFF\t0\t0\t0\n")         -- public: left out
    f:close()
    local list = housemates.read_networks(path)
    must(#list == 3, #list .. " networks, not 3")
    must(list[1].network == "192.168.1.0" and list[1].bits == 24, "the first network is " .. list[1].network .. "/" .. list[1].bits)
    must(list[2].network == "10.0.0.0" and list[2].bits == 20, "the second network is " .. list[2].network .. "/" .. list[2].bits)
    must(list[3].network == "172.17.0.0" and list[3].bits == 16, "the third network is " .. list[3].network .. "/" .. list[3].bits)
    must(#housemates.read_networks(T.SCRATCH .. "/no-such-file") == 0, "a missing table gave networks")
end)

check("the same-network test uses the real mask (open question 1)", function()
    local narrow = { { network = "192.168.1.0", bits = 25 } }
    must(housemates.on_own_network("192.168.1.100", narrow), "an address inside a /25 was refused")
    must(not housemates.on_own_network("192.168.1.130", narrow), "the first-three-numbers rule was used")
    must(housemates.on_own_network("10.0.15.3", { { network = "10.0.0.0", bits = 20 } }), "an address inside a /20 was refused")
    must(not housemates.on_own_network("10.0.16.3", { { network = "10.0.0.0", bits = 20 } }), "an address past a /20 was taken")
    must(not housemates.on_own_network(PUBLIC, NETWORK), "a public address was on the home network")
end)

check("the sweep: every host of a /24 but this one; a wider network on the /24 around it", function()
    local list = housemates.sweep_addresses(NETWORK, { "192.168.1.10" })
    must(#list == 253 and list[1] == "192.168.1.1" and list[#list] == "192.168.1.254", #list .. " addresses swept")
    for _, address in ipairs(list) do must(address ~= "192.168.1.10", "the sweep went to this machine") end
    local wide = housemates.sweep_addresses({ { network = "10.0.0.0", bits = 16 } }, { "10.0.7.9" })
    must(#wide == 253 and wide[1] == "10.0.7.1" and wide[#wide] == "10.0.7.254", "a /16 was swept as " .. #wide .. " addresses")
end)

------------------------------------------------------------------------------
-- 1. Discovery trusts the body
------------------------------------------------------------------------------

-- {{{ referee 1
local function referee_body(broken)
    local function run()
        local a, b = behind_one_router()
        world.rewrite_source = function() return ROUTER end
        b.housemates:start(now())
        must(run_until(function() return kept(a, B_HOME) ~= nil end, 60),
            "A never kept B's home pair (192.168.1.20, 41000)")
        must(attempts(A_HOME.address, { address = ROUTER, port = 50000 }) == 0, "A called the router back")
        local e = kept(a, B_HOME)
        must(#e.stated == 1 and e.stated[1].address == PUBLIC and e.stated[1].port == B_PUBLIC.port,
            "A did not keep the public pair B stated")
    end
    if not broken then return run() end
    swap(housemates, "body_pair", function(_, source) return { address = source.host, port = source.port } end, run)
end
-- }}}

check("referee 1: a discover whose source is the router's: the pair kept is the one inside the seal", function()
    referee_body()
    must_fail(referee_body, true, "using the packet's source")
end)

check("both find each other; A's message to B goes in through the home network", function()
    local a, b = behind_one_router()
    a.housemates:start(now())
    must(run_until(function() return kept(a, B_HOME) and kept(b, A_HOME) end, 60), "A and B never kept each other")
    must(a.housemates:route(B_PUBLIC).address == B_HOME.address, "A does not route B's public pair inside")
    local id = T.write(a, "through the house")
    must(run_until(function() return T.holds(b, id) == 1 end, 60), "A's message never reached B")
    must(attempts(A_HOME.address, B_HOME) >= 1, "the message did not go to B's home pair")
    -- a hello to a housemate states the home-network pair; to anyone else it does not
    local to_b = hello.stated_pairs(a.stage.seams, a.tag, B_PUBLIC)
    local to_stranger = hello.stated_pairs(a.stage.seams, a.tag, { address = "198.51.100.9", port = 7509 })
    local function has_home(list) for _, p in ipairs(list) do if p.kind == "home-network" then return true end end end
    must(has_home(to_b), "a hello to a housemate left out the home-network pair")
    must(not has_home(to_stranger), "a hello to a stranger stated the home-network pair")
end)

check("without the search, the router's refusal keeps A's message from B", function()
    local a, b = behind_one_router()
    local id = T.write(a, "around the router")
    idle(60)
    must(T.holds(b, id) == 0, "the world let a connection loop back through the router")
end)

------------------------------------------------------------------------------
-- 2. A relaying router is not a housemate
------------------------------------------------------------------------------

-- {{{ referee 2
local function referee_relay(broken)
    local function run()
        sim.reset()
        world.reset()
        local a = at_home("A", A_HOME)
        local c = new_node("C", { "10.0.0.7" }, 7509, { announce = true })
        recipients.add_member(a.home, a.tag, "10.0.0.7", 7509)
        recipients.add_member(c.home, c.tag, PUBLIC, A_PUBLIC.port)
        local first = T.write(c, "relayed once")
        local second = T.write(c, "relayed twice")
        must(run_until(function() return T.holds(a, first) == 1 and T.holds(a, second) == 1 end, 60),
            "set-up: C's messages never reached A")
        must(next(a.housemates.seen) == nil, "A kept a relaying router's address")
        must(#world.datagrams == 0, "a relaying router's connection started a search")
        must(#a.logged == 1 and a.logged[1]:match("10%.0%.0%.7"), #a.logged .. " log lines for one relay, not 1")
        -- the control: an address on this machine's own network is a housemate's
        must(a.housemates:from_connection(a.tag, { host = "192.168.1.30", port = 50123 }, now()) == "housemate",
            "an address on the home network was not taken as a housemate's")
        must(#world.datagrams > 0, "a housemate's connection did not start a search")
    end
    if not broken then return run() end
    swap(housemates, "on_own_network", function() return NETWORK[1] end, run)
end
-- }}}

check("referee 2: a connection from a private address on another network keeps nothing", function()
    referee_relay()
    must_fail(referee_relay, true, "recording the source")
end)

------------------------------------------------------------------------------
-- 3. No housemate, no traffic
------------------------------------------------------------------------------

-- {{{ referee 3
local function referee_quiet(broken)
    local function run()
        sim.reset()
        world.reset()
        local a = at_home("A", A_HOME)
        local d = new_node("D", { "198.51.100.4" }, 7504, { announce = true })
        recipients.add_member(a.home, a.tag, "198.51.100.4", 7504)
        recipients.add_member(d.home, d.tag, PUBLIC, A_PUBLIC.port)
        a.housemates:start(now())
        local id = T.write(d, "from elsewhere")
        must(run_until(function() return T.holds(a, id) == 1 end, 60), "set-up: D's message never reached A")
        a.housemates:moved(now())
        idle(30)
        must(#world.datagrams == 0, #world.datagrams .. " datagrams from a home with no pair at its public address")
    end
    if not broken then return run() end
    swap(housemates.Housemates, "needs_search", function() return "public address" end, run)
end
-- }}}

check("referee 3: a home whose rooms hold no pair at its public address sends no discover", function()
    referee_quiet()
    must_fail(referee_quiet, true, "searching every room")
end)

------------------------------------------------------------------------------
-- 4. Found pairs are called back and never shared
------------------------------------------------------------------------------

-- {{{ referee 4
local function referee_called_back(broken)
    local function run()
        local a, b = behind_one_router()
        -- someone holding the room's key claims A's home pair, under a
        -- claim A never made
        local keys = room_key.key_pair(rooms.read_entry(b.home, b.tag).token)
        local forged = seal.seal(keys, records.encode({ kind = "discover", claim = CLAIM,
            pairs = { { kind = "home-network", address = A_HOME.address, port = A_HOME.port } } })):sub(5)
        local what = b.housemates:receive(forged, { host = "192.168.1.66", port = 50000 }, B_HOME.port, now())
        must(what == "answered", "B did not take the forged discover as a claim: " .. tostring(what))
        must(kept(b, A_HOME) == nil, "B kept the pair a discover named before calling it back")
        idle(30)
        must(attempts(B_HOME.address, A_HOME) >= 1, "B never called A's home pair back")
        -- (A, hearing B's call-back from its home network, searches and is
        -- then rightly kept under its own claim; the forged one is not)
        for _, e in ipairs(b.housemates:list(b.tag)) do
            must(e.claim ~= CLAIM, "B kept a pair under a claim its home never made")
        end
        local refused = false
        for _, c in pairs(b.stage.checks) do
            if c.claim == CLAIM and c.state == "refused" then refused = true end
        end
        must(refused, "A did not answer no to the forged claim")
    end
    if not broken then return run() end
    local real = housemates.Housemates.receive
    swap(housemates.Housemates, "receive", function(self, bytes, source, port, at)
        local what, made = real(self, bytes, source, port, at)
        if type(made) == "table" then self:keep(made.tag, made, at) end
        return what, made
    end, run)
end
-- }}}

check("referee 4: a found pair is kept only when it answers yes to the claim", function()
    referee_called_back()
    must_fail(referee_called_back, true, "keeping on receipt")
end)

check("referee 4: found pairs are never members and never in a members list", function()
    local a, b = behind_one_router()
    a.housemates:start(now())
    must(run_until(function() return kept(a, B_HOME) and kept(b, A_HOME) end, 60), "set-up: A and B never kept each other")
    must(not recipients.is_member(a.home, a.tag, B_HOME.address, B_HOME.port), "a housemate's home pair became a member")
    for _, e in ipairs(members.held(a.stage, a.tag)) do
        must(e.address ~= B_HOME.address and e.address ~= A_HOME.address, "a home-network pair is held for lists")
    end
    local list = members.list_record(a.stage, a.tag, now())
    for _, pair in ipairs(list and list.pairs or {}) do
        must(pair.kind ~= "home-network" and not pair.address:match("^192%.168%."), "A's list holds " .. pair.address)
    end
end)

------------------------------------------------------------------------------
-- Open questions 2 and 3
------------------------------------------------------------------------------

check("open question 2: kept housemates are in the RAM folder and read back after a restart", function()
    local a, b = behind_one_router()
    a.housemates:start(now())
    must(run_until(function() return kept(a, B_HOME) end, 60), "set-up: A never kept B")
    local text = io.open(housemates.housemates_path(a.ram)):read("*a")
    must(text:match("192%.168%.1%.20\t41000\t203%.0%.113%.5:41000"), "the RAM file is " .. text)
    a = new_node("A", { PUBLIC, A_HOME.address }, A_HOME.port, { restart = a, announce = true, lan = "home",
        private = A_HOME.address, networks = NETWORK })
    must(kept(a, B_HOME) ~= nil, "a restarted A forgot B")
    must(a.housemates:route(B_PUBLIC).address == B_HOME.address, "a restarted A does not route B inside")
end)

check("open question 3: the search goes to the group and the sweep, at each port the room's pairs name", function()
    local a = behind_one_router()
    local sent = a.housemates:search(a.tag, now())
    must(sent == 2 * (1 + 253), sent .. " datagrams, not (group + 253) at two ports")
    local ports, group = {}, 0
    for _, d in ipairs(world.datagrams) do
        ports[d.port] = true
        if d.host == housemates.GROUP then group = group + 1 end
    end
    must(ports[B_PUBLIC.port] and ports[A_HOME.port], "the ports were not B's public port and A's own")
    must(group == 2, group .. " datagrams to the group, not one per port")
end)

------------------------------------------------------------------------------
-- Real datagrams, on loopback only
------------------------------------------------------------------------------

check("the real sender sets time-to-live 1 and sends one datagram over loopback", function()
    local set = {}
    local stand_in = { setoption = function(_, name, value) set[name] = value; return 1 end,
                       sendto = function() return 1 end }
    housemates.udp_send(stand_in)
    must(set["ip-multicast-ttl"] == 1, "the time-to-live was not 1")
    local ok, socket = pcall(require, "socket")
    must(ok, "LuaSocket is not installed")
    local listen = housemates.udp_listen(0, "127.0.0.1", false)
    local _, port = listen:getsockname()
    listen:settimeout(2)
    local send = housemates.udp_send()
    must(send("127.0.0.1", port, "a datagram"), "the datagram was not sent")
    local got = listen:receive()
    listen:close()
    must(got == "a datagram", "loopback gave back " .. tostring(got))
end)

T.finish()
