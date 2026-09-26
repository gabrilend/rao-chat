-- 048-test-ignore.lua — the ignore list (issue 103a): both levels, the
-- member filter (a synced-back ignored address refused), un-ignoring, and
-- every variant of its three undecided choices.

local A = { "203.0.113.1", 7001 }
local B = { "203.0.113.2", 7002 }
local T = 1790000000

-- {{{ local function run
local function run(h)
    local R, I = h.recipients, h.ignore

    h.check("ignore: the file starts empty; ignoring writes one line and rings 'ignore' on ''", function()
        local home = h.new_home("ignore-file", {})
        h.equal(#I.entries(home), 0, "empty")
        h.rings()
        h.equal(I.ignore(home, A[1], A[2], "hide", "*", T), "ignored", "ignore")
        h.equal(table.concat(h.rings(), ","), "ignore@", "rings on the empty tag")
        local file = assert(io.open(h.rooms.ignore_path(home), "r"))
        local text = file:read("*a")
        file:close()
        h.equal(text, "203.0.113.1 7001 hide " .. T .. " *\n", "file line")
    end)

    h.check("ignore: both levels answer how_ignored; others are 'none'", function()
        local home = h.new_home("ignore-levels", {})
        local tag = h.room(home, "room", { A, B })
        I.ignore(home, A[1], A[2], "hide", "*", T)
        I.ignore(home, B[1], B[2], "mark", "*", T)
        h.equal(I.how_ignored(home, tag, A[1], A[2]), "hide", "A")
        h.equal(I.how_ignored(home, tag, B[1], B[2]), "mark", "B")
        h.equal(I.how_ignored(home, tag, "198.51.100.1", 7001), "none", "stranger")
    end)

    h.check("ignore: changing level, 'already' for no change, unknown level refused", function()
        local home = h.new_home("ignore-change", {})
        h.equal(I.ignore(home, A[1], A[2], "mark", "*", T), "ignored", "first")
        h.equal(I.ignore(home, A[1], A[2], "mark", "*", T + 1), "already", "same")
        h.equal(I.ignore(home, A[1], A[2], "hide", "*", T + 2), "level-changed", "changed")
        h.equal(I.entries(home)[1].added, T + 2, "time restamped")
        h.equal(#I.entries(home), 1, "still one line")
        h.expect_error("level must be", function() I.ignore(home, B[1], B[2], "mute", "*", T) end)
    end)

    h.check("ignore: ignoring does not withhold, and does not change membership", function()
        local home = h.new_home("ignore-not-withhold", {})
        local tag = h.room(home, "room", { A, B })
        I.ignore(home, A[1], A[2], "hide", "*", T)
        h.equal(#R.members(home, tag), 2, "members")
        h.equal(#R.send_list(home, tag), 2, "A still hears you")
    end)

    h.check("ignore: a synced-back ignored address is refused as a member (either level)", function()
        local home = h.new_home("ignore-refuse", {})
        local tag = h.room(home, "room", { B })
        I.ignore(home, A[1], A[2], "mark", "*", T)
        h.equal(R.add_member(home, tag, A[1], A[2]), "ignored", "via a member's list")
        h.equal(R.heard_from(home, tag, A[1], A[2], T), "ignored", "by speaking")
        h.equal(#R.members(home, tag), 1, "not added")
    end)

    h.check("ignore: un-ignoring lets the address back in", function()
        local home = h.new_home("ignore-unignore", {})
        local tag = h.room(home, "room", { B })
        I.ignore(home, A[1], A[2], "hide", "*", T)
        h.equal(I.unignore(home, A[1], A[2], "*"), "unignored", "unignore")
        h.equal(R.add_member(home, tag, A[1], A[2]), "added", "added now")
        h.expect_error("is not ignored", function() I.unignore(home, A[1], A[2], "*") end)
    end)

    h.check("ignore: an existing member who is then ignored stays a member", function()
        local home = h.new_home("ignore-existing", {})
        local tag = h.room(home, "room", { A })
        I.ignore(home, A[1], A[2], "hide", "*", T)
        h.equal(R.add_member(home, tag, A[1], A[2]), "already", "already a member")
    end)

    h.check("ignore: the address change escapes the list (by design)", function()
        local home = h.new_home("ignore-moved", { ["ignore.match"] = "pair" })
        local tag = h.room(home, "room", {})
        I.ignore(home, A[1], A[2], "hide", "*", T)
        h.equal(R.add_member(home, tag, "198.51.100.9", A[2]), "added", "new address, same person")
    end)

    -- ignore.match
    h.check("ignore.match = pair: another port at the same address is not ignored", function()
        local home = h.new_home("ignore-match-pair", { ["ignore.match"] = "pair" })
        local tag = h.room(home, "room", {})
        I.ignore(home, A[1], A[2], "hide", "*", T)
        h.equal(I.how_ignored(home, tag, A[1], 9999), "none", "other port")
    end)

    h.check("ignore.match = host: every port at that address is ignored; strongest level wins", function()
        local home = h.new_home("ignore-match-host", { ["ignore.match"] = "host" })
        local tag = h.room(home, "room", {})
        I.ignore(home, A[1], A[2], "mark", "*", T)
        h.equal(I.how_ignored(home, tag, A[1], 9999), "mark", "other port")
        I.ignore(home, A[1], 8000, "hide", "*", T)
        h.equal(I.how_ignored(home, tag, A[1], 9999), "hide", "stronger of two lines")
        h.equal(R.add_member(home, tag, A[1], 12345), "ignored", "refused on any port")
    end)

    -- ignore.scope
    h.check("ignore.scope = home: a one-room entry is refused", function()
        local home = h.new_home("ignore-scope-home", { ["ignore.scope"] = "home" })
        local tag = h.room(home, "room", {})
        h.expect_error("needs ignore.scope = home-and-room", function()
            I.ignore(home, A[1], A[2], "hide", tag, T)
        end)
    end)

    h.check("ignore.scope = home-and-room: a one-room entry covers only that room", function()
        local home = h.new_home("ignore-scope-room", { ["ignore.scope"] = "home-and-room" })
        local here = h.room(home, "here", {})
        local there = h.room(home, "there", {})
        h.rings()
        I.ignore(home, A[1], A[2], "hide", here, T)
        h.equal(table.concat(h.rings(), ","), "ignore@" .. here, "rings on the room's tag")
        h.equal(I.how_ignored(home, here, A[1], A[2]), "hide", "here")
        h.equal(I.how_ignored(home, there, A[1], A[2]), "none", "there")
        h.equal(R.add_member(home, here, A[1], A[2]), "ignored", "refused here")
        h.equal(R.add_member(home, there, A[1], A[2]), "added", "added there")
        h.expect_error("no room", function() I.ignore(home, B[1], B[2], "hide", h.rooms.new_local_tag(), T) end)
    end)

    h.check("ignore.scope: a one-room line in a home set to 'home' is reported (hand-edited)", function()
        local home = h.new_home("ignore-scope-edited", { ["ignore.scope"] = "home-and-room" })
        local tag = h.room(home, "room", {})
        I.ignore(home, A[1], A[2], "hide", tag, T)
        h.rooms.set_config(home, "ignore.scope", "home")
        h.expect_error("one-room entry", function() I.how_ignored(home, tag, A[1], A[2]) end)
    end)

    -- ignore.hide-files
    h.check("ignore.hide-files = filed: a hidden message is still filed; marked always filed", function()
        local home = h.new_home("ignore-files-filed", { ["ignore.hide-files"] = "filed" })
        local tag = h.room(home, "room", {})
        I.ignore(home, A[1], A[2], "hide", "*", T)
        I.ignore(home, B[1], B[2], "mark", "*", T)
        h.equal(I.files_message(home, tag, A[1], A[2]), true, "hidden, filed")
        h.equal(I.files_message(home, tag, B[1], B[2]), true, "marked, filed")
        h.equal(I.files_message(home, tag, "198.51.100.1", 1), true, "stranger, filed")
    end)

    h.check("ignore.hide-files = not-filed: a hidden message is not filed; marked still is", function()
        local home = h.new_home("ignore-files-not", { ["ignore.hide-files"] = "not-filed" })
        local tag = h.room(home, "room", {})
        I.ignore(home, A[1], A[2], "hide", "*", T)
        I.ignore(home, B[1], B[2], "mark", "*", T)
        h.equal(I.files_message(home, tag, A[1], A[2]), false, "hidden, not filed")
        h.equal(I.files_message(home, tag, B[1], B[2]), true, "marked, filed")
    end)

    h.check("ignore: an unknown variant value in config is refused at first use", function()
        local home = h.new_home("ignore-typo", { ["ignore.match"] = "hosts" })
        local tag = h.room(home, "room", {})
        h.expect_error("not a built variant", function() I.how_ignored(home, tag, A[1], A[2]) end)
    end)

    h.check("ignore: an absent config key is an error, never a default", function()
        local home = h.new_home("ignore-absent", {})
        local tag = h.room(home, "room", {})
        -- rewrite config without ignore.match
        local cfg = h.rooms.read_config(home)
        cfg["ignore.match"] = nil
        local lines = {}
        for k, v in pairs(cfg) do lines[#lines + 1] = k .. " = " .. v .. "\n" end
        local file = assert(io.open(home.dir .. "/config", "w"))
        file:write(table.concat(lines))
        file:close()
        h.expect_error("ignore.match", function() I.how_ignored(home, tag, A[1], A[2]) end)
    end)
end
-- }}}

return run
