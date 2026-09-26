-- 047-test-address-pairs.lua — the address-and-port shape: what is refused,
-- how a pair becomes a file line and back.

-- {{{ local function run
local function run(h)
    local P = h.pairs

    h.check("pairs: a hostname, an IPv4 and an IPv6 address are accepted", function()
        P.check("sorelu.example.org", 7777)
        P.check("203.0.113.9", 1)
        P.check("2001:db8::1", 65535)
    end)

    h.check("pairs: no default port — a missing, text, fractional or out-of-range port is refused", function()
        h.expect_error("port must be", function() P.check("203.0.113.9", nil) end)
        h.expect_error("port must be", function() P.check("203.0.113.9", "7777") end)
        h.expect_error("port must be", function() P.check("203.0.113.9", 77.5) end)
        h.expect_error("port must be", function() P.check("203.0.113.9", 0) end)
        h.expect_error("port must be", function() P.check("203.0.113.9", 65536) end)
    end)

    h.check("pairs: an empty address or one holding spaces is refused", function()
        h.expect_error("address must be", function() P.check("", 7777) end)
        h.expect_error("may not hold spaces", function() P.check("a b", 7777) end)
        h.expect_error("may not hold spaces", function() P.check("a\nb", 7777) end)
    end)

    h.check("pairs: a file line round-trips, colons in IPv6 included", function()
        local path = h.scratch .. "/pairs-roundtrip"
        local rows = {
            { address = "2001:db8::1", port = 7777, words = { "x", "12" } },
            { address = "203.0.113.9", port = 80, words = { "y", "13" } },
        }
        local file = assert(io.open(path, "w"))
        file:write(P.pair_file_text(rows))
        file:close()
        local back = P.read_pair_file(path, 2)
        h.equal(#back, 2, "rows")
        h.equal(back[1].address, "2001:db8::1", "address")
        h.equal(back[1].port, 7777, "port is a number")
        h.equal(back[2].words[2], "13", "extra word")
    end)

    h.check("pairs: a damaged line (wrong word count, text port) stops the reader", function()
        local path = h.scratch .. "/pairs-damaged"
        local file = assert(io.open(path, "w"))
        file:write("203.0.113.9 7777 extra\n")
        file:close()
        h.expect_error("expected 2 words", function() P.read_pair_file(path, 0) end)
        file = assert(io.open(path, "w"))
        file:write("203.0.113.9 seven\n")
        file:close()
        h.expect_error("whole number", function() P.read_pair_file(path, 0) end)
    end)

    h.check("pairs: an absent file is an error, not an empty list", function()
        h.expect_error("cannot read", function() P.read_pair_file(h.scratch .. "/no-such-file", 0) end)
    end)
end
-- }}}

return run
