-- 246-phase-6-scenes.lua — the scenes of the phase 6 demo (issue 606).
--
-- One world for every scene: two homes made by the installer
-- (scripts/install-home, 602) and set up by it as systemd user services
-- (604), A on 127.0.0.2 and B on 127.0.0.3; the service manager's
-- commands are the stand-ins of 242 on the scratch PATH, HOME a scratch
-- folder, the services' logs in a scratch folder, the list of homes (605)
-- a scratch file.  The stand-in systemctl runs each unit's ExecStart as it
-- is written, in a bare environment, so what the real one would run is
-- what runs.  Everything runs on loopback, on the real clock, under
-- tmp/shared-memory/phase-6-demo/, which `finish` removes.
--
-- The scenes run in order and build on each other; a scene that needs
-- what an earlier one failed to make fails too, saying so.  A scene is a
-- function(c) → {lines = {...}, gaps = {...}}, as 201's are, and raises an
-- error when what it shows did not happen: what is printed is read from
-- the homes', the services' and the device's files, never text about
-- them.
--
-- Two stand-ins, said where they happen: the room between the homes is
-- made with 002's make_room and 041's add_member (no viewer makes rooms
-- yet), and the demo's timing settings are changed with 232, as a person
-- editing the config would.
--
-- c (from 245): dir, scratch, m (the modules by short name), world (set
-- by `setup`).

local socket = require("socket")

local M = {}

-- The scenes, in the order the demo shows them.
M.ORDER = {
    { key = "needs",    title = "What a home needs, as this machine answers it (601)" },
    { key = "install",  title = "Two homes installed, unattended, each as a systemd user service (602, 604, 605)" },
    { key = "again",    title = "Installed again: nothing changes (602)" },
    { key = "room",     title = "A room between them, and the demo's timing settings (by hand)" },
    { key = "services", title = "The services run the homes: each unit's ExecStart, as written (603, 604)" },
    { key = "talk",     title = "The homes talk: a phone paired with A writes, and B receives it (303, 305)" },
    { key = "update",   title = "An update: every listed home restarted, and the phone catches up after (605)" },
    { key = "stop",     title = "The stop: each service stopped, each home stopping its own programs (603)" },
}

local ADDRESS = { A = "127.0.0.2", B = "127.0.0.3" }
local DIRECT_PORT = { A = 7802, B = 7803 }
local ROOM_PORT = { A = 7804, B = 7805 }
local DEVICE_PORT = { A = 7812, B = 7813 }
local TIMING = { "gatherer.sync-interval=2", "delivery.retry-floor=1", "delivery.retry-ceiling=4",
                 "callback.answer-time=2", "devices.frame-deadline=2", "devices.idle-limit=10" }

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

