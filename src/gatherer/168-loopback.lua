-- 168-loopback.lua — the loopback interface, for the programs that run
-- real gatherers in a network namespace of their own (issue 211).
--
-- `unshare -rn` gives a namespace whose only interface, `lo`, is down, so
-- not even 127.0.0.1 answers.  This brings it up with the same ioctl `ip
-- link set lo up` makes, through LuaJIT's FFI, so no outside tool is
-- needed.  It changes nothing that is already up, and it touches no
-- interface but `lo`.
--
--   is_up()          → whether lo is up
--   bring_up()       → true, or nil and why (not allowed outside a
--                      namespace of one's own, say)
--   only_loopback()  → whether lo is the only interface here: no packet
--                      can leave, so a lookup outside cannot happen

local ffi = require("ffi")

ffi.cdef [[
int socket(int domain, int type, int protocol);
int ioctl(int fd, unsigned long request, ...);
int close(int fd);
char *strerror(int errnum);
struct rao_ifreq { char name[16]; short flags; char rest[22]; };
]]

local AF_INET, SOCK_DGRAM = 2, 2
local SIOCGIFFLAGS, SIOCSIFFLAGS = 0x8913, 0x8914
local IFF_UP = 1

local M = {}

-- {{{ local function flags
-- → the socket, the request (holding lo's flags), or nil and why.
local function flags()
    local fd = ffi.C.socket(AF_INET, SOCK_DGRAM, 0)
    if fd < 0 then return nil, nil, "no socket: " .. ffi.string(ffi.C.strerror(ffi.errno())) end
    local request = ffi.new("struct rao_ifreq")
    ffi.copy(request.name, "lo")
    if ffi.C.ioctl(fd, SIOCGIFFLAGS, request) < 0 then
        local why = ffi.string(ffi.C.strerror(ffi.errno()))
        ffi.C.close(fd)
        return nil, nil, "cannot read lo's flags: " .. why
    end
    return fd, request
end
-- }}}

-- {{{ function M.is_up
function M.is_up()
    local fd, request = flags()
    if not fd then return false end
    ffi.C.close(fd)
    return bit.band(request.flags, IFF_UP) ~= 0
end
-- }}}

-- {{{ function M.bring_up
function M.bring_up()
    local fd, request, why = flags()
    if not fd then return nil, why end
    if bit.band(request.flags, IFF_UP) ~= 0 then ffi.C.close(fd); return true end
    request.flags = bit.bor(request.flags, IFF_UP)
    local ok = ffi.C.ioctl(fd, SIOCSIFFLAGS, request) >= 0
    why = not ok and ffi.string(ffi.C.strerror(ffi.errno())) or nil
    ffi.C.close(fd)
    if not ok then return nil, "cannot bring lo up: " .. why end
    return true
end
-- }}}

-- {{{ function M.only_loopback
function M.only_loopback()
    local f = io.open("/proc/net/dev", "rb")
    if not f then return false end
    local text = f:read("*a")
    f:close()
    local names = 0
    for name in text:gmatch("\n%s*([^%s:]+):") do
        if name ~= "lo" then return false end
        names = names + 1
    end
    return names == 1
end
-- }}}

return M
