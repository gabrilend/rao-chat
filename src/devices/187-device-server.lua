-- 187-device-server.lua — the home's device port: where its paired phones
-- and browsers connect (issue 302; decision of 2026-11-06, rubric question
-- 24 and 301's decision 22: one device port per home, never a mailbox's).
--
--   luajit src/devices/187-device-server.lua <project> <disk home>
--
-- One small process per home, beside the home starter.  It reads the
-- home's `config` (`devices.port`, `devices.address`,
-- `devices.frame-deadline`, `gatherer.ram-root`), the home's `devices`
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
-- Nothing is ever sent in the clear: a connection whose first four bytes
-- are no frame length 124 accepts is closed without an answer (125).
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
-- file sent again is put again, though it was taken).
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
    local _, paths = mirror.listing(home_ram)
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
    return replies
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
        return M.catch_up_replies(session.server.home_ram, positions)
    end,
    want = function(session, record)
        return M.want_replies(session.server.home_ram, record)
    end,
    typed = function(session, record)
        return M.typed_replies(session.server, session.label, record)
    end,
}
-- }}}

-- {{{ function M.serve_connection
-- conn (162's), server ({deadline, keys = function() → ring, by_label},
-- home_ram, on_refused, on_problem}) → nothing; the connection is closed
-- at the end.
function M.serve_connection(conn, server)
    local session = { conn = conn, server = server }
    local pinned
    while true do
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
            session.label = label
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
        local reply_pair = pinned
        if M.broken == "wrong-key" then reply_pair = room_key.key_pair("not this device's token") end
        local sent = true
        for _, reply in ipairs(replies) do
            sent = frames.write_frame(conn, seal.seal(reply_pair, records.encode(reply)))
            if not sent then break end
        end
        if not sent then break end
    end
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
