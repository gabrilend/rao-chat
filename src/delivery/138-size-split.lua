-- 138-size-split.lua — a growing text file kept as a series of files, each
-- under a size limit (issue 203, step 3; the rule 215a's running log uses).
--
-- The rule (215a): a new file starts **before** a write would carry the
-- current one past the limit, never after.  So no file is ever larger
-- than the limit; a file may be smaller, since the write that did not fit
-- goes whole into the next one.
--
-- Two ways of naming the files, one rule:
--
--   "rotate"    the newest file always has the same name (`<name>`), so a
--               program that follows a path — fail2ban — keeps reading
--               it.  When it is full it is renamed `<name>.1`, an older
--               `.1` becomes `.2`, and so on; only `keep` files in all are
--               kept, the oldest removed.  (203's failed-decryption log.)
--   "numbered"  `<name>.0001`, `<name>.0002`, ...: nothing is renamed or
--               removed, and `keep` is not used.  (215a's running log,
--               whose files go into git and are kept forever.)
--
-- A single write larger than the limit: "numbered" splits it across files
-- (215a: "a single cycle's lines larger than the limit are split across
-- files"); "rotate" refuses it, because a log line cut in two matches
-- nothing — 203 checks that the limit is far larger than its longest line.
--
-- The writer keeps its current file open and counts its size, so a flood
-- costs one write per line, not an open and a stat.  On opening it carries
-- on from what is already on disk.

local M = {}

-- {{{ local function file_size
local function file_size(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    return size
end
-- }}}

-- {{{ local function numbered_name
local function numbered_name(base, n)
    return string.format("%s.%04d", base, n)
end
-- }}}

local Writer = {}
Writer.__index = Writer

-- {{{ function M.would_pass
-- The rule on its own: does adding `adding` bytes to a file of `size`
-- bytes carry it past `limit`?
function M.would_pass(size, adding, limit)
    return size + adding > limit
end
-- }}}

-- {{{ function M.open
-- {folder, name, limit (bytes), keep (rotate: files kept in all, ≥ 1),
-- naming ("rotate" | "numbered")} → a writer.
function M.open(options)
    local limit, naming = options.limit, options.naming or "rotate"
    if type(limit) ~= "number" or limit < 1 or limit ~= math.floor(limit) then
        error("size-split: the limit must be a whole number of bytes ≥ 1", 2)
    end
    if naming ~= "rotate" and naming ~= "numbered" then
        error("size-split: naming is rotate or numbered, not " .. tostring(naming), 2)
    end
    if naming == "rotate" and (type(options.keep) ~= "number" or options.keep < 1) then
        error("size-split: a rotated file needs keep ≥ 1", 2)
    end
    local self = setmetatable({ folder = options.folder, name = options.name, limit = limit,
        keep = options.keep, naming = naming }, Writer)
    self.base = self.folder .. "/" .. self.name
    if naming == "numbered" then
        local n = 1
        while file_size(numbered_name(self.base, n + 1)) do n = n + 1 end
        self.number = n
    end
    self.size = file_size(self:current_path()) or 0
    return self
end
-- }}}

-- {{{ function Writer:current_path
function Writer:current_path()
    if self.naming == "numbered" then return numbered_name(self.base, self.number) end
    return self.base
end
-- }}}

-- {{{ function Writer:start_next
-- The current file is full: close it and start the next one.
function Writer:start_next()
    if self.handle then self.handle:close(); self.handle = nil end
    if self.naming == "numbered" then
        self.number = self.number + 1
    else
        -- the oldest goes, the rest move up one, the newest becomes .1
        local oldest = self.keep - 1
        if oldest >= 1 then
            os.remove(self.base .. "." .. oldest)
            for n = oldest - 1, 1, -1 do os.rename(self.base .. "." .. n, self.base .. "." .. (n + 1)) end
            os.rename(self.base, self.base .. ".1")
        else
            os.remove(self.base)
        end
    end
    self.size = 0
end
-- }}}

-- {{{ function Writer:put
-- Writes text into the current file (opened on first use).
function Writer:put(text)
    if not self.handle then
        self.handle = assert(io.open(self:current_path(), "ab"))
        self.handle:setvbuf("no")
    end
    assert(self.handle:write(text))
    self.size = self.size + #text
end
-- }}}

-- {{{ function Writer:write
-- text → true.  Starts a new file first if this text would carry the
-- current one past the limit (and the current one holds anything).
function Writer:write(text)
    if #text > self.limit then
        if self.naming == "rotate" then
            error("size-split: a write of " .. #text .. " bytes is larger than the limit of "
                .. self.limit .. " and would be cut in two", 2)
        end
        -- numbered: fill what is left of the current file, then whole files
        local rest = text
        while #rest > 0 do
            local room = self.limit - self.size
            if room == 0 then self:start_next(); room = self.limit end
            self:put(rest:sub(1, room))
            rest = rest:sub(room + 1)
        end
        return true
    end
    if self.size > 0 and M.would_pass(self.size, #text, self.limit) then self:start_next() end
    self:put(text)
    return true
end
-- }}}

-- {{{ function Writer:close
function Writer:close()
    if self.handle then self.handle:close(); self.handle = nil end
end
-- }}}

return M
