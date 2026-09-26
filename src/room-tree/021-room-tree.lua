-- 021-room-tree.lua — the room tree: rooms inside rooms, like folders.
--
-- The owner pictures the rooms "sorted like a directory tree structure ...
-- Very Microsoft Windows Explorer core."  A room sits under another in one
-- of two ways:
--
--   * declared: it was made as a child of that room.  Its entry's `parent`
--     holds a fingerprint of the parent's token (a one-way scramble, so
--     naming the parent reveals nothing to anyone who does not already
--     hold the parent's token).  Everyone in the child sees the same
--     parent, and every home server enforces one rule for it: an address
--     may join the child only if it is a member of the parent, as this
--     server sees it — the owner's "tiers of trust".
--   * filed: you placed it there on your own screen.  Its entry's
--     `filed-under` holds the local tag of the room it sits under.  Never
--     sent, no rule applied; the owner's first example (the girlfriend in
--     `programming` without being in `ritz`).
--
-- Both show in one tree.  A room with both shows under its declared
-- parent when that parent is held here; otherwise under where you filed
-- it; otherwise it is a top room.  A declared parent that is not held here
-- (you were never invited to it) leaves the room a top, marked so.
--
-- Nothing here stores a tree separately from the entries: every answer is
-- worked out from them on request, in one pass over the home (a snapshot).
-- The one derived file is `where` (022), which this module rewrites for
-- every room whenever a change that could move something in the tree is
-- announced on the room-folders module's change bell — loading this
-- module is enough to keep it current.
--
-- Drawing the tree is 024's job; this file only works it out.

local rooms = require("002-room-folders")
local where_file = require("022-where-file")

local M = {}

-- ---------------------------------------------------------------------
-- what this module asks of room-folders (issue 101), in one place, so a
-- renamed function there is one line to change here
-- ---------------------------------------------------------------------

local ask = {
    list_rooms = rooms.list_rooms,               -- (home) -> sorted list of local tags
    read_entry = rooms.read_entry,               -- (home, tag) -> entry, below
    fingerprint = rooms.token_fingerprint,       -- (token) -> 64 hex characters
    room_dir = rooms.room_dir,                   -- (home, tag) -> string
    config_value = rooms.config_value,           -- (home, key) -> string, errors when absent
    write_filed_under = rooms.write_filed_under, -- (home, tag, tag or ""), rings "filed"
    on_change = rooms.on_change,                 -- (listener(home, tag, what))
}

-- An entry, as read_entry gives it (every field present, "" for none):
--   tag          string, 32 hex, the folder's name, never sent
--   label        string, your own name for the room
--   token        string, the room's shared secret
--   kind         "group" | "direct"
--   parent       string, 64 hex fingerprint of the parent's token, or ""
--   filed_under  string, a local tag held here, or ""
--   members      list of { address = string, port = integer,
--                          heard = integer (seconds since 1970, 0 never) }

-- ---------------------------------------------------------------------
-- the snapshot: every room read once, the tree worked out from it
-- ---------------------------------------------------------------------

-- A snapshot is a table:
--   entries     tag -> the entry read from 101 (shape above)
--   by_print    fingerprint -> tag, for every room held here
--   declared    tag -> the held declared parent's tag, or ""
--   unheld      tag -> true when the entry names a parent fingerprint
--               that matches no room held here
--   parent      tag -> the parent in the tree (declared if held, else
--               filed, else ""), the one every walk follows
--   placed      tag -> "declared" | "filed" | "top"
--   children    tag -> list of child tags in the tree, sorted by label
--               then tag
--   tops        list of top tags, sorted by label then tag

-- {{{ local function by_label_then_tag
local function by_label_then_tag(entries)
    return function(a, b)
        local la, lb = entries[a].label, entries[b].label
        -- different labels: alphabetical; the same label: tag decides, so
        -- two rooms both called "coffee-shop" always come out in one order
        if la ~= lb then
            return la < lb
        end
        return a < b
    end
end
-- }}}

