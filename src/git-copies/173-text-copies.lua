-- 173-text-copies.lua — the text copy of every message, one file per
-- message in the mailbox's git repository, committed once per sync cycle
-- (issue 215).
--
-- The log (105) stays the delivery record; the copies are a reading and
-- editing copy beside it, fed one way: log → copies, never back.
--
-- The repository: `<disk home>/git/<mailbox tag>/` (open question 1,
-- decided 2026-11-05: in the home, beside rooms/).  Its checked-out
-- branch is `rooms`; in its working tree:
--
--   rooms/<room fingerprint>/<written>-<id>.txt   one copy per message
--   labels        fingerprint → this home's own label, one line per room;
--                 left out of the repository (.git/info/exclude): labels
--                 are private (planning section 2) and never tracked
--
-- and inside .git/, never tracked: `rao-copies`, how far into each room's
-- log the copies have been brought (a byte offset per local tag).
--
-- A copy holds only the agreed part, what every home holding the room
-- writes identically, so two members' copies of one message are the same
-- bytes at the same path:
--
--   id: <id>
--   written: <seconds since 1970> <ISO-8601 UTC>
--   kind: message | correction
--   target: <the id the correction changes, or nothing>
--   signature: <169's rule over the text>
--   (a blank line)
--   <the text exactly as written>
--
-- `from` and `arrived` differ per home and stay in the log only.  The
-- room folder is the token fingerprint (007: the same on every home, and
-- it reveals nothing without the token), never the local tag.
--
-- Edits.  A copy is named after its message and stays at that path for
-- life.  A correction rewrites it with the latest correction of that
-- message — by written time, then id: 086's order, so every home picks
-- the same one — and its lines are that correction's (kind correction,
-- target the message).  A deletion removes the file.  Both are committed
-- at the next sync, so git keeps every version.
--
-- Hand edits.  The person may change or delete any copy; the next sync
-- commits that, and nothing is sent.  A correction that arrives later for
-- the same message rewrites the copy (open question 3, decided
-- 2026-11-05: as proposed; history keeps the hand edit).
--
-- Bringing copies up to date.  `filed(tag)` (the filing hook, run by the
-- gatherer after each record is filed or written) and `sync()` (each sync
-- cycle) both call `catch_up`, which reads the room's log from the offset
-- the copies have reached and applies each record after it, in log order.
-- So a hook that failed, or a gatherer that stopped between filing and
-- copying, is made good at the next sync from the log; and records the
-- copies already reached are never applied twice (a hand edit made since
-- is not written over).  The offsets are saved after each commit.
--
-- Paths are built only from a 64-hex fingerprint, a whole number and an
-- id in 105's alphabet (letters, digits, '-', '_': no '/', no '.'),
-- checked here again before any path is built (structure R14).
--
-- For referees only (175): RAO_COPIES_BROKEN=per-home-fields (the copy
-- also carries `from` and `arrived`) or local-tag-folder (rooms named by
-- the local tag) are broken versions referee 1 must catch.

local disk = require("003-disk")
local rooms = require("002-room-folders")
local reader = require("084-log-reader")
local signature = require("169-signature")
local git = require("172-git")

local M = {}

local BROKEN = os.getenv("RAO_COPIES_BROKEN") or ""
local q = disk.shell_quote

M.MOST_ID = 128

-- {{{ function M.repository
-- disk home folder, mailbox tag → the repository's folder.
function M.repository(home_dir, mailbox)
    if not tostring(mailbox):match("^%x+$") then error("not a mailbox tag: " .. tostring(mailbox), 0) end
    return home_dir .. "/git/" .. mailbox
end
-- }}}

-- The broken version of referee 6 (175 sets it): no check before a path
-- is built.
M.unchecked = false

-- {{{ local function check_record
local function check_record(record)
    if M.unchecked then return end
    local id = record.id
    if type(id) ~= "string" or not id:match("^[%w_%-]+$") or #id > M.MOST_ID then
        error("text copy: id '" .. tostring(id):sub(1, 80) .. "' is not usable in a file name", 0)
    end
    if type(record.written) ~= "number" or record.written < 0 or record.written % 1 ~= 0 then
        error("text copy: written time of " .. id .. " is not a whole number", 0)
    end
end
-- }}}

-- {{{ function M.copy_name
-- the message record → "<written>-<id>.txt".
function M.copy_name(record)
    check_record(record)
    return string.format("%d-%s.txt", record.written, record.id)
end
-- }}}

