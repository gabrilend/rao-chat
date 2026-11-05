-- 149-reach.lua — where a mailbox can be reached: its outside port, the
-- home's public address as last confirmed, and the pairs a hello states,
-- each with its kind (issue 212, steps 1 and 4).
--
-- The outside port (open question 1; decision of 2026-11-05, the owner may
-- overturn it) is the number the router forwards to a mailbox's listening
-- port.  It cannot be read off any connection (addresses R1), so the
-- person writes it, per mailbox, in the home's `outside-ports` file beside
-- `mailboxes`, in the same "name.field = value" shape:
--
--   <mailbox tag>.outside-port = 52000
--
-- A separate file rather than a new field of 101's `mailboxes` entries, so
-- phase 1's file and its checks stay as they are; moving the line into
-- `mailboxes` later is a change to this file's reader only.  A mailbox
-- with no line is an error naming the mailbox and the line to write; the
-- listening port is never used in its place ("no default port numbers").
--
-- The public address is one fact per home, kept by 150's watcher in the
-- home's RAM root as `public-address`, one line, tab-separated:
--
--   address     the home's public IPv4 address, as looked up from outside
--   confirmed   whole seconds: when two operators last agreed on it
--   operators   the operators that agreed, comma-separated
--
-- The pairs a mailbox states (the issue's table), for 205's hello:
--   public        the fact file's address   the outside port
--   hostname      config address.hostname   the outside port
--   ipv6          each global IPv6 address   the listening port
--   home-network  each private IPv4 address  the listening port (145 sends
--                                            these only to housemates)
-- The fact's address is stated as it was looked up from outside, whatever
-- its class, except that a public address in 100.64/10 (carrier-grade
-- translation) is not stated:
-- nobody outside can reach it, so a hello naming it could never be
-- confirmed; `state` names it instead (open question 4: run, outbound only,
-- and say so).
--
-- The private-range test is exact (addresses R4): 10/8, 172.16/12,
-- 192.168/16, 100.64/10, 169.254/16; the rest of 172/8 is public.

local rooms = require("002-room-folders")
local disk = require("003-disk")
local formats = require("004-rmail-formats")

local M = {}

M.FACT_NAME = "public-address"

-- {{{ local function home_dir
local function home_dir(home)
    return (rooms.mailboxes_path(home):gsub("/[^/]+$", ""))
end
-- }}}

-- {{{ function M.outside_ports_path
function M.outside_ports_path(home)
    return home_dir(home) .. "/outside-ports"
end
-- }}}

-- {{{ local function check_port
local function check_port(text, where)
    local port = tonumber(text)
    if not text:match("^%d+$") or port < 1 or port > 65535 then
        error(where .. ": an outside port is a whole number 1-65535, got '" .. text .. "'", 0)
    end
    return port
end
-- }}}

-- {{{ function M.read_outside_ports
-- home → { [mailbox tag] = outside port }.  A field other than
-- outside-port, a name that is not a mailbox tag, or a bad port is an error
-- naming the file.  No file: no outside ports yet.
function M.read_outside_ports(home)
    local path = M.outside_ports_path(home)
    local ports = {}
    if not disk.is_file(path) then return ports end
    for name, fields in pairs(formats.parse_contacts(disk.read_all(path), path)) do
        if not rooms.is_local_tag(name) then error(path .. ": '" .. name .. "' is not a mailbox's local tag", 0) end
        for field, value in pairs(fields) do
            if field ~= "outside-port" then error(path .. ": " .. name .. "." .. field .. " is not a field here", 0) end
            ports[name] = check_port(value, path .. " (" .. name .. ")")
        end
    end
    return ports
end
-- }}}

-- {{{ function M.set_outside_port
-- What the viewer (or the person, by hand) writes: home, mailbox tag, port.
function M.set_outside_port(home, mailbox_tag, port)
    rooms.read_mailbox(home, mailbox_tag)
    check_port(tostring(port), "outside port")
    local ports = M.read_outside_ports(home)
    ports[mailbox_tag] = port
    local tags = {}
    for tag in pairs(ports) do tags[#tags + 1] = tag end
    table.sort(tags)
    local lines = { "// rao-chat outside ports: the number your router forwards to each mailbox (issue 212)" }
    for _, tag in ipairs(tags) do lines[#lines + 1] = string.format("%s.outside-port = %d", tag, ports[tag]) end
    disk.write_atomic(M.outside_ports_path(home), table.concat(lines, "\n") .. "\n")
end
-- }}}

-- {{{ function M.outside_port
-- home, mailbox tag → its outside port; an error naming the mailbox and
-- what to write when it has none.
function M.outside_port(home, mailbox_tag)
    local port = M.read_outside_ports(home)[mailbox_tag]
    if port then return port end
    local mailbox = rooms.read_mailbox(home, mailbox_tag)
    error(string.format("mailbox '%s' (%s) has no outside port; write the number your router forwards to "
        .. "its port %d as the line '%s.outside-port = <number>' in %s", mailbox.label, mailbox_tag,
        mailbox.port, mailbox_tag, M.outside_ports_path(home)), 0)
end
-- }}}

-- {{{ function M.check_mailboxes
-- home → the problems a starter reports, one per mailbox without an
-- outside port (empty when every mailbox has one).
function M.check_mailboxes(home)
    local problems = {}
    for _, mailbox in ipairs(rooms.read_mailboxes(home)) do
        local ok, why = pcall(M.outside_port, home, mailbox.tag)
        if not ok then problems[#problems + 1] = why end
    end
    return problems
end
-- }}}

-- {{{ local function ipv4_numbers
local function ipv4_numbers(address)
    local a, b, c, d = address:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return nil end
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    if a > 255 or b > 255 or c > 255 or d > 255 then return nil end
    return a, b, c, d
end
-- }}}

-- {{{ function M.classify
-- An IPv4 address → "public", "private", "carrier" (100.64/10),
-- "link-local", "loopback", or nil when it is not one.  An IPv6 address →
-- "ipv6-global", "ipv6-local" (fc00::/7, fe80::/10, ::1).
function M.classify(address)
    if type(address) ~= "string" then return nil end
    if address:find(":", 1, true) then
        local lower = address:lower()
        if lower == "::1" or lower:match("^f[cd]") or lower:match("^fe[89ab]") then return "ipv6-local" end
        return "ipv6-global"
    end
    local a, b = ipv4_numbers(address)
    if not a then return nil end
    if a == 127 then return "loopback" end
    if a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168) then return "private" end
    if a == 100 and b >= 64 and b <= 127 then return "carrier" end
    if a == 169 and b == 254 then return "link-local" end
    return "public"
end
-- }}}

-- {{{ function M.fact_path
function M.fact_path(ram_root)
    return ram_root .. "/" .. M.FACT_NAME
end
-- }}}

-- {{{ function M.read_fact
-- ram_root → {address, confirmed, operators = {...}}, or nil when no
-- address has been confirmed yet.  A malformed file is an error.
function M.read_fact(ram_root)
    local path = M.fact_path(ram_root)
    if not disk.is_file(path) then return nil end
    local address, confirmed, operators = disk.read_all(path):match("^([^\t\n]+)\t(%d+)\t([^\t\n]+)\n$")
    if not address or not M.classify(address) then
        error(path .. " is not 'address TAB confirmed TAB operators'", 0)
    end
    local list = {}
    for name in operators:gmatch("[^,]+") do list[#list + 1] = name end
    return { address = address, confirmed = tonumber(confirmed), operators = list }
end
-- }}}

-- {{{ function M.write_fact
function M.write_fact(ram_root, fact)
    disk.write_atomic(M.fact_path(ram_root), string.format("%s\t%d\t%s\n", fact.address, fact.confirmed,
        table.concat(fact.operators, ",")))
end
-- }}}

-- {{{ function M.read_ipv6_global
-- The machine's global IPv6 addresses from the kernel's list (default
-- /proc/net/if_inet6: address, index, prefix, scope, flags, name; scope 00
-- is global).  Unique-local and link-local ones are left out.
function M.read_ipv6_global(path)
    path = path or "/proc/net/if_inet6"
    local list = {}
    if not disk.is_file(path) then return list end
    for line in disk.read_all(path):gmatch("[^\n]+") do
        local hex, scope = line:match("^(%x+)%s+%x+%s+%x+%s+(%x+)%s+%x+%s+%S+$")
        if hex and #hex == 32 and scope == "00" then
            local groups = {}
            for i = 1, 32, 4 do groups[#groups + 1] = string.format("%x", tonumber(hex:sub(i, i + 3), 16)) end
            local address = table.concat(groups, ":")
            if M.classify(address) == "ipv6-global" then list[#list + 1] = address end
        end
    end
    return list
end
-- }}}

-- {{{ function M.read_private_ipv4
-- The machine's own private IPv4 addresses (10/8, 172.16/12, 192.168/16)
-- from the kernel's routing table dump (default /proc/net/fib_trie: an
-- address line followed by "/32 host LOCAL" is one of this machine's).
function M.read_private_ipv4(path)
    path = path or "/proc/net/fib_trie"
    local seen, list = {}, {}
    if not disk.is_file(path) then return list end
    local last = nil
    for line in disk.read_all(path):gmatch("[^\n]+") do
        local address = line:match("^[%s|`%-+]*(%d+%.%d+%.%d+%.%d+)%s*$")
        if address then
            last = address
        elseif line:match("/32 host LOCAL") and last then
            if M.classify(last) == "private" and not seen[last] then
                seen[last] = true
                list[#list + 1] = last
            end
        end
    end
    return list
end
-- }}}

-- {{{ function M.hostname
-- home → the configured hostname, or nil when address.hostname is "none".
function M.hostname(home)
    local value = rooms.config_value(home, "address.hostname")
    if value == "none" then return nil end
    if not value:match("^[%w][%w%.%-]*$") or #value > 253 then
        error("address.hostname must be a hostname or 'none', got '" .. value .. "'", 0)
    end
    return value
end
-- }}}

-- {{{ function M.own_pairs
-- home, room tag, the fact (read_fact's, or nil), local addresses
-- ({ipv6 = {...}, private = {...}}) → the pairs this room's mailbox states,
-- each {kind, address, port}.  An error when the mailbox has no outside
-- port.
function M.own_pairs(home, tag, fact, locals)
    local mailbox_tag = rooms.read_entry(home, tag).mailbox
    local listening = rooms.read_mailbox(home, mailbox_tag).port
    local outside = M.outside_port(home, mailbox_tag)
    local list = {}
    if fact and M.classify(fact.address) ~= "carrier" then
        list[#list + 1] = { kind = "public", address = fact.address, port = outside }
    end
    local hostname = M.hostname(home)
    if hostname then list[#list + 1] = { kind = "hostname", address = hostname, port = outside } end
    for _, address in ipairs(locals and locals.ipv6 or {}) do
        list[#list + 1] = { kind = "ipv6", address = address, port = listening }
    end
    for _, address in ipairs(locals and locals.private or {}) do
        list[#list + 1] = { kind = "home-network", address = address, port = listening }
    end
    return list
end
-- }}}

-- {{{ function M.seam
-- home, ram root, locals (a function giving {ipv6, private}; omitted: the
-- kernel's lists) → the `own_pairs(tag)` seam 134's stage takes (205).  The
-- fact file is read at every call, so a confirmed move is stated at once.
function M.seam(home, ram_root, locals)
    locals = locals or function()
        return { ipv6 = M.read_ipv6_global(), private = M.read_private_ipv4() }
    end
    return function(tag) return M.own_pairs(home, tag, M.read_fact(ram_root), locals()) end
end
-- }}}

-- {{{ function M.state
-- home, ram root → what the viewer shows: {public = address or nil,
-- kind = its class, reachable = true/false/nil (not known yet), notes}.
function M.state(home, ram_root)
    local fact = M.read_fact(ram_root)
    local state = { notes = {}, problems = M.check_mailboxes(home) }
    if not fact then
        state.notes[#state.notes + 1] = "the public address has not been confirmed yet"
        return state
    end
    state.public, state.kind = fact.address, M.classify(fact.address)
    if state.kind == "carrier" then
        state.reachable = false
        state.notes[#state.notes + 1] = "carrier-grade address translation: the public address " .. fact.address
            .. " is in 100.64.0.0/10, so nobody outside can reach this home; its mailboxes send but are "
            .. "not announced at that address"
    elseif state.kind == "public" then
        state.reachable = true
    else
        state.reachable = false
        state.notes[#state.notes + 1] = "the public address " .. fact.address .. " is " .. state.kind
            .. ", not public"
    end
    return state
end
-- }}}

return M