-- {{{ local function index_fingerprints
-- Two held rooms with one token would be one room to everyone else, and a
-- child naming that token could not say which is its parent: reported.
local function index_fingerprints(entries, tags)
    local by_print = {}
    for _, tag in ipairs(tags) do
        local print_of = ask.fingerprint(entries[tag].token)
        -- already seen: two folders share a token; otherwise record it
        if by_print[print_of] then
            error("room-tree: rooms " .. by_print[print_of] .. " and " .. tag
                .. " hold the same token, so a child naming it has two parents")
        end
        by_print[print_of] = tag
    end
    return by_print
end
-- }}}

-- {{{ local function place_room
-- Works out one room's declared parent, whether it is unheld, and its
-- parent in the tree.  A filed-under tag that is not held here, or names
-- the room itself, is damage (the bell listener unfiles rooms whose shelf
-- is removed, and file_under refuses both), so it is reported.
local function place_room(snap, tag)
    local entry = snap.entries[tag]
    local declared = ""
    local unheld = false
    -- no parent named: not a declared child
    -- a parent named and held here: that is the declared parent
    -- a parent named but not held: a top here, marked unheld
    if entry.parent ~= "" then
        declared = snap.by_print[entry.parent] or ""
        unheld = declared == ""
    end
    local filed = entry.filed_under
    -- filed somewhere: that room must be here and must not be this one
    if filed ~= "" then
        if snap.entries[filed] == nil then
            error("room-tree: room " .. tag .. " is filed under " .. filed .. ", which is not held here")
        end
        if filed == tag then
            error("room-tree: room " .. tag .. " is filed under itself")
        end
    end
    snap.declared[tag] = declared
    snap.unheld[tag] = unheld
    -- held declared parent: it wins; else a filing; else a top
    if declared ~= "" then
        snap.parent[tag], snap.placed[tag] = declared, "declared"
    elseif filed ~= "" then
        snap.parent[tag], snap.placed[tag] = filed, "filed"
    else
        snap.parent[tag], snap.placed[tag] = "", "top"
    end
end
-- }}}

