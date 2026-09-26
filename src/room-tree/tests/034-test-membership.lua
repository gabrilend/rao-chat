-- 034-test-membership.lua — tests the parent-membership check ("does this
-- address belong in this room, by the rooms declared above it?") and the
-- re-check ("which members below this room now fail it?").
--
-- Tiers of trust, detected rather than enforced: a member of a child room
-- should be a member of every declared room above it, as this home sees
-- it.  The check answers yes, no, or cannot-check (a room above is not
-- held here); nothing is ever refused.  This builds home > ritz >
-- programming, then asks about members, strangers, someone in the child
-- but missing from the grandparent, a member at a different port, a filed
-- room (no rule), a top room (no rule), a chain that runs into a room not
-- held here (directly, and one level further up), and re-checks after
-- someone is dropped from `home`.
--
-- Run: luajit 034-test-membership.lua [DIR] stand-in|real

local DIR = "/home/ritz/programs/rao-chat"
-- a project folder given first: use it; otherwise the one above
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end

local t = dofile(DIR .. "/src/room-tree/tests/031-test-support.lua")
local rooms, tree = t.setup(DIR, arg[2])

local home = t.fresh_home(rooms, "membership")
local girlfriend = { "192.168.1.20", 7777 }
local sister = { "sister.example.org", 7001 }
local friend = { "203.0.113.9", 7777 }

local h = t.room(rooms, home, "home", "token-home", "", { girlfriend, sister })
local r = t.room(rooms, home, "ritz", "token-ritz", h, { girlfriend })
local p = t.room(rooms, home, "programming", "token-prog", r, { girlfriend })
local cafe = t.room(rooms, home, "cafe", "token-cafe", "", { friend })

-- {{{ local function answer
local function answer(tag, pair)
    return (tree.check_member(home, tag, pair[1], pair[2]))
end
-- }}}

-- top rooms: no rule
t.equal(answer(h, friend), "yes", "a top room: yes for anyone holding its token")
local said, reason = tree.check_member(home, h, friend[1], friend[2])
t.equal(reason, "", "no reason for yes")

-- the child: the parent's members
t.equal(answer(r, girlfriend), "yes", "ritz: yes for a member of home")
t.equal(answer(r, sister), "yes", "ritz: yes for the sister (member of home)")
t.equal(answer(r, friend), "no", "ritz: no for the friend (not in home)")
said, reason = tree.check_member(home, r, friend[1], friend[2])
t.check(reason:find("is not a member of home", 1, true) ~= nil, "the reason names the room above")
t.equal(answer(r, { "192.168.1.20", 7778 }), "no", "the same address at another port is another member")
t.equal(answer(r, { "girlfriend.example.org", 7777 }), "no", "a hostname is not matched to an IP")

-- the grandchild: every room above, not only the parent
t.equal(answer(p, girlfriend), "yes", "programming: yes for someone in ritz and home")
t.equal(answer(p, sister), "no", "programming: no for the sister, in home but not ritz")
rooms.write_members(home, r, t.members({ girlfriend, sister, friend }))
t.equal(answer(p, friend), "no", "programming: no for the friend, in ritz but missing from the grandparent home")
said, reason = tree.check_member(home, p, friend[1], friend[2])
t.check(reason:find("not a member of home", 1, true) ~= nil and reason:find("ritz", 1, true) == nil,
    "the reason names home, and not ritz (which holds the friend)")
said, reason = tree.check_member(home, p, "198.51.100.1", 9)
t.check(reason:find("ritz, home", 1, true) ~= nil, "a stranger: the reason names every room lacking them, nearest first")
t.equal(answer(p, sister), "yes", "after the sister joins ritz, programming: yes")

-- a filed room carries no rule
tree.file_under(home, cafe, p)
t.equal(answer(cafe, friend), "yes", "a room filed under programming: yes for anyone")
t.equal(answer(cafe, { "198.51.100.1", 9 }), "yes", "filing adds no rule")

-- one snapshot, many questions: the same answers
local snap = tree.snapshot(home)
t.equal((tree.check_member_in(snap, p, sister[1], sister[2])), "yes", "check_member_in agrees (yes)")
t.equal((tree.check_member_in(snap, r, "198.51.100.1", 9)), "no", "check_member_in agrees (no)")

-- re-checking: failing members of one room, and of everything below.
-- First make every tier agree: everyone in home, the sister in
-- programming too.
rooms.write_members(home, h, t.members({ girlfriend, sister, friend }))
rooms.write_members(home, p, t.members({ girlfriend, sister }))
t.equal(#tree.failing_members(home, h), 0, "home, a top room, has nobody failing")
t.equal(#tree.failing_below(home, h), 0, "nobody below home fails while every tier agrees")
-- drop the sister from home: she is still in ritz and programming
rooms.write_members(home, h, t.members({ girlfriend, friend }))
local failing = tree.failing_below(home, h)
local seen = {}
for _, row in ipairs(failing) do
    seen[#seen + 1] = row.room .. " " .. row.address .. " " .. row.answer
end
t.same_list(seen, {
    r .. " sister.example.org no",
    p .. " sister.example.org no",
}, "dropping the sister from home: she fails in ritz and in home's grandchild programming")
t.check(failing[2].reason:find("not a member of home", 1, true) ~= nil,
    "the grandchild's reason names home")
t.equal(failing[1].port, 7001, "each row carries the port as a whole number")
t.equal(#tree.failing_below(home, r), 1, "below ritz only programming's row")
t.equal(#tree.failing_members(home, r), 1, "ritz itself: the sister")
t.equal(#tree.failing_below(home, cafe), 0, "a filed room has no declared children")

-- shapes are checked where the pair comes in
t.refuses(function() tree.check_member(home, r, "192.168.1.20", "7777") end, "whole number",
    "a port given as text is refused, not silently unmatched")
t.refuses(function() tree.check_member(home, r, "", 7777) end, "non-empty", "an empty address is refused")
t.refuses(function() tree.check_member_in(snap, h, "x", 7.5) end, "whole number",
    "a fractional port is refused")
t.refuses(function() tree.failing_below(home, "00000000000000000000000000000000") end, "no room",
    "re-checking a room not held here is an error")

-- chains running into a room not held here: cannot-check
local away = t.fresh_home(rooms, "membership-unheld")
-- programming alone: its parent ritz is not held
local lone = t.make(rooms, away, {
    label = "programming", token = "token-prog", kind = "group",
    parent = rooms.token_fingerprint("token-ritz"), filed_under = "", members = {},
})
said, reason = tree.check_member(away, lone, friend[1], friend[2])
t.equal(said, "cannot-check", "a parent not held: cannot-check")
t.check(reason:find("above programming is not held", 1, true) ~= nil, "the reason says which room's parent is unseen")
-- ritz arrives, still without home: the chain stops one level higher
local r2 = t.make(rooms, away, {
    label = "ritz", token = "token-ritz", kind = "group",
    parent = rooms.token_fingerprint("token-home"), filed_under = "", members = t.members({ girlfriend }),
})
t.equal((tree.check_member(away, lone, girlfriend[1], girlfriend[2])), "cannot-check",
    "held parent holds them but the grandparent is not held: cannot-check")
t.equal((tree.check_member(away, lone, friend[1], friend[2])), "no",
    "held parent lacks them: no, whatever lies beyond")
t.equal((tree.check_member(away, r2, friend[1], friend[2])), "cannot-check", "ritz itself: cannot-check")
rooms.write_members(away, lone, t.members({ girlfriend, friend }))
local rows = tree.failing_below(away, r2)
seen = {}
for _, row in ipairs(rows) do
    seen[#seen + 1] = row.address .. " " .. row.answer
end
t.same_list(seen, { "192.168.1.20 cannot-check", "203.0.113.9 no" },
    "re-check below ritz: both answers are listed")
-- home arrives holding the girlfriend: everything checks
t.room(rooms, away, "home", "token-home", "", { girlfriend })
t.equal((tree.check_member(away, lone, girlfriend[1], girlfriend[2])), "yes", "the whole chain held: yes")
t.equal(#tree.failing_members(away, lone), 1, "only the friend still fails in programming")

t.finish("034-test-membership")
