-- 130-delivered.lua — what each pair on a room's send list has
-- acknowledged, and so what it is still missing (issue 202, step 1).
--
-- The log is the outbox (owner, 2026-09-27): there is no outbox folder
-- and no queue file.  Beside a room's `log`, a file called `delivered`
-- keeps one line per pair on the send list:
--
--   <address> TAB <port> TAB <mark> TAB <ids> TAB <after>
--
--   mark   whole seconds since 1970: every own record (`from` = "me")
--          written at or before it has been acknowledged by this pair
--   ids    the own records written after the mark that this pair has
--          acknowledged, separated by single spaces (ids hold only
--          letters, digits, "-" and "_"), in the order acknowledged;
--          empty when none
--   after  (since 209) the id of the newest own record in the log when
--          the line was made, or "-" when there was none: the records
--          after it in file order are the ones meant for this pair, which
--          209's cross-check may send again.  A line without the field
--          (made before 209) reads as "-".
--
-- "Missing for a pair" is worked out, never stored: the own records in
-- the log, in file order, written after the pair's mark and not in its
-- ids.  An acknowledgement adds ids, then moves the mark forward over
-- every written time whose records are all acknowledged, and drops the
-- ids the mark now covers, so the list stays short.
--
-- A pair's line is made when its first message is written while it is on
-- the send list (`join`, called by 134 before the message is filed):
-- every own record already in the log counts as acknowledged, so a new
-- or un-withheld pair gets what is written from then on (decision of
-- 2026-11-05, issue 202 open question 3; the owner may overturn it).  A
-- pair that leaves the send list loses its line at the next write, so
-- one that comes back starts again from then.
--
-- The mark relies on own written times never going back in file order;
-- 134's write keeps them so.
--
-- The file is rewritten whole (write, then rename over), by the sender
-- stage only: 211 must keep it to one writer per room at a time.  A room
-- made before 202 has no `delivered` file, which reads as no lines.

local rooms = require("002-room-folders")
local disk = require("003-disk")
local message_log = require("081-message-log")

local M = {}

-- {{{ local function key
local function key(address, port)
    return address .. " " .. tostring(port)
end
-- }}}

-- {{{ function M.path
function M.path(home, tag)
    return rooms.room_dir(home, tag) .. "/delivered"
end
-- }}}

