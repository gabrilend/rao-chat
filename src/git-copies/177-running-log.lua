-- 177-running-log.lua — the gatherer's running log, committed every sync
-- cycle to a branch of its own and split by size (issue 215a).
--
-- The owner (2026-09-27): "the output log for while it's been running is
-- stored in git, even though it's in RAM, we'll make backups periodically
-- (like every sync cycle maybe) and that gets put in git, always and
-- eternally, once it's large enough we split into a new file."
--
-- Each sync cycle `take_and_commit` reads the RAM `running-log` (211),
-- appends what it holds to the newest file of
--
--   branch  running-log/<home name>
--   files   running-log/<home name>/0001.log, 0002.log, ...
--
-- in the mailbox's repository, and commits.  The branch is never checked
-- out and never shares a tree with the rooms' branch: the files are
-- written through an index of their own (172), on top of the log
-- branch's own tip.
--
-- The split is 138's numbered rule, line by line: a new file starts
-- before a line would carry the current one past `git.log-file-size`
-- bytes, never after, so no file is ever over the limit; a line longer
-- than the limit is split across files.
--
-- The RAM file is emptied only after the commit succeeded (structure
-- R21): on a failure the lines stay in RAM, the caller says so, and the
-- next cycle commits them.  Only the bytes that were committed are taken
-- off the front of the RAM file, so a line written meanwhile is kept.
--
-- For referees only (178): `M.broken` = "split-after" (a new file only
-- after the limit was passed), "drop-oversize" (a cycle larger than the
-- limit dropped), "empty-first" (the RAM file emptied before the commit),
-- "on-rooms-tree" (the log branch built on the rooms' tree) or
-- "default-size" (a missing setting quietly 100,000,000).

local disk = require("003-disk")
local rooms = require("002-room-folders")
local split = require("138-size-split")
local git = require("172-git")

local M = {}

M.broken = nil
M.SETTING = "git.log-file-size"

local q = disk.shell_quote

-- {{{ function M.settings
-- home → the limit in bytes (a whole number ≥ 1), read strictly: a home
-- without the setting is an error naming it.
function M.settings(home)
    local ok, text = pcall(rooms.config_value, home, M.SETTING)
    if not ok then
        if M.broken == "default-size" then return 100000000 end
        error(text, 0)
    end
    if not text:match("^%d+$") or tonumber(text) < 1 then
        error(M.SETTING .. " must be a whole number of bytes ≥ 1, got '" .. text .. "'", 0)
    end
    return tonumber(text)
end
-- }}}

-- {{{ function M.branch / M.path
function M.branch(name) return "running-log/" .. name end
function M.path(name, n) return string.format("running-log/%s/%04d.log", name, n) end
-- }}}

-- {{{ local function newest
-- repo, name, tip → the newest file's number (0 when none) and path.
local function newest(repo, name, tip)
    if not tip then return 0 end
    local list = git.must(repo, { "ls-tree", "--name-only", tip, "running-log/" .. name .. "/" })
    local best = 0
    for n in list:gmatch("/(%d%d%d%d+)%.log") do
        if tonumber(n) > best then best = tonumber(n) end
    end
    return best
end
-- }}}

-- {{{ local function write_pieces
-- work folder, starting number, size of that file, text, limit → the
-- numbers of the files written.  138's numbered writer, one line at a
-- time.
local function write_pieces(work, number, text, limit)
    if M.broken == "drop-oversize" and #text > limit then return {} end
    local writer = split.open({ folder = work, name = "run", limit = limit, naming = "numbered", number = number })
    local first = writer.number
    for line in text:gmatch("[^\n]*\n?") do
        if line ~= "" then
            if M.broken == "split-after" then
                writer:put(line)
                if writer.size > limit then writer:start_next() end
            else
                writer:write(line)
            end
        end
    end
    writer:close()
    local numbers = {}
    for n = first, writer.number do numbers[#numbers + 1] = n end
    return numbers
end
-- }}}

-- {{{ function M.commit_lines
-- repo, name (git.home-name), text (whole lines), limit → the new
-- commit.  Raises when anything fails; then nothing is committed.
function M.commit_lines(repo, name, text, limit)
    local branch = M.branch(name)
    local tip = git.ref(repo, "refs/heads/" .. branch)
    local number = newest(repo, name, tip)
    local work = repo .. "/.git/rao-running-log-work"
    os.execute("rm -rf " .. q(work) .. " && mkdir -p " .. q(work))
    if number == 0 then
        number = 1
    else
        -- the newest file, copied out to be appended to
        local copied = os.execute(git.command(repo, { "cat-file", "blob", tip .. ":" .. M.path(name, number) })
            .. " >" .. q(string.format("%s/run.%04d", work, number)))
        if copied ~= 0 and copied ~= true then error("could not read " .. M.path(name, number) .. " from " .. branch, 0) end
    end
    local numbers = write_pieces(work, number, text, limit)
    local index = repo .. "/.git/rao-index-running-log"
    os.remove(index)
    local env = "GIT_INDEX_FILE=" .. q(index)
    local base = M.broken == "on-rooms-tree" and git.ref(repo, "refs/heads/" .. git.ROOMS_BRANCH) or tip
    if base then
        git.must(repo, { "read-tree", base }, { env = env })
    else
        git.must(repo, { "read-tree", "--empty" }, { env = env })
    end
    for _, n in ipairs(numbers) do
        local blob = git.must(repo, { "hash-object", "-w", string.format("%s/run.%04d", work, n) })
        git.must(repo, { "update-index", "--add", "--cacheinfo", "100644," .. blob .. "," .. M.path(name, n) },
            { env = env })
    end
    local tree = git.must(repo, { "write-tree" }, { env = env })
    os.remove(index)
    os.execute("rm -rf " .. q(work))
    local lines = select(2, text:gsub("\n", ""))
    return git.commit_tree(repo, branch, tree, string.format("running log: %d line(s), %d byte(s)", lines, #text), name)
end
-- }}}

-- {{{ function M.take_and_commit
-- folder (the gatherer's RAM folder), repo, name, limit → how many bytes
-- were committed (0 when the RAM log was empty).  Raises when the commit
-- failed; the RAM file is then as it was.
function M.take_and_commit(folder, repo, name, limit)
    local path = folder .. "/running-log"
    local handle = io.open(path, "rb")
    if not handle then return 0 end
    local text = handle:read("*a")
    handle:close()
    -- whole lines only: a line being written is left for the next cycle
    text = text:match("^(.*\n)") or ""
    if text == "" then return 0 end
    if M.broken == "empty-first" then disk.write_atomic(path, "") end
    M.commit_lines(repo, name, text, limit)
    -- the committed bytes off the front; whatever came after them stays
    local now_text = disk.read_all(path)
    if now_text:sub(1, #text) == text then
        disk.write_atomic(path, now_text:sub(#text + 1))
    end
    return #text
end
-- }}}

return M
