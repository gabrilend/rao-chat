-- 035-test-rings.lua — tests the one way the tree can end up with rooms
-- inside each other in a ring, and both answers to it.
--
-- Filing refuses a ring when you file.  But a ring can close later,
-- without anyone filing: you hold `programming` (its declared parent
-- `ritz` not held here), and you filed `home` under `programming`.  Then
-- you are invited to `ritz`, whose own declared parent is `home`:
-- programming sits under ritz, ritz under home, home (filed) under
-- programming.  tree.filing-loop decides: refuse (the arrival fails
-- loudly) or unfile (the filed rooms in the ring are unfiled; declared
-- parents win).
--
-- Run: luajit 035-test-rings.lua [DIR] stand-in|real

local DIR = "/home/ritz/programs/rao-chat"
-- a project folder given first: use it; otherwise the one above
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end

local t = dofile(DIR .. "/src/room-tree/tests/031-test-support.lua")
local rooms, tree = t.setup(DIR, arg[2])

-- {{{ local function set_up_ring
-- Gives home, and the tags of home and programming, one step before the
-- ring closes.
local function set_up_ring(name)
    local home = t.fresh_home(rooms, name)
    local h = t.room(rooms, home, "home", "token-home", "", {})
    local p = t.make(rooms, home, {
        label = "programming", token = "token-prog", kind = "group",
        parent = rooms.token_fingerprint("token-ritz"), filed_under = "", members = {},
    })
    tree.file_under(home, h, p)
    return home, h, p
end
-- }}}

-- {{{ local function arrive_ritz
local function arrive_ritz(home)
    return t.make(rooms, home, {
        label = "ritz", token = "token-ritz", kind = "group",
        parent = rooms.token_fingerprint("token-home"), filed_under = "", members = {},
    })
end
-- }}}

-- unfile: declared parents win
local home, h, p = set_up_ring("rings-unfile")
t.equal(tree.read_where(home, h).labels, "programming/home", "before: home filed under programming")
rooms.set_config(home, "tree.filing-loop", "unfile")
local r = arrive_ritz(home)
t.equal(rooms.read_entry(home, h).filed_under, "", "unfile: home's filing was removed")
t.same_list(tree.ancestors(home, p), { h, r, p }, "unfile: home / ritz / programming, as declared")
t.equal(tree.read_where(home, p).labels, "home/ritz/programming", "unfile: where rewritten")
t.equal(tree.read_where(home, h).labels, "home", "unfile: home is a top again")

-- refuse: the arrival fails loudly, the room is on disk, the tree unusable
home, h, p = set_up_ring("rings-refuse")
rooms.set_config(home, "tree.filing-loop", "refuse")
t.refuses(function() arrive_ritz(home) end, "filing made a ring", "refuse: the arrival raises")
t.refuses(function() tree.tops(home) end, "in a ring", "refuse: every question about the tree now errors")
rooms.write_filed_under(home, h, "")
t.equal(#tree.tops(home), 1, "refuse: unfiling by hand mends it")

-- no key set: an error when the case happens (not before)
home, h, p = set_up_ring("rings-unset")
t.refuses(function() arrive_ritz(home) end, "tree.filing-loop", "unset key: an error naming it")

-- an unknown value
home, h, p = set_up_ring("rings-typo")
rooms.set_config(home, "tree.filing-loop", "maybe")
t.refuses(function() arrive_ritz(home) end, "must be refuse or unfile", "unknown value: an error")

-- The declared settings (round 4): 101 refuses any config line no module
-- declares, and any read of an undeclared name, so 023-settings.lua must
-- list exactly what this module reads — tree.filing-loop, the options
-- file's one switchable key, read by name in 021-room-tree.lua.
do
    local declared = dofile(DIR .. "/src/room-tree/023-settings.lua")
    local switched = {}
    for _, choice in ipairs(dofile(DIR .. "/src/room-tree/039-options.lua")) do
        -- a switchable choice: its key must be declared
        if choice.config_key ~= "" then
            switched[#switched + 1] = choice.config_key
        end
    end
    table.sort(declared)
    table.sort(switched)
    t.same_list(declared, switched, "023-settings declares exactly the options file's switchable keys")
    local source = assert(io.open(DIR .. "/src/room-tree/021-room-tree.lua", "rb")):read("*a")
    t.check(source:find('"tree.filing-loop"', 1, true) ~= nil, "tree.filing-loop is read by name in 021")
    -- the real 101: it found the name by scanning src/, owned by room-tree
    if t.which == "real" then
        local owner = rooms.declared_settings()["tree.filing-loop"]
        t.check(owner ~= nil and owner.module == "room-tree", "the real 101 lists tree.filing-loop as room-tree's")
        local typo = t.fresh_home(rooms, "rings-undeclared")
        t.refuses(function() rooms.set_config(typo, "tree.filing-loops", "unfile") end,
            "tree.filing-loops", "the real 101 refuses a misspelt tree setting")
    end
end

t.finish("035-test-rings")