-- {{{ function M.read
-- home, tag → { [key] = {address, port, mark, ids = {id, ...}} } and the
-- keys in file order.  A malformed line is an error naming it.
function M.read(home, tag)
    local path = M.path(home, tag)
    local lines, order = {}, {}
    if not disk.is_file(path) then return lines, order end
    local number = 0
    for line in disk.read_all(path):gmatch("[^\n]+") do
        number = number + 1
        local address, port, mark, ids, after = line:match("^([^\t]+)\t([1-9]%d*)\t(%d+)\t([%w%-_ ]*)\t([%w%-_]+)$")
        if not address then
            address, port, mark, ids = line:match("^([^\t]+)\t([1-9]%d*)\t(%d+)\t([%w%-_ ]*)$")
            after = "-"
        end
        if not address then
            error("delivered: line " .. number .. " of " .. path .. " is not 'address TAB port TAB mark TAB ids TAB after'", 0)
        end
        local entry = { address = address, port = tonumber(port), mark = tonumber(mark), ids = {}, after = after }
        for id in ids:gmatch("%S+") do entry.ids[#entry.ids + 1] = id end
        local k = key(address, entry.port)
        if lines[k] then error("delivered: " .. k .. " has two lines in " .. path, 0) end
        lines[k] = entry
        order[#order + 1] = k
    end
    return lines, order
end
-- }}}

-- {{{ function M.write
function M.write(home, tag, lines, order)
    local out = {}
    for _, k in ipairs(order) do
        local entry = lines[k]
        if entry then
            out[#out + 1] = table.concat({ entry.address, tostring(entry.port),
                string.format("%d", entry.mark), table.concat(entry.ids, " "), entry.after or "-" }, "\t") .. "\n"
        end
    end
    disk.write_atomic(M.path(home, tag), table.concat(out))
end
-- }}}

-- {{{ function M.own_records
-- The room's own records (messages and edits, `from` = "me"), file order.
function M.own_records(home, tag)
    local own = {}
    for _, record in ipairs(message_log.read(home, tag)) do
        if record.from == "me" then own[#own + 1] = record end
    end
    return own
end
-- }}}

-- {{{ local function starting_line
-- A line for a pair that joins now: every own record already filed counts
-- as acknowledged.  The mark stops one second short of the newest written
-- time, and that second's records go in the ids, so a record written
-- later in the same second is still missing.
local function starting_line(address, port, own)
    local newest = -1
    for _, record in ipairs(own) do
        if record.written > newest then newest = record.written end
    end
    local entry = { address = address, port = port, mark = math.max(newest - 1, 0), ids = {},
                    after = #own > 0 and own[#own].id or "-" }
    for _, record in ipairs(own) do
        if record.written > entry.mark then entry.ids[#entry.ids + 1] = record.id end
    end
    return entry
end
-- }}}

-- {{{ function M.join
-- home, tag, send_list (103's list of {address, port}) → nothing.  Makes a
-- line for each pair on the list without one, and drops the lines of pairs
-- no longer on it.  Called before an own record is filed.
function M.join(home, tag, send_list)
    local lines, order = M.read(home, tag)
    local own = nil
    local wanted, new_order, changed = {}, {}, false
    for _, pair in ipairs(send_list) do
        local k = key(pair.address, pair.port)
        wanted[k] = true
        if not lines[k] then
            own = own or M.own_records(home, tag)
            lines[k] = starting_line(pair.address, pair.port, own)
            order[#order + 1] = k
            changed = true
        end
    end
    for _, k in ipairs(order) do
        if wanted[k] then new_order[#new_order + 1] = k else changed = true end
    end
    if changed then M.write(home, tag, lines, new_order) end
end
-- }}}

-- {{{ function M.drop
-- home, tag, pair → true when the pair had a line and it was removed (208:
-- a confirmed leave drops what was not yet delivered).  Other lines are
-- written back as they were.
function M.drop(home, tag, pair)
    local lines, order = M.read(home, tag)
    local k = key(pair.address, pair.port)
    if not lines[k] then return false end
    lines[k] = nil
    M.write(home, tag, lines, order)
    return true
end
-- }}}

-- {{{ function M.missing_for
-- home, tag, pair → the own records this pair has not acknowledged, in
-- file order (a message before its edits).  A pair with no line is
-- missing nothing: it was not on the send list when anything was written.
function M.missing_for(home, tag, pair)
    local lines = M.read(home, tag)
    local entry = lines[key(pair.address, pair.port)]
    if not entry then return {} end
    local acked = {}
    for _, id in ipairs(entry.ids) do acked[id] = true end
    local missing = {}
    for _, record in ipairs(M.own_records(home, tag)) do
        if record.written > entry.mark and not acked[record.id] then missing[#missing + 1] = record end
    end
    return missing
end
-- }}}

-- {{{ function M.acknowledge
-- home, tag, pair, ids (acknowledged by this pair) → nothing.  Ids that
-- are not own records after the mark are ignored.  Then the mark moves
-- forward over each written time whose own records are all acknowledged.
function M.acknowledge(home, tag, pair, ids)
    local lines, order = M.read(home, tag)
    local entry = lines[key(pair.address, pair.port)]
    if not entry or #ids == 0 then return end
    local own = M.own_records(home, tag)
    local acked, pending = {}, {}
    for _, id in ipairs(entry.ids) do acked[id] = true end
    for _, record in ipairs(own) do
        if record.written > entry.mark then pending[record.id] = record.written end
    end
    for _, id in ipairs(ids) do
        if pending[id] and not acked[id] then
            acked[id] = true
            entry.ids[#entry.ids + 1] = id
        end
    end
    -- the earliest written time after the mark still holding an
    -- unacknowledged record: the mark may move to just before it
    local blocked = math.huge
    local latest = entry.mark
    for id, written in pairs(pending) do
        if not acked[id] and written < blocked then blocked = written end
        if written > latest then latest = written end
    end
    local new_mark = blocked == math.huge and latest or blocked - 1
    if new_mark > entry.mark then
        entry.mark = new_mark
        local kept = {}
        for _, id in ipairs(entry.ids) do
            if pending[id] and pending[id] > new_mark then kept[#kept + 1] = id end
        end
        entry.ids = kept
    end
    M.write(home, tag, lines, order)
end
-- }}}

-- {{{ function M.meant_for
-- home, tag, pair → the set of own record ids written for this pair: those
-- after its line's join point in file order.  None without a line.
function M.meant_for(home, tag, pair)
    local entry = (M.read(home, tag))[key(pair.address, pair.port)]
    local set = {}
    if not entry then return set end
    local counting = entry.after == "-"
    for _, record in ipairs(M.own_records(home, tag)) do
        if counting then set[record.id] = true end
        if record.id == entry.after then counting = true end
    end
    return set
end
-- }}}

-- {{{ function M.forget
-- 209: home, tag, pair, ids (own records the pair turned out to lack) →
-- the ids it had counted as acknowledged and now does not.  The mark goes
-- back to just before the earliest of them, and every other own record
-- the mark covered stays acknowledged in the ids, so only these are
-- missing again; only an acknowledgement marks them again (R4).
function M.forget(home, tag, pair, ids)
    local lines, order = M.read(home, tag)
    local entry = lines[key(pair.address, pair.port)]
    if not entry or #ids == 0 then return {} end
    local own = M.own_records(home, tag)
    local drop, acked, forgotten = {}, {}, {}
    for _, id in ipairs(ids) do drop[id] = true end
    for _, id in ipairs(entry.ids) do acked[id] = true end
    local lowest = nil
    for _, record in ipairs(own) do
        if drop[record.id] and (record.written <= entry.mark or acked[record.id]) then
            forgotten[#forgotten + 1] = record.id
            if record.written <= entry.mark and (not lowest or record.written < lowest) then lowest = record.written end
        end
    end
    if #forgotten == 0 then return forgotten end
    local old_mark = entry.mark
    if lowest then entry.mark = lowest - 1 end
    local kept, seen = {}, {}
    for _, record in ipairs(own) do
        local covered_before = record.written <= old_mark or acked[record.id]
        if record.written > entry.mark and covered_before and not drop[record.id] and not seen[record.id] then
            seen[record.id] = true
            kept[#kept + 1] = record.id
        end
    end
    entry.ids = kept
    M.write(home, tag, lines, order)
    return forgotten
end
-- }}}

-- {{{ function M.pile
-- home, tag → list of {address, port, missing (count), oldest (written
-- time of the oldest missing record, or nil)}: what each pair waits for,
-- for the viewer (open question 6).
function M.pile(home, tag)
    local lines, order = M.read(home, tag)
    local own = M.own_records(home, tag)
    local list = {}
    for _, k in ipairs(order) do
        local entry = lines[k]
        local acked = {}
        for _, id in ipairs(entry.ids) do acked[id] = true end
        local count, oldest = 0, nil
        for _, record in ipairs(own) do
            if record.written > entry.mark and not acked[record.id] then
                count = count + 1
                if not oldest or record.written < oldest then oldest = record.written end
            end
        end
        list[#list + 1] = { address = entry.address, port = entry.port, missing = count, oldest = oldest }
    end
    return list
end
-- }}}

M.key = key
return M
