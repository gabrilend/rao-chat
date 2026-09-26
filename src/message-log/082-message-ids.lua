-- 082-message-ids.lua — makes message ids, and checks that a given id is
-- safe to write into a log.
--
-- Every message gets a name no other message will ever have: 16 random bytes
-- read from the computer's own source of randomness (/dev/urandom), written
-- out as 32 hexadecimal letters, the same shape as a room id.  Because the
-- name is chosen when the message is written and travels with it, a copy of
-- the message that arrives twice carries the same name, and the log can say
-- "I already have this one".  The name is also the message's anchor: a
-- notice or search result can point straight at it.
--
-- Ids that come from elsewhere (another home server) are not
-- required to be 32 hex letters, only to be made of letters, digits, '-' and
-- '_'.  That narrow alphabet is load-bearing: it keeps an id from ever
-- containing a tab or a newline, which is what lets the log find a
-- record's id with a plain text search (see 083-record-codecs.lua,
-- id_marker).  It also kept out ':' and '{', which round 2 needed to tell
-- three record shapes apart; kept narrow so a shape could be added back.

local ids = {}

-- {{{ local function read_random_bytes
local function read_random_bytes(count)
    local source = assert(io.open("/dev/urandom", "rb"))
    local bytes = source:read(count)
    source:close()
    -- A short read from /dev/urandom does not happen on Linux; if it ever
    -- did, the id would be shorter than promised, so it is an error rather
    -- than something to pad.
    if #bytes ~= count then
        error("message-ids: /dev/urandom gave " .. #bytes .. " bytes, wanted " .. count)
    end
    return bytes
end
-- }}}

-- {{{ function ids.new_message_id
-- Gives: string, 32 lower-case hexadecimal characters.
function ids.new_message_id()
    local bytes = read_random_bytes(16)
    return (bytes:gsub(".", function(byte)
        return string.format("%02x", byte:byte())
    end))
end
-- }}}

-- {{{ function ids.check_id
-- Raises an error naming `what` (for example "message id") when `value` is
-- not a usable id.  Used for message ids and correction targets.
function ids.check_id(value, what)
    -- Path: not a string at all — the caller built the message wrongly.
    if type(value) ~= "string" then
        error("message-log: " .. what .. " must be a string, got " .. type(value), 0)
    end
    -- Path: a string with a character outside the id alphabet (or empty) —
    -- refused, because it could break a record's layout or its search marker.
    if not value:match("^[%w%-_]+$") then
        error("message-log: " .. what .. " '" .. value
            .. "' may hold only letters, digits, '-' and '_'", 0)
    end
end
-- }}}

-- {{{ function ids.check_from
-- `from` is where a message arrived from: "me" for your own, or an address
-- written "<host> <port>" — one space between them, the port a whole number
-- 1-65535 with no leading zero.  (There is no default port in rao-chat, so
-- an address is always a pair; planning document section 2.)  The host may
-- be an IP address (v4 or v6), a hostname or a .onion name; it is not
-- looked up or checked beyond holding no whitespace, because it proves
-- nothing about who wrote the message and is kept only as a note of where
-- the copy came from.  No whitespace in the host is what keeps the pair
-- splittable on its one space and keeps tsv records on one line.
function ids.check_from(value)
    -- Path: not a string — caller error.
    if type(value) ~= "string" then
        error("message-log: from must be a string, got " .. type(value), 0)
    end
    -- Path: "me" — your own message; accepted.
    if value == "me" then
        return
    end
    local host, port = value:match("^(%S+) ([1-9]%d*)$")
    -- Path: "<host> <port>" with a port in range — accepted.  Anything else
    -- (empty, no port, two spaces, a tab, port 0 or above 65535) — refused.
    if not host or tonumber(port) > 65535 then
        error("message-log: from '" .. value .. "' is neither \"me\" nor \"<host> <port>\" "
            .. "(one space, port 1-65535)", 0)
    end
end
-- }}}

-- {{{ function ids.check_time
-- Times are whole seconds since 1970 (integer).
function ids.check_time(value, what)
    -- Path: a number with no fraction — accepted.  Anything else — refused.
    if type(value) ~= "number" or value ~= math.floor(value) or value < 0 then
        error("message-log: " .. what .. " must be a whole number of seconds since 1970, got "
            .. tostring(value), 0)
    end
end
-- }}}

return ids
