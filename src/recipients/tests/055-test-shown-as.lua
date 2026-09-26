-- 055-test-shown-as.lua — a member is shown by the label of the direct
-- message holding its address, else by the address; both variants of an
-- address held by two direct messages.

local A = { "203.0.113.1", 7001 }
local B = { "203.0.113.2", 7002 }
local C = { "203.0.113.3", 7003 }

-- {{{ local function run
local function run(h)
    local R = h.recipients

    h.check("shown_as: one direct message holds the address — its label", function()
        local home = h.new_home("shown-one", {})
        h.room(home, "sorelu", { A, { "198.51.100.4", 7001 } }, "direct")
        h.room(home, "coffee", { A, B }, "group")
        local shown = R.shown_as(home, A[1], A[2])
        h.equal(shown.text, "sorelu", "label")
        h.equal(shown.how, "label", "how")
        h.equal(R.shown_as(home, "198.51.100.4", 7001).text, "sorelu", "her other machine")
    end)

    h.check("shown_as: no direct message — the address itself", function()
        local home = h.new_home("shown-none", {})
        h.room(home, "coffee", { B }, "group")
        local shown = R.shown_as(home, B[1], B[2])
        h.equal(shown.text, "203.0.113.2 7002", "address")
        h.equal(shown.how, "address", "how")
    end)

    h.check("shown_as: a group room's label is never used for a person", function()
        local home = h.new_home("shown-group", {})
        h.room(home, "coffee", { C }, "group")
        h.equal(R.shown_as(home, C[1], C[2]).how, "address", "group label not used")
    end)

    h.check("recipients.shared-address-label = all-labels: two direct messages, both labels", function()
        local home = h.new_home("shown-all", { ["recipients.shared-address-label"] = "all-labels" })
        h.room(home, "zed", { A }, "direct")
        h.room(home, "amy", { A }, "direct")
        local shown = R.shown_as(home, A[1], A[2])
        h.equal(shown.text, "amy, zed", "sorted, joined")
        h.equal(shown.how, "labels", "how")
    end)

    h.check("recipients.shared-address-label = address: two direct messages, the address", function()
        local home = h.new_home("shown-addr", { ["recipients.shared-address-label"] = "address" })
        h.room(home, "zed", { A }, "direct")
        h.room(home, "amy", { A }, "direct")
        local shown = R.shown_as(home, A[1], A[2])
        h.equal(shown.text, "203.0.113.1 7001", "address")
        h.equal(shown.how, "address", "how")
    end)

    h.check("recipients.shared-address-label: an unknown value is refused", function()
        local home = h.new_home("shown-typo", { ["recipients.shared-address-label"] = "both" })
        h.room(home, "zed", { A }, "direct")
        h.room(home, "amy", { A }, "direct")
        h.expect_error("not a built variant", function() R.shown_as(home, A[1], A[2]) end)
    end)
end
-- }}}

return run
