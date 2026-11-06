-- 201-phase-3-scenes.lua — the scenes of the phase 3 demo (issue 310).
--
-- One world for every scene: two real homes, A on 127.0.0.2 and B on
-- 127.0.0.3, one room between them, each home with its starter (164),
-- whose gatherer (163) is its own process, and its device server (187);
-- and two devices paired with A: a "phone" and a "browser", each a folder
-- driven by the reference device (190).  The browser reaches A through
-- 309's WebSocket upgrade; it is 190 speaking WebSocket, since the web
-- client itself is phase 4's.  Everything runs on loopback, on the real
-- clock, under tmp/shared-memory/phase-3-demo/, which `finish` removes.
--
-- The scenes run in order and build on each other (the browser stays live
-- from `writing` on, the phone checks in from `locked` on); a scene that
-- needs what an earlier one failed to make fails too, saying so.  A scene
-- is a function(c) → {lines = {...}, gaps = {...}}, as 159's are: `gaps`
-- names a part that could not run and why; the scene still ran.  A scene
-- raises an error when what it shows did not happen (a message that never
-- reached a mirror, a mirror that differs from the home), so the demo
-- counts it as could-not: what is printed is read from the homes' and the
-- devices' files, never text about them.
--
-- One stand-in, said where it happens: no viewer or device command makes
-- an edit yet, so `edit` files the correction into A's RAM home with
-- 081's correct, beside the running gatherer, as its filer would; the
-- gatherer writes the inbox again at its next sync, and the devices are
-- shown what it wrote.
--
-- c (from 200): dir, scratch, m (the modules by short name), world (set
-- by `setup`).

local socket = require("socket")

local M = {}

-- The scenes, in the order the demo shows them.
M.ORDER = {
    { key = "homes",    title = "Two homes, each with its gatherer and its device port (211, 302)" },
    { key = "pairing",  title = "A phone and a browser paired with home A (303, 307)" },
    { key = "catch-up", title = "Each device catches up: its mirror of A's RAM folder (301, 304, 309)" },
    { key = "writing",  title = "The phone writes; the browser is pushed it; home B receives it (305, 306)" },
    { key = "locked",   title = "The phone locks, and catches up at its check-ins (308)" },
    { key = "edit",     title = "A message edited: the edit reaches both devices (304, 306, 308)" },
}

local ADDRESS_A, ADDRESS_B = "127.0.0.2", "127.0.0.3"
local MAILBOX_PORT_A, MAILBOX_PORT_B = 7702, 7703
local DEVICE_PORT_A, DEVICE_PORT_B = 7712, 7713
local SOCKET_PATH = "/rao-chat-socket"

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

