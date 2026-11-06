-- 215-test-reaching-the-home.lua — the referees of issue 403, reaching
-- the home from the page: pairing a page (189's `add --browser`) gives
-- lines the page reads whole and a connection the home answers; each
-- failure a browser can tell apart is named; the home-network address is
-- tried before the public one, and a home that opens but refuses is not
-- passed over; the token is never in what the page remembers; settings
-- are checked.  Each referee with a broken version also runs against it.
--
-- The page is the stand-in browser (208) under Node, speaking WebSocket
-- to a real device server (187).  Run it under the loopback-only wrapper
-- (a network namespace with only `lo`): the device port listens on
-- 127.0.0.2.
--
-- Run: luajit src/web/tests/215-test-reaching-the-home.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>".

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/web/tests/[^/]+$")
end
local t = dofile(DIR .. "/src/web/tests/214-kit-for-page-tests.lua").new(DIR, "reaching-test", { port = 46403 })
local check, must, with_broken, q = t.check, t.must, t.with_broken, t.q
local socket = require("socket")

if not t.has_node then
    t.check("every referee", function() error("STOPPED: node is not installed, so the page's scripts cannot be run outside a browser here") end)
    t.finish()
end

t.make_home()
t.start()
local LINES = t.pair("laptop")
local TOKEN = LINES:match("\ntoken = ([^\n]*)")

-- the paired lines with some changed: { name = value or false (dropped) }
local function lines_with(changes)
    local out = {}
    for line in LINES:gmatch("[^\n]+") do
        local name = line:match("^(%S+) =")
        if changes[name] == nil then out[#out + 1] = line
        elseif changes[name] then out[#out + 1] = name .. " = " .. changes[name] end
    end
    return table.concat(out, "\n") .. "\n"
end

-- {{{ referee 1: pairing gives a working page
check("1: add --browser prints a page's lines, and the page's test is answered", function()
    for _, name in ipairs({ "port", "home-network", "public", "token", "websocket-path", "wait", "quick-wait", "keep-alive" }) do
        must(("\n" .. LINES):find("\n" .. name .. " = ", 1, true), "no " .. name .. " line: " .. LINES)
    end
    must(LINES:find("\nwebsocket%-path = /the%-socket\n") and LINES:find("\nkeep%-alive = 2\n"), "not the home's path and half its idle limit")
    local status, out = t.page("test --settings " .. q(t.file_of(LINES)))
    must(status == 0 and out:find("^answered in %d+ ms by 127%.0%.0%.2 46403"), "not answered: " .. out)
end)
check("1b: a phone's lines are as they were, and the token box wins over a token line", function()
    local status, out = t.run("luajit " .. q(t.PAIR) .. " " .. q(DIR) .. " " .. q(t.HOME) .. " add phone")
    must(status == 0 and not out:find("websocket") and not out:find("keep%-alive"), "a phone was given a page's lines: " .. out)
    must(out:find("give the device these lines"), out)
    status, out = t.page("test --settings " .. q(t.file_of(lines_with({ token = "not the token" })))
        .. " --token " .. q(t.file_of(TOKEN)))
    must(status == 0, "the token box was not used: " .. out)
end)
-- }}}

-- {{{ referee 2: each failure is named
local function failures(broken)
    local _, said = t.page("test --settings " .. q(t.file_of(LINES)) .. " --token " .. q(t.file_of("not this home's token")), broken)
    must(said:find("closed the connection without a word: the token is not one this home knows"), "wrong token: " .. said)
    local _, path = t.page("test --settings " .. q(t.file_of(lines_with({ ["websocket-path"] = "/not-the-path" }))), broken)
    must(path:find("^no WebSocket could be opened at 127%.0%.0%.2 46403"), "wrong path: " .. path)
    local _, closed = t.page("test --settings " .. q(t.file_of(lines_with({ port = "46453" }))), broken)
    must(closed:find("^no WebSocket could be opened at 127%.0%.0%.2 46453"), "closed port: " .. closed)
    -- a listener that takes the connection and never answers the opening
    local listener = assert(socket.bind("127.0.0.2", 46463))
    local started = t.now()
    local _, silent = t.page("test --settings " .. q(t.file_of(lines_with({ port = "46463", wait = "1" }))), broken)
    local took = t.now() - started
    listener:close()
    must(silent:find("^nothing answered the opening at 127%.0%.0%.2 46463 within 1 s"), "silent listener: " .. silent)
    must(took < 4, "the page waited " .. string.format("%.1f", took) .. " s, not its wait of 1 s")
end
with_broken("2: a wrong token, a wrong path, a closed port and a silent listener are each named", failures, "one-message")
-- }}}

-- {{{ referee 3: home network first
local function home_network_first(broken)
    local _, out = t.page("reach --settings " .. q(t.file_of(lines_with({ public = "127.0.0.2" }))), broken)
    must(out:find("^reached 127%.0%.0%.2 46403 by way of home%-network"), "both reachable: " .. out)
    _, out = t.page("reach --settings " .. q(t.file_of(lines_with({ ["home-network"] = "127.0.0.9", public = "127.0.0.2" }))), broken)
    must(out:find("^reached 127%.0%.0%.2 46403 by way of public"), "home network away: " .. out)
end
with_broken("3: the home-network address first, then the public one", home_network_first, "public-first")
check("3b: a home that opens but refuses the ping is said, not passed over for the public address", function()
    local status, out = t.page("reach --settings " .. q(t.file_of(lines_with({ public = "127.0.0.2" })))
        .. " --token " .. q(t.file_of("not this home's token")))
    must(status ~= 0 and out:find("^127%.0%.0%.2 46403 closed the connection without a word"), out)
end)
-- }}}

check("3c: a pong for another ping is not an answer (a stand-in home)", function()
    local server = require("187-device-server")
    local frames, seal_ = require("125-frames"), require("124-seal")
    local records = require("186-device-records")
    local pair = require("123-room-key").key_pair(TOKEN)
    local listener = assert(socket.bind("127.0.0.2", 46473))
    listener:settimeout(10)
    local output = t.page_background("test --settings " .. q(t.file_of(lines_with({ port = "46473", wait = "2" }))))
    local conn = listener:accept()
    must(conn, "the page never connected")
    conn:settimeout(5)
    local head = server.read_head(conn, "")
    conn:send(assert(server.upgrade_answer(head, "/the-socket")))
    local ws = server.websocket(conn, "server")
    local frame = frames.read_frame(ws)
    local ping = records.decode(assert(seal_.open(pair, frame)))
    must(ping and ping.kind == "ping", "the page's first frame was not a ping")
    frames.write_frame(ws, seal_.seal(pair, records.encode({ kind = "pong", id = "another-ping", at = 1 })))
    local give_up = t.now() + 6
    while t.now() < give_up and output() == "" do t.sleep(0.1) end
    conn:close()
    listener:close()
    must(output():find("^127%.0%.0%.2 46473 answered, but not this ping's pong"), "taken as an answer: " .. output())
end)

-- {{{ referee 4: the token is never kept
local function token_not_kept(broken)
    local status, out = t.page("remember --settings " .. q(t.file_of(LINES)), broken)
    must(status == 0, out)
    must(not out:find("token") and not out:find(TOKEN, 1, true), "the token was kept: " .. out)
    must(out:find("port = 46403") and out:find("websocket%-path = /the%-socket"), "the other lines were not kept: " .. out)
end
with_broken("4: what the page remembers holds every line but the token", token_not_kept, "keep-token")
-- }}}

-- {{{ referee 5: settings are checked
check("5: a missing line, a port of 70000, a path without /, no address, a wait of 0: refused, named", function()
    local cases = {
        { { port = false }, "no port line" },
        { { port = "70000" }, "port must be a whole number 1 to 65535" },
        { { ["websocket-path"] = "the-socket" }, "websocket%-path must start with /" },
        { { ["home-network"] = "unknown", public = "unknown" }, "no address to try" },
        { { wait = "0" }, "wait must be a number of seconds above 0" },
        { { ["keep-alive"] = "1.5" }, "keep%-alive must be whole seconds" },
        { { token = "two\\nlines" }, nil },
    }
    for _, case in ipairs(cases) do
        local _, out = t.page("settings --settings " .. q(t.file_of(lines_with(case[1]))))
        if case[2] then must(out:find("^refused: [^\n]*" .. case[2]), "not refused as " .. case[2] .. ": " .. out) end
    end
    local _, out = t.page("settings --settings " .. q(t.file_of(LINES .. "port = 1\n")))
    must(out:find("^refused: [^\n]*'port' is set twice"), "a line set twice: " .. out)
    _, out = t.page("settings --settings " .. q(t.file_of(lines_with({ token = false }))))
    must(out:find("^refused: there is no token"), "no token: " .. out)
end)
-- }}}

t.finish()
