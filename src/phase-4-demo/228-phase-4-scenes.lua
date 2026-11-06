-- 228-phase-4-scenes.lua — the scenes of the phase 4 demo (issue 409).
--
-- One world for every scene, borrowed from the phase 3 demo (310, 409
-- decision 3): two real homes, A on 127.0.0.2 and B on 127.0.0.3, one
-- room between them, each home with its starter (164), whose gatherer
-- (163) is its own process, and its device server (187).  Here each home
-- has a web page paired with it: the page's own scripts (src/web), run by
-- the stand-in browser (208) under Node, which stands in for a browser
-- (401 decision 4), each page reaching its home through 309's WebSocket
-- upgrade.  Everything runs on loopback, on the real clock, under
-- tmp/shared-memory/phase-4-demo/, which `finish` removes.
--
-- The scenes run in order and build on each other; a scene that needs what
-- an earlier one failed to make fails too, saying so.  A scene is a
-- function(c) → {lines = {...}, gaps = {...}}, as 201's are, and raises an
-- error when what it shows did not happen.  What is printed is read from
-- the homes' folders and from what the pages printed and kept.
--
-- c (from 227): dir, scratch, m (the modules by short name), node (the
-- version, or nil), world (set by `setup`).

local socket = require("socket")
local phase3 = require("201-phase-3-scenes")
local h3 = phase3.helpers
local quote, seconds, read_all, shell = h3.quote, h3.seconds, h3.read_all, h3.shell
local wait_until, listens, holding, short = h3.wait_until, h3.listens, h3.holding, h3.short

local M = {}

-- The scenes, in the order the demo shows them.
M.ORDER = {
    { key = "folder",   title = "The page's folder: whole, and nothing from elsewhere (401)" },
    { key = "homes",    title = "Two homes, each with its gatherer and its device port (310's world)" },
    { key = "pairing",  title = "A page paired with each home, and tested (403)" },
    { key = "catch-up", title = "Each page catches up: its mirror of its home's RAM folder (404)" },
    { key = "talking",  title = "Page A writes; page B is pushed it and answers; page A is pushed that (406, 407)" },
    { key = "rooms",    title = "Each page's room, as the page lays it out (405)" },
    { key = "drop",     title = "Home A's device port stops and starts again: page A comes back by itself (407)" },
}

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

