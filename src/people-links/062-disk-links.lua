-- 062-disk-links.lua — the few disk operations the people/ folder needs that
-- plain Lua does not have: making, reading and removing symbolic links,
-- making and removing folders, and listing a folder.
--
-- A symbolic link is a tiny file whose whole content is a path to somewhere
-- else; opening it opens the place it points to.  Lua's standard library
-- cannot make one.  LuaJIT can call the operating system's own C functions
-- directly (its "foreign function interface"), so this file declares the
-- handful of system calls needed (symlink, readlink, unlink, mkdir, rmdir,
-- opendir/readdir/closedir, access) and wraps each in a Lua function that
-- raises an error carrying the system's own reason when the call fails.
--
-- No shell is used, so folder and link names are never re-read by a shell
-- and cannot be misunderstood by it (a contact called  it's  is safe).

local ffi = require("ffi")

-- The layout of one folder entry as the C library hands it back.  This is
-- the Linux x86_64 layout, identical in glibc and musl: an 8-byte inode
-- number, an 8-byte position, a 2-byte record length, a 1-byte type, then
-- the name as a zero-terminated string of up to 255 bytes.  Only the name is
-- read here; the type byte is not trusted because some filesystems leave it
-- as "unknown", so link-ness and folder-ness are asked of the system
-- separately (readlink, opendir).
ffi.cdef[[
typedef struct rao_dirent {
    uint64_t       d_ino;
    int64_t        d_off;
    unsigned short d_reclen;
    unsigned char  d_type;
    char           d_name[256];
} rao_dirent;
typedef struct rao_DIR rao_DIR;
int        symlink(const char *target, const char *linkpath);
long       readlink(const char *path, char *buf, size_t size);
int        unlink(const char *path);
int        mkdir(const char *path, unsigned int mode);
int        rmdir(const char *path);
int        access(const char *path, int mode);
rao_DIR   *opendir(const char *path);
rao_dirent *readdir(rao_DIR *dir);
int        closedir(rao_DIR *dir);
char      *strerror(int errnum);
]]

local C = ffi.C

-- errno numbers used below (Linux values)
local EINVAL    = 22   -- readlink on something that is not a link
local ENOENT    = 2    -- nothing at that path
local EEXIST    = 17   -- something already at that path
local ENOTEMPTY = 39   -- rmdir on a folder that still holds things
local F_OK      = 0    -- access(): does the path lead anywhere

-- a link target never needs more than this; ours are under 120 bytes
local LINK_BUFFER_SIZE = 4096

local M = {}

-- {{{ local function system_reason
-- The system's own words for the last failure, e.g. "Permission denied".
local function system_reason(errnum)
    return ffi.string(C.strerror(errnum))
end
-- }}}

-- {{{ local function try_read_link
-- Asks the system what a link points to.  Gives (true, target) for a link,
-- or (false, errno) for anything else, so callers can tell "not a link"
-- (EINVAL), "nothing there" (ENOENT) and real failures apart.
local function try_read_link(path)
    local buffer = ffi.new("char[?]", LINK_BUFFER_SIZE)
    local length = C.readlink(path, buffer, LINK_BUFFER_SIZE)
    -- negative: the system refused; say why by number
    if length < 0 then
        return false, ffi.errno()
    end
    -- a target filling the whole buffer may have been cut short
    if length >= LINK_BUFFER_SIZE then
        error("disk-links: link target too long at " .. path)
    end
    return true, ffi.string(buffer, length)
end
-- }}}

-- {{{ function M.is_link
-- true when path is itself a symbolic link (dangling or not).
function M.is_link(path)
    local ok, answer = try_read_link(path)
    -- a link: yes
    if ok then
        return true
    end
    -- not a link, or nothing there: a plain no
    if answer == EINVAL or answer == ENOENT then
        return false
    end
    -- anything else (permission, bad path) is a real fault
    error("disk-links: cannot look at " .. path .. ": " .. system_reason(answer))
end
-- }}}

-- {{{ function M.read_link
-- The target text stored in the link at path.  Errors when path is not a
-- link, since every caller has already checked with is_link.
function M.read_link(path)
    local ok, answer = try_read_link(path)
    -- a link: its target
    if ok then
        return answer
    end
    -- otherwise: the caller asked about something that is not a link
    error("disk-links: " .. path .. " is not a link: " .. system_reason(answer))
end
-- }}}

-- {{{ function M.make_link
-- Makes a link at path whose content is target (stored as given, so a
-- relative target stays relative).  Errors if anything is already there.
function M.make_link(target, path)
    local result = C.symlink(target, path)
    -- nonzero: the system refused (most often something is already there)
    if result ~= 0 then
        error("disk-links: cannot make link " .. path .. " -> " .. target
              .. ": " .. system_reason(ffi.errno()))
    end
end
-- }}}

-- {{{ function M.remove_link
-- Removes the link at path.  Checks first that it is a link, because the
-- system's unlink would just as happily delete an ordinary file, and this
-- module promises never to delete anything but its own links.
function M.remove_link(path)
    -- not a link: refuse rather than delete a file someone put there
    if not M.is_link(path) then
        error("disk-links: refusing to remove " .. path .. ": not a link")
    end
    local result = C.unlink(path)
    -- nonzero: the system refused
    if result ~= 0 then
        error("disk-links: cannot remove link " .. path .. ": " .. system_reason(ffi.errno()))
    end
end
-- }}}

-- {{{ function M.is_dir
-- true when path is a folder (following a link, as opendir does).
function M.is_dir(path)
    local dir = C.opendir(path)
    -- could not open it as a folder
    if dir == nil then
        return false
    end
    C.closedir(dir)
    return true
end
-- }}}

-- {{{ function M.exists
-- true when anything at all is at path, including a link that points
-- nowhere (access alone would say no to a dangling link).
function M.exists(path)
    -- a link, even a dangling one, is something
    if M.is_link(path) then
        return true
    end
    return C.access(path, F_OK) == 0
end
-- }}}

-- {{{ function M.make_dir
-- Makes one folder (not its parents).  A folder already there is fine; any
-- other thing already there is an error.
function M.make_dir(path)
    local result = C.mkdir(path, tonumber("755", 8))
    -- made: done
    if result == 0 then
        return
    end
    local errnum = ffi.errno()
    -- already a folder there: nothing to do
    if errnum == EEXIST and M.is_dir(path) and not M.is_link(path) then
        return
    end
    -- something else is in the way, or the system refused
    error("disk-links: cannot make folder " .. path .. ": " .. system_reason(errnum))
end
-- }}}

-- {{{ function M.remove_dir_if_empty
-- Removes a folder only if it is empty.  Gives true when removed, false when
-- it still holds something (which is left alone).
function M.remove_dir_if_empty(path)
    local result = C.rmdir(path)
    -- removed
    if result == 0 then
        return true
    end
    local errnum = ffi.errno()
    -- still holds something: keep it
    if errnum == ENOTEMPTY or errnum == EEXIST then
        return false
    end
    -- any other refusal is a real fault
    error("disk-links: cannot remove folder " .. path .. ": " .. system_reason(errnum))
end
-- }}}

-- {{{ function M.list_dir
-- The names inside a folder, without "." and "..", sorted byte-wise so every
-- caller sees the same order.
function M.list_dir(path)
    local dir = C.opendir(path)
    -- not a folder we can open: the caller expected one
    if dir == nil then
        error("disk-links: cannot list " .. path .. ": " .. system_reason(ffi.errno()))
    end
    local names = {}
    local entry = C.readdir(dir)
    while entry ~= nil do
        local name = ffi.string(entry.d_name)
        -- skip the folder's names for itself and its parent
        if name ~= "." and name ~= ".." then
            names[#names + 1] = name
        end
        entry = C.readdir(dir)
    end
    C.closedir(dir)
    table.sort(names)
    return names
end
-- }}}

return M
