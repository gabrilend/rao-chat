-- 028-test-mailboxes.lua — tests that a room's mailbox follows its
-- declared parent, and that the tree and the mailboxes tell the same story
-- when rooms arrive bottom-up.
--
-- A mailbox is a group of rooms with its own listening port: one per
-- top-level room, its declared children inside it (issue 101 chooses and
-- stores it; the room tree only hears the bell ring "mailbox").  The hard
-- case is a child made while its declared parent is not held here.  The
-- owner answered (round 4): it always gets a mailbox and port of its own,
-- and once the parent arrives its mailbox can merge into the parent's.
-- Whether that merge happens by itself is 101's setting
-- mailboxes.merge-when-parent-arrives:
--   automatic  the rooms move into the parent's mailbox as it arrives;
--   ask        nothing moves; 101's mergeable_mailboxes lists the merge
--              until the person says yes with merge_mailbox.
-- This test builds the chain home > ritz > programming bottom-up
-- (programming first, then ritz, then home) under each value, and checks
-- the mailboxes, the tree's placement and the membership check at every
-- step.  It also checks a child made after its parent (joins the parent's
-- mailbox under either value) and a direct message (the direct mailbox;
-- a top room in the tree, kind direct).  Whatever the mailboxes do, the
-- tree drawn is the same: mailboxes place nothing.
--
-- Runs only against the real room-folders module: the stand-in keeps no
-- mailboxes.
-- Run: luajit 028-test-mailboxes.lua [DIR] real

local DIR = "/home/ritz/programs/rao-chat"
-- a project folder given first: use it; otherwise the one above
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end

local t = dofile(DIR .. "/src/room-tree/tests/031-test-support.lua")
-- only the real module: mailboxes are 101's, the stand-in has none
if arg[2] ~= "real" then
    error("028 runs only against the real room-folders module (second argument real)")
end
local rooms, tree = t.setup(DIR, arg[2])

-- A shared port is a warning; warnings are errors here (house rule), so
-- every warning 101 reports fails the test.
rooms.set_warning_sink(function(text)
    t.check(false, "101 reported a warning: " .. tostring(text))
end)

local girlfriend = { "192.168.1.20", 7777 }

-- {{{ local function mailbox_of
local function mailbox_of(home, tag)
    return rooms.read_entry(home, tag).mailbox
end
-- }}}

-- {{{ local function bottom_up
-- Makes programming, then ritz, then home, each naming the next as its
-- declared parent; gives the three tags and the mailbox of each after
-- every step, as a list of { p, r, h } mailbox triples ("" not yet made).
local function bottom_up(home)
    local steps = {}
    local p = t.make(rooms, home, {
        label = "programming", token = "token-prog", kind = "group",
        parent = rooms.token_fingerprint("token-ritz"), filed_under = "",
        members = t.members({ girlfriend }),
    })
    steps[1] = { mailbox_of(home, p), "", "" }
    local r = t.make(rooms, home, {
        label = "ritz", token = "token-ritz", kind = "group",
        parent = rooms.token_fingerprint("token-home"), filed_under = "",
        members = t.members({ girlfriend }),
    })
    steps[2] = { mailbox_of(home, p), mailbox_of(home, r), "" }
    local h = t.room(rooms, home, "home", "token-home", "", { girlfriend })
    steps[3] = { mailbox_of(home, p), mailbox_of(home, r), mailbox_of(home, h) }
    return p, r, h, steps
end
-- }}}

-- {{{ local function sorted
local function sorted(list)
    local copy = {}
    for i, v in ipairs(list) do copy[i] = v end
    table.sort(copy)
    return copy
end
-- }}}

-- ---------------------------------------------------------------------
-- automatic: each room made without its parent gets its own mailbox, and
-- merges into the parent's as the parent arrives
-- ---------------------------------------------------------------------

local auto = t.fresh_home(rooms, "mailboxes-automatic")
-- fresh_home already says automatic; set again so the test reads alone
rooms.set_config(auto, "mailboxes.merge-when-parent-arrives", "automatic")
local p, r, h, steps = bottom_up(auto)
t.check(steps[1][1] ~= "", "automatic: programming, parent not held, gets a mailbox of its own")
t.equal(steps[2][1], steps[2][2], "automatic: ritz arrives; programming merges into ritz's mailbox")
t.check(steps[2][2] ~= steps[1][1], "automatic: ritz, its own parent not held, has a mailbox of its own")
t.check(steps[3][3] ~= steps[2][2], "automatic: home, a top room, has a tree mailbox of its own")
t.equal(steps[3][2], steps[3][3], "automatic: home arrives; ritz merges into home's mailbox")
t.equal(steps[3][1], steps[3][3], "automatic: and programming, two levels down, moves with it")
t.same_list(rooms.list_rooms_by_mailbox(auto, steps[3][3]), sorted({ p, r, h }),
    "automatic: home's mailbox holds the whole tree")
