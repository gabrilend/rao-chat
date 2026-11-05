-- 150-public-address.lua — looking up the home's public address from
-- outside, confirming a change with a second operator, and rechecking it
-- while running (issue 212, steps 2 and 3).
--
-- The lookup (open question 6; decision of 2026-11-05, the owner may
-- overturn it): rmail's rule, kept.  Each source is one resolver of one
-- operator, asked over DNS the question that operator answers with the
-- asker's own address (OPERATORS, rmail's table).  A check asks the
-- sources in order until one answers:
--   the stored address                    "same": the fact's confirmed time
--                                         moves on
--   another address                       the sources of OTHER operators are
--                                         asked until one answers: the same
--                                         new address — "moved" (or "first"
--                                         when nothing was stored), written
--                                         and announced; anything else —
--                                         "disagree", nothing changes;
--                                         nobody — "unconfirmed", nothing
--                                         changes
--   nobody at all                         "silence": the stored address
--                                         stands (addresses R6)
-- Two resolvers of one operator agree whether right or wrong, so a second
-- answer from the same operator never confirms (R5).
--
-- The recheck clock (the watcher): a check at start-up, then one at a
-- random point between config address.recheck-earliest and
-- address.recheck-latest seconds later (no defaults), drawn again after
-- every check from the kernel's random source (/dev/urandom; structure
-- R7).  After "silence", "unconfirmed" or "disagree" the next check comes
-- sooner: between a quarter and a half of the earliest (decision of
-- 2026-11-05).  A "moved" calls `on_move(fact)`: 211's starter tells every
-- gatherer, and each calls 134's `Stage:moved` (a fresh hello to every
-- pair).  The same moment is 215b's pull and push (not built).
--
-- The watcher belongs to 211's home starter (not built), which runs it
-- once before it starts the gatherers, so their start-up hellos already
-- state the public address.

local rooms = require("002-room-folders")
local reach = require("149-reach")

local M = {}

-- rmail's sources (its rmail.lua, "public IP lookup"): A records from
-- OpenDNS, TXT in class CHAOS from Cloudflare, TXT from Google.
M.OPERATORS = {
    { operator = "opendns",    name = "myip.opendns.com",        qtype = 1,  qclass = 1, resolver = "208.67.222.222" },
    { operator = "opendns",    name = "myip.opendns.com",        qtype = 1,  qclass = 1, resolver = "208.67.220.220" },
    { operator = "cloudflare", name = "whoami.cloudflare",       qtype = 16, qclass = 3, resolver = "1.1.1.1" },
    { operator = "cloudflare", name = "whoami.cloudflare",       qtype = 16, qclass = 3, resolver = "1.0.0.1" },
    { operator = "google",     name = "o-o.myaddr.l.google.com", qtype = 16, qclass = 1, resolver = "216.239.32.10" },
    { operator = "google",     name = "o-o.myaddr.l.google.com", qtype = 16, qclass = 1, resolver = "216.239.34.10" },
}

-- How long one question waits for its answer, in seconds.
M.ANSWER_WAIT = 2

-- {{{ function M.settings
-- home → earliest, latest (whole seconds, 1 ≤ earliest ≤ latest).
function M.settings(home)
    local function whole(key)
        local text = rooms.config_value(home, key)
        if not text:match("^%d+$") or tonumber(text) < 1 then
            error(key .. " must be a whole number of seconds ≥ 1, got '" .. text .. "'", 0)
        end
        return tonumber(text)
    end
    local earliest, latest = whole("address.recheck-earliest"), whole("address.recheck-latest")
    if earliest > latest then
        error("address.recheck-earliest (" .. earliest .. ") is after address.recheck-latest (" .. latest .. ")", 0)
    end
    return earliest, latest
end
-- }}}

-- {{{ local function be16
local function be16(n) return string.char(math.floor(n / 256) % 256, n % 256) end
local function read16(s, i) return s:byte(i) * 256 + s:byte(i + 1) end
-- }}}

