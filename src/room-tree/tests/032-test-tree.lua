-- 032-test-tree.lua — tests one home's tree: declared children, filing,
-- top rooms, ancestors, paths of labels, and the `where` notes.
--
-- Builds the owner's rooms in a scratch home folder in RAM — `home`, a
-- child `ritz`, a grandchild `programming` — then relabels, files and
-- unfiles rooms, joins a parent late, changes a token and removes a room
-- the way a person (or phase 2) would, and checks that every answer and
-- every `where` note follows.
--
-- Run: luajit 032-test-tree.lua [DIR] stand-in|real

local DIR = "/home/ritz/programs/rao-chat"
-- a project folder given first: use it; otherwise the one above
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end

local t = dofile(DIR .. "/src/room-tree/tests/031-test-support.lua")
local rooms, tree = t.setup(DIR, arg[2])

-- {{{ local function where_raw
local function where_raw(home, tag)
    local f = assert(io.open(rooms.room_dir(home, tag) .. "/where"))
    local text = f:read("*a")
    f:close()
    return text
end
-- }}}

-- ---- a three-level tree on one home
local home = t.fresh_home(rooms, "tree")
local h = t.room(rooms, home, "home", "token-home", "", { { "10.0.0.2", 7777 }, { "10.0.0.3", 7777 } })
local r = t.room(rooms, home, "ritz", "token-ritz", h, { { "10.0.0.2", 7777 } })
local p = t.room(rooms, home, "programming", "token-prog", r, { { "10.0.0.2", 7777 } })
local other = t.room(rooms, home, "other", "token-other", "", {})

t.same_list(tree.ancestors(home, p), { h, r, p }, "ancestors of programming: home, ritz, programming")
t.same_list(tree.ancestors(home, h), { h }, "ancestors of a top room: itself")
t.same_list(tree.children_of(home, h), { r }, "children of home: ritz")
t.same_list(tree.children_of(home, p), {}, "children of programming: none")
t.same_list(tree.tops(home), { h, other }, "tops: home, other (by label)")
t.equal(tree.declared_parent_of(home, p), r, "declared parent of programming is ritz")
t.equal(tree.tree_parent_of(home, p), r, "tree parent of programming is ritz")
t.equal(tree.declared_parent_of(home, h), "", "a top room has no declared parent")
t.equal(tree.placement(home, p).how, "declared", "programming is placed as declared")
t.equal(tree.placement(home, h).how, "top", "home is a top")
t.equal(tree.path_of_labels(home, p), "home/ritz/programming", "path of labels")

-- where is written on creation, because loading 021 listens on the bell
local w = tree.read_where(home, p)
t.equal(w.labels, "home/ritz/programming", "where labels written on create")
t.equal(w.folder, rooms.room_dir(home, p), "where folder is the room's own folder")
t.equal(tree.read_where(home, other).labels, "other", "where of a lone top room")
t.equal(where_raw(home, r), "folder = " .. rooms.room_dir(home, r) .. "\nlabels = home/ritz\n",
    "where file shape: two key = value lines")

-- relabelling a room rewrites it and everything below
rooms.write_label(home, r, "ritz-stuff")
t.equal(tree.read_where(home, r).labels, "home/ritz-stuff", "relabel rewrites the room's where")
t.equal(tree.read_where(home, p).labels, "home/ritz-stuff/programming", "relabel rewrites where below")
t.equal(tree.read_where(home, h).labels, "home", "relabel leaves the room above alone")
rooms.write_label(home, r, "ritz")

-- labels may hold "=" and "/" (issue 101); the path escapes "/" and "\"
rooms.write_label(home, other, "a = b")
t.equal(tree.read_where(home, other).labels, "a = b", "a label holding = survives where")
rooms.write_label(home, r, "ri/tz")
t.equal(tree.path_of_labels(home, p), "home/ri\\/tz/programming", "a / in a label is written \\/")
local where_split = require("022-where-file").split_path(tree.read_where(home, p).labels)
t.same_list(where_split, { "home", "ri/tz", "programming" }, "split_path gives the labels back")
rooms.write_label(home, r, "back\\slash")
t.same_list(require("022-where-file").split_path(tree.path_of_labels(home, p)),
    { "home", "back\\slash", "programming" }, "a \\ in a label survives the path")
rooms.write_label(home, r, "ritz")
rooms.write_label(home, other, "other")

-- the same label twice: two rooms, ordered by tag
local twin1 = t.room(rooms, home, "coffee-shop", "token-c1", "", {})
local twin2 = t.room(rooms, home, "coffee-shop", "token-c2", "", {})
local first, second = twin1, twin2
if twin2 < twin1 then
    first, second = twin2, twin1
end
t.same_list(tree.tops(home), { first, second, h, other }, "two rooms labelled coffee-shop: both tops, by tag")

