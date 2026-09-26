-- 037-test-forest-text.lua — tests the tree as data (forest) and drawn as
-- text (024).
--
-- Builds a small home with a declared tree, a filed room and a room whose
-- parent is not held, and checks the nodes' fields and the exact text.
--
-- Run: luajit 037-test-forest-text.lua [DIR] stand-in|real

local DIR = "/home/ritz/programs/rao-chat"
-- a project folder given first: use it; otherwise the one above
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end

local t = dofile(DIR .. "/src/room-tree/tests/031-test-support.lua")
local rooms, tree, text = t.setup(DIR, arg[2])

local home = t.fresh_home(rooms, "forest")
local h = t.room(rooms, home, "home", "token-home", "", {})
local k = t.room(rooms, home, "kitchen", "token-kitchen", h, {})
t.room(rooms, home, "recipes", "token-recipes", k, {})
local g = t.room(rooms, home, "garden", "token-garden", h, {})
local p = t.make(rooms, home, {
    label = "programming", token = "token-prog", kind = "group",
    parent = rooms.token_fingerprint("token-ritz"), filed_under = "", members = {},
})
local sam = t.make(rooms, home, {
    label = "sam", token = "token-sam", kind = "direct",
    parent = "", filed_under = "", members = t.members({ { "10.0.0.9", 7777 } }),
})

local forest = tree.forest(home)
t.equal(#forest, 3, "three tops: home, programming, sam")
t.equal(forest[1].label, "home", "first top: home")
t.equal(forest[1].children[1].label, "garden", "children sorted by label: garden first")
t.equal(forest[1].children[2].children[1].label, "recipes", "grandchild recipes under kitchen")
t.equal(forest[1].children[1].placed, "declared", "garden placed as declared")
t.equal(forest[2].parent_unheld, true, "programming: parent not held")
t.equal(forest[3].kind, "direct", "a direct message is in the forest, kind direct")
t.equal(forest[1].tag, h, "nodes carry the local tag")

tree.file_under(home, p, g)
local drawn = text.text(tree.forest(home))
local wanted = table.concat({
    "home",
    "├── garden",
    "│   └── programming   (filed)   (parent not held here)",
    "└── kitchen",
    "    └── recipes",
    "sam",
}, "\n") .. "\n"
t.equal(drawn, wanted, "drawn as text with both marks")
t.equal(#text.lines(tree.forest(home)), 6, "one line per room")
t.check(sam ~= "", "sam made")

t.finish("037-test-forest-text")
