-- 181-inbox-files.lua — the viewer's inbox: one file per message, in RAM
-- (issue 301, step 1).
--
-- The viewer (the Android app, the web page, or a program on the home
-- machine) reads only RAM: each gatherer's `inbox/` folder and its
-- `state`.  This module writes `inbox/`; nothing in the viewer applies
-- edits or reads a log.
--
--   inbox/<room local tag>/<written>-<id>    one file per message
--
-- Sorted by name, a room's folder is the room's order: written time, then
-- id, which is 105's order (`read_ordered`), as long as written times have
-- the same number of digits -- ten, from 2001 to 2286.  Each file is in
-- rmail's inbox-file shape, header lines, a blank line, the body, so a
-- viewer written for rmail's inbox reads it with its own field names:
--
--   id: <message id>
--   room: <the room's local tag on this home>
--   from: me | <address> <port> | the direct-message label (103's shown_as)
--   written: <whole seconds since 1970>
--   arrived: <whole seconds since 1970>
--   signature: <214's rule over the text>
--   edited: yes | no
--   deleted: yes | no
--   ignored: none | mark
--   (a blank line)
--   <the body: the text with the signature line taken off, edits applied>
--
-- What a person sees is what the record says: the views are 105's
-- `read_ordered` (086's edits applied), the signature is 169's one rule;
-- nothing here re-implements either.  A deleted message keeps its file,
-- with `deleted: yes` and an empty body.  A message from an address
-- ignored at `hide` (103a) has no file -- it is never filed in the log,
-- and one filed before the address was hidden has its file removed.
--
-- A reader never sees half a file: every file is written under a
-- temporary name and renamed (161's `put`).  A file is written only when
-- its text changes, so a viewer waiting on change notices is not woken
-- for nothing.  Removing an inbox file deletes nothing (planning section
-- 8): the next pass writes it again.
--
-- Room tags must be 32 hex and ids in 105's alphabet (letters, digits,
-- `-`, `_`, at most 128) before any path is built (structure R14).
--
-- For referees only (182): RAO_INBOX_BROKEN=arrival-order (files named by
-- arrival), raw-text (edits not applied: the original text, never marked
-- deleted), hide-shown (hidden addresses get a file) or in-place (written
-- straight to the final name) are broken versions the referees must
-- catch.

local disk = require("003-disk")
local log = require("081-message-log")
local signature = require("169-signature")
local ignore = require("042-ignore-list")
local recipients = require("041-recipients")
local ram = require("161-ram-folders")

local M = {}

M.broken = os.getenv("RAO_INBOX_BROKEN") or ""
M.MOST_ID = 128

-- {{{ local function checked_tag
local function checked_tag(tag)
    if type(tag) ~= "string" or not tag:match("^%x+$") or #tag ~= 32 then
        error("inbox: room tag '" .. tostring(tag):sub(1, 80) .. "' is not 32 hex", 0)
    end
    return tag
end
-- }}}

-- {{{ local function checked_view
local function checked_view(view)
    local id = view.id
    if type(id) ~= "string" or not id:match("^[%w_%-]+$") or #id > M.MOST_ID then
        error("inbox: id '" .. tostring(id):sub(1, 80) .. "' is not usable in a file name", 0)
    end
    if type(view.written) ~= "number" or view.written < 0 or view.written % 1 ~= 0 then
        error("inbox: written time of " .. id .. " is not a whole number", 0)
    end
    return view
end
-- }}}

-- {{{ function M.folder
-- a gatherer's RAM folder (161's layout) → its inbox folder.
function M.folder(gatherer_folder)
    return gatherer_folder .. "/inbox"
end
-- }}}

-- {{{ function M.file_name
-- view → "<written>-<id>".
function M.file_name(view)
    checked_view(view)
    if M.broken == "arrival-order" then return string.format("%d-%s", view.arrived, view.id) end
    return string.format("%d-%s", view.written, view.id)
end
-- }}}

-- {{{ local function sender
-- view.from → what `from:` shows, and the ignore level of that address.
local function sender(home, tag, from)
    if from == "me" then return "me", "none" end
    local address, port = tostring(from):match("^(%S+) (%d+)$")
    if not address then return tostring(from), "none" end
    port = tonumber(port)
    return recipients.shown_as(home, address, port).text, ignore.how_ignored(home, tag, address, port)
end
-- }}}

-- {{{ function M.file_text
-- home, room tag, view → the file's text, or nil when it has no file
-- (an address ignored at hide).
function M.file_text(home, tag, view)
    checked_view(view)
    local from, level = sender(home, tag, view.from)
    if level == "hide" and M.broken ~= "hide-shown" then return nil end
    local body, sig = signature.read(view.text or "")
    return table.concat({
        "id: " .. view.id,
        "room: " .. tag,
        "from: " .. from,
        "written: " .. string.format("%d", view.written),
        "arrived: " .. string.format("%d", view.arrived or 0),
        "signature: " .. sig,
        "edited: " .. (view.edited and "yes" or "no"),
        "deleted: " .. (view.deleted and "yes" or "no"),
        "ignored: " .. (level == "mark" and "mark" or "none"),
        "",
        body,
    }, "\n")
end
-- }}}

-- {{{ local function views
-- The room as a person should see it: 105's read_ordered, or, in the
-- broken version raw-text, the plain messages as first written.
local function views(home, tag)
    if M.broken ~= "raw-text" then return log.read_ordered(home, tag) end
    local list = {}
    for _, record in ipairs(log.read(home, tag)) do
        if record.kind == "message" then
            list[#list + 1] = { id = record.id, from = record.from, written = record.written,
                                arrived = record.arrived, text = record.text, edited = false, deleted = false }
        end
    end
    return list
end
-- }}}

-- {{{ local function put
local function put(folder, name, text)
    if M.broken == "in-place" then
        local handle = assert(io.open(folder .. "/" .. name, "wb"))
        -- written in two halves, as a slow disk might
        handle:write(text:sub(1, math.floor(#text / 2)))
        handle:flush()
        os.execute("sleep 0.05")
        handle:write(text:sub(math.floor(#text / 2) + 1))
        handle:close()
        return
    end
    ram.put(folder, name, text)
end
-- }}}

-- {{{ function M.write_room
-- gatherer RAM folder, home (the RAM home), room tag → how many files
-- were written or removed.  Brings `inbox/<tag>/` up to date with the
-- room's log: a file per message, written where missing or different.
function M.write_room(gatherer_folder, home, tag)
    checked_tag(tag)
    local folder = M.folder(gatherer_folder) .. "/" .. tag
    os.execute("mkdir -p " .. disk.shell_quote(folder))
    local changed = 0
    for _, view in ipairs(views(home, tag)) do
        local name = M.file_name(view)
        local path = folder .. "/" .. name
        local text = M.file_text(home, tag, view)
        local handle = io.open(path, "rb")
        local now = handle and handle:read("*a")
        if handle then handle:close() end
        if text == nil then
            if now then os.remove(path); changed = changed + 1 end
        elseif now ~= text then
            put(folder, name, text)
            changed = changed + 1
        end
    end
    return changed
end
-- }}}

-- {{{ function M.write_all
-- gatherer RAM folder, home, list of room tags → files written or
-- removed in all of them.
function M.write_all(gatherer_folder, home, tags)
    local changed = 0
    for _, tag in ipairs(tags) do changed = changed + M.write_room(gatherer_folder, home, tag) end
    return changed
end
-- }}}

return M
