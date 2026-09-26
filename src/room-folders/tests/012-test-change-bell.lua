-- 012-test-change-bell.lua — tests for the change bell.
--
-- Listens on the bell while a room is made and changed in every way
-- room-folders can change it, and checks that each write rings exactly
-- its own kind, once, after the change is on disk; that a token change
-- rings "parent" for each held child before "token"; that every kind in
-- the list can be rung and anything else is refused; that "ignore" and
-- "mailbox" take "" or a room tag while room kinds need a tag; that a new
-- top room's mailbox rings nothing but "created", while making the direct
-- mailbox, changing a port and moving a room ring "mailbox"; and that a listener's
-- failure reaches whoever made the change (with the change kept).
-- Run: luajit 012-test-change-bell.lua [project folder]

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local kit = dofile(DIR .. "/src/room-folders/tests/008-kit-for-tests.lua")
local rooms = kit.setup(DIR)
local check, same, same_list, fails = kit.check, kit.same, kit.same_list, kit.fails

-- Every ring heard, as "<tag> <what>" strings, and what the listener saw
-- on disk at the moment of the ring.
local heard = {}
local seen_on_disk = {}
local fail_on = nil

rooms.on_change(function(home, tag, what)
    heard[#heard + 1] = tag .. " " .. what
    -- a room-scoped ring: record the label on disk right now, proving the
    -- write happened before the ring.
    if tag ~= "" and what ~= "removed-room" and rooms.room_exists(home, tag) then
        seen_on_disk[#seen_on_disk + 1] = rooms.read_entry(home, tag).label
    end
    -- the test asked this listener to fail on this kind.
    if fail_on == what then
        error("listener refuses " .. what)
    end
end)

-- {{{ local function spec
local function spec(label, token, parent)
    return { label = label, token = token, kind = "group", parent = parent, filed_under = "", members = {},
             mailbox_port = kit.port_for("group", parent) }
end
-- }}}

-- {{{ local function take
-- The rings heard since the last take, emptying the list.
local function take()
    local got = heard
    heard = {}
    seen_on_disk = {}
    return got
end
-- }}}

local home = rooms.open_home(kit.fresh_home_dir("bell"))
local parent_tag, child_a, child_b

check("make_mailbox rings mailbox once, with \"\" (the mailboxes file is the home's)", function()
    take()
    rooms.make_mailbox(home, { label = "direct messages", kind = "direct", port = kit.DIRECT_PORT })
    same_list(take(), { " mailbox" })
end)

check("make_room rings created once, after the folder is whole (its new mailbox rings nothing more)", function()
    take()
    parent_tag = rooms.make_room(home, spec("parent", "bell-parent", ""))
    same_list(take(), { parent_tag .. " created" })
end)

check("the listener sees the change already on disk", function()
    rooms.write_label(home, parent_tag, "renamed")
    same(seen_on_disk[1], "renamed")
    same_list(take(), { parent_tag .. " label" })
end)

check("each write rings exactly its own kind", function()
    local fp = rooms.token_fingerprint("bell-parent")
    child_a = rooms.make_room(home, spec("a", "bell-a", fp))
    child_b = rooms.make_room(home, spec("b", "bell-b", fp))
    take()
    rooms.write_members(home, child_a, { { address = "h", port = 1, heard = 0 } })
    same_list(take(), { child_a .. " members" }, "members")
    rooms.write_heard(home, child_a, "h", 1, 42)
    same_list(take(), { child_a .. " heard" }, "heard")
    rooms.write_parent(home, child_a, "")
    same_list(take(), { child_a .. " parent" }, "parent")
    rooms.write_parent(home, child_a, fp)
    take()
    rooms.write_filed_under(home, child_b, child_a)
    same_list(take(), { child_b .. " filed" }, "filed")
end)

check("change_token rings parent for each held child, then token", function()
    rooms.change_token(home, parent_tag, "bell-parent-2")
    local got = take()
    same(#got, 3, "three rings")
    local children = { got[1], got[2] }
    table.sort(children)
    local want = { child_a .. " parent", child_b .. " parent" }
    table.sort(want)
    same_list(children, want, "children first")
    same(got[3], parent_tag .. " token", "token last")
end)

check("every listed kind can be rung; the list is the contract's", function()
    local want = { "created", "label", "token", "members", "heard", "parent", "filed",
                   "withheld", "log", "ignore", "removed-room", "mailbox" }
    local count = 0
    for _ in pairs(rooms.BELL_KINDS) do count = count + 1 end
    same(count, #want, "number of kinds")
    for _, what in ipairs(want) do
        same(rooms.BELL_KINDS[what] ~= nil, true, "listed: " .. what)
        rooms.notify(home, child_a, what)
    end
    same(#take(), #want)
end)

check("an unknown kind is an error (round 1's kinds included)", function()
    for _, what in ipairs({ "name", "recipients", "split", "rename", "" }) do
        fails(function() rooms.notify(home, child_a, what) end, "unknown kind")
    end
end)

check("ignore takes \"\" (whole home) or a room tag", function()
    rooms.notify(home, "", "ignore")
    rooms.notify(home, child_a, "ignore")
    same_list(take(), { " ignore", child_a .. " ignore" })
    fails(function() rooms.notify(home, "somebody", "ignore") end, "or a local tag")
end)

check("mailbox takes \"\" (the mailboxes file) or a room tag (that room moved)", function()
    rooms.notify(home, "", "mailbox")
    rooms.notify(home, child_a, "mailbox")
    same_list(take(), { " mailbox", child_a .. " mailbox" })
    fails(function() rooms.notify(home, "7777", "mailbox") end, "or a local tag")
end)

check("write_mailbox_port rings mailbox with \"\"; write_mailbox rings it with the room's tag", function()
    local own = rooms.read_entry(home, parent_tag).mailbox
    take()
    rooms.write_mailbox_port(home, own, kit.fresh_port())
    same_list(take(), { " mailbox" }, "port")
    local other_top = rooms.make_room(home, spec("other", "bell-other", ""))
    take()
    rooms.write_mailbox(home, child_b, rooms.read_entry(home, other_top).mailbox)
    same_list(take(), { child_b .. " mailbox" }, "moved")
end)

check("room kinds need a local tag", function()
    fails(function() rooms.notify(home, "", "members") end, "must be rung with a local tag")
    fails(function() rooms.notify(home, nil, "log") end, "must be rung with a local tag")
    fails(function() rooms.notify({}, child_a, "log") end, "home")
end)

check("a listener's failure reaches the writer; the change is kept (keep-and-raise)", function()
    fail_on = "label"
    fails(function() rooms.write_label(home, child_a, "kept anyway") end, "listener refuses label")
    fail_on = nil
    same(rooms.read_entry(home, child_a).label, "kept anyway")
    take()
end)

check("a listener failing on created: the room exists, the maker hears the error", function()
    fail_on = "created"
    local before = #rooms.list_rooms(home)
    fails(function() rooms.make_room(home, spec("c", "bell-c", "")) end, "listener refuses created")
    fail_on = nil
    same(#rooms.list_rooms(home), before + 1)
    take()
end)

check("on_change refuses a non-function", function()
    fails(function() rooms.on_change("not a function") end, "needs a function")
end)

check("listener_count counts signed-up listeners", function()
    same(rooms.listener_count(), 1)
end)

kit.finish()
