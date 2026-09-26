-- 053-test-leave-and-heard.lua — an address leaves only by its own
-- confirmed say-so; speaking again re-adds; last-heard times move only
-- forward; silent members are listed, never removed.

local A = { "203.0.113.1", 7001 }
local B = { "203.0.113.2", 7002 }
local C = { "203.0.113.3", 7003 }

-- {{{ local function run
local function run(h)
    local R = h.recipients

    h.check("leave: a forged leave notice does nothing — only confirm_leave removes", function()
        -- phase 2 receives "B left" but B answers the call-back "no": phase 2
        -- never calls confirm_leave, and nothing else in this module removes
        local home = h.new_home("leave-forged", {})
        local tag = h.room(home, "room", { A, B, C })
        local exported = {}
        for name in pairs(R) do exported[#exported + 1] = name end
        table.sort(exported)
        for _, name in ipairs(exported) do
            -- the only function whose name suggests removal is the confirmed one
            if name:find("remove") or name:find("drop") or name:find("prune") or name:find("kick") then
                error("an unexpected removing function: " .. name)
            end
        end
        h.equal(#R.members(home, tag), 3, "still three")
        h.equal(#R.send_list(home, tag), 3, "B still hears you")
    end)

    h.check("leave: a confirmed leave removes the member and rings 'members'", function()
        local home = h.new_home("leave-confirmed", {})
        local tag = h.room(home, "room", { A, B, C })
        h.rings()
        h.equal(R.confirm_leave(home, tag, B[1], B[2]), "removed", "confirmed")
        h.equal(table.concat(h.rings(), ","), "members@" .. tag, "rings")
        h.equal(h.keys(R.members(home, tag)), "203.0.113.1 7001,203.0.113.3 7003", "B gone")
    end)

    h.check("leave: a confirmed leave for a non-member is an error", function()
        local home = h.new_home("leave-nonmember", {})
        local tag = h.room(home, "room", { A })
        h.expect_error("not a member", function() R.confirm_leave(home, tag, B[1], B[2]) end)
    end)

    h.check("leave: speaking again after leaving re-adds the address", function()
        local home = h.new_home("leave-speak", {})
        local tag = h.room(home, "room", { A, B })
        R.confirm_leave(home, tag, B[1], B[2])
        local when = h.tick()
        h.equal(R.heard_from(home, tag, B[1], B[2], when), "added", "re-added")
        local m = R.members(home, tag)
        h.equal(h.keys(m), "203.0.113.1 7001,203.0.113.2 7002", "back")
        h.equal(m[2].heard, when, "heard recorded on re-adding")
    end)

    h.check("heard: a member speaking records when; rings 'heard', not 'members'", function()
        local home = h.new_home("heard-record", {})
        local tag = h.room(home, "room", { A, B })
        h.rings()
        local when = h.tick()
        h.equal(R.heard_from(home, tag, A[1], A[2], when), "already", "a member")
        h.equal(table.concat(h.rings(), ","), "heard@" .. tag, "rings heard only")
        h.equal(R.members(home, tag)[1].heard, when, "recorded")
        h.equal(R.members(home, tag)[2].heard, 0, "B never heard")
    end)

    h.check("heard: a late old message does not move last-heard backwards", function()
        local home = h.new_home("heard-late", {})
        local tag = h.room(home, "room", { A })
        local later = h.tick() + 100
        R.heard_from(home, tag, A[1], A[2], later)
        h.rings()
        R.heard_from(home, tag, A[1], A[2], later - 50)
        h.equal(R.members(home, tag)[1].heard, later, "unchanged")
        h.equal(#h.rings(), 0, "no ring when nothing changed")
    end)

    h.check("heard: a stranger speaking is added (holding the token is the invitation)", function()
        local home = h.new_home("heard-stranger", {})
        local tag = h.room(home, "room", { A })
        h.equal(R.heard_from(home, tag, C[1], C[2], h.tick()), "added", "added")
        h.equal(#R.send_list(home, tag), 2, "and hears you")
    end)

    h.check("heard: silent members are listed for pruning, and not removed", function()
        local home = h.new_home("heard-silent", {})
        local tag = h.room(home, "room", { A, B, C })
        local t1 = h.tick()
        R.heard_from(home, tag, A[1], A[2], t1)
        local t2 = h.tick() + 1000
        R.heard_from(home, tag, B[1], B[2], t2)
        -- since t2: A (heard at t1) and C (never) are silent
        h.equal(h.keys(R.silent_since(home, tag, t2)), "203.0.113.1 7001,203.0.113.3 7003", "silent")
        h.equal(#R.silent_since(home, tag, t1), 1, "since t1 only C")
        h.equal(#R.members(home, tag), 3, "nobody removed")
    end)
end
-- }}}

return run
