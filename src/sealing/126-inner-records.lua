-- 126-inner-records.lua — the record inside a frame: a kind, then that
-- kind's fields in a fixed order, on one tab-separated line (issue 201,
-- step 6).
--
-- The shape (decision of 2026-11-05, issue 201 open question 1; the owner
-- may overturn it): the log's own shape, formation C of the sealing note.
-- Fields are separated by tabs and escaped by exactly the log's rule
-- (src/message-log/083-record-codecs.lua): "\\" "\t" "\n" "\r" become
-- \\ \t \n \r, and nothing else is touched.  A `message` on the wire is
-- the log's record without the two fields the reader adds on arrival
-- (`from`, `arrived`), so a received message can be compared with the log
-- byte for byte.  Choosing it is reversible: every frame goes through this
-- table, so another shape replaces encode and decode here and nothing
-- else.
--
-- The table holds the kinds whose fields are settled: the log's three
-- (message, correction, deletion), 202's `ack`, 204's `did-you` and
-- `did-you-answer`, 205's `hello`, 208's `leave`, and 207's
-- `members-digest`, `members-ask` and `members`.  Every other kind 201
-- names (summary, discover, here) gets its row from the issue that
-- defines its fields (209), when that issue is built.  Until then it is an unknown kind, and an unknown kind is an
-- error.  205's hello and 208's leave each carry a `claim` field: the
-- claim id 204's `claims` file keeps (141).
--
-- `hello` (issue 205, decision of 2026-11-05; the owner may overturn it):
-- `claim`, the claim id (32 hex), and `pairs`, every pair the mailbox
-- states, one per line, each "<kind> <address> <port>": kind is one of
-- PAIR_KINDS (212's: public, hostname, ipv6, home-network), the port a
-- whole number 1 to 65535.  The lines are joined with "\n", which the
-- escaping writes as \n, so the record stays one line.  A pair without
-- its port, an unknown kind, or no pairs at all fails to decode: "no
-- default port numbers" (the owner), so nothing is guessed.
--
-- `leave` (issue 208, decision of 2026-11-05; the owner may overturn it):
-- `claim`, `written` (the leaver's own clock, whole seconds: what "newer
-- than the leave" is measured against) and `pairs`, the pairs leaving, in
-- the hello's form.
--
-- 207's three (decision of 2026-11-05; the owner may overturn it): each
-- carries an `id` (32 hex) that the answering `ack` names.
--   members-digest  `digest` (64 hex: SHA-256 of the pairs held, sorted as
--                   "<address> <port>" lines) and `count`: "this is what I
--                   hold"
--   members-ask     the asker's own `digest` and `count`: "send me yours"
--   members         the lister's `digest`, its `pairs` (the hello's form)
--                   and `claims`: one claim id per pair, in order,
--                   separated by single spaces — the claim that pair
--                   answered yes to, so a receiver can call it back (204)
--
-- `discover` and `here` (issue 213, decision of 2026-11-05; the owner may
-- overturn it): the hello's two fields, `claim` and `pairs`, sent as UDP
-- datagrams (a sealed frame without its 4 length bytes).  The pairs are
-- every pair the sending mailbox states, its `home-network` pair (this
-- machine's home address and the mailbox's listening port) among them:
-- the address to answer and call back is read from inside the seal, never
-- from the packet's source.  A `here` answers a `discover`.
--
-- `did-you` and `did-you-answer` (issue 204, decision of 2026-11-05; the
-- owner may overturn it): a `did-you` names the claim id (32 hex) and the
-- pair it is asked at (`address`, `port`); the answer names the claim id
-- back and `yes` or `no`.  142 asks and reads the answer; 133 answers
-- from 141.
--
-- `ack` (issue 202, decision of 2026-11-05; the owner may overturn it):
-- one field, `answers`: the ids the answer covers, each followed by the
-- receiver's word, `filed` or `duplicate`, all separated by single spaces
-- ("q7Kd2 filed x1 duplicate").  Ids hold no spaces, so no escaping is
-- needed.  An empty `answers` is allowed and delivers nothing; there is no
-- bare "ok" (question 10).  132 and 133 read and write the field.
--
-- Errors over fallbacks: an unknown kind, a missing field, an extra field,
-- an unknown escape, or a `written` that is not a whole number is refused,
-- never filled in.

local KINDS = {}

-- Each row: the fields after the kind, in wire order, and how each is
-- checked.  "text" fields hold any bytes; "whole" fields are whole numbers
-- written in decimal.
local LOG_FIELDS = {
    { name = "id", type = "text" },
    { name = "written", type = "whole" },
    { name = "target", type = "text" },
    { name = "text", type = "text" },
}
KINDS.message = LOG_FIELDS
KINDS.correction = LOG_FIELDS
KINDS.deletion = LOG_FIELDS
KINDS.ack = { { name = "answers", type = "text" } }
KINDS["did-you"] = { { name = "claim", type = "text" }, { name = "address", type = "text" },
                     { name = "port", type = "whole" } }
KINDS["did-you-answer"] = { { name = "claim", type = "text" }, { name = "answer", type = "text" } }
KINDS.hello = { { name = "claim", type = "text" }, { name = "pairs", type = "pairs" } }
KINDS["members-digest"] = { { name = "id", type = "text" }, { name = "digest", type = "text" },
                            { name = "count", type = "whole" } }
KINDS["members-ask"] = KINDS["members-digest"]
KINDS.members = { { name = "id", type = "text" }, { name = "digest", type = "text" },
                  { name = "pairs", type = "pairs" }, { name = "claims", type = "text" } }
KINDS.leave = { { name = "claim", type = "text" }, { name = "written", type = "whole" },
                { name = "pairs", type = "pairs" } }
-- 213's datagrams: the hello's form (see the header).
KINDS.discover = KINDS.hello
KINDS.here = KINDS.hello

-- The kinds of pair a `pairs` field may name (212).
local PAIR_KINDS = { public = true, hostname = true, ipv6 = true, ["home-network"] = true }

local ESCAPE = { ["\\"] = "\\\\", ["\t"] = "\\t", ["\n"] = "\\n", ["\r"] = "\\r" }
local UNESCAPE = { ["\\"] = "\\", t = "\t", n = "\n", r = "\r" }

-- {{{ local function escape
local function escape(text)
    return (text:gsub("[\\\t\n\r]", ESCAPE))
end
-- }}}

-- {{{ local function unescape
local function unescape(text)
    return (text:gsub("\\(.?)", function(letter)
        local plain = UNESCAPE[letter]
        -- Path: a known escape — its character.  Anything else — refused.
        if not plain then error("inner record: an unknown escape '\\" .. letter .. "'", 0) end
        return plain
    end))
end
-- }}}

-- {{{ local function split_tabs
-- Every field, empty ones kept.
local function split_tabs(line)
    local fields, start = {}, 1
    while true do
        local tab = line:find("\t", start, true)
        if not tab then
            fields[#fields + 1] = line:sub(start)
            return fields
        end
        fields[#fields + 1] = line:sub(start, tab - 1)
        start = tab + 1
    end
end
-- }}}

-- {{{ local function pairs_text
-- A list of {kind, address, port} → the `pairs` field's text (unescaped).
local function pairs_text(name, list)
    if type(list) ~= "table" or #list == 0 then
        error("inner record: '" .. name .. "' must be a list of at least one pair", 0)
    end
    local lines = {}
    for index, pair in ipairs(list) do
        local where = "inner record: '" .. name .. "' pair " .. index
        if not PAIR_KINDS[pair.kind] then error(where .. " has no known kind: " .. tostring(pair.kind), 0) end
        if type(pair.address) ~= "string" or not pair.address:match("^%S+$") then
            error(where .. " has no address", 0)
        end
        if type(pair.port) ~= "number" or pair.port ~= math.floor(pair.port) or pair.port < 1 or pair.port > 65535 then
            error(where .. " has no port (a port is never guessed): " .. tostring(pair.port), 0)
        end
        lines[#lines + 1] = string.format("%s %s %d", pair.kind, pair.address, pair.port)
    end
    return table.concat(lines, "\n")
end
-- }}}

-- {{{ local function read_pairs
-- The `pairs` field's text (unescaped) → the list; anything else refused.
local function read_pairs(name, text)
    local list = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local kind, address, port = line:match("^(%S+) (%S+) (%d+)$")
        if not kind then
            error("inner record: '" .. name .. "' line is not 'kind address port': " .. line:sub(1, 60), 0)
        end
        if not PAIR_KINDS[kind] then error("inner record: '" .. name .. "' has an unknown kind: " .. kind:sub(1, 20), 0) end
        port = tonumber(port)
        if #line > 300 or port < 1 or port > 65535 then
            error("inner record: '" .. name .. "' port out of range: " .. line:sub(1, 60), 0)
        end
        list[#list + 1] = { kind = kind, address = address, port = port }
    end
    return list
end
-- }}}

-- {{{ local function row_of
local function row_of(kind)
    local row = KINDS[kind]
    if not row then error("inner record: unknown kind '" .. tostring(kind) .. "'", 0) end
    return row
end
-- }}}

-- {{{ local function encode
-- record ({kind = ..., and each of its kind's fields}) → one line, no "\n".
-- A missing field, or one the kind does not have, is an error.
local function encode(record)
    local row = row_of(record.kind)
    local known = { kind = true }
    local parts = { record.kind }
    for _, field in ipairs(row) do
        known[field.name] = true
        local value = record[field.name]
        -- Path: a whole number written in decimal; text escaped.
        if field.type == "whole" then
            if type(value) ~= "number" or value ~= math.floor(value) or value < 0 then
                error("inner record: '" .. field.name .. "' must be a whole number, got " .. tostring(value), 0)
            end
            parts[#parts + 1] = string.format("%d", value)
        elseif field.type == "pairs" then
            parts[#parts + 1] = escape(pairs_text(field.name, value))
        else
            if type(value) ~= "string" then
                error("inner record: '" .. field.name .. "' is missing", 0)
            end
            parts[#parts + 1] = escape(value)
        end
    end
    for name in pairs(record) do
        if not known[name] then error("inner record: '" .. tostring(name) .. "' is not a field of " .. record.kind, 0) end
    end
    return table.concat(parts, "\t")
end
-- }}}

-- {{{ local function decode
-- line (one record, as opened from a frame) → the record table.
local function decode(line)
    local parts = split_tabs(line)
    local row = row_of(parts[1])
    -- Path: exactly the kind's fields — read them.  More or fewer — refused.
    if #parts ~= #row + 1 then
        error("inner record: " .. parts[1] .. " has " .. (#parts - 1) .. " fields, wanted " .. #row, 0)
    end
    local record = { kind = parts[1] }
    for index, field in ipairs(row) do
        local raw = parts[index + 1]
        if field.type == "whole" then
            if not raw:match("^%d+$") or #raw > 15 then
                error("inner record: '" .. field.name .. "' is not a whole number: " .. raw:sub(1, 20), 0)
            end
            record[field.name] = tonumber(raw)
        elseif field.type == "pairs" then
            record[field.name] = read_pairs(field.name, unescape(raw))
        else
            record[field.name] = unescape(raw)
        end
    end
    return record
end
-- }}}

-- {{{ local function kinds
-- The kinds the table knows, sorted.
local function kinds()
    local list = {}
    for kind in pairs(KINDS) do list[#list + 1] = kind end
    table.sort(list)
    return list
end
-- }}}

return {
    encode = encode,
    decode = decode,
    kinds = kinds,
    escape = escape,
    KINDS = KINDS,
    PAIR_KINDS = PAIR_KINDS,
}
