-- 036-test-with-neighbours.lua — tests the room tree together with the
-- real modules that lean on it: members (issue 103, which asks the tree
-- "may this address join?" before adding anyone) and the people/ links
-- (issue 104, which finds each person's top rooms from the tree).
--
-- Runs only against the real room-folders module, since the neighbours
-- load it by name.  Builds the owner's household tree, adds people
-- through 103, files a room, and checks that 103's refusals follow the
-- parent-membership rule and that 104's tops agree with the tree.
--
-- Run: luajit 036-test-with-neighbours.lua [DIR] real

local DIR = "/home/ritz/programs/rao-chat"
-- a project folder given first: use it; otherwise the one above
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end

local t = dofile(DIR .. "/src/room-tree/tests/031-test-support.lua")
-- only the real module: the neighbours require it by name themselves
if arg[2] ~= "real" then
    error("036 runs only against the real room-folders module (second argument real)")
end
local rooms, tree = t.setup(DIR, arg[2])
local members = require("041-recipients")
local people = require("061-people-links")

local home = t.fresh_home(rooms, "neighbours")
-- 104 reads these on every rebuild once loaded (see its options file)
rooms.set_config(home, "people.link-collision", "suffix-id")
rooms.set_config(home, "people.direct-message-link", "leave-out")
rooms.set_config(home, "people.members-without-dm", "leave-out")
-- 103a reads these when judging an address (see src/recipients/059-options.lua)
rooms.set_config(home, "ignore.match", "pair")
rooms.set_config(home, "ignore.scope", "home")
rooms.set_config(home, "ignore.hide-files", "filed")
rooms.set_config(home, "recipients.shared-address-label", "all-labels")

local girlfriend = { "192.168.1.20", 7777 }
local sister = { "sister.example.org", 7001 }
local friend = { "203.0.113.9", 7777 }

local h = t.room(rooms, home, "home", "token-home", "", {})
local r = t.room(rooms, home, "ritz", "token-ritz", h, {})
local p = t.room(rooms, home, "programming", "token-prog", r, {})
local cafe = t.room(rooms, home, "cafe", "token-cafe", "", {})

-- {{{ local function add
local function add(tag, pair)
    return (members.add_member(home, tag, pair[1], pair[2]))
end
-- }}}

-- 103 asks the tree before adding
t.equal(add(h, girlfriend), "added", "103: girlfriend added to home (a top)")
t.equal(add(h, sister), "added", "103: sister added to home")
t.equal(add(r, friend), "not-in-parent", "103: friend refused in ritz (not in home)")
t.equal(add(r, girlfriend), "added", "103: girlfriend added to ritz")
t.equal(add(p, sister), "not-in-parent", "103: sister refused in programming (not in ritz)")
t.equal(add(p, girlfriend), "added", "103: girlfriend added to programming")
t.equal(add(cafe, friend), "added", "103: friend added to cafe (a top)")
local word, why = members.add_member(home, p, sister[1], sister[2])
t.check(why ~= nil and why:find("ritz", 1, true) ~= nil, "103 passes on the tree's reason, naming the parent")
t.equal(add(r, sister), "added", "103: sister added to ritz")
t.equal(add(p, sister), "added", "103: now the sister may join programming")

-- member changes do not move anything in the tree
t.equal(tree.read_where(home, p).labels, "home/ritz/programming", "where untouched by member changes")

-- 104's tops agree with the tree
-- {{{ local function tree_tops_for
-- The tops the tree gives for one member: rooms holding them whose tree
-- parent does not.
local function tree_tops_for(pair)
    local snap = tree.snapshot(home)
    local out = {}
    for _, tag in ipairs(snap.tags) do
        local holds = false
        for _, m in ipairs(snap.entries[tag].members) do
            holds = holds or (m.address == pair[1] and m.port == pair[2])
        end
        local up = snap.parent[tag]
        local up_holds = false
        if up ~= "" then
            for _, m in ipairs(snap.entries[up].members) do
                up_holds = up_holds or (m.address == pair[1] and m.port == pair[2])
            end
        end
        if holds and not up_holds then
            out[#out + 1] = tag
        end
    end
    table.sort(out)
    return out
end
-- }}}

-- {{{ local function people_tops_for
local function people_tops_for(pair)
    local got = people.top_rooms_for_addresses(home, { { address = pair[1], port = pair[2] } })
    table.sort(got)
    return got
end
-- }}}

t.same_list(people_tops_for(girlfriend), { h }, "104: girlfriend's one top is home")
t.same_list(people_tops_for(girlfriend), tree_tops_for(girlfriend), "104 agrees with the tree: girlfriend")
t.same_list(people_tops_for(friend), { cafe }, "104: friend's top is cafe")

-- filing cafe under programming: the friend is not in programming, so
-- cafe is still the friend's top; filing a room holding the girlfriend
-- under home folds it into her home tree
tree.file_under(home, cafe, p)
t.same_list(people_tops_for(friend), { cafe }, "104: filed cafe is still the friend's top")
t.same_list(people_tops_for(friend), tree_tops_for(friend), "104 agrees with the tree: friend, filed")
local games = t.room(rooms, home, "games", "token-games", "", {})
t.equal(add(games, girlfriend), "added", "103: girlfriend added to games (a top)")
local before = people_tops_for(girlfriend)
t.equal(#before, 2, "104: girlfriend now has two tops (home, games)")
tree.file_under(home, games, h)
t.same_list(people_tops_for(girlfriend), { h }, "104: games filed under home folds into her home tree")
t.same_list(people_tops_for(girlfriend), tree_tops_for(girlfriend), "104 agrees with the tree after filing")

-- which child rooms hold the girlfriend, for the client's clean-up
t.same_list(tree.child_rooms_holding(home, h, girlfriend[1], girlfriend[2]), { r, p },
    "child rooms of home holding her: ritz, then programming below it (top-down)")

t.finish("036-test-with-neighbours")
