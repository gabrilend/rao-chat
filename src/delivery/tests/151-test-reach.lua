-- 151-test-reach.lua — the referees of issue 212 (where a mailbox can be
-- reached), each run against the real code and, where the issue names
-- one, against a deliberately broken version it must catch.
--
-- Referees 1 and 2 and the move run in 143's simulated world: a port
-- forward is a second listener address leading to the same mailbox, the
-- public address 203.0.113.1 (a documentation address) forwarding to the
-- mailbox's listening port on 10.0.0.1.  Referees 3-5 run 150's watcher
-- against fake operators.  The DNS question and answer are checked over
-- real UDP on the loopback address, against a stand-in resolver in this
-- process: run under the loopback-only wrapper, nothing leaves the
-- machine.
--
-- Run: luajit src/delivery/tests/151-test-reach.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>"; exit status
-- 0 only when nothing failed.

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/delivery/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local rooms = require("002-room-folders")
local disk = require("003-disk")
local recipients = require("041-recipients")
local reach = require("149-reach")
local public = require("150-public-address")

local T = dofile(DIR .. "/src/delivery/tests/143-test-world.lua")(DIR, "reach")
local sim, world, check, must, must_fail, swap = T.sim, T.world, T.check, T.must, T.must_fail, T.swap
local new_node, run_until, TOKEN = T.new_node, T.run_until, T.TOKEN

local INSIDE = "10.0.0.1"
local PUBLIC = "203.0.113.1"
local MOVED = "198.51.100.7"
local B_PAIR = { address = "127.0.0.2", port = 7502 }
local TOKEN2 = "reach test second room"

-- {{{ local function now
local function now() return math.floor(sim.now) end
-- }}}

-- {{{ local function forward
-- The router: `outside` on `address` leads to node's listener on `inside`.
local function forward(node, address, outside, inside)
    world.listeners[address .. " " .. outside] = world.listeners[node.host .. " " .. inside]
end
-- }}}

-- {{{ local function forwarded_home
-- A at 10.0.0.1 listening on 41000 (and 41001 with `two`), its public
-- address 203.0.113.1 forwarding 52000 (and 52001) there; B announcing.
local function forwarded_home(two)
    sim.reset()
    world.reset()
    local outside = { [41000] = 52000, [41001] = 52001 }
    local a = new_node("A", { INSIDE }, 41000, { announce = true, outside = outside, ports = two and { 41001 } or nil })
    reach.write_fact(a.ram, { address = PUBLIC, confirmed = now(), operators = { "x", "y" } })
    forward(a, PUBLIC, 52000, 41000)
    local b = new_node("B", { B_PAIR.address }, B_PAIR.port, { announce = true, ports = two and { 7503 } or nil })
    if two then forward(a, PUBLIC, 52001, 41001) end
    return a, b
end
-- }}}

-- {{{ local function member
local function member(node, tag, address, port) return recipients.is_member(node.home, tag, address, port) end
-- }}}

------------------------------------------------------------------------------
-- 1. The outside port is what is said
------------------------------------------------------------------------------

-- {{{ referee 1
local function referee_outside(broken)
    local function run()
        local a, b = forwarded_home()
        local job = a.stage:hello(a.tag, B_PAIR, now())
        must(run_until(function() return job.done end, 60), "A's hello was never acknowledged: " .. tostring(job.why))
        must(job.pairs[1].kind == "public" and job.pairs[1].address == PUBLIC and job.pairs[1].port == 52000,
            "A's hello stated " .. tostring(job.pairs[1].address) .. " " .. tostring(job.pairs[1].port)
            .. ", not the public address with the outside port")
        must(run_until(function() return member(b, b.tag, PUBLIC, 52000) end, 60),
            "B's call-back to the outside port was never answered")
    end
    if not broken then return run() end
    swap(reach, "outside_port", function(home, mailbox_tag) return rooms.read_mailbox(home, mailbox_tag).port end, run)
end
-- }}}

check("referee 1: A listens on 41000 behind a forward from 52000; its hello says 52000 and B's call-back lands", function()
    referee_outside()
    must_fail(referee_outside, true, "the listening port stated")
end)

------------------------------------------------------------------------------
-- 2. Each mailbox says its own port
------------------------------------------------------------------------------

