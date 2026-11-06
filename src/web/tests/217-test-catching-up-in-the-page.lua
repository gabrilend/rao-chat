-- 217-test-catching-up-in-the-page.lua — the referees of issue 404,
-- catching up in the page: a new page's mirror equals the home's RAM
-- folder file for file; a page that holds the room is sent only what is
-- new; an edit, a file the home no longer holds, and a room the home has
-- left are all made good; a path from the network outside 301's layout is
-- refused and said; the page's catch-up lines are 192's for the same
-- files.  Each referee with a broken version also runs against it.
--
-- The page is the stand-in browser (208) under Node, its in-memory mirror
-- written into a folder at the end of each catch-up (and read back from
-- one at the start of the next), speaking WebSocket to a real device
-- server (187).  Run it under the loopback-only wrapper (a network
-- namespace with only `lo`): the device port listens on 127.0.0.2.
--
-- Run: luajit src/web/tests/217-test-catching-up-in-the-page.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>".

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/web/tests/[^/]+$")
end
local t = dofile(DIR .. "/src/web/tests/214-kit-for-page-tests.lua").new(DIR, "catching-up-test", { port = 46404 })
local check, must, with_broken, q = t.check, t.must, t.with_broken, t.q
local socket = require("socket")
local mirror = require("192-mirror")

if not t.has_node then
    t.check("every referee", function() error("STOPPED: node is not installed, so the page's scripts cannot be run outside a browser here") end)
    t.finish()
end

local home = t.make_home()
t.start()
local SETTINGS = t.file_of(t.pair("laptop"))

