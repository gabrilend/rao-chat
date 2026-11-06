-- 190-device.lua — the reference device: what a phone or a browser does,
-- written as a small Lua program the referees can drive (issue 303; the
-- Android app and the web page follow it, as they follow 183).
--
--   luajit src/devices/190-device.lua <device folder> test [--public]
--   luajit src/devices/190-device.lua <device folder> catch-up
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

local M = {}

-- For referees only (191): RAO_DEVICE_BROKEN=one-message (every failure
-- is told the same way).  (193): no-path-check (a path from the home is
-- written into the mirror unchecked).
M.broken = os.getenv("RAO_DEVICE_BROKEN") or ""

-- {{{ function M.read_config
-- device folder → the settings, or nil and why.
function M.read_config(folder)
    local handle = io.open(folder .. "/config", "rb")
    if not handle then return nil, folder .. "/config cannot be read" end
    local text = handle:read("*a")
    handle:close()
    local ok, values = pcall(formats.parse_config, text, folder .. "/config")
    if not ok then return nil, tostring(values) end
    local config = {}
    for _, name in ipairs({ "port", "home-network", "public", "token", "wait" }) do
        if values[name] == nil then return nil, folder .. "/config has no " .. name .. " line" end
        config[name] = values[name]
    end
    config.port = formats.parse_port(config.port)
    if not config.port then return nil, "port must be a whole number 1 to 65535" end
    config.wait = tonumber(config.wait)
    if not config.wait or config.wait <= 0 then return nil, "wait must be a number of seconds above 0" end
    local good, why = pcall(tokens.check_token, config.token)
    if not good then return nil, "token: " .. tostring(why) end
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
-- config, address → a connected socket, or nil and the words that say
-- what failed (nothing listens, cannot be reached).
function M.connect(config, address)
    local where = address .. " " .. config.port
    if address == "unknown" then return nil, "no address to try: the setting is \"unknown\"" end
    local sock = (address:find(":", 1, true) and socket.tcp6 or socket.tcp4)()
    sock:settimeout(config.wait)
    local connected, why = sock:connect(address, config.port)
    if not connected then
        sock:close()
        if why == "connection refused" then return nil, "nothing listens at " .. where .. " (refused)" end
        if why == "timeout" then
            return nil, address .. " cannot be reached: no answer to connect within " .. config.wait .. " s"
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
    -- {{{ local function take_file
    local function take_file(record)
        summary.files = summary.files + 1
        local kind, why = mirror.check_path(record.path)
        if not kind and M.broken == "no-path-check" then kind = "unchecked" end
        -- Path: a path outside 301's layout — refused, nothing written.
        if not kind then
            summary.refused[#summary.refused + 1] = why
            return
        end
        if kind == "message" then summary.messages = summary.messages + 1 end
        if mirror.write(root, record.path, record.content) then summary.changed = summary.changed + 1 end
    end
    -- }}}
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
    return summary
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
local USAGE = "usage: luajit 190-device.lua <device folder> test [--public] | catch-up\n"
local function main(args)
    local folder, command = args[1], args[2]
    if not folder or (command ~= "test" and command ~= "catch-up") then
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
    local address = config["home-network"]
    local where = address .. " " .. config.port
    local sock, failed = M.connect(config, address)
    if not sock then io.write(failed, "\n") return 1 end
    local summary, lost = M.catch_up(sock, room_key.key_pair(config.token), folder, where, config)
    sock:close()
    if not summary then io.write(lost, "\n") return 1 end
    io.write(M.summary_text(summary, where), "\n")
    return #summary.refused == 0 and 0 or 1
end
-- }}}

if arg and arg[0] and arg[0]:match("190%-device%.lua$") then os.exit(main(arg)) end
return M
