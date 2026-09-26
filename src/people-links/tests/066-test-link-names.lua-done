-- 066-test-link-names.lua — checks how links are named when rooms share a
-- name, in all three collision modes, without touching the disk.
--
-- Run: luajit 066-test-link-names.lua [DIR] <stand-in|real>

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local H = dofile(DIR .. "/src/people-links/tests/065-test-harness.lua")
H.setup(DIR, arg[2])
local names = H.names

local A = "3fa9" .. string.rep("0", 28)
local B = "b710" .. string.rep("1", 28)
local C = "3fa9a" .. string.rep("2", 27)
local D = "3fa9b" .. string.rep("3", 27)
local E = "0000" .. string.rep("4", 28)

-- {{{ local function paths
local function paths(links)
    local out = {}
    for _, link in ipairs(links) do
        out[#out + 1] = link.path .. "=" .. link.room_id:sub(1, 5)
    end
    return out
end
-- }}}

-- unique names: every mode but id-folder keeps them as they are
for _, mode in ipairs({ "suffix-id", "numbered" }) do
    H.same(paths(names.plan({ { room_id = A, name = "home" }, { room_id = B, name = "programming" } }, mode)),
           { "home=3fa90", "programming=b7101" }, mode .. ": unique names kept")
end
H.same(paths(names.plan({ { room_id = A, name = "home" } }, "id-folder")),
       { A .. "/home=3fa90" }, "id-folder: every room in its own id folder")

-- suffix-id
H.same(paths(names.plan({ { room_id = B, name = "programming" }, { room_id = A, name = "programming" } }, "suffix-id")),
       { "programming~3fa9=3fa90", "programming~b710=b7101" }, "suffix-id: both clashing rooms tagged")
H.same(paths(names.plan({ { room_id = C, name = "p" }, { room_id = D, name = "p" } }, "suffix-id")),
       { "p~3fa9a=3fa9a", "p~3fa9b=3fa9b" }, "suffix-id: shared 4-char prefix grows to 5")
H.same(paths(names.plan({ { room_id = A, name = "p" }, { room_id = B, name = "p" },
                          { room_id = E, name = "p~3fa9" } }, "suffix-id")),
       { "p~3fa9=00004", "p~3fa90=3fa90", "p~b7101=b7101" }, "suffix-id: a real room called p~3fa9 is never overwritten")

-- numbered
H.same(paths(names.plan({ { room_id = B, name = "programming" }, { room_id = A, name = "programming" } }, "numbered")),
       { "programming=3fa90", "programming-2=b7101" }, "numbered: room-id order, not input order")
H.same(paths(names.plan({ { room_id = A, name = "p" }, { room_id = B, name = "p" },
                          { room_id = E, name = "p-2" } }, "numbered")),
       { "p=3fa90", "p-2=00004", "p-3=b7101" }, "numbered: skips a number a real room already uses")
H.same(paths(names.plan({ { room_id = A, name = "p" }, { room_id = B, name = "p" }, { room_id = C, name = "p" } }, "numbered")),
       { "p=3fa90", "p-2=3fa9a", "p-3=b7101" }, "numbered: three clashing rooms")
-- finding: numbers follow room ids, so a new room with a lower id takes the
-- bare name and pushes the others up by one
H.same(paths(names.plan({ { room_id = A, name = "p" }, { room_id = B, name = "p" }, { room_id = E, name = "p" } }, "numbered")),
       { "p=00004", "p-2=3fa90", "p-3=b7101" }, "numbered: a lower-id newcomer renumbers the rest")

-- id-folder
H.same(paths(names.plan({ { room_id = B, name = "p" }, { room_id = A, name = "p" } }, "id-folder")),
       { A .. "/p=3fa90", B .. "/p=b7101" }, "id-folder: clashing names never meet")

-- targets are not this file's business, but folder/name are
local one = names.plan({ { room_id = A, name = "p" } }, "id-folder")[1]
H.check(one.folder == A and one.name == "p", "id-folder: folder and name fields")

-- the same input in any order gives the same plan
for _, mode in ipairs(names.MODES) do
    local forward = paths(names.plan({ { room_id = A, name = "x" }, { room_id = B, name = "x" }, { room_id = C, name = "y" } }, mode))
    local backward = paths(names.plan({ { room_id = C, name = "y" }, { room_id = B, name = "x" }, { room_id = A, name = "x" } }, mode))
    H.same(forward, backward, mode .. ": input order does not matter")
end

-- names that cannot be file names are refused, in every mode
for _, mode in ipairs(names.MODES) do
    for _, bad in ipairs({ "", ".", "..", "a/b" }) do
        H.fails(function() names.plan({ { room_id = A, name = bad } }, mode) end,
                "cannot be a link name", mode .. ": refuses name " .. string.format("%q", bad))
    end
end

H.fails(function() names.plan({}, "alphabetical") end, "unknown people.link-collision",
        "unknown collision mode refused")

H.finish()
