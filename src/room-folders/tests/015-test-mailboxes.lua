-- 015-test-mailboxes.lua — tests for mailboxes: which port each room listens on.
--
-- Checks the mailboxes file as text (written and read back unchanged,
-- every malformed shape refused); where make_room puts each kind of room
-- (a top room and everything under it in one new mailbox, every direct
-- message in the one direct mailbox); that ports are never defaulted;
-- that two mailboxes on one port are allowed but reported every time the
-- file is read; that mailboxes are found by port, and rooms by mailbox,
-- as phase 2's trial opening needs; that a child whose declared parent is
-- not held here starts its own mailbox, remembering it awaits the parent;
-- and both values of mailboxes.merge-when-parent-arrives once the parent
-- arrives (automatic: the rooms move; ask: listed until merge_mailbox).
-- Run: luajit 015-test-mailboxes.lua [project folder]

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local kit = dofile(DIR .. "/src/room-folders/tests/008-kit-for-tests.lua")
local rooms = kit.setup(DIR)
local mailbox_file = require("014-mailboxes")
local check, same, same_list, fails = kit.check, kit.same, kit.same_list, kit.fails

-- Shared-port reports, caught instead of printed, so a test can count them.
local reports = {}
rooms.set_warning_sink(function(text) reports[#reports + 1] = text end)

-- Every "mailbox" ring, as "<tag> mailbox".
local mailbox_rings = {}
rooms.on_change(function(home, tag, what)
    -- only mailbox rings are of interest here.
    if what == "mailbox" then
        mailbox_rings[#mailbox_rings + 1] = tag .. " mailbox"
    end
end)

-- {{{ local function take_rings
local function take_rings()
    local got = mailbox_rings
    mailbox_rings = {}
    return got
end
-- }}}

local A = "0123456789abcdef0123456789abcdef"
local B = "fedcba9876543210fedcba9876543210"
local C = "9c41d07a2be35f6e8810aa3c5d7e9f01"

-- {{{ local function room
-- A make_room spec: a group room unless `kind` says otherwise, its parent
-- named by the parent's token ("" for none), and a mailbox_port that is
-- `port` when given, else what the contract's placement table asks.
local function room(label, token, parent_token, kind, port)
    kind = kind or "group"
    local parent = ""
    -- a parent token named: the entry holds its fingerprint.
    if parent_token ~= "" then
        parent = rooms.token_fingerprint(parent_token)
    end
    local mailbox_port = port
    -- no port given: the placement rule's usual value.
    if mailbox_port == nil then
        mailbox_port = kit.port_for(kind, parent)
    end
    return { label = label, token = token, kind = kind, parent = parent, filed_under = "",
             members = {}, mailbox_port = mailbox_port }
end
-- }}}

-- {{{ local function mailbox_of
local function mailbox_of(home, tag)
    return rooms.read_entry(home, tag).mailbox
end
-- }}}

---------------------------------------------------------------- the file

check("file: a list turns into text and back unchanged, sorted by tag", function()
    local list = {
        { tag = B, label = "programming \"odd\" / name", kind = "tree", port = 7777, awaits_parent_of = "" },
        { tag = A, label = "direct messages", kind = "direct", port = 7700, awaits_parent_of = "" },
        { tag = C, label = "stray", kind = "tree", port = 7701, awaits_parent_of = A },
    }
    local text = mailbox_file.mailboxes_text(list)
    same(text:sub(1, #mailbox_file.HEADER), mailbox_file.HEADER, "header first")
    local back = mailbox_file.parse_mailboxes(text, "test")
    same_list({ back[1].tag, back[2].tag, back[3].tag }, { A, C, B }, "sorted")
    same(back[2].awaits_parent_of, A, "awaits a room's parent") same(back[1].awaits_parent_of, "", "empty kept empty")
    same(back[3].label, "programming \"odd\" / name") same(back[3].port, 7777) same(back[3].kind, "tree")
    same(back[1].kind, "direct") same(type(back[1].port), "number")
end)

check("file: no mailboxes is just the header, and reads back empty", function()
    same(#mailbox_file.parse_mailboxes(mailbox_file.mailboxes_text({}), "test"), 0)
end)

check("file: rmail's contacts format — each line is <tag>.<field> = <value>", function()
    local text = mailbox_file.mailboxes_text({ { tag = A, label = "x", kind = "tree", port = 9, awaits_parent_of = "" } })
    same(text:find(A .. '.label = "x"\n' .. A .. ".kind = tree\n" .. A .. ".port = 9\n"
        .. A .. ".awaits-parent-of = \n", 1, true) ~= nil, true)
end)

check("file: writer refusals (no default port, known kinds, one direct, awaits_parent_of shape)", function()
    local cases = {
        { { tag = A, label = "x", kind = "tree" }, "no default port" },
        { { tag = A, label = "x", kind = "tree", port = 0, awaits_parent_of = "" }, "1-65535" },
        { { tag = A, label = "x", kind = "tree", port = 70000, awaits_parent_of = "" }, "1-65535" },
        { { tag = A, label = "x", kind = "tree", port = 80.5, awaits_parent_of = "" }, "1-65535" },
        { { tag = A, label = "x", kind = "tree", port = "80", awaits_parent_of = "" }, "1-65535" },
        { { tag = A, label = "x", kind = "room", port = 80, awaits_parent_of = "" }, "mailbox kind must be" },
        { { tag = A, label = "", kind = "tree", port = 80, awaits_parent_of = "" }, "label must be" },
        { { tag = A, label = "a\nb", kind = "tree", port = 80, awaits_parent_of = "" }, "label must be" },
        { { tag = "ROOM", label = "x", kind = "tree", port = 80, awaits_parent_of = "" }, "mailbox.tag" },
        { { tag = A, label = "x", kind = "tree", port = 80, awaits_parent_of = "", colour = "red" }, "unknown field 'colour'" },
    }
    for _, case in ipairs(cases) do
        fails(function() mailbox_file.mailboxes_text({ case[1] }) end, case[2])
    end
    fails(function() mailbox_file.mailboxes_text({
        { tag = A, label = "d1", kind = "direct", port = 1, awaits_parent_of = "" }, { tag = B, label = "d2", kind = "direct", port = 2, awaits_parent_of = "" } }) end,
        "at most one 'direct'")
    fails(function() mailbox_file.mailboxes_text({ { tag = A, label = "w", kind = "waiting", port = 1,
        awaits_parent_of = "" } }) end, "must be 'tree' or 'direct'")
    fails(function() mailbox_file.mailboxes_text({ { tag = A, label = "x", kind = "tree", port = 1 } }) end,
        "awaits_parent_of must be")
    fails(function() mailbox_file.mailboxes_text({ { tag = A, label = "x", kind = "tree", port = 1,
        awaits_parent_of = "room" } }) end, "awaits_parent_of must be")
    fails(function() mailbox_file.mailboxes_text({ { tag = A, label = "x", kind = "direct", port = 1,
        awaits_parent_of = B } }) end, "only a tree mailbox can await")
    fails(function() mailbox_file.mailboxes_text({
        { tag = A, label = "t", kind = "tree", port = 1, awaits_parent_of = "" }, { tag = A, label = "t", kind = "tree", port = 2, awaits_parent_of = "" } }) end,
        "listed twice")
end)

check("file: reader refusals for hand edits, naming the file", function()
    local good = mailbox_file.mailboxes_text({ { tag = A, label = "x", kind = "tree", port = 80, awaits_parent_of = "" } })
    local cases = {
        { good:gsub(A .. "%.port = 80\n", ""), "has no 'port'" },
        { good:gsub(A .. "%.awaits%-parent%-of = \n", ""), "has no 'awaits-parent-of'" },
        { good:gsub("awaits%-parent%-of = ", "awaits-parent-of = x"), "awaits_parent_of must be" },
        { good:gsub("port = 80", "port = 080"), "port must be" },
        { good:gsub("port = 80", "port = http"), "port must be" },
        { good:gsub("kind = tree", "kind = room"), "mailbox kind must be" },
        { good .. A .. ".colour = red\n", "unknown field 'colour'" },
        { good .. A .. ".port = 81\n", "set twice" },
    }
    for _, case in ipairs(cases) do
        fails(function() mailbox_file.parse_mailboxes(case[1], "/h/mailboxes") end, case[2])
        fails(function() mailbox_file.parse_mailboxes(case[1], "/h/mailboxes") end, "/h/mailboxes")
    end
end)

check("file: shared_ports_of finds ports named twice or more, and only those", function()
    local list = {
        { tag = A, label = "a", kind = "tree", port = 7777, awaits_parent_of = "" },
        { tag = B, label = "b", kind = "direct", port = 7777, awaits_parent_of = "" },
        { tag = C, label = "c", kind = "tree", port = 7778, awaits_parent_of = "" },
    }
    local shared = mailbox_file.shared_ports_of(list)
    same(#shared, 1) same(shared[1].port, 7777) same_list(shared[1].mailboxes, { A, B })
    same(#mailbox_file.shared_ports_of({ list[1], list[3] }), 0, "all apart")
end)

---------------------------------------------------------------- placement

local home = kit.test_home(rooms, "mailboxes", "")
local top, child, grandchild, dm, other_top

check("a top room and its child (and grandchild) share one new tree mailbox", function()
    top = rooms.make_room(home, room("home", "m-home", ""))
    child = rooms.make_room(home, room("ritz", "m-ritz", "m-home"))
    grandchild = rooms.make_room(home, room("programming", "m-prog", "m-ritz"))
    local box = rooms.read_mailbox(home, mailbox_of(home, top))
    same(box.kind, "tree") same(box.label, "home", "takes the top room's label")
    same(mailbox_of(home, child), box.tag, "child") same(mailbox_of(home, grandchild), box.tag, "grandchild")
    local want = { top, child, grandchild }
    table.sort(want)
    same_list(rooms.list_rooms_by_mailbox(home, box.tag), want, "rooms by mailbox")
end)

check("a direct message goes in the one direct mailbox", function()
    dm = rooms.make_room(home, room("girlfriend", "m-gf", "", "direct"))
    same(mailbox_of(home, dm), rooms.direct_mailbox(home))
    same(rooms.read_mailbox(home, rooms.direct_mailbox(home)).port, kit.DIRECT_PORT)
    same_list(rooms.list_rooms_by_mailbox(home, rooms.direct_mailbox(home)), { dm })
end)

check("a second top room starts a second tree mailbox with its own port", function()
    local port = kit.fresh_port()
    other_top = rooms.make_room(home, room("work", "m-work", "", "group", port))
    same(mailbox_of(home, other_top) ~= mailbox_of(home, top), true)
    same(rooms.read_mailbox(home, mailbox_of(home, other_top)).port, port)
    same(#rooms.read_mailboxes(home), 3, "direct + two trees")
end)

check("a top room without a port is refused: there is no default port", function()
    fails(function() rooms.make_room(home, room("x", "m-noport", "", "group", "")) end, "no default port")
    fails(function() rooms.make_room(home, room("x", "m-badport", "", "group", 0)) end, "1-65535")
    fails(function() rooms.make_room(home, room("x", "m-textport", "", "group", "7777")) end, "must be a port")
end)

check("a room that joins a mailbox may not name a port (it would go unused)", function()
    fails(function() rooms.make_room(home, room("x", "m-kidport", "m-home", "group", 9999)) end,
          "mailbox_port must be \"\" here")
    fails(function() rooms.make_room(home, room("x", "m-dmport", "", "direct", 9999)) end,
          "mailbox_port must be \"\" here")
    fails(function() rooms.make_room(home, room("x", "m-tableport", "m-home", "group", {})) end,
          "must be a port")
end)

check("a direct message on a home with no direct mailbox is refused, naming the fix", function()
    local bare = rooms.open_home(kit.fresh_home_dir("mailboxes-bare"))
    fails(function() rooms.make_room(bare, room("x", "m-bare", "", "direct")) end, "make_mailbox")
    same(#rooms.list_rooms(bare), 0)
end)

check("make_mailbox: one direct per home; tree mailboxes only through make_room; no waiting kind; ports checked", function()
    fails(function() rooms.make_mailbox(home, { label = "again", kind = "direct", port = 7800 }) end,
          "already has its 'direct' mailbox")
    fails(function() rooms.make_mailbox(home, { label = "t", kind = "tree", port = 7800 }) end, "made by make_room")
    fails(function() rooms.make_mailbox(home, { label = "w", kind = "direct" }) end, "spec.port is missing")
    fails(function() rooms.make_mailbox(home, { label = "w", kind = "direct", port = 0 }) end, "1-65535")
    fails(function() rooms.make_mailbox(home, { label = "w", kind = "direct", port = 1, colour = 2 }) end,
          "unknown spec field")
    fails(function() rooms.make_mailbox(home, { label = "w", kind = "waiting", port = 1 }) end,
          "must be 'tree' or 'direct'")
    fails(function() rooms.make_mailbox(home, { label = "w", kind = "box", port = 1 }) end, "mailbox kind must be")
end)

check("mailboxes_by_port: the mailboxes to try a frame against, and no others", function()
    same_list(rooms.mailboxes_by_port(home, kit.DIRECT_PORT), { rooms.direct_mailbox(home) })
    same_list(rooms.mailboxes_by_port(home, rooms.read_mailbox(home, mailbox_of(home, top)).port),
              { mailbox_of(home, top) })
    same(#rooms.mailboxes_by_port(home, 1), 0, "nobody listens on 1")
    fails(function() rooms.mailboxes_by_port(home, "7700") end, "1-65535")
end)

check("no shared port yet: nothing reported", function()
    reports = {}
    rooms.read_mailboxes(home)
    same(#reports, 0)
    same(#rooms.shared_ports(home), 0)
end)

check("two mailboxes on one port: allowed, reported every time the file is read", function()
    local shared_port = rooms.read_mailbox(home, mailbox_of(home, top)).port
    local third = rooms.make_room(home, room("games", "m-games", "", "group", shared_port))
    reports = {}
    rooms.read_mailboxes(home)
    same(#reports, 1, "one report for one shared port")
    same(reports[1]:find("port " .. shared_port .. " is shared by 2 mailboxes", 1, true) ~= nil, true, reports[1])
    same(reports[1]:find("\"home\"", 1, true) ~= nil and reports[1]:find("\"games\"", 1, true) ~= nil, true,
         "names both")
    rooms.read_mailboxes(home)
    same(#reports, 2, "reported again on the next read")
    local both = { mailbox_of(home, top), mailbox_of(home, third) }
    table.sort(both)
    same_list(rooms.mailboxes_by_port(home, shared_port), both, "a frame there is tried against both")
    local shared = rooms.shared_ports(home)
    same(#shared, 1) same(shared[1].port, shared_port) same_list(shared[1].mailboxes, both)
end)

check("write_mailbox_port moves a mailbox to another port (and ends the sharing)", function()
    local games_box = mailbox_of(home, rooms.find_by_fingerprint(home, rooms.token_fingerprint("m-games")))
    local port = kit.fresh_port()
    rooms.write_mailbox_port(home, games_box, port)
    same(rooms.read_mailbox(home, games_box).port, port)
    same(#rooms.shared_ports(home), 0)
    fails(function() rooms.write_mailbox_port(home, games_box, 0) end, "1-65535")
    fails(function() rooms.write_mailbox_port(home, A, 8000) end, "no such mailbox")
end)

check("write_mailbox: moves a room by hand; its kind must fit", function()
    take_rings()
    rooms.write_mailbox(home, grandchild, mailbox_of(home, other_top))
    same(mailbox_of(home, grandchild), mailbox_of(home, other_top))
    same_list(take_rings(), { grandchild .. " mailbox" })
    fails(function() rooms.write_mailbox(home, dm, mailbox_of(home, top)) end, "a direct room cannot be in a 'tree'")
    fails(function() rooms.write_mailbox(home, top, rooms.direct_mailbox(home)) end, "a group room cannot be in a 'direct'")
    fails(function() rooms.write_mailbox(home, top, A) end, "no such mailbox")
    rooms.write_mailbox(home, grandchild, mailbox_of(home, top))
end)

check("read_mailbox / list_rooms_by_mailbox on an unknown mailbox are errors", function()
    fails(function() rooms.read_mailbox(home, A) end, "no such mailbox")
    fails(function() rooms.list_rooms_by_mailbox(home, A) end, "no such mailbox")
    fails(function() rooms.read_mailbox(home, "home") end, "not a local tag")
end)

check("a hand-broken mailboxes file stops every mailbox read, naming the file", function()
    local broken = rooms.open_home(kit.fresh_home_dir("mailboxes-broken"))
    kit.write_file(rooms.mailboxes_path(broken), A .. ".label = \"x\"\n" .. A .. ".kind = tree\n")
    fails(function() rooms.read_mailboxes(broken) end, "has no 'port'")
    fails(function() rooms.read_mailboxes(broken) end, rooms.mailboxes_path(broken))
end)

---------------------------------------------------------------- a parent not held here

check("a child of an unheld parent starts its own tree mailbox, remembering it awaits the parent", function()
    local own = kit.test_home(rooms, "mailboxes-own", "")
    fails(function() rooms.make_room(own, room("stray", "o-child", "o-parent", "group", "")) end, "no default port")
    local port = kit.fresh_port()
    local stray = rooms.make_room(own, room("stray", "o-child", "o-parent", "group", port))
    local box = rooms.read_mailbox(own, mailbox_of(own, stray))
    same(box.kind, "tree") same(box.port, port) same(box.label, "stray")
    same(box.awaits_parent_of, stray, "remembers the room")
    same(#rooms.mergeable_mailboxes(own), 0, "parent not here: nothing to merge")
    -- a grandchild made now follows its held parent: the stray's mailbox.
    local grand = rooms.make_room(own, room("grand", "o-grand", "o-child"))
    same(mailbox_of(own, grand), box.tag)
    -- a top room's mailbox awaits nothing.
    local top_room = rooms.make_room(own, room("other", "o-other", ""))
    same(rooms.read_mailbox(own, mailbox_of(own, top_room)).awaits_parent_of, "")
end)

check("the merge setting is read only once a merge is possible (none set above), then required", function()
    local bare = kit.test_home(rooms, "mailboxes-unset", "")
    rooms.make_room(bare, room("kid", "u-child", "u-parent", "group", kit.fresh_port()))
    same(rooms.read_config(bare)[rooms.MERGE_KEY], nil, "never needed so far")
    fails(function() rooms.make_room(bare, room("parent", "u-parent", "")) end,
          "config key '" .. rooms.MERGE_KEY .. "' is not set")
end)

check("an unknown value of the merge setting is refused, not guessed past", function()
    local odd = kit.test_home(rooms, "mailboxes-odd", "sometimes")
    rooms.make_room(odd, room("kid", "d-child", "d-parent", "group", kit.fresh_port()))
    fails(function() rooms.make_room(odd, room("parent", "d-parent", "")) end, "must be 'automatic' or 'ask'")
end)

check("automatic: when the parent arrives, the child's mailbox rooms move into the parent's", function()
    local auto = kit.test_home(rooms, "mailboxes-auto", "automatic")
    local kid = rooms.make_room(auto, room("kid", "a-child", "a-parent", "group", kit.fresh_port()))
    local own_box = mailbox_of(auto, kid)
    local grand = rooms.make_room(auto, room("grand", "a-grand", "a-child"))
    take_rings()
    local parent = rooms.make_room(auto, room("parent", "a-parent", ""))
    same(mailbox_of(auto, kid), mailbox_of(auto, parent), "the child moved")
    same(mailbox_of(auto, grand), mailbox_of(auto, parent), "the grandchild moved with it")
    same_list(take_rings(), { kid .. " mailbox", grand .. " mailbox" }, "the room made for first, one ring each")
    same(rooms.read_mailbox(auto, own_box).awaits_parent_of, "", "no longer waiting")
    same(#rooms.list_rooms_by_mailbox(auto, own_box), 0, "the old mailbox stays, empty (phase 2 keeps its port)")
    same(#rooms.mergeable_mailboxes(auto), 0, "nothing left to ask about")
end)

check("automatic: a chain arriving bottom-up merges step by step into the top's mailbox", function()
    local auto = kit.test_home(rooms, "mailboxes-auto-chain", "automatic")
    local programming = rooms.make_room(auto, room("programming", "c-prog", "c-ritz", "group", kit.fresh_port()))
    local ritz = rooms.make_room(auto, room("ritz", "c-ritz", "c-home", "group", kit.fresh_port()))
    same(mailbox_of(auto, programming), mailbox_of(auto, ritz), "programming merged into ritz's own mailbox")
    take_rings()
    local home_room = rooms.make_room(auto, room("home", "c-home", ""))
    local box = mailbox_of(auto, home_room)
    same(mailbox_of(auto, ritz), box, "ritz moved")
    same(mailbox_of(auto, programming), box, "programming moved with it")
    same_list(take_rings(), { ritz .. " mailbox", programming .. " mailbox" }, "ritz first, then programming")
end)

check("automatic: a parent arriving by a token change merges too", function()
    local auto = kit.test_home(rooms, "mailboxes-auto-token", "automatic")
    local kid = rooms.make_room(auto, room("kid", "t-child", "t-parent", "group", kit.fresh_port()))
    local holder = rooms.make_room(auto, room("holder", "t-old", ""))
    take_rings()
    rooms.change_token(auto, holder, "t-parent")
    same(mailbox_of(auto, kid), mailbox_of(auto, holder))
    same_list(take_rings(), { kid .. " mailbox" })
end)

check("automatic: a waiting child given a held parent by write_parent merges into it", function()
    local auto = kit.test_home(rooms, "mailboxes-auto-parent", "automatic")
    local kid = rooms.make_room(auto, room("kid", "p-child", "p-nowhere", "group", kit.fresh_port()))
    local held = rooms.make_room(auto, room("held", "p-held", ""))
    rooms.write_parent(auto, kid, rooms.token_fingerprint("p-held"))
    same(mailbox_of(auto, kid), mailbox_of(auto, held))
end)

check("ask: the merge is listed, nothing moves, until the person says yes", function()
    local ask = kit.test_home(rooms, "mailboxes-ask", "ask")
    local kid = rooms.make_room(ask, room("kid", "k-child", "k-parent", "group", kit.fresh_port()))
    local own_box = mailbox_of(ask, kid)
    local grand = rooms.make_room(ask, room("grand", "k-grand", "k-child"))
    take_rings()
    local parent = rooms.make_room(ask, room("parent", "k-parent", ""))
    same(mailbox_of(ask, kid), own_box, "not moved")
    same(#take_rings(), 0, "nothing rung")
    local listed = rooms.mergeable_mailboxes(ask)
    same(#listed, 1)
    same(listed[1].mailbox, own_box) same(listed[1].room, kid) same(listed[1].into, mailbox_of(ask, parent))
    local both = { kid, grand }
    table.sort(both)
    same_list(listed[1].rooms, both, "the rooms that would move")
    -- another write does not move it either.
    rooms.make_room(ask, room("other", "k-other", ""))
    same(mailbox_of(ask, kid), own_box, "still waiting for the yes")
    rooms.merge_mailbox(ask, own_box)
    same(mailbox_of(ask, kid), mailbox_of(ask, parent), "the yes moved it")
    same(mailbox_of(ask, grand), mailbox_of(ask, parent), "and the grandchild")
    same_list(take_rings(), { kid .. " mailbox", grand .. " mailbox" })
    same(#rooms.mergeable_mailboxes(ask), 0, "no longer listed")
    fails(function() rooms.merge_mailbox(ask, own_box) end, "is not waiting to merge")
end)

check("ask: merge_mailbox before the parent arrives is refused, saying why", function()
    local ask = kit.test_home(rooms, "mailboxes-ask-early", "ask")
    local kid = rooms.make_room(ask, room("kid", "e-child", "e-parent", "group", kit.fresh_port()))
    fails(function() rooms.merge_mailbox(ask, mailbox_of(ask, kid)) end, "cannot merge yet")
    fails(function() rooms.merge_mailbox(ask, A) end, "no such mailbox")
    fails(function() rooms.merge_mailbox(ask, rooms.direct_mailbox(ask)) end, "is not waiting to merge")
end)

check("ask: in a chain, a yes lower down lands in the parent's mailbox as it is now", function()
    local ask = kit.test_home(rooms, "mailboxes-ask-chain", "ask")
    local programming = rooms.make_room(ask, room("programming", "q-prog", "q-ritz", "group", kit.fresh_port()))
    local ritz = rooms.make_room(ask, room("ritz", "q-ritz", "q-home", "group", kit.fresh_port()))
    local home_room = rooms.make_room(ask, room("home", "q-home", ""))
    same(#rooms.mergeable_mailboxes(ask), 2, "both listed")
    rooms.merge_mailbox(ask, mailbox_of(ask, ritz))
    same(mailbox_of(ask, ritz), mailbox_of(ask, home_room))
    local listed = rooms.mergeable_mailboxes(ask)
    same(#listed, 1) same(listed[1].into, mailbox_of(ask, home_room), "programming would now go to home's")
    rooms.merge_mailbox(ask, listed[1].mailbox)
    same(mailbox_of(ask, programming), mailbox_of(ask, home_room))
end)

check("moving the awaited room by hand ends its mailbox's wait", function()
    local ask = kit.test_home(rooms, "mailboxes-hand", "ask")
    local kid = rooms.make_room(ask, room("kid", "h-child", "h-parent", "group", kit.fresh_port()))
    local own_box = mailbox_of(ask, kid)
    local other = rooms.make_room(ask, room("other", "h-other", ""))
    rooms.write_mailbox(ask, kid, mailbox_of(ask, other))
    same(rooms.read_mailbox(ask, own_box).awaits_parent_of, "", "wait over")
    rooms.make_room(ask, room("parent", "h-parent", ""))
    same(#rooms.mergeable_mailboxes(ask), 0, "nothing to merge: the person placed it")
end)

check("a room already in a settled mailbox keeps it when its parent is changed", function()
    local tree_box = mailbox_of(home, grandchild)
    rooms.write_parent(home, grandchild, rooms.token_fingerprint("m-work"))
    same(mailbox_of(home, grandchild), tree_box)
    rooms.write_parent(home, grandchild, rooms.token_fingerprint("m-ritz"))
end)

check("MAILBOX_KINDS lists tree and direct (waiting retired)", function()
    same(rooms.MAILBOX_KINDS.tree.how_many, "many")
    same(rooms.MAILBOX_KINDS.direct.how_many, "one")
    same(rooms.MAILBOX_KINDS.waiting, nil)
    same(rooms.waiting_mailbox, nil, "no waiting_mailbox function")
    same(rooms.UNHELD_PARENT_KEY, nil, "no mailboxes.unheld-parent")
end)

kit.finish()
