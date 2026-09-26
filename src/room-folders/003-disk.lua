-- 003-disk.lua — the small file-handling tools the room folders are built on.
--
-- Everything rao-chat keeps at home is plain text in plain folders, so a
-- person can read it with `cat` and back it up by copying it.  This file
-- holds the handful of things the rest of room-folders needs to do to
-- those files: read one whole, write one so that it is never seen half
-- written, make a folder, list a folder, and ask whether something is
-- there.  Writing works like swapping a page in a binder: the new page is
-- written out in full beside the old one under a temporary name, then
-- slid into place in one motion (a rename), so anyone reading sees either
-- the old page or the new one, never a torn one.
--
-- Folder making and renaming go through the C library directly (LuaJIT's
-- ffi) so that failures carry the operating system's own reason
-- ("No such file or directory", "Permission denied") instead of a bare
-- false.

local ffi = require("ffi")

-- Another module may already have declared these C functions; declaring
-- one twice is an error in LuaJIT, so each declaration is tried on its
-- own and a "redefined" complaint is the only failure accepted.
local C_DECLARATIONS = {
    "int mkdir(const char *path, unsigned int mode);",
    "char *strerror(int errnum);",
}
for _, declaration in ipairs(C_DECLARATIONS) do
    local ok, problem = pcall(ffi.cdef, declaration)
    -- ok: newly declared.  not ok: must be "attempt to redefine", which
    -- means someone declared it already and the declaration is usable;
    -- anything else is a real problem and stops the load.
    if not ok and not tostring(problem):match("redefine") then
        error(problem)
    end
end

-- {{{ local function shell_quote
-- Paths go to `ls` inside single quotes; a single quote inside the path is
-- closed, escaped, and reopened, so no path can break out of its quotes.
local function shell_quote(path)
    return "'" .. path:gsub("'", "'\\''") .. "'"
end
-- }}}

-- {{{ local function is_dir
-- Opening "<path>/." only succeeds when path is a folder (rmail's test).
local function is_dir(path)
    local handle = io.open(path .. "/.", "r")
    -- handle: path is a folder.  nil: absent, or a plain file.
    if handle then
        handle:close()
        return true
    end
    return false
end
-- }}}

-- {{{ local function is_file
-- A plain file opens for reading and is not a folder.
local function is_file(path)
    local handle = io.open(path, "r")
    -- no handle: nothing readable there at all.
    if not handle then
        return false
    end
    handle:close()
    return not is_dir(path)
end
-- }}}

-- {{{ local function read_all
-- Reads a whole file as one string.  A missing file is an error, because
-- every caller reads files it expects to exist (a room's name, the
-- config); a missing one means the home is damaged, not empty.
local function read_all(path)
    local handle, problem = io.open(path, "rb")
    -- no handle: the file the caller relies on is not there.
    if not handle then
        error("cannot read " .. path .. ": " .. tostring(problem), 2)
    end
    local text = handle:read("*a")
    handle:close()
    return text
end
-- }}}

-- {{{ local function random_suffix
-- Temporary names must not collide when two writers work in one folder at
-- once, so each carries 8 random bytes (16 hex characters).
local function random_suffix()
    local source = assert(io.open("/dev/urandom", "rb"))
    local bytes = source:read(8)
    source:close()
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
-- }}}

-- {{{ local function write_atomic
-- Writes text to path by writing "<path>.tmp-<random>" then renaming it
-- over path.  rename() on one filesystem replaces the old file in one step,
-- so a crash leaves either the old contents or the new, never half.
-- Temporary names start with the target's own name, so they sort beside
-- it in a listing and are easy to recognise if a crash leaves one behind.
-- (Surviving a power cut as well would also need fsync; see 019-options.)
local function write_atomic(path, text)
    local temporary = path .. ".tmp-" .. random_suffix()
    local handle, problem = io.open(temporary, "wb")
    -- no handle: the folder is missing or not writable.
    if not handle then
        error("cannot write " .. temporary .. ": " .. tostring(problem), 2)
    end
    handle:write(text)
    handle:close()
    local ok, rename_problem = os.rename(temporary, path)
    -- not ok: the rename failed; remove the orphan so it is not mistaken
    -- for data, then say why.
    if not ok then
        os.remove(temporary)
        error("cannot move " .. temporary .. " to " .. path .. ": " .. tostring(rename_problem), 2)
    end
end
-- }}}

-- {{{ local function make_dir
-- Makes one folder (not its parents: a missing parent is a mistake the
-- caller should hear about).  Mode 0755 = owner writes, everyone reads.
local function make_dir(path)
    local result = ffi.C.mkdir(path, 493)
    -- non-zero: the operating system refused; its reason is in errno.
    if result ~= 0 then
        error("cannot make folder " .. path .. ": " .. ffi.string(ffi.C.strerror(ffi.errno())), 2)
    end
end
-- }}}

-- {{{ local function rename
local function rename(from, to)
    local ok, problem = os.rename(from, to)
    -- not ok: say which move failed and why.
    if not ok then
        error("cannot move " .. from .. " to " .. to .. ": " .. tostring(problem), 2)
    end
end
-- }}}

-- {{{ local function list_dir
-- Every entry name in a folder, hidden ones included, sorted.  `ls -1A`
-- prints one name per line and leaves out "." and "..".  A name with a
-- newline in it would split in two here; room-folders never makes such
-- names.
local function list_dir(path)
    -- a missing folder: ls would print an error and an empty list would
    -- look like an empty folder, so refuse first.
    if not is_dir(path) then
        error("cannot list " .. path .. ": not a folder", 2)
    end
    local listing = io.popen("ls -1A " .. shell_quote(path))
    local names = {}
    for name in listing:lines() do
        names[#names + 1] = name
    end
    listing:close()
    table.sort(names)
    return names
end
-- }}}

-- {{{ local function remove_tree
-- Removes a folder and everything in it.  Only used on room-folders' own
-- half-built temporary folders, which never hold anything but plain files.
local function remove_tree(path)
    for _, name in ipairs(list_dir(path)) do
        local ok, problem = os.remove(path .. "/" .. name)
        -- not ok: something unexpected (a folder) is inside; stop loudly.
        if not ok then
            error("cannot remove " .. path .. "/" .. name .. ": " .. tostring(problem), 2)
        end
    end
    local ok, problem = os.remove(path)
    -- not ok: the folder could not be removed.
    if not ok then
        error("cannot remove " .. path .. ": " .. tostring(problem), 2)
    end
end
-- }}}

return {
    is_dir = is_dir,
    is_file = is_file,
    read_all = read_all,
    write_atomic = write_atomic,
    make_dir = make_dir,
    rename = rename,
    list_dir = list_dir,
    remove_tree = remove_tree,
    shell_quote = shell_quote,
}
