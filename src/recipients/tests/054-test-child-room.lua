-- 054-test-child-room.lua — the room tree is detected, not enforced: in a
-- declared child room, an address that is not a member of every room above
-- it (as this home sees them), or whose rooms above are not held here, is
-- added but flagged; a flagged member hears nothing until approved;
-- declining withholds; a member dropped from a parent shows up flagged in
-- its children.

local A = { "203.0.113.1", 7001 }
local B = { "203.0.113.2", 7002 }
local C = { "203.0.113.3", 7003 }

-- {{{ local function run
local function run(h)
    local R = h.recipients

    -- {{{ local function flag_text
    -- The flagged file's lines as "address port state,..." (file order).
    local function flag_text(home, tag)
        local out = {}
        for i, fl in ipairs(R.flags(home, tag)) do
            out[i] = fl.address .. " " .. fl.port .. " " .. fl.state
        end
        return table.concat(out, ",")
    end
    -- }}}

    -- {{{ local function orphan
    -- A child room whose declared parent (named by the fingerprint of
    -- `parent_token`) is not held here.
    local function orphan(home, label, members, parent_token)
        local list = {}
        for i, m in ipairs(members) do list[i] = { address = m[1], port = m[2], heard = 0 } end
        return h.make(home, {
            label = label, token = "orphan-token-" .. h.rooms.new_local_tag():sub(1, 6), kind = "group",
            parent = h.rooms.token_fingerprint(parent_token), filed_under = "", members = list,
        })
    end
    -- }}}

    h.check("child: an address in every room above is added plainly and hears you", function()
        local home = h.new_home("child-in", {})
        local parent = h.room(home, "home", { A, B })
        local child = h.room(home, "programming", { A }, "group", parent)
        h.equal(R.add_member(home, child, B[1], B[2]), "added", "B is in the parent")
        h.equal(flag_text(home, child), "", "no flags")
        h.equal(h.keys(R.send_list(home, child)), "203.0.113.1 7001,203.0.113.2 7002", "both hear you")
    end)

    h.check("child: an address not in the parent is added flagged ('no') and left off the send list", function()
        local home = h.new_home("child-out", {})
        local parent = h.room(home, "home", { A, B })
        local child = h.room(home, "programming", { A }, "group", parent)
        h.rings()
        local word, answer, reason = R.add_member(home, child, C[1], C[2])
        h.equal(word, "added-flagged", "via sync")
        h.equal(answer, "no", "the tree's answer")
        h.equal(type(reason) == "string" and reason ~= "", true, "a reason in words")
        h.equal(table.concat(h.rings(), ","), "withheld@" .. child .. ",members@" .. child,
            "flag written (rung as withheld) before the member")
        h.equal(R.is_member(home, child, C[1], C[2]), true, "a member")
        h.equal(h.keys(R.flagged(home, child)), "203.0.113.3 7003", "flagged")
        h.equal(h.keys(R.send_list(home, child)), "203.0.113.1 7001", "C hears nothing yet")
        local file = assert(io.open(h.rooms.flagged_path(home, child), "r"))
        local text = file:read("*a")
        file:close()
        h.equal(text, "203.0.113.3 7003 no\n", "the flagged file's line")
    end)

    h.check("child: speaking from outside the parent also adds flagged", function()
        local home = h.new_home("child-speak", {})
        local parent = h.room(home, "home", { A })
        local child = h.room(home, "programming", {}, "group", parent)
        local when = h.tick()
        h.equal(R.heard_from(home, child, C[1], C[2], when), "added-flagged", "via speaking")
        h.equal(R.members(home, child)[1].heard, when, "heard recorded for a flagged member")
        h.equal(#R.send_list(home, child), 0, "not sent to")
    end)

    h.check("child: approving puts a flagged member on the send list, and the line says approved", function()
        local home = h.new_home("child-approve", {})
        local parent = h.room(home, "home", { A })
        local child = h.room(home, "programming", { A }, "group", parent)
        R.add_member(home, child, C[1], C[2])
        h.equal(R.approve(home, child, C[1], C[2]), "approved", "approve")
        h.equal(#R.flagged(home, child), 0, "nothing awaiting review")
        h.equal(flag_text(home, child), "203.0.113.3 7003 approved", "approval remembered")
        h.equal(h.keys(R.send_list(home, child)), "203.0.113.1 7001,203.0.113.3 7003", "C hears you")
        h.expect_error("is not flagged", function() R.approve(home, child, C[1], C[2]) end)
    end)

    h.check("child: declining withholds the member and clears the flag; it stays a member", function()
        local home = h.new_home("child-decline", {})
        local parent = h.room(home, "home", { A })
        local child = h.room(home, "programming", { A }, "group", parent)
        R.add_member(home, child, C[1], C[2])
        h.equal(R.decline(home, child, C[1], C[2]), "declined", "decline")
        h.equal(flag_text(home, child), "", "flag line gone")
        h.equal(h.keys(R.withheld(home, child)), "203.0.113.3 7003", "withheld")
        h.equal(R.is_member(home, child, C[1], C[2]), true, "still a member")
        h.equal(h.keys(R.send_list(home, child)), "203.0.113.1 7001", "not sent to")
        h.expect_error("is not flagged", function() R.decline(home, child, C[1], C[2]) end)
        h.expect_error("is not flagged", function() R.decline(home, child, A[1], A[2]) end)
    end)

    h.check("child: a declined member is not flagged again when the parent changes", function()
        local home = h.new_home("child-decline-stays", {})
        local parent = h.room(home, "home", { A })
        local child = h.room(home, "programming", { A }, "group", parent)
        R.add_member(home, child, C[1], C[2])
        R.decline(home, child, C[1], C[2])
        R.add_member(home, parent, B[1], B[2])
        h.equal(flag_text(home, child), "", "still no flag")
    end)

    h.check("child: every room above counts — in the parent but not the grandparent is 'no'", function()
        local home = h.new_home("child-three", {})
        local top = h.room(home, "home", { A, B })
        local middle = h.room(home, "ritz", { A, B }, "group", top)
        local bottom = h.room(home, "programming", {}, "group", middle)
        h.equal(R.add_member(home, middle, C[1], C[2]), "added-flagged", "C not in top")
        local word, answer = R.add_member(home, bottom, C[1], C[2])
        h.equal(word, "added-flagged", "C in middle, not top")
        h.equal(answer, "no", "answer")
        h.equal(R.add_member(home, bottom, B[1], B[2]), "added", "B is in both")
    end)

    h.check("child: dropping someone from a parent flags them in its children and grandchildren", function()
        local home = h.new_home("child-drop", {})
        local top = h.room(home, "home", { A, B })
        local middle = h.room(home, "ritz", { A, B }, "group", top)
        local bottom = h.room(home, "programming", { A, B }, "group", middle)
        h.equal(#R.flagged(home, middle) + #R.flagged(home, bottom), 0, "nobody flagged at first")
        h.equal(R.confirm_leave(home, top, B[1], B[2]), "removed", "B leaves home")
        h.equal(flag_text(home, middle), "203.0.113.2 7002 no", "flagged in the child")
        h.equal(flag_text(home, bottom), "203.0.113.2 7002 no", "flagged in the grandchild")
        h.equal(h.keys(R.send_list(home, bottom)), "203.0.113.1 7001", "B hears nothing below")
        h.equal(R.is_member(home, bottom, B[1], B[2]), true, "nothing removed")
    end)

    h.check("child: a room made with members already in it has them checked (joining a child)", function()
        local home = h.new_home("child-made", {})
        local parent = h.room(home, "home", { A })
        local child = h.room(home, "programming", { A, C }, "group", parent)
        h.equal(flag_text(home, child), "203.0.113.3 7003 no", "C flagged on arrival")
        h.equal(h.keys(R.send_list(home, child)), "203.0.113.1 7001", "only A hears you")
    end)

    h.check("child: a parent not held here gives 'cannot-check', flagged", function()
        local home = h.new_home("child-unheld", { ["mailboxes.unheld-parent"] = "own-mailbox" })
        local tag = orphan(home, "orphan", {}, "somebody-elses-token")
        local word, answer = R.add_member(home, tag, C[1], C[2])
        h.equal(word, "added-flagged", "flagged")
        h.equal(answer, "cannot-check", "answer")
        h.equal(flag_text(home, tag), "203.0.113.3 7003 cannot-check", "line")
    end)

    h.check("child: an approved member is not flagged again on a later re-check", function()
        local home = h.new_home("child-approved-stays", { ["mailboxes.unheld-parent"] = "own-mailbox" })
        local tag = orphan(home, "orphan", {}, "somebody-elses-token")
        R.add_member(home, tag, C[1], C[2])
        R.approve(home, tag, C[1], C[2])
        R.add_member(home, tag, B[1], B[2])
        R.recheck(home, tag, true)
        h.equal(flag_text(home, tag), "203.0.113.3 7003 approved,203.0.113.2 7002 cannot-check", "C stays approved")
    end)

    -- the parent arrives later: under both of 101's mailbox variants, and
    -- both of this module's flag-after-passing variants
    for _, mailbox_mode in ipairs({ "own-mailbox", "waiting-mailbox" }) do
        for _, case in ipairs({ { "kept", "203.0.113.3 7003 cannot-check" }, { "cleared", "" } }) do
            h.check("child: the parent arrives holding a flagged member, mailboxes " .. mailbox_mode
                .. ", flag-after-passing = " .. case[1], function()
                local home = h.new_home("child-arrives-" .. mailbox_mode .. "-" .. case[1], {
                    ["mailboxes.unheld-parent"] = mailbox_mode,
                    ["recipients.flag-after-passing"] = case[1],
                })
                local parent_token = "parent-token-" .. h.rooms.new_local_tag():sub(1, 8)
                local tag = orphan(home, "orphan", {}, parent_token)
                R.add_member(home, tag, C[1], C[2])
                R.add_member(home, tag, B[1], B[2])
                -- the parent arrives: C is in it, B is not
                h.make(home, {
                    label = "home", token = parent_token, kind = "group", parent = "", filed_under = "",
                    members = { { address = A[1], port = A[2], heard = 0 }, { address = C[1], port = C[2], heard = 0 } },
                })
                local lines = flag_text(home, tag)
                local want_b = "203.0.113.2 7002 no"
                h.equal(lines, case[2] == "" and want_b or (case[2] .. "," .. want_b), "flags after the parent arrived")
            end)
        end
    end

    h.check("child: a confirmed leave deletes the flag; returning is checked afresh", function()
        local home = h.new_home("child-leave", {})
        local parent = h.room(home, "home", { A })
        local child = h.room(home, "programming", {}, "group", parent)
        R.add_member(home, child, C[1], C[2])
        R.approve(home, child, C[1], C[2])
        R.confirm_leave(home, child, C[1], C[2])
        h.equal(flag_text(home, child), "", "line gone with the member")
        h.equal(R.heard_from(home, child, C[1], C[2], h.tick()), "added-flagged", "back, flagged again")
    end)

    h.check("child: an unknown recipients.flag-after-passing value is refused when it is read", function()
        local home = h.new_home("child-typo", {
            ["mailboxes.unheld-parent"] = "own-mailbox",
            ["recipients.flag-after-passing"] = "forgotten",
        })
        local parent_token = "parent-token-" .. h.rooms.new_local_tag():sub(1, 8)
        local tag = orphan(home, "orphan", {}, parent_token)
        R.add_member(home, tag, C[1], C[2])
        h.expect_error("not a built variant", function()
            h.make(home, {
                label = "home", token = parent_token, kind = "group", parent = "", filed_under = "",
                members = { { address = C[1], port = C[2], heard = 0 } },
            })
        end)
    end)

    h.check("child: a damaged flagged line is an error, not skipped", function()
        local home = h.new_home("child-damaged", {})
        local parent = h.room(home, "home", { A })
        local child = h.room(home, "programming", {}, "group", parent)
        local file = assert(io.open(h.rooms.flagged_path(home, child), "w"))
        file:write("203.0.113.3 7003 orange\n")
        file:close()
        h.expect_error("unknown flag state", function() R.send_list(home, child) end)
    end)

    h.check("child: ignoring is checked before the tree", function()
        local home = h.new_home("child-ignore", {})
        local parent = h.room(home, "home", { A })
        local child = h.room(home, "programming", {}, "group", parent)
        h.ignore.ignore(home, C[1], C[2], "mark", "*", h.tick())
        h.equal(R.add_member(home, child, C[1], C[2]), "ignored", "ignored first")
        h.equal(flag_text(home, child), "", "no flag written")
    end)
end
-- }}}

return run
