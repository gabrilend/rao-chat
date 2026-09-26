-- 028-test-mailboxes.lua — tests that a room's mailbox follows its
-- declared parent, and that the tree and the mailboxes tell the same story
-- when rooms arrive bottom-up.
--
-- A mailbox is a group of rooms with its own listening port: one per
-- top-level room, its declared children inside it (issue 101 chooses and
-- stores it; the room tree only hears the bell ring "mailbox").  The hard
-- case is a child made while its declared parent is not held here.  The
-- owner has not chosen what then; 101 builds both answers, switched by the
-- config key mailboxes.unheld-parent:
--   own-mailbox      the child gets a mailbox (and port) of its own, and
--                    keeps it when the parent later arrives;
--   waiting-mailbox  the child waits in the one "waiting" mailbox, and
--                    moves into its parent's mailbox when the parent
--                    arrives.
-- This test builds the chain home > ritz > programming bottom-up
-- (programming first, then ritz, then home) under each answer, and checks
-- the mailboxes, the tree's placement and the membership check at every
-- step.  It also checks a child made after its parent (joins the parent's
-- mailbox under either answer) and a direct message (the direct mailbox;
-- a top room in the tree, kind direct).
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

-- ---------------------------------------------------------------------
-- waiting-mailbox: the chain waits, then settles into home's mailbox
-- ---------------------------------------------------------------------

local wait = t.fresh_home(rooms, "mailboxes-waiting")
rooms.set_config(wait, "mailboxes.unheld-parent", "waiting-mailbox")
t.next_port = t.next_port + 1
local waiting = rooms.make_mailbox(wait, { label = "waiting", kind = "waiting", port = t.next_port })
t.equal(rooms.waiting_mailbox(wait), waiting, "waiting: the one waiting mailbox is made")

local p, r, h, steps = bottom_up(wait)
t.equal(steps[1][1], waiting, "waiting: programming, parent not held, waits")
t.equal(steps[2][1], waiting, "waiting: ritz arrives without home; programming still waits")
t.equal(steps[2][2], waiting, "waiting: ritz, parent not held, waits too")
t.check(steps[3][3] ~= waiting and steps[3][3] ~= "", "waiting: home, a top room, has a tree mailbox of its own")
t.equal(steps[3][2], steps[3][3], "waiting: home arrives; ritz moves into home's mailbox")
t.equal(steps[3][1], steps[3][3], "waiting: and programming, two levels down, moves with it")
t.equal(#rooms.list_rooms_by_mailbox(wait, waiting), 0, "waiting: nothing is left waiting")
t.same_list(rooms.list_rooms_by_mailbox(wait, steps[3][3]), (function()
    local all = { p, r, h }
    table.sort(all)
    return all
end)(), "waiting: home's mailbox holds the whole tree")
t.equal(tree.path_of_labels(wait, p), "home/ritz/programming", "waiting: the tree agrees")
t.equal(tree.read_where(wait, p).labels, "home/ritz/programming", "waiting: where rewritten through the mailbox rings")
t.equal((tree.check_member(wait, p, girlfriend[1], girlfriend[2])), "yes", "waiting: the chain is whole, yes")

-- a child made after its parent: the parent's mailbox
local games = t.room(rooms, wait, "games", "token-games", r, {})
t.equal(mailbox_of(wait, games), steps[3][3], "waiting: a child made under a held parent joins its mailbox")

-- ---------------------------------------------------------------------
-- own-mailbox: every room made without its parent keeps its own
-- ---------------------------------------------------------------------

local own = t.fresh_home(rooms, "mailboxes-own")
-- fresh_home already says own-mailbox; set again so the test reads alone
rooms.set_config(own, "mailboxes.unheld-parent", "own-mailbox")
p, r, h, steps = bottom_up(own)
t.check(steps[1][1] ~= "", "own: programming gets a mailbox of its own")
t.check(steps[2][2] ~= steps[2][1], "own: ritz gets another")
t.check(steps[3][3] ~= steps[3][2] and steps[3][3] ~= steps[3][1], "own: home a third")
t.equal(steps[3][1], steps[1][1], "own: programming keeps its mailbox when its parents arrive")
t.equal(steps[3][2], steps[2][2], "own: ritz keeps its mailbox when home arrives")
t.equal(rooms.waiting_mailbox(own), "", "own: no waiting mailbox is needed")
t.equal(tree.path_of_labels(own, p), "home/ritz/programming", "own: the tree is the same; only the ports differ")
t.equal(#rooms.read_mailboxes(own), 3, "own: one tree drawn, three mailboxes (three ports) listening")
games = t.room(rooms, own, "games", "token-games", r, {})
t.equal(mailbox_of(own, games), steps[2][2], "own: a child made under held ritz joins ritz's own mailbox")

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
rooms.write_mailbox(own, games, steps[3][3])
t.equal(tree.path_of_labels(own, games), before, "moving a room's mailbox moves nothing in the tree")

t.finish("028-test-mailboxes")
