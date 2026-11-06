-- 187-device-server.lua — the home's device port: where its paired phones
-- and browsers connect (issue 302; decision of 2026-11-06, rubric question
-- 24 and 301's decision 22: one device port per home, never a mailbox's).
--
--   luajit src/devices/187-device-server.lua <project> <disk home>
--
-- One small process per home, beside the home starter.  It reads the
-- home's `config` (`devices.port`, `devices.address`,
-- `devices.frame-deadline`, `devices.idle-limit`, `gatherer.ram-root`),
-- the home's `devices`
-- file, and nothing of the disk home else; its own `state` and
-- `running-log` are in `<home RAM folder>/devices/`, and a `stop` file
-- there stops it.
--
-- The `devices` file is rmail's contacts format, one entry per paired
-- device: `<label>.token = "<token>"` and `<label>.own = true` (planning
-- section 6).  An entry without `own = true`, a field that is neither, or
-- a token 123 would refuse stops the server at start-up, naming the
-- entry.  The file must not be readable by anyone but its owner (302's
-- decision 4: every token in it opens the whole home); otherwise the
-- server refuses to start, naming the file and the chmod to run.  The
-- file is read again whenever a connection's first frame arrives, so a
-- device paired or unpaired (303) counts at once; a file that has become
-- unreadable or wrong then refuses every device until it is fixed, and
-- `state` says why.
--
-- A connection:
--   - its first frame is opened under each paired device's key (127's
--     keyring; 123's rule makes the key from the token, so a device frame
--     never opens as a room frame); none opens it — closed, not a byte
--     sent, `refused` counted;
--   - one opens it — the connection belongs to that device: every later
--     frame must open under the same key, or the connection is closed;
--   - each record (186) is handed to its kind's handler, and each reply
--     is sealed under the device's own key;
--   - a frame that does not arrive whole within devices.frame-deadline,
--     a record that does not decode, or a kind the home does not answer:
--     closed.
-- Live (issue 306): once a device has caught up, its connection stays
-- open.  The home lists its RAM folder once a second while any device is
-- live (192's listing: a listing is a hint to re-read) and sends each new
-- or changed file to every live device as a `file` record, each
-- connection keeping its own record of what it has been sent; a removed
-- file reaches a device at its next catch-up (306 decision 3).  After its
-- first frame a connection may be quiet for devices.idle-limit seconds
-- before its next frame starts; longer, and it is closed.  Replies and
-- pushes share one writer per connection, so their frames never mix.
-- Nothing is ever sent in the clear: a connection whose first four bytes
-- are no frame length 124 accepts is closed without an answer (125); the
-- one exception is a browser's WebSocket upgrade (309), below.
-- Each connection is a thread under 162's wait loop, so a stuck one stops
-- nothing.

local DIR = os.getenv("RAO_CHAT_DIR")
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/devices/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local socket = require("socket")
local disk = require("003-disk")
local formats = require("004-rmail-formats")
local tokens = require("007-tokens")
local room_key = require("123-room-key")
local seal = require("124-seal")
local frames = require("125-frames")
local keyring = require("127-keyring")
local wait = require("162-wait-loop")
local records = require("186-device-records")
local mirror = require("192-mirror")
local ram = require("161-ram-folders")

local M = {}

-- For referees only (188): RAO_DEVICES_BROKEN=wrong-key (replies sealed
-- under another key), answer-unknown (an unknown key is answered in the
-- clear), any-key (every frame tried under every key, so a connection
-- does not keep its device).  (193): from-start (a catch-up is sent every
-- message file, whatever the device holds), no-digest (positions only:
-- no index however the digests disagree).  (194): no-dedupe (a typed
-- file sent again is put again, though it was taken).  (195):
-- only-writer (pushes go only to a device that has sent a typed file).
-- (198): answer-404 (a request that is not the upgrade is answered 404).
M.broken = os.getenv("RAO_DEVICES_BROKEN") or ""

local function now() return socket.gettime() end

-- {{{ function M.devices_path
function M.devices_path(home_dir) return home_dir:gsub("/+$", "") .. "/devices" end
-- }}}

-- {{{ local function file_mode
-- path → its permission bits as octal text ("600"), or nil.
local function file_mode(path)
    local listing = io.popen("stat -c %a " .. disk.shell_quote(path) .. " 2>/dev/null")
    local mode = listing:read("*l")
    listing:close()
    return mode
end
-- }}}

-- {{{ function M.read_devices
-- home folder → list of {label, token} sorted by label, the file's text;
-- or nil and why.  No file: no devices.
function M.read_devices(home_dir)
    local path = M.devices_path(home_dir)
    local handle = io.open(path, "rb")
    if not handle then
        if disk.is_file(path) then return nil, path .. " cannot be read" end
        return {}, ""
    end
    local text = handle:read("*a")
    handle:close()
    local mode = file_mode(path)
    -- Path: group or others may read or write it — refused (decision 4).
    if not mode or not mode:match("^[0-7]?[0-7]00$") then
        return nil, path .. " may be read by others (mode " .. tostring(mode)
            .. "); every token in it opens the whole home: chmod 600 " .. path
    end
    local ok, contacts = pcall(formats.parse_contacts, text, path)
    if not ok then return nil, tostring(contacts) end
    local list = {}
    for label, fields in pairs(contacts) do
        for field in pairs(fields) do
            if field ~= "token" and field ~= "own" then
                return nil, path .. ": " .. label .. "." .. field .. " is not a device's field (a device has token and own)"
            end
        end
        if fields.own ~= "true" then
            return nil, path .. ": " .. label .. " has no own = true, so it is not a device"
        end
        local good, why = pcall(tokens.check_token, fields.token)
        if fields.token == nil or not good then
            return nil, path .. ": " .. label .. ".token " .. (fields.token == nil and "is missing" or tostring(why))
        end
        list[#list + 1] = { label = label, token = fields.token }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list, text
end
-- }}}

-- {{{ function M.ring_of
-- list of {label, token} → a keyring and {label = entry} (an entry is a
-- {key, tie} pair 124 seals with).
function M.ring_of(list)
    local items = {}
    for _, device in ipairs(list) do items[#items + 1] = { room = device.label, token = device.token } end
    local ring = keyring.from_tokens(items)
    local by_label = {}
    for _, entry in ipairs(ring.entries) do by_label[entry.room] = entry end
    return ring, by_label
end
-- }}}

-- {{{ function M.catch_up_replies
-- the home's RAM folder, the device's positions (192's read_positions)
-- → the answer to a catch-up (issue 304): a `file` for every `state`,
-- `.tree` and `.room`, and for every message file after the device's
-- position in its room (all of a room it did not list); an `index` for
-- each listed room whose digest over the home's files up to that
-- position is not the device's; then `caught-up`.
M.INDEX_LINES = 4000   -- index lines per record, well under 124's cap
function M.catch_up_replies(home_ram, positions)
    local found, paths = mirror.listing(home_ram)
    local replies = {}
    for _, path in ipairs(paths) do
        local kind, where = mirror.check_path(path)
        local send = true
        if kind == "message" then
            local held = positions[where.room]
            send = not held or M.broken == "from-start" or where.name > held.last
        end
        local content = send and mirror.read_file(home_ram .. "/" .. path)
        if content then replies[#replies + 1] = { kind = "file", path = path, content = content } end
    end
    local rooms = mirror.rooms(home_ram, paths)
    local tags = {}
    for tag in pairs(positions) do tags[#tags + 1] = tag end
    table.sort(tags)
    for _, tag in ipairs(tags) do
        local held, room = positions[tag], rooms[tag]
        local entries = room and mirror.entries(home_ram, room.mailbox, tag, room.names, held.last) or {}
        -- Path: the digests disagree (an edit, a loss, a late message, a
        -- room the home no longer has) — the index; else positions alone.
        if M.broken ~= "no-digest" and mirror.digest(entries) ~= held.digest then
            local first = 1
            repeat
                local lines = {}
                for i = first, math.min(#entries, first + M.INDEX_LINES - 1) do
                    lines[#lines + 1] = entries[i].name .. " " .. entries[i].hash
                end
                replies[#replies + 1] = { kind = "index", room = tag, entries = table.concat(lines, "\n") }
                first = first + M.INDEX_LINES
            until first > #entries
        end
    end
    replies[#replies + 1] = { kind = "caught-up", at = math.floor(now()) }
    return replies, found
end
-- }}}

-- {{{ function M.want_replies
-- the home's RAM folder, a want record → a `file` for each named message
-- file the home holds in that room, then `sent`; or nil and why.
function M.want_replies(home_ram, record)
    local room = mirror.rooms(home_ram)[record.room]
    local replies = {}
    for name in (record.names .. "\n"):gmatch("([^\n]*)\n") do
        if name ~= "" then
            if not mirror.is_message_name(name) then
                return nil, "a want names '" .. name:sub(1, 40) .. "', which is not a message file"
            end
            local path = room and (room.mailbox .. "/inbox/" .. record.room .. "/" .. name)
            local content = path and mirror.read_file(home_ram .. "/" .. path)
            if content then replies[#replies + 1] = { kind = "file", path = path, content = content } end
        end
    end
    replies[#replies + 1] = { kind = "sent", id = record.id }
    return replies
end
-- }}}

-- {{{ function M.typed_replies
-- the server, the device's label, a typed record → its answer (issue
-- 305).  The file is checked as the filer will check it (161's
-- decode_typed, a room of this home with a gatherer's typed/), then put
-- into that gatherer's typed/ with 161's put, under the device's own id
-- as its name (305 decision 3: the same file sent again after a restart
-- has the same name and bytes, so 161's typed_id files it once).  An id
-- this device sent before, in the server's life, is answered typed-ok
-- and not put again (305 decision 2).
M.TYPED_NAME = "^%d%d%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-%x%x%x%x%x%x%x%x$"   -- 161's new_name
function M.typed_replies(server, label, record)
    server.accepted = server.accepted or {}
    local accepted = server.accepted[label] or {}
    server.accepted[label] = accepted
    local function refused(why) return { { kind = "typed-refused", id = record.id, why = why } } end
    if accepted[record.id] and M.broken ~= "no-dedupe" then return { { kind = "typed-ok", id = record.id } } end
    if not record.id:match(M.TYPED_NAME) then
        return refused("the id is not a typed file's name (" .. "<seconds>-<sequence>-<8 hex>)")
    end
    local typed, why = ram.decode_typed(record.content)
    if not typed then return refused(why) end
    local room = mirror.rooms(server.home_ram)[typed.room]
    if not room then return refused("this home has no room " .. typed.room) end
    local queue = server.home_ram .. "/" .. room.mailbox .. "/typed"
    if not disk.is_dir(queue) then return refused("the room's gatherer has no typed/ folder (is it running?)") end
    ram.put(queue, record.id, record.content)
    accepted[record.id] = true
    return { { kind = "typed-ok", id = record.id } }
end
-- }}}

-- {{{ M.handlers
-- kind → function(session, record) → a list of reply records, or nil and
-- why to close the connection.  Later issues add their kinds.
M.handlers = {
    ping = function(_, record)
        return { { kind = "pong", id = record.id, at = math.floor(now()) } }
    end,
    ["catch-up"] = function(session, record)
        local positions, why = mirror.read_positions(record.rooms)
        if not positions then return nil, why end
        local replies, found = M.catch_up_replies(session.server.home_ram, positions)
        M.go_live(session, found)
        return replies
    end,
    want = function(session, record)
        return M.want_replies(session.server.home_ram, record)
    end,
    typed = function(session, record)
        session.wrote = true
        return M.typed_replies(session.server, session.label, record)
    end,
}
-- }}}

-- {{{ function M.send_replies
-- session, records → true, or nil when the connection failed.  One
-- writer at a time per connection (the connection's thread answering,
-- its pusher pushing), so a frame is never cut by another.
function M.send_replies(session, replies)
    while session.writing do
        wait.block(function() return not session.writing end, math.huge)
    end
    session.writing = true
    local reply_pair = session.pair
    if M.broken == "wrong-key" then reply_pair = room_key.key_pair("not this device's token") end
    local sent = true
    for _, reply in ipairs(replies) do
        sent = frames.write_frame(session.conn, seal.seal(reply_pair, records.encode(reply)))
        if not sent then break end
    end
    session.writing = false
    return sent
end
-- }}}

-- {{{ local function await_first_byte
-- conn, seconds → true when a byte came (and is kept for the next
-- read), false when none came in time or the connection closed.
local function await_first_byte(conn, seconds)
    conn.timeout = seconds
    conn.deadline = now() + seconds
    local byte = conn:receive(1)
    if not byte then return false end
    conn.buffer = byte .. conn.buffer
    return true
end
-- }}}

-- {{{ function M.push_round
-- session → the `file` records of what changed since it was last told:
-- every path of the server's latest listing whose stamp is not the one
-- this connection last sent (the file is read again: a listing is a
-- hint to re-read).
function M.push_round(session)
    local server, pushes = session.server, {}
    local paths = {}
    for path in pairs(server.found) do paths[#paths + 1] = path end
    table.sort(paths)
    for _, path in ipairs(paths) do
        local stamp = server.found[path]
        if session.known[path] ~= stamp then
            session.known[path] = stamp
            local content = server.read(path)
            if content then pushes[#pushes + 1] = { kind = "file", path = path, content = content } end
        end
    end
    for path in pairs(session.known) do
        if not server.found[path] then session.known[path] = nil end
    end
    if M.broken == "only-writer" and not session.wrote then return {} end
    return pushes
end
-- }}}

-- {{{ function M.go_live
-- session, the listing its catch-up answered from: from now on the
-- connection is pushed each change (306).  Its pusher waits for each new
-- listing (server.round) and sends what changed, until the connection
-- closes.  Without a loop to run it in (a test calling the handler), the
-- session only remembers what it was sent.
function M.go_live(session, found)
    session.known = {}
    for path, stamp in pairs(found) do session.known[path] = stamp end
    local server = session.server
    if session.pusher or not server.spawn then return end
    session.pusher = true
    server.live = (server.live or 0) + 1
    server.spawn("pusher for " .. tostring(session.label), function()
        local seen = server.round or 0
        while not session.closed do
            wait.block(function() return session.closed or (server.round or 0) ~= seen end, math.huge)
            if session.closed then break end
            seen = server.round
            local pushes = M.push_round(session)
            if #pushes > 0 and not M.send_replies(session, pushes) then
                session.closed = true
                session.conn:close()
            end
        end
        server.live = server.live - 1
    end)
end
-- }}}

-- {{{ The browser's way in (issue 309)
--
-- A browser cannot open a plain TCP connection, so the device port takes
-- one clear-text exchange: an HTTP/1.1 `GET <devices.websocket-path>`
-- asking for a WebSocket (Upgrade: websocket, Connection: Upgrade,
-- Sec-WebSocket-Version: 13, a Sec-WebSocket-Key of 16 bytes), read with
-- a byte cap (HEAD_MOST) and the frame deadline.  The answer is the
-- standard 101 with Sec-WebSocket-Accept and nothing that names the
-- server; any other request is closed with not a byte sent.  After it,
-- each binary WebSocket message holds exactly one 302 frame, and the
-- rest is 302 to 308 unchanged.  Messages from the browser must be
-- masked (RFC 6455); a text message, a fragment, an unmasked message, or
-- one whose 302 frame does not fill it exactly closes the connection.
-- The connection a browser holds is wrapped (M.websocket) so 125's
-- read_frame and write_frame work on it as on a plain one.

local ffi = require("ffi")
for _, declaration in ipairs({
    "unsigned char *SHA1(const unsigned char *data, size_t length, unsigned char *digest);",
    "int EVP_EncodeBlock(unsigned char *t, const unsigned char *f, int n);",
}) do
    local ok, problem = pcall(ffi.cdef, declaration)
    if not ok and not tostring(problem):match("redefine") then error(problem) end
end
local libcrypto = ffi.load("crypto")

M.HEAD_MOST = 4096
M.WEBSOCKET_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

-- {{{ function M.base64
function M.base64(bytes)
    local out = ffi.new("unsigned char[?]", 4 * math.ceil(#bytes / 3) + 1)
    local n = libcrypto.EVP_EncodeBlock(out, bytes, #bytes)
    return ffi.string(out, n)
end
-- }}}

-- {{{ function M.accept_value
-- a Sec-WebSocket-Key → its Sec-WebSocket-Accept (RFC 6455 section 4.2.2).
function M.accept_value(key)
    local digest = ffi.new("unsigned char[20]")
    local text = key .. M.WEBSOCKET_GUID
    libcrypto.SHA1(text, #text, digest)
    return M.base64(ffi.string(digest, 20))
end
-- }}}

-- {{{ function M.read_head
-- conn, what was read already → the request's head up to the blank line
-- (without it), or nil when it is longer than HEAD_MOST or does not come.
function M.read_head(conn, started)
    local head = started
    while #head < M.HEAD_MOST do
        if head:sub(-4) == "\r\n\r\n" then return head:sub(1, -5) end
        local byte = conn:receive(1)
        if not byte then return nil end
        head = head .. byte
    end
    return nil
end
-- }}}

-- {{{ function M.upgrade_answer
-- a request head, the websocket path → the 101 answer, or nil and why.
function M.upgrade_answer(head, path)
    local lines = {}
    for line in (head .. "\r\n"):gmatch("(.-)\r\n") do lines[#lines + 1] = line end
    local target = (lines[1] or ""):match("^GET (%S+) HTTP/1%.1$")
    if not target then return nil, "not a GET of HTTP/1.1" end
    if target ~= path then return nil, "another path" end
    local headers = {}
    for i = 2, #lines do
        local name, value = lines[i]:match("^([%w%-]+):%s*(.-)%s*$")
        if not name then return nil, "a header line that is not one" end
        headers[name:lower()] = value
    end
    if (headers.upgrade or ""):lower() ~= "websocket" then return nil, "no Upgrade: websocket" end
    local upgrade_token = false
    for token in (headers.connection or ""):gmatch("[^,%s]+") do
        if token:lower() == "upgrade" then upgrade_token = true end
    end
    if not upgrade_token then return nil, "no Connection: Upgrade" end
    if headers["sec-websocket-version"] ~= "13" then return nil, "not Sec-WebSocket-Version 13" end
    local key = headers["sec-websocket-key"] or ""
    if not key:match("^[%w%+/]+=*$") or #key ~= 24 then return nil, "no Sec-WebSocket-Key of 16 bytes" end
    return "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        .. "Sec-WebSocket-Accept: " .. M.accept_value(key) .. "\r\n\r\n"
end
-- }}}

-- {{{ M.websocket: a connection that carries one 302 frame per message
local WebSocket = {}
WebSocket.__index = WebSocket

-- conn (a 162 connection or a LuaSocket socket), role ("server": what
-- comes must be masked and what goes is not; "client": the other way)
-- → a connection with receive, send, settimeout and close, as 125 needs.
function M.websocket(conn, role)
    return setmetatable({ conn = conn, sock = conn.sock, raw = conn, role = role, buffer = "", closed = false },
        WebSocket)
end

function WebSocket:settimeout(seconds)
    self.timeout = seconds
    if self.conn.settimeout then self.conn:settimeout(seconds) end
end

-- → one message's payload (a whole 302 frame), or nil and why.
function WebSocket:read_message()
    local conn = self.conn
    -- a 162 connection takes the wait and deadline as fields; a LuaSocket
    -- socket has its own timeout, set through settimeout
    if type(conn) == "table" then
        if self.timeout then conn.timeout = self.timeout end
        if self.deadline then conn.deadline = self.deadline end
    end
    local head, why = frames.receive_exactly(conn, 2)
    if not head then return nil, why end
    local b1, b2 = head:byte(1, 2)
    local fin, opcode = bit.band(b1, 0x80) ~= 0, bit.band(b1, 0x0f)
    local masked, length = bit.band(b2, 0x80) ~= 0, bit.band(b2, 0x7f)
    if bit.band(b1, 0x70) ~= 0 then return nil, "reserved bits set" end
    if masked ~= (self.role == "server") then return nil, masked and "a masked message to a browser" or "an unmasked message" end
    if length == 126 or length == 127 then
        local extra = frames.receive_exactly(conn, length == 126 and 2 or 8)
        if not extra then return nil, "closed" end
        length = 0
        for i = 1, #extra do length = length * 256 + extra:byte(i) end
    end
    if length > seal.CAP + seal.LENGTH_BYTES then return nil, "a message over the cap" end
    local mask = masked and frames.receive_exactly(conn, 4)
    if masked and not mask then return nil, "closed" end
    local payload = length > 0 and frames.receive_exactly(conn, length) or ""
    if not payload then return nil, "closed" end
    if masked then
        local bytes, m = {}, { mask:byte(1, 4) }
        for i = 1, #payload do bytes[i] = string.char(bit.bxor(payload:byte(i), m[(i - 1) % 4 + 1])) end
        payload = table.concat(bytes)
    end
    if opcode == 0x8 then return nil, "closed" end
    -- Path: a binary message, whole — its payload must be exactly one
    -- 302 frame.  Anything else (text, a fragment, a control frame other
    -- than close) is refused (309 decisions 3 and 4).
    if opcode ~= 0x2 or not fin then return nil, "not one whole binary message" end
    if #payload < seal.LENGTH_BYTES or seal.read_uint32_be(payload:sub(1, 4)) ~= #payload - seal.LENGTH_BYTES then
        return nil, "a message that is not exactly one frame"
    end
    return payload
end

function WebSocket:receive(n)
    if #self.buffer == 0 then
        if self.closed then return nil, "closed", "" end
        local payload, why = self:read_message()
        if not payload then
            if why ~= "timeout" then self.closed = true end
            return nil, why == "timeout" and "timeout" or "closed", ""
        end
        self.buffer = payload
    end
    if #self.buffer < n then
        local partial = self.buffer
        self.buffer = ""
        self.closed = true
        return nil, "closed", partial
    end
    local out = self.buffer:sub(1, n)
    self.buffer = self.buffer:sub(n + 1)
    return out
end

-- data, i, j → j, the whole of data:sub(i, j) sent as one message.
function WebSocket:send(data, i, j)
    i, j = i or 1, j or #data
    local payload = data:sub(i, j)
    local head
    if #payload < 126 then head = string.char(0x82, #payload)
    elseif #payload < 65536 then head = string.char(0x82, 126, math.floor(#payload / 256), #payload % 256)
    else
        local bytes, n = {}, #payload
        for k = 8, 1, -1 do bytes[k] = n % 256; n = math.floor(n / 256) end
        head = string.char(0x82, 127, unpack(bytes))
    end
    if self.role == "client" then
        local mask = assert(io.open("/dev/urandom", "rb")):read(4)
        local m, bytes = { mask:byte(1, 4) }, {}
        for k = 1, #payload do bytes[k] = string.char(bit.bxor(payload:byte(k), m[(k - 1) % 4 + 1])) end
        head = head:sub(1, 1) .. string.char(bit.bor(head:byte(2), 0x80)) .. head:sub(3) .. mask
        payload = table.concat(bytes)
    end
    if self.timeout and type(self.conn) == "table" then self.conn.timeout = self.timeout end
    local sent, why = frames.write_frame(self.conn, head .. payload)
    if not sent then return nil, why, i - 1 end
    return j
end

function WebSocket:close()
    self.closed = true
    self.conn:close()
end
-- }}}

-- {{{ function M.websocket_client
-- a connected LuaSocket socket, host, path → the socket wrapped as a
-- browser's WebSocket connection, or nil and why: the reference device
-- speaking as the browser does (309), so the referees and the demo can
-- drive the browser's way in.
function M.websocket_client(sock, host, path)
    local key = M.base64(assert(io.open("/dev/urandom", "rb")):read(16))
    local request = "GET " .. path .. " HTTP/1.1\r\nHost: " .. host .. "\r\nUpgrade: websocket\r\n"
        .. "Connection: Upgrade\r\nSec-WebSocket-Key: " .. key .. "\r\nSec-WebSocket-Version: 13\r\n\r\n"
    if not frames.write_frame(sock, request) then return nil, "closed" end
    local head = M.read_head(sock, "")
    if not head then return nil, "closed" end
    if not head:match("^HTTP/1%.1 101 ") or not head:find("\r\nSec%-WebSocket%-Accept: "
        .. M.accept_value(key):gsub("%p", "%%%0") .. "\r?\n?") then
        return nil, "the upgrade was not answered as the standard says"
    end
    return M.websocket(sock, "client")
end
-- }}}
-- }}}

-- {{{ function M.serve_connection
-- conn (162's), server ({deadline, idle_limit, keys = function() → ring,
-- by_label}, home_ram, spawn, on_refused, on_problem}) → nothing; the
-- connection is closed at the end.
function M.serve_connection(conn, server)
    local session = { conn = conn, server = server }
    local pinned
    -- Path: a browser's upgrade (309) — answered, and the connection
    -- wrapped; anything else in the clear — closed, as 302 says.
    conn.timeout = server.deadline
    conn.deadline = now() + server.deadline
    local start = frames.receive_exactly(conn, 4)
    if not start then conn:close() return end
    if start == "GET " then
        local head = M.read_head(conn, start)
        local answer = head and server.websocket_path and M.upgrade_answer(head, server.websocket_path)
        if not answer then
            if M.broken == "answer-404" then conn:send("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n") end
            conn:close()
            return
        end
        if not frames.write_frame(conn, answer) then conn:close() return end
        conn = M.websocket(conn, "server")
        session.conn = conn
    else
        conn.buffer = start .. conn.buffer
    end
    while true do
        -- Path: the connection has its device — it may be quiet up to the
        -- idle limit before its next frame starts (306).
        if pinned and server.idle_limit and not await_first_byte(conn, server.idle_limit) then break end
        conn.timeout = server.deadline
        conn.deadline = now() + server.deadline
        local frame = frames.read_frame(conn)
        if not frame then break end
        local record
        -- Path: the connection has its device — only that key.  Otherwise
        -- (its first frame, or the any-key broken version) — every key.
        if pinned and M.broken ~= "any-key" then
            record = seal.open(pinned, frame)
            if not record then break end
        else
            local ring, by_label = server.keys()
            local label, opened = keyring.open_frame(ring, frame)
            if not label then
                if server.on_refused then server.on_refused(conn) end
                if M.broken == "answer-unknown" then conn:send("unknown device\n") end
                break
            end
            pinned, record = by_label[label], opened
            session.label, session.pair = label, pinned
        end
        local decoded, why = records.decode(record)
        local handler = decoded and M.handlers[decoded.kind]
        if not handler then
            if server.on_problem then
                server.on_problem(session.label, decoded and ("a " .. decoded.kind .. " is not answered here") or why)
            end
            break
        end
        local replies, refused = handler(session, decoded)
        if not replies then
            if server.on_problem then server.on_problem(session.label, refused) end
            break
        end
        if not M.send_replies(session, replies) then break end
    end
    session.closed = true
    conn:close()
end
-- }}}

-- {{{ local function main
local function main(args)
    local project, home_dir = args[1], args[2]
    if not (project and home_dir) then
        io.stderr:write("usage: luajit 187-device-server.lua <project> <disk home>\n")
        return 2
    end
    local rooms = require("002-room-folders")
    local settings = {}
    local ok, problem = pcall(function()
        local home = rooms.open_home(home_dir)
        settings.port = formats.parse_port(rooms.config_value(home, "devices.port"))
        if not settings.port then error("devices.port must be a whole number 1 to 65535", 0) end
        settings.address = rooms.config_value(home, "devices.address")
        settings.deadline = tonumber(rooms.config_value(home, "devices.frame-deadline"))
        if not settings.deadline or settings.deadline < 1 or settings.deadline % 1 ~= 0 then
            error("devices.frame-deadline must be a whole number of seconds, at least 1", 0)
        end
        settings.idle_limit = tonumber(rooms.config_value(home, "devices.idle-limit"))
        if not settings.idle_limit or settings.idle_limit < 1 or settings.idle_limit % 1 ~= 0 then
            error("devices.idle-limit must be a whole number of seconds, at least 1", 0)
        end
        settings.websocket_path = rooms.config_value(home, "devices.websocket-path")
        if not settings.websocket_path:match("^/[%w%-%._~/]*$") then
            error("devices.websocket-path must be a path starting with /, of letters, digits and - . _ ~ /", 0)
        end
        settings.ram_root = rooms.config_value(home, "gatherer.ram-root")
        for _, mailbox in ipairs(rooms.read_mailboxes(home)) do
            if mailbox.port == settings.port then
                error("devices.port " .. settings.port .. " is a mailbox's port; the device port is the home's own", 0)
            end
        end
    end)
    if not ok then io.stderr:write("device server: " .. tostring(problem) .. "\n") return 1 end

    local list, text_or_why = M.read_devices(home_dir)
    if not list then io.stderr:write("device server: " .. text_or_why .. "\n") return 1 end

    local root, root_note = ram.choose_root(settings.ram_root)
    local folder = ram.home_ram(root, home_dir) .. "/devices"
    os.execute("mkdir -p " .. disk.shell_quote(folder))
    os.remove(folder .. "/stop")
    local state = { started = math.floor(now()), port = settings.port, devices = #list, refused = 0 }
    if root_note then state["problem.ram-root"] = root_note end
    local function log(words) ram.log(folder, now(), words) end
    local function save() ram.write_state(folder, state) end

    -- the keys, rebuilt when the file's text changes
    local held_text = text_or_why
    local ring, by_label = M.ring_of(list)
    local function keys()
        local fresh, text = M.read_devices(home_dir)
        if not fresh then
            if state["problem.devices"] ~= text then log(text) end
            state["problem.devices"] = text
            state.devices = 0
            held_text = nil
            ring, by_label = M.ring_of({})
            save()
        elseif text ~= held_text then
            held_text = text
            ring, by_label = M.ring_of(fresh)
            state["problem.devices"] = nil
            state.devices = #fresh
            log(#fresh .. " devices paired")
            save()
        end
        return ring, by_label
    end

    local listener = settings.address:find(":", 1, true) and socket.tcp6() or socket.tcp4()
    listener:setoption("reuseaddr", true)
    local claimed, claim_problem = listener:bind(settings.address == "any" and "*" or settings.address, settings.port)
    if claimed then claimed, claim_problem = listener:listen(64) end
    if not claimed then
        state["problem.port"] = "cannot listen on " .. settings.address .. " " .. settings.port .. ": " .. tostring(claim_problem)
        save()
        io.stderr:write("device server: " .. state["problem.port"] .. "\n")
        return 1
    end
    listener:settimeout(0)
    save()
    log("listening on " .. settings.address .. " " .. settings.port .. " for " .. #list .. " devices")

    local server = {
        deadline = settings.deadline,
        idle_limit = settings.idle_limit,
        websocket_path = settings.websocket_path,
        keys = keys,
        home_ram = ram.home_ram(root, home_dir),
        on_refused = function()
            state.refused = state.refused + 1
            save()
        end,
        on_problem = function(label, words)
            log((label or "a device") .. ": " .. tostring(words))
        end,
    }
    local stopping = false
    local loop = wait.new(function(name, message) log("thread " .. name .. " failed: " .. tostring(message)) end)
    loop:spawn("listener", function()
        while true do
            wait.block(nil, math.huge, listener, "read")
            while true do
                local client = listener:accept()
                if not client then break end
                local host, port = client:getpeername()
                local conn = wait.wrap(client)
                loop:spawn("device connection " .. tostring(host) .. ":" .. tostring(port),
                    function() M.serve_connection(conn, server) end)
            end
        end
    end)
    server.spawn = function(name, fn) loop:spawn(name, fn) end
    -- the listing live devices are pushed from: once a second while any
    -- device is live (306 decision 1)
    server.round, server.found = 0, {}
    loop:spawn("poll", function()
        while true do
            wait.sleep(1)
            if (server.live or 0) > 0 then
                local cache = {}
                server.found = mirror.listing(server.home_ram)
                server.read = function(path)
                    if cache[path] == nil then cache[path] = mirror.read_file(server.home_ram .. "/" .. path) or false end
                    return cache[path] or nil
                end
                server.round = server.round + 1
            end
        end
    end)
    loop:spawn("stop", function()
        while true do
            if disk.is_file(folder .. "/stop") then stopping = true; return end
            wait.sleep(0.2)
        end
    end)
    loop:run(function() return stopping end)
    listener:close()
    log("stopped")
    return 0
end
-- }}}

if arg and arg[0] and arg[0]:match("187%-device%-server%.lua$") then os.exit(main(arg)) end
return M