t.equal(#rooms.list_rooms_by_mailbox(auto, steps[1][1]), 0,
    "automatic: programming's first mailbox is left empty (its old port is kept for phase 2)")
t.equal(#rooms.mergeable_mailboxes(auto), 0, "automatic: nothing is left waiting for a yes")
t.equal(tree.path_of_labels(auto, p), "home/ritz/programming", "automatic: the tree agrees")
t.equal(tree.read_where(auto, p).labels, "home/ritz/programming", "automatic: where rewritten through the rings")
t.equal((tree.check_member(auto, p, girlfriend[1], girlfriend[2])), "yes", "automatic: the chain is whole, yes")

-- a child made after its parent: the parent's mailbox
local games = t.room(rooms, auto, "games", "token-games", r, {})
t.equal(mailbox_of(auto, games), steps[3][3], "automatic: a child made under a held parent joins its mailbox")

-- ---------------------------------------------------------------------
-- ask: the same arrivals move nothing until the person says yes
-- ---------------------------------------------------------------------

local ask = t.fresh_home(rooms, "mailboxes-ask")
rooms.set_config(ask, "mailboxes.merge-when-parent-arrives", "ask")
p, r, h, steps = bottom_up(ask)
t.check(steps[1][1] ~= "", "ask: programming gets a mailbox of its own")
t.check(steps[2][2] ~= steps[2][1], "ask: ritz arrives; programming stays in its own, ritz gets another")
t.check(steps[3][3] ~= steps[3][2] and steps[3][3] ~= steps[3][1], "ask: home a third")
t.equal(steps[3][1], steps[1][1], "ask: programming keeps its mailbox when its parents arrive")
t.equal(steps[3][2], steps[2][2], "ask: ritz keeps its mailbox when home arrives")
t.equal(#rooms.read_mailboxes(ask), 3, "ask: one tree drawn, three mailboxes (three ports) listening")
t.equal(tree.path_of_labels(ask, p), "home/ritz/programming", "ask: the tree is the same; only the ports differ")
t.equal((tree.check_member(ask, p, girlfriend[1], girlfriend[2])), "yes", "ask: the check does not look at mailboxes")
local waiting = rooms.mergeable_mailboxes(ask)
t.equal(#waiting, 2, "ask: two merges wait for a yes")
local by_room = {}
for _, row in ipairs(waiting) do by_room[row.room] = row end
t.check(by_room[p] ~= nil and by_room[p].into == steps[3][2], "ask: programming's mailbox would merge into ritz's")
t.check(by_room[r] ~= nil and by_room[r].into == steps[3][3], "ask: ritz's mailbox would merge into home's")
-- the person says yes to ritz: ritz moves; programming's merge now points at home's
rooms.merge_mailbox(ask, by_room[r].mailbox)
t.equal(mailbox_of(ask, r), steps[3][3], "ask: yes to ritz — ritz moves into home's mailbox")
t.equal(mailbox_of(ask, p), steps[1][1], "ask: programming still waits in its own")
waiting = rooms.mergeable_mailboxes(ask)
t.check(#waiting == 1 and waiting[1].room == p and waiting[1].into == steps[3][3],
    "ask: programming's merge now leads into home's mailbox, where ritz is")
rooms.merge_mailbox(ask, waiting[1].mailbox)
t.equal(mailbox_of(ask, p), steps[3][3], "ask: yes to programming — the whole tree in home's mailbox")
t.equal(#rooms.mergeable_mailboxes(ask), 0, "ask: nothing left waiting")
t.equal(tree.path_of_labels(ask, p), "home/ritz/programming", "ask: merging moved nothing in the tree")
games = t.room(rooms, ask, "games", "token-games", r, {})
t.equal(mailbox_of(ask, games), steps[3][3], "ask: a child made under held ritz joins ritz's mailbox")
local own = ask

-- ---------------------------------------------------------------------
-- a direct message: the direct mailbox; a top room of kind direct
-- ---------------------------------------------------------------------

local sam = t.make(rooms, own, {
    label = "sam", token = "token-sam", kind = "direct", parent = "", filed_under = "",
    members = t.members({ { "10.0.0.9", 7777 } }),
})
t.equal(mailbox_of(own, sam), rooms.direct_mailbox(own), "a direct message goes in the direct mailbox")
t.equal(tree.placement(own, sam).how, "top", "a direct message is a top room in the tree")

-- a room moved to another mailbox by hand: nothing in the tree changes
local before = tree.path_of_labels(own, games)
rooms.write_mailbox(own, games, steps[1][1])
t.equal(tree.path_of_labels(own, games), before, "moving a room's mailbox moves nothing in the tree")

t.finish("028-test-mailboxes")