-- {{{ local function quote / seconds / read_all / shell
local function quote(text) return "'" .. tostring(text):gsub("'", "'\\''") .. "'" end
local function seconds(value) return string.format("%.1f s", value) end
local function read_all(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
-- A command's output, as lines, and whether it exited 0 (and its status).
local function shell(command)
    local p = io.popen(command .. " 2>&1 </dev/null; echo \"exit=$?\"")
    local lines = {}
    for line in p:lines() do lines[#lines + 1] = line end
    p:close()
    local status = tonumber((table.remove(lines) or ""):match("^exit=(%d+)$"))
    return lines, status == 0, status
end
local function write_private(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
    os.execute("chmod 600 " .. quote(path))
end
-- }}}

-- {{{ local function wait_until / alive / listens
local function wait_until(condition, limit)
    local stop = socket.gettime() + limit
    while socket.gettime() < stop do
        if condition() then return true end
        socket.sleep(0.1)
    end
    return condition()
end
local function alive(pid)
    local f = pid and io.open("/proc/" .. pid .. "/stat", "rb")
    if not f then return false end
    local stat = f:read("*a")
    f:close()
    return stat:match("%) (%a)") ~= "Z"
end
local function listens(address, port)
    local sock = socket.tcp4()
    sock:settimeout(0.3)
    local ok = sock:connect(address, port)
    sock:close()
    return ok ~= nil
end
-- }}}

-- {{{ local function running_under(path) → "pid cmdline" of each process naming path
-- Read from /proc, so the looking is not itself found.
local function running_under(path)
    local found = {}
    local p = io.popen("ls /proc")
    for pid in p:lines() do
        if pid:match("^%d+$") and alive(tonumber(pid)) then
            local cmdline = (read_all("/proc/" .. pid .. "/cmdline") or ""):gsub("%z", " ")
            if cmdline:find(path, 1, true) then found[#found + 1] = pid .. " " .. cmdline end
        end
    end
    p:close()
    return found
end
-- }}}

-- {{{ local function short
local function short(text) return (tostring(text):gsub("(%x%x%x%x%x%x%x%x)%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x", "%1...")) end
-- }}}

-- {{{ local function holding
-- The 301-layout message files under `root` whose text holds `text`.
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

-- {{{ local function snapshot(folders) → path → text, the number of files
local function snapshot(folders)
    local files, count = {}, 0
    for _, folder in ipairs(folders) do
        local p = io.popen("cd " .. quote(folder) .. " 2>/dev/null && find . -type f | sort")
        for path in p:lines() do
            files[folder .. path:sub(2)] = read_all(folder .. path:sub(2))
            count = count + 1
        end
        p:close()
    end
    return files, count
end
-- }}}

------------------------------------------------------------------------------
-- The world
------------------------------------------------------------------------------

-- {{{ function M.setup
-- c → the world: its folders, the stand-in service managers, and the two
-- homes' names and ports (nothing installed yet); or nil and why.
function M.setup(c)
    local m = c.m
    local up, why = m.loopback.bring_up()
    if not up then return nil, "loopback could not be brought up (" .. tostring(why) .. ")" end
    if not m.loopback.only_loopback() then
        return nil, "not in a loopback-only namespace: the homes' starters check the public address, so the demo"
            .. " runs only under unshare -rn (issues/completed/demos/phase-6-demo starts it so)"
    end
    local root = c.scratch
    os.execute("rm -rf " .. quote(root) .. " && mkdir -p " .. quote(root .. "/homes") .. " " .. quote(root .. "/user")
        .. " " .. quote(root .. "/devices"))
    local w = { root = root, ram_root = root .. "/ram", user = root .. "/user", logs = root .. "/logs",
                list = root .. "/installed-homes", managers = root .. "/managers", devices = {} }
    local made = io.popen("luajit " .. quote(c.dir .. "/src/install/242-stand-in-service-managers.lua") .. " make "
        .. quote(w.managers) .. " 2>&1")
    w.bin = made:read("*l")
    made:close()
    if not w.bin or not w.bin:match("/bin$") then return nil, "the stand-in service managers (242) were not made: "
        .. tostring(w.bin) end
    w.system_root = w.managers .. "/root"
    -- every command of the demo's person: the scratch HOME, the stand-ins first
    w.env = "HOME=" .. quote(w.user) .. " PATH=" .. quote(w.bin) .. ":\"$PATH\" "
    w.homes = {}
    for _, name in ipairs({ "A", "B" }) do
        local dir = root .. "/homes/" .. name
        local h = { name = name, dir = dir, address = ADDRESS[name], direct_port = DIRECT_PORT[name],
                    port = ROOM_PORT[name], device_port = DEVICE_PORT[name],
                    service = m.files.name(dir), home_ram = m.ram.home_ram(w.ram_root, dir) }
        h.unit = w.user .. "/.config/systemd/user/" .. h.service .. ".service"
        h.log = w.logs .. "/" .. h.service .. ".log"
        w.homes[#w.homes + 1] = h
        w[name:lower()] = h
    end
    function w.install(h)
        return shell(w.env .. quote(c.dir .. "/scripts/install-home") .. " --silent --home=" .. quote(h.dir)
            .. " --home-name=" .. h.name .. " --device-port=" .. h.device_port .. " --direct-port=" .. h.direct_port
            .. " --address=" .. h.address .. " --ram-root=" .. quote(w.ram_root) .. " --setup-service"
            .. " --service-manager=systemd --user-service --no-start-service --log-dir=" .. quote(w.logs)
            .. " --homes-list=" .. quote(w.list) .. " --system-root=" .. quote(w.system_root))
    end
    function w.systemctl(words) return shell(w.env .. quote(w.bin .. "/systemctl") .. " --user " .. words) end
    function w.launcher(h) return tonumber(read_all(w.managers .. "/" .. h.service .. ".pid") or "") end
    -- the gatherers' folders of a home: name → state
    function w.gatherers(h)
        local found = {}
        local p = io.popen("cd " .. quote(h.home_ram) .. " 2>/dev/null && ls")
        for name in p:lines() do
            if name ~= "devices" and read_all(h.home_ram .. "/" .. name .. "/state") then
                found[name] = m.ram.read_state(h.home_ram .. "/" .. name)
            end
        end
        p:close()
        return found
    end
    function w.device(name, pairing_lines, extra)
        local folder = root .. "/devices/" .. name
        os.execute("mkdir -p " .. quote(folder))
        write_private(folder .. "/config", table.concat(pairing_lines, "\n") .. "\n" .. extra)
        local d = { name = name, folder = folder, mirror = folder .. "/mirror" }
        w.devices[name] = d
        return d
    end
    function w.run_device(d, words)
        return shell("luajit " .. quote(c.dir .. "/src/devices/190-device.lua") .. " " .. quote(d.folder) .. " " .. words)
    end
    -- what a home's room log holds with `text` in a record
    function w.copies(h, text)
        local n = 0
        for line in (read_all(h.home_ram .. "/" .. h.mailbox .. "/home/rooms/" .. h.tag .. "/log") or ""):gmatch("[^\n]+") do
            if line:find(text, 1, true) then n = n + 1 end
        end
        return n
    end
    -- a message typed on the home machine, signed with the home's name
    function w.type(h, text)
        m.ram.put(h.home_ram .. "/" .. h.mailbox .. "/typed", m.ram.new_name(socket.gettime()), "room: " .. h.tag
            .. "\nwritten: " .. math.floor(socket.gettime()) .. "\n\n" .. text .. "\n\n" .. h.name .. "\n")
    end
    w.alive, w.wait_until, w.listens, w.holding, w.snapshot = alive, wait_until, listens, holding, snapshot
    return w
end
-- }}}

-- {{{ function M.finish
-- Stops whatever the demo started (each service through the stand-in, then
-- anything left), then removes its folder.
function M.finish(c)
    local w = c.world
    if not w then return end
    for _, h in ipairs(w.homes) do
        if alive(w.launcher(h)) then w.systemctl("stop " .. h.service) end
    end
    for _, line in ipairs(running_under(w.root .. "/")) do os.execute("kill -9 " .. line:match("^%d+")) end
    wait_until(function() return #running_under(w.root .. "/") == 0 end, 3)
    os.execute("rm -rf " .. quote(w.root))
end
-- }}}

------------------------------------------------------------------------------
-- The scenes
------------------------------------------------------------------------------

-- {{{ scene needs
M["needs"] = function(c)
    local out = {}
    local lines, ok, status = shell("luajit " .. quote(c.dir .. "/src/install/230-what-a-home-needs.lua") .. " "
        .. quote(c.dir))
    out[#out + 1] = "  $ luajit src/install/230-what-a-home-needs.lua <project>"
    for _, line in ipairs(lines) do out[#out + 1] = "      " .. line end
    if status == 1 then error("this machine is missing something a home needs (above)", 0) end
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene install
M["install"] = function(c)
    local w = c.world
    local out = {}
    out[#out + 1] = "  no real service manager is used: a demo installs nothing on the machine it runs on.  The"
    out[#out + 1] = "  systemctl, loginctl and sudo the installer finds are 242's stand-ins on a scratch PATH,"
    out[#out + 1] = "  HOME is " .. w.user .. ", the services' logs go to " .. w.logs .. "."
    for _, h in ipairs(w.homes) do
        local lines, ok = w.install(h)
        out[#out + 1] = string.format("  $ install-home --silent --home=<homes>/%s --home-name=%s --device-port=%d"
            .. " --direct-port=%d --address=%s", h.name, h.name, h.device_port, h.direct_port, h.address)
        out[#out + 1] = "        --setup-service --service-manager=systemd --user-service --no-start-service ..."
        for _, line in ipairs(lines) do
            if line:match("^  set ") or line:match("^  made ") or line:match("^  ok: ") or line:match("^  wrote ")
                or line:match("^  listed ") or line:match("^  stated ") or line:match("^  error") then
                out[#out + 1] = "    " .. line
            end
        end
        if not ok then error("the installer failed for home " .. h.name .. ": " .. table.concat(lines, " / "), 0) end
    end
    -- the asked lines, and two stated ones, each with its comment, as A's config holds them
    local config = read_all(w.a.dir .. "/config") or ""
    out[#out + 1] = "  A's config: the lines it was asked for, and two of the lines stated, each with its comment:"
    for _, key in ipairs({ "git.home-name", "devices.port", "gatherer.address", "gatherer.sync-interval",
                           "delivery.retry-floor" }) do
        -- the line, and the comment lines right above it
        local lines = {}
        for l in (config .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
        local at
        for i, l in ipairs(lines) do if l:sub(1, #key + 3) == key .. " = " then at = i end end
        if not at then error("A's config has no " .. key, 0) end
        local first = at
        while first > 1 and lines[first - 1]:match("^#") do first = first - 1 end
        for i = first, at do out[#out + 1] = "      " .. lines[i] end
    end
    out[#out + 1] = "  A's unit file, " .. w.a.unit:sub(#w.root + 2) .. ":"
    local unit = read_all(w.a.unit)
    if not unit then error("no unit file for A at " .. w.a.unit, 0) end
    for l in unit:gmatch("[^\n]+") do
        if not l:match("^# ") or l:match("^# rao%-chat home:") then out[#out + 1] = "      " .. l end
    end
    out[#out + 1] = "  the list of homes installed as services (installed-homes):"
    for l in (read_all(w.list) or ""):gmatch("[^\n]+") do out[#out + 1] = "      " .. l end
    if select(2, (read_all(w.list) or ""):gsub("\n", "")) ~= 2 then error("the list does not hold the two homes", 0) end
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene again
M["again"] = function(c)
    local w = c.world
    local out = {}
    local folders = { w.a.dir, w.b.dir, w.user }
    local before, count = snapshot(folders)
    before[w.list] = read_all(w.list)
    for _, h in ipairs(w.homes) do
        local lines, ok = w.install(h)
        local kept = 0
        for _, line in ipairs(lines) do if line:match("^  kept ") then kept = kept + 1 end end
        out[#out + 1] = string.format("  home %s installed again with the same answers: %d lines say kept", h.name, kept)
        if not ok then error("the second install of " .. h.name .. " failed: " .. table.concat(lines, " / "), 0) end
    end
    local after = snapshot(folders)
    after[w.list] = read_all(w.list)
    local differ = {}
    for path, text in pairs(before) do if after[path] ~= text then differ[#differ + 1] = path end end
    for path in pairs(after) do if before[path] == nil then differ[#differ + 1] = path end end
    if #differ > 0 then
        table.sort(differ)
        error("installing again changed " .. differ[1]:sub(#w.root + 2) .. " (and " .. (#differ - 1) .. " more)", 0)
    end
    out[#out + 1] = string.format("  %d files (both homes, the unit files, the list): every one byte for byte as it was",
        count + 1)
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene room
M["room"] = function(c)
    local w, m = c.world, c.m
    local out = {}
    out[#out + 1] = "  (a stand-in: no viewer makes rooms yet, so the demo makes the room with 002's make_room and"
    out[#out + 1] = "  041's add_member, each home's room on a mailbox port of its own)"
    for _, h in ipairs(w.homes) do
        local disk = m.rooms.open_home(h.dir)
        h.tag = m.rooms.make_room(disk, { label = "the room", token = "the phase 6 demo's room", kind = "group",
            parent = "", members = {}, filed_under = "", mailbox_port = h.port })
        h.mailbox = m.rooms.read_entry(disk, h.tag).mailbox
        h.disk = disk
    end
    m.recipients.add_member(w.a.disk, w.a.tag, w.b.address, w.b.port)
    m.recipients.add_member(w.b.disk, w.b.tag, w.a.address, w.a.port)
    for _, h in ipairs(w.homes) do
        out[#out + 1] = string.format("  %s: room %s on mailbox port %d, its member %s", h.name, short(h.tag), h.port,
            h == w.a and (w.b.address .. ":" .. w.b.port) or (w.a.address .. ":" .. w.a.port))
    end
    out[#out + 1] = "  the demo's timing, as a person editing the config would (232; the installer keeps hand edits):"
    for _, h in ipairs(w.homes) do
        local lines, ok = shell("luajit " .. quote(c.dir .. "/src/install/232-make-home.lua") .. " " .. quote(c.dir)
            .. " " .. quote(h.dir) .. " " .. table.concat(TIMING, " "))
        if not ok then error("232 could not change " .. h.name .. "'s timing: " .. table.concat(lines, " / "), 0) end
        if h == w.a then for _, line in ipairs(lines) do out[#out + 1] = "      " .. line end end
    end
    out[#out + 1] = "      (and the same in B's)"
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene services
M["services"] = function(c)
    local w = c.world
    local out = {}
    if not (w.a.tag and w.b.tag) then error("no room: the room scene did not run", 0) end
    for _, h in ipairs(w.homes) do
        local lines, ok = w.systemctl("start " .. h.service)
        out[#out + 1] = "  $ systemctl --user start " .. h.service .. "      (the stand-in)"
        for _, line in ipairs(lines) do out[#out + 1] = "      " .. line end
        if not ok then error("the stand-in could not start " .. h.name, 0) end
    end
    for _, h in ipairs(w.homes) do
        local up = wait_until(function()
            return listens(h.address, h.device_port) and listens(h.address, h.direct_port) and listens(h.address, h.port)
        end, 25)
        if not up then
            error(h.name .. " does not answer on its ports: " .. tostring(read_all(h.log)), 0)
        end
    end
    for _, h in ipairs(w.homes) do
        h.launcher = w.launcher(h)
        local environ = (read_all("/proc/" .. tostring(h.launcher) .. "/environ") or ""):gsub("%z", " ")
        out[#out + 1] = string.format("  home %s, service %s: %s", h.name, h.service,
            (w.systemctl("is-active " .. h.service))[1] or "?")
        out[#out + 1] = "      the launcher, pid " .. tostring(h.launcher) .. ", run in the service's bare environment:"
        out[#out + 1] = "        " .. environ
        out[#out + 1] = "      its first lines in the service's log (" .. h.log:sub(#w.root + 2) .. "):"
        for line in (read_all(h.log) or ""):gmatch("[^\n]+") do
            if line:find("run-home:", 1, true) then out[#out + 1] = "        " .. short(line) end
        end
        local starter = tonumber((read_all(h.log) or ""):match("starter pid (%d+)"))
        local server = tonumber((read_all(h.log) or ""):match("device server pid (%d+)"))
        out[#out + 1] = string.format("      starter pid %s %s, device server pid %s %s on %s:%d", tostring(starter),
            alive(starter) and "running" or "NOT RUNNING", tostring(server), alive(server) and "running" or "NOT RUNNING",
            h.address, h.device_port)
        wait_until(function()
            local n = 0
            for _, state in pairs(w.gatherers(h)) do if alive(tonumber(state.pid or "")) then n = n + 1 end end
            return n == 2
        end, 10)
        for mailbox, state in pairs(w.gatherers(h)) do
            local port = mailbox == h.mailbox and h.port or h.direct_port
            out[#out + 1] = string.format("      gatherer pid %s %s, mailbox %s on port %d (%s)", tostring(state.pid),
                alive(tonumber(state.pid or "")) and "running" or "NOT RUNNING", short(mailbox), port,
                mailbox == h.mailbox and "the room's" or "direct messages")
        end
    end
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene talk
M["talk"] = function(c)
    local w, m = c.world, c.m
    local out = {}
    if not w.a.launcher then error("the homes are not running: the services scene did not run", 0) end
    local pair = "luajit " .. quote(c.dir .. "/src/devices/189-pair.lua") .. " " .. quote(c.dir) .. " " .. quote(w.a.dir)
    local lines, ok = shell(pair .. " add phone")
    if not ok then error("189 add phone failed: " .. table.concat(lines, " / "), 0) end
    local settings = {}
    out[#out + 1] = "  $ 189-pair.lua <project> <home A> add phone"
    for _, line in ipairs(lines) do
        if line:match("^%a[%w-]* = ") then settings[#settings + 1] = line end
        out[#out + 1] = "      " .. (line:gsub("^(token = )(.*)$", function(head, token)
            return head .. token:match("^([^-]+)") .. "-... (" .. (select(2, token:gsub("%-", "")) + 1) .. " words)"
        end))
    end
    local phone = w.device("phone", settings, "wait = 2\nquick-wait = 0.5\nkeep-alive = 2\n")
    for _, words in ipairs({ "test", "catch-up" }) do
        lines, ok = w.run_device(phone, words)
        out[#out + 1] = "  $ 190-device.lua <phone> " .. words
        for _, line in ipairs(lines) do out[#out + 1] = "      " .. short(line) end
        if not ok then error("the phone's " .. words .. " failed", 0) end
    end
    local text = "written on the phone, " .. os.date("!%H:%M:%S")
    lines, ok = shell("luajit " .. quote(c.dir .. "/src/viewer/183-viewer.lua") .. " " .. quote(phone.mirror)
        .. " write " .. w.a.tag:sub(1, 8) .. " --signature phone " .. quote(text))
    out[#out + 1] = "  $ 183-viewer.lua <phone mirror> write " .. w.a.tag:sub(1, 8) .. " --signature phone \"" .. text .. "\""
    if not ok then error("the viewer's write into the mirror failed: " .. table.concat(lines, " / "), 0) end
    local t0 = socket.gettime()
    lines, ok = w.run_device(phone, "send")
    out[#out + 1] = "  $ 190-device.lua <phone> send"
    for _, line in ipairs(lines) do out[#out + 1] = "      " .. short(line) end
    if not ok then error("the phone's send failed", 0) end
    local at = {}
    wait_until(function()
        local now = socket.gettime() - t0
        if not at.a and w.copies(w.a, text) > 0 then at.a = now end
        if not at.b and w.copies(w.b, text) > 0 then at.b = now end
        if not at.inbox and #holding(m, w.b.home_ram, text) > 0 then at.inbox = now end
        return at.a and at.b and at.inbox
    end, 25)
    out[#out + 1] = "  after the send (real time):"
    out[#out + 1] = "      in A's room log (A's gatherer filed it)          " .. (at.a and seconds(at.a) or "NOT within 25 s")
    out[#out + 1] = "      in B's room log (delivered by A's gatherer)      " .. (at.b and seconds(at.b) or "NOT within 25 s")
    out[#out + 1] = "      in B's RAM inbox (301's layout)                  " .. (at.inbox and seconds(at.inbox) or "NOT within 25 s")
    if not (at.a and at.b and at.inbox) then error("the phone's message did not reach B", 0) end
    local message = holding(m, w.b.home_ram, text)[1]
    out[#out + 1] = "  B's " .. short(message.path:match("[^/]+/[^/]+$") or message.path) .. ":"
    for line in message.text:gmatch("[^\n]+") do out[#out + 1] = "      | " .. short(line) end
    w.text = text
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene update
M["update"] = function(c)
    local w, m = c.world, c.m
    local out = {}
    local phone = w.devices.phone
    if not (phone and w.text) then error("the talk scene did not run", 0) end
    out[#out + 1] = "  (an update is a git pull of the program folder; a running home keeps the code it started with"
    out[#out + 1] = "  until its service restarts, so the update is finished by restarting every listed home)"
    local lines, ok = shell(w.env .. quote(c.dir .. "/scripts/restart-homes") .. " --yes --homes-list=" .. quote(w.list)
        .. " --system-root=" .. quote(w.system_root))
    out[#out + 1] = "  $ restart-homes --yes"
    for _, line in ipairs(lines) do out[#out + 1] = "    " .. short(line) end
    if not ok then error("restart-homes did not restart both homes", 0) end
    for _, h in ipairs(w.homes) do
        local launcher = w.launcher(h)
        out[#out + 1] = string.format("  home %s: launcher pid %s before, %s now (%s)", h.name, tostring(h.launcher),
            tostring(launcher), alive(launcher) and "running" or "NOT RUNNING")
        if launcher == h.launcher or not alive(launcher) then error(h.name .. " was not restarted", 0) end
        if alive(h.launcher) then error(h.name .. "'s old launcher is still running", 0) end
        h.launcher = launcher
        if not wait_until(function() return listens(h.address, h.device_port) and listens(h.address, h.port) end, 25) then
            error(h.name .. " does not answer after its restart", 0)
        end
    end
    local text = "from B, after the update"
    local t0 = socket.gettime()
    w.type(w.b, text)
    if not wait_until(function() return #holding(m, w.a.home_ram, text) > 0 end, 25) then
        error("B's message after the update never reached A's inbox", 0)
    end
    out[#out + 1] = "  B typed \"" .. text .. "\"; in A's inbox " .. seconds(socket.gettime() - t0) .. " later"
    lines, ok = w.run_device(phone, "catch-up")
    out[#out + 1] = "  $ 190-device.lua <phone> catch-up"
    for _, line in ipairs(lines) do out[#out + 1] = "      " .. short(line) end
    if not ok then error("the phone's catch-up after the update failed", 0) end
    local has_new = #holding(m, phone.mirror, text) > 0
    local has_old = #holding(m, phone.mirror, w.text) > 0
    out[#out + 1] = "  the phone's mirror holds B's message after the update: " .. (has_new and "yes" or "NO")
        .. "; its own from before: " .. (has_old and "yes" or "NO")
    if not (has_new and has_old) then error("the phone did not catch up after the update", 0) end
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene stop
M["stop"] = function(c)
    local w = c.world
    local out = {}
    for _, h in ipairs(w.homes) do
        if not alive(w.launcher(h)) then error(h.name .. " is not running: an earlier scene failed", 0) end
    end
    for _, h in ipairs(w.homes) do
        local lines, ok = w.systemctl("stop " .. h.service)
        out[#out + 1] = "  $ systemctl --user stop " .. h.service .. "      (SIGTERM to the launcher alone: KillMode=mixed)"
        for _, line in ipairs(lines) do out[#out + 1] = "      " .. line end
        local ended = table.concat(lines, "\n"):match("ended with status (%S+)")
        if not ok or ended ~= "0" then error(h.name .. "'s launcher did not stop cleanly (status " .. tostring(ended) .. ")", 0) end
        local last
        for line in (read_all(h.log) or ""):gmatch("[^\n]+") do
            if line:find("run-home:", 1, true) then last = line end
        end
        out[#out + 1] = "      its last line: " .. short(tostring(last))
        for mailbox, state in pairs(w.gatherers(h)) do
            out[#out + 1] = string.format("      gatherer of mailbox %s: stopped = %s", short(mailbox), tostring(state.stopped))
            if state.stopped ~= "asked" then error(h.name .. "'s gatherer was not stopped by being asked", 0) end
        end
    end
    local left = running_under(w.root .. "/homes/")
    out[#out + 1] = "  processes of either home still running: " .. (#left == 0 and "none" or table.concat(left, "; "))
    if #left > 0 then error("something of the homes is still running", 0) end
    for _, h in ipairs(w.homes) do
        out[#out + 1] = string.format("  %s's ports %d, %d, %d: %s", h.name, h.device_port, h.direct_port, h.port,
            (listens(h.address, h.device_port) or listens(h.address, h.port)) and "STILL OPEN" or "closed")
    end
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ every scene's lines with the demo's folder as <demo> and the program
-- folder as <project>, so they read the same wherever the demo runs
for _, entry in ipairs(M.ORDER) do
    local scene = M[entry.key]
    M[entry.key] = function(c)
        local record = scene(c)
        local function tidy(line)
            if c.world then
                local at = line:find(c.world.root, 1, true)
                while at do
                    line = line:sub(1, at - 1) .. "<demo>" .. line:sub(at + #c.world.root)
                    at = line:find(c.world.root, 1, true)
                end
            end
            local at = line:find(c.dir, 1, true)
            while at do
                line = line:sub(1, at - 1) .. "<project>" .. line:sub(at + #c.dir)
                at = line:find(c.dir, 1, true)
            end
            return line
        end
        for i, line in ipairs(record.lines) do record.lines[i] = tidy(line) end
        return record
    end
end
-- }}}

return M
