-- 046-stand-in-room-tree.lua — a small copy of the one thing the recipients
-- module asks the room tree (issue 102): "may this address join this room?"
--
-- The rule it stands in for: an address may join a child room only if it is
-- a member of the parent room as this home sees it.  A room with no parent
-- accepts anyone.  A room whose parent is not held here follows 102's
-- config key tree.unheld-parent-join: refuse (nobody new until the parent
-- is held) or accept (as a top room).  The runner loads the real module
-- instead when told "real".

local rooms = require("002-room-folders")

local M = {}

-- {{{ function M.may_join
-- Gives true, or false and a reason in words.
function M.may_join(home, tag, address, port)
    local entry = rooms.read_entry(home, tag)
    -- no declared parent: a top room, anyone may join
    if entry.parent == "" then
        return true, ""
    end
    local parent_tag = rooms.find_by_fingerprint(home, entry.parent)
    -- parent not held here: 102's setting decides
    if parent_tag == "" then
        local mode = rooms.config_value(home, "tree.unheld-parent-join")
        -- accept: like a top room; refuse: nobody can be checked, so nobody new
        if mode == "accept" then
            return true, ""
        elseif mode == "refuse" then
            return false, "the parent is not held here"
        end
        error("stand-in tree: tree.unheld-parent-join = " .. mode)
    end
    for _, m in ipairs(rooms.read_entry(home, parent_tag).members) do
        -- a member of the parent: welcome
        if m.address == address and m.port == port then
            return true, ""
        end
    end
    return false, "not a member of the parent room"
end
-- }}}

return M