-- {{{ referee 2
local function referee_each_mailbox(broken)
    local function run()
        local a, b = forwarded_home(true)
        local a2 = rooms.make_room(a.home, { label = "second", token = TOKEN2, kind = "group", parent = "",
            members = {}, filed_under = "", mailbox_port = 41001 })
        local b2 = rooms.make_room(b.home, { label = "second", token = TOKEN2, kind = "group", parent = "",
            members = {}, filed_under = "", mailbox_port = 7503 })
        local first = a.stage:hello(a.tag, B_PAIR, now())
        local second = a.stage:hello(a2, { address = B_PAIR.address, port = 7503 }, now())
        run_until(function() return first.done and second.done end, 60)
        must(first.pairs and second.pairs and first.pairs[1].port == 52000 and second.pairs[1].port == 52001,
            "the two mailboxes' hellos did not state 52000 and 52001")
        must(run_until(function() return member(b, b.tag, PUBLIC, 52000) and member(b, b2, PUBLIC, 52001) end, 60),
            "a call-back did not land on the right mailbox")
        must(not member(b, b2, PUBLIC, 52000) and not member(b, b.tag, PUBLIC, 52001), "a mailbox was added at the other's port")
    end
    if not broken then return run() end
    swap(reach, "outside_port", function(home)
        local first = rooms.read_mailboxes(home)[1]
        return reach.read_outside_ports(home)[first.tag]
    end, run)
end
-- }}}

check("referee 2: two mailboxes forwarded from 52000 and 52001 state their own ports; each call-back lands right", function()
    referee_each_mailbox()
    must_fail(referee_each_mailbox, true, "one home-wide outside port")
end)

------------------------------------------------------------------------------
-- 3-5. The lookup and the recheck clock
------------------------------------------------------------------------------

local X1 = { operator = "x", resolver = "x1" }
local X2 = { operator = "x", resolver = "x2" }
local Y = { operator = "y", resolver = "y1" }

