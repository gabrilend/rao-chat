-- 034-test-membership.lua — tests the parent-membership rule ("may this
-- address join this room?") and "which child rooms hold this address?".
--
-- Tiers of trust: a member of a child room must be a member of its
-- declared parent, as this home sees it.  This builds a parent with two
-- members and a child and grandchild, then asks about members, strangers,
-- a member at a different port, a filed room (no rule), a top room (no
-- rule), and a child whose parent is not held here under both answers of
-- tree.unheld-parent-join.
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

-- {{{ local function may
local function may(tag, pair)
    return (tree.may_join(home, tag, pair[1], pair[2]))
end
-- }}}

-- top rooms: no rule
t.equal(may(h, friend), true, "a top room accepts anyone holding its token")
local ok, reason = tree.may_join(home, h, friend[1], friend[2])
t.equal(reason, "", "no reason when accepted")

-- the child: only the parent's members
t.equal(may(r, girlfriend), true, "ritz accepts a member of home")
t.equal(may(r, sister), true, "ritz accepts the sister (member of home)")
t.equal(may(r, friend), false, "ritz refuses the friend (not in home)")
ok, reason = tree.may_join(home, r, friend[1], friend[2])
t.check(reason:find("not a member of the parent room home", 1, true) ~= nil, "the reason names the parent's label")
t.equal(may(r, { "192.168.1.20", 7778 }), false, "the same address at another port is another member")
t.equal(may(r, { "girlfriend.example.org", 7777 }), false, "a hostname is not matched to an IP")

-- the grandchild: only ritz's members (one level up)
t.equal(may(p, girlfriend), true, "programming accepts ritz's member")
t.equal(may(p, sister), false, "programming refuses the sister: in home, not in ritz")

-- a filed room carries no rule
tree.file_under(home, cafe, p)
t.equal(may(cafe, friend), true, "a room filed under programming still accepts anyone")
t.equal(may(cafe, sister), true, "filing adds no rule")

-- adding the sister to ritz lets her into programming
rooms.write_members(home, r, t.members({ girlfriend, sister }))
t.equal(may(p, sister), true, "after the sister joins ritz, programming accepts her")

-- which child rooms hold an address (for the client, when someone leaves)
t.same_list(tree.child_rooms_holding(home, h, girlfriend[1], girlfriend[2]), { r, p },
    "girlfriend is in ritz and programming below home")
t.same_list(tree.child_rooms_holding(home, h, sister[1], sister[2]), { r },
    "sister is in ritz only below home")
t.same_list(tree.child_rooms_holding(home, h, friend[1], friend[2]), {},
    "the friend is in no child of home (cafe is only filed)")
t.same_list(tree.child_rooms_holding(home, r, girlfriend[1], girlfriend[2]), { p },
    "below ritz: programming")
-- a grandchild holding someone the child does not (withdrawn by hand)
rooms.write_members(home, r, t.members({ sister }))
t.same_list(tree.child_rooms_holding(home, h, girlfriend[1], girlfriend[2]), { p },
    "a grandchild is found even when the child no longer holds them")

-- shapes are checked where the pair comes in
t.refuses(function() tree.may_join(home, r, "192.168.1.20", "7777") end, "whole number",
    "a port given as text is refused, not silently unmatched")
t.refuses(function() tree.may_join(home, r, "", 7777) end, "non-empty", "an empty address is refused")
t.refuses(function() tree.child_rooms_holding(home, h, "x", 7.5) end, "whole number",
    "a fractional port is refused")

-- a child whose declared parent is not held here: tree.unheld-parent-join
local away = t.fresh_home(rooms, "membership-unheld")
local lone = rooms.make_room(away, {
    label = "programming", token = "token-prog", kind = "group",
    parent = rooms.token_fingerprint("token-ritz"), filed_under = "", members = {},
})
t.refuses(function() tree.may_join(away, lone, friend[1], friend[2]) end, "tree.unheld-parent-join",
    "unset key: an error, not a default")
rooms.set_config(away, "tree.unheld-parent-join", "refuse")
ok, reason = tree.may_join(away, lone, friend[1], friend[2])
t.equal(ok, false, "refuse: nobody new joins a child whose parent is not held")
t.check(reason:find("not held here", 1, true) ~= nil, "refuse: the reason says why")
rooms.set_config(away, "tree.unheld-parent-join", "accept")
t.equal((tree.may_join(away, lone, friend[1], friend[2])), true, "accept: anyone holding the token joins")
rooms.set_config(away, "tree.unheld-parent-join", "sometimes")
t.refuses(function() tree.may_join(away, lone, friend[1], friend[2]) end, "must be refuse or accept",
    "an unknown value is an error")
-- the key is read only in that case: a home without it answers the rest
t.equal(may(p, girlfriend), false, "the main home never set the key and still answers (girlfriend withdrawn)")

t.finish("034-test-membership")
