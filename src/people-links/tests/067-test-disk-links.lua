-- 067-test-disk-links.lua — checks the small disk layer (links and folders
-- made through LuaJIT's foreign-function interface) in a RAM scratch folder.
--
-- Run: luajit 067-test-disk-links.lua [DIR] <stand-in|real>

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local H = dofile(DIR .. "/src/people-links/tests/065-test-harness.lua")
H.setup(DIR, arg[2])
local disk = H.disk

local base = DIR .. "/tmp/shared-memory/people-links/" .. H.mode .. "-disk"
os.execute('rm -rf "' .. base .. '"')
os.execute('mkdir -p "' .. base .. '/target"')

-- {{{ local function write_file
local function write_file(path, text)
    local file = assert(io.open(path, "w"))
    file:write(text)
    file:close()
end
-- }}}

write_file(base .. "/target/name", "hello\n")

-- a relative link, read back exactly as written, and followed by the system
disk.make_link("target", base .. "/link")
H.check(disk.is_link(base .. "/link"), "made link is a link")
H.check(disk.read_link(base .. "/link") == "target", "target kept relative, as written")
local through = io.open(base .. "/link/name", "r")
H.check(through ~= nil and through:read("*l") == "hello", "system follows the relative link")
-- opened: close it
if through then through:close() end

-- a dangling link still counts as something there
disk.make_link("../nowhere", base .. "/dangling")
H.check(disk.is_link(base .. "/dangling"), "dangling link is a link")
H.check(disk.exists(base .. "/dangling"), "dangling link exists")
H.check(not disk.is_dir(base .. "/dangling"), "dangling link is not a folder")

-- ordinary things are not links
H.check(not disk.is_link(base .. "/target"), "folder is not a link")
H.check(not disk.is_link(base .. "/target/name"), "file is not a link")
H.check(not disk.is_link(base .. "/absent"), "nothing is not a link")
H.check(not disk.exists(base .. "/absent"), "nothing does not exist")
H.fails(function() disk.read_link(base .. "/target/name") end, "is not a link", "read_link refuses a file")

-- making a link where something is: refused
H.fails(function() disk.make_link("x", base .. "/link") end, "cannot make link", "make_link will not overwrite")

-- remove_link only ever removes links
H.fails(function() disk.remove_link(base .. "/target/name") end, "not a link", "remove_link refuses a file")
H.check(io.open(base .. "/target/name", "r") ~= nil, "the file survived")
disk.remove_link(base .. "/dangling")
H.check(not disk.exists(base .. "/dangling"), "link removed")
H.check(disk.is_dir(base .. "/target"), "removing the link to a folder leaves the folder")

-- folders
disk.make_dir(base .. "/made")
H.check(disk.is_dir(base .. "/made"), "make_dir makes a folder")
disk.make_dir(base .. "/made")
H.check(true, "make_dir on an existing folder is fine")
H.fails(function() disk.make_dir(base .. "/target/name") end, "cannot make folder", "make_dir refuses over a file")
H.fails(function() disk.make_dir(base .. "/link") end, "cannot make folder", "make_dir refuses over a link to a folder")
H.check(disk.remove_dir_if_empty(base .. "/target") == false, "non-empty folder kept")
H.check(disk.is_dir(base .. "/target"), "non-empty folder still there")
H.check(disk.remove_dir_if_empty(base .. "/made") == true, "empty folder removed")

-- listing: sorted, no . or .., odd names intact (no shell involved)
write_file(base .. "/it's a \"name\"", "x")
H.same(disk.list_dir(base), { "it's a \"name\"", "link", "target" }, "list_dir sorted with odd names")
H.fails(function() disk.list_dir(base .. "/absent") end, "cannot list", "list_dir of nothing errors")

H.finish()
