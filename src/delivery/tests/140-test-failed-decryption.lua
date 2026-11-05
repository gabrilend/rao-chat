-- 140-test-failed-decryption.lua — the referees of issue 203 (the
-- failed-decryption log), each run against the real code and against a
-- deliberately broken version it must catch.
--
-- Frames reach the real reader (133's serve) through a stand-in
-- connection that holds bytes and counts what was taken; the log is
-- written by the real 139 into a scratch folder in RAM.  The shipped
-- fail2ban filter is checked with fail2ban's own matcher, fail2ban-regex,
-- when it is installed.  When it is not, that check says so and counts as
-- failed (the issue: "the referee says so and stops, rather than
-- skipping"), and the same filter is also checked by a stand-in: Python's
-- regular expressions with <HOST> expanded as fail2ban documents it.
--
-- Run: luajit src/delivery/tests/140-test-failed-decryption.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>"; exit status
-- 0 only when nothing failed.  About 40 s (referee 3 floods a million
-- frames three times: once real, twice broken).

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/delivery/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local room_key = require("123-room-key")
local seal = require("124-seal")
local frames = require("125-frames")
local records = require("126-inner-records")
local keyring = require("127-keyring")
local rooms = require("002-room-folders")
local receive = require("133-receive")
local split = require("138-size-split")
local fd = require("139-failed-decryption")

local passed, failed = 0, 0
-- {{{ local function check
local function check(name, test)
    local ok, problem = pcall(test)
    if ok then
        passed = passed + 1
        print("PASS " .. name)
    else
        failed = failed + 1
        print("FAIL " .. name .. ": " .. tostring(problem))
    end
end
-- }}}

-- {{{ local function must / must_fail
local function must(condition, words)
    if not condition then error(words, 2) end
end
local function must_fail(referee, broken, words)
    local ok, caught = pcall(referee, broken)
    if ok then error("the referee passed a broken version: " .. words, 2) end
    print("     caught: " .. tostring(caught):gsub("^[^:]*:%d+: ", ""))
end
-- }}}

-- {{{ local function swap
local function swap(tbl, name, value, fn)
    local old = tbl[name]
    tbl[name] = value
    local ok, problem = pcall(fn)
    tbl[name] = old
    if not ok then error(problem, 0) end
end
-- }}}

local SCRATCH = DIR .. "/tmp/shared-memory/failed-decryption"
os.execute("rm -rf '" .. SCRATCH .. "' && mkdir -p '" .. SCRATCH .. "'")
local folder_count = 0

-- {{{ local function new_folder
local function new_folder(name)
    folder_count = folder_count + 1
    local path = SCRATCH .. "/" .. name .. "-" .. folder_count
    os.execute("mkdir -p '" .. path .. "'")
    return path
end
-- }}}

-- {{{ local function read_all
local function read_all(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
-- }}}

-- {{{ local function lines_of
local function lines_of(path)
    local list = {}
    for line in (read_all(path) or ""):gmatch("([^\n]*)\n") do list[#list + 1] = line end
    return list
end
-- }}}

-- {{{ local function stand_in_conn
-- A connection holding `bytes`; counts what was taken; closed when empty.
local function stand_in_conn(bytes)
    local conn = { at = 1, taken = 0, closed = false }
    function conn:receive(n)
        local give = math.min(n, #bytes - self.at + 1)
        local piece = bytes:sub(self.at, self.at + give - 1)
        self.at = self.at + give
        self.taken = self.taken + give
        if #piece < n then return nil, "closed", piece end
        return piece
    end
    function conn:send(data, i, j) return j end
    function conn:close() self.closed = true end
    return conn
end
-- }}}

-- {{{ local function first_variants
-- The first variant of every switchable choice (as the phase 1 demo's
-- homes start), so the real neighbours, which refuse to guess, can run.
local function first_variants()
    local config = {}
    local listing = io.popen("ls " .. DIR .. "/src/*/[0-9][0-9][0-9]-options.lua")
    for path in listing:lines() do
        for _, choice in ipairs(dofile(path)) do
            if choice.config_key ~= "" then config[choice.config_key] = choice.variants[1].name end
        end
    end
    listing:close()
    return config
end
-- }}}
local START_CONFIG = first_variants()

local MAILBOX_PORT = 7501
local TOKENS = { "failed decryption room one", "failed decryption room two", "failed decryption room three" }
local RING = keyring.from_tokens({ { room = "one", token = TOKENS[1] }, { room = "two", token = TOKENS[2] },
    { room = "three", token = TOKENS[3] } })
local CLOCK = 1793878367

-- {{{ local function serve_one
-- bytes arriving from peer → (why serve ended, the conn).  Written into
-- `log` through 139's seams.
local function serve_one(bytes, peer, log, now)
    local conn = stand_in_conn(bytes)
    local seams = fd.seams(log, MAILBOX_PORT, function() return now or CLOCK end)
    seams.peer = peer
    seams.ring = function() return RING end
    seams.now = function() return now or CLOCK end
    local why = receive.serve(conn, seams)
    return why, conn
end
-- }}}

-- {{{ local function garbage_frame
-- A frame of `length` announced bytes that no key opens.
local function garbage_frame(length)
    return seal.uint32_be(length) .. string.rep("\170", length)
end
-- }}}

------------------------------------------------------------------------------
-- fail2ban's matcher, and a stand-in for it
------------------------------------------------------------------------------

local FILTER = DIR .. "/docs/fail2ban/rao-chat-failed-decryption.conf"

-- {{{ local function shell_quote
local function shell_quote(text)
    return "'" .. text:gsub("'", "'\\''") .. "'"
end
-- }}}

-- {{{ local function fail2ban_regex
-- A file of lines → the addresses fail2ban-regex finds with the shipped
-- filter, or nil and why.
local function fail2ban_regex(path)
    local probe = io.popen("command -v fail2ban-regex 2>/dev/null")
    local where = probe:read("*l")
    probe:close()
    if not where or where == "" then return nil, "fail2ban-regex is not installed" end
    local run = io.popen("fail2ban-regex --print-all-matched " .. shell_quote(path) .. " "
        .. shell_quote(FILTER) .. " 2>&1")
    local text = run:read("*a")
    run:close()
    local found = {}
    for host in text:gmatch("from=([%x:.]+)") do found[#found + 1] = host end
    return found, text
end
-- }}}

-- {{{ local function stand_in_regex
-- A file of lines → for each line, the address the filter's failregex
-- extracts (or false), both as written and with the leading seconds cut
-- out (fail2ban may cut the matched time out before matching).  <HOST> is
-- expanded as fail2ban documents it for addresses:
-- (?:::f{4,6}:)?(?P<host>[\w\-.^_]*\w).  Run with Python 3, read-only.
local STAND_IN = [[
import re, sys
conf = open(sys.argv[1]).read()
regex = re.search(r'^failregex\s*=\s*(.+)$', conf, re.M).group(1).strip()
regex = regex.replace('<HOST>', r'(?:::f{4,6}:)?(?P<host>[\w\-.^_]*\w)')
pattern = re.compile(regex)
for line in open(sys.argv[2]).read().split('\n'):
    if not line:
        continue
    cut = re.sub(r'^\d+', '', line)
    found = []
    for form in (line, cut):
        m = pattern.search(form)
        found.append(m.group('host') if m else '-')
    print(' '.join(found))
]]
local function stand_in_regex(path)
    local script = SCRATCH .. "/stand-in.py"
    local f = assert(io.open(script, "w"))
    f:write(STAND_IN)
    f:close()
    local run = io.popen("python3 -I " .. shell_quote(script) .. " " .. shell_quote(FILTER) .. " "
        .. shell_quote(path) .. " 2>&1")
    local results = {}
    for line in run:lines() do
        local whole_line, cut = line:match("^(%S+) (%S+)$")
        if not whole_line then error("the stand-in matcher said: " .. line, 0) end
        results[#results + 1] = { whole_line ~= "-" and whole_line, cut ~= "-" and cut }
    end
    run:close()
    return results
end
-- }}}

------------------------------------------------------------------------------
-- The line on its own
------------------------------------------------------------------------------

check("the line: written and read back the same; the stamp is the same instant; nothing but an address in from=", function()
    local text = fd.line({ seconds = CLOCK, address = "127.0.0.3", port = 5555, to_port = MAILBOX_PORT,
                           length = 40, reason = "no-key" })
    must(text == "1793878367 2026-11-05T11:32:47Z rao-chat failed-decryption v1 from=127.0.0.3 port=5555 "
        .. "to-port=7501 length=40 reason=no-key\n", "the line is not the documented one: " .. text)
    local back = fd.parse(text)
    must(back and back.address == "127.0.0.3" and back.port == 5555 and back.to_port == 7501
        and back.length == 40 and back.reason == "no-key" and back.seconds == CLOCK, "it did not read back")
    must(fd.parse(text:gsub("11:32:47", "11:32:48")) == nil, "a stamp of another instant was read")
    must(fd.parse((text:gsub(" v1 ", " v2 "))) == nil, "another grammar version was read")
    local six = fd.line({ seconds = CLOCK, address = "fe80::1%eth0", port = 1, to_port = 2, length = 3, reason = "length" })
    must(fd.parse(six).address == "fe80::1%eth0", "an IPv6 address with a zone did not read back")
    for _, bad in ipairs({ "127.0.0.3 reason=length", "host.example", "", "1.2.3.4\n" }) do
        must(not pcall(fd.line, { seconds = CLOCK, address = bad, port = 1, to_port = 2, length = 3, reason = "no-key" }),
            "a line was written with '" .. bad .. "' as the address")
    end
    must(not pcall(fd.line, { seconds = CLOCK, address = "1.2.3.4", port = 1, to_port = 2, length = 3, reason = "maybe" }),
        "an unknown reason was written")
end)

check("settings: both are read strictly, with no default and no file under 1024 bytes", function()
    local home = rooms.open_home(new_folder("home"))
    must(not pcall(fd.settings, home), "absent settings were read")
    rooms.set_config(home, "failed-decryption.file-size", "1000")
    rooms.set_config(home, "failed-decryption.files-kept", "3")
    must(not pcall(fd.settings, home), "a file size under 1024 was accepted")
    rooms.set_config(home, "failed-decryption.file-size", "1000000")
    local size, kept = fd.settings(home)
    must(size == 1000000 and kept == 3, "the settings did not read")
    rooms.set_config(home, "failed-decryption.files-kept", "0")
    must(not pcall(fd.settings, home), "keeping no files was accepted")
end)

------------------------------------------------------------------------------
-- 1. Garbage writes one line with the address
------------------------------------------------------------------------------

-- {{{ referee 1
-- broken: nil, "anonymous" (rmail's line) or "per key".  Gives back the
-- log's path.
local function referee_garbage(broken)
    local folder = new_folder("garbage")
    local log = fd.open(folder, 4096, 3)
    local function run()
        local why = serve_one(garbage_frame(40), { host = "127.0.0.3", port = 5555 }, log)
        must(why == "unopened", "the garbage frame ended the connection as " .. tostring(why))
    end
    if broken == "anonymous" then
        swap(fd, "line", function() return os.date("!%Y-%m-%d %H:%M:%S", CLOCK) .. " decryption failed: no matching contact key\n" end, run)
    elseif broken == "per key" then
        swap(keyring, "open_frame", function(ring, after)
            for _ in ipairs(ring.entries) do
                log:write({ host = "127.0.0.3", port = 5555 }, MAILBOX_PORT, #after, "no-key", CLOCK)
            end
            return nil
        end, function()
            local why = serve_one(garbage_frame(40), { host = "127.0.0.3", port = 5555 }, { write = function() end })
            must(why == "unopened", "the garbage frame ended the connection as " .. tostring(why))
        end)
    else
        run()
    end
    log:close()
    local path = folder .. "/" .. fd.FILE
    local lines = lines_of(path)
    must(#lines == 1, "a garbage frame tried against " .. #RING.entries .. " keys wrote " .. #lines .. " lines")
    local fields = fd.parse(lines[1])
    must(fields and fields.address == "127.0.0.3" and fields.port == 5555 and fields.to_port == MAILBOX_PORT
        and fields.length == 40 and fields.reason == "no-key", "the line does not carry the address and ports: " .. lines[1])
    local matched = stand_in_regex(path)
    must(matched[1][1] == "127.0.0.3" and matched[1][2] == "127.0.0.3",
        "the stand-in for fail2ban's matcher did not extract 127.0.0.3 from the line")
    return path
end
-- }}}

check("referee 1: a garbage frame writes exactly one line, with its address, that the shipped filter matches", function()
    referee_garbage()
    must_fail(referee_garbage, "anonymous", "rmail's line without the address")
    must_fail(referee_garbage, "per key", "one line per key tried")
end)

check("referee 1: fail2ban-regex itself, with the shipped filter, extracts 127.0.0.3", function()
    local path = referee_garbage()
    local found, why = fail2ban_regex(path)
    if not found then error("STOPPED: " .. why .. ", so the filter is not checked by fail2ban here; "
        .. "install fail2ban and run this again (the stand-in check above passed)", 0) end
    must(#found >= 1 and found[1] == "127.0.0.3", "fail2ban-regex did not extract 127.0.0.3:\n" .. tostring(why))
end)

check("the filter matches no other kind of line, and rmail's line not at all", function()
    local folder = new_folder("others")
    local path = folder .. "/lines"
    local f = assert(io.open(path, "w"))
    f:write("2026-11-05 11:32:47 decryption failed: no matching contact key\n")
    f:write("1793878367 2026-11-05T11:32:47Z rao-chat filed message from=127.0.0.3 port=5555\n")
    f:write("1793878367 2026-11-05T11:32:47Z rao-chat failed-decryption v2 from=127.0.0.3 port=5555 to-port=7501 length=40 reason=no-key\n")
    f:close()
    for i, result in ipairs(stand_in_regex(path)) do
        must(not result[1] and not result[2], "line " .. i .. " matched the filter")
    end
end)

------------------------------------------------------------------------------
-- 2. A genuine frame writes nothing
------------------------------------------------------------------------------

-- {{{ referee 2
local function referee_genuine(broken)
    local folder = new_folder("genuine")
    local home = rooms.open_home(new_folder("genuine-home"))
    for key, value in pairs(START_CONFIG) do rooms.set_config(home, key, value) end
    local tag = rooms.make_room(home, { label = "the room", token = TOKENS[2], kind = "group", parent = "",
        members = {}, filed_under = "", mailbox_port = MAILBOX_PORT })
    local log = fd.open(folder, 4096, 3)
    local record = records.encode({ kind = "message", id = "genuine1", written = CLOCK, target = "", text = "hello" })
    local frame = seal.seal(room_key.key_pair(TOKENS[2]), record)
    local conn = stand_in_conn(frame)
    local seams = fd.seams(log, MAILBOX_PORT, function() return CLOCK end)
    seams.home = home
    seams.peer = { host = "127.0.0.4", port = 6000 }
    seams.ring = function() return keyring.for_port(rooms, home, MAILBOX_PORT) end
    seams.now = function() return CLOCK end
    local function run()
        local why = receive.serve(conn, seams)
        must(why == "closed", "the genuine frame's connection ended as " .. tostring(why))
    end
    if broken then
        -- logging every opening attempt
        local real = keyring.open_frame
        swap(keyring, "open_frame", function(ring, after, workers)
            log:write(seams.peer, MAILBOX_PORT, #after, "no-key", CLOCK)
            return real(ring, after, workers)
        end, run)
    else
        run()
    end
    log:close()
    must(read_all(folder .. "/" .. fd.FILE) == nil or #read_all(folder .. "/" .. fd.FILE) == 0,
        "a genuine frame wrote: " .. tostring(read_all(folder .. "/" .. fd.FILE)))
end
-- }}}

check("referee 2: a genuine frame writes nothing", function()
    referee_genuine()
    must_fail(referee_genuine, true, "logging every opening attempt")
end)

------------------------------------------------------------------------------
-- 3. Bounded
------------------------------------------------------------------------------

local FLOOD = 1000000
local FILE_SIZE, KEPT = 4096, 3

-- {{{ referee 3
-- broken: nil, "never splits" or "after passing".
local function referee_bounded(broken)
    local folder = new_folder("flood")
    local log = fd.open(folder, FILE_SIZE, KEPT)
    if broken == "never splits" then log.writer.start_next = function(self) self.size = 0 end end
    local frame = garbage_frame(seal.MIN_LENGTH)
    local function flood()
        -- a frame no key opens closes its connection, so each frame of a
        -- flood comes on a connection of its own; a thousand a second
        for i = 1, FLOOD do
            serve_one(frame, { host = "127.0.0.3", port = 5555 + (i % 100) }, log, CLOCK + math.floor(i / 1000))
        end
    end
    if broken == "after passing" then
        swap(split, "would_pass", function(size, adding, limit) return size > limit end, flood)
    else
        flood()
    end
    log:close()
    local files, total_lines = {}, 0
    for name in io.popen("ls '" .. folder .. "'"):lines() do files[#files + 1] = name end
    must(#files <= KEPT, #files .. " files are kept, more than " .. KEPT)
    for _, name in ipairs(files) do
        local text = read_all(folder .. "/" .. name)
        must(#text <= FILE_SIZE, name .. " is " .. #text .. " bytes, larger than " .. FILE_SIZE)
        for line in text:gmatch("([^\n]*)\n") do
            must(fd.parse(line), "a line in " .. name .. " does not read: " .. line)
            total_lines = total_lines + 1
        end
    end
    -- the kept files hold the newest lines, in order, the last one last
    local newest = lines_of(folder .. "/" .. fd.FILE)
    must(fd.parse(newest[#newest]).seconds == CLOCK + FLOOD / 1000,
        "the newest file does not end with the last frame")
    local previous = nil
    for n = KEPT - 1, 1, -1 do
        for _, line in ipairs(lines_of(folder .. "/" .. fd.FILE .. "." .. n)) do
            local s = fd.parse(line).seconds
            must(not previous or s >= previous, "the kept files are not in order")
            previous = s
        end
    end
    return total_lines
end
-- }}}

check("referee 3: a million garbage frames leave at most files-kept files, none larger than file-size", function()
    local started = os.clock()
    local lines = referee_bounded()
    print(string.format("     %d frames: %d lines kept in %d files of at most %d bytes (%.1f s)",
        FLOOD, lines, KEPT, FILE_SIZE, os.clock() - started))
    must_fail(referee_bounded, "never splits", "one file growing forever")
    must_fail(referee_bounded, "after passing", "a split after passing the size")
end)

check("the size rule, numbered (215a's naming): never over the limit, every byte once, an oversize write split", function()
    local folder = new_folder("numbered")
    local writer = split.open({ folder = folder, name = "running-log", limit = 1000, naming = "numbered" })
    local written = {}
    for cycle = 1, 30 do
        local text = string.rep(string.format("cycle %02d line\n", cycle), cycle == 7 and 160 or 18)
        writer:write(text)
        written[#written + 1] = text
    end
    writer:close()
    local joined, n = {}, 1
    while true do
        local text = read_all(string.format("%s/running-log.%04d", folder, n))
        if not text then break end
        must(#text <= 1000, "file " .. n .. " is " .. #text .. " bytes")
        joined[#joined + 1] = text
        n = n + 1
    end
    must(table.concat(joined) == table.concat(written), "the files joined in order are not what was written")
    -- carrying on after a restart
    local again = split.open({ folder = folder, name = "running-log", limit = 1000, naming = "numbered" })
    must(again.number == n - 1, "a reopened writer did not carry on from the last file")
    again:close()
    local rotate = split.open({ folder = folder, name = "rotated", limit = 1000, keep = 2 })
    must(not pcall(rotate.write, rotate, string.rep("x", 1001)), "a rotated file took a write it would cut in two")
    rotate:close()
end)

------------------------------------------------------------------------------
-- 4. Length refusals are counted
------------------------------------------------------------------------------

-- {{{ referee 4
-- broken: nil, "reads the body" or "not logged".
local function referee_length(broken)
    local folder = new_folder("length")
    local log = fd.open(folder, 4096, 3)
    local bytes = garbage_frame(seal.CAP + 1)
    local why, conn
    local function run() why, conn = serve_one(bytes, { host = "127.0.0.5", port = 7000 }, log) end
    if broken == "reads the body" then
        local real = frames.read_frame
        swap(frames, "read_frame", function(c)
            local head = c:receive(4)
            local length = seal.read_uint32_be(head)
            c:receive(length)
            if length > seal.CAP then return nil, "over the cap", length end
            return real(c)
        end, run)
    elseif broken == "not logged" then
        swap(fd, "seams", function(l, port, now)
            return { on_unopened = function(peer, length) l:write(peer, port, length, "no-key", now()) end }
        end, run)
    else
        run()
    end
    log:close()
    must(why == "length", "the connection ended as " .. tostring(why))
    must(conn.taken == 4, "the reader took " .. conn.taken .. " bytes before refusing")
    local lines = lines_of(folder .. "/" .. fd.FILE)
    must(#lines == 1, "a length refusal wrote " .. #lines .. " lines")
    local fields = fd.parse(lines[1])
    must(fields.reason == "length" and fields.length == seal.CAP + 1 and fields.address == "127.0.0.5",
        "the line is not a length refusal from 127.0.0.5: " .. lines[1])
end
-- }}}

check("referee 4: a header announcing more than the cap writes one line, reason length, having read 4 bytes", function()
    referee_length()
    must_fail(referee_length, "reads the body", "reading the body before refusing")
    must_fail(referee_length, "not logged", "a length refusal not written")
end)

os.execute("rm -rf '" .. SCRATCH .. "'")
print(string.format("counts %d %d", passed, failed))
os.exit(failed == 0 and 0 or 1)
