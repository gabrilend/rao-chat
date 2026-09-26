-- 036-test-with-neighbours.lua — tests the room tree together with the
-- real modules that lean on it: members (issue 103, which asks the tree
-- "does this address belong here, by the rooms above?" and adds everyone,
-- flagging those answered no or cannot-check) and the people/ links
-- (issue 104, which finds each person's top rooms from the tree).
--
-- Runs only against the real room-folders module, since the neighbours
-- load it by name.  Builds the owner's household tree, adds people
-- through 103, files a room, and checks that 103's flags follow the
-- tree's answers and that 104's tops agree with the tree.
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
-- 103a reads these when judging an address (see src/recipients/059-options.lua);
-- (only names some module declares may be set; a retired one such as
-- recipients.flag-after-passing is now refused by 101)
rooms.set_config(home, "ignore.scope", "home")
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

-- 103 asks the tree, adds everyone, flags the ones it answers no
t.equal(add(h, girlfriend), "added", "103: girlfriend added to home (a top)")
t.equal(add(h, sister), "added", "103: sister added to home")
t.equal(add(r, friend), "added-flagged", "103: friend added to ritz but flagged (not in home)")
t.equal(add(r, girlfriend), "added", "103: girlfriend added to ritz")
t.equal(add(p, sister), "added-flagged", "103: sister added to programming but flagged (not in ritz)")
t.equal(add(p, girlfriend), "added", "103: girlfriend added to programming")
t.equal(add(cafe, friend), "added", "103: friend added to cafe (a top)")
t.equal(add(r, sister), "added", "103: sister added to ritz")
-- the tree's own view of what 103 flagged
local rows = tree.failing_below(home, h)
local seen = {}
for _, row in ipairs(rows) do
    seen[#seen + 1] = row.room .. " " .. row.address .. " " .. row.answer
end
t.same_list(seen, { r .. " 203.0.113.9 no" },
    "after the sister joins ritz only the friend still fails below home")
-- dropping the sister from home, written straight into the entry: she fails in
-- ritz and in the grandchild programming (every room above counts)
rooms.write_members(home, h, t.members({ girlfriend }))
rows = tree.failing_below(home, h)
seen = {}
for _, row in ipairs(rows) do
    seen[#seen + 1] = row.room .. " " .. row.address
end
t.same_list(seen, { r .. " 203.0.113.9", r .. " sister.example.org", p .. " sister.example.org" },
    "the sister dropped from home fails in ritz and programming")
-- 103's listener heard 'members' on home and re-checked below it with
-- failing_below: the sister is now awaiting review in both rooms
-- {{{ local function flagged_addresses
local function flagged_addresses(tag)
    local out = {}
    for _, row in ipairs(members.flagged(home, tag)) do
        out[#out + 1] = row.address
    end
    table.sort(out)
    return out
end
-- }}}
t.same_list(flagged_addresses(r), { "203.0.113.9", "sister.example.org" },
    "103 flags the friend and the sister in ritz")
t.same_list(flagged_addresses(p), { "sister.example.org" },
    "103 flags the sister in the grandchild programming")

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
-- the friend now sits in ritz too (flagged, not refused), and home does
-- not hold them, so ritz is one of the friend's tops as well as cafe
local friend_tops = { cafe, r }
table.sort(friend_tops)
t.same_list(people_tops_for(friend), friend_tops, "104: friend's tops are cafe and ritz (flagged there)")
t.same_list(people_tops_for(friend), tree_tops_for(friend), "104 agrees with the tree: friend")

-- filing cafe under programming: the friend is not in programming, so
-- cafe is still the friend's top; filing a room holding the girlfriend
-- under home folds it into her home tree
tree.file_under(home, cafe, p)
t.same_list(people_tops_for(friend), friend_tops, "104: filed cafe is still one of the friend's tops")
t.same_list(people_tops_for(friend), tree_tops_for(friend), "104 agrees with the tree: friend, filed")
local games = t.room(rooms, home, "games", "token-games", "", {})
t.equal(add(games, girlfriend), "added", "103: girlfriend added to games (a top)")
local before = people_tops_for(girlfriend)
t.equal(#before, 2, "104: girlfriend now has two tops (home, games)")
tree.file_under(home, games, h)
t.same_list(people_tops_for(girlfriend), { h }, "104: games filed under home folds into her home tree")
t.same_list(people_tops_for(girlfriend), tree_tops_for(girlfriend), "104 agrees with the tree after filing")

-- the girlfriend is in every tier: nothing to flag anywhere below home
local girlfriend_fails = 0
for _, row in ipairs(tree.failing_below(home, h)) do
    -- a row for her: counted; anyone else: not this check's concern
    if row.address == girlfriend[1] then
        girlfriend_fails = girlfriend_fails + 1
    end
end
t.equal(girlfriend_fails, 0, "the girlfriend fails nowhere below home")

t.finish("036-test-with-neighbours")
