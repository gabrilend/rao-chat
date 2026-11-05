-- 172-git.lua — running git for a mailbox's repository (issue 215): find
-- the program, make the repository, run a command, and commit a folder to
-- a branch without touching the checked-out tree.
--
-- Every command runs with the machine's and the person's own git settings
-- left out (GIT_CONFIG_NOSYSTEM, GIT_CONFIG_GLOBAL=/dev/null) and hooks
-- turned off (core.hooksPath=/dev/null), so a global `commit.gpgsign`, a
-- template's hooks or a pager cannot change what the gatherer does, and
-- nothing in a repository runs a program.  No command ever asks for a
-- password (GIT_TERMINAL_PROMPT=0, GIT_ASKPASS=/bin/false): a remote that
-- wants one fails and says so (215b).
--
-- Names that become git refs (the home's name, for `code/<home name>`
-- and the commit author) are checked by `check_name` before use.

local disk = require("003-disk")

local M = {}

local q = disk.shell_quote

M.ENV = "GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/false "
    .. "SSH_ASKPASS=/bin/false LC_ALL=C"

-- The branch the text copies are on (the checked-out one).
M.ROOMS_BRANCH = "rooms"

-- {{{ function M.find
-- → the path of the git program, or nil and the words to say.
function M.find()
    local p = io.popen("command -v git 2>/dev/null")
    local path = p:read("*l")
    p:close()
    if not path or path == "" then
        return nil, "git is required (each mailbox keeps its text copies in a git repository, issue 215) and "
            .. "the program 'git' is not on the PATH"
    end
    return path
end
-- }}}

-- {{{ function M.check_name
-- A home name, as git.home-name gives it: letters, digits, '.', '_' and
-- '-', starting with a letter or digit, at most 64, no "..", not ending
-- in ".lock" (git's own ref rules, narrowed).
function M.check_name(name)
    if type(name) ~= "string" or not name:match("^[%w][%w%._%-]*$") or #name > 64
        or name:find("..", 1, true) or name:match("%.lock$") then
        error("git.home-name must be letters, digits, '.', '_' or '-' (at most 64, starting with a letter "
            .. "or digit, no '..', not ending in .lock), got '" .. tostring(name) .. "'", 0)
    end
    return name
end
-- }}}

-- {{{ function M.identity
-- home name → the -c words that make it the author and committer.
function M.identity(name)
    return { "-c", "user.name=" .. name, "-c", "user.email=" .. name .. "@rao-chat.invalid" }
end
-- }}}

-- {{{ function M.command
-- repo (folder, or nil), args (list of words), env (words, optional) →
-- the shell command text.
function M.command(repo, args, env)
    local words = { M.ENV, env or "", "git" }
    if repo then words[#words + 1] = "-C " .. q(repo) end
    words[#words + 1] = "-c core.hooksPath=/dev/null -c core.pager=cat -c commit.gpgsign=false"
    for _, a in ipairs(args) do words[#words + 1] = q(a) end
    return table.concat(words, " ")
end
-- }}}

-- {{{ function M.run
-- repo, args, opts {env, input} → ok (exit status 0), output (stdout and
-- stderr together, final line break removed), status.
function M.run(repo, args, opts)
    opts = opts or {}
    local command = M.command(repo, args, opts.env)
    local input_path
    if opts.input then
        input_path = os.tmpname()
        disk.write_atomic(input_path, opts.input)
        command = command .. " <" .. q(input_path)
    else
        command = command .. " </dev/null"
    end
    local p = io.popen(command .. " 2>&1; echo \"\nexit-status $?\"")
    local output = p:read("*a")
    p:close()
    if input_path then os.remove(input_path) end
    local status = tonumber(output:match("\nexit%-status (%d+)\n?$")) or -1
    output = output:gsub("\n?\nexit%-status %d+\n?$", "")
    return status == 0, output, status
end
-- }}}

-- {{{ function M.must
-- As run, but a failure is an error naming the command and what git said.
function M.must(repo, args, opts)
    local ok, output, status = M.run(repo, args, opts)
    if not ok then
        error("git " .. table.concat(args, " ") .. " failed (" .. status .. "): " .. output:sub(1, 300), 0)
    end
    return output
end
-- }}}

-- {{{ function M.ensure
-- repo folder → true when it was made now.  Makes the repository with the
-- rooms' branch checked out (no commit yet) and `labels` left out of it
-- (.git/info/exclude: a per-home file, never tracked, never pushed).
-- Opening it again changes nothing.
function M.ensure(repo)
    if disk.is_dir(repo .. "/.git") then return false end
    os.execute("mkdir -p " .. q(repo .. "/rooms"))
    M.must(nil, { "init", "-q", "-b", M.ROOMS_BRANCH, repo })
    disk.write_atomic(repo .. "/.git/info/exclude",
        "# rao-chat: per-home files, never tracked (issue 215)\n/labels\n")
    return true
end
-- }}}

-- {{{ function M.ref
-- repo, ref name → the commit it points at, or nil.
function M.ref(repo, name)
    local ok, output = M.run(repo, { "rev-parse", "-q", "--verify", name .. "^{commit}" })
    if ok and output:match("^%x+$") then return output end
    return nil
end
-- }}}

-- {{{ function M.commit_tree
-- repo, branch, tree (hash), message, name (home name) → the new commit,
-- or nil when the branch's tip already has that tree.  The branch moves
-- only from the tip read here (update-ref's old value), so two writers
-- cannot lose each other's commit.
function M.commit_tree(repo, branch, tree, message, name)
    local parent = M.ref(repo, "refs/heads/" .. branch)
    if parent and M.must(repo, { "rev-parse", parent .. "^{tree}" }) == tree then return nil end
    local args = M.identity(name)
    for _, w in ipairs({ "commit-tree", tree, "-m", message }) do args[#args + 1] = w end
    if parent then args[#args + 1] = "-p"; args[#args + 1] = parent end
    local commit = M.must(repo, args)
    M.must(repo, { "update-ref", "refs/heads/" .. branch, commit, parent or string.rep("0", 40) })
    return commit
end
-- }}}

-- {{{ function M.commit_folder
-- repo, branch, folder, message, name → the new commit, or nil when the
-- folder is as the branch already holds it.  Uses an index of its own
-- (never the repository's), so the checked-out tree and its index are
-- untouched; the folder's own .gitignore applies, and git never takes
-- a path named .git.
function M.commit_folder(repo, branch, folder, message, name)
    local index = repo .. "/.git/rao-index-" .. branch:gsub("[^%w]", "-")
    os.remove(index)
    local env = "GIT_INDEX_FILE=" .. q(index)
    M.must(nil, { "--git-dir=" .. repo .. "/.git", "--work-tree=" .. folder, "add", "-A", "." }, { env = env })
    local tree = M.must(nil, { "--git-dir=" .. repo .. "/.git", "write-tree" }, { env = env })
    os.remove(index)
    return M.commit_tree(repo, branch, tree, message, name)
end
-- }}}

return M
