-- 054-test-child-room.lua — tiers of trust: a child room refuses an address
-- that is not a member of its parent, as this home sees the parent.

local A = { "203.0.113.1", 7001 }
local B = { "203.0.113.2", 7002 }
local C = { "203.0.113.3", 7003 }

-- {{{ local function run
local function run(h)
    local R = h.recipients

    h.check("child: an address in the parent is accepted", function()
        local home = h.new_home("child-in", {})
        local parent = h.room(home, "home", { A, B })
        local child = h.room(home, "programming", { A }, "group", parent)
        h.equal(R.add_member(home, child, B[1], B[2]), "added", "B is in the parent")
    end)

    h.check("child: an address not in the parent is refused, by adding and by speaking", function()
        local home = h.new_home("child-out", {})
        local parent = h.room(home, "home", { A, B })
        local child = h.room(home, "programming", { A }, "group", parent)
        local word = R.add_member(home, child, C[1], C[2])
        h.equal(word, "not-in-parent", "via sync")
        h.equal(R.heard_from(home, child, C[1], C[2], h.tick()), "not-in-parent", "via speaking")
        h.equal(#R.members(home, child), 1, "not added")
    end)

    h.check("child: once the parent gains the address, the child accepts it", function()
        local home = h.new_home("child-later", {})
        local parent = h.room(home, "home", { A })
        local child = h.room(home, "programming", {}, "group", parent)
        h.equal(R.add_member(home, child, C[1], C[2]), "not-in-parent", "before")
        h.equal(R.add_member(home, parent, C[1], C[2]), "added", "parent gains C")
        h.equal(R.add_member(home, child, C[1], C[2]), "added", "after")
    end)

    h.check("child: three levels — the grandchild checks its own parent", function()
        local home = h.new_home("child-three", {})
        local top = h.room(home, "home", { A, B, C })
        local middle = h.room(home, "ritz", { A, B }, "group", top)
        local bottom = h.room(home, "programming", {}, "group", middle)
        h.equal(R.add_member(home, bottom, C[1], C[2]), "not-in-parent", "C is in top, not middle")
        h.equal(R.add_member(home, bottom, B[1], B[2]), "added", "B is in middle")
    end)

    -- a parent not held here: 102's tree.unheld-parent-join decides; 103
    -- passes 102's answer through unchanged, in both variants
    for _, case in ipairs({ { "accept", "added" }, { "refuse", "not-in-parent" } }) do
        h.check("child: parent not held here, tree.unheld-parent-join = " .. case[1], function()
            local home = h.new_home("child-unheld-" .. case[1], { ["tree.unheld-parent-join"] = case[1] })
            local tag = h.rooms.make_room(home, {
                label = "orphan", token = "orphan-token-" .. h.rooms.new_local_tag():sub(1, 6), kind = "group",
                parent = string.rep("ab", 32), filed_under = "", members = {},
            })
            h.equal(R.add_member(home, tag, C[1], C[2]), case[2], "answer")
            h.equal(R.heard_from(home, tag, C[1], C[2], h.tick()), case[2] == "added" and "already" or case[2], "speaking")
        end)
    end

    h.check("child: ignoring is checked before the parent rule", function()
        local home = h.new_home("child-ignore", {})
        local parent = h.room(home, "home", { A })
        local child = h.room(home, "programming", {}, "group", parent)
        h.ignore.ignore(home, A[1], A[2], "mark", "*", h.tick())
        h.equal(R.add_member(home, child, A[1], A[2]), "ignored", "ignored first")
    end)
end
-- }}}

return run