-- {{{ function M.question
-- id (0-65535), name, qtype, qclass → a DNS query asking for recursion.
function M.question(id, name, qtype, qclass)
    local parts = { be16(id), be16(0x0100), be16(1), be16(0), be16(0), be16(0) }
    for label in name:gmatch("[^.]+") do parts[#parts + 1] = string.char(#label) .. label end
    parts[#parts + 1] = "\0" .. be16(qtype) .. be16(qclass)
    return table.concat(parts)
end
-- }}}

-- {{{ local function skip_name
-- The position after a (possibly compressed) name starting at i.
local function skip_name(s, i)
    while true do
        local len = s:byte(i)
        if not len then return nil end
        if len == 0 then return i + 1 end
        if len >= 192 then return i + 2 end
        i = i + 1 + len
    end
end
-- }}}

-- {{{ function M.answer
-- reply, id, qtype → the address it gives, or nil and why.  Only an
-- answer to that question id, with no error, counts; a TXT answer gives
-- its first string that is an IPv4 address.
function M.answer(reply, id, qtype)
    if #reply < 12 then return nil, "too short" end
    if read16(reply, 1) ~= id then return nil, "another question's answer" end
    local flags = read16(reply, 3)
    if flags < 0x8000 then return nil, "not an answer" end
    if flags % 16 ~= 0 then return nil, "error code " .. flags % 16 end
    local questions, answers = read16(reply, 5), read16(reply, 7)
    local i = 13
    for _ = 1, questions do
        i = skip_name(reply, i)
        if not i then return nil, "a broken question" end
        i = i + 4
    end
    for _ = 1, answers do
        i = skip_name(reply, i)
        if not i or i + 9 > #reply then return nil, "a broken answer" end
        local rtype, length = read16(reply, i), read16(reply, i + 8)
        local data = reply:sub(i + 10, i + 9 + length)
        i = i + 10 + length
        if rtype == qtype and qtype == 1 and #data == 4 then
            return string.format("%d.%d.%d.%d", data:byte(1, 4))
        elseif rtype == qtype and qtype == 16 then
            local j = 1
            while j <= #data do
                local n = data:byte(j)
                local text = data:sub(j + 1, j + n)
                if reach.classify(text) and not text:find(":", 1, true) then return text end
                j = j + 1 + n
            end
        end
    end
    return nil, "no address in the answer"
end
-- }}}

-- {{{ function M.ask
-- source (one of OPERATORS, or a test's: `port` optional), seams ({udp,
-- random}) → the address, or nil and why.
function M.ask(source, seams)
    local udp = seams.udp or function() return require("socket").udp() end
    local sock, problem = udp()
    if not sock then return nil, "no socket: " .. tostring(problem) end
    local id = seams.random(0, 65535)
    sock:settimeout(M.ANSWER_WAIT)
    local ok, why = sock:setpeername(source.resolver, source.port or 53)
    if not ok then sock:close(); return nil, "no route: " .. tostring(why) end
    ok, why = sock:send(M.question(id, source.name, source.qtype, source.qclass))
    if not ok then sock:close(); return nil, "sending: " .. tostring(why) end
    local reply, failed = sock:receive()
    sock:close()
    if not reply then return nil, tostring(failed) end
    return M.answer(reply, id, source.qtype)
end
-- }}}

-- {{{ function M.check
-- sources (in the order asked), the stored address (or nil), seams ({ask
-- = function(source) → address | nil, why; defaults to M.ask}) → a result:
-- {outcome, address, operators, asked}.
function M.check(sources, stored, seams)
    local ask = seams.ask or function(source) return M.ask(source, seams) end
    local asked = {}
    local first, first_source = nil, nil
    for _, source in ipairs(sources) do
        local address, why = ask(source)
        asked[#asked + 1] = { source = source, address = address, why = why }
        if address then first, first_source = address, source; break end
    end
    if not first then return { outcome = "silence", address = stored, asked = asked } end
    if first == stored then return { outcome = "same", address = stored, operators = { first_source.operator }, asked = asked } end
    for _, source in ipairs(sources) do
        -- another operator only: two resolvers of one operator agree whether right or wrong
        if source.operator ~= first_source.operator then
            local address, why = ask(source)
            asked[#asked + 1] = { source = source, address = address, why = why }
            if address == first then
                return { outcome = stored and "moved" or "first", address = first,
                         operators = { first_source.operator, source.operator }, asked = asked }
            elseif address then
                return { outcome = "disagree", address = stored, asked = asked,
                         operators = { first_source.operator .. "=" .. first, source.operator .. "=" .. address } }
            end
        end
    end
    return { outcome = "unconfirmed", address = stored, asked = asked }
end
-- }}}

-- {{{ function M.random
-- a, b → a whole number in [a, b] from /dev/urandom.
function M.random(a, b)
    local file = assert(io.open("/dev/urandom", "rb"))
    local bytes = file:read(4)
    file:close()
    local n = ((bytes:byte(1) * 256 + bytes:byte(2)) * 256 + bytes:byte(3)) * 256 + bytes:byte(4)
    return a + n % (b - a + 1)
end
-- }}}

local Watcher = {}
Watcher.__index = Watcher

-- {{{ function M.new_watcher
-- options: {ram_root, sources (default OPERATORS), earliest, latest,
-- on_move(fact, now), seams ({ask, udp, random})} → a watcher.  Nothing is
-- asked until `start`.
function M.new_watcher(options)
    local seams = options.seams or {}
    seams.random = seams.random or M.random
    return setmetatable({ ram_root = options.ram_root, sources = options.sources or M.OPERATORS,
        earliest = options.earliest, latest = options.latest, on_move = options.on_move,
        seams = seams, history = {} }, Watcher)
end
-- }}}

-- {{{ function Watcher:run
-- One check now: the fact file written on an agreed answer, on_move on a
-- confirmed change, and the next check drawn.  → the result.
function Watcher:run(now)
    local fact = reach.read_fact(self.ram_root)
    local result = M.check(self.sources, fact and fact.address, self.seams)
    local outcome = result.outcome
    if outcome == "same" then
        fact.confirmed = math.floor(now)
        reach.write_fact(self.ram_root, fact)
    elseif outcome == "moved" or outcome == "first" then
        local new = { address = result.address, confirmed = math.floor(now), operators = result.operators }
        reach.write_fact(self.ram_root, new)
        if outcome == "moved" and self.on_move then self.on_move(new, now) end
    end
    if outcome == "same" or outcome == "moved" or outcome == "first" then
        self.due = now + self.seams.random(self.earliest, self.latest)
    else
        local quarter = math.max(1, math.floor(self.earliest / 4))
        self.due = now + self.seams.random(quarter, math.max(quarter, math.floor(self.earliest / 2)))
    end
    result.at, result.due = now, self.due
    self.history[#self.history + 1] = result
    return result
end
-- }}}

-- {{{ function Watcher:start
function Watcher:start(now)
    return self:run(now)
end
-- }}}

-- {{{ function Watcher:tick
-- now → the result when a check was due and ran, or nil.
function Watcher:tick(now)
    if self.due and now >= self.due then return self:run(now) end
    return nil
end
-- }}}

return M
