-- 214-kit-for-page-tests.lua — what the web client's referees (issues 403
-- to 407) share: the check counting of every referee here, a home with
-- three rooms written into its RAM folder as its gatherers write it (no
-- gatherer running), its device server started and stopped, pairing a
-- page with 189's `add --browser`, and running the stand-in browser (208).
-- Taken from 198's own helpers, so the page is tried against the same
-- home 309's referees use.
--
--   local kit = dofile(DIR .. "/src/web/tests/214-kit-for-page-tests.lua")
--   local t = kit.new(DIR, "name", { port = 46403 })
--
-- Run every referee that uses it under the loopback-only wrapper (a
-- network namespace with only `lo`): the device port listens on
-- 127.0.0.2.  Its folders are under RAO_TEST_ROOT when that is set,
-- otherwise a folder of its own under /dev/shm (or /tmp); `t.finish`
-- removes it, prints "counts <passed> <failed>" and exits.

local M = {}

-- {{{ function M.new
-- DIR, a name for the folder, options {port} → the kit for one referee file
function M.new(DIR, name, options)
    dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)
    local ffi = require("ffi")
    local socket = require("socket")
    local rooms = require("002-room-folders")
    local disk = require("003-disk")
    local message_log = require("081-message-log")
    local ram = require("161-ram-folders")
    local inbox = require("181-inbox-files")
    local mirror = require("192-mirror")
    pcall(ffi.cdef, "int getpid(void);")

    local t = { DIR = DIR, passed = 0, failed = 0, q = disk.shell_quote }
    local q = t.q
    local base = os.getenv("RAO_TEST_ROOT")
    if not base or base == "" then
        base = os.execute("test -d /dev/shm && test -w /dev/shm") == 0 and "/dev/shm" or "/tmp"
    end
    t.ROOT = base .. "/rao-chat-" .. name .. "-" .. ffi.C.getpid()
    t.ADDRESS, t.PORT = "127.0.0.2", options.port
    t.PATH = "/the-socket"
    t.STAND_IN = DIR .. "/src/web/tests/208-stand-in-browser.js"
    t.SERVER = DIR .. "/src/devices/187-device-server.lua"
    t.PAIR = DIR .. "/src/devices/189-pair.lua"
    os.execute("mkdir -p " .. q(t.ROOT))

    -- {{{ check / must / with_broken / finish
    local ONLY = os.getenv("ONLY")
    function t.check(claim, test)
        if ONLY and not claim:find(ONLY, 1, true) then return end
        local ok, problem = pcall(test)
        if ok then
            t.passed = t.passed + 1
            print("PASS " .. claim)
        else
            t.failed = t.failed + 1
            print("FAIL " .. claim .. ": " .. tostring(problem))
        end
    end
    function t.must(condition, words)
        if not condition then error(words, 2) end
    end
    -- a referee, then (when broken is given) the same referee against that
    -- broken version, which it must fail
    function t.with_broken(claim, referee, broken)
        t.check(claim, function() referee() end)
        if broken then
            t.check(claim .. " (catches " .. broken .. ")", function()
                local ok, problem = pcall(referee, broken)
                t.must(not ok, "the referee passed the broken version " .. broken)
                print("     caught (" .. broken .. "): " .. (tostring(problem):gsub("^[^:]*:%d+: ", ""):gsub("\n+$", "")))
            end)
        end
    end
    function t.finish()
        t.stop()
        if t.ROOT:match("/rao%-chat%-[%w%-]+%-%d+$") then os.execute("rm -rf " .. q(t.ROOT)) end
        print(string.format("counts %d %d", t.passed, t.failed))
        os.exit(t.failed == 0 and 0 or 1)
    end
    -- }}}

    -- {{{ files and commands
    function t.read_file(path)
        local handle = io.open(path, "rb")
        if not handle then return nil end
        local text = handle:read("*a")
        handle:close()
        return text
    end
    function t.write_file(path, text, mode)
        local handle = assert(io.open(path, "wb"))
        handle:write(text)
        handle:close()
        if mode then os.execute("chmod " .. mode .. " " .. q(path)) end
    end
    local files = 0
    function t.file_of(text)
        files = files + 1
        local path = t.ROOT .. "/file-" .. files
        t.write_file(path, text, "600")
        return path
    end
    -- command → exit status, what it printed (both streams)
    local runs = 0
    function t.run(command)
        runs = runs + 1
        local out = t.ROOT .. "/run-output-" .. runs
        local status = os.execute(command .. " > " .. q(out) .. " 2>&1")
        return status, t.read_file(out) or ""
    end
    -- the stand-in browser: its command line after the project → status, what it printed
    function t.page(words, broken)
        return t.run((broken and ("RAO_WEB_BROKEN=" .. q(broken) .. " ") or "") .. "node " .. q(t.STAND_IN)
            .. " " .. q(DIR) .. " " .. words)
    end
    -- the same, started in the background; → a function giving what it printed so far
    function t.page_background(words, broken)
        runs = runs + 1
        local out = t.ROOT .. "/run-output-" .. runs
        os.execute((broken and ("RAO_WEB_BROKEN=" .. q(broken) .. " ") or "") .. "node " .. q(t.STAND_IN) .. " "
            .. q(DIR) .. " " .. words .. " > " .. q(out) .. " 2>&1 &")
        return function() return t.read_file(out) or "" end
    end
    t.has_node = os.execute("command -v node > /dev/null 2>&1") == 0
    -- }}}

    -- {{{ the home: two mailboxes, three rooms, their inbox as their gatherers write it
    t.HOME = t.ROOT .. "/home"
    local home = {}
    t.home = home
    local function first_variants()
        local config = {}
        local listing = io.popen("ls " .. DIR .. "/src/*/[0-9][0-9][0-9]-options.lua")
        for path in listing:lines() do
            for _, choice in ipairs(dofile(path)) do
                if choice.config_key ~= "" then config[choice.config_key] = choice.variants[1].name end
            end
        end
        listing:close()
        return config
    end
    -- every gatherer's inbox and state written again from its RAM home
    function t.write_inbox()
        for mailbox, tags in pairs(home.mailboxes) do
            local folder = t.HOME_RAM .. "/" .. mailbox
            inbox.write_all(folder, rooms.open_home(folder .. "/home"), tags, home.disk)
            ram.write_state(folder, { pid = "1", started = "1000000000", ["last-sync"] = tostring(os.time()) })
        end
    end
    local function ram_home_of(tag) return rooms.open_home(t.HOME_RAM .. "/" .. home.mailbox_of[tag] .. "/home") end
    local written = 1000000100
    -- tag, text, from (nil: an address) → the message's id; the inbox is
    -- not written again until write_inbox
    function t.add_message(tag, text, from)
        written = written + 10
        local id = message_log.new_message_id()
        message_log.append(ram_home_of(tag), tag, { id = id, from = from or "10.0.0.9 5000", written = written,
            arrived = written + 1, text = text })
        return id
    end
    function t.correct(tag, target, text)
        written = written + 10
        local id = message_log.new_message_id()
        message_log.correct(ram_home_of(tag), tag, { id = id, from = "me", written = written, arrived = written,
            target = target, text = text })
        return id
    end
    function t.make_home(settings)
        local h = rooms.open_home(t.HOME)
        for key, value in pairs(first_variants()) do rooms.set_config(h, key, value) end
        local mine = { ["devices.port"] = tostring(t.PORT), ["devices.address"] = t.ADDRESS,
            ["devices.frame-deadline"] = "2", ["devices.idle-limit"] = "4", ["devices.websocket-path"] = t.PATH,
            ["gatherer.ram-root"] = t.ROOT .. "/ram" }
        for key, value in pairs(settings or {}) do mine[key] = value end
        for key, value in pairs(mine) do rooms.set_config(h, key, value) end
        home.disk = h
        home.lobby = rooms.make_room(h, { label = "lobby", token = "page test lobby", kind = "group", parent = "",
            members = {}, filed_under = "", mailbox_port = t.PORT + 1 })
        home.coffee = rooms.make_room(h, { label = "coffee", token = "page test coffee", kind = "group", parent = "",
            members = {}, filed_under = home.lobby, mailbox_port = t.PORT + 2 })
        home.quiet = rooms.make_room(h, { label = "quiet", token = "page test quiet", kind = "group", parent = "",
            members = {}, filed_under = home.lobby, mailbox_port = t.PORT + 3 })
        t.HOME_RAM = ram.home_ram(t.ROOT .. "/ram", t.HOME)
        home.mailboxes, home.mailbox_of = {}, {}
        for _, mailbox in ipairs(rooms.read_mailboxes(h)) do
            local tags = rooms.list_rooms_by_mailbox(h, mailbox.tag)
            home.mailboxes[mailbox.tag] = tags
            for _, tag in ipairs(tags) do home.mailbox_of[tag] = mailbox.tag end
            local folder = ram.layout(t.HOME_RAM, mailbox.tag)
            ram.load(t.HOME, folder .. "/home", tags)
        end
        home.first = t.add_message(home.coffee, "the first message\n\nAnn")
        t.add_message(home.coffee, "the second")
        t.add_message(home.lobby, "in the lobby")
        t.write_inbox()
        t.write_file(t.HOME .. "/devices", "", "600")
        return home
    end
    -- }}}

    -- {{{ the device server
    local running = false
    local function connect(seconds)
        local sock = socket.tcp4()
        sock:settimeout(seconds or 2)
        local ok = sock:connect(t.ADDRESS, t.PORT)
        if not ok then sock:close(); return nil end
        return sock
    end
    function t.start(broken)
        os.execute((broken and ("RAO_DEVICES_BROKEN=" .. q(broken) .. " ") or "") .. "luajit " .. q(t.SERVER) .. " "
            .. q(DIR) .. " " .. q(t.HOME) .. " > " .. q(t.ROOT .. "/server-output") .. " 2>&1 &")
        local give_up = socket.gettime() + 10
        while socket.gettime() < give_up do
            local sock = connect(0.2)
            if sock then sock:close(); running = true; return end
            socket.sleep(0.1)
        end
        error("the device server did not start: " .. tostring(t.read_file(t.ROOT .. "/server-output")))
    end
    function t.stop()
        if not running then return end
        t.write_file(t.HOME_RAM .. "/devices/stop", "")
        local give_up = socket.gettime() + 5
        while socket.gettime() < give_up do
            local sock = connect(0.2)
            if not sock then break end
            sock:close()
            socket.sleep(0.1)
        end
        os.remove(t.HOME_RAM .. "/devices/stop")
        running = false
    end
    -- }}}

    -- {{{ pairing a page, and reading what is held
    -- label → the lines 189 printed for a page (token included), or error
    function t.pair(label)
        local status, out = t.run("luajit " .. q(t.PAIR) .. " " .. q(DIR) .. " " .. q(t.HOME) .. " add "
            .. q(label) .. " --browser")
        t.must(status == 0, "189 add --browser failed: " .. out)
        local lines = out:match("these lines:\n(.*)$")
        t.must(lines, "189 printed no lines: " .. out)
        return lines
    end
    -- every file of 301's layout under a folder → { path = text }
    function t.layout_of(root)
        local found = {}
        for _, path in ipairs(select(2, mirror.listing(root))) do found[path] = t.read_file(root .. "/" .. path) end
        return found
    end
    -- a folder → the problems in it against the home's RAM folder, file for file
    function t.differences(root)
        local problems = {}
        local want, have = t.layout_of(t.HOME_RAM), t.layout_of(root)
        for path, text in pairs(want) do
            if have[path] == nil then problems[#problems + 1] = "lacks " .. path
            elseif have[path] ~= text then problems[#problems + 1] = path .. " differs" end
        end
        for path in pairs(have) do
            if want[path] == nil then problems[#problems + 1] = "holds " .. path .. ", which the home does not" end
        end
        table.sort(problems)
        return problems
    end
    t.sleep = socket.sleep
    t.now = socket.gettime
    -- }}}

    return t
end
-- }}}

return M
