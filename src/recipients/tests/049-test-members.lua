-- 049-test-members.lua — members are the entry's address pairs: reading,
-- adding, a move adding a second address, no minimum, and the send list
-- holding everyone by default.

local A = { "203.0.113.1", 7001 }
local B = { "203.0.113.2", 7002 }
local C = { "sorelu.example.org", 7003 }

-- {{{ local function run
local function run(h)
    local R = h.recipients

    h.check("members: read from the entry, in its order, never heard (0)", function()
        local home = h.new_home("members-read", {})
        local tag = h.room(home, "coffee", { A, B, C })
        local m = R.members(home, tag)
        h.equal(h.keys(m), "203.0.113.1 7001,203.0.113.2 7002,sorelu.example.org 7003", "members")
        h.equal(m[1].heard, 0, "never heard")
        h.equal(R.is_member(home, tag, B[1], B[2]), true, "B is a member")
        h.equal(R.is_member(home, tag, B[1], 9999), false, "same address, other port is not")
    end)

    h.check("members: every member hears you by default (send list = members)", function()
        local home = h.new_home("members-default", {})
        local tag = h.room(home, "coffee", { A, B, C })
        h.equal(h.keys(R.send_list(home, tag)), h.keys(R.members(home, tag)), "send list")
    end)

    h.check("members: adding appends, rings 'members', and a repeat is 'already' with no ring", function()
        local home = h.new_home("members-add", {})
        local tag = h.room(home, "coffee", { A })
        h.rings()
        h.equal(R.add_member(home, tag, B[1], B[2]), "added", "first add")
        h.equal(table.concat(h.rings(), ","), "members@" .. tag, "rings")
        h.equal(R.add_member(home, tag, B[1], B[2]), "already", "second add")
        h.equal(#h.rings(), 0, "no ring for a non-change")
        h.equal(h.keys(R.members(home, tag)), "203.0.113.1 7001,203.0.113.2 7002", "members")
        h.equal(h.keys(R.send_list(home, tag)), "203.0.113.1 7001,203.0.113.2 7002", "new member hears you")
    end)

    h.check("members: a move adds the new address beside the old (both kept)", function()
        local home = h.new_home("members-move", {})
        local tag = h.room(home, "coffee", { A, B })
        h.equal(R.add_member(home, tag, "198.51.100.7", A[2]), "added", "new address")
        h.equal(h.keys(R.members(home, tag)),
            "203.0.113.1 7001,203.0.113.2 7002,198.51.100.7 7001", "old and new")
        h.equal(#R.send_list(home, tag), 3, "both addresses hear you")
    end)

    h.check("members: same address, second port is a second member", function()
        local home = h.new_home("members-ports", {})
        local tag = h.room(home, "coffee", { A })
        h.equal(R.add_member(home, tag, A[1], 7999), "added", "other port")
        h.equal(#R.members(home, tag), 2, "two members")
    end)

    h.check("members: no minimum — a room with no members but you", function()
        local home = h.new_home("members-empty", {})
        local tag = h.room(home, "about-to-invite", {})
        h.equal(#R.members(home, tag), 0, "no members")
        h.equal(#R.send_list(home, tag), 0, "nobody to send to")
        h.equal(R.add_member(home, tag, A[1], A[2]), "added", "first member")
    end)

    h.check("members: a malformed pair is refused before anything is read", function()
        local home = h.new_home("members-bad", {})
        local tag = h.room(home, "coffee", { A })
        h.expect_error("port must be", function() R.add_member(home, tag, A[1], "7001") end)
        h.expect_error("address must be", function() R.add_member(home, tag, "", 7001) end)
    end)

    h.check("members: a room that does not exist is an error", function()
        local home = h.new_home("members-none", {})
        h.expect_error("", function() R.members(home, h.rooms.new_local_tag()) end)
    end)
end
-- }}}

return run
