-- 226-test-people-and-settings.lua — the referees of issue 408, People
-- and Settings: remembered settings read back as the same lines without
-- the token, and "forget this home" leaves nothing of it; two homes are
-- remembered each with its own lines, and choosing one gives its lines;
-- People lists every mailbox's direct-message rooms and no group room;
-- the top bar's words for each connection state, and the home's name
-- falling back to the address reached; and the page's own script (207,
-- on the stand-in's paper document) filling the form, the top bar and
-- both lists.  Each referee with a broken version also runs against it.
--
-- The page is the stand-in browser (208) under Node.  No server is
-- started; run it under the loopback-only wrapper all the same.
--
-- Run: luajit src/web/tests/226-test-people-and-settings.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>".

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/web/tests/[^/]+$")
end
local t = dofile(DIR .. "/src/web/tests/214-kit-for-page-tests.lua").new(DIR, "people-test", { port = 46408 })
local check, must, with_broken, q = t.check, t.must, t.with_broken, t.q

if not t.has_node then
    t.check("every referee", function() error("STOPPED: node is not installed, so the page's scripts cannot be run outside a browser here") end)
    t.finish()
end

t.make_home()
local LINES = t.pair("laptop")
local TOKEN = LINES:match("\ntoken = ([^\n]*)")
local WITHOUT_TOKEN = (LINES:gsub("token = [^\n]*\n", ""))

-- {{{ helpers
local function steps(list, broken)
    local status, out = t.page("homes --steps " .. q(t.file_of(table.concat(list, "\n") .. "\n")), broken)
    must(status == 0, "homes failed: " .. out)
    return out
end
-- a JSON string, as the stand-in prints one (enough for these lines)
local function json(text)
    return '"' .. text:gsub('[\\"]', "\\%0"):gsub("\n", "\\n") .. '"'
end
-- }}}

-- {{{ referee 1: settings round trip
check("1: remembered settings read back as the same lines without the token; forgetting leaves nothing", function()
    local file = t.file_of(LINES)
    local out = steps({ "remember attic " .. file .. " Ann", "read attic", "dump", "forget attic", "dump", "list", "last" })
    must(out:find("remember attic: kept\n", 1, true), out)
    must(out:find("read attic: lines " .. json(WITHOUT_TOKEN) .. ', signature "Ann"\n', 1, true), "read back: " .. out)
    must(not out:find(TOKEN, 1, true) and not out:find("token", 1, true), "the token was kept: " .. out)
    must(out:find("forget attic: forgotten\n", 1, true), out)
    local after = out:match("forget attic: forgotten\n(.*)$")
    must(after:find("^held 0 key%(s%)\nlist: \nlast: \n$"), "something was left after forgetting: " .. after)
    out = steps({ "remember  " .. file })
    must(out:find("remember : give this home a name first", 1, true), "a home without a name was kept: " .. out)
end)
-- }}}

-- {{{ referee 2: several homes
local function several_homes(broken)
    local other = LINES:gsub("\nport = %d+", "\nport = 47777"):gsub("^port = %d+", "port = 47777")
    local out = steps({ "remember attic " .. t.file_of(LINES), "remember cellar " .. t.file_of(other) .. " Bo",
        "read attic", "read cellar", "list", "last" }, broken)
    must(out:find("read attic: lines " .. json(WITHOUT_TOKEN) .. ', signature ""\n', 1, true), "attic: " .. out)
    must(out:find("read cellar: lines " .. json((other:gsub("token = [^\n]*\n", ""))) .. ', signature "Bo"\n', 1, true),
        "cellar: " .. out)
    must(out:find("list: attic, cellar\nlast: cellar\n", 1, true), out)
end
with_broken("2: two homes remembered, each with its own lines and signature; choosing one gives its lines", several_homes,
    "one-home")
-- }}}

