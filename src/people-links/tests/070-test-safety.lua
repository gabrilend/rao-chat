-- 070-test-safety.lua — the promise that nothing in people/ is removed
-- unless it is a link this module made, and that nothing someone else put
-- there is ever overwritten.
--
-- Run: luajit 070-test-safety.lua [DIR] <stand-in|real-101|real>

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local H = dofile(DIR .. "/src/people-links/tests/065-test-harness.lua")
H.setup(DIR, arg[2])
local rooms, people, disk = H.rooms, H.people, H.disk

-- {{{ local function write_file
local function write_file(path, text)
    local file = assert(io.open(path, "w"))
    file:write(text)
    file:close()
end
-- }}}

local GONE = string.rep("e", 32)   -- a tag no room has
local GF, HOUSE, FRIEND = "gf.example 7000", "house.example 7000", "friend.example 7000"

for _, mode in ipairs(H.names.MODES) do
    local home = H.fresh_home("safety-" .. mode, { ["people.link-collision"] = mode })
    H.direct(home, "girlfriend", { GF })
    H.direct(home, "housemate", { HOUSE })
    H.direct(home, "friend", { FRIEND })
    local home_tag = H.group(home, "home", { GF, HOUSE })
    local p = home.dir .. "/people"

    -- things someone else put in people/
    write_file(p .. "/README", "my notes about people/\n")
    write_file(p .. "/girlfriend/notes.txt", "birthday in may\n")
    disk.make_link("/etc", p .. "/girlfriend/elsewhere")                        -- not our shape
    disk.make_link("../rooms/" .. home_tag, p .. "/girlfriend/shallow")         -- wrong depth
    os.execute('mkdir -p "' .. p .. '/girlfriend/photos"')
    disk.make_link("../../rooms/" .. home_tag, p .. "/girlfriend/photos/deep")  -- ours in shape, not in a tag folder

    -- links of ours that are stale
    disk.make_link("../../rooms/" .. GONE, p .. "/girlfriend/old-room")         -- room no longer exists
    -- the bell already made housemate/home in the flat modes; swap it
    if disk.is_link(p .. "/housemate/home") then
        disk.remove_link(p .. "/housemate/home")
    end
    disk.make_link("../../rooms/" .. GONE, p .. "/housemate/home")              -- right name, wrong target
    os.execute('mkdir -p "' .. p .. '/formerfriend/' .. GONE .. '"')
    disk.make_link("../../../rooms/" .. GONE, p .. "/formerfriend/" .. GONE .. "/stuff")
    disk.make_link("../../rooms/" .. GONE, p .. "/formerfriend/stuff")

    people.rebuild_all(home)

    H.check(io.open(p .. "/README") ~= nil, mode .. ": README at people/ top kept")
    H.check(io.open(p .. "/girlfriend/notes.txt") ~= nil, mode .. ": a note in a person's folder kept")
    H.check(disk.is_link(p .. "/girlfriend/elsewhere"), mode .. ": a foreign link kept")
    H.check(disk.is_link(p .. "/girlfriend/shallow"), mode .. ": a link of another depth kept")
    H.check(disk.is_link(p .. "/girlfriend/photos/deep"), mode .. ": a link inside a non-tag folder kept")
    H.check(not disk.exists(p .. "/girlfriend/old-room") and not disk.is_link(p .. "/girlfriend/old-room"),
            mode .. ": our link to a vanished room removed")
    H.check(not disk.exists(p .. "/formerfriend"), mode .. ": a folder nobody owns: our links and emptied folders removed")

    local want = (mode == "id-folder") and ("../../../rooms/" .. home_tag) or ("../../rooms/" .. home_tag)
    local at = (mode == "id-folder") and (p .. "/housemate/" .. home_tag .. "/home") or (p .. "/housemate/home")
    H.check(disk.is_link(at) and disk.read_link(at) == want, mode .. ": wrong-target link replaced by the right one")

    -- taken out of every room: our links go, the folder stays for the note
    H.set_members(home, home_tag, { HOUSE })
    H.check(disk.is_dir(p .. "/girlfriend"), mode .. ": folder kept while it holds someone's note")
    H.check(io.open(p .. "/girlfriend/notes.txt") ~= nil, mode .. ": note still there after her links went")
    H.same(people.planned_links(home, "girlfriend"), {}, mode .. ": nothing planned for her")

    -- something that is not our link sits exactly where a link must go
    local blocked = (mode == "id-folder") and (p .. "/friend/" .. home_tag) or (p .. "/friend/home")
    os.execute('mkdir -p "' .. p .. '/friend"')
    write_file(blocked, "mine\n")
    H.fails(function() H.set_members(home, home_tag, { HOUSE, FRIEND }) end,
            (mode == "id-folder") and "cannot make folder" or "is in the way",
            mode .. ": refuses to overwrite a file where a link must go")
    H.check(io.open(blocked):read("*l") == "mine", mode .. ": the blocking file untouched")
    os.remove(blocked)

    -- a person's folder that is itself a link: never followed into
    os.execute('mkdir -p "' .. home.dir .. '/outside"')
    disk.make_link("../../rooms/" .. GONE, home.dir .. "/outside/looks-like-ours")
    disk.make_link("../outside", p .. "/linked-person")
    people.rebuild_person(home, "linked-person")
    H.check(disk.is_link(home.dir .. "/outside/looks-like-ours"),
            mode .. ": a link-shaped entry behind a linked person folder is not touched")

    -- a folder name that cannot be one
    H.fails(function() people.rebuild_person(home, "../escape") end, "cannot be a folder name",
            mode .. ": refuses a folder name with a slash")
    H.fails(function() people.rebuild_person(home, "..") end, "cannot be a folder name",
            mode .. ": refuses .. as a folder name")

    -- people/ itself a link: refused
    os.execute('mv "' .. p .. '" "' .. home.dir .. '/people-real"')
    disk.make_link("people-real", p)
    H.fails(function() people.rebuild_all(home) end, "is a link", mode .. ": people/ as a link is refused")
end

H.finish()
