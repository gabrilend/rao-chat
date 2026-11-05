-- 154-housemates.lua — finding housemates on the home network: homes
-- behind the same router, which reach each other by their home-network
-- addresses because many routers cannot loop a connection back in through
-- the public address (issue 213).
--
-- When (decision of 2026-11-05; the owner may overturn it): a room is
-- searched only when one of its members is at this home's own public
-- address (212's fact), or when a connection in that room came from an
-- address on this machine's own network.  A room with neither sends
-- nothing (referee 3).  `start` searches every such room once a run;
-- `moved` searches again after 212 confirms a new public address.
--
-- What is sent: a `discover` (126), sealed with the room's key, as one UDP
-- datagram (the sealed frame without its 4 length bytes) to the multicast
-- group GROUP with time-to-live 1 and to every address of each of this
-- machine's own home networks (the sweep), at each port in `ports`.  Its
-- body is a claim (141, kind `discover`) and every pair this mailbox
-- states, its `home-network` pair among them: this machine's home address
-- and the mailbox's listening port.
--
-- Receiving a discover or a `here` (`receive`): the frame is opened with
-- the listening port's keyring, and the pair to answer and call back is
-- read from inside the seal (`body_pair`), never from the packet's source,
-- which a router may have rewritten (R11, referee 1).  A discover is
-- answered with a `here` to that pair; either is a claim, called back
-- (204) like any other.  Only when that call-back is answered yes is the
-- pair kept (`keep`, through 142's `discover` action): in memory and in
-- the RAM folder's `housemates` file, never as a room member, and never
-- in a members list (207 lists members only).  A body naming an address
-- that is not on this machine's own network is not called back.
--
-- Learning from connections (`from_connection`, R2): a connection from a
-- private address is a housemate's only when the address is on one of
-- this machine's own networks, by the network's real mask (from
-- /proc/net/route).  Then the room is searched.  A private address on
-- another network is a router relaying: noted once in the running log
-- (seams.log) and kept nowhere (referee 2).
--
-- Routing: `route(pair)` gives the home-network pair of a housemate whose
-- stated public pair is `pair`, so the sender connects inside the house;
-- `is_housemate(pair)` is 145's seam (home-network pairs go only to a
-- housemate).

local socket_ok, socket = pcall(require, "socket")
local seal = require("124-seal")
local records = require("126-inner-records")
local room_key = require("123-room-key")
local keyring = require("127-keyring")
local rooms = require("002-room-folders")
local disk = require("003-disk")
local recipients = require("041-recipients")
local claims = require("141-claims")
local call_back = require("142-call-back")
local reach = require("149-reach")

local M = {}

-- The multicast group (decision of 2026-11-05): rmail uses 239.192.82.77;
-- rao-chat takes the next address, so the two programs' daemons on one
-- network do not wake each other.  Organisation-local scope (239.192/14).
M.GROUP = "239.192.82.78"
M.TTL = 1
-- The sweep covers at most this many addresses per network: a network
-- wider than /24 is swept on the /24 around this machine's address.
M.SWEEP_BITS = 24

-- {{{ function M.to_number / M.to_address
function M.to_number(address)
    local a, b, c, d = tostring(address):match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    if a > 255 or b > 255 or c > 255 or d > 255 then return nil end
    return ((a * 256 + b) * 256 + c) * 256 + d
end

function M.to_address(n)
    return string.format("%d.%d.%d.%d", math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
        math.floor(n / 256) % 256, n % 256)
end
-- }}}

-- {{{ local function block
-- A number and a prefix length → the network's first number and size.
local function block(n, bits)
    local size = 2 ^ (32 - bits)
    return n - n % size, size
end
-- }}}

-- {{{ function M.read_networks
-- The machine's directly attached private IPv4 networks, from the kernel's
-- routing table (default /proc/net/route: hex, little-endian; a route
-- with the gateway flag 0x2 is not attached).  → list of {network =
-- address, bits, iface}.
function M.read_networks(path)
    path = path or "/proc/net/route"
    local list = {}
    if not disk.is_file(path) then return list end
    for line in disk.read_all(path):gmatch("[^\n]+") do
        local iface, destination, flags, mask = line:match("^(%S+)%s+(%x+)%s+%x+%s+(%x+)%s+%S+%s+%S+%s+%S+%s+(%x+)")
        if iface and #destination == 8 and #mask == 8 then
            local function swap(hex)
                local n = 0
                for i = 7, 1, -2 do n = n * 256 + tonumber(hex:sub(i, i + 1), 16) end
                return n
            end
            local dest, bitmask, flag = swap(destination), swap(mask), tonumber(flags, 16)
            local bits, m = 0, bitmask
            while m >= 2 ^ 31 do bits, m = bits + 1, (m - 2 ^ 31) * 2 end
            local address = M.to_address(dest)
            if bits > 0 and math.floor(flag / 2) % 2 == 0 and reach.classify(address) == "private" then
                list[#list + 1] = { network = address, bits = bits, iface = iface }
            end
        end
    end
    return list
end
-- }}}

-- {{{ function M.on_own_network
-- address, networks (read_networks's) → the network it is on, or nil.
-- The real mask, never "the first three numbers" (open question 1).
function M.on_own_network(address, networks)
    local n = M.to_number(address)
    if not n or reach.classify(address) ~= "private" then return nil end
    for _, net in ipairs(networks or {}) do
        local first = block(M.to_number(net.network), net.bits)
        local start = block(n, net.bits)
        if start == first then return net end
    end
    return nil
end
-- }}}

-- {{{ function M.sweep_addresses
-- networks, own addresses (list) → every host address of each own network,
-- less the network and broadcast addresses and this machine's own; a
-- network wider than SWEEP_BITS is swept on the block around an own
-- address.  Sorted by number.
function M.sweep_addresses(networks, own)
    local mine, seen, list = {}, {}, {}
    for _, address in ipairs(own or {}) do mine[address] = true end
    for _, net in ipairs(networks or {}) do
        local starts = {}
        if net.bits >= M.SWEEP_BITS then
            starts[#starts + 1] = { block(M.to_number(net.network), net.bits) }
        else
            for _, address in ipairs(own or {}) do
                if M.on_own_network(address, { net }) then
                    starts[#starts + 1] = { block(M.to_number(address), M.SWEEP_BITS) }
                end
            end
        end
        for _, s in ipairs(starts) do
            local first, size = s[1], s[2]
            for n = first + 1, first + size - 2 do
                local address = M.to_address(n)
                if not mine[address] and not seen[address] then
                    seen[address] = true
                    list[#list + 1] = n
                end
            end
        end
    end
    table.sort(list)
    for i, n in ipairs(list) do list[i] = M.to_address(n) end
    return list
end
-- }}}

-- {{{ function M.body_pair
-- A decoded discover or here, and the packet's source → the pair to answer
-- and call back: the body's home-network pair, never the source (R11).
function M.body_pair(record, source)
    for _, pair in ipairs(record.pairs) do
        if pair.kind == "home-network" then return { address = pair.address, port = pair.port } end
    end
    return nil
end
-- }}}

-- {{{ function M.housemates_path
function M.housemates_path(ram_root)
    return ram_root .. "/housemates"
end
-- }}}

-- {{{ function M.read_kept
-- ram_root → list of {tag, home = {address, port}, stated = {pairs}}.  The
-- file: "tag TAB home address TAB home port TAB stated pairs", the stated
-- pairs as "address:port" separated by spaces.
function M.read_kept(ram_root)
    local list = {}
    local path = M.housemates_path(ram_root)
    if not disk.is_file(path) then return list end
    local number = 0
    for line in disk.read_all(path):gmatch("[^\n]+") do
        number = number + 1
        local tag, address, port, stated = line:match("^(%S+)\t(%S+)\t(%d+)\t(.*)$")
        if not tag then error("housemates: line " .. number .. " of " .. path .. " is not 'tag TAB address TAB port TAB pairs'", 0) end
        local pairs_ = {}
        for a, p in stated:gmatch("(%S+):(%d+)") do pairs_[#pairs_ + 1] = { address = a, port = tonumber(p) } end
        list[#list + 1] = { tag = tag, home = { address = address, port = tonumber(port) }, stated = pairs_ }
    end
    return list
end
-- }}}

local Housemates = {}
Housemates.__index = Housemates
M.Housemates = Housemates

-- {{{ function M.new
-- options: home, stage (134's), ram_root, networks() → read_networks's
-- list, own_pairs(tag) (the stage's seam), fact() → 212's fact or nil,
-- send(host, port, bytes) (one datagram), log(words) (the running log),
-- listening(tag) → the room's mailbox's listening port.  What a earlier
-- run kept in the RAM folder is read back (open question 2).
function M.new(options)
    local self = setmetatable({ home = options.home, stage = options.stage, ram_root = options.ram_root,
        networks = options.networks, own_pairs = options.own_pairs, fact = options.fact, send = options.send,
        log = options.log or function() end, listening = options.listening, found = {}, seen = {},
        searched = {}, relays = {}, sent = 0 }, Housemates)
    if self.ram_root then
        for _, e in ipairs(M.read_kept(self.ram_root)) do
            self.found[e.tag .. " " .. e.home.address .. " " .. e.home.port] = e
        end
    end
    return self
end
-- }}}

-- {{{ function Housemates:needs_search
-- tag → why the room is searched ("public address", "connection"), or nil.
function Housemates:needs_search(tag)
    local fact = self.fact()
    if fact then
        for _, member in ipairs(recipients.members(self.home, tag)) do
            if member.address == fact.address then return "public address" end
        end
    end
    if self.seen[tag] then return "connection" end
    return nil
end
-- }}}

-- {{{ function Housemates:ports
-- tag → the ports a search goes to (open question 3): every port named
-- by a member at this home's public address, and this mailbox's own
-- listening port (a housemate on the same defaults), sorted.
function Housemates:ports(tag)
    local set, list = {}, {}
    local fact = self.fact()
    for _, member in ipairs(recipients.members(self.home, tag)) do
        if fact and member.address == fact.address then set[member.port] = true end
    end
    set[self.listening(tag)] = true
    for port in pairs(set) do list[#list + 1] = port end
    table.sort(list)
    return list
end
-- }}}

-- {{{ local function datagram
-- home, tag, record → the sealed datagram (the frame less its length).
local function datagram(home, tag, record)
    local keys = room_key.key_pair(rooms.read_entry(home, tag).token)
    return seal.seal(keys, records.encode(record)):sub(5)
end
-- }}}

-- {{{ local function own_body
-- The claim and pairs a discover or here carries: every pair this mailbox
-- states, under one new `discover` claim.  nil when it states no
-- home-network pair (nothing to find it by).
local function own_body(self, tag, kind, now)
    local stated = self.own_pairs(tag)
    local home_pair = nil
    for _, pair in ipairs(stated) do if pair.kind == "home-network" then home_pair = pair end end
    if not home_pair then return nil end
    local claim = claims.make_for(self.home, tag, "discover", stated, math.floor(now))
    return { kind = kind, claim = claim, pairs = stated }
end
-- }}}

-- {{{ function Housemates:search
-- tag, now → the datagrams sent (0 when the room needs no search, or this
-- mailbox has no home-network pair).
function Housemates:search(tag, now)
    if not self:needs_search(tag) then return 0 end
    local body = own_body(self, tag, "discover", now)
    if not body then return 0 end
    local bytes = datagram(self.home, tag, body)
    local own = {}
    for _, pair in ipairs(body.pairs) do if pair.kind == "home-network" then own[#own + 1] = pair.address end end
    local sweep = M.sweep_addresses(self.networks(), own)
    local count = 0
    for _, port in ipairs(self:ports(tag)) do
        self.send(M.GROUP, port, bytes)
        count = count + 1
        for _, address in ipairs(sweep) do
            self.send(address, port, bytes)
            count = count + 1
        end
    end
    self.searched[tag] = true
    self.sent = self.sent + count
    return count
end
-- }}}

-- {{{ function Housemates:start
-- Every room that needs it is searched once.
function Housemates:start(now)
    for _, tag in ipairs(rooms.list_rooms(self.home)) do self:search(tag, now) end
end
-- }}}

-- {{{ function Housemates:moved
-- 212 confirmed a new public address: every room is searched again.
function Housemates:moved(now)
    self:start(now)
end
-- }}}

-- {{{ function Housemates:receive
-- One datagram: bytes, the packet's source {host, port}, the port it
-- arrived on, now → what was done: "answered", "heard", or nil and why.
-- Nothing that does not open is logged: other programs use multicast too.
function Housemates:receive(bytes, source, port, now)
    local ring = keyring.for_port(rooms, self.home, port)
    local tag, line = keyring.open_frame(ring, bytes, 1)
    if not tag then return nil, "not sealed with a key of this port" end
    local ok, record = pcall(records.decode, line)
    if not ok or (record.kind ~= "discover" and record.kind ~= "here") then return nil, "not a discover or here" end
    local pair = M.body_pair(record, source)
    if not pair then return nil, "no home-network pair inside" end
    -- this mailbox's own discover, come back through the multicast group
    for _, mine in ipairs(self.own_pairs(tag)) do
        if mine.address == pair.address and mine.port == pair.port then return nil, "our own" end
    end
    if not M.on_own_network(pair.address, self.networks()) then return nil, "not on this machine's network" end
    local check, made = call_back.heard(self.stage, tag, { kind = "discover", id = record.claim,
        address = pair.address, port = pair.port }, source, now)
    if made then
        check.housemates = self
        check.stated = {}
        for _, p in ipairs(record.pairs) do
            if p.kind ~= "home-network" then check.stated[#check.stated + 1] = { address = p.address, port = p.port } end
        end
    end
    if record.kind == "discover" then
        local body = own_body(self, tag, "here", now)
        if body then
            self.send(pair.address, pair.port, datagram(self.home, tag, body))
            self.sent = self.sent + 1
        end
        return "answered", check
    end
    return "heard", check
end
-- }}}

-- {{{ local function write_kept
local function write_kept(self)
    if not self.ram_root then return end
    local keys = {}
    for k in pairs(self.found) do keys[#keys + 1] = k end
    table.sort(keys)
    local lines = {}
    for _, k in ipairs(keys) do
        local e = self.found[k]
        local stated = {}
        for _, p in ipairs(e.stated) do stated[#stated + 1] = p.address .. ":" .. p.port end
        lines[#lines + 1] = string.format("%s\t%s\t%d\t%s\n", e.tag, e.home.address, e.home.port, table.concat(stated, " "))
    end
    os.execute("mkdir -p '" .. self.ram_root .. "'")
    disk.write_atomic(M.housemates_path(self.ram_root), table.concat(lines))
end
-- }}}

-- {{{ function Housemates:keep
-- 142's `discover` action: the call-back said yes → kept.  → "kept".
function Housemates:keep(tag, check, now)
    local entry = { tag = tag, home = { address = check.pair.address, port = check.pair.port },
                    stated = check.stated or {}, claim = check.claim }
    self.found[tag .. " " .. entry.home.address .. " " .. entry.home.port] = entry
    write_kept(self)
    return "kept"
end
-- }}}

-- {{{ function Housemates:list
-- tag (nil: every room) → the kept housemates, sorted.
function Housemates:list(tag)
    local keys, list = {}, {}
    for k, e in pairs(self.found) do if tag == nil or e.tag == tag then keys[#keys + 1] = k end end
    table.sort(keys)
    for _, k in ipairs(keys) do list[#list + 1] = self.found[k] end
    return list
end
-- }}}

-- {{{ function Housemates:is_housemate
-- pair → true when it is a kept housemate's home-network pair or one of
-- the pairs it stated (145's seam).
function Housemates:is_housemate(pair)
    for _, e in pairs(self.found) do
        if e.home.address == pair.address and e.home.port == pair.port then return true end
        for _, p in ipairs(e.stated) do
            if p.address == pair.address and p.port == pair.port then return true end
        end
    end
    return false
end
-- }}}

-- {{{ function Housemates:route
-- pair → where to connect: a kept housemate's home-network pair when the
-- pair is one it stated, else the pair itself.
function Housemates:route(pair)
    for _, e in pairs(self.found) do
        for _, p in ipairs(e.stated) do
            if p.address == pair.address and p.port == pair.port then return e.home end
        end
    end
    return pair
end
-- }}}

-- {{{ function Housemates:from_connection
-- tag, peer ({host, port}), now → "outside", "housemate" (searched, if not
-- yet) or "relay" (logged once, kept nowhere).
function Housemates:from_connection(tag, peer, now)
    if reach.classify(peer.host) ~= "private" then return "outside" end
    if M.on_own_network(peer.host, self.networks()) then
        self.seen[tag] = true
        if not self.searched[tag] then self:search(tag, now) end
        return "housemate"
    end
    if not self.relays[peer.host] then
        self.relays[peer.host] = true
        self.log("a connection from " .. peer.host .. ", a private address on no network of this machine: "
            .. "a router relaying, not a housemate; not kept")
    end
    return "relay"
end
-- }}}

-- {{{ function M.udp_send
-- The real `send`: one datagram over LuaSocket.  To the group, the
-- time-to-live is TTL and the sender does not hear its own copy.  A
-- socket may be given (a test's stand-in).
function M.udp_send(udp)
    if not udp then
        if not socket_ok then error("housemates: LuaSocket is needed to send datagrams", 2) end
        -- udp4: an unbound udp() has no family yet, and refuses options
        udp = assert(socket.udp4())
    end
    assert(udp:setoption("ip-multicast-ttl", M.TTL))
    pcall(udp.setoption, udp, "ip-multicast-loop", false)
    return function(host, port, bytes)
        return udp:sendto(bytes, host, port)
    end
end
-- }}}

-- {{{ function M.udp_listen
-- port, address to bind (default "*") → a LuaSocket UDP socket that hears
-- datagrams on that port, joined to GROUP when join is true.  211's
-- gatherer reads it and hands each datagram to `receive`.
function M.udp_listen(port, address, join)
    if not socket_ok then error("housemates: LuaSocket is needed to hear datagrams", 2) end
    local udp = assert(socket.udp4())
    assert(udp:setoption("reuseaddr", true))
    assert(udp:setsockname(address or "*", port))
    if join then assert(udp:setoption("ip-add-membership", { multiaddr = M.GROUP, interface = "0.0.0.0" })) end
    return udp
end
-- }}}

return M
