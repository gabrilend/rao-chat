-- 068-test-owners-example.lua — the owner's own example, in all three
-- collision modes, driven only by the change bell (no rebuild is called by
-- hand until people/ is deleted on purpose).
--
--   home                 girlfriend, housemate
--   └── ritz             (just you)          declared child of home
--       └── programming  girlfriend, friend  filed under ritz (your own
--                                            filing: the girlfriend is not
--                                            in ritz, so it cannot be a
--                                            declared child of it)
--
-- The girlfriend gets two links (home, programming); adding her to ritz
-- leaves one (home); deleting people/ and rebuilding gives the same links.
-- Also: a person in three rooms, one a declared child of another, gets two
-- links (issue 104's first test).
--
-- Run: luajit 068-test-owners-example.lua [DIR] <stand-in|real-101|real>

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local H = dofile(DIR .. "/src/people-links/tests/065-test-harness.lua")
H.setup(DIR, arg[2])
local rooms, people = H.rooms, H.people

local GF, FRIEND, HOUSE = "gf.example 7000", "friend.example 7001", "house.example 7002"

-- {{{ local function expected_view
-- What H.view should show for a map folder -> list of {name, tag}, in the
-- given collision mode (names here never clash).  Folder "" is a view of
-- one person's folder: no folder line, no prefix.
local function expected_view(mode, map)
    local out = {}
    for folder, list in pairs(map) do
        local prefix = folder .. "/"
        -- one person's view: no prefix; else a folder line first
        if folder == "" then
            prefix = ""
        else
            out[#out + 1] = prefix
        end
        for _, entry in ipairs(list) do
            local name, tag = entry[1], entry[2]
            -- id-folder: a folder per room with the link one level down
            if mode == "id-folder" then
                out[#out + 1] = prefix .. tag .. "/"
                out[#out + 1] = prefix .. tag .. "/" .. name .. " -> ../../../rooms/" .. tag
            -- the other two: the link straight in the person's folder
            else
                out[#out + 1] = prefix .. name .. " -> ../../rooms/" .. tag
            end
        end
    end
    table.sort(out)
    return out
end
-- }}}

-- {{{ local function link_path
local function link_path(home, mode, folder, name, tag)
    -- id-folder: one level deeper
    if mode == "id-folder" then
        return home.dir .. "/people/" .. folder .. "/" .. tag .. "/" .. name
    end
    return home.dir .. "/people/" .. folder .. "/" .. name
end
-- }}}

for _, mode in ipairs(H.names.MODES) do
    local home = H.fresh_home("owners-example-" .. mode, { ["people.link-collision"] = mode })
    local gf_dm     = H.direct(home, "girlfriend", { GF })
    local friend_dm = H.direct(home, "friend", { FRIEND })
    local house_dm  = H.direct(home, "housemate", { HOUSE })
    local home_tag  = H.group(home, "home", { GF, HOUSE })
    local ritz_tag  = H.group(home, "ritz", {}, { parent = home_tag })
    local prog_tag  = H.group(home, "programming", { GF, FRIEND }, { filed = ritz_tag })

    H.same(people.top_rooms_for(home, gf_dm), H.sorted({ home_tag, prog_tag }),
           mode .. ": girlfriend's tops are home and programming")
    H.same(people.top_rooms_for(home, friend_dm), { prog_tag }, mode .. ": friend's top is programming")
    H.same(people.top_rooms_for(home, house_dm), { home_tag }, mode .. ": housemate's top is home")

    local before = H.view(home)
    H.same(before, expected_view(mode, {
        girlfriend = { { "home", home_tag }, { "programming", prog_tag } },
        friend     = { { "programming", prog_tag } },
        housemate  = { { "home", home_tag } },
    }), mode .. ": the bell alone built people/ (girlfriend has two links)")

    H.check(H.label_through(home, link_path(home, mode, "girlfriend", "programming", prog_tag)) == "programming",
            mode .. ": girlfriend/programming leads to the programming room")
    H.check(#people.planned_links(home, "girlfriend") == 2, mode .. ": two planned links for girlfriend")

    -- delete people/ entirely and rebuild: the same view
    os.execute('rm -rf "' .. home.dir .. '/people"')
    H.same(H.view(home), {}, mode .. ": people/ really gone")
    people.rebuild_all(home)
    H.same(H.view(home), before, mode .. ": deleting people/ and rebuilding gives the same links")
    people.rebuild_all(home)
    H.same(H.view(home), before, mode .. ": a second rebuild is a no-op")

    -- add her to ritz: the gap closes, one link left
    H.set_members(home, ritz_tag, { GF })
    H.same(people.top_rooms_for(home, gf_dm), { home_tag }, mode .. ": after adding her to ritz, one top")
    H.same(H.view(home, "girlfriend"), expected_view(mode, { [""] = { { "home", home_tag } } }),
           mode .. ": after adding her to ritz, girlfriend/ holds only home")
    H.same(H.view(home, "friend"), expected_view(mode, { [""] = { { "programming", prog_tag } } }),
           mode .. ": friend unchanged")

    local after = H.view(home)
    os.execute('rm -rf "' .. home.dir .. '/people"')
    people.rebuild_all(home)
    H.same(H.view(home), after, mode .. ": rebuild from nothing after the change")

    -- relabelling a room relabels the links
    rooms.write_label(home, home_tag, "house")
    H.check(H.label_through(home, link_path(home, mode, "girlfriend", "house", home_tag)) == "house",
            mode .. ": relabelled room, relabelled link")
    H.check(not H.disk.exists(link_path(home, mode, "girlfriend", "home", home_tag)),
            mode .. ": old label's link gone")

    -- relabelling the direct message renames the person's folder
    rooms.write_label(home, friend_dm, "coder")
    H.check(H.disk.is_dir(home.dir .. "/people/coder") and not H.disk.exists(home.dir .. "/people/friend"),
            mode .. ": relabelled direct message, renamed folder")

    -- unfiling programming: a top again for her
    rooms.write_filed_under(home, prog_tag, "")
    H.same(people.top_rooms_for(home, gf_dm), H.sorted({ home_tag, prog_tag }),
           mode .. ": unfiling programming makes it a top again")

    -- the housemate taken out of home: her folder goes
    H.set_members(home, home_tag, { GF })
    H.check(not H.disk.exists(home.dir .. "/people/housemate"), mode .. ": housemate's emptied folder removed")

    -- the whole rao-home copied elsewhere: links still lead to rooms there
    local copy = home.dir .. "-copy"
    os.execute('rm -rf "' .. copy .. '"')
    os.execute('cp -a "' .. home.dir .. '" "' .. copy .. '"')
    local copied = copy .. link_path(home, mode, "coder", "programming", prog_tag):sub(#home.dir + 1)
    H.check(H.disk.exists(copied .. "/entry") and H.disk.read_link(copied):sub(-32) == prog_tag,
            mode .. ": links still lead to the room in a copied rao-home")
end

-- issue 104's first test: a person in three rooms, one a declared child of
-- another: two links
do
    local home = H.fresh_home("three-rooms", { ["people.link-collision"] = "suffix-id" })
    local alice = H.direct(home, "alice", { "alice.example 7000" })
    local games = H.group(home, "games", { "alice.example 7000", "bob.example 7000" })
    local chess = H.group(home, "chess", { "alice.example 7000" }, { parent = games })
    local books = H.group(home, "books", { "alice.example 7000" })
    H.same(people.top_rooms_for(home, alice), H.sorted({ games, books }), "three rooms, one a child: two tops")
    H.same(H.view(home, "alice"), H.sorted({ H.link_line("", "games", games), H.link_line("", "books", books) }),
           "three rooms, one a child: two links")
    -- the child's parent not held any more (its token changed by hand
    -- without re-pointing, i.e. a parent fingerprint nobody here holds):
    -- the child is a top
    rooms.write_parent(home, chess, string.rep("ab", 32))
    H.same(people.top_rooms_for(home, alice), H.sorted({ games, chess, books }),
           "a declared parent not held here: the child is a top")
end

-- changing a token by hand: held children follow (101 re-points them), so
-- the links stay
do
    local home = H.fresh_home("token-change", { ["people.link-collision"] = "suffix-id" })
    local alice = H.direct(home, "alice", { "alice.example 7000" })
    local games = H.group(home, "games", { "alice.example 7000" })
    H.group(home, "chess", { "alice.example 7000" }, { parent = games })
    local before = H.view(home)
    rooms.change_token(home, games, "a-brand-new-token-" .. rooms.new_local_tag())
    H.same(H.view(home), before, "token changed by hand: children follow, links unchanged")
    H.same(people.top_rooms_for(home, alice), { games }, "token changed by hand: one top still")
end

H.finish()