-- {{{ function M.copy_text
-- record (the message, or the correction whose text it now shows) → the
-- copy's bytes.
function M.copy_text(record)
    check_record(record)
    local lines = {
        "id: " .. record.id,
        "written: " .. string.format("%d", record.written) .. " " .. os.date("!%Y-%m-%dT%H:%M:%SZ", record.written),
        "kind: " .. record.kind,
        "target:" .. ((record.target or "") ~= "" and (" " .. record.target) or ""),
    }
    local sig = signature.signature(record.text or "")
    lines[#lines + 1] = "signature:" .. (sig ~= "" and (" " .. sig) or "")
    if BROKEN == "per-home-fields" then
        lines[#lines + 1] = "from: " .. tostring(record.from)
        lines[#lines + 1] = "arrived: " .. tostring(record.arrived)
    end
    return table.concat(lines, "\n") .. "\n\n" .. (record.text or "")
end
-- }}}

-- {{{ local function later
-- 086's order of edits of one message: the later written time, then the
-- larger id.
local function later(a, b)
    if a.written ~= b.written then return a.written > b.written end
    return a.id > b.id
end
-- }}}

-- {{{ function M.current
-- records (a room's, in log order), message id → the message record, and
-- what its copy shows now: the record to write (the message or its latest
-- correction), or false when deleted.  nil when the message is not there.
function M.current(records, id)
    local message, fix, deleted
    for _, r in ipairs(records) do
        if r.kind == "message" and r.id == id then message = r
        elseif r.kind == "correction" and r.target == id then
            if not fix or later(r, fix) then fix = r end
        elseif r.kind == "deletion" and r.target == id then deleted = true end
    end
    if not message then return nil end
    if deleted then return message, false end
    return message, fix or message
end
-- }}}

------------------------------------------------------------------------------
-- A mailbox's copies
------------------------------------------------------------------------------

local Copies = {}
Copies.__index = Copies

-- {{{ function M.open
-- home (the RAM home the gatherer files into), disk_dir (the disk home),
-- mailbox (tag), name (git.home-name) → a copies value.  Makes the
-- repository if it is not there; a repository made now is brought up to
-- date with every record already in the mailbox's logs at the next
-- catch_up (its offsets start at 0).
function M.open(home, disk_dir, mailbox, name)
    git.check_name(name)
    local self = setmetatable({
        home = home, mailbox = mailbox, name = name,
        repo = M.repository(disk_dir, mailbox),
        offsets = {}, made = false,
    }, Copies)
    os.execute("mkdir -p " .. q(disk_dir .. "/git"))
    self.made = git.ensure(self.repo)
    local text = io.open(self.repo .. "/.git/rao-copies", "rb")
    if text then
        for tag, offset in text:read("*a"):gmatch("(%x+) (%d+)\n") do self.offsets[tag] = tonumber(offset) end
        text:close()
    end
    return self
end
-- }}}

-- {{{ function Copies:folder
-- tag → the room's folder name: its token fingerprint.
function Copies:folder(tag)
    if BROKEN == "local-tag-folder" then return tag end
    local entry = rooms.read_entry(self.home, tag)
    return rooms.token_fingerprint(entry.token)
end
-- }}}

-- {{{ local function write_copy / remove_copy
local function write_copy(path, text)
    local folder = path:match("^(.*)/[^/]+$")
    if not disk.is_dir(folder) then os.execute("mkdir -p " .. q(folder)) end
    local old = io.open(path, "rb")
    if old then
        local same = old:read("*a") == text
        old:close()
        if same then return end
    end
    disk.write_atomic(path, text)
end
-- }}}

-- {{{ function Copies:apply
-- tag, record, records (the room's, needed for edits) → applies one
-- record to the working tree.
function Copies:apply(tag, record, records)
    local dir = self.repo .. "/rooms/" .. self:folder(tag)
    if record.kind == "message" then
        write_copy(dir .. "/" .. M.copy_name(record), M.copy_text(record))
        return
    end
    local message, shown = M.current(records, record.target)
    if not message then return end          -- 105 files no edit without its message
    local path = dir .. "/" .. M.copy_name(message)
    if shown then
        write_copy(path, M.copy_text(shown))
    else
        os.remove(path)
    end
end
-- }}}

-- {{{ function Copies:catch_up
-- tag → how many records were applied.  Reads the room's log from the
-- copies' offset; applies each record after it, in order; moves the
-- offset after each.  An error ends the catch-up where it stands (the
-- next one starts there).
function Copies:catch_up(tag)
    local content = disk.read_all(rooms.log_path(self.home, tag))
    local offset = self.offsets[tag] or 0
    if offset > #content then offset = 0 end          -- a log shorter than before: start again
    if offset == #content then return 0 end
    local list, starts = reader.parse(content:sub(offset + 1))
    local records
    local applied = 0
    for i, record in ipairs(list) do
        if record.kind ~= "message" and not records then records = reader.parse(content) end
        self:apply(tag, record, records)
        applied = applied + 1
        self.offsets[tag] = offset + (starts[i + 1] and (starts[i + 1] - 1) or (#content - offset))
    end
    return applied
end
-- }}}

-- {{{ function Copies:labels
-- Rewrites `labels` when it changed: "<fingerprint> <label>" per room.
function Copies:write_labels(tags)
    local lines = {}
    for _, tag in ipairs(tags) do
        local entry = rooms.read_entry(self.home, tag)
        lines[#lines + 1] = rooms.token_fingerprint(entry.token) .. " " .. (entry.label or ""):gsub("\n", " ")
    end
    table.sort(lines)
    local text = "# this home's own labels for the room folders under rooms/ (never tracked, never sent)\n"
        .. table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
    write_copy(self.repo .. "/labels", text)
end
-- }}}

-- {{{ function Copies:save_offsets
function Copies:save_offsets()
    local lines = {}
    for tag, offset in pairs(self.offsets) do lines[#lines + 1] = tag .. " " .. offset .. "\n" end
    table.sort(lines)
    disk.write_atomic(self.repo .. "/.git/rao-copies", table.concat(lines))
end
-- }}}

-- {{{ function Copies:changed_since_commit
-- → list of {status, path} for the working tree against the last commit
-- (nothing staged yet): what the next commit would hold.
function Copies:changed_since_commit()
    git.must(self.repo, { "add", "-A", "." })
    local list = {}
    local out = git.must(self.repo, { "diff", "--cached", "--name-status", "--no-renames" })
    for status, path in out:gmatch("(%u)%d*\t([^\n]+)") do list[#list + 1] = { status = status, path = path } end
    return list
end
-- }}}

-- {{{ function Copies:commit
-- → {added, changed, removed, other, commit} for what was committed, or
-- nil when nothing changed.  One commit for the whole working tree (the
-- copies the hooks wrote, the person's hand edits); its message counts
-- the copies.
function Copies:commit(why)
    local list = self:changed_since_commit()
    if #list == 0 then return nil end
    local counts = { added = 0, changed = 0, removed = 0, other = 0 }
    for _, item in ipairs(list) do
        if item.path:match("^rooms/") then
            local key = item.status == "A" and "added" or item.status == "D" and "removed" or "changed"
            counts[key] = counts[key] + 1
        else
            counts.other = counts.other + 1
        end
    end
    local message = string.format("%s: %d cop%s added, %d changed, %d removed%s", why or "sync",
        counts.added, counts.added == 1 and "y" or "ies", counts.changed, counts.removed,
        counts.other > 0 and string.format("; %d other file(s)", counts.other) or "")
    local args = git.identity(self.name)
    for _, w in ipairs({ "commit", "-q", "--no-verify", "-m", message }) do args[#args + 1] = w end
    git.must(self.repo, args)
    counts.commit = git.ref(self.repo, "HEAD")
    counts.message = message
    return counts
end
-- }}}

-- {{{ function Copies:sync
-- tags (this mailbox's rooms) → the commit's counts, or nil.  Each sync
-- cycle: every room brought up to date from its log (a failed hook is
-- made good here), `labels` rewritten, one commit, offsets saved.
function Copies:sync(tags)
    local problems = {}
    for _, tag in ipairs(tags) do
        local ok, why = pcall(self.catch_up, self, tag)
        if not ok then problems[#problems + 1] = tag:sub(1, 8) .. ": " .. tostring(why) end
    end
    self:write_labels(tags)
    local counts = self:commit("sync")
    self:save_offsets()
    if #problems > 0 then error("text copies: " .. table.concat(problems, "; "), 0) end
    return counts
end
-- }}}

return M
