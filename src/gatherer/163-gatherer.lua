-- 163-gatherer.lua — the mailbox gatherer: one process per mailbox,
-- working in its RAM folder (issue 211).
--
--   luajit src/gatherer/163-gatherer.lua <project> <disk home> <mailbox tag>
--
-- (normally started by the home starter, 164).  In order it:
--
--   1. claims the mailbox's port, before anything slow (R9).  When the
--      port cannot be claimed it writes the problem, naming the port and
--      its `mailboxes` line, to `state` and the running log, makes no
--      connection, and exits with status 1 (open question 5: only this
--      gatherer stops);
--   2. makes its RAM folder (161), puts back what a previous process left
--      in `working/`, and loads the mailbox's rooms from disk into `home/`;
--   3. runs its stages as threads of one wait loop (162; open question 2):
--        listener   accepts, holds at most gatherer.connection-limit
--                   connections (a new one closes the one held longest),
--                   gives each one gatherer.frame-deadline seconds per
--                   frame, writes each frame to arrived/, and sends the
--                   answer the filer leaves in answers/ on the same
--                   connection;
--        filer      takes arrived/ files and opens and files each through
--                   133's answer_frame on the RAM home: the only writer to
--                   home/.  With gatherer.acknowledge-after = disk the
--                   room's log is forced to disk before the answer is
--                   written; with ram it is not.  A frame whose filing
--                   throws ends that frame only (R5);
--        typed      takes typed/ files (the viewer's) and writes them with
--                   202's stage;
--        sender     202's stage `pass`, never inside the listener (R4),
--                   each due item in a thread of its own; after each pass
--                   and each attempt due/ holds one file per (pair, room)
--                   with something missing;
--        sync       every gatherer.sync-interval seconds: RAM → disk for
--                   this mailbox's rooms, disk → RAM for the home-wide
--                   files (161);
--        state      every second: `state` rewritten (pid, started, last
--                   sync, piles, connections, problems); a `stop` file in
--                   the folder makes the gatherer sync once more and exit.
--
-- Text copies (issue 215, 173).  git is required: without it the
-- gatherer writes the problem to `state` and stderr, naming the program,
-- and exits with status 1.  The mailbox's repository is made at start-up
-- when it is not there.  The filing hook runs after every record filed
-- into a room of the mailbox (the filer, once the frame is answered) or
-- written there (typed): it writes that record's text copy.  A hook that
-- fails is a problem line and ends nothing; each sync cycle brings every
-- room's copies up to date from its log and makes one commit.  Then the
-- running log's new lines go to the branch running-log/<home name> (215a,
-- 177), split under git.log-file-size; they leave RAM only once committed.
--
-- Problems that belong to no room are kept one line per distinct problem
-- in `state` (`problem.<name>`), rewritten in place, and written to the
-- running log at most once per sync interval each, with a count (R16).
--
-- For referees only (167): RAO_GATHERER_CRASH=<point>:<n> ends the
-- process at the n-th frame's `before-answer` (filed, not yet answered)
-- or `after-answer` (answer sent) point, as a crash would;
-- RAO_GATHERER_BROKEN=answer-first (the filer answers, then files),
-- disk-answers-first (disk mode without the forced write), no-limit (no
-- connection limit) or single-loop (the sender inside the listener's
-- loop), retry-at-once (a frame whose filing throws is tried again at
-- once), other-port (another port when the mailbox's is held),
-- fixed-folder (one RAM folder for every home, in 161) and skip-entry (a
-- sync that misses `entry`, in 161) are the broken versions the referees
-- must catch.  For 215's referees (175): RAO_COPIES_FAIL=hook:<n> makes
-- the n-th run of the filing hook throw (hook:all, every run); RAO_COPIES_BROKEN=receive-only
-- (no hook for own messages), hook-unguarded (the hook inside filing,
-- unguarded), edits-to-corrections (hand edits of copies sent as
-- corrections) and no-git (running on without git, and without copies)
-- are the broken versions.

local DIR, HOME_DIR, MAILBOX = arg[1], arg[2], arg[3]
if not (DIR and HOME_DIR and MAILBOX) then
    io.stderr:write("usage: luajit 163-gatherer.lua <project> <disk home> <mailbox tag>\n")
    os.exit(2)
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local ffi = require("ffi")
local socket = require("socket")
local rooms = require("002-room-folders")
local disk = require("003-disk")
local frames = require("125-frames")
local records = require("126-inner-records")
local keyring = require("127-keyring")
local seal = require("124-seal")
local recipients = require("041-recipients")
local delivered = require("130-delivered")
local receive = require("133-receive")
local delivery = require("134-delivery")
local fd = require("139-failed-decryption")
local leaving = require("147-leaving")
local reach = require("149-reach")
local members = require("152-members")
local crosscheck = require("156-cross-check")
local ram = require("161-ram-folders")
local wait = require("162-wait-loop")
local git = require("172-git")
local copies_m = require("173-text-copies")
local runlog = require("177-running-log")

ffi.cdef [[ int getpid(void); ]]

local BROKEN = os.getenv("RAO_GATHERER_BROKEN") or ""
local COPIES_BROKEN = os.getenv("RAO_COPIES_BROKEN") or ""
local HOOK_FAIL = (os.getenv("RAO_COPIES_FAIL") or ""):match("^hook:(%w+)$")
local CRASH_POINT, CRASH_AT = (os.getenv("RAO_GATHERER_CRASH") or ""):match("^([%w%-]+):(%d+)$")
CRASH_AT = tonumber(CRASH_AT)

local now = wait.now
local disk_home = rooms.open_home(HOME_DIR)
local function setting(key) return rooms.config_value(disk_home, key) end
-- {{{ local function whole
local function whole(key, least)
    local text = setting(key)
    if not text:match("^%d+$") or tonumber(text) < least then
        error(key .. " must be a whole number ≥ " .. least .. ", got '" .. text .. "'", 0)
    end
    return tonumber(text)
end
-- }}}

------------------------------------------------------------------------------
-- 1. The port, first
------------------------------------------------------------------------------

local mailbox = rooms.read_mailbox(disk_home, MAILBOX)
local ADDRESS = setting("gatherer.address")
-- an IPv4 or IPv6 socket made now (socket.tcp() makes its descriptor
-- only at bind, too late for reuseaddr: a port left with connections
-- closing by a crashed gatherer could not be claimed again)
local server = ADDRESS:find(":", 1, true) and socket.tcp6() or socket.tcp4()
server:setoption("reuseaddr", true)
local claimed, claim_problem = server:bind(ADDRESS == "any" and "*" or ADDRESS, mailbox.port)
if claimed then claimed, claim_problem = server:listen(128) end

local root, root_note = ram.choose_root(setting("gatherer.ram-root"))
local HOME_RAM = ram.home_ram(root, HOME_DIR)
local FOLDER = ram.layout(HOME_RAM, MAILBOX)
local PID = ffi.C.getpid()
local STARTED = math.floor(now())
local state = { pid = PID, started = STARTED, mailbox = MAILBOX, port = mailbox.port, address = ADDRESS }
local problems = {}       -- name → {words, count, logged_at}

-- {{{ local function problem
-- One line per distinct problem: kept in state, logged at most once per
-- `every` seconds with how many times it happened.
local function problem(name, words, every)
    local p = problems[name]
    if not p or p.words ~= words then
        p = { words = words, count = 0, logged_at = -math.huge }
        problems[name] = p
    end
    p.count = p.count + 1
    if now() - p.logged_at >= (every or 0) then
        ram.log(FOLDER, now(), "problem " .. name .. ": " .. words .. (p.count > 1 and (" (" .. p.count .. " times)") or ""))
        p.logged_at = now()
    end
end
-- }}}

-- {{{ local function write_state
local function write_state()
    local values = {}
    for k, v in pairs(state) do values[k] = v end
    for name, p in pairs(problems) do values["problem." .. name] = p.words .. " (" .. p.count .. " times)" end
    for _, queue in ipairs(ram.QUEUES) do values["pile." .. queue] = ram.pile(FOLDER .. "/" .. queue) end
    ram.write_state(FOLDER, values)
end
-- }}}

if not claimed and BROKEN == "other-port" then
    -- referee 7's broken version: another port, quietly
    claimed, claim_problem = server:bind(ADDRESS == "any" and "*" or ADDRESS, mailbox.port + 1000)
    if claimed then claimed, claim_problem = server:listen(128) end
end
if not claimed then
    -- name the port and the mailboxes line that gives it, and stop: no
    -- other port is chosen, and nothing was sent
    local line_number, line_text = "?", ""
    local n = 0
    for line in (disk.read_all(HOME_DIR .. "/mailboxes") or ""):gmatch("[^\n]*") do
        n = n + 1
        if line:find(MAILBOX, 1, true) then line_number, line_text = n, line; break end
    end
    problem("port", string.format("port %d cannot be claimed (%s): mailboxes line %s: %s", mailbox.port,
        tostring(claim_problem), tostring(line_number), line_text))
    state.stopped = "port"
    write_state()
    io.stderr:write("rao-chat gatherer: port " .. mailbox.port .. " cannot be claimed: " .. tostring(claim_problem) .. "\n")
    os.exit(1)
end
server:settimeout(0)
ram.log(FOLDER, now(), string.format("started: pid %d, mailbox %s, port %d on %s", PID, MAILBOX, mailbox.port, ADDRESS))

-- git, required (215): refuse to start rather than run without copies
local git_path, no_git = git.find()
if not git_path and COPIES_BROKEN ~= "no-git" then
    problem("git", no_git)
    state.stopped = "git"
    write_state()
    io.stderr:write("rao-chat gatherer: " .. no_git .. "\n")
    server:close()
    os.exit(1)
end
local HOME_NAME = git.check_name(setting("git.home-name"))
local LOG_LIMIT = runlog.settings(disk_home)
if root_note then problem("ram-root", root_note) end

------------------------------------------------------------------------------
-- 2. The RAM folder and the mailbox, loaded
------------------------------------------------------------------------------

local ACK_AFTER = setting("gatherer.acknowledge-after")
if ACK_AFTER ~= "disk" and ACK_AFTER ~= "ram" then
    error("gatherer.acknowledge-after must be disk or ram, got '" .. ACK_AFTER .. "'", 0)
end
local SYNC_EVERY = whole("gatherer.sync-interval", 1)
local LIMIT = whole("gatherer.connection-limit", 1)
local DEADLINE = whole("gatherer.frame-deadline", 1)

local returned = ram.return_working(FOLDER .. "/arrived") + ram.return_working(FOLDER .. "/typed")
os.execute("rm -f " .. disk.shell_quote(FOLDER .. "/answers") .. "/* " .. disk.shell_quote(FOLDER .. "/answers/working") .. "/* 2>/dev/null")
local sync_record, kept = ram.load(HOME_DIR, FOLDER .. "/home", rooms.list_rooms_by_mailbox(disk_home, MAILBOX))
local home = rooms.open_home(FOLDER .. "/home")
local copies = git_path and copies_m.open(home, HOME_DIR, MAILBOX, HOME_NAME)
if copies and copies.made then
    ram.log(FOLDER, now(), "made the mailbox's git repository at " .. copies.repo)
end
ram.log(FOLDER, now(), string.format("%s %d room(s); %d file(s) put back from working/; acknowledge after %s",
    kept and "kept the RAM copy (newer than disk) of" or "loaded from disk", #sync_record.rooms, returned, ACK_AFTER))
state["acknowledge-after"] = ACK_AFTER
state["last-sync"] = STARTED

local stage_seams = {
    connect = function(pair) return wait.connect(ADDRESS, pair) end,
    now = now,
}
if reach.read_fact(HOME_RAM) then
    -- the starter's 212 watcher has confirmed a public address: state pairs
    stage_seams.own_pairs = reach.seam(home, HOME_RAM)
end
local stage = delivery.new_stage(home, stage_seams)
local fd_log = fd.open(FOLDER, fd.settings(home))
local fd_seams = fd.seams(fd_log, mailbox.port, function() return math.floor(now()) end)

local loop = wait.new(function(name, message)
    problem("thread-" .. name:gsub("%s", "-"), message, SYNC_EVERY)
end)

------------------------------------------------------------------------------
-- 3. The stages
------------------------------------------------------------------------------

-- {{{ local function run_hooks
-- The filing hook (215): after a record is filed or written into room
-- `tag`, its text copy.  It never stops or undoes filing: a failure is a
-- problem line, and the next sync makes the copy from the log.
local hook_runs = 0
local function copy_hook(tag)
    hook_runs = hook_runs + 1
    if HOOK_FAIL == "all" or tonumber(HOOK_FAIL) == hook_runs then error("the filing hook failed on purpose (referee)", 0) end
    if copies then copies:catch_up(tag) end
end
local function run_hooks(tag)
    local ok, why = pcall(copy_hook, tag)
    if not ok then problem("hook-text-copy", "room " .. tostring(tag):sub(1, 8) .. ": " .. tostring(why), SYNC_EVERY) end
end
-- }}}

local held = {}            -- the connections held, oldest first
local arrived_pending = returned > 0
local answered_frames, filed_frames = 0, 0

-- {{{ local function crash_if
local function crash_if(point, count)
    if CRASH_POINT == point and CRASH_AT == count then
        ram.log(FOLDER, now(), "crashing on purpose at " .. point .. " " .. count .. " (referee)")
        os.exit(3)
    end
end
-- }}}

-- {{{ local function drop
local function drop(conn)
    for i, c in ipairs(held) do if c == conn then table.remove(held, i) break end end
    conn:close()
end
-- }}}

-- {{{ local function serve_connection
-- One held connection: frames to arrived/, answers back on it.
local function serve_connection(conn)
    while not conn.closed do
        conn.deadline = now() + DEADLINE
        local after, _, refused_length = frames.read_frame(conn)
        if not after then
            if refused_length then fd_seams.on_refused_length(conn.peer, refused_length) end
            drop(conn)
            return
        end
        local name = ram.new_name(now())
        ram.put(FOLDER .. "/arrived", name, ram.encode_arrived(MAILBOX, conn.peer.host, conn.peer.port,
            math.floor(now()), after))
        arrived_pending = true
        local answer_path = FOLDER .. "/answers/" .. name
        local give_up = now() + 60
        wait.block(function() return disk.is_file(answer_path) end, give_up)
        if not disk.is_file(answer_path) then drop(conn) return end
        local answer = disk.read_all(answer_path)
        os.remove(answer_path)
        if answer == "" then drop(conn) return end      -- no key opened it
        local ok = frames.write_frame(conn, answer)
        if not ok then drop(conn) return end
        answered_frames = answered_frames + 1
        crash_if("after-answer", answered_frames)
    end
end
-- }}}

loop:spawn("listener", function()
    while true do
        if BROKEN == "single-loop" then
            -- referee 4's broken version: each pass's attempts, one after
            -- another, inside the loop that accepts
            stage:pass(now())
            wait.block(nil, now() + 0.05, server, "read")
        else
            wait.block(nil, math.huge, server, "read")
        end
        while true do
            local client = server:accept()
            if not client then break end
            local host, port = client:getpeername()
            local conn = wait.wrap(client)
            conn.peer = { host = host, port = tonumber(port) }
            if #held >= LIMIT and BROKEN ~= "no-limit" then
                -- R2: at the limit, the connection held longest makes room
                local oldest = table.remove(held, 1)
                oldest:close()
                problem("connection-limit", "at the limit of " .. LIMIT .. " connections; the oldest was closed", SYNC_EVERY)
            end
            held[#held + 1] = conn
            loop:spawn("connection " .. host .. ":" .. port, function() serve_connection(conn) end)
        end
    end
end)

-- {{{ local function room_log_relative
local function room_log_relative(tag)
    return rooms.log_path(home, tag):sub(#home.dir + 2)
end
-- }}}

-- {{{ local function file_seams
local function file_seams(item)
    local peer = { host = item.host, port = item.port }
    local s = {
        home = home, peer = peer,
        ring = function() return keyring.for_mailbox(rooms, home, MAILBOX) end,
        now = function() return item.at end,
        on_unopened = fd_seams.on_unopened,
        on_problem = function(tag, words)
            problem("room-" .. tostring(tag):sub(1, 8), words, SYNC_EVERY)
            if BROKEN == "retry-at-once" then error(words, 0) end
        end,
        on_opened = function(tag) stage:heard_at(tag, peer.host, now()) end,
        on_claim = function(tag, record) return leaving.on_claim(stage, tag, record, peer, math.floor(now())) end,
        on_members = function(tag, record) return members.answer(stage, tag, record, peer, math.floor(now())) end,
        on_summary = function(tag, record) return crosscheck.answer(stage, tag, record, peer, math.floor(now())) end,
        on_filed = function(tag)
            filed_frames = filed_frames + 1
            item.filed_tags = item.filed_tags or {}
            item.filed_tags[#item.filed_tags + 1] = tag
            if COPIES_BROKEN == "hook-unguarded" then copy_hook(tag) end
            if ACK_AFTER == "disk" and BROKEN ~= "disk-answers-first" then
                -- the room's log on disk, forced, before the answer exists
                ram.sync_file(sync_record, room_log_relative(tag), true)
            end
            crash_if("before-answer", filed_frames)
        end,
    }
    return s
end
-- }}}

-- {{{ local function answer_first
-- The broken filer of referee 1: answers "filed" from the opened record,
-- removes the frame, waits for the answer to go, and only then files.
local function answer_first(item, name, taken)
    local tag, opened = keyring.open_frame(keyring.for_mailbox(rooms, home, MAILBOX), item.after)
    if not tag then return false end
    local record = records.decode(opened)
    if not record.id then return false end
    local ack = records.encode({ kind = "ack", answers = record.id .. " filed" })
    local pair
    for _, entry in ipairs(keyring.for_mailbox(rooms, home, MAILBOX).entries) do
        if entry.room == tag then pair = entry end
    end
    os.remove(taken)
    ram.put(FOLDER .. "/answers", name, seal.seal(pair, ack))
    wait.block(function() return not disk.is_file(FOLDER .. "/answers/" .. name) end, now() + 5)
    receive.answer_frame(item.after, file_seams(item))
    return true
end
-- }}}

loop:spawn("filer", function()
    while true do
        wait.block(function() return arrived_pending end, now() + 1)
        arrived_pending = false
        for _, name in ipairs(ram.waiting(FOLDER .. "/arrived")) do
            local bytes, taken = ram.take(FOLDER .. "/arrived", name)
            if bytes then
                local item, why = ram.decode_arrived(bytes)
                if not item then
                    problem("arrived-file", name .. ": " .. why, SYNC_EVERY)
                    os.remove(taken)
                elseif not (BROKEN == "answer-first" and answer_first(item, name, taken)) then
                    local ok, frame = pcall(receive.answer_frame, item.after, file_seams(item))
                    if not ok then
                        -- R5: this frame ends here; the sender will try it again
                        problem("filing", tostring(frame):match("^[^\n]*"), SYNC_EVERY)
                        frame = nil
                        if BROKEN == "retry-at-once" then
                            -- referee 5's broken version: no clock step, the
                            -- frame is tried again at once, forever
                            os.rename(taken, FOLDER .. "/arrived/" .. name)
                            arrived_pending = true
                            taken = nil
                        end
                    end
                    if taken then
                        ram.put(FOLDER .. "/answers", name, frame or "")
                        os.remove(taken)
                    end
                    if COPIES_BROKEN ~= "hook-unguarded" then
                        for _, tag in ipairs(item.filed_tags or {}) do run_hooks(tag) end
                    end
                end
            end
        end
    end
end)

loop:spawn("typed", function()
    while true do
        for _, name in ipairs(ram.waiting(FOLDER .. "/typed")) do
            local bytes, taken = ram.take(FOLDER .. "/typed", name)
            if bytes then
                local typed, why = ram.decode_typed(bytes)
                if typed then
                    local ok, failed = pcall(stage.write, stage, typed.room, { kind = "message", text = typed.text },
                        math.floor(now()))
                    if not ok then problem("typed", name .. ": " .. tostring(failed), SYNC_EVERY)
                    elseif COPIES_BROKEN ~= "receive-only" then run_hooks(typed.room) end
                else
                    problem("typed", name .. ": " .. why, SYNC_EVERY)
                end
                os.remove(taken)
            end
        end
        wait.sleep(0.2)
    end
end)

-- {{{ local function write_due
-- due/: one file per (pair, room) with something missing, rewritten only
-- when it changes; files for pairs no longer owed anything are removed.
local due_written = {}
local function write_due()
    local wanted = {}
    for _, tag in ipairs(rooms.list_rooms_by_mailbox(home, MAILBOX)) do
        for _, p in ipairs(recipients.send_list(home, tag)) do
            local missing = #delivered.missing_for(home, tag, p)
            if missing > 0 then
                local name = p.address .. "-" .. p.port .. "-" .. tag:sub(1, 8)
                local job = stage:job(tag, p)
                wanted[name] = string.format("room = %s\naddress = %s\nport = %d\nmissing = %d\nnext-try = %s\n",
                    tag, p.address, p.port, missing, job and job.timer and tostring(math.floor(job.timer.due or 0)) or "-")
            end
        end
    end
    for name, text in pairs(wanted) do
        if due_written[name] ~= text then ram.put(FOLDER .. "/due", name, text) end
    end
    for name in pairs(due_written) do
        if not wanted[name] then os.remove(FOLDER .. "/due/" .. name) end
    end
    due_written = wanted
end
-- }}}

-- {{{ local function runner
-- 134's pass hands each due item here: each runs in its own thread, one
-- at a time per item, so a dead pair delays no other pair (R4).
local function runner(item, fn)
    if item.running then return end
    item.running = true
    loop:spawn("attempt", function()
        local ok, failed = pcall(fn)
        item.running = false
        if not ok then problem("attempt", tostring(failed), SYNC_EVERY) end
        -- due/ follows each attempt, not only the next pass
        local written, why = pcall(write_due)
        if not written then problem("due", tostring(why), SYNC_EVERY) end
    end)
end
-- }}}

-- {{{ local function next_free_due
-- The earliest due time of an item not running now, or nil.
local function next_free_due()
    local earliest
    local function see(item, due)
        if due and not item.running and (not earliest or due < earliest) then earliest = due end
    end
    for _, job in pairs(stage.jobs) do see(job, job.timer.due) end
    for _, check in pairs(stage.checks) do see(check, not check.done and check.timer.due) end
    for _, job in pairs(stage.hellos) do see(job, not job.done and job.timer.due) end
    if stage.crosscheck then see(stage.crosscheck, stage.crosscheck.next) end
    return earliest
end
-- }}}

if BROKEN == "single-loop" then
    -- referee 4's broken version: the listener's own loop sends (below)
    loop:spawn("sender start", function() stage:start(now()) end)
else
    loop:spawn("sender", function()
        stage:start(now())
        while true do
            stage:pass(now(), runner)
            local ok, failed = pcall(write_due)
            if not ok then problem("due", tostring(failed), SYNC_EVERY) end
            local due = next_free_due() or (now() + 5)
            wait.block(function()
                local d = next_free_due()
                return d ~= nil and d <= now()
            end, math.min(due, now() + 5))
        end
    end)
end

-- {{{ local function sync_copies
-- Each sync cycle: every room's copies brought up to date and committed
-- (215).  The broken version of referee 4 first sends each hand-changed
-- copy as a correction.
local function sync_copies()
    local tags = rooms.list_rooms_by_mailbox(home, MAILBOX)
    if COPIES_BROKEN == "edits-to-corrections" then
        for _, item in ipairs(copies:changed_since_commit()) do
            local fp, id = item.path:match("^rooms/(%x+)/%d+%-([%w_%-]+)%.txt$")
            if fp and item.status == "M" then
                for _, tag in ipairs(tags) do
                    if copies:folder(tag) == fp then
                        local text = disk.read_all(copies.repo .. "/" .. item.path):match("\n\n(.*)$") or ""
                        pcall(stage.write, stage, tag, { kind = "correction", target = id, text = text }, math.floor(now()))
                    end
                end
            end
        end
    end
    return copies:sync(tags)
end
-- }}}

-- {{{ local function sync_now
local function sync_now()
    local result = ram.sync(sync_record)
    state["last-sync"] = math.floor(now())
    if result.written > 0 or #result.reloaded > 0 then
        ram.log(FOLDER, now(), string.format("sync: %d file(s) written to disk%s", result.written,
            #result.reloaded > 0 and ("; reloaded " .. table.concat(result.reloaded, ", ")) or ""))
    end
    if #result.hand_edits > 0 then
        problem("hand-edit", "changed on disk by hand, not written over: " .. table.concat(result.hand_edits, ", "), SYNC_EVERY)
    end
    if copies then
        local ok, counts = pcall(sync_copies)
        if not ok then problem("copies", tostring(counts), SYNC_EVERY)
        elseif counts then ram.log(FOLDER, now(), "git: " .. counts.message .. " (" .. counts.commit:sub(1, 12) .. ")") end
        -- the running log, to its own branch (215a); kept in RAM on failure
        local logged, why = pcall(runlog.take_and_commit, FOLDER, copies.repo, HOME_NAME, LOG_LIMIT)
        if not logged then
            problem("running-log-commit", "not committed, kept in RAM for the next cycle: " .. tostring(why), SYNC_EVERY)
        end
    end
end
-- }}}

loop:spawn("sync", function()
    while true do
        wait.sleep(SYNC_EVERY)
        local ok, failed = pcall(sync_now)
        if not ok then problem("sync", tostring(failed), SYNC_EVERY) end
    end
end)

local stopping = false
loop:spawn("state", function()
    while true do
        state.connections = #held
        state.answered = answered_frames
        write_state()
        if disk.is_file(FOLDER .. "/stop") then
            os.remove(FOLDER .. "/stop")
            sync_now()
            ram.log(FOLDER, now(), "stopped: asked to; synced once more")
            state.stopped = "asked"
            write_state()
            stopping = true
            return
        end
        wait.sleep(1)
    end
end)

loop:run(function() return stopping end)
server:close()
fd_log:close()
os.exit(0)
