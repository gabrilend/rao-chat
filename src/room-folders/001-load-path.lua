-- 001-load-path.lua — lets every rao-chat module find every other one.
--
-- rao-chat's home-server code is split into module folders under src/
-- (room-folders, room-tree, recipients, ...), each built separately.  This
-- file returns one function: given the project folder, it adds each of those
-- folders to the list of places Lua looks when a module is asked for by
-- name, plus the project's libs/ folder for bundled libraries.  After that,
-- any module is loaded by its file name, e.g. require("002-room-folders").
--
-- Usage (from any program or test):
--   dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

-- {{{ local function list_module_folders
-- Module folders are found by listing src/, not by a fixed list, so a new
-- module is picked up without editing this file.  Only folders are listed
-- (src/README is a plain file and holds no modules), sorted, so every
-- program searches the folders in the same order.
local function list_module_folders(dir)
    local listing = io.popen("find \"" .. dir .. "/src\" -mindepth 1 -maxdepth 1 -type d -printf '%f\\n' | sort")
    local folders = {}
    for entry in listing:lines() do
        folders[#folders + 1] = entry
    end
    listing:close()
    return folders
end
-- }}}

-- {{{ local function add_to_search_path
local function add_to_search_path(dir)
    local extra = { dir .. "/libs/?.lua" }
    for _, folder in ipairs(list_module_folders(dir)) do
        extra[#extra + 1] = dir .. "/src/" .. folder .. "/?.lua"
    end
    package.path = table.concat(extra, ";") .. ";" .. package.path
end
-- }}}

return add_to_search_path
