-- 052-test-withheld-and-send.lua — withholding is all removal is: the send
-- list shrinks, the member list does not; un-withholding brings them back;
-- each home keeps its own choices.

local A = { "203.0.113.1", 7001 }
local B = { "203.0.113.2", 7002 }
local C = { "203.0.113.3", 7003 }
local D = { "203.0.113.4", 7004 }
local E = { "203.0.113.5", 7005 }
local F = { "203.0.113.6", 7006 }

-- {{{ local function run
local function run(h)
    local R = h.recipients

    h.check("withheld: a room of six, one withheld — send list five, members still six", function()
        local home = h.new_home("withheld-six", {})
        local tag = h.room(home, "six", { A, B, C, D, E, F })
        h.rings()
        h.equal(R.withhold(home, tag, C[1], C[2]), "withheld", "withhold")
        h.equal(table.concat(h.rings(), ","), "withheld@" .. tag, "rings withheld only")
        h.equal(#R.members(home, tag), 6, "members unchanged")
        h.equal(h.keys(R.send_list(home, tag)),
            "203.0.113.1 7001,203.0.113.2 7002,203.0.113.4 7004,203.0.113.5 7005,203.0.113.6 7006",
            "send list without C")
        h.equal(h.keys(R.withheld(home, tag)), "203.0.113.3 7003", "withheld list")
    end)

    h.check("withheld: the file on disk is one 'address port' per line", function()
        local home = h.new_home("withheld-file", {})
        local tag = h.room(home, "file", { A, B })
        R.withhold(home, tag, B[1], B[2])
        local file = assert(io.open(h.rooms.withheld_path(home, tag), "r"))
        local text = file:read("*a")
        file:close()
        h.equal(text, "203.0.113.2 7002\n", "withheld file")
    end)

    h.check("withheld: withholding twice is 'already', no second ring", function()
        local home = h.new_home("withheld-twice", {})
        local tag = h.room(home, "twice", { A, B })
        R.withhold(home, tag, A[1], A[2])
        h.rings()
        h.equal(R.withhold(home, tag, A[1], A[2]), "already", "second")
        h.equal(#h.rings(), 0, "no ring")
    end)

    h.check("withheld: un-withholding brings them back onto the send list", function()
        local home = h.new_home("withheld-back", {})
        local tag = h.room(home, "back", { A, B, C })
        R.withhold(home, tag, B[1], B[2])
        h.equal(R.unwithhold(home, tag, B[1], B[2]), "unwithheld", "unwithhold")
        h.equal(h.keys(R.send_list(home, tag)), h.keys(R.members(home, tag)), "everyone again")
        h.equal(#R.withheld(home, tag), 0, "withheld empty")
    end)

    h.check("withheld: withholding a non-member or un-withholding a non-withheld is an error", function()
        local home = h.new_home("withheld-errors", {})
        local tag = h.room(home, "errors", { A })
        h.expect_error("is not a member", function() R.withhold(home, tag, B[1], B[2]) end)
        h.expect_error("is not withheld", function() R.unwithhold(home, tag, A[1], A[2]) end)
    end)

    h.check("withheld: you cannot choose who hears anyone else — two homes, two lists", function()
        -- the same room on two homes: yours and a friend's; each withholds
        -- someone different, and neither choice touches the other home
        local mine = h.new_home("withheld-mine", {})
        local theirs = h.new_home("withheld-theirs", {})
        local my_tag = h.room(mine, "shared", { B, C, D })
        local their_tag = h.room(theirs, "shared", { A, C, D })
        R.withhold(mine, my_tag, C[1], C[2])
        h.equal(#R.send_list(theirs, their_tag), 3, "their send list untouched")
        R.withhold(theirs, their_tag, D[1], D[2])
        h.equal(h.keys(R.send_list(mine, my_tag)), "203.0.113.2 7002,203.0.113.4 7004", "mine")
        h.equal(h.keys(R.send_list(theirs, their_tag)), "203.0.113.1 7001,203.0.113.3 7003", "theirs")
    end)

    h.check("withheld: a withheld member who leaves and comes back is still withheld", function()
        local home = h.new_home("withheld-return", {})
        local tag = h.room(home, "return", { A, B })
        R.withhold(home, tag, B[1], B[2])
        R.confirm_leave(home, tag, B[1], B[2])
        h.equal(h.keys(R.withheld(home, tag)), "203.0.113.2 7002", "line kept after leaving")
        h.equal(R.heard_from(home, tag, B[1], B[2], h.tick()), "added", "speaks again")
        h.equal(h.keys(R.send_list(home, tag)), "203.0.113.1 7001", "still withheld")
    end)
end
-- }}}

return run
