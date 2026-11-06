-- 219-test-how-a-room-looks.lua — the referees of issue 405, how a room
-- looks: the page's room tree is the reference viewer's (183) on the same
-- folder; a name only where the speaker changes, the person's own on the
-- other side; the home's notices are neither side; every message has its
-- own anchor; edited, deleted and ignored-mark messages are shown as such
-- (the last two without a body); markup in a message stays text.  Each
-- referee with a broken version also runs against it.
--
-- What the page shows is worked out by rao.view (218) from a mirror of
-- 301's layout; the stand-in browser (208) prints it as text (`tree`,
-- `room`).  The mirror here is the kit's home RAM folder itself, written
-- by the home's own inbox writer (181), with messages, an edit, a delete
-- and an ignore made through the home's own modules; the home's notices
-- (`.room`'s pile and flagged lines) and a deeper tree are written by hand
-- in 301's layout, as a home with those would write them.  No server is
-- started; run it under the loopback-only wrapper all the same.
--
-- Run: luajit src/web/tests/219-test-how-a-room-looks.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>".

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/web/tests/[^/]+$")
end
local t = dofile(DIR .. "/src/web/tests/214-kit-for-page-tests.lua").new(DIR, "room-look-test", { port = 46405 })
local check, must, with_broken, q = t.check, t.must, t.with_broken, t.q
local rooms = require("002-room-folders")
local message_log = require("081-message-log")
local ignore = require("042-ignore-list")

if not t.has_node then
    t.check("every referee", function() error("STOPPED: node is not installed, so the page's scripts cannot be run outside a browser here") end)
    t.finish()
end

local home = t.make_home()
local VIEWER = DIR .. "/src/viewer/183-viewer.lua"

-- {{{ the home's messages, made through its own modules
local function ram_home_of(tag) return rooms.open_home(t.HOME_RAM .. "/" .. home.mailbox_of[tag] .. "/home") end
-- the quiet room: three from one address and signature, one from
-- another, two of the person's own (referee 2).  Each is signed: by the
-- owner's rule (214) an unsigned message is signed by its last word, so
-- two unsigned ones are two speakers; the page's compose line adds the
-- person's signature to what they send (406).
local SPOKEN = {
    { "the garden needs water\n\nAnn" }, { "and the roses\n\nAnn" }, { "today, please\n\nAnn" },
    { "I can do it\n\nBo", "10.0.0.7 5000" }, { "thank you both\n\nRo", "me" }, { "I will bring the hose\n\nRo", "me" },
}
local QUIET_IDS = {}
for _, said in ipairs(SPOKEN) do QUIET_IDS[#QUIET_IDS + 1] = t.add_message(home.quiet, said[1], said[2]) end
-- the coffee room: the first message corrected (in the kit's home), the
-- second deleted, one holding markup
t.correct(home.coffee, home.first, "the first message, put right\n\nAnn")
local second
for _, entry in ipairs(message_log.read_ordered(ram_home_of(home.coffee), home.coffee)) do
    if entry.text == "the second" then second = entry.id end
end
assert(second, "the kit's second message was not found")
message_log.delete(ram_home_of(home.coffee), home.coffee, { id = message_log.new_message_id(), from = "me",
    written = 1000000900, arrived = 1000000900, target = second })
local MARKUP = "<b>bold</b> &amp; <script>x()</script> &lt;"
local markup_id = t.add_message(home.coffee, MARKUP)
-- the lobby: an address ignored at mark speaks
ignore.ignore(ram_home_of(home.lobby), "10.0.0.66", 5000, "mark", "*", 1000000000)
local ignored_id = t.add_message(home.lobby, "you should not read this", "10.0.0.66 5000")
t.write_inbox()
-- }}}

-- {{{ helpers
local function tree_of(folder, broken, more)
    local status, out = t.page("tree --mirror-in " .. q(folder) .. (more or ""), broken)
    must(status == 0, "tree failed: " .. out)
    return out
end
local function room_of(folder, tag, broken)
    local status, out = t.page("room --mirror-in " .. q(folder) .. " --room " .. q(tag), broken)
    must(status == 0, "room failed: " .. out)
    return out
end
local function viewer_tree(folder)
    local status, out = t.run("luajit " .. q(VIEWER) .. " " .. q(folder) .. " tree")
    must(status == 0, "183's tree failed: " .. out)
    return out
end
-- the room's text → its message lines {side, anchor, marks, text} and name lines {side, name, from}, in order
local function lines_of(text)
    local out = {}
    for line in text:gmatch("[^\n]+") do
        local side, name, from = line:match("^(%a+) name (.-) %((.*)%)$")
        if side then
            out[#out + 1] = { kind = "name", side = side, name = name, from = from }
        else
            local s, anchor, rest = line:match("^(%a+) message (m%-%S+) (.*)$")
            if s then
                local marks, body = rest:match("^%S+ %S+ %[(.-)%] | (.*)$")
                if not marks then body = rest:match("^%S+ %S+ | (.*)$") end
                out[#out + 1] = { kind = "message", side = s, anchor = anchor, marks = marks or "", text = body }
            elseif line:match("^notice | ") then
                out[#out + 1] = { kind = "notice", text = line:sub(10) }
            end
        end
    end
    return out
end
-- }}}

-- {{{ a deeper tree, written by hand in 301's layout
-- Two mailboxes; tags chosen so that tag order is not label order at
-- every level; a room listed by both (the first mailbox's listing wins);
-- a room whose parent no mailbox holds (at the top); a direct room;
-- labels with a space and with a letter outside ASCII; marks.
local HAND = t.ROOT .. "/hand"
local function tag(c) return string.rep(c, 32) end
local M1, M2 = tag("1"), tag("2")
local ZETA, ALPHA, BETA, PAT, LOST, TOP_ALPHA, GARDEN, EMILE =
    tag("a"), tag("c"), tag("b"), tag("d"), tag("e"), tag("f"), tag("9"), tag("8")
local function put(path, text)
    os.execute("mkdir -p " .. q((HAND .. "/" .. path):match("^(.*)/")))
    t.write_file(HAND .. "/" .. path, text)
end
local function room_file(mailbox, room, label, kind, parent, extra)
    put(mailbox .. "/inbox/" .. room .. "/.room", "label: " .. label .. "\nkind: " .. kind .. "\nparent: "
        .. (parent or "none") .. "\npath: " .. label .. "\nmembers: 2\nflagged: " .. ((extra or {}).flagged or "0")
        .. "\n" .. ((extra or {}).pile or "pile: none\n"))
end
put(M1 .. "/inbox/.tree", table.concat({
    ZETA .. " none group zeta",
    ALPHA .. " " .. ZETA .. " group alpha",
    BETA .. " " .. ZETA .. " group beta",
    PAT .. " " .. ALPHA .. " direct Pat",
    GARDEN .. " " .. ZETA .. " group the garden",
    EMILE .. " " .. ZETA .. " group \195\169mile",
}, "\n") .. "\n")
put(M2 .. "/inbox/.tree", table.concat({
    BETA .. " none group listed again",
    LOST .. " " .. tag("7") .. " group lost",
    TOP_ALPHA .. " none group alpha",
    tag("0") .. " none group alpha",
}, "\n") .. "\n")
room_file(M1, ZETA, "zeta", "group")
room_file(M1, ALPHA, "alpha", "group", ZETA, { flagged = "2" })
room_file(M1, BETA, "beta", "group", ZETA, { pile = "pile: 10.0.0.5 7000 3 1000000200\npile: 10.0.0.6 7001 1 1000000300\n" })
room_file(M1, PAT, "Pat", "direct", ALPHA)
room_file(M1, GARDEN, "the garden", "group", ZETA)
room_file(M1, EMILE, "\195\169mile", "group", ZETA)
room_file(M2, BETA, "listed again", "group")
room_file(M2, LOST, "lost", "group", tag("7"))
room_file(M2, TOP_ALPHA, "alpha", "group")
room_file(M2, tag("0"), "alpha", "group")
put(M1 .. "/inbox/" .. BETA .. "/1000000400-hand1", "id: hand1\nroom: " .. BETA .. "\nfrom: 10.0.0.5 7000\n"
    .. "written: 1000000400\narrived: 1000000401\nsignature: \nedited: no\ndeleted: no\nignored: none\n\nthe first line\n\nhello")
-- }}}

-- {{{ referee 1: the tree is 183's
local function tree_is_183s(broken)
    for _, folder in ipairs({ t.HOME_RAM, HAND }) do
        local want = viewer_tree(folder)
        -- the mirror's paths in either order (a home sends in its own)
        for _, backwards in ipairs({ "", " --backwards" }) do
            local have = tree_of(folder, broken, backwards)
            must(#want > 0 and have == want, "the page's tree for " .. folder .. backwards .. ":\n" .. have
                .. "183's:\n" .. want)
        end
    end
end
with_broken("1: the page's tree is 183's `tree` on the same folder (the kit's home, and a deeper hand-made one)",
    tree_is_183s, "tag-order")
check("1b: the hand-made tree has its depths, its first listing, its stray room at the top, and its marks", function()
    local have = tree_of(HAND)
    local want = table.concat({
        "alpha  00000000", "alpha  ffffffff", "lost  eeeeeeee", "zeta  aaaaaaaa", "  alpha  cccccccc [2 flagged]", "    Pat (direct)  dddddddd",
        "  beta  bbbbbbbb [4 waiting]", "  the garden  99999999", "  \195\169mile  88888888" }, "\n") .. "\n"
    must(have == want, "the tree:\n" .. have)
end)
check("1c: each row carries its last line, and a direct room is marked as one", function()
    local status, out = t.page("tree --rows --mirror-in " .. q(HAND))
    must(status == 0, out)
    must(out:find("\n1 " .. BETA .. " group 0 4 beta | hello\n", 1, true), "beta's row: " .. out)
    must(out:find("\n2 " .. PAT .. " direct 0 0 Pat | \n", 1, true), "Pat's row: " .. out)
    status, out = t.page("tree --rows --mirror-in " .. q(t.HOME_RAM))
    must(out:find(" lobby | (someone you ignore spoke)", 1, true), "the lobby's last line: " .. out)
end)
-- }}}

-- {{{ referee 2: a name only where the speaker changes
local function names_where_speaker_changes(broken)
    local lines = lines_of(room_of(t.HOME_RAM, home.quiet, broken))
    local names, sides, named = {}, {}, {}
    local pending
    for _, line in ipairs(lines) do
        if line.kind == "name" then pending = line
        elseif line.kind == "message" then
            sides[#sides + 1] = line.side
            if pending then named[#named + 1] = #sides; names[#names + 1] = pending.name .. "/" .. pending.from end
            pending = nil
        end
    end
    must(#sides == 6, #sides .. " messages shown, not 6")
    must(table.concat(sides, " ") == "theirs theirs theirs theirs mine mine", "sides: " .. table.concat(sides, " "))
    must(table.concat(named, " ") == "1 4 5", "names on messages " .. table.concat(named, " ") .. ", not 1 4 5")
    must(names[1] == "Ann/10.0.0.9 5000" and names[2] == "Bo/10.0.0.7 5000" and names[3] == "Ro/me",
        "names: " .. table.concat(names, ", "))
end
with_broken("2: three from one address and signature, one from another, two of the person's own: names on the 1st, 4th and 5th only",
    names_where_speaker_changes, "name-every-line")
check("2b: the same address under another signature, or the same signature from another address, is another speaker (405 decision 1)", function()
    t.add_message(home.quiet, "it is me again\n\nAnnie")
    t.write_inbox()
    local lines = lines_of(room_of(t.HOME_RAM, home.quiet))
    local last = lines[#lines - 1]
    must(last.kind == "name" and last.name == "Annie" and last.from == "10.0.0.9 5000" and last.side == "theirs",
        "the seventh message was not named Annie: " .. room_of(t.HOME_RAM, home.quiet))
    t.add_message(home.quiet, "and me, from elsewhere\n\nAnnie", "10.0.0.8 5000")
    t.write_inbox()
    lines = lines_of(room_of(t.HOME_RAM, home.quiet))
    last = lines[#lines - 1]
    must(last.kind == "name" and last.name == "Annie" and last.from == "10.0.0.8 5000",
        "the same signature from another address was not named: " .. room_of(t.HOME_RAM, home.quiet))
    t.add_message(home.quiet, "straight after, signed otherwise\n\nZed", "10.0.0.8 5000")
    t.write_inbox()
    lines = lines_of(room_of(t.HOME_RAM, home.quiet))
    last = lines[#lines - 1]
    must(last.kind == "name" and last.name == "Zed" and last.from == "10.0.0.8 5000",
        "another signature straight after, from the same address, was not named: " .. room_of(t.HOME_RAM, home.quiet))
end)
-- }}}

-- {{{ referee 3: notices are neither side
check("3: a pile line and flagged members show as notices, after the last message, naming address, port and count", function()
    local lines = lines_of(room_of(HAND, BETA))
    must(#lines == 4, "lines: " .. room_of(HAND, BETA))
    must(lines[2].kind == "message", "the message is not before the notices")
    must(lines[3].kind == "notice" and lines[3].text:find("^3 message%(s%) could not be delivered yet to 10%.0%.0%.5 7000"),
        "the first notice: " .. tostring(lines[3].text))
    must(lines[4].kind == "notice" and lines[4].text:find("^1 message%(s%) could not be delivered yet to 10%.0%.0%.6 7001"),
        "the second notice: " .. tostring(lines[4].text))
    local flagged = lines_of(room_of(HAND, ALPHA))
    must(#flagged == 1 and flagged[1].kind == "notice" and flagged[1].text:find("^2 flagged member%(s%)"),
        "the flagged notice: " .. room_of(HAND, ALPHA))
    must(#lines_of(room_of(HAND, ZETA)) == 0, "a room with nothing owed shows a notice")
end)
-- }}}

-- {{{ referee 4: anchors
check("4: every message line carries m-<its id>, and no two the same", function()
    local seen, count = {}, 0
    for _, room in ipairs({ home.lobby, home.coffee, home.quiet }) do
        local folder = t.HOME_RAM .. "/" .. home.mailbox_of[room] .. "/inbox/" .. room
        local ids = {}
        for _, name in ipairs(require("003-disk").list_dir(folder)) do
            if name:sub(1, 1) ~= "." then ids[#ids + 1] = "m-" .. name:match("^%d+%-(.*)$") end
        end
        table.sort(ids)
        local anchors = {}
        for _, line in ipairs(lines_of(room_of(t.HOME_RAM, room))) do
            if line.kind == "message" then
                must(not seen[line.anchor], "the anchor " .. line.anchor .. " twice")
                seen[line.anchor] = true
                anchors[#anchors + 1] = line.anchor
                count = count + 1
            end
        end
        table.sort(anchors)
        must(table.concat(anchors, " ") == table.concat(ids, " "), "anchors " .. table.concat(anchors, " ")
            .. " are not the ids " .. table.concat(ids, " "))
    end
    must(count >= 10, "only " .. count .. " messages")
    must(seen["m-" .. QUIET_IDS[1]] and seen["m-" .. markup_id], "the ids made here have no anchors")
end)
-- }}}

-- {{{ referee 5: marks
local function marks_shown(broken)
    local coffee = room_of(t.HOME_RAM, home.coffee, broken)
    local lines = lines_of(coffee)
    local by_anchor = {}
    for _, line in ipairs(lines) do if line.kind == "message" then by_anchor[line.anchor] = line end end
    local edited = by_anchor["m-" .. home.first]
    must(edited and edited.marks == "edited" and edited.text == "the first message, put right", "the edited one: " .. coffee)
    local deleted = by_anchor["m-" .. second]
    must(deleted and deleted.marks == "deleted" and deleted.text == "(deleted)", "the deleted one: " .. coffee)
    must(not coffee:find("the second", 1, true), "the deleted text is shown")
    local lobby = room_of(t.HOME_RAM, home.lobby, broken)
    local marked
    for _, line in ipairs(lines_of(lobby)) do if line.anchor == "m-" .. ignored_id then marked = line end end
    must(marked and marked.marks == "ignored" and marked.text == "someone you ignore spoke", "the ignored one: " .. lobby)
    must(not lobby:find("you should not read this", 1, true), "an ignored message's body is shown")
end
with_broken("5: edited is marked; deleted and ignored-mark show no body", marks_shown, "show-ignored")
-- }}}

-- {{{ referee 6: markup is text
check("6: a message holding <b>, <script> and &amp; keeps those characters in its line's text", function()
    local found
    for _, line in ipairs(lines_of(room_of(t.HOME_RAM, home.coffee))) do
        if line.anchor == "m-" .. markup_id then found = line end
    end
    must(found and found.text == MARKUP, "the line's text: " .. tostring(found and found.text))
end)
-- }}}

-- {{{ referee 8: the page's own script places what the view worked out
-- (207 run on the stand-in's paper document)
local function drawn(words)
    local status, out = t.page("draw " .. words)
    must(status == 0, "draw failed: " .. out)
    return out
end
check("8: the page draws the tree as nested lists, a later catch-up's new message as unread, and opening the room clears it", function()
    local before = t.ROOT .. "/before-lobby"
    os.execute("cp -r " .. q(t.HOME_RAM) .. " " .. q(before))
    local new_id = t.add_message(home.lobby, "something new in the lobby\n\nAnn")
    t.write_inbox()
    local out = drawn("--mirror-in " .. q(before) .. " --then " .. q(t.HOME_RAM))
    must(out:find("\n  li | \n    button.tree%-fold | %-\n    button.tree%-row | \n      span.label | lobby\n      span.unread |  %(1%)\n"),
        "the lobby's row has no unread mark of 1: " .. out)
    must(out:find("\n    ul | \n      li | \n        button.tree%-row | \n          span.label | coffee\n"),
        "coffee is not in a list inside the lobby's: " .. out)
    must(not out:find("span.label | coffee\n          span.unread"), "coffee is marked unread")
    out = drawn("--mirror-in " .. q(before) .. " --then " .. q(t.HOME_RAM) .. " --open " .. q(home.lobby))
    must(out:find("button.tree%-row.open | \n      span.label | lobby\n      span.last%-line"), "opening did not clear it: " .. out)
    must(out:find("\n  li.line.theirs#m%-" .. new_id .. " | \n    span.name | Ann\n      span.from |   10.0.0.9 5000\n"
        .. "    span.body | something new in the lobby\n", 1), "the new message's line: " .. out)
    must(out:find("\n  li.line.theirs#m%-" .. ignored_id .. " | \n    span.name | [^\n]*\n[^\n]*\n    span.body.marked | someone you ignore spoke\n"),
        "the ignored line: " .. out)
end)
check("8b: the page draws the person's own on their side, the home's notices as notices, and markup as text", function()
    local out = drawn("--mirror-in " .. q(t.HOME_RAM) .. " --open " .. q(home.quiet))
    must(select(2, out:gsub("\n  li%.line%.mine#m%-", "")) >= 2, "no lines of the person's own: " .. out)
    must(select(2, out:gsub("\n    span%.name | ", "")) == 6, "not six names drawn in the quiet room: " .. out)
    out = drawn("--mirror-in " .. q(t.HOME_RAM) .. " --open " .. q(home.coffee))
    must(out:find("\n    span.body | " .. MARKUP:gsub("%p", "%%%0") .. "\n"), "the markup's text: " .. out)
    out = drawn("--mirror-in " .. q(HAND) .. " --open " .. q(BETA))
    must(out:find("\n  li.line.notice | 3 message%(s%) could not be delivered yet to 10.0.0.5 7000"), "the notice: " .. out)
    must(out:find("\nbeta  %(group, 2 member%(s%)%)\n"), "the title: " .. out)
end)
-- }}}

check("7: a room the mirror does not hold is said, not shown", function()
    local status, out = t.page("room --mirror-in " .. q(HAND) .. " --room " .. q(tag("7")))
    must(status ~= 0 and out:find("no room here is"), out)
end)

t.finish()
