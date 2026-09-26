-- 071-test-choices.lua — the config keys failing loudly, what the bell does
-- for each kind of change, and labels that cannot be file names as they
-- are ("/" inside, "." and "..") under both people.slash-in-link-name
-- variants, for room links and for people's folders.
--
-- Run: luajit 071-test-choices.lua [DIR] <stand-in|real-101|real>

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local H = dofile(DIR .. "/src/people-links/tests/065-test-harness.lua")
H.setup(DIR, arg[2])
local rooms, people, disk = H.rooms, H.people, H.disk

local FRIEND = "friend.example 7000"

-- config keys read on every rebuild fail loudly --------------------------------
for _, key in ipairs({ "people.link-collision", "people.direct-message-link", "people.members-without-dm" }) do
    local home = H.fresh_home("missing-" .. key, { [key] = false })
    H.fails(function() people.rebuild_all(home) end, key, "missing " .. key .. " is an error")
    H.fails(function() H.direct(home, "friend", { FRIEND }) end, key,
            "missing " .. key .. ": the error reaches whoever rang the bell")
    rooms.set_config(home, key, "whatever")
    H.fails(function() people.rebuild_all(home) end, "unknown " .. key, "unknown value of " .. key .. " is an error")
end

-- the declared settings (round 4) ----------------------------------------------
-- 101 refuses any config line no module declares, and any read of an
-- undeclared name.  078-settings.lua must therefore list exactly the names
-- this module reads: the same five the options file switches on, each
-- read by name in 061's source (the CHOICES table).
do
    local declared = dofile(DIR .. "/src/people-links/078-settings.lua")
    local options = dofile(DIR .. "/src/people-links/079-options.lua")
    local source = assert(io.open(DIR .. "/src/people-links/061-people-links.lua", "rb")):read("*a")
    local switched = {}
    for _, choice in ipairs(options) do
        -- a switchable choice: its key must be declared
        if choice.config_key ~= "" then
            switched[#switched + 1] = choice.config_key
        end
    end
    H.same(H.sorted(declared), H.sorted(switched),
           "078-settings declares exactly the options file's switchable keys")
    for _, name in ipairs(declared) do
        H.check(source:find('"' .. name .. '"', 1, true) ~= nil,
                "declared " .. name .. " is read by name in 061-people-links.lua")
    end
    -- the real 101: its scan of src/ found them, owned by this folder
    if H.mode ~= "stand-in" then
        local owners = rooms.declared_settings()
        for _, name in ipairs(declared) do
            H.check(owners[name] ~= nil and owners[name].module == "people-links",
                    "the real 101 lists " .. name .. " as people-links'")
        end
        local home = H.fresh_home("undeclared-line", {})
        H.fails(function() rooms.set_config(home, "people.flagged-members", "count") end,
                "people.flagged-members", "the real 101 refuses a people.* name nobody declares")
    end
end

-- keys read only on their edge case are not needed without it ------------------
do
    local home = H.fresh_home("edge-keys-unset", {})
    H.direct(home, "friend", { FRIEND })
    H.group(home, "home", { FRIEND })
    H.check(disk.is_link(home.dir .. "/people/friend/home"),
            "no odd label and no folder clash: slash-in-link-name and person-folder-collision never read")
end

-- the bell -----------------------------------------------------------------------
do
    local home = H.fresh_home("bell", {})
    H.direct(home, "friend", { FRIEND })
    local tag = H.group(home, "home", { FRIEND })
    local link = home.dir .. "/people/friend/home"
    disk.remove_link(link)
    for _, what in ipairs({ "log", "withheld", "heard" }) do
        rooms.notify(home, tag, what)
        H.check(not disk.is_link(link), "bell: " .. what .. " does not rebuild")
    end
    rooms.notify(home, "", "ignore")
    H.check(not disk.is_link(link), "bell: ignore (tag \"\") does not rebuild")
    for _, what in ipairs({ "created", "label", "token", "members", "parent", "filed", "removed-room" }) do
        -- the link removed by hand, then the ring alone must bring it back
        if disk.is_link(link) then
            disk.remove_link(link)
        end
        rooms.notify(home, tag, what)
        H.check(disk.is_link(link), "bell: " .. what .. " rebuilds")
    end
    H.fails(function() rooms.notify(home, tag, "weather") end, "weather",
            "bell: an unknown kind of change is an error")
end

-- labels that are not file names as they are ------------------------------------
local SHAPES = {
    { mode = "percent",        slash = "home%2Fritz",              dot = "%2E",          dotdot = "%2E%2E" },
    { mode = "division-slash", slash = "home\226\136\149ritz",     dot = "\226\128\164", dotdot = "\226\128\165" },
}
for _, shape in ipairs(SHAPES) do
    local home = H.fresh_home("unsafe-" .. shape.mode, { ["people.slash-in-link-name"] = shape.mode })
    H.direct(home, "friend", { FRIEND })
    local slash = H.group(home, "home/ritz", { FRIEND })
    local dot = H.group(home, ".", { FRIEND })
    local dotdot = H.group(home, "..", { FRIEND })
    H.same(H.view(home, "friend"), H.sorted({
        H.link_line("", shape.slash, slash), H.link_line("", shape.dot, dot), H.link_line("", shape.dotdot, dotdot),
    }), shape.mode .. ": room labels '/', '.', '..' become " .. shape.slash .. ", " .. shape.dot .. ", " .. shape.dotdot)

    -- people's folders get the same rewrite
    H.direct(home, "me/work", { "work.example 7000" })
    H.group(home, "office", { "work.example 7000" })
    H.check(disk.is_link(home.dir .. "/people/" .. shape.slash:gsub("home", "me"):gsub("ritz", "work") .. "/office"),
            shape.mode .. ": a direct-message label with '/' is rewritten for its folder")
end
do
    local home = H.fresh_home("unsafe-clash", { ["people.slash-in-link-name"] = "percent",
                                                ["people.link-collision"] = "numbered" })
    H.direct(home, "friend", { FRIEND })
    local a = H.group(home, "a/b", { FRIEND })
    local b = H.group(home, "a%2Fb", { FRIEND })
    local first, second = a, b
    -- tags are random: the lower one takes the bare name under numbered
    if b < a then
        first, second = b, a
    end
    H.same(H.view(home, "friend"), { H.link_line("", "a%2Fb", first), H.link_line("", "a%2Fb-2", second) },
           "an escaped label clashing with a real one is told apart like any clash")
end
do
    local home = H.fresh_home("unsafe-missing-key", {})
    H.direct(home, "friend", { FRIEND })
    H.fails(function() H.group(home, "home/ritz", { FRIEND }) end, "people.slash-in-link-name",
            "people.slash-in-link-name missing is an error once such a label exists")
end

H.finish()