-- {{{ local function quote / seconds / read_all / shell
local function quote(text) return "'" .. text:gsub("'", "'\\''") .. "'" end
local function seconds(value) return string.format("%.1f s", value) end
local function read_all(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
-- A command's output, as lines, and whether it exited 0.
local function shell(command)
    local p = io.popen(command .. " 2>&1; echo \"exit=$?\"")
    local lines = {}
    for line in p:lines() do lines[#lines + 1] = line end
    p:close()
    local status = tonumber((table.remove(lines) or ""):match("^exit=(%d+)$"))
    return lines, status == 0
end
local function write_private(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
    os.execute("chmod 600 " .. quote(path))
end
-- }}}

-- {{{ local function wait_until
local function wait_until(condition, limit)
    local stop = socket.gettime() + limit
    while socket.gettime() < stop do
        if condition() then return true end
        socket.sleep(0.1)
    end
    return condition()
end
-- }}}

-- {{{ local function first_variants
-- Every setting's first variant, from each module's options file: the
-- homes' config before the demo's own lines.
local function first_variants(dir)
    local config = {}
    local listing = io.popen("ls " .. quote(dir) .. "/src/*/[0-9][0-9][0-9]-options.lua")
    for path in listing:lines() do
        for _, choice in ipairs(dofile(path)) do
            if choice.config_key ~= "" then config[choice.config_key] = choice.variants[1].name end
        end
    end
    listing:close()
    return config
end
-- }}}

-- {{{ local function alive
-- running: there, and not a zombie waiting to be reaped
local function alive(pid)
    local f = pid and io.open("/proc/" .. pid .. "/stat", "rb")
    if not f then return false end
    local stat = f:read("*a")
    f:close()
    return stat:match("%) (%a)") ~= "Z"
end
-- }}}

-- {{{ local function listens
-- Whether something accepts a connection at address:port.
local function listens(address, port)
    local sock = socket.tcp4()
    sock:settimeout(0.3)
    local ok = sock:connect(address, port)
    sock:close()
    return ok ~= nil
end
-- }}}

-- {{{ local function holding
-- The 301-layout message files under `root` whose text holds `text`:
-- a list of {path, text}.
local function holding(m, root, text)
    local found = {}
    local _, paths = m.mirror.listing(root)
    for _, path in ipairs(paths) do
        if m.mirror.check_path(path) == "message" then
            local body = read_all(root .. "/" .. path)
            if body and body:find(text, 1, true) then found[#found + 1] = { path = path, text = body } end
        end
    end
    return found
end
-- }}}

-- {{{ local function compare
-- A device's mirror against the home's RAM folder: the number of files
-- the home has, the paths that are wrong (missing, extra, or a message
-- whose text differs), and the other files whose text differs (state,
-- .tree, .room: a gatherer writes its state again at every sync, so a
-- snapshot taken a moment ago can be older; the next catch-up brings it).
local function compare(m, home_root, mirror_root)
    local want, have = {}, {}
    for _, path in ipairs(select(2, m.mirror.listing(home_root))) do want[path] = read_all(home_root .. "/" .. path) end
    for _, path in ipairs(select(2, m.mirror.listing(mirror_root))) do have[path] = read_all(mirror_root .. "/" .. path) end
    local count, wrong, newer = 0, {}, {}
    for path, text in pairs(want) do
        count = count + 1
        if have[path] == nil or (have[path] ~= text and m.mirror.check_path(path) == "message") then
            wrong[#wrong + 1] = path
        elseif have[path] ~= text then
            newer[#newer + 1] = path
        end
    end
    for path in pairs(have) do if want[path] == nil then wrong[#wrong + 1] = path end end
    table.sort(wrong)
    table.sort(newer)
    return count, wrong, newer
end
-- }}}

-- {{{ local function compared
-- compare's figures as a line, raising an error when any path is wrong.
local function compared(m, who, home_root, mirror_root)
    local count, wrong, newer = compare(m, home_root, mirror_root)
    if #wrong > 0 then error("the " .. who .. "'s mirror differs from A at " .. wrong[1], 0) end
    local names = {}
    for _, path in ipairs(newer) do names[#names + 1] = path:match("([^/]+)$") end
    return string.format("  the %s's mirror against A's RAM folder: %d files, every message the same%s", who, count,
        #newer > 0 and ("; since rewritten by A's gatherer: " .. table.concat(names, ", ")) or ", and every other file")
end
-- }}}

-- {{{ local function body_lines
-- An inbox file's lines, indented, its long hex shortened.
local function body_lines(out, text, indent)
    for line in text:gmatch("([^\n]*)\n?") do
        if line ~= "" or #out == 0 then
            out[#out + 1] = indent .. (line:gsub("(%x%x%x%x%x%x%x%x)%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x", "%1..."))
        end
    end
end
-- }}}

-- {{{ local function short
local function short(path) return (path:gsub("(%x%x%x%x%x%x%x%x)%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x", "%1...")) end
-- }}}

------------------------------------------------------------------------------
-- The world
------------------------------------------------------------------------------

-- {{{ function M.setup
-- c → the world: its folder, the two homes (made, not started), and the
-- process tools; or nil and why.
function M.setup(c)
    local m = c.m
    local up, why = m.loopback.bring_up()
    if not up then return nil, "loopback could not be brought up (" .. tostring(why) .. ")" end
    local root = c.scratch
    os.execute("rm -rf " .. quote(root) .. " && mkdir -p " .. quote(root .. "/homes") .. " " .. quote(root .. "/devices"))
    local w = { root = root, ram_root = root .. "/ram", pids = {}, no_lookups = m.loopback.only_loopback(),
                devices = {} }
    local defaults = first_variants(c.dir)

    -- a home with the demo's one room on its own mailbox, and its device port
    local function home(name, address, mailbox_port, device_port)
        local dir = root .. "/homes/" .. name
        local h = m.rooms.open_home(dir)
        for key, value in pairs(defaults) do m.rooms.set_config(h, key, value) end
        local config = {
            ["gatherer.ram-root"] = w.ram_root, ["gatherer.address"] = address, ["gatherer.sync-interval"] = "2",
            ["delivery.retry-floor"] = "1", ["delivery.retry-ceiling"] = "4", ["callback.answer-time"] = "2",
            ["git.home-name"] = name,
            ["devices.port"] = tostring(device_port), ["devices.address"] = address,
            ["devices.frame-deadline"] = "2", ["devices.idle-limit"] = "10", ["devices.websocket-path"] = SOCKET_PATH,
        }
        for key, value in pairs(config) do m.rooms.set_config(h, key, value) end
        local tag = m.rooms.make_room(h, { label = "the room", token = "the phase 3 demo's room", kind = "group",
            parent = "", members = {}, filed_under = "", mailbox_port = mailbox_port })
        local mailbox = m.rooms.read_entry(h, tag).mailbox
        local home_ram = m.ram.home_ram(w.ram_root, dir)
        return { name = name, dir = dir, disk = h, tag = tag, mailbox = mailbox, address = address,
                 port = mailbox_port, device_port = device_port, home_ram = home_ram,
                 folder = home_ram .. "/" .. mailbox }
    end
    w.a = home("A", ADDRESS_A, MAILBOX_PORT_A, DEVICE_PORT_A)
    w.b = home("B", ADDRESS_B, MAILBOX_PORT_B, DEVICE_PORT_B)
    m.recipients.add_member(w.a.disk, w.a.tag, w.b.address, w.b.port)
    m.recipients.add_member(w.b.disk, w.b.tag, w.a.address, w.a.port)

    function w.launch(command, log)
        local p = io.popen(command .. " </dev/null >>" .. quote(log) .. " 2>&1 & echo $!")
        local pid = tonumber(p:read("*l"))
        p:close()
        w.pids[#w.pids + 1] = pid
        return pid
    end
    function w.state(h) return m.ram.read_state(h.folder) end
    -- the home's starter (164), which starts its gatherer; or, outside a
    -- loopback-only namespace (where the starter's public-address check
    -- would look outside), the gatherer by hand
    function w.start(h)
        os.execute("mkdir -p " .. quote(h.folder))
        if w.no_lookups then
            h.starter = w.launch("luajit " .. quote(c.dir .. "/src/gatherer/164-home-starter.lua") .. " "
                .. quote(c.dir) .. " " .. quote(h.dir), h.home_ram .. "/stderr")
        else
            w.launch("luajit " .. quote(c.dir .. "/src/gatherer/163-gatherer.lua") .. " " .. quote(c.dir) .. " "
                .. quote(h.dir) .. " " .. quote(h.mailbox), h.folder .. "/stderr")
        end
        wait_until(function() return alive(tonumber(w.state(h).pid or "")) end, 8)
        h.pid = tonumber(w.state(h).pid or "")
        h.server = w.launch("luajit " .. quote(c.dir .. "/src/devices/187-device-server.lua") .. " " .. quote(c.dir)
            .. " " .. quote(h.dir), h.home_ram .. "/device-server-output")
        wait_until(function() return listens(h.address, h.device_port) end, 8)
    end
    -- a device folder, its config from 189's lines and the demo's own
    function w.device(name, pairing_lines, extra)
        local folder = root .. "/devices/" .. name
        os.execute("mkdir -p " .. quote(folder))
        write_private(folder .. "/config", table.concat(pairing_lines, "\n") .. "\n" .. extra)
        local d = { name = name, folder = folder, mirror = folder .. "/mirror" }
        w.devices[name] = d
        return d
    end
    -- 190 run on a device: its lines and whether it exited 0
    function w.run_device(d, words)
        return shell("luajit " .. quote(c.dir .. "/src/devices/190-device.lua") .. " " .. quote(d.folder) .. " " .. words)
    end
    -- 190 run on a device in the background, its output in `log`
    function w.background(d, words, log)
        return w.launch("luajit " .. quote(c.dir .. "/src/devices/190-device.lua") .. " " .. quote(d.folder) .. " "
            .. words, log)
    end
    -- what a home's RAM log holds with `text` as a record's text
    function w.copies(h, text)
        local n = 0
        for line in (read_all(h.folder .. "/home/rooms/" .. h.tag .. "/log") or ""):gmatch("[^\n]+") do
            if line:find(text, 1, true) then n = n + 1 end
        end
        return n
    end
    -- a message typed on the home machine, signed with the home's name
    function w.type(h, text)
        m.ram.put(h.folder .. "/typed", m.ram.new_name(socket.gettime()), "room: " .. h.tag .. "\nwritten: "
            .. math.floor(socket.gettime()) .. "\n\n" .. text .. "\n\n" .. h.name .. "\n")
    end
    function w.process_line(h)
        local function program(pid)
            local cmdline = (read_all("/proc/" .. tostring(pid) .. "/cmdline") or ""):gsub("%z", " ")
            return cmdline:match("(%d%d%d%-[%w%-]+%.lua)") or "?"
        end
        local lines = {}
        if h.starter then
            lines[1] = string.format("      %s: pid %-7s %-22s %-17s %s", h.name, tostring(h.starter), program(h.starter),
                "", alive(h.starter) and "running" or "NOT RUNNING")
        end
        for _, line in ipairs({
            string.format("      %s: pid %-7s %-22s %s:%d   %s", h.name, tostring(h.pid), program(h.pid), h.address,
                h.port, alive(h.pid) and "running" or "NOT RUNNING"),
            string.format("      %s: pid %-7s %-22s %s:%d   %s", h.name, tostring(h.server), program(h.server),
                h.address, h.device_port, listens(h.address, h.device_port) and "listening" or "NOT LISTENING"),
        }) do lines[#lines + 1] = line end
        return lines
    end
    w.alive, w.wait_until = alive, wait_until
    return w
end
-- }}}

-- {{{ function M.finish
-- Stops every process the world started (the starters and device servers
-- asked first, through their stop files), then removes its folder.
function M.finish(c)
    local w = c.world
    if not w then return end
    for _, h in ipairs({ w.a, w.b }) do
        if h.starter and alive(h.starter) then os.execute("touch " .. quote(h.home_ram .. "/stop")) end
        if h.server and alive(h.server) then os.execute("touch " .. quote(h.home_ram .. "/devices/stop")) end
    end
    wait_until(function()
        for _, h in ipairs({ w.a, w.b }) do
            if (h.starter and alive(h.starter)) or (h.server and alive(h.server)) then return false end
        end
        return true
    end, 12)
    for _, pid in ipairs(w.pids) do if alive(pid) then os.execute("kill -9 " .. pid .. " 2>/dev/null") end end
    os.execute("pkill -9 -f " .. quote(w.root) .. " 2>/dev/null")
    wait_until(function()
        for _, pid in ipairs(w.pids) do if alive(pid) then return false end end
        return true
    end, 3)
    os.execute("rm -rf " .. quote(w.root))
end
-- }}}

------------------------------------------------------------------------------
-- The scenes
------------------------------------------------------------------------------

-- {{{ scene homes
M["homes"] = function(c)
    local w = c.world
    local out, gaps = {}, {}
    for _, h in ipairs({ w.a, w.b }) do w.start(h) end
    for _, h in ipairs({ w.a, w.b }) do
        if not w.alive(h.pid) then error(h.name .. "'s gatherer did not start: " .. tostring(read_all(h.home_ram .. "/stderr")), 0) end
        if not listens(h.address, h.device_port) then
            error(h.name .. "'s device server did not start: " .. tostring(read_all(h.home_ram .. "/device-server-output")), 0)
        end
    end
    if w.no_lookups then
        out[#out + 1] = "  two homes, each started by its own starter (164), which starts its gatherer (163); each gatherer"
        out[#out + 1] = "  and each device server (187) a process of its own:"
    else
        gaps[#gaps + 1] = "the home starters (outside a loopback-only namespace their public-address check would "
            .. "look outside, so each gatherer was started by hand)"
        out[#out + 1] = "  two homes, each gatherer started by hand; each gatherer and each device server a process:"
    end
    for _, h in ipairs({ w.a, w.b }) do
        for _, line in ipairs(w.process_line(h)) do out[#out + 1] = line end
    end
    out[#out + 1] = "  one room between them, \"the room\": A's tag " .. short(w.a.tag) .. ", B's " .. short(w.b.tag)
    out[#out + 1] = "  each home's RAM folder, under " .. w.ram_root .. ":"
    for _, h in ipairs({ w.a, w.b }) do
        out[#out + 1] = "      " .. h.name .. ": " .. h.home_ram:sub(#w.ram_root + 2) .. "/  (the gatherer's "
            .. short(h.mailbox) .. "/ and the device server's devices/)"
    end
    out[#out + 1] = "  A's device server's state file:"
    local state = c.m.ram.read_state(w.a.home_ram .. "/devices")
    local names = {}
    for name in pairs(state) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do out[#out + 1] = "      " .. name .. " = " .. tostring(state[name]) end
    return { lines = out, gaps = gaps }
end
-- }}}

-- {{{ scene pairing
M["pairing"] = function(c)
    local w = c.world
    local out = {}
    local pair = "luajit " .. quote(c.dir .. "/src/devices/189-pair.lua") .. " " .. quote(c.dir) .. " " .. quote(w.a.dir)
    local extra = { phone = "wait = 2\nquick-wait = 0.5\nkeep-alive = 2\ncheck-in = 6\n",
                    browser = "wait = 2\nquick-wait = 0.5\nkeep-alive = 2\nwebsocket-path = " .. SOCKET_PATH .. "\n" }
    for _, name in ipairs({ "phone", "browser" }) do
        local lines, ok = shell(pair .. " add " .. name)
        if not ok then error("189 add " .. name .. " failed: " .. table.concat(lines, " / "), 0) end
        out[#out + 1] = "  $ 189-pair.lua <project> <home A> add " .. name
        local settings = {}
        for _, line in ipairs(lines) do
            if line:match("^%a[%w-]* = ") then settings[#settings + 1] = line end
            out[#out + 1] = "      " .. (line:gsub("^(token = )(.*)$", function(head, token)
                local words = select(2, token:gsub("%-", "")) + 1
                return head .. token:match("^([^-]+)") .. "-... (" .. words .. " words)"
            end))
        end
        w.device(name, settings, extra[name])
    end
    out[#out + 1] = "  the browser's config adds websocket-path = " .. SOCKET_PATH
        .. " (309), so it reaches A by a WebSocket upgrade; it is the"
    out[#out + 1] = "  reference device (190) speaking WebSocket, standing in for phase 4's web client"
    out[#out + 1] = "  $ 189-pair.lua <project> <home A> list"
    for _, line in ipairs((shell(pair .. " list"))) do out[#out + 1] = "      " .. line end
    local mode = (shell("stat -c %a " .. quote(w.a.dir .. "/devices")))[1]
    out[#out + 1] = "  A's devices file is private (mode " .. tostring(mode) .. "): every token in it opens the whole home"
    for _, name in ipairs({ "phone", "browser" }) do
        local lines, ok = w.run_device(w.devices[name], "test")
        out[#out + 1] = "  $ 190-device.lua <" .. name .. "> test"
        for _, line in ipairs(lines) do out[#out + 1] = "      " .. line end
        if not ok then error("the " .. name .. "'s test failed", 0) end
    end
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene catch-up
M["catch-up"] = function(c)
    local w, m = c.world, c.m
    local out = {}
    local phone, browser = w.devices.phone, w.devices.browser
    if not phone or not browser then error("no devices: the pairing scene did not pair them", 0) end
    -- a first message, so the mirrors hold one
    w.type(w.b, "hello from B, before any device")
    if not w.wait_until(function() return #holding(m, w.a.home_ram, "hello from B, before any device") == 1 end, 15) then
        error("B's first message never reached A's inbox", 0)
    end
    out[#out + 1] = "  B typed \"hello from B, before any device\"; it is in A's inbox."
    for _, d in ipairs({ phone, browser }) do
        local lines, ok = w.run_device(d, "catch-up")
        out[#out + 1] = "  $ 190-device.lua <" .. d.name .. "> catch-up"
        for _, line in ipairs(lines) do out[#out + 1] = "      " .. line end
        if not ok then error("the " .. d.name .. "'s catch-up failed", 0) end
    end
    for _, d in ipairs({ phone, browser }) do
        out[#out + 1] = compared(m, d.name, w.a.home_ram, d.mirror)
    end
    out[#out + 1] = "  the phone's mirror (301's layout; a typed/ folder made beside the mailbox for writing):"
    for _, line in ipairs((shell("cd " .. quote(phone.mirror) .. " && find . -mindepth 1 | sort"))) do
        out[#out + 1] = "      " .. short(line)
    end
    local message = holding(m, phone.mirror, "hello from B, before any device")[1]
    out[#out + 1] = "  " .. short(message.path) .. ":"
    body_lines(out, message.text, "      | ")
    -- caught up again with nothing new: nothing is sent twice
    local lines = w.run_device(phone, "catch-up")
    out[#out + 1] = "  the phone catches up again, nothing having changed (state, .tree and .room are always sent"
    out[#out + 1] = "  whole; no message is sent again):"
    for _, line in ipairs(lines) do out[#out + 1] = "      " .. line end
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene writing
M["writing"] = function(c)
    local w, m = c.world, c.m
    local out = {}
    local phone, browser = w.devices.phone, w.devices.browser
    if not (phone and browser and m.disk.is_dir(phone.mirror)) then error("no mirrors: the catch-up scene did not run", 0) end
    -- the browser goes live and stays so for the rest of the demo
    browser.log = browser.folder .. "/live-output"
    browser.pid = w.background(browser, "live --for 300", browser.log)
    if not w.wait_until(function() return (read_all(browser.log) or ""):find("caught up", 1, true) end, 10) then
        error("the browser did not go live: " .. tostring(read_all(browser.log)), 0)
    end
    out[#out + 1] = "  the browser goes live (190 live, through the WebSocket); its first lines:"
    for line in (read_all(browser.log) or ""):gmatch("[^\n]+") do out[#out + 1] = "      " .. line end
    browser.seen = #(read_all(browser.log) or "")

    local text = "written on the phone, " .. os.date("!%H:%M:%S")
    w.text = text
    local lines, ok = shell("luajit " .. quote(c.dir .. "/src/viewer/183-viewer.lua") .. " " .. quote(phone.mirror)
        .. " write " .. w.a.tag:sub(1, 8) .. " --signature phone " .. quote(text))
    out[#out + 1] = "  the phone writes into its mirror with the reference viewer (183), as on the home machine:"
    out[#out + 1] = "  $ 183-viewer.lua <phone mirror> write " .. w.a.tag:sub(1, 8) .. " --signature phone \"" .. text .. "\""
    for _, line in ipairs(lines) do
        local at = line:find(phone.mirror, 1, true)
        if at then line = line:sub(1, at - 1) .. "<phone mirror>" .. line:sub(at + #phone.mirror) end
        out[#out + 1] = "      " .. short(line)
    end
    if not ok then error("the viewer's write into the mirror failed", 0) end
    local t0 = socket.gettime()
    lines, ok = w.run_device(phone, "send")
    out[#out + 1] = "  $ 190-device.lua <phone> send"
    for _, line in ipairs(lines) do out[#out + 1] = "      " .. short(line) end
    if not ok then error("the phone's send failed", 0) end

    local at = {}
    w.wait_until(function()
        local now = socket.gettime() - t0
        if not at.a and w.copies(w.a, text) > 0 then at.a = now end
        if not at.browser and #holding(m, browser.mirror, text) > 0 then at.browser = now end
        if not at.b and w.copies(w.b, text) > 0 then at.b = now end
        return at.a and at.browser and at.b
    end, 20)
    out[#out + 1] = "  after the send (real time):"
    out[#out + 1] = "      in A's log (A's gatherer filed the typed file)   " .. (at.a and seconds(at.a) or "NOT within 20 s")
    out[#out + 1] = "      in the browser's mirror (pushed, no catch-up)     " .. (at.browser and seconds(at.browser) or "NOT within 20 s")
    out[#out + 1] = "      in B's log (delivered by A's gatherer)            " .. (at.b and seconds(at.b) or "NOT within 20 s")
    if not (at.a and at.browser and at.b) then error("the phone's message did not reach everywhere", 0) end
    local name = holding(m, browser.mirror, text)[1].path
    w.wait_until(function() return (read_all(browser.log) or ""):find("received " .. name, 1, true) end, 3)
    local pushed = (read_all(browser.log) or ""):sub(browser.seen + 1)
    browser.seen = browser.seen + #pushed
    out[#out + 1] = "  the browser's live output since it caught up:"
    for line in pushed:gmatch("[^\n]+") do out[#out + 1] = "      " .. short(line) end
    local message = holding(m, browser.mirror, text)[1]
    out[#out + 1] = "  the browser's " .. short(message.path) .. ":"
    body_lines(out, message.text, "      | ")
    w.message_path = message.path
    w.wait_until(function() return #holding(m, w.b.home_ram, text) > 0 end, 5)
    out[#out + 1] = "  B's own inbox holds it too: " .. (#holding(m, w.b.home_ram, text) > 0 and "yes" or "NO")
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene locked
M["locked"] = function(c)
    local w, m = c.world, c.m
    local out = {}
    local phone = w.devices.phone
    if not (phone and w.message_path) then error("the writing scene did not run", 0) end
    phone.log = phone.folder .. "/check-in-output"
    phone.pid = w.background(phone, "check-in --for 300", phone.log)
    out[#out + 1] = "  the phone's screen locks: no connection, only check-ins (190 check-in), each after"
    out[#out + 1] = "  check-in = 6 seconds plus the next card of a shuffled deck, -5 ... +5 (308)"
    local text = "from B, while the phone is locked"
    local t0 = socket.gettime()
    w.type(w.b, text)
    local got = w.wait_until(function() return #holding(m, phone.mirror, text) > 0 end, 40)
    local took = socket.gettime() - t0
    -- (190 writes the files, then its line)
    w.wait_until(function() return (read_all(phone.log) or ""):find("checked in: ", 1, true) end, 3)
    out[#out + 1] = "  B typed \"" .. text .. "\"; the phone's check-in output since:"
    for line in (read_all(phone.log) or ""):gmatch("[^\n]+") do out[#out + 1] = "      " .. short(line) end
    out[#out + 1] = "  in the phone's mirror " .. (got and (seconds(took) .. " after B typed it") or "NOT within 40 s")
    if not got then error("the phone did not catch up at a check-in", 0) end
    phone.seen = #(read_all(phone.log) or "")
    out[#out + 1] = compared(m, "phone", w.a.home_ram, phone.mirror)
    local browser = w.devices.browser
    out[#out + 1] = "  the browser, live, has it too: " .. (#holding(m, browser.mirror, text) > 0 and "yes" or "NO")
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene edit
M["edit"] = function(c)
    local w, m = c.world, c.m
    local out = {}
    local phone, browser = w.devices.phone, w.devices.browser
    if not (phone and phone.pid and w.message_path) then error("the locked scene did not run", 0) end
    local id = w.message_path:match("/(%d+%-[%w_%-]+)$"):match("^%d+%-(.*)$")
    local edited = "written on the phone, and edited"
    local now = math.floor(socket.gettime())
    out[#out + 1] = "  no viewer or device command makes an edit yet, so the demo files a correction of the phone's"
    out[#out + 1] = "  message into A's RAM home with 081's correct, beside the running gatherer, as its filer would:"
    m.message_log.correct(m.rooms.open_home(w.a.folder .. "/home"), w.a.tag, { id = m.message_log.new_message_id(),
        from = "me", written = now, arrived = now, target = id, text = edited .. "\n\nphone" })
    out[#out + 1] = "      correction of " .. short(id) .. ": \"" .. edited .. "\""
    local t0 = socket.gettime()
    local function shows(root)
        local text = read_all(root .. "/" .. w.message_path) or ""
        return text:find(edited, 1, true) ~= nil and text:find("edited: yes", 1, true) ~= nil
    end
    local at = {}
    w.wait_until(function()
        local now_ = socket.gettime() - t0
        if not at.inbox and shows(w.a.home_ram) then at.inbox = now_ end
        if not at.browser and shows(browser.mirror) then at.browser = now_ end
        if not at.phone and shows(phone.mirror) then at.phone = now_ end
        return at.inbox and at.browser and at.phone
    end, 40)
    out[#out + 1] = "  after the correction was filed (real time):"
    out[#out + 1] = "      A's inbox file rewritten (the gatherer's sync)   " .. (at.inbox and seconds(at.inbox) or "NOT within 40 s")
    out[#out + 1] = "      the browser's mirror (pushed, live)             " .. (at.browser and seconds(at.browser) or "NOT within 40 s")
    out[#out + 1] = "      the phone's mirror (at its next check-in)        " .. (at.phone and seconds(at.phone) or "NOT within 40 s")
    if not (at.inbox and at.browser and at.phone) then error("the edit did not reach both devices", 0) end
    w.wait_until(function() return (read_all(phone.log) or ""):sub(phone.seen + 1):find("checked in: ", 1, true) end, 3)
    out[#out + 1] = "  the phone's check-in output since the last scene:"
    for line in (read_all(phone.log) or ""):sub(phone.seen + 1):gmatch("[^\n]+") do out[#out + 1] = "      " .. short(line) end
    out[#out + 1] = "  the same file, " .. short(w.message_path) .. ", in the phone's mirror now:"
    body_lines(out, read_all(phone.mirror .. "/" .. w.message_path), "      | ")
    local same = read_all(phone.mirror .. "/" .. w.message_path) == read_all(browser.mirror .. "/" .. w.message_path)
    out[#out + 1] = "  the browser's copy is byte for byte the same: " .. (same and "yes" or "NO")
    if not same then error("the phone's and the browser's copies of the edited message differ", 0) end
    return { lines = out, gaps = {} }
end
-- }}}

-- the helpers, for the phase 4 demo (409), which borrows this world
M.helpers = { quote = quote, seconds = seconds, read_all = read_all, shell = shell, write_private = write_private,
    wait_until = wait_until, alive = alive, listens = listens, holding = holding, compare = compare,
    body_lines = body_lines, short = short }

return M