-- {{{ catching up: from a mirror folder (or none) into a new one
local mirrors = 0
-- from (nil: empty), broken → the new mirror's folder, status, the
-- summary's numbers, what the page printed
local function catch_up(from, broken)
    mirrors = mirrors + 1
    local into = t.ROOT .. "/mirror-" .. mirrors
    local status, out = t.page("catch-up --settings " .. q(SETTINGS) .. (from and (" --mirror-in " .. q(from)) or "")
        .. " --mirror-out " .. q(into), broken)
    local files, messages, changed, dropped =
        out:match("(%d+) file%(s%) received %((%d+) message%(s%)%), (%d+) changed, (%d+) dropped")
    return into, status, { files = tonumber(files), messages = tonumber(messages), changed = tonumber(changed),
        dropped = tonumber(dropped) }, out
end
local function same_as_home(folder)
    local problems = t.differences(folder)
    must(#problems == 0, "the page's mirror " .. table.concat(problems, "; "))
end
local function copy(folder)
    mirrors = mirrors + 1
    local into = t.ROOT .. "/mirror-" .. mirrors
    os.execute("cp -r " .. q(folder) .. " " .. q(into))
    return into
end
-- }}}

-- {{{ referee 1: a new page gets everything
local FIRST
check("1: a new page's mirror equals the home's RAM folder, byte for byte", function()
    local into, status, summary, out = catch_up(nil)
    must(status == 0, "catch-up failed: " .. out)
    same_as_home(into)
    must(summary.messages == 3, "messages received: " .. tostring(summary.messages))
    FIRST = into
end)
-- }}}

-- {{{ referee 2: only what is new
local SECOND
local function only_new(broken)
    local into, status, summary, out = catch_up(FIRST, broken)
    must(status == 0, "catch-up failed: " .. out)
    same_as_home(into)
    must(summary.messages == 2, summary.messages .. " message files sent, not the 2 new ones")
    return into
end
check("2 (setting up): two new messages on the home", function()
    must(FIRST, "referee 1 made no mirror")
    t.add_message(home.coffee, "new one")
    t.add_message(home.lobby, "new two")
    t.write_inbox()
end)
with_broken("2: a second catch-up from the same mirror receives exactly the two new message files", function(broken)
    local into = only_new(broken)
    if not broken then SECOND = into end
end, "from-start")
-- }}}

-- {{{ referee 3: an edit is caught; so are a lost file and a room left
check("3 (setting up): the first message corrected on the home", function()
    must(SECOND, "referee 2 made no mirror")
    t.correct(home.coffee, home.first, "the first message, put right\n\nAnn")
    t.write_inbox()
    must(#t.differences(SECOND) > 0, "the correction changed nothing on the home")
end)
with_broken("3: the corrected message's file is replaced in the page's mirror", function(broken)
    local into, status, summary, out = catch_up(copy(SECOND), broken)
    must(status == 0, "catch-up failed: " .. out)
    same_as_home(into)
    must(summary.changed >= 1, "nothing changed")
    must(summary.messages == 1, summary.messages .. " message files sent, not just the corrected one")
end, "no-digest")
check("3d: a late message (written before the page's last) is fetched, and a second catch-up at once gets none", function()
    t.add_message(home.coffee, "late, but in its place", nil, 1000000105)
    t.write_inbox()
    mirrors = mirrors + 1
    local into = t.ROOT .. "/mirror-" .. mirrors
    local status, out = t.page("catch-up --twice --settings " .. q(SETTINGS) .. " --mirror-in " .. q(copy(SECOND))
        .. " --mirror-out " .. q(into))
    must(status == 0, "catch-up failed: " .. out)
    same_as_home(into)
    local counts = {}
    for n in out:gmatch("%((%d+) message%(s%)%)") do counts[#counts + 1] = n end
    must(counts[1] == "2", "not the late message and the corrected one fetched: " .. out)
    must(counts[2] == "0", "the second catch-up was sent messages again: " .. out)
end)
check("3b: a file the home no longer holds is dropped; 3c: a room the home has left leaves the mirror", function()
    local before = copy(SECOND)
    -- the home drops one message of the lobby (as a hide added does, 301
    -- decision 4) and has left the quiet room
    local lobby = home.mailbox_of[home.lobby] .. "/inbox/" .. home.lobby
    local gone
    for _, name in ipairs(require("003-disk").list_dir(t.HOME_RAM .. "/" .. lobby)) do
        if mirror.is_message_name(name) then gone = name end
    end
    os.remove(t.HOME_RAM .. "/" .. lobby .. "/" .. gone)
    local quiet_mailbox = home.mailbox_of[home.quiet]
    local tree_path = t.HOME_RAM .. "/" .. quiet_mailbox .. "/inbox/.tree"
    local tree = t.read_file(tree_path)
    t.write_file(tree_path, (tree:gsub(home.quiet .. "[^\n]*\n", "")))
    os.execute("rm -rf " .. q(t.HOME_RAM .. "/" .. quiet_mailbox .. "/inbox/" .. home.quiet))
    local into, status, summary, out = catch_up(before)
    must(status == 0, "catch-up failed: " .. out)
    same_as_home(into)
    must(summary.dropped >= 2, "dropped " .. tostring(summary.dropped))
end)
-- }}}

-- {{{ referee 4: a bad path is refused (a stand-in home)
-- a stand-in home on 46414 that answers the page's ping, then its
-- catch-up with the records given; → what the page printed
local function stand_in_home(answers, broken)
    local server = require("187-device-server")
    local frames, seal = require("125-frames"), require("124-seal")
    local records = require("186-device-records")
    local token = t.read_file(SETTINGS):match("\ntoken = ([^\n]*)")
    local pair = require("123-room-key").key_pair(token)
    local listener = assert(socket.bind("127.0.0.2", 46414))
    listener:settimeout(10)
    local settings = t.file_of((t.read_file(SETTINGS):gsub("\nport = %d+", "\nport = 46414"):gsub("^port = %d+", "port = 46414")))
    mirrors = mirrors + 1
    local into = t.ROOT .. "/mirror-" .. mirrors
    local output = t.page_background("catch-up --settings " .. q(settings) .. " --mirror-out " .. q(into), broken)
    local conn = listener:accept()
    must(conn, "the page never connected")
    conn:settimeout(5)
    conn:send(assert(server.upgrade_answer(server.read_head(conn, ""), "/the-socket")))
    local ws = server.websocket(conn, "server")
    local function answer(list)
        for _, record in ipairs(list) do frames.write_frame(ws, seal.seal(pair, records.encode(record))) end
    end
    local ping = records.decode(assert(seal.open(pair, frames.read_frame(ws))))
    answer({ { kind = "pong", id = ping.id, at = 1 } })
    local asked = records.decode(assert(seal.open(pair, frames.read_frame(ws))))
    must(asked.kind == "catch-up", "the page did not ask to catch up")
    answer(answers)
    local give_up = t.now() + 6
    while t.now() < give_up and not (output():find("dropped") or output():find("not due")) do t.sleep(0.1) end
    t.sleep(0.3)
    conn:close()
    listener:close()
    return output(), into
end
local MAILBOX, ROOM = string.rep("a", 32), string.rep("b", 32)
local function bad_paths(broken)
    local said, into = stand_in_home({
        { kind = "file", path = "../../escape-" .. mirrors, content = "outside" },
        { kind = "file", path = MAILBOX .. "/inbox/not-hex-room/1000-abc", content = "x" },
        { kind = "file", path = MAILBOX .. "/inbox/" .. ROOM .. "/.hidden", content = "x" },
        { kind = "file", path = MAILBOX .. "/inbox/" .. ROOM .. "/1000-a b", content = "x" },
        { kind = "file", path = string.rep("z", 32) .. "/inbox/.tree", content = "x" },
        { kind = "file", path = MAILBOX .. "/inbox/" .. ROOM .. "/1000-good", content = "kept" },
        { kind = "caught-up", at = 1 },
    }, broken)
    must(not said:find("held%-unchecked"), "a refused path was taken: " .. said)
    must(select(2, said:gsub("\nrefused ", "")) == 5, "not five refusals: " .. said)
    must(t.read_file(into .. "/" .. MAILBOX .. "/inbox/" .. ROOM .. "/1000-good") == "kept", "the good file was not kept")
end
with_broken("4: a home answering with ../../escape, a non-hex room or mailbox, a dot file or a spaced name: nothing taken, and said", bad_paths, "no-path-check")
check("4b: a record that is not due in a catch-up ends it, said", function()
    local said = stand_in_home({
        { kind = "file", path = MAILBOX .. "/inbox/" .. ROOM .. "/1000-good", content = "kept" },
        { kind = "sent", id = "stray" },
        { kind = "caught-up", at = 1 },
    })
    must(said:find("the home sent a sent where it was not due"), "not ended: " .. said)
end)
-- }}}

-- {{{ referee 5: the digests are 192's
check("5: the page's catch-up lines for a mirror are 192's positions_text for it", function()
    local into = select(1, catch_up(nil))
    local status, out = t.page("positions --mirror-in " .. q(into))
    must(status == 0, out)
    local want = mirror.positions_text(into)
    must(#want > 100 and out == want, "the page:\n" .. out .. "\n192:\n" .. want)
end)
-- }}}

t.finish()
