-- 033-test-two-homes.lua — tests that the same rooms held on two homes
-- form the same tree, each in its own labels.
--
-- Two people hold the same three rooms (the same tokens) but label them
-- differently and keep them in folders with different local tags.  The
-- parent links are fingerprints of tokens, so both homes must work out
-- the same shape; the labels, tags and `where` notes must be each home's
-- own.  A third person holds only the bottom room and sees it as a top.
--
-- Run: luajit 033-test-two-homes.lua [DIR] stand-in|real

local DIR = "/home/ritz/programs/rao-chat"
-- a project folder given first: use it; otherwise the one above
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end

local t = dofile(DIR .. "/src/room-tree/tests/031-test-support.lua")
local rooms, tree = t.setup(DIR, arg[2])

-- ritz's home: home / ritz / programming
local one = t.fresh_home(rooms, "two-homes-ritz")
local h1 = t.room(rooms, one, "home", "maple-orbit-velvet-tin", "", {})
local r1 = t.room(rooms, one, "ritz", "cobalt-ferry-lantern-oak", h1, {})
local p1 = t.room(rooms, one, "programming", "quiet-anvil-saffron-dune", r1, {})

-- the same rooms on a housemate's home, with the housemate's labels.
-- Made bottom-up on purpose (programming arrives first): the tree must
-- join whatever order rooms arrive in.
local two = t.fresh_home(rooms, "two-homes-housemate")
local p2 = t.make(rooms, two, {
    label = "code-club", token = "quiet-anvil-saffron-dune", kind = "group",
    parent = rooms.token_fingerprint("cobalt-ferry-lantern-oak"), filed_under = "", members = {},
})
t.equal(tree.placement(two, p2).parent_unheld, true, "housemate: code-club arrives before its parent")
local r2 = t.make(rooms, two, {
    label = "ritz-corner", token = "cobalt-ferry-lantern-oak", kind = "group",
    parent = rooms.token_fingerprint("maple-orbit-velvet-tin"), filed_under = "", members = {},
})
local h2 = t.make(rooms, two, {
    label = "our-house", token = "maple-orbit-velvet-tin", kind = "group",
    parent = "", filed_under = "", members = {},
})

t.check(p1 ~= p2 and r1 ~= r2 and h1 ~= h2, "the two homes' local tags differ")
t.equal(rooms.read_entry(one, p1).parent, rooms.read_entry(two, p2).parent,
    "the fingerprints naming the parent match on both homes")
t.equal(tree.path_of_labels(one, p1), "home/ritz/programming", "ritz's path, ritz's labels")
t.equal(tree.path_of_labels(two, p2), "our-house/ritz-corner/code-club", "housemate's path, housemate's labels")
t.equal(tree.read_where(two, p2).labels, "our-house/ritz-corner/code-club", "housemate's where joined bottom-up")
t.equal(tree.read_where(two, p2).folder, rooms.room_dir(two, p2), "housemate's where names its own folder")
t.equal(#tree.ancestors(one, p1), #tree.ancestors(two, p2), "same depth on both homes")
t.equal(#tree.tops(one), 1, "ritz: one tree")
t.equal(#tree.tops(two), 1, "housemate: one tree")

-- a friend holds only programming: a top, marked, in the friend's label
local three = t.fresh_home(rooms, "two-homes-friend")
local p3 = t.make(rooms, three, {
    label = "programming", token = "quiet-anvil-saffron-dune", kind = "group",
    parent = rooms.token_fingerprint("cobalt-ferry-lantern-oak"), filed_under = "", members = {},
})
t.same_list(tree.tops(three), { p3 }, "friend: programming is a top")
t.equal(tree.placement(three, p3).parent_unheld, true, "friend: marked as inside a room not held")
t.equal(tree.path_of_labels(three, p3), "programming", "friend: path is its own label")

-- the fingerprint gives nothing back: it is not the token, nor holds it
local print_of = rooms.token_fingerprint("cobalt-ferry-lantern-oak")
t.check(print_of:find("cobalt", 1, true) == nil, "the fingerprint does not contain the token")
t.equal(#print_of, 64, "the fingerprint is 64 characters")

t.finish("033-test-two-homes")
