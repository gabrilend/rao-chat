-- 139-failed-decryption.lua — the failed-decryption log: one line for each
-- frame that no held key opens, and for each frame refused for its length
-- (issue 203).
--
-- The file is written for fail2ban first and people second.  Its grammar
-- is a contract with that program, written down once, in
-- docs/failed-decryption-log.md, beside the filter that reads it
-- (docs/fail2ban/).  This file writes and reads exactly that grammar:
--
--   <seconds> <stamp> rao-chat failed-decryption v1 from=<address>
--       port=<source port> to-port=<listening port> length=<announced>
--       reason=<no-key | length>
--
-- on one line, fields separated by single spaces:
--   seconds    whole seconds since 1970 (UTC)
--   stamp      the same instant, ISO-8601 UTC: 2026-11-05T11:52:47Z
--   v1         the grammar's version; a change to the grammar is a new
--              version and a new filter
--   address    the source address as the connection shows it (IPv4 or
--              IPv6 text), never a name looked up
--   port       the source port, as the connection shows it
--   to-port    the mailbox's listening port (already visible on the wire);
--              never a room (sealing R11)
--   length     the length the frame announced (its first 4 bytes)
--   reason     no-key: the whole keyring was tried once and nothing opened
--              it (one line per frame, never one per key: sealing R12);
--              length: refused for its length alone, having read only
--              those 4 bytes (201's cap)
--
-- Nothing in a line comes from the frame's contents but its announced
-- length, a number, so a sender cannot write text into the log.
--
-- Where (211's seam): the opener stage gives the folder (the mailbox's
-- RAM folder); the file is `failed-decryption` there, and older ones
-- `failed-decryption.1`, `.2`, ... (138, "rotate": the newest keeps one
-- name, so fail2ban, which expands a path's pattern when its jail starts,
-- keeps reading it).  Settings, no defaults (135 declares them):
--   failed-decryption.file-size    bytes; at least MIN_FILE_SIZE
--   failed-decryption.files-kept   how many files in all, at least 1
--
-- Decisions of 2026-11-05 (issue 203; the owner may overturn each):
--   open question 1  a frame that opens but is refused (an ignored address
--                    at `hide`) is not written here: it opened, so its
--                    sender holds the room's key, and this log is for
--                    frames nobody here can read
--   open question 2  RAM is acceptable: fail2ban needs only recent lines
--   open question 3  never committed or pushed: the file lives in the RAM
--                    folder, outside every repository

local rooms = require("002-room-folders")
local split = require("138-size-split")

local M = {}

M.FILE = "failed-decryption"
M.VERSION = "v1"
M.REASONS = { ["no-key"] = true, length = true }
-- A line is at most about 150 bytes (an IPv6 address with a zone is the
-- longest field); a file must hold several.
M.MIN_FILE_SIZE = 1024

-- {{{ local function checked_address
-- The source address, refused unless it is address text: digits, hex
-- letters, dots, colons and an IPv6 zone after "%".  A line is never
-- written with something else in that field.
local function checked_address(address)
    if type(address) ~= "string" or not address:match("^[%x:.]+$") and not address:match("^[%x:.]+%%[%w_.-]+$") then
        error("failed-decryption: not an address: " .. tostring(address):sub(1, 60), 3)
    end
    return address
end
-- }}}

-- {{{ local function whole
local function whole(value, name)
    if type(value) ~= "number" or value < 0 or value ~= math.floor(value) then
        error("failed-decryption: " .. name .. " must be a whole number, got " .. tostring(value), 3)
    end
    return value
end
-- }}}

-- {{{ function M.line
-- {seconds, address, port, to_port, length, reason} → one line, "\n" at
-- the end.
function M.line(fields)
    if not M.REASONS[fields.reason] then
        error("failed-decryption: the reason is no-key or length, not " .. tostring(fields.reason), 2)
    end
    local seconds = whole(fields.seconds, "seconds")
    return string.format("%d %s rao-chat failed-decryption %s from=%s port=%d to-port=%d length=%d reason=%s\n",
        seconds, os.date("!%Y-%m-%dT%H:%M:%SZ", seconds), M.VERSION, checked_address(fields.address),
        whole(fields.port, "port"), whole(fields.to_port, "to-port"), whole(fields.length, "length"),
        fields.reason)
end
-- }}}

-- {{{ function M.parse
-- One line (with or without its "\n") → the fields, or nil and why.  The
-- stamp must be the same instant as the seconds.
function M.parse(text)
    local seconds, stamp, version, address, port, to_port, length, reason = text:match(
        "^(%d+) (%S+) rao%-chat failed%-decryption (v%d+) from=(%S+) port=(%d+) to%-port=(%d+) length=(%d+) reason=(%S+)\n?$")
    if not seconds then return nil, "not a failed-decryption line" end
    if version ~= M.VERSION then return nil, "grammar " .. version .. ", this reader knows " .. M.VERSION end
    seconds = tonumber(seconds)
    if os.date("!%Y-%m-%dT%H:%M:%SZ", seconds) ~= stamp then return nil, "the stamp is not the same instant" end
    if not M.REASONS[reason] then return nil, "an unknown reason: " .. reason end
    return { seconds = seconds, address = address, port = tonumber(port), to_port = tonumber(to_port),
             length = tonumber(length), reason = reason }
end
-- }}}

-- {{{ function M.settings
-- home → file_size, files_kept, read strictly: absent, not whole, or too
-- small is an error naming the key.
function M.settings(home)
    local function whole_setting(key, least)
        local text = rooms.config_value(home, key)
        if not text:match("^%d+$") or tonumber(text) < least then
            error(key .. " must be a whole number ≥ " .. least .. ", got '" .. text .. "'", 0)
        end
        return tonumber(text)
    end
    return whole_setting("failed-decryption.file-size", M.MIN_FILE_SIZE),
           whole_setting("failed-decryption.files-kept", 1)
end
-- }}}

local Log = {}
Log.__index = Log

-- {{{ function M.open
-- folder (the mailbox's RAM folder), file_size, files_kept → the log.
function M.open(folder, file_size, files_kept)
    if file_size < M.MIN_FILE_SIZE then
        error("failed-decryption: a file size under " .. M.MIN_FILE_SIZE .. " bytes holds too few lines", 2)
    end
    return setmetatable({ writer = split.open({ folder = folder, name = M.FILE, limit = file_size,
        keep = files_kept, naming = "rotate" }) }, Log)
end
-- }}}

-- {{{ function Log:write
-- peer ({host, port}), to_port, length, reason, seconds → the line written.
function Log:write(peer, to_port, length, reason, seconds)
    local text = M.line({ seconds = seconds, address = peer.host, port = peer.port, to_port = to_port,
                          length = length, reason = reason })
    self.writer:write(text)
    return text
end
-- }}}

-- {{{ function Log:close
function Log:close()
    self.writer:close()
end
-- }}}

-- {{{ function M.seams
-- log, to_port, now (→ whole seconds) → the two seams 133's serve calls:
-- on_unopened(peer, length) and on_refused_length(peer, length).
function M.seams(log, to_port, now)
    return {
        on_unopened = function(peer, length) log:write(peer, to_port, length, "no-key", now()) end,
        on_refused_length = function(peer, length) log:write(peer, to_port, length, "length", now()) end,
    }
end
-- }}}

return M
