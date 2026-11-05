-- 179-sharing.lua — sharing a mailbox's text copies through a shared
-- upstream: pull, then push, at three moments (issue 215b).
--
-- The owner (2026-09-27): edits to the git copy reach others "only if they
-- share an upstream. Ideally, git push when the server starts up and shuts
-- down, and maybe whenever it does random IP checks"; on pulling: "yeah
-- probs"; on the code: "it should be freely downloadable for anyone
-- sharing the same upstream."
--
-- Upstreams are the mailbox repository's own git remotes, which the person
-- adds with `git remote add` (decided 2026-11-05: the remote's address and
-- its credentials stay in git's own place, never in rao-chat's config):
--
--   upstream           the mailbox's shared upstream
--   room-<fingerprint> one room's own upstream (git.upstream-rooms =
--                      repository-per-room)
--
-- A mailbox with no such remote shares nothing and says nothing about it.
--
-- `moment(s)` is one pull-then-push, for each remote in use:
--
--   1. fetch everything from it (in the background, killed after
--      git.share-deadline seconds; the caller's wait lets the gatherer's
--      other threads run meanwhile: structure R4);
--   2. merge its `rooms` into the local rooms' branch.  The same message
--      filed on two homes is the same bytes (215's agreed part), so it
--      merges cleanly.  A conflict (two different hand edits of one copy)
--      is never resolved: the merge is aborted, the conflict reported,
--      and the next moment tries again; nothing of the rooms is pushed
--      to that remote while it stands;
--   3. push a commit on top of the remote's `rooms` whose tree is the
--      remote's, with each room folder this home may share there replaced
--      by its own.  Its only parent is the remote's tip, so nothing of a
--      room that is not shared there is reachable from what is pushed;
--      plus `code/<home name>`, and `running-log/<home name>` only when
--      git.push-running-log = yes (to `upstream` only).  Once pushed, that
--      commit is merged here with this tree kept as it is (`-s ours`), so
--      the next pull starts from it.
--
-- Which room folders a remote gets (git.upstream-rooms, no default):
--
--   only-fully-shared    `upstream` gets a room's folder only when every
--                        pair listed as sharing it (the repository's
--                        `rao.upstream-pair` lines, "<address> <port>")
--                        is on the room's member list: nobody who can fetch
--                        the upstream is outside the room.  (The issue's
--                        wording, "every pair on its member list is listed
--                        as sharing", would give a child room to a top-room
--                        member who shares the upstream: referee 5's
--                        broken version `members-listed`.)
--   repository-per-room  each room's folder goes only to its own remote
--                        `room-<fingerprint>`; `upstream`, if any, gets
--                        the code branch and the running log.
--
-- Pulled code is never run or switched to: other homes' `code/<name>`
-- branches arrive as remote-tracking refs (`refs/remotes/<remote>/code/
-- <name>`), readable and downloadable, and only `rooms` is ever merged.
--
-- For referees only (180): `M.broken` = "start-only" (172's caller shares
-- only at start-up; read by the gatherer), "auto-resolve" (a conflict
-- resolved to the remote's side), "merge-all" (every fetched branch
-- merged), "members-listed" (the issue's wording of only-fully-shared),
-- "branch-per-room" (repository-per-room as one branch per room on
-- `upstream`) or "blocking" (fetch and push run in the caller's thread,
-- no deadline).

local disk = require("003-disk")
local rooms = require("002-room-folders")
local recipients = require("041-recipients")
local git = require("172-git")
local runlog = require("177-running-log")

local M = {}

M.broken = os.getenv("RAO_SHARE_BROKEN")
if M.broken == "" then M.broken = nil end

local q = disk.shell_quote
local EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
local MODES = { ["only-fully-shared"] = true, ["repository-per-room"] = true }

-- {{{ function M.settings
-- home → {mode, push_log (bool), deadline (seconds)}, read strictly.
-- Read only when the mailbox has a remote, so a home that shares nothing
-- needs none of these lines.
function M.settings(home)
    local mode = rooms.config_value(home, "git.upstream-rooms")
    if not MODES[mode] then
        error("git.upstream-rooms must be only-fully-shared or repository-per-room, got '" .. mode .. "'", 0)
    end
    local push = rooms.config_value(home, "git.push-running-log")
    if push ~= "yes" and push ~= "no" then error("git.push-running-log must be yes or no, got '" .. push .. "'", 0) end
    local deadline = rooms.config_value(home, "git.share-deadline")
    if not deadline:match("^%d+$") or tonumber(deadline) < 1 then
        error("git.share-deadline must be a whole number of seconds ≥ 1, got '" .. deadline .. "'", 0)
    end
    return { mode = mode, push_log = push == "yes", deadline = tonumber(deadline) }
end
-- }}}

-- {{{ function M.remotes
-- repo → list of remote names this module uses ("upstream", "room-<64 hex>").
function M.remotes(repo)
    local ok, out = git.run(repo, { "remote" })
    local list = {}
    if not ok then return list end
    for name in out:gmatch("[^\n]+") do
        if name == "upstream" or name:match("^room%-" .. string.rep("%x", 64) .. "$") then list[#list + 1] = name end
    end
    table.sort(list)
    return list
end
-- }}}

-- {{{ function M.sharers
-- repo → the pairs listed as sharing `upstream` ({"<address> <port>"}).
function M.sharers(repo)
    local _, out = git.run(repo, { "config", "--get-all", "rao.upstream-pair" })
    local list = {}
    for line in (out or ""):gmatch("[^\n]+") do
        local address, port = line:match("^%s*(%S+)%s+(%d+)%s*$")
        if address then list[#list + 1] = address .. " " .. tonumber(port) end
    end
    return list
end
-- }}}

-- {{{ local function member_set
local function member_set(home, tag)
    local set = {}
    for _, m in ipairs(recipients.members(home, tag)) do set[m.address .. " " .. m.port] = true end
    return set
end
-- }}}

-- {{{ function M.plan
-- s (a sharing value) → { [remote] = {folders = {fingerprint → true},
-- code = bool, log = bool} } for the remotes in use.
function M.plan(s)
    local plan = {}
    local remotes = M.remotes(s.repo)
    local fingerprint_of = {}
    for _, tag in ipairs(s.tags) do
        fingerprint_of[tag] = rooms.token_fingerprint(rooms.read_entry(s.home, tag).token)
    end
    for _, remote in ipairs(remotes) do
        plan[remote] = { folders = {}, code = true, log = remote == "upstream" and s.settings.push_log }
    end
    if s.settings.mode == "only-fully-shared" then
        if plan.upstream then
            local sharers = M.sharers(s.repo)
            for _, tag in ipairs(s.tags) do
                local members = member_set(s.home, tag)
                local ok = true
                if M.broken == "members-listed" then
                    local listed = {}
                    for _, pair in ipairs(sharers) do listed[pair] = true end
                    for pair in pairs(members) do if not listed[pair] then ok = false end end
                else
                    for _, pair in ipairs(sharers) do if not members[pair] then ok = false end end
                end
                if ok then plan.upstream.folders[fingerprint_of[tag]] = true end
            end
        end
        for remote in pairs(plan) do if remote ~= "upstream" then plan[remote] = nil end end
    else
        for _, tag in ipairs(s.tags) do
            local fp = fingerprint_of[tag]
            if M.broken == "branch-per-room" and plan.upstream then
                plan.upstream.branches = plan.upstream.branches or {}
                plan.upstream.branches[fp] = true
            elseif plan["room-" .. fp] then
                plan["room-" .. fp].folders[fp] = true
            end
        end
    end
    return plan
end
-- }}}

-- {{{ local function background
-- Runs a git command with a deadline (killed when it passes), waiting
-- through s.wait so the caller's other threads go on.  → ok, output.
local counter = 0
local function background(s, args)
    if M.broken == "blocking" then
        return git.run(s.repo, args)
    end
    counter = counter + 1
    local dir = s.repo .. "/.git/rao-share-" .. counter
    os.execute("rm -rf " .. q(dir) .. " && mkdir -p " .. q(dir))
    os.execute("( timeout -s KILL " .. s.settings.deadline .. " env " .. git.command(s.repo, args) .. " >"
        .. q(dir .. "/out") .. " 2>&1 </dev/null; echo $? >" .. q(dir .. "/status.tmp") .. "; mv " .. q(dir .. "/status.tmp")
        .. " " .. q(dir .. "/status") .. " ) >/dev/null 2>&1 &")
    local status_path = dir .. "/status"
    s.wait(function() return disk.is_file(status_path) end, s.now() + s.settings.deadline + 5)
    local status = disk.is_file(status_path) and tonumber((disk.read_all(status_path):match("%d+"))) or -1
    local out = disk.is_file(dir .. "/out") and disk.read_all(dir .. "/out") or ""
    os.execute("rm -rf " .. q(dir))
    if status == 137 or status == 124 then out = "no answer within git.share-deadline (" .. s.settings.deadline .. " s)" end
    return status == 0, out:gsub("\n$", "")
end
-- }}}

-- {{{ local function merge
-- s, remote → "merged" | "nothing" | "conflict", and the conflicting paths.
local function merge(s, remote)
    local theirs = git.ref(s.repo, "refs/remotes/" .. remote .. "/" .. git.ROOMS_BRANCH)
    local targets = {}
    if theirs then targets[1] = theirs end
    if M.broken == "merge-all" then
        local _, refs = git.run(s.repo, { "for-each-ref", "--format=%(refname)", "refs/remotes/" .. remote .. "/" })
        for ref in refs:gmatch("[^\n]+") do
            if not ref:match("/HEAD$") and ref ~= "refs/remotes/" .. remote .. "/" .. git.ROOMS_BRANCH then
                targets[#targets + 1] = ref
            end
        end
    end
    if #targets == 0 then return "nothing" end
    local result = "nothing"
    for _, target in ipairs(targets) do
        local before = git.ref(s.repo, "HEAD")
        local args = git.identity(s.name)
        for _, w in ipairs({ "merge", "-q", "--no-edit", "--allow-unrelated-histories" }) do args[#args + 1] = w end
        if M.broken == "auto-resolve" then args[#args + 1] = "-X"; args[#args + 1] = "theirs" end
        args[#args + 1] = "-m"
        args[#args + 1] = "merge " .. remote .. "'s copies"
        args[#args + 1] = target
        local ok, out = git.run(s.repo, args)
        if not ok then
            local _, unmerged = git.run(s.repo, { "diff", "--name-only", "--diff-filter=U" })
            git.run(s.repo, { "merge", "--abort" })
            local paths = {}
            for path in (unmerged or ""):gmatch("[^\n]+") do paths[#paths + 1] = path end
            if #paths == 0 then error("merging " .. remote .. " failed: " .. out:sub(1, 200), 0) end
            return "conflict", paths
        end
        if git.ref(s.repo, "HEAD") ~= before then result = "merged" end
    end
    return result
end
-- }}}

-- {{{ local function shared_commit
-- s, remote, folders → the commit to push as the remote's `rooms`, or nil
-- when there is nothing to change there.  Its tree: the remote's, with
-- each shared folder replaced by this home's; its one parent: the
-- remote's tip.
local function shared_commit(s, remote, folders, branch_folder)
    local base = git.ref(s.repo, "refs/remotes/" .. remote .. "/" .. git.ROOMS_BRANCH)
    if branch_folder then base = nil end
    local mine = git.ref(s.repo, "HEAD")
    local index = s.repo .. "/.git/rao-index-share"
    os.remove(index)
    local env = "GIT_INDEX_FILE=" .. q(index)
    git.must(s.repo, base and { "read-tree", base } or { "read-tree", "--empty" }, { env = env })
    local list = {}
    for fp in pairs(folders) do list[#list + 1] = fp end
    table.sort(list)
    for _, fp in ipairs(list) do
        local path = "rooms/" .. fp
        git.must(s.repo, { "rm", "-r", "-q", "-f", "--cached", "--ignore-unmatch", "--", path }, { env = env })
        local found, sub = false, nil
        if mine then found, sub = git.run(s.repo, { "rev-parse", "-q", "--verify", mine .. ":" .. path }) end
        if found and sub:match("^%x+$") then
            git.must(s.repo, { "read-tree", "--prefix=" .. path .. "/", sub }, { env = env })
        end
    end
    local tree = git.must(s.repo, { "write-tree" }, { env = env })
    os.remove(index)
    if base and git.must(s.repo, { "rev-parse", base .. "^{tree}" }) == tree then return nil end
    if not base and (#list == 0 or tree == EMPTY_TREE) then return nil end
    local args = git.identity(s.name)
    for _, w in ipairs({ "commit-tree", tree, "-m", "shared copies from " .. s.name }) do args[#args + 1] = w end
    if base then args[#args + 1] = "-p"; args[#args + 1] = base end
    return git.must(s.repo, args)
end
-- }}}

-- {{{ function M.new
-- {home, repo, tags (this mailbox's rooms), name (home name), settings
-- (M.settings), wait (function(condition, until)), now, commit (function:
-- commit the working tree), log (function(words)), problem (function(name,
-- words)), clear (function(name))} → a sharing value.
function M.new(s)
    s.pulls, s.pushes, s.conflicts = 0, 0, {}
    return s
end
-- }}}

-- {{{ function M.moment
-- s, why ("start" | "recheck" | "stop") → a list of report lines.  One
-- remote's failure never stops another's.
function M.moment(s, why)
    local report = {}
    local plan = M.plan(s)
    local names = {}
    for remote in pairs(plan) do names[#names + 1] = remote end
    table.sort(names)
    for _, remote in ipairs(names) do
        local p = plan[remote]
        local words = {}
        local fetched, out = background(s, { "fetch", "-q", "--prune", remote })
        s.pulls = s.pulls + 1
        local conflict = false
        if not fetched then
            words[#words + 1] = "pull failed: " .. out:match("^[^\n]*")
            if s.problem then s.problem("share-" .. remote, "pull failed (" .. why .. "): " .. out:match("^[^\n]*")) end
        else
            -- whatever the hooks wrote while fetching, committed first, so
            -- the merge meets a clean tree
            if s.commit then s.commit() end
            local result, paths = merge(s, remote)
            words[#words + 1] = "pulled (" .. result .. ")"
            if result == "conflict" then
                conflict = true
                s.conflicts[remote] = paths
                if s.problem then
                    s.problem("share-conflict-" .. remote:sub(1, 12), "two different edits, left unmerged (retried at the "
                        .. "next moment): " .. table.concat(paths, ", "))
                end
            else
                s.conflicts[remote] = nil
            end
        end
        -- push: the shared rooms (not while a conflict stands, nor when the
        -- pull failed: the remote's tip is not known), the code, the log
        local refspecs = {}
        local shared
        if fetched and not conflict then
            shared = shared_commit(s, remote, p.folders)
            if shared then refspecs[#refspecs + 1] = shared .. ":refs/heads/" .. git.ROOMS_BRANCH end
            for fp in pairs(p.branches or {}) do
                local c = shared_commit(s, remote, { [fp] = true }, true)
                if c then refspecs[#refspecs + 1] = "+" .. c .. ":refs/heads/room/" .. fp end
            end
        end
        if p.code and git.ref(s.repo, "refs/heads/code/" .. s.name) then
            refspecs[#refspecs + 1] = "refs/heads/code/" .. s.name .. ":refs/heads/code/" .. s.name
        end
        if p.log and git.ref(s.repo, "refs/heads/" .. runlog.branch(s.name)) then
            refspecs[#refspecs + 1] = "refs/heads/" .. runlog.branch(s.name) .. ":refs/heads/" .. runlog.branch(s.name)
        end
        if #refspecs > 0 then
            local args = { "push", "-q", "--porcelain", remote }
            for _, r in ipairs(refspecs) do args[#args + 1] = r end
            local pushed, pout = background(s, args)
            s.pushes = s.pushes + 1
            if pushed then
                words[#words + 1] = "pushed " .. #refspecs .. " ref(s)"
                if shared then
                    -- what was pushed is recorded as merged here, keeping this
                    -- tree as it is, so the next pull's merge starts from it
                    -- (otherwise this home's own pushed copies would meet its
                    -- later edits as a conflict)
                    local args2 = git.identity(s.name)
                    for _, w in ipairs({ "merge", "-q", "-s", "ours", "--no-edit", "--allow-unrelated-histories", "-m",
                        "pushed to " .. remote, shared }) do args2[#args2 + 1] = w end
                    git.must(s.repo, args2)
                end
                if s.clear then s.clear("share-" .. remote) end
            else
                words[#words + 1] = "push failed: " .. (pout:match("![^\n]*") or pout:match("^[^\n]*"))
                if s.problem then
                    s.problem("share-" .. remote, "push failed (" .. why .. "): " .. (pout:match("![^\n]*") or pout:match("^[^\n]*")))
                end
            end
        end
        report[#report + 1] = "share " .. why .. ": " .. remote .. ": " .. table.concat(words, "; ")
        if s.log then s.log(report[#report]) end
    end
    return report
end
-- }}}

return M