-- {{{ local function find_rings
-- Every ring of parents in the tree, each as a list of tags in walking
-- order.  A ring has no top, so nothing in it could ever be drawn.
local function find_rings(snap, tags)
    local state = {}   -- tag -> "walking" | "done"
    local rings = {}
    for _, start in ipairs(tags) do
        local path = {}
        local current = start
        -- walk up until a top, a room already finished, or a room on this
        -- very walk (which closes a ring)
        while current ~= "" and state[current] == nil do
            state[current] = "walking"
            path[#path + 1] = current
            current = snap.parent[current]
        end
        -- stopped on this walk's own path: the tail from there is a ring
        if current ~= "" and state[current] == "walking" then
            local ring = {}
            local inside = false
            for _, step in ipairs(path) do
                -- the ring starts where the walk first met `current`
                if step == current then
                    inside = true
                end
                if inside then
                    ring[#ring + 1] = step
                end
            end
            rings[#rings + 1] = ring
        end
        for _, step in ipairs(path) do
            state[step] = "done"
        end
    end
    return rings
end
-- }}}

-- {{{ local function snapshot_unchecked
-- Reads every room and places it, without refusing rings; the bell
-- listener uses it to find and mend rings made by filing.
local function snapshot_unchecked(home)
    local tags = ask.list_rooms(home)
    local snap = {
        home = home, tags = tags, entries = {}, declared = {}, unheld = {},
        parent = {}, placed = {}, children = {}, tops = {},
    }
    for _, tag in ipairs(tags) do
        snap.entries[tag] = ask.read_entry(home, tag)
    end
    snap.by_print = index_fingerprints(snap.entries, tags)
    for _, tag in ipairs(tags) do
        place_room(snap, tag)
    end
    for _, tag in ipairs(tags) do
        local up = snap.parent[tag]
        -- a top: listed with the tops; else a child of its parent
        if up == "" then
            snap.tops[#snap.tops + 1] = tag
        else
            snap.children[up] = snap.children[up] or {}
            table.insert(snap.children[up], tag)
        end
    end
    local order = by_label_then_tag(snap.entries)
    table.sort(snap.tops, order)
    for _, list in pairs(snap.children) do
        table.sort(list, order)
    end
    return snap
end
-- }}}

-- {{{ local function ring_text
local function ring_text(snap, ring)
    local steps = {}
    for _, tag in ipairs(ring) do
        steps[#steps + 1] = snap.entries[tag].label .. " (" .. tag .. ", " .. snap.placed[tag] .. ")"
    end
    return table.concat(steps, " -> ")
end
-- }}}

-- {{{ function M.snapshot
-- The whole tree of this home, worked out once (shape described above).
-- A ring of parents is an error naming every room in it.
function M.snapshot(home)
    local snap = snapshot_unchecked(home)
    local rings = find_rings(snap, snap.tags)
    -- any ring: the tree cannot be drawn; say exactly where
    if #rings > 0 then
        error("room-tree: these rooms sit inside each other in a ring: " .. ring_text(snap, rings[1]))
    end
    return snap
end
-- }}}

-- ---------------------------------------------------------------------
-- asking about the tree
-- ---------------------------------------------------------------------

-- {{{ local function must_hold
local function must_hold(snap, tag)
    -- a tag not held here: the caller has the wrong room
    if snap.entries[tag] == nil then
        error("room-tree: no room " .. tostring(tag) .. " is held here")
    end
end
-- }}}

-- {{{ local function copy
local function copy(list)
    local out = {}
    for i, v in ipairs(list or {}) do
        out[i] = v
    end
    return out
end
-- }}}

-- {{{ function M.declared_parent_of
-- The held room whose token fingerprint the entry's `parent` names, or "".
function M.declared_parent_of(home, tag)
    local snap = M.snapshot(home)
    must_hold(snap, tag)
    return snap.declared[tag]
end
-- }}}

-- {{{ function M.tree_parent_of
-- The room this one shows under: the declared parent if held here, else
-- where you filed it, else "" (a top room).
function M.tree_parent_of(home, tag)
    local snap = M.snapshot(home)
    must_hold(snap, tag)
    return snap.parent[tag]
end
-- }}}

-- {{{ function M.placement
-- How the room sits: { how = "declared" | "filed" | "top",
-- parent_unheld = bool (its entry names a parent not held here) }.
function M.placement(home, tag)
    local snap = M.snapshot(home)
    must_hold(snap, tag)
    return { how = snap.placed[tag], parent_unheld = snap.unheld[tag] }
end
-- }}}

-- {{{ function M.children_of
-- The rooms showing directly under `tag`, sorted by label then tag.
function M.children_of(home, tag)
    local snap = M.snapshot(home)
    must_hold(snap, tag)
    return copy(snap.children[tag])
end
-- }}}

-- {{{ function M.tops
-- The top rooms, sorted by label then tag.
function M.tops(home)
    return copy(M.snapshot(home).tops)
end
-- }}}

-- {{{ local function ancestors_in
local function ancestors_in(snap, tag)
    local chain = {}
    local current = tag
    while current ~= "" do
        table.insert(chain, 1, current)
        current = snap.parent[current]
    end
    return chain
end
-- }}}

-- {{{ function M.ancestors
-- Rooms from the top of the tree down to `tag`, ending with `tag` itself.
function M.ancestors(home, tag)
    local snap = M.snapshot(home)
    must_hold(snap, tag)
    return ancestors_in(snap, tag)
end
-- }}}

-- {{{ local function labels_in
local function labels_in(snap, tag)
    local steps = {}
    for _, step in ipairs(ancestors_in(snap, tag)) do
        steps[#steps + 1] = where_file.path_step(snap.entries[step].label)
    end
    return table.concat(steps, "/")
end
-- }}}

-- {{{ function M.path_of_labels
-- "home/ritz/programming": your own labels of the room's ancestors, top
-- first.  Another home holding the same rooms has its own labels.
function M.path_of_labels(home, tag)
    local snap = M.snapshot(home)
    must_hold(snap, tag)
    return labels_in(snap, tag)
end
-- }}}

-- {{{ local function node_for
local function node_for(snap, tag)
    local entry = snap.entries[tag]
    local node = {
        tag = tag, label = entry.label, kind = entry.kind,
        placed = snap.placed[tag], parent_unheld = snap.unheld[tag], children = {},
    }
    for i, child in ipairs(snap.children[tag] or {}) do
        node.children[i] = node_for(snap, child)
    end
    return node
end
-- }}}

-- {{{ function M.forest
-- Every room in this home as trees: a list of top nodes, each
-- { tag, label, kind, placed, parent_unheld, children = list of nodes },
-- tops and children sorted by label then tag.  Direct messages are rooms
-- too and appear here; a client that lists them apart filters on `kind`.
function M.forest(home)
    local snap = M.snapshot(home)
    local forest = {}
    for i, tag in ipairs(snap.tops) do
        forest[i] = node_for(snap, tag)
    end
    return forest
end
-- }}}

-- ---------------------------------------------------------------------
-- the parent-membership rule
-- ---------------------------------------------------------------------

-- A member is an (address, port) pair, always together (issue 101).  Two
-- pairs are the same member when the address is equal as written and the
-- port is the same whole number: a hostname and the IP it points to are
-- different members here (see the options file, tree-member-match), and
-- the same address with another port is another home server.  `heard`
-- plays no part: a member never heard from is still a member.

-- {{{ local function check_pair
-- A caller passing a port as text ("7777") would never match the whole
-- number read from the entry, and every address would be refused for no
-- visible reason; so the shape is checked where the pair comes in.
local function check_pair(address, port)
    -- not a non-empty string: a caller's mistake
    if type(address) ~= "string" or address == "" then
        error("room-tree: an address must be non-empty text, got " .. tostring(address), 3)
    end
    -- not a whole number: a caller's mistake (ports are integers, issue 101)
    if type(port) ~= "number" or port ~= math.floor(port) then
        error("room-tree: a port must be a whole number, got " .. type(port) .. " " .. tostring(port), 3)
    end
end
-- }}}

-- {{{ local function holds_pair
local function holds_pair(entry, address, port)
    for _, pair in ipairs(entry.members) do
        -- both parts equal: this member; otherwise keep looking
        if pair.address == address and pair.port == port then
            return true
        end
    end
    return false
end
-- }}}

-- A child room whose declared parent is not held here: nobody on this
-- server can see the parent's members, so the rule cannot be checked.
-- The owner has not said what then; tree.unheld-parent-join decides, read
-- only in that case:
--   refuse: nobody new is accepted until the parent room is held here
--           (the tiers hold, at the price of a room nobody can join);
--   accept: anyone holding the token is accepted, as in a top room (the
--           room stays usable; the tier above is not enforced here).

-- {{{ local function unheld_refuse
local function unheld_refuse(entry)
    return false, "the parent of " .. entry.label .. " is not held here, so its members cannot be checked"
end
-- }}}

-- {{{ local function unheld_accept
local function unheld_accept(entry)
    return true, ""
end
-- }}}

local unheld_parent_join = {
    ["refuse"] = unheld_refuse,
    ["accept"] = unheld_accept,
}

-- {{{ function M.may_join
-- May the member (address, port) be added to room `tag`?  Gives a bool and
-- a reason (text; "" when allowed).  The rule looks only at the declared
-- parent, never at filing, and only one level up: the parent's own
-- members were checked against its parent when they joined.
function M.may_join(home, tag, address, port)
    check_pair(address, port)
    local snap = M.snapshot(home)
    must_hold(snap, tag)
    local entry = snap.entries[tag]
    -- not a declared child: any address holding the token may join
    if entry.parent == "" then
        return true, ""
    end
    -- a declared parent not held here: the owner's setting decides
    if snap.unheld[tag] then
        local mode = ask.config_value(home, "tree.unheld-parent-join")
        local decide = unheld_parent_join[mode]
        -- a value that is neither: a typo in config
        if decide == nil then
            error("room-tree: tree.unheld-parent-join must be refuse or accept, got " .. mode)
        end
        return decide(entry)
    end
    local parent = snap.entries[snap.declared[tag]]
    -- a member of the parent: welcome; otherwise refused, saying why
    if holds_pair(parent, address, port) then
        return true, ""
    end
    return false, address .. " " .. tostring(port) .. " is not a member of the parent room " .. parent.label
end
-- }}}

-- {{{ local function declared_children_in
local function declared_children_in(snap, tag)
    local out = {}
    for _, other in ipairs(snap.tags) do
        -- declared under this room: a child for the rule; otherwise not
        if snap.declared[other] == tag then
            out[#out + 1] = other
        end
    end
    table.sort(out, by_label_then_tag(snap.entries))
    return out
end
-- }}}

-- {{{ local function collect_holding
local function collect_holding(snap, tag, address, port, found)
    for _, child in ipairs(declared_children_in(snap, tag)) do
        -- the child holds the member: listed; its own children are
        -- searched either way (a grandchild may hold them when the child
        -- no longer does, after someone withdrew them by hand)
        if holds_pair(snap.entries[child], address, port) then
            found[#found + 1] = child
        end
        collect_holding(snap, child, address, port, found)
    end
end
-- }}}

-- {{{ function M.child_rooms_holding
-- Every declared child room below `tag` (all levels, top-down, siblings by
-- label then tag) whose members include (address, port).  For the client:
-- when a member leaves a parent room, it also removes them from these
-- (owner: "This is UI work"); the server itself only refuses them as new
-- members.  Filed rooms are not included: filing carries no rule.
function M.child_rooms_holding(home, tag, address, port)
    check_pair(address, port)
    local snap = M.snapshot(home)
    must_hold(snap, tag)
    local found = {}
    collect_holding(snap, tag, address, port, found)
    return found
end
-- }}}

-- ---------------------------------------------------------------------
-- filing a room under another on your own screen
-- ---------------------------------------------------------------------

-- {{{ function M.file_under
-- Places room `tag` under `under` (a local tag, or "" to unfile it).
-- Refuses a room not held here, filing under itself, and filing under a
-- room that already shows inside it (a ring).  A room with a held
-- declared parent keeps showing there; its filing is kept and takes over
-- if that parent is ever gone.  The write goes through room-folders,
-- which rings "filed", which rewrites `where`.
function M.file_under(home, tag, under)
    local snap = M.snapshot(home)
    must_hold(snap, tag)
    -- unfiling: always allowed, nothing can loop
    if under == "" then
        ask.write_filed_under(home, tag, "")
        return
    end
    -- the shelf must be a room held here, and not the room itself
    if snap.entries[under] == nil then
        error("room-tree: cannot file " .. tag .. " under " .. under .. ": that room is not held here")
    end
    if under == tag then
        error("room-tree: cannot file room " .. tag .. " under itself")
    end
    -- `under` already shows inside `tag`: filing would close a ring
    for _, step in ipairs(ancestors_in(snap, under)) do
        if step == tag then
            error("room-tree: cannot file " .. snap.entries[tag].label .. " under "
                .. snap.entries[under].label .. ", which sits inside it")
        end
    end
    ask.write_filed_under(home, tag, under)
end
-- }}}

-- ---------------------------------------------------------------------
-- keeping `where` current
-- ---------------------------------------------------------------------

-- {{{ function M.write_all_where
-- Rewrites `where` for every room held here.  Also for a home made before
-- the room tree was loaded, or a home folder that was moved (the folder
-- line records the old place).  Writing `where` rings nothing: it is
-- derived, and nobody else needs to hear about it.
function M.write_all_where(home)
    local snap = M.snapshot(home)
    for _, tag in ipairs(snap.tags) do
        where_file.write(ask.room_dir(home, tag), labels_in(snap, tag))
    end
end
-- }}}

-- {{{ function M.read_where
-- Gives { folder = string, labels = string } from the room's `where`.
function M.read_where(home, tag)
    return where_file.read(ask.room_dir(home, tag))
end
-- }}}

-- Rings made by filing.  A ring can only come about without file_under
-- refusing it when the tree above changes after the filing: a declared
-- parent arrives (you join it) or a token changes, and a room you filed
-- now sits above the room it was filed under.  The owner has not said
-- what then; tree.filing-loop decides, read only when a ring is found:
--   refuse: the change that closed the ring fails loudly (the room is on
--           disk, the error reaches whoever wrote it);
--   unfile: every room in the ring that was filed (not declared) is
--           unfiled, so declared parents win, as they do everywhere else.
-- A ring made only of declared parents is always an error: two rooms
-- naming each other's tokens is not something filing can mend.

-- {{{ local function filed_in_ring
local function filed_in_ring(snap, ring)
    local filed = {}
    for _, tag in ipairs(ring) do
        -- placed by filing: can be unfiled; declared: stays
        if snap.placed[tag] == "filed" then
            filed[#filed + 1] = tag
        end
    end
    return filed
end
-- }}}

-- {{{ local function ring_refuse
local function ring_refuse(home, snap, ring)
    error("room-tree: filing made a ring (tree.filing-loop = refuse): " .. ring_text(snap, ring))
end
-- }}}

-- {{{ local function ring_unfile
local function ring_unfile(home, snap, ring)
    for _, tag in ipairs(filed_in_ring(snap, ring)) do
        ask.write_filed_under(home, tag, "")
    end
end
-- }}}

local filing_loop = {
    ["refuse"] = ring_refuse,
    ["unfile"] = ring_unfile,
}

-- {{{ local function mend_rings
-- Gives true when something was unfiled (the nested ring of "filed" has
-- then already rewritten `where`).
local function mend_rings(home)
    local snap = snapshot_unchecked(home)
    local rings = find_rings(snap, snap.tags)
    -- no ring: nothing to mend
    if #rings == 0 then
        return false
    end
    for _, ring in ipairs(rings) do
        -- only declared parents: always an error; else the setting decides
        if #filed_in_ring(snap, ring) == 0 then
            error("room-tree: these rooms name each other's tokens as parents: " .. ring_text(snap, ring))
        end
    end
    local mode = ask.config_value(home, "tree.filing-loop")
    local mend = filing_loop[mode]
    -- a value that is neither: a typo in config
    if mend == nil then
        error("room-tree: tree.filing-loop must be refuse or unfile, got " .. mode)
    end
    -- one ring at a time: unfiling rings "filed", whose own refresh finds
    -- and mends any ring left, from a fresh snapshot
    mend(home, snap, rings[1])
    return true
end
-- }}}

-- A room removed from this home: rooms you filed under it would name a
-- shelf that is gone.  They are unfiled (they rise to where their own
-- declared parent or the top puts them).  Declared children need nothing:
-- their parent's fingerprint simply matches no room held here any more.

-- {{{ local function unfile_orphans
local function unfile_orphans(home, removed_tag)
    for _, other in ipairs(ask.list_rooms(home)) do
        -- filed under the room that went: unfile it; otherwise leave it
        if ask.read_entry(home, other).filed_under == removed_tag then
            ask.write_filed_under(home, other, "")
        end
    end
end
-- }}}

-- {{{ local function refresh
-- Mends rings, then rewrites every `where`.  When mending unfiled a room,
-- the nested ring already rewrote them, so it is not done twice.
local function refresh(home, tag)
    -- something unfiled: already rewritten by the nested ring
    if mend_rings(home) then
        return
    end
    M.write_all_where(home)
end
-- }}}

-- {{{ local function on_removed
local function on_removed(home, tag)
    unfile_orphans(home, tag)
    refresh(home, tag)
end
-- }}}

-- {{{ local function ignore
local function ignore(home, tag)
end
-- }}}

-- What each kind of change means for the tree:
--   created, label, parent, filed: a room appeared, moved or was renamed —
--     mend rings, rewrite every `where`;
--   token: the room's fingerprint changed.  Room-folders has already
--     re-pointed the held children to the new fingerprint (each ringing
--     "parent") before this ring, so only the refresh is left;
--   removed-room: rooms filed under it are unfiled, then as above;
--   members, heard, withheld, log, ignore: nothing about placement or
--     labels ("ignore" rings with the tag "", the whole home).
-- Every `where` is rewritten rather than only the changed room's subtree:
-- a joined parent or a changed token can move rooms anywhere in the home,
-- and phase 1 homes hold tens of rooms, not thousands.
local bell_actions = {
    ["created"] = refresh,
    ["label"] = refresh,
    ["parent"] = refresh,
    ["filed"] = refresh,
    ["token"] = refresh,
    ["removed-room"] = on_removed,
    ["members"] = ignore,
    ["heard"] = ignore,
    ["withheld"] = ignore,
    ["log"] = ignore,
    ["ignore"] = ignore,
}

-- {{{ local function on_bell
local function on_bell(home, tag, what)
    local action = bell_actions[what]
    -- a kind of change this module was not told about: stop and say so
    if action == nil then
        error("room-tree: the change bell rang with an unknown kind '" .. tostring(what) .. "'")
    end
    action(home, tag)
end
-- }}}

ask.on_change(on_bell)

return M