-- {{{ local function stand_in / page_live
-- the stand-in browser run on the page's scripts: its lines and whether it exited 0
local function stand_in(c, words)
    return shell("node " .. quote(c.dir .. "/src/web/tests/208-stand-in-browser.js") .. " " .. quote(c.dir) .. " " .. words)
end
-- the same, in the background, its output in the page's log; `--until` its stop file
local function page_live(c, page, words)
    local w = c.world
    os.remove(page.stop)
    page.log = page.folder .. "/live-" .. (page.runs or 0) + 1
    page.runs = (page.runs or 0) + 1
    page.pid = w.launch("node " .. quote(c.dir .. "/src/web/tests/208-stand-in-browser.js") .. " " .. quote(c.dir)
        .. " live --settings " .. quote(page.settings) .. " --mirror-in " .. quote(page.mirror) .. " --mirror-out "
        .. quote(page.mirror) .. " --for 120 --until " .. quote(page.stop) .. " " .. words, page.log)
    if not wait_until(function() return (read_all(page.log) or ""):find(" state live: ", 1, true) end, 15) then
        error(page.name .. " did not go live: " .. tostring(read_all(page.log)), 0)
    end
end
local function page_said(page) return read_all(page.log) or "" end
-- stops a live page (its stop file) and waits for its last line
local function page_end(page)
    local f = assert(io.open(page.stop, "wb"))
    f:close()
    return wait_until(function() return page_said(page):find(" end %a+, tries %d+") ~= nil end, 10)
end
-- the page's lines, indented, its long hex shortened
local function lines_of(out, text, indent)
    for line in text:gmatch("[^\n]+") do out[#out + 1] = indent .. short(line) end
end
-- }}}

-- {{{ local function compared
-- a page's mirror against its home's RAM folder, as a line; an error when
-- a path is missing or extra, or a message differs
local function compared(m, who, home_name, home_root, mirror_root)
    local count, wrong, newer = h3.compare(m, home_root, mirror_root)
    if #wrong > 0 then error(who .. "'s mirror differs from " .. home_name .. " at " .. wrong[1], 0) end
    local names = {}
    for _, path in ipairs(newer) do names[#names + 1] = path:match("([^/]+)$") end
    return string.format("  %s's mirror against %s's RAM folder: %d files, every message the same%s", who, home_name, count,
        #newer > 0 and ("; since rewritten by the gatherer: " .. table.concat(names, ", ")) or ", and every other file")
end
-- }}}

------------------------------------------------------------------------------
-- The world
------------------------------------------------------------------------------

-- {{{ function M.setup
-- c → the world: phase 3's (two homes, made, not started), and a folder
-- for each page; or nil and why.
function M.setup(c)
    local w, why = phase3.setup(c)
    if not w then return nil, why end
    w.pages = {}
    for _, name in ipairs({ "A", "B" }) do
        local folder = w.root .. "/pages/page-" .. name
        os.execute("mkdir -p " .. quote(folder .. "/mirror"))
        w.pages[name] = { name = "page " .. name, folder = folder, mirror = folder .. "/mirror",
            settings = folder .. "/settings", stop = folder .. "/stop", home = name == "A" and w.a or w.b }
    end
    return w
end
-- }}}

-- {{{ function M.finish
function M.finish(c)
    phase3.finish(c)
end
-- }}}

------------------------------------------------------------------------------
-- The scenes
------------------------------------------------------------------------------

-- {{{ scene folder
M["folder"] = function(c)
    local out = {}
    local web = c.dir .. "/src/web"
    local html_name
    for _, name in ipairs(c.m.disk.list_dir(web)) do if name:match("^%d%d%d%-rao%-chat%.html$") then html_name = name end end
    if not html_name then error("src/web holds no page", 0) end
    local html = read_all(web .. "/" .. html_name)
    local named = { [html_name] = true }
    local order = {}
    for name in html:gmatch('<script src="([^"]+)"') do named[name] = true; order[#order + 1] = name end
    for name in html:gmatch('<link rel="stylesheet" href="([^"]+)"') do named[name] = true end
    local present, outside = {}, {}
    for _, name in ipairs(c.m.disk.list_dir(web)) do
        if c.m.disk.is_file(web .. "/" .. name) and not name:match("%.info%.md$") then
            present[#present + 1] = name
            if (read_all(web .. "/" .. name) or ""):find("https?://") then outside[#outside + 1] = name end
        end
    end
    table.sort(present)
    local unnamed, missing = {}, {}
    for _, name in ipairs(present) do if not named[name] then unnamed[#unnamed + 1] = name end end
    for name in pairs(named) do if not c.m.disk.is_file(web .. "/" .. name) then missing[#missing + 1] = name end end
    out[#out + 1] = "  src/web/ holds " .. #present .. " files (with a note beside each), and the page names each one:"
    for _, name in ipairs(present) do out[#out + 1] = "      " .. name end
    if #unnamed > 0 or #missing > 0 then
        error("the folder is not whole: unnamed " .. table.concat(unnamed, ", ") .. "; missing " .. table.concat(missing, ", "), 0)
    end
    if #outside > 0 then error("a page file names an address elsewhere: " .. table.concat(outside, ", "), 0) end
    out[#out + 1] = "  no file of the page names an address anywhere else (no http:// or https://)"
    local lines, ok = stand_in(c, "load")
    out[#out + 1] = "  $ node 208-stand-in-browser.js <project> load"
    for _, line in ipairs(lines) do out[#out + 1] = "      " .. line end
    if not ok or not table.concat(lines, "\n"):find("crypto ok", 1, true) then error("the page's scripts did not load", 0) end
    out[#out + 1] = "  Node " .. tostring(c.node) .. " stands in for the browser here (401 decision 4): it runs the page's own"
    out[#out + 1] = "  scripts, in the page's order, with its own WebCrypto and WebSocket.  The page's drawing (207) is not"
    out[#out + 1] = "  shown here; what each page would show is printed as text from the same lists it draws (405)."
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene homes (310's)
M["homes"] = function(c)
    return phase3["homes"](c)
end
-- }}}

-- {{{ scene pairing
M["pairing"] = function(c)
    local w = c.world
    local out = {}
    for _, name in ipairs({ "A", "B" }) do
        local page = w.pages[name]
        local pair = "luajit " .. quote(c.dir .. "/src/devices/189-pair.lua") .. " " .. quote(c.dir) .. " " .. quote(page.home.dir)
        local lines, ok = shell(pair .. " add laptop --browser")
        if not ok then error("189 add laptop --browser on " .. name .. " failed: " .. table.concat(lines, " / "), 0) end
        out[#out + 1] = "  $ 189-pair.lua <project> <home " .. name .. "> add laptop --browser"
        local settings = {}
        for _, line in ipairs(lines) do
            if line:match("^%a[%w-]* = ") then settings[#settings + 1] = line end
            out[#out + 1] = "      " .. (line:gsub("^(token = )(.*)$", function(head, token)
                local words = select(2, token:gsub("%-", "")) + 1
                return head .. token:match("^([^-]+)") .. "-... (" .. words .. " words)"
            end))
        end
        h3.write_private(page.settings, table.concat(settings, "\n") .. "\n")
        out[#out + 1] = "  " .. page.name .. "'s settings: those lines pasted (in a browser the token goes in its own box,"
        out[#out + 1] = "  and is never stored by the page, 403 decision 2)"
        lines, ok = stand_in(c, "test --settings " .. quote(page.settings))
        out[#out + 1] = "  $ node 208-stand-in-browser.js <project> test --settings <" .. page.name .. "'s settings>"
        for _, line in ipairs(lines) do out[#out + 1] = "      " .. line end
        if not ok then error(page.name .. "'s connection test failed", 0) end
    end
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene catch-up
M["catch-up"] = function(c)
    local w, m = c.world, c.m
    local out = {}
    if not (w.pages.A and h3.read_all(w.pages.A.settings) and h3.read_all(w.pages.B.settings)) then
        error("no settings: the pairing scene did not pair the pages", 0)
    end
    w.type(w.b, "hello from B, before any page")
    if not wait_until(function() return #holding(m, w.a.home_ram, "hello from B, before any page") == 1 end, 20) then
        error("B's first message never reached A's inbox", 0)
    end
    out[#out + 1] = "  B typed \"hello from B, before any page\" on the home machine; it is in both homes' inboxes."
    for _, name in ipairs({ "A", "B" }) do
        local page = w.pages[name]
        local lines, ok = stand_in(c, "catch-up --settings " .. quote(page.settings) .. " --mirror-out " .. quote(page.mirror))
        out[#out + 1] = "  $ node 208-stand-in-browser.js <project> catch-up --settings <" .. page.name .. "'s> --mirror-out <its mirror>"
        for _, line in ipairs(lines) do out[#out + 1] = "      " .. line end
        if not ok then error(page.name .. "'s catch-up failed", 0) end
        out[#out + 1] = compared(m, page.name, name, page.home.home_ram, page.mirror)
    end
    local lines = stand_in(c, "catch-up --settings " .. quote(w.pages.A.settings) .. " --mirror-in " .. quote(w.pages.A.mirror)
        .. " --mirror-out " .. quote(w.pages.A.mirror))
    out[#out + 1] = "  page A catches up again from the mirror it holds (state, .tree and .room come whole; no message"
    out[#out + 1] = "  is sent again):"
    for _, line in ipairs(lines) do out[#out + 1] = "      " .. line end
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene talking
M["talking"] = function(c)
    local w, m = c.world, c.m
    local out = {}
    local a, b = w.pages.A, w.pages.B
    if not (m.disk.is_dir(a.mirror) and #holding(m, a.mirror, "hello from B") > 0) then
        error("no mirrors: the catch-up scene did not run", 0)
    end
    local said_a = "hello B, this is page A, " .. os.date("!%H:%M:%S")
    local said_b = "hello A, page B heard you"
    w.said_a, w.said_b = said_a, said_b
    local function file_of(name, text)
        local path = w.root .. "/pages/" .. name
        local f = assert(io.open(path, "wb"))
        f:write(text)
        f:close()
        return path
    end
    -- page B listens, and answers once it hears page A
    page_live(c, b, "--write-when " .. quote(said_a) .. " --room " .. w.b.tag .. " --text "
        .. quote(file_of("answer", said_b)) .. " --signature " .. quote(file_of("signature-b", "page B")))
    -- page A writes a second after it is live
    page_live(c, a, "--write 1 --room " .. w.a.tag .. " --text " .. quote(file_of("first", said_a)) .. " --signature "
        .. quote(file_of("signature-a", "page A")))
    out[#out + 1] = "  both pages live (the stand-in's live: reach, catch up, listen, ping, retry)"
    if not wait_until(function() return page_said(a):find(" typed ", 1, true) end, 5) then
        error("page A did not write: " .. page_said(a), 0)
    end
    local t0 = socket.gettime()
    local at = {}
    local function arrived(home_ram, text)
        local found = holding(m, home_ram, text)[1]
        return found and found.path
    end
    wait_until(function()
        local now = socket.gettime() - t0
        if not at.a and arrived(w.a.home_ram, said_a) then at.a = now end
        if not at.b and arrived(w.b.home_ram, said_a) then at.b = now end
        if at.b and not at.page_b and page_said(b):find(" got " .. arrived(w.b.home_ram, said_a), 1, true) then at.page_b = now end
        if not at.answer_b and arrived(w.b.home_ram, said_b) then at.answer_b = now end
        if not at.answer_a and arrived(w.a.home_ram, said_b) then at.answer_a = now end
        if at.answer_a and not at.page_a and page_said(a):find(" got " .. arrived(w.a.home_ram, said_b), 1, true) then
            at.page_a = now
        end
        return at.page_a ~= nil
    end, 40)
    out[#out + 1] = "  after page A typed \"" .. said_a .. "\" (real time):"
    out[#out + 1] = "      in A's inbox (A's gatherer filed the page's typed file)   " .. (at.a and seconds(at.a) or "NOT within 40 s")
    out[#out + 1] = "      in B's inbox (delivered by A's gatherer to B's)           " .. (at.b and seconds(at.b) or "NOT within 40 s")
    out[#out + 1] = "      in page B's mirror (pushed by B's device server)          " .. (at.page_b and seconds(at.page_b) or "NOT within 40 s")
    out[#out + 1] = "      page B's answer in B's inbox                              " .. (at.answer_b and seconds(at.answer_b) or "NOT within 40 s")
    out[#out + 1] = "      page B's answer in A's inbox                              " .. (at.answer_a and seconds(at.answer_a) or "NOT within 40 s")
    out[#out + 1] = "      page B's answer in page A's mirror (pushed by A's)        " .. (at.page_a and seconds(at.page_a) or "NOT within 40 s")
    local ended = page_end(a) and page_end(b)
    for _, page in ipairs({ a, b }) do
        out[#out + 1] = "  " .. page.name .. "'s live output (\"got\" lines for its first catch-up left out):"
        for line in page_said(page):gmatch("[^\n]+") do
            if not line:match("^0%.%d got ") then out[#out + 1] = "      " .. short(line) end
        end
    end
    if not at.page_a then error("the pages did not hear each other", 0) end
    if not ended then error("a page did not end when asked", 0) end
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene rooms
M["rooms"] = function(c)
    local w, m = c.world, c.m
    local out = {}
    if not w.said_b then error("no talk: the talking scene did not run", 0) end
    for _, name in ipairs({ "A", "B" }) do
        local page = w.pages[name]
        local lines, ok = stand_in(c, "tree --mirror-in " .. quote(page.mirror))
        out[#out + 1] = "  " .. page.name .. "'s room tree:"
        for _, line in ipairs(lines) do out[#out + 1] = "      " .. short(line) end
        if not ok then error(page.name .. "'s tree failed", 0) end
        lines, ok = stand_in(c, "room --mirror-in " .. quote(page.mirror) .. " --room " .. page.home.tag)
        out[#out + 1] = "  " .. page.name .. "'s room, its lines as the page lays them out (side, a name where the speaker"
        out[#out + 1] = "  changes, the anchor, the time, the text):"
        for _, line in ipairs(lines) do out[#out + 1] = "      " .. short(line) end
        if not ok then error(page.name .. "'s room failed", 0) end
        local text = table.concat(lines, "\n")
        local own = name == "A" and w.said_a or w.said_b
        local other = name == "A" and w.said_b or w.said_a
        if not text:find("\nmine message [^\n]*| " .. own:gsub("%p", "%%%0")) then error(page.name .. " does not show its own message on its side", 0) end
        if not text:find("\ntheirs message [^\n]*| " .. other:gsub("%p", "%%%0")) then error(page.name .. " does not show the other's message", 0) end
        -- the files themselves: from: me for its own, the other home's address for the other's
        local mine = holding(m, page.mirror, own)[1]
        local theirs = holding(m, page.mirror, other)[1]
        local mine_from = mine.text:match("\nfrom: ([^\n]*)")
        local theirs_from = theirs.text:match("\nfrom: ([^\n]*)")
        out[#out + 1] = "  in " .. page.name .. "'s mirror: its own message from: " .. tostring(mine_from) .. "; the other's from: "
            .. tostring(theirs_from)
        if mine_from ~= "me" or theirs_from == "me" or not theirs_from then
            error(page.name .. "'s mirror has the wrong from: lines", 0)
        end
    end
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene drop
M["drop"] = function(c)
    local w, m = c.world, c.m
    local out = {}
    local a, h = w.pages.A, w.a
    if not w.said_b then error("no talk: the talking scene did not run", 0) end
    page_live(c, a, "")
    out[#out + 1] = "  page A live again, from the mirror it holds"
    local seen = #page_said(a)
    os.execute("touch " .. quote(h.home_ram .. "/devices/stop"))
    if not wait_until(function() return not listens(h.address, h.device_port) end, 10) then
        error("A's device server did not stop", 0)
    end
    out[#out + 1] = "  A's device server asked to stop (its stop file); its port no longer listens"
    if not wait_until(function() return page_said(a):find("errors retrying: connection lost", seen, true) end, 10) then
        error("page A did not say the connection was lost: " .. page_said(a), 0)
    end
    local away = "while page A was away"
    w.type(w.b, away)
    if not wait_until(function() return #holding(m, h.home_ram, away) == 1 end, 20) then
        error("B's message never reached A's inbox", 0)
    end
    out[#out + 1] = "  B typed \"" .. away .. "\"; it is in A's inbox"
    os.remove(h.home_ram .. "/devices/stop")
    local t0 = socket.gettime()
    h.server = w.launch("luajit " .. quote(c.dir .. "/src/devices/187-device-server.lua") .. " " .. quote(c.dir) .. " "
        .. quote(h.dir), h.home_ram .. "/device-server-output")
    if not wait_until(function() return listens(h.address, h.device_port) end, 10) then
        error("A's device server did not start again", 0)
    end
    out[#out + 1] = "  A's device server started again"
    local path = holding(m, h.home_ram, away)[1].path
    local back = wait_until(function() return page_said(a):find(" got " .. path, 1, true) end, 20)
    out[#out + 1] = "  in page A's mirror " .. (back and seconds(socket.gettime() - t0) or "NOT within 20 s")
        .. " after the server started again, without anyone asking"
    page_end(a)
    out[#out + 1] = "  page A's live output since the drop:"
    lines_of(out, page_said(a):sub(seen + 1), "      ")
    if not back then error("page A did not come back by itself", 0) end
    return { lines = out, gaps = {} }
end
-- }}}

return M