-- {{{ a mirror with direct and group rooms in two mailboxes
local HAND = t.ROOT .. "/hand"
local function tag(c) return string.rep(c, 32) end
local function put(path, text)
    os.execute("mkdir -p " .. q((HAND .. "/" .. path):match("^(.*)/")))
    t.write_file(HAND .. "/" .. path, text)
end
local function room(mailbox, room_tag, label, kind, parent)
    put(mailbox .. "/inbox/" .. room_tag .. "/.room", "label: " .. label .. "\nkind: " .. kind .. "\nparent: "
        .. (parent or "none") .. "\npath: " .. label .. "\nmembers: 2\nflagged: 0\npile: none\n")
end
put(tag("1") .. "/inbox/.tree", tag("a") .. " none group lobby\n" .. tag("b") .. " " .. tag("a") .. " direct Pat\n")
put(tag("2") .. "/inbox/.tree", tag("c") .. " none direct Sam\n" .. tag("d") .. " none group garden\n")
room(tag("1"), tag("a"), "lobby", "group")
room(tag("1"), tag("b"), "Pat", "direct", tag("a"))
room(tag("2"), tag("c"), "Sam", "direct")
room(tag("2"), tag("d"), "garden", "group")
put(tag("2") .. "/inbox/" .. tag("c") .. "/1000000400-s1", "id: s1\nroom: " .. tag("c") .. "\nfrom: Sam\n"
    .. "written: 1000000400\narrived: 1000000401\nsignature: Sam\nedited: no\ndeleted: no\nignored: none\n\nsee you at six")
-- }}}

-- {{{ referee 3: People
check("3: People lists the direct-message rooms of every mailbox, with their last lines, and no group room", function()
    local status, out = t.page("people --mirror-in " .. q(HAND))
    must(status == 0, out)
    -- in the tree's order: Sam at the top (labels compare byte for byte), Pat under the lobby
    must(out == "person " .. tag("c") .. " Sam | see you at six\nperson " .. tag("b") .. " Pat | \n", "People: " .. out)
end)
-- }}}

-- {{{ referee 4: the top bar
check("4: the top bar's words for each connection state, and the home's name falling back to the address reached", function()
    local want = { connecting = "connecting…", ["catching-up"] = "catching up", live = "live", waiting = "not connected",
        stopped = "not connected" }
    for state, words in pairs(want) do
        local _, out = t.page("topbar --state " .. state .. " --label attic --where " .. q("127.0.0.2 46408"))
        must(out == "name attic, state " .. words .. "\n", state .. ": " .. out)
    end
    local _, out = t.page("topbar --state live --where " .. q("127.0.0.2 46408"))
    must(out == "name 127.0.0.2 46408, state live\n", "no label: " .. out)
    _, out = t.page("topbar --state stopped")
    must(out == "name rao-chat, state not connected\n", "nothing reached: " .. out)
end)
-- }}}

-- {{{ referee 5: the page's own script
check("5: the page opens on the last home remembered: its form, the top bar's name, the Homes and People lists", function()
    local storage = '{"rao-chat homes": "attic\\ncellar", "rao-chat home attic": ' .. json(WITHOUT_TOKEN)
        .. ', "rao-chat signature attic": "Ann", "rao-chat home cellar": "port = 1\\n", "rao-chat last home": "attic"}'
    local status, out = t.page("draw --mirror-in " .. q(HAND) .. " --storage " .. q(t.file_of(storage)))
    must(status == 0, "draw failed: " .. out)
    must(out:find("\nform \"attic\" " .. json(WITHOUT_TOKEN) .. ' "Ann" remember true\n', 1, true), "the form: " .. out)
    must(out:find("\ntop attic | not connected\n", 1, true), "the top bar: " .. out)
    must(out:find("ul#homes-list | \n  li | \n    button.open | attic\n  li | \n    button | cellar\n", 1, true), "Homes: " .. out)
    must(out:find("ul#people-list | \n  li | \n    button.tree-row | \n      span.label | Sam\n      span.last-line | see you at six\n", 1, true)
        and out:find("span.label | Pat\n", 1, true)
        and not out:find("span.label | garden\n      span.last-line | \n  li", 1, true), "People: " .. out)
    status, out = t.page("draw --mirror-in " .. q(HAND) .. " --storage " .. q(t.file_of("{}")))
    must(out:find("\ntop rao-chat | not connected\n", 1, true) and out:find("No home remembered", 1, true),
        "with nothing remembered: " .. out)
    status, out = t.page("draw --mirror-in " .. q(HAND))
    must(out:find("this browser keeps nothing for this page", 1, true), "a browser with no storage: " .. out)
end)
-- }}}

t.finish()