-- {{{ local function fake_watcher
-- A watcher whose operators answer from `answers` (resolver → address or
-- nil), with a fixed draw (the low end) and moves counted.
local function fake_watcher(answers, sources, stored)
    local ram = T.SCRATCH .. "/watcher"
    os.execute("rm -rf '" .. ram .. "' && mkdir -p '" .. ram .. "'")
    if stored then reach.write_fact(ram, { address = stored, confirmed = 1, operators = { "x", "y" } }) end
    local moves = {}
    local w = public.new_watcher({ ram_root = ram, sources = sources or { X1, X2, Y }, earliest = 86400,
        latest = 172800, on_move = function(fact) moves[#moves + 1] = fact.address end,
        seams = { ask = function(source)
            local address = answers[source.resolver]
            if address then return address end
            return nil, "timeout"
        end, random = function(a) return a end } })
    return w, moves, ram
end
-- }}}

-- {{{ referee 3
local function referee_one_lookup(sources)
    local w, moves, ram = fake_watcher({ x1 = "198.51.100.7", x2 = "198.51.100.7", y1 = "203.0.113.1" }, sources, "203.0.113.1")
    local result = w:start(1000)
    must(#moves == 0, "one operator's answer moved the home (" .. result.outcome .. ")")
    must(reach.read_fact(ram).address == "203.0.113.1", "the stored address changed on one operator's word")
    local both, both_moves, both_ram = fake_watcher({ x1 = "198.51.100.7", y1 = "198.51.100.7" }, nil, "203.0.113.1")
    both:start(1000)
    both:run(2000)
    must(#both_moves == 1 and both_moves[1] == "198.51.100.7", "two operators agreeing made " .. #both_moves .. " moves")
    must(reach.read_fact(both_ram).address == "198.51.100.7", "the agreed address was not written")
end
-- }}}

check("referee 3: X says new and Y says old: nothing; both say new: exactly one move", function()
    referee_one_lookup()
    must_fail(referee_one_lookup, { X1, { operator = "x2", resolver = "x2" }, Y },
        "a second resolver of operator X counted as another operator")
end)

check("referee 4: every lookup times out: the stored address stands, nothing moves, the next check is sooner", function()
    local w, moves, ram = fake_watcher({}, nil, "203.0.113.1")
    local result = w:start(1000)
    must(result.outcome == "silence", "silence was read as " .. result.outcome)
    must(#moves == 0 and reach.read_fact(ram).address == "203.0.113.1", "silence changed the stored address")
    must(result.due - 1000 <= 86400 / 2, "after silence the next check is " .. (result.due - 1000) .. " s away, not sooner")
    local fine = fake_watcher({ x1 = "203.0.113.1" }, nil, "203.0.113.1")
    local same = fine:start(1000)
    must(same.outcome == "same" and same.due - 1000 >= 86400, "an answered check was not followed by a full wait")
end)

-- {{{ referee 5
local function referee_rechecks(broken)
    local answers = { x1 = "203.0.113.1", y1 = "203.0.113.1" }
    local w, moves = fake_watcher(answers, nil, "203.0.113.1")
    w.seams.random = public.random
    if broken then setmetatable(w, { __index = setmetatable({ tick = function() end }, { __index = getmetatable(w) }) }) end
    local t = 1000
    w:start(t)
    answers.x1, answers.y1 = "198.51.100.7", "198.51.100.7"
    while t < 1000 + 172800 + 60 and #moves == 0 do
        t = t + 60
        w:tick(t)
    end
    must(#moves == 1, "a change after start-up was not seen within one window")
end
-- }}}

check("referee 5: the public address changes after start-up and is seen within one window", function()
    referee_rechecks()
    must_fail(referee_rechecks, true, "checking at start-up only")
end)

check("the recheck draw is from the kernel's random source and stays in its window", function()
    local seen = {}
    for _ = 1, 50 do
        local n = public.random(86400, 172800)
        must(n >= 86400 and n <= 172800, "a draw outside the window: " .. n)
        seen[n] = true
    end
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    must(count > 40, "50 draws gave only " .. count .. " different waits")
end)

------------------------------------------------------------------------------
-- 6-8. The address table, carrier translation, the missing outside port
------------------------------------------------------------------------------

-- {{{ referee 6
local function referee_table(classify)
    local want = { ["172.15.0.1"] = "public", ["172.32.0.1"] = "public", ["172.16.0.1"] = "private",
        ["172.31.255.254"] = "private", ["169.254.1.1"] = "link-local", ["100.64.0.1"] = "carrier",
        ["100.127.255.255"] = "carrier", ["100.128.0.1"] = "public", ["10.1.2.3"] = "private",
        ["192.168.1.4"] = "private", ["192.169.0.1"] = "public", ["127.0.0.1"] = "loopback" }
    for address, kind in pairs(want) do
        must(classify(address) == kind, address .. " is " .. tostring(classify(address)) .. ", not " .. kind)
    end
    local private = { private = true, carrier = true, ["link-local"] = true }
    must(not private[classify("172.15.0.1")] and private[classify("100.64.0.1")], "the private side is wrong")
end
-- }}}

check("referee 6: the private-range table is exact (172.16/12, not a 172. prefix)", function()
    referee_table(reach.classify)
    must_fail(referee_table, function(address)
        if address:match("^172%.") then return "private" end
        return reach.classify(address)
    end, "a 172. prefix test")
end)

-- {{{ referee 7
local function referee_carrier(broken)
    local function run()
        local a = new_node("C7", { INSIDE }, 41000, { announce = true })
        reach.write_fact(a.ram, { address = "100.64.12.34", confirmed = now(), operators = { "x", "y" } })
        local state = reach.state(a.home, a.ram)
        must(state.reachable == false, "a carrier-translated home is said to be reachable")
        must(table.concat(state.notes, " "):match("carrier%-grade"), "the state does not name carrier-grade translation")
        for _, pair in ipairs(a.stage.seams.own_pairs(a.tag)) do
            must(pair.kind ~= "public", "the carrier-translated address was stated in a hello")
        end
    end
    if not broken then return run() end
    local real = reach.classify
    swap(reach, "classify", function(address)
        if address:match("^100%.") then return "public" end
        return real(address)
    end, run)
end
-- }}}

check("referee 7: a public address in 100.64/10: the state names carrier-grade translation; no hello states it", function()
    sim.reset()
    world.reset()
    referee_carrier()
    must_fail(referee_carrier, true, "classifying 100.64/10 as public")
end)

-- {{{ referee 8
local function referee_no_outside(broken)
    local function run()
        sim.reset()
        world.reset()
        local a = new_node("C8", { INSIDE }, 41000)
        local mailbox = rooms.read_entry(a.home, a.tag).mailbox
        local ok, why = pcall(reach.own_pairs, a.home, a.tag, nil, nil)
        must(not ok, "a mailbox with no outside port stated pairs")
        must(tostring(why):find(mailbox .. ".outside-port = <number>", 1, true)
            and tostring(why):find("outside-ports", 1, true), "the error does not name the line to write: " .. tostring(why))
        must(#reach.check_mailboxes(a.home) == 1, "the starter's check did not report the mailbox")
    end
    if not broken then return run() end
    local real = reach.read_outside_ports
    swap(reach, "read_outside_ports", function(home)
        local ports = real(home)
        for _, mailbox in ipairs(rooms.read_mailboxes(home)) do ports[mailbox.tag] = ports[mailbox.tag] or mailbox.port end
        return ports
    end, run)
end
-- }}}

check("referee 8: a mailbox without an outside port refuses, naming the mailbox and the line to write", function()
    referee_no_outside()
    must_fail(referee_no_outside, true, "using the listening port")
end)

------------------------------------------------------------------------------
-- A confirmed move, the pairs by kind, and the files
------------------------------------------------------------------------------

check("a confirmed move: every pair gets a fresh hello with the new address, added beside the old", function()
    local a, b = forwarded_home()
    recipients.add_member(a.home, a.tag, B_PAIR.address, B_PAIR.port)
    a.stage:start(now())
    must(run_until(function() return member(b, b.tag, PUBLIC, 52000) end, 60), "set-up: B never added A")
    forward(a, MOVED, 52000, 41000)
    local answers = { x1 = MOVED, y1 = MOVED }
    local w = public.new_watcher({ ram_root = a.ram, sources = { X1, Y }, earliest = 100, latest = 200,
        on_move = function(_, at) a.stage:moved(at) end,
        seams = { ask = function(source) return answers[source.resolver] end, random = function(lo) return lo end } })
    local result = w:start(now())
    must(result.outcome == "moved", "the watcher saw " .. result.outcome)
    must(run_until(function() return member(b, b.tag, MOVED, 52000) end, 60), "B never added A's new address")
    must(member(b, b.tag, PUBLIC, 52000), "the new address replaced the old one")
end)

check("the pairs by kind: public and hostname with the outside port; IPv6 and home-network with the listening port", function()
    sim.reset()
    world.reset()
    local a = new_node("K", { INSIDE }, 41000)
    local mailbox = rooms.read_entry(a.home, a.tag).mailbox
    reach.set_outside_port(a.home, mailbox, 52000)
    rooms.set_config(a.home, "address.hostname", "home.example.net")
    local pairs_ = reach.own_pairs(a.home, a.tag, { address = PUBLIC, confirmed = 1, operators = { "x" } },
        { ipv6 = { "2001:db8::5" }, private = { "192.168.1.4" } })
    local by = {}
    for _, p in ipairs(pairs_) do by[p.kind] = p end
    must(by.public and by.public.address == PUBLIC and by.public.port == 52000, "the public pair is wrong")
    must(by.hostname and by.hostname.address == "home.example.net" and by.hostname.port == 52000, "the hostname pair is wrong")
    must(by.ipv6 and by.ipv6.port == 41000, "IPv6 was not stated with the listening port")
    must(by["home-network"] and by["home-network"].port == 41000, "the home-network pair is wrong")
    rooms.set_config(a.home, "address.hostname", "none")
    must(#reach.own_pairs(a.home, a.tag, nil, nil) == 0, "pairs were stated with nothing known")
    must(not pcall(reach.set_outside_port, a.home, mailbox, 0), "port 0 was written")
    must(disk.read_all(reach.outside_ports_path(a.home)):find(mailbox .. ".outside-port = 52000", 1, true),
        "the outside-ports line is not '<tag>.outside-port = <port>'")
end)

check("the kernel's lists: global IPv6 and private IPv4 read from if_inet6 and fib_trie", function()
    local six = T.SCRATCH .. "/if_inet6"
    local f = assert(io.open(six, "w"))
    f:write("20010db8000000000000000000000005 02 40 00 00     eth0\n",
            "fe800000000000000000000000000001 02 40 20 80     eth0\n",
            "00000000000000000000000000000001 01 80 10 80       lo\n",
            "fd000000000000000000000000000009 02 40 00 00     eth0\n")
    f:close()
    local list = reach.read_ipv6_global(six)
    must(#list == 1 and list[1] == "2001:db8:0:0:0:0:0:5", "IPv6: " .. table.concat(list, ","))
    local trie = T.SCRATCH .. "/fib_trie"
    f = assert(io.open(trie, "w"))
    f:write("Main:\n  +-- 0.0.0.0/0 3 0 5\n     |-- 0.0.0.0\n        /0 universe UNICAST\n",
            "     |-- 192.168.1.4\n        /32 host LOCAL\n     |-- 192.168.1.255\n        /32 link BROADCAST\n",
            "     |-- 127.0.0.1\n        /32 host LOCAL\nLocal:\n     |-- 192.168.1.4\n        /32 host LOCAL\n")
    f:close()
    list = reach.read_private_ipv4(trie)
    must(#list == 1 and list[1] == "192.168.1.4", "IPv4: " .. table.concat(list, ","))
end)

check("settings: the recheck window is read strictly", function()
    sim.reset()
    world.reset()
    local a = new_node("S", { INSIDE }, 41000)
    local earliest, latest = public.settings(a.home)
    must(earliest == 86400 and latest == 172800, "the demo's window is not 86400 to 172800")
    rooms.set_config(a.home, "address.recheck-earliest", "200000")
    must(not pcall(public.settings, a.home), "an earliest after the latest was taken")
end)

------------------------------------------------------------------------------
-- The DNS question and answer, over loopback UDP
------------------------------------------------------------------------------

check("DNS: an A answer and a TXT answer give the address; another question's answer counts for nothing", function()
    local socket = require("socket")
    local server = assert(socket.udp())
    assert(server:setsockname("127.0.0.1", 0))
    local _, port = server:getsockname()
    server:settimeout(2)
    -- {{{ local function respond
    local function respond(answer_of)
        local query, host, from = server:receivefrom()
        assert(query, "the stand-in resolver heard nothing: " .. tostring(host))
        local qend = 13
        while query:byte(qend) ~= 0 do qend = qend + 1 + query:byte(qend) end
        local qtype = query:byte(qend + 1) * 256 + query:byte(qend + 2)
        local rdata = answer_of(qtype)
        local reply = query:sub(1, 2) .. "\129\128\0\1\0\1\0\0\0\0" .. query:sub(13, qend + 4)
            .. "\192\12" .. string.char(0, qtype, 0, 1, 0, 0, 0, 60, 0, #rdata) .. rdata
        server:sendto(reply, host, from)
    end
    -- }}}
    local function udp_with(answer_of)
        return function()
            local real = socket.udp()
            return setmetatable({ send = function(_, data)
                local ok, why = real:send(data)
                respond(answer_of)
                return ok, why
            end }, { __index = function(_, k) return function(_, ...) return real[k](real, ...) end end })
        end
    end
    local source = { operator = "t", name = "myip.opendns.com", qtype = 1, qclass = 1, resolver = "127.0.0.1", port = port }
    local a = public.ask(source, { random = public.random, udp = udp_with(function() return "\198\51\100\7" end) })
    must(a == "198.51.100.7", "the A answer read as " .. tostring(a))
    source.qtype = 16
    local txt = public.ask(source, { random = public.random,
        udp = udp_with(function() return "\019edns0-client-subnet\011" .. "203.0.113.9" end) })
    must(txt == "203.0.113.9", "the TXT answer read as " .. tostring(txt))
    must(public.answer(public.question(7, "x.example", 1, 1), 7, 1) == nil, "a question was read as an answer")
    must(public.answer(("\0\8\129\128\0\0\0\0\0\0\0\0"), 7, 1) == nil, "another question's answer counted")
    server:close()
end)

T.finish()
