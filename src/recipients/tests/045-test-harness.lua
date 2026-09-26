-- 045-test-harness.lua — the shared toolkit for the recipients tests.
--
-- It does three things: it wires up either the stand-in neighbours kept in
-- this tests folder or the real room-folders and room-tree modules (the
-- runner says which); it makes fresh throw-away home folders in RAM for each
-- test, with every module's settings filled in; and it counts passes and
-- failures, printing one line per test.
--
-- Returns a function(dir, neighbours) giving the harness table `h`.

-- {{{ local function wire_neighbours
-- "stand-in": the two copies in this folder are put where require looks
-- first, so 041-recipients picks them up as if they were the real ones.
-- "real": nothing is pre-loaded; require finds src/room-folders and
-- src/room-tree through the load path.
-- "real-101": the real room folders with the stand-in tree, for while 102
-- is being rewritten and its parent-membership check has not landed.
local function wire_neighbours(dir, neighbours)
    dofile(dir .. "/src/room-folders/001-load-path.lua")(dir)
    local wirings = {
        ["stand-in"] = function()
            local tests = dir .. "/src/recipients/tests/"
            package.loaded["002-room-folders"] = dofile(tests .. "044-stand-in-room-folders.lua")
            package.loaded["021-room-tree"] = dofile(tests .. "046-stand-in-room-tree.lua")
        end,
        ["real"] = function() end,
        ["real-101"] = function()
            package.loaded["021-room-tree"] = dofile(dir .. "/src/recipients/tests/046-stand-in-room-tree.lua")
        end,
    }
    -- only the three built wirings; anything else is a typo in the runner call
    if wirings[neighbours] == nil then
        error("harness: neighbours must be stand-in, real-101 or real, got " .. tostring(neighbours))
    end
    wirings[neighbours]()
end
-- }}}

-- {{{ local function every_first_variant
-- The first listed variant of every switchable choice in every module's
-- options file — what the phase 1 demo starts its homes with (contract,
-- "The options tally") — so the real neighbours, which refuse to guess,
-- can run.  Tests about one of this module's keys set it themselves.
local function every_first_variant(dir)
    local config = {}
    local listing = io.popen("ls " .. dir .. "/src/*/[0-9][0-9][0-9]-options.lua")
    for path in listing:lines() do
        for _, choice in ipairs(dofile(path)) do
            -- switchable: take its first variant; not switchable: nothing to set
            if choice.config_key ~= "" then
                config[choice.config_key] = choice.variants[1].name
            end
        end
    end
    listing:close()
    return config
end
-- }}}

-- {{{ local function make_harness
local function make_harness(dir, neighbours)
    wire_neighbours(dir, neighbours)
    local h = {
        dir = dir,
        neighbours = neighbours,
        rooms = require("002-room-folders"),
        recipients = require("041-recipients"),
        ignore = require("042-ignore-list"),
        pairs = require("040-address-pairs"),
        passed = 0,
        failed = 0,
        failures = {},
        home_count = 0,
        clock = 1790000000,
        start_config = every_first_variant(dir),
    }
    -- every run gets its own scratch folder in RAM, so two runs never share
    h.scratch = dir .. "/tmp/shared-memory/recipients/run-" .. os.time()
        .. "-" .. h.rooms.new_local_tag():sub(1, 6)
    os.execute('mkdir -p "' .. h.scratch .. '"')

    -- {{{ function h.check
    -- Runs one test; a test fails by raising an error.
    function h.check(name, test)
        local ok, why = pcall(test)
        -- no error: a pass; an error: a failure with its message
        if ok then
            h.passed = h.passed + 1
            print("pass  " .. name)
        else
            h.failed = h.failed + 1
            h.failures[#h.failures + 1] = name
            print("FAIL  " .. name .. "\n        " .. tostring(why))
        end
    end
    -- }}}

    -- {{{ function h.expect_error
    -- Passes when fn raises an error whose text contains `fragment`.
    function h.expect_error(fragment, fn)
        local ok, why = pcall(fn)
        -- no error at all: the refusal the test wanted did not happen
        if ok then
            error("expected an error containing '" .. fragment .. "', got none", 2)
        end
        -- an error, but a different one: some other mistake happened first
        if not tostring(why):find(fragment, 1, true) then
            error("expected an error containing '" .. fragment .. "', got: " .. tostring(why), 2)
        end
    end
    -- }}}

    -- {{{ function h.equal
    function h.equal(got, want, what)
        -- equal: fine; different: say both
        if got ~= want then
            error((what or "value") .. ": wanted " .. tostring(want) .. ", got " .. tostring(got), 2)
        end
    end
    -- }}}

    -- {{{ function h.keys
    -- A list of pairs as one comparable string "a 1,b 2" (order kept).
    function h.keys(list)
        local out = {}
        for i, p in ipairs(list) do out[i] = p.address .. " " .. p.port end
        return table.concat(out, ",")
    end
    -- }}}

    -- {{{ function h.new_home
    -- A fresh home with every module's first variant set, then `config`
    -- (key -> value) on top.
    function h.new_home(label, config)
        h.home_count = h.home_count + 1
        local home = h.rooms.open_home(h.scratch .. "/" .. h.home_count .. "-" .. label)
        for key, value in pairs(h.start_config) do
            h.rooms.set_config(home, key, value)
        end
        for key, value in pairs(config) do
            h.rooms.set_config(home, key, value)
        end
        return home
    end
    -- }}}

    -- {{{ function h.room
    -- Makes a room.  members: list of {address, port}; kind "group" unless
    -- given; parent: another room's tag here, or "" for none.
    function h.room(home, label, members, kind, parent_tag)
        local list = {}
        for i, m in ipairs(members) do
            list[i] = { address = m[1], port = m[2], heard = 0 }
        end
        local parent = ""
        -- a child room names its parent by the parent's token fingerprint
        if parent_tag ~= nil and parent_tag ~= "" then
            parent = h.rooms.token_fingerprint(h.rooms.read_entry(home, parent_tag).token)
        end
        return h.rooms.make_room(home, {
            label = label,
            token = "token-" .. label .. "-" .. h.rooms.new_local_tag():sub(1, 8),
            kind = kind or "group",
            parent = parent,
            filed_under = "",
            members = list,
        })
    end
    -- }}}

    -- {{{ function h.tick
    -- The next whole second on a pretend clock.
    function h.tick()
        h.clock = h.clock + 1
        return h.clock
    end
    -- }}}

    -- {{{ function h.rings
    -- Records every ring from now on; returns a function giving the list of
    -- "what@tag" strings heard since, and forgetting them.
    local heard_rings = {}
    h.rooms.on_change(function(home, tag, what)
        heard_rings[#heard_rings + 1] = what .. "@" .. tag
    end)
    function h.rings()
        local out = heard_rings
        heard_rings = {}
        return out
    end
    -- }}}

    return h
end
-- }}}

return make_harness