-- ---- filing: your own placement, shown in the same tree
tree.file_under(home, other, p)
t.equal(tree.tree_parent_of(home, other), p, "other filed under programming")
t.equal(tree.placement(home, other).how, "filed", "other is placed as filed")
t.equal(tree.declared_parent_of(home, other), "", "filing is not a declared parent")
t.equal(tree.read_where(home, other).labels, "home/ritz/programming/other", "where follows a filing")
t.same_list(tree.children_of(home, p), { other }, "programming's children include the filed room")
t.same_list(tree.tops(home), { first, second, h }, "a filed room is no longer a top")

-- relabelling above a filed room reaches it too
rooms.write_label(home, h, "house")
t.equal(tree.read_where(home, other).labels, "house/ritz/programming/other", "relabel above reaches a filed room")
rooms.write_label(home, h, "home")

-- a room with a declared parent and a filing shows under its declared parent
tree.file_under(home, p, twin1)
t.equal(tree.tree_parent_of(home, p), r, "declared parent wins over filing")
t.equal(tree.placement(home, p).how, "declared", "still placed as declared")
t.equal(rooms.read_entry(home, p).filed_under, twin1, "the filing is kept in the entry")
tree.file_under(home, p, "")
t.equal(rooms.read_entry(home, p).filed_under, "", "unfiled")

-- refusals
t.refuses(function() tree.file_under(home, other, other) end, "under itself", "filing a room under itself")
t.refuses(function() tree.file_under(home, other, string.rep("0", 32)) end, "not held here",
    "filing under a room not held here")
t.refuses(function() tree.file_under(home, h, other) end, "sits inside it",
    "filing home under other (which sits inside home) would close a ring")
t.refuses(function() tree.children_of(home, string.rep("1", 32)) end, "is held here",
    "asking about a room not held here")

tree.file_under(home, other, "")
t.equal(tree.read_where(home, other).labels, "other", "unfiling puts it back at the top")

-- ---- a declared parent not held here: the child is a top, marked
local home2 = t.fresh_home(rooms, "unheld")
local lone = t.room(rooms, home2, "programming", "token-prog", "", {})
rooms.write_parent(home2, lone, rooms.token_fingerprint("token-ritz"))
t.same_list(tree.tops(home2), { lone }, "a child whose parent is not held is a top")
t.equal(tree.placement(home2, lone).how, "top", "placed as top")
t.equal(tree.placement(home2, lone).parent_unheld, true, "marked parent not held")
t.equal(tree.declared_parent_of(home2, lone), "", "no held declared parent")
t.equal(tree.read_where(home2, lone).labels, "programming", "where: just its own label")

-- filed while its parent is not held: shows where filed
local shelf = t.room(rooms, home2, "shelf", "token-shelf", "", {})
tree.file_under(home2, lone, shelf)
t.equal(tree.read_where(home2, lone).labels, "shelf/programming", "unheld parent + filing: under the filing")

-- the parent arrives (you are invited to ritz): the tree joins by itself
local r2 = t.room(rooms, home2, "my-ritz", "token-ritz", "", {})
t.equal(tree.tree_parent_of(home2, lone), r2, "the arriving parent takes the child")
t.equal(tree.placement(home2, lone).parent_unheld, false, "no longer marked")
t.equal(tree.read_where(home2, lone).labels, "my-ritz/programming", "where rewritten when the parent arrives")

-- ---- a token changed by hand: room-folders re-points held children
rooms.change_token(home, r, "token-ritz-new")
t.equal(tree.tree_parent_of(home, p), r, "after ritz's token changes, programming is still its child")
t.equal(rooms.read_entry(home, p).parent, rooms.token_fingerprint("token-ritz-new"),
    "programming now names the new fingerprint")
t.equal(tree.read_where(home, p).labels, "home/ritz/programming", "where unchanged by a token change")

-- ---- a removed room: rooms filed under it are unfiled, children become tops
local home3 = t.fresh_home(rooms, "removed")
local a = t.room(rooms, home3, "a", "token-a", "", {})
local b = t.room(rooms, home3, "b", "token-b", a, {})
local c = t.room(rooms, home3, "c", "token-c", "", {})
tree.file_under(home3, c, a)
t.equal(tree.read_where(home3, c).labels, "a/c", "c filed under a")
-- phase 1 has no remover; remove the folder and ring the bell the way a
-- remover (phase 2, leaving) will
os.execute('rm -rf "' .. rooms.room_dir(home3, a) .. '"')
rooms.notify(home3, a, "removed-room")
t.equal(rooms.read_entry(home3, c).filed_under, "", "removing a unfiles c")
t.equal(tree.read_where(home3, c).labels, "c", "c is a top again")
t.equal(tree.placement(home3, b).parent_unheld, true, "b's declared parent is gone: marked")
t.equal(tree.read_where(home3, b).labels, "b", "b is a top again")

-- ---- write_all_where rebuilds every note
os.remove(rooms.room_dir(home, p) .. "/where")
tree.write_all_where(home)
t.equal(tree.read_where(home, p).labels, "home/ritz/programming", "write_all_where rebuilds a missing where")
os.remove(rooms.room_dir(home, p) .. "/where")
t.refuses(function() tree.read_where(home, p) end, "no where file", "reading a missing where is an error")

t.finish("032-test-tree")
