-- 190-device.lua — the reference device: what a phone or a browser does,
-- written as a small Lua program the referees can drive (issue 303; the
-- Android app and the web page follow it, as they follow 183).
--
--   luajit src/devices/190-device.lua <device folder> test [--public]
--   luajit src/devices/190-device.lua <device folder> catch-up
--   luajit src/devices/190-device.lua <device folder> send
--   luajit src/devices/190-device.lua <device folder> live [--for <seconds>]
--   luajit src/devices/190-device.lua <device folder> check-in --for <seconds>
--
-- The device's settings are `<device folder>/config`, "name = value"
-- lines, the lines 189's `add` prints plus the device's own:
--
--   port          the home's device port
--   home-network  the home's address on the home network, or "unknown"
--   public        the home's public address, or "unknown"
--   token         the device's own token, exactly as the home holds it
--   wait          whole or part seconds to wait for a connection, and
--                 again for an answer
--   quick-wait    whole or part seconds to wait for a connection to the
--                 home-network address (307), before the public one
--
-- `test` connects to the home-network address (`--public`: the public
-- one), sends a sealed `ping`, and says exactly what happened (rmail's
-- connection test, planning section 6):
--
--   answered in N ms by A P                     (exit 0)
--   nothing listens at A P (refused)            (exit 1, and below)
--   A cannot be reached: <why>                  no route, or no answer to
--                                               connect within the wait
--   A P closed the connection without a word:   the token is not one this
--     the token is not one this home knows      home knows
--   A P said nothing within W s: ...            not a device port, or a
--                                               home that is stuck
--   A P answered with something that is not a frame, or under another
--     key
--
-- `catch-up`, `send` and `live` reach the home as rmail's phone does
-- (issue 307): the home-network address with quick-wait, then the
-- public one with wait; each must answer a sealed ping before it is
-- used, and one that connects but does not answer stops the attempt,
-- said, rather than being passed over.  They print which address it was.
--
-- `catch-up` (issue 304) keeps a mirror of the home's RAM folder in
-- 301's exact layout under `<device folder>/mirror`, so the reference
-- viewer (183) reads it unchanged.  It sends `catch-up` with one line per
-- room it holds (192: the last message file's name and a digest of what
-- it holds), writes every `file` the home sends after checking its path
-- (192's check_path: a 32-hex mailbox and room, 301's names, nothing
-- else; a refused path is said and nothing is written), then for each
-- room the home sent an `index` of — the digests disagreed: an edit, a
-- loss, a late message — drops what the index does not list and asks
-- with `want` for what it holds otherwise.  Room folders that no `.tree`
-- of their mailbox names are removed.  It prints how many files came and
-- how many changed.  Every file is written under a temporary name and
-- renamed (161's put), so a viewer on the mirror never sees half a file.
--
-- `send` (issue 305): the person writes into the mirror exactly as on the
-- home machine (183's `write`, pointed at the mirror, drops a file into
-- `<mailbox>/typed/`); each typed file goes to the home as `typed`, its
-- name the id, the oldest first, and is removed only when the home
-- answers `typed-ok`.  `typed-refused` leaves it, with the reason in
-- `<name>.refused` beside it; such a file is not sent again until the
-- person removes the reason (305 decision 4).
--
-- `live` (issue 306): a catch-up, then the connection stays open: what
-- the home pushes is written into the mirror, what the person types is
-- sent at once, and a `ping` goes when this device has sent nothing for
-- `keep-alive` seconds (a config line `live` needs).  `--for` ends it
-- after that many seconds.
--
-- `check-in` (issue 308): the locked screen's rule, with no connection
-- kept: a wait of `check-in` seconds (a config line, above 5; the
-- planning document's 30) plus a card from M.deck, then one catch-up,
-- again and again for `--for` seconds.
--
-- The project folder is found from this file's own place (or
-- RAO_CHAT_DIR), as 183 does.

local DIR = os.getenv("RAO_CHAT_DIR")
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/devices/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local socket = require("socket")
local formats = require("004-rmail-formats")
local tokens = require("007-tokens")
local room_key = require("123-room-key")
local seal = require("124-seal")
local frames = require("125-frames")
local records = require("186-device-records")
local mirror = require("192-mirror")
local disk = require("003-disk")
local ram = require("161-ram-folders")

local M = {}

-- For referees only (191): RAO_DEVICE_BROKEN=one-message (every failure
-- is told the same way).  (196): fall-through (an address that answered
-- but not to the ping is passed over for the next).  (193): no-path-check (a path from the home is
-- written into the mirror unchecked).  (194): drop-refused (a typed file
-- the home refused is removed anyway).
M.broken = os.getenv("RAO_DEVICE_BROKEN") or ""

-- {{{ function M.config_values
-- device folder → every "name = value" of its config (none: {}).
function M.config_values(folder)
    local text = mirror.read_file(folder .. "/config")
    local ok, values = pcall(formats.parse_config, text or "", folder .. "/config")
    return ok and values or {}
end
-- }}}

-- {{{ function M.read_config
-- (A config may also hold `websocket-path`: then the device reaches its
-- home as a browser does, through 309's upgrade.)
-- device folder → the settings, or nil and why.
function M.read_config(folder)
    local handle = io.open(folder .. "/config", "rb")
    if not handle then return nil, folder .. "/config cannot be read" end
    local text = handle:read("*a")
    handle:close()
    local ok, values = pcall(formats.parse_config, text, folder .. "/config")
    if not ok then return nil, tostring(values) end
    local config = {}
    for _, name in ipairs({ "port", "home-network", "public", "token", "wait", "quick-wait" }) do
        if values[name] == nil then return nil, folder .. "/config has no " .. name .. " line" end
        config[name] = values[name]
    end
    config.port = formats.parse_port(config.port)
    if not config.port then return nil, "port must be a whole number 1 to 65535" end
    config.wait = tonumber(config.wait)
    if not config.wait or config.wait <= 0 then return nil, "wait must be a number of seconds above 0" end
    config["quick-wait"] = tonumber(config["quick-wait"])
    if not config["quick-wait"] or config["quick-wait"] <= 0 then
        return nil, "quick-wait must be a number of seconds above 0"
    end
    local good, why = pcall(tokens.check_token, config.token)
    if not good then return nil, "token: " .. tostring(why) end
    config["websocket-path"] = values["websocket-path"]
    return config
end
-- }}}

-- {{{ local function new_id
local function new_id()
    local source = assert(io.open("/dev/urandom", "rb"))
    local bytes = source:read(8)
    source:close()
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
-- }}}

-- {{{ function M.connect
-- config, address, seconds to connect (nil: wait) → a connected socket,
-- or nil and the words that say what failed (nothing listens, cannot be
-- reached).
function M.connect(config, address, seconds)
    local where = address .. " " .. config.port
    if address == "unknown" then return nil, "no address to try: the setting is \"unknown\"" end
    local sock = (address:find(":", 1, true) and socket.tcp6 or socket.tcp4)()
    seconds = seconds or config.wait
    sock:settimeout(seconds)
    local connected, why = sock:connect(address, config.port)
    if not connected then
        sock:close()
        if why == "connection refused" then return nil, "nothing listens at " .. where .. " (refused)" end
        if why == "timeout" then
            return nil, address .. " cannot be reached: no answer to connect within " .. seconds .. " s"
        end
        return nil, address .. " cannot be reached: " .. tostring(why)
    end
    -- a frame's reads give up after PATIENCE quiet waits: the whole wait
    sock:settimeout(config.wait / frames.PATIENCE)
    return sock
end
-- }}}

-- {{{ function M.silence
-- config, where, why read_frame gave → the words for a home that sent
-- nothing (or not a frame) where an answer was due.
function M.silence(config, where, lost)
    if lost == "closed" then
        return where .. " closed the connection without a word: the token is not one this home knows"
    end
    if lost == "timeout" then
        return where .. " said nothing within " .. config.wait
            .. " s: this may not be a device port, or the home is stuck"
    end
    return where .. " answered with something that is not a frame (" .. tostring(lost) .. ")"
end
-- }}}

-- {{{ function M.send_record / M.read_record
-- sock, pair, record → true, or nil and why.
function M.send_record(sock, pair, record)
    local sent, why = frames.write_frame(sock, seal.seal(pair, records.encode(record)))
    if not sent then return nil, why or "closed" end
    return true
end
-- sock, pair → the record; or nil, why read_frame gave (closed, timeout,
-- ...), or "sealed" (not under this device's key) or "record" (no record).
function M.read_record(sock, pair)
    local frame, lost = frames.read_frame(sock)
    if not frame then return nil, lost end
    local line = seal.open(pair, frame)
    if not line then return nil, "sealed" end
    local record = records.decode(line)
    if not record then return nil, "record" end
    return record
end
-- }}}

-- {{{ local function server_module
-- 187 as a module, for its WebSocket layer (309), loaded when first needed.
local loaded_server
local function server_module()
    loaded_server = loaded_server or require("187-device-server")
    return loaded_server
end
-- }}}

-- {{{ function M.reach
-- config → a socket whose home has answered a sealed ping, where (the
-- address and port), and which setting it was ("home-network" or
-- "public"); or nil and the words that say what failed (issue 307).
-- The home-network address is tried first with quick-wait to connect,
-- then the public one with wait, as rmail's phone does.  An address that
-- connects but does not answer the ping is the home itself refusing (or
-- stuck), so the next address is not tried: the device says so (307
-- decision 2), rather than hide a wrong token behind "cannot be reached".
function M.reach(config)
    local tried = {}
    for _, choice in ipairs({ { "home-network", config["quick-wait"] }, { "public", config.wait } }) do
        local setting, seconds = choice[1], choice[2]
        local address = config[setting]
        local where = address .. " " .. config.port
        local sock, failed = M.connect(config, address, seconds)
        -- Path: a browser's way in (309) — the upgrade first, then the
        -- same frames inside WebSocket messages.
        if sock and config["websocket-path"] then
            local plain = sock
            sock, failed = server_module().websocket_client(plain, address, config["websocket-path"])
            if not sock then
                plain:close()
                if M.broken ~= "fall-through" then return nil, where .. " did not take the WebSocket upgrade: " .. failed end
                tried[#tried + 1] = setting .. ": " .. where .. " did not take the WebSocket upgrade: " .. failed
            end
        end
        if sock then
            local pair, id = room_key.key_pair(config.token), new_id()
            local reply, lost
            if M.send_record(sock, pair, { kind = "ping", id = id }) then
                reply, lost = M.read_record(sock, pair)
            else
                lost = "closed"
            end
            if reply and reply.kind == "pong" and reply.id == id then return sock, where, setting end
            sock:close()
            local words = reply and (where .. " answered under another key, or not this ping's pong")
                or (lost == "sealed" or lost == "record") and (where .. " answered with something that is not one of its records")
                or M.silence(config, where, lost)
            -- Path: the home answered at the TCP level — said, not passed
            -- over (or, in the broken version fall-through, passed over).
            if M.broken ~= "fall-through" then return nil, words end
            tried[#tried + 1] = setting .. ": " .. words
        else
            tried[#tried + 1] = setting .. ": " .. failed
        end
    end
    return nil, "the home could not be reached (" .. table.concat(tried, "; ") .. ")"
end
-- }}}

-- {{{ function M.test
-- config, address → ok (boolean), the words that say what happened.
function M.test(config, address)
    local function told(ok, words)
        if not ok and M.broken == "one-message" then return false, "could not connect" end
        return ok, words
    end
    local where = address .. " " .. config.port
    local started = socket.gettime()
    local sock, failed = M.connect(config, address)
    if not sock then return told(false, failed) end
    local pair = room_key.key_pair(config.token)
    local id = new_id()
    local sent = M.send_record(sock, pair, { kind = "ping", id = id })
    local frame, lost
    if sent then frame, lost = frames.read_frame(sock) else lost = "closed" end
    sock:close()
    if not frame then return told(false, M.silence(config, where, lost)) end
    local line = seal.open(pair, frame)
    local reply = line and records.decode(line)
    if not reply or reply.kind ~= "pong" or reply.id ~= id then
        return told(false, where .. " answered under another key, or not this ping's pong")
    end
    return true, string.format("answered in %d ms by %s", math.floor((socket.gettime() - started) * 1000 + 0.5), where)
end
-- }}}

-- {{{ local function remove_room_folder
-- mirror, mailbox, room (both checked 32 hex) → the room's folder gone.
local function remove_room_folder(root, mailbox, room)
    if not (mirror.is_tag(mailbox) and mirror.is_tag(room)) then return end
    local folder = root .. "/" .. mailbox .. "/inbox/" .. room
    for _, name in ipairs(disk.list_dir(folder)) do os.remove(folder .. "/" .. name) end
    os.remove(folder)
end
-- }}}

-- {{{ local function prune
-- mirror → room folders no `.tree` of their mailbox names, removed (a room
-- the home has left); how many.  A mailbox without a `.tree` is left.
local function prune(root)
    local removed = 0
    for _, mailbox in ipairs(disk.is_dir(root) and disk.list_dir(root) or {}) do
        local tree = mirror.is_tag(mailbox) and mirror.read_file(root .. "/" .. mailbox .. "/inbox/.tree")
        if tree then
            local named = {}
            for tag in tree:gmatch("(%x+) [^\n]*") do named[tag] = true end
            for _, room in ipairs(disk.list_dir(root .. "/" .. mailbox .. "/inbox")) do
                if mirror.is_tag(room) and not named[room] then
                    remove_room_folder(root, mailbox, room)
                    removed = removed + 1
                end
            end
        end
    end
    return removed
end
-- }}}

-- {{{ function M.take_file
-- mirror, a `file` record, a summary: the file written into the mirror
-- when its path passes 192's check (counted in summary.refused, with
-- why, when it does not).
function M.take_file(root, record, summary)
    summary.files = summary.files + 1
    local kind, why = mirror.check_path(record.path)
    if not kind and M.broken == "no-path-check" then kind = "unchecked" end
    -- Path: a path outside 301's layout — refused, nothing written.
    if not kind then
        summary.refused[#summary.refused + 1] = why
        return false
    end
    if kind == "message" then summary.messages = summary.messages + 1 end
    if mirror.write(root, record.path, record.content) then summary.changed = summary.changed + 1 end
    return true
end
-- }}}

-- {{{ function M.catch_up
-- sock, pair, device folder, where (for the words) → a summary {files,
-- messages, changed, dropped, refused = {why...}}; or nil and the words
-- that say what failed.  One exchange (issue 304): `catch-up` with this
-- mirror's positions, the home's files written into the mirror, then for
-- each room the home sent an index of: the files it does not hold
-- dropped, and those it holds otherwise asked for with `want`.
function M.catch_up(sock, pair, folder, where, config)
    local root = folder .. "/mirror"
    if not disk.is_dir(root) then os.execute("mkdir -p " .. disk.shell_quote(root)) end
    local positions_text = mirror.positions_text(root)
    local positions = assert(mirror.read_positions(positions_text))
    local summary = { files = 0, messages = 0, changed = 0, dropped = 0, refused = {} }
    if not M.send_record(sock, pair, { kind = "catch-up", rooms = positions_text }) then
        return nil, M.silence(config, where, "closed")
    end
    local function take_file(record) M.take_file(root, record, summary) end
    -- {{{ local function answer_until
    -- reads records until `stop(record)` is true; files are taken, an
    -- index is kept; anything else is the home breaking the exchange.
    local indexes = {}
    local function answer_until(stop)
        while true do
            local record, lost = M.read_record(sock, pair)
            if not record then
                if lost == "sealed" or lost == "record" then
                    return nil, where .. " answered with something that is not one of its records"
                end
                return nil, M.silence(config, where, lost)
            end
            if record.kind == "file" then take_file(record)
            elseif record.kind == "index" then
                local index = indexes[record.room] or {}
                indexes[record.room] = index
                for line in (record.entries .. "\n"):gmatch("([^\n]*)\n") do
                    local name, hash = line:match("^(%S+) (%x+)$")
                    if name and mirror.is_message_name(name) and #hash == 64 then index[name] = hash
                    elseif line ~= "" then summary.refused[#summary.refused + 1] = "an index line '" .. line:sub(1, 60) .. "'" end
                end
            elseif stop(record) then return true
            else return nil, where .. " sent a " .. record.kind .. " where it was not due" end
        end
    end
    -- }}}
    local ok, why = answer_until(function(record) return record.kind == "caught-up" end)
    if not ok then return nil, why end
    -- the rooms the home sent an index of
    local rooms = mirror.rooms(root)
    local tags = {}
    for tag in pairs(indexes) do tags[#tags + 1] = tag end
    table.sort(tags)
    for _, tag in ipairs(tags) do
        local held, room, index = positions[tag], rooms[tag], indexes[tag]
        if not held or not room then
            summary.refused[#summary.refused + 1] = "an index for room " .. tag .. ", which this device did not list"
        else
            local mine = {}
            for _, entry in ipairs(mirror.entries(root, room.mailbox, tag, room.names, held.last)) do
                mine[entry.name] = entry.hash
                -- Path: held here, not on the home — dropped.
                if not index[entry.name] then
                    os.remove(root .. "/" .. room.mailbox .. "/inbox/" .. tag .. "/" .. entry.name)
                    summary.dropped = summary.dropped + 1
                end
            end
            local wanted = {}
            for name, hash in pairs(index) do if mine[name] ~= hash then wanted[#wanted + 1] = name end end
            table.sort(wanted)
            if #wanted > 0 then
                local id = new_id()
                if not M.send_record(sock, pair, { kind = "want", id = id, room = tag, names = table.concat(wanted, "\n") }) then
                    return nil, M.silence(config, where, "closed")
                end
                ok, why = answer_until(function(record) return record.kind == "sent" and record.id == id end)
                if not ok then return nil, why end
            end
        end
    end
    summary.dropped = summary.dropped + prune(root)
    -- a typed/ beside each mailbox's inbox, where 183 writes (305)
    for _, mailbox in ipairs(disk.list_dir(root)) do
        if mirror.is_tag(mailbox) and disk.is_dir(root .. "/" .. mailbox .. "/inbox")
            and not disk.is_dir(root .. "/" .. mailbox .. "/typed") then
            os.execute("mkdir -p " .. disk.shell_quote(root .. "/" .. mailbox .. "/typed"))
        end
    end
    return summary
end
-- }}}

-- {{{ function M.typed_files
-- device folder → the typed files waiting in the mirror, oldest first:
-- { mailbox, name, path }.  A file with a `<name>.refused` beside it
-- waits for the person, not for the home; temporary names (".") and the
-- reasons themselves are not typed files.
function M.typed_files(folder)
    local root = folder .. "/mirror"
    local list = {}
    for _, mailbox in ipairs(disk.is_dir(root) and disk.list_dir(root) or {}) do
        local queue = root .. "/" .. mailbox .. "/typed"
        if mirror.is_tag(mailbox) and disk.is_dir(queue) then
            local names = {}
            for _, name in ipairs(disk.list_dir(queue)) do names[name] = true end
            for name in pairs(names) do
                if name:sub(1, 1) ~= "." and not name:match("%.refused$") and not names[name .. ".refused"]
                    and disk.is_file(queue .. "/" .. name) then
                    list[#list + 1] = { mailbox = mailbox, name = name, path = queue .. "/" .. name }
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end
-- }}}

-- {{{ function M.send_typed
-- sock, pair, device folder, where, config → {sent, refused, lines}, or
-- nil and the words that say what failed.  Each typed file goes as
-- `typed` (its name the id), the oldest first; it is removed only on
-- `typed-ok`; `typed-refused` leaves it, with the reason in
-- `<name>.refused` beside it, so nothing typed is lost silently (305).
function M.send_typed(sock, pair, folder, where, config)
    local summary = { sent = 0, refused = 0, lines = {} }
    for _, file in ipairs(M.typed_files(folder)) do
        local content = mirror.read_file(file.path)
        if content then
            local ok = file.name:match("^[%w%-]+$") and #file.name <= 64
                and M.send_record(sock, pair, { kind = "typed", id = file.name, content = content })
            if not ok then
                if not file.name:match("^[%w%-]+$") or #file.name > 64 then
                    ram.put(file.path:match("^(.*)/[^/]+$"), file.name .. ".refused",
                        "not sent: its name is not a typed file's name\n")
                    summary.refused = summary.refused + 1
                    summary.lines[#summary.lines + 1] = "kept " .. file.name .. ": its name is not a typed file's name"
                else
                    return nil, M.silence(config, where, "closed")
                end
            else
                local reply, lost = M.read_record(sock, pair)
                if not reply then return nil, M.silence(config, where, lost) end
                if reply.id ~= file.name or (reply.kind ~= "typed-ok" and reply.kind ~= "typed-refused") then
                    return nil, where .. " answered " .. file.name .. " with a " .. reply.kind .. " for " .. tostring(reply.id)
                end
                -- Path: taken — removed here.  Refused — kept, with why
                -- (or, in the broken version drop-refused, removed).
                if reply.kind == "typed-ok" or M.broken == "drop-refused" then
                    os.remove(file.path)
                    if reply.kind == "typed-ok" then summary.sent = summary.sent + 1 end
                else
                    ram.put(file.path:match("^(.*)/[^/]+$"), file.name .. ".refused", reply.why .. "\n")
                    summary.refused = summary.refused + 1
                    summary.lines[#summary.lines + 1] = "kept " .. file.name .. ": " .. reply.why
                end
            end
        end
    end
    return summary
end
-- }}}

-- {{{ local function keep_refused
-- a typed file and the home's reason: kept, the reason beside it.
local function keep_refused(file, why)
    ram.put(file.path:match("^(.*)/[^/]+$"), file.name .. ".refused", why .. "\n")
end
-- }}}

-- {{{ function M.live
-- sock, pair, device folder, where, config, seconds (nil: until the
-- connection ends), out(line) → the summary of what was pushed, or nil
-- and the words that say how the connection ended (issue 306).  After a
-- catch-up the connection stays open: each `file` the home pushes is
-- written into the mirror (checked as in a catch-up); each typed file
-- the person writes is sent as soon as it is seen (polled every 0.2 s)
-- and removed on its `typed-ok`; and when this device has sent nothing
-- for `keep-alive` seconds it sends a `ping`, so the home, which closes
-- a connection quiet for its idle limit, keeps it (306 decision 4).
function M.live(sock, pair, folder, where, config, seconds, out)
    local root = folder .. "/mirror"
    local stop_at = seconds and (socket.gettime() + seconds)
    local summary = { files = 0, messages = 0, changed = 0, dropped = 0, refused = {} }
    local pending = {}
    local last_sent = socket.gettime()
    local function send(record)
        last_sent = socket.gettime()
        return M.send_record(sock, pair, record)
    end
    while not stop_at or socket.gettime() < stop_at do
        for _, file in ipairs(M.typed_files(folder)) do
            if not pending[file.name] and file.name:match("^[%w%-]+$") and #file.name <= 64 then
                local content = mirror.read_file(file.path)
                if content then
                    if not send({ kind = "typed", id = file.name, content = content }) then
                        return nil, where .. " closed the connection"
                    end
                    pending[file.name] = file
                end
            end
        end
        if socket.gettime() - last_sent >= config["keep-alive"] then
            if not send({ kind = "ping", id = new_id() }) then return nil, where .. " closed the connection" end
        end
        local readable = socket.select({ sock.raw or sock }, nil, 0.2)
        if readable and #readable > 0 then
            local record, lost = M.read_record(sock, pair)
            if not record then
                if lost == "closed" then return nil, where .. " closed the connection" end
                return nil, M.silence(config, where, lost)
            end
            if record.kind == "file" then
                if M.take_file(root, record, summary) then out("received " .. record.path) end
            elseif (record.kind == "typed-ok" or record.kind == "typed-refused") and pending[record.id] then
                local file = pending[record.id]
                pending[record.id] = nil
                if record.kind == "typed-ok" then
                    os.remove(file.path)
                    out("sent " .. file.name)
                else
                    keep_refused(file, record.why)
                    out("kept " .. file.name .. ": " .. record.why)
                end
            elseif record.kind ~= "pong" then
                return nil, where .. " sent a " .. record.kind .. " where it was not due"
            end
        end
    end
    return summary
end
-- }}}

-- {{{ M.deck
-- The locked-screen check-in's deck (issue 308; planning section 6): each
-- wait is the base (30 s) plus a card dealt from a shuffled deck of
-- whole-second cards, without putting cards back; when the deck runs out
-- it is shuffled again.  The cards are -5 ... +5 (308 decision 1): eleven
-- cards adding up to zero, so any whole number of passes through the
-- deck averages exactly the base.  Shuffled with the kernel's random
-- bytes (Fisher-Yates, each draw by 007's rule: no modulo bias).  The
-- Android app follows this.
M.deck = {}
M.deck.CARDS = { -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5 }

-- {{{ local function random_below
-- n → a whole number from 1 to n, every value equally likely.
local function random_below(n)
    local source = assert(io.open("/dev/urandom", "rb"))
    local range = 4294967296
    local limit = range - (range % n)
    while true do
        local bytes = source:read(4)
        if bytes == nil or #bytes ~= 4 then source:close() error("could not read 4 bytes from /dev/urandom", 2) end
        local b1, b2, b3, b4 = bytes:byte(1, 4)
        local value = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
        if value < limit then source:close() return (value % n) + 1 end
    end
end
-- }}}

-- {{{ function M.deck.shuffled
-- → the cards in a fresh random order (Fisher-Yates).
function M.deck.shuffled()
    local cards = {}
    for i, card in ipairs(M.deck.CARDS) do cards[i] = card end
    for i = #cards, 2, -1 do
        local j = random_below(i)
        cards[i], cards[j] = cards[j], cards[i]
    end
    return cards
end
-- }}}

-- {{{ function M.deck.new
-- → a deck: deck:deal() gives the next card, shuffling again when the
-- deck has run out.  For referees only (197): RAO_DEVICE_BROKEN=replace
-- (each card drawn from the whole deck, put back), no-reshuffle (the
-- first order dealt again and again).
function M.deck.new()
    local deck = { left = {}, first = nil }
    function deck:deal()
        if M.broken == "replace" then return M.deck.CARDS[random_below(#M.deck.CARDS)] end
        if #self.left == 0 then
            if M.broken == "no-reshuffle" and self.first then
                for i, card in ipairs(self.first) do self.left[i] = card end
            else
                self.left = M.deck.shuffled()
                self.first = self.first or { unpack(self.left) }
            end
        end
        return table.remove(self.left, 1)
    end
    return deck
end
-- }}}
-- }}}

-- {{{ function M.check_in
-- device folder, config, seconds, out(line) → how many check-ins, and
-- how many failed.  While the screen is locked (issue 308) there is no
-- connection: each wait is `check-in` seconds plus the next card, then
-- one check-in, which is a 304 catch-up exchange (reached as 307 says),
-- and the connection is closed again.  Stops when the next wait would end
-- after `seconds`.
function M.check_in(folder, config, seconds, out)
    local deck = M.deck.new()
    local stop_at = socket.gettime() + seconds
    local done, missed = 0, 0
    while true do
        local wait = config["check-in"] + deck:deal()
        if socket.gettime() + wait > stop_at then break end
        out("next check-in in " .. wait .. " s")
        socket.sleep(wait)
        local sock, where = M.reach(config)
        if not sock then
            missed = missed + 1
            out("check-in failed: " .. where)
        else
            local summary, lost = M.catch_up(sock, room_key.key_pair(config.token), folder, where, config)
            sock:close()
            if summary then
                done = done + 1
                out("checked in: " .. M.summary_text(summary, where))
            else
                missed = missed + 1
                out("check-in failed: " .. lost)
            end
        end
    end
    return done, missed
end
-- }}}

-- {{{ function M.summary_text
function M.summary_text(summary, where)
    local out = { string.format("caught up with %s: %d file(s) received (%d message(s)), %d changed, %d dropped",
        where, summary.files, summary.messages, summary.changed, summary.dropped) }
    for _, why in ipairs(summary.refused) do out[#out + 1] = "refused from the home: " .. why end
    return table.concat(out, "\n")
end
-- }}}

-- {{{ local function main
local USAGE = "usage: luajit 190-device.lua <device folder> test [--public] | catch-up | send | live [--for <seconds>]"
    .. " | check-in --for <seconds>\n"
local COMMANDS = { test = true, ["catch-up"] = true, send = true, live = true, ["check-in"] = true }
local function main(args)
    local folder, command = args[1], args[2]
    if not folder or not COMMANDS[command] then
        io.stderr:write(USAGE)
        return 2
    end
    local config, why = M.read_config(folder)
    if not config then io.stderr:write("device: " .. why .. "\n") return 1 end
    if command == "test" then
        local ok, words = M.test(config, args[3] == "--public" and config.public or config["home-network"])
        io.write(words, "\n")
        return ok and 0 or 1
    end
    if command == "check-in" then
        config["check-in"] = tonumber(M.config_values(folder)["check-in"] or "")
        local seconds = args[3] == "--for" and tonumber(args[4])
        if not config["check-in"] or config["check-in"] <= 5 then
            io.stderr:write("device: check-in needs check-in = <seconds above 5> in " .. folder .. "/config\n")
            return 1
        end
        if not seconds then io.stderr:write(USAGE) return 2 end
        local done, missed = M.check_in(folder, config, seconds, function(line) io.write(line, "\n") io.flush() end)
        io.write(string.format("checked in %d time(s), %d failed\n", done, missed))
        return missed == 0 and 0 or 1
    end
    local sock, where, setting = M.reach(config)
    if not sock then io.write(where, "\n") return 1 end
    io.write("reached the home by its " .. setting .. " address, " .. where
        .. (config["websocket-path"] and (", through a WebSocket upgrade on " .. config["websocket-path"]) or "") .. "\n")
    if command == "send" then
        local sent, lost = M.send_typed(sock, room_key.key_pair(config.token), folder, where, config)
        sock:close()
        if not sent then io.write(lost, "\n") return 1 end
        io.write(string.format("sent %d typed file(s) to %s, %d kept\n", sent.sent, where, sent.refused))
        for _, line in ipairs(sent.lines) do io.write(line, "\n") end
        return sent.refused == 0 and 0 or 1
    end
    local live_for
    if command == "live" then
        config["keep-alive"] = tonumber(M.config_values(folder)["keep-alive"] or "")
        if not config["keep-alive"] or config["keep-alive"] <= 0 then
            sock:close()
            io.stderr:write("device: live needs keep-alive = <seconds above 0> in " .. folder .. "/config\n")
            return 1
        end
        if args[3] == "--for" then live_for = tonumber(args[4]) end
    end
    local pair = room_key.key_pair(config.token)
    local summary, lost = M.catch_up(sock, pair, folder, where, config)
    if not summary then sock:close() io.write(lost, "\n") return 1 end
    io.write(M.summary_text(summary, where), "\n")
    if command ~= "live" then
        sock:close()
        return #summary.refused == 0 and 0 or 1
    end
    io.flush()
    local pushed, ended = M.live(sock, pair, folder, where, config, live_for,
        function(line) io.write(line, "\n") io.flush() end)
    sock:close()
    if not pushed then io.write(ended, "\n") return 1 end
    io.write(string.format("live for %s s: %d file(s) pushed, %d changed\n", tostring(live_for), pushed.files,
        pushed.changed))
    for _, why in ipairs(pushed.refused) do io.write("refused from the home: ", why, "\n") end
    return #pushed.refused == 0 and 0 or 1
end
-- }}}

if arg and arg[0] and arg[0]:match("190%-device%.lua$") then os.exit(main(arg)) end
return M
