-- 212-test-sealing-in-the-page.lua — the referees of issue 402, sealing in
-- the page: a frame the page seals (WebCrypto, 210) opens with the home's
-- 124 under the same token, at 124's padded size, and a frame 124 seals
-- opens in the page; opening is all or nothing (a flipped byte, another
-- token, another token's tying value, padding that is not zeros); the
-- page's record table (211) is 186's, and both sides read and refuse the
-- same lines; the page's key follows 123's rule for tokens.  Each referee
-- with a broken version also runs against it.
--
-- The page's side runs in the stand-in browser (208) under Node.  No
-- network is used.  Files are under RAO_TEST_ROOT when that is set,
-- otherwise a folder of its own under /dev/shm (or /tmp), removed at the
-- end.
--
-- Run: luajit src/web/tests/212-test-sealing-in-the-page.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>".

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/web/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local ffi = require("ffi")
local disk = require("003-disk")
local tokens = require("007-tokens")
local room_key = require("123-room-key")
local seal = require("124-seal")
local records = require("186-device-records")
ffi.cdef [[ int getpid(void); ]]

local base = os.getenv("RAO_TEST_ROOT")
if not base or base == "" then
    base = os.execute("test -d /dev/shm && test -w /dev/shm") == 0 and "/dev/shm" or "/tmp"
end
local ROOT = base .. "/rao-chat-sealing-page-test-" .. ffi.C.getpid()
local STAND_IN = DIR .. "/src/web/tests/208-stand-in-browser.js"
local q = disk.shell_quote
local passed, failed = 0, 0

-- {{{ local function check / must
local ONLY = os.getenv("ONLY")
local function check(claim, test)
    if ONLY and not claim:find(ONLY, 1, true) then return end
    local ok, problem = pcall(test)
    if ok then
        passed = passed + 1
        print("PASS " .. claim)
    else
        failed = failed + 1
        print("FAIL " .. claim .. ": " .. tostring(problem))
    end
end
local function must(condition, words)
    if not condition then error(words, 2) end
end
-- }}}

-- {{{ local function read_file / write_file / page
local function read_file(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end
local function write_file(path, text)
    local handle = assert(io.open(path, "wb"))
    handle:write(text)
    handle:close()
end
local files = 0
local function file_of(text)
    files = files + 1
    local path = ROOT .. "/file-" .. files
    write_file(path, text)
    return path
end
-- the stand-in: command line after the project → status, what it printed
local function page(words, broken)
    local out = ROOT .. "/page-output"
    local status = os.execute((broken and ("RAO_WEB_BROKEN=" .. q(broken) .. " ") or "") .. "node " .. q(STAND_IN)
        .. " " .. q(DIR) .. " " .. words .. " > " .. q(out) .. " 2>&1")
    return status, read_file(out) or ""
end
local function hex(bytes) return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
-- }}}

-- {{{ the page's sealing and opening, through the stand-in
local TOKEN = "harbor lantern ünïcode ☕ violet"
local OTHER = "another device's token"
local function page_seal(token, record, broken)
    local out = ROOT .. "/sealed-" .. files
    local status, said = page("seal --token " .. q(file_of(token)) .. " --record " .. q(file_of(record))
        .. " --out " .. q(out), broken)
    must(status == 0, "the page did not seal: " .. said)
    return read_file(out)
end
-- token, whole frame → the record, or nil and the page's words
local function page_open(token, frame, broken)
    local out = ROOT .. "/opened-" .. files
    os.remove(out)
    local status, said = page("open --token " .. q(file_of(token)) .. " --frame " .. q(file_of(frame))
        .. " --out " .. q(out), broken)
    must(status == 0, "the page failed to run open: " .. said)
    if said:match("^record") then return read_file(out) end
    return nil, said
end
-- a frame made by hand: key of one token, tying value given, body after it
local function hand_frame(token, tie, rest)
    local pair = room_key.key_pair(token)
    local iv = seal.nonce()
    local sealed, tag = seal.gcm_encrypt(pair.key, iv, tie .. rest)
    local after = iv .. sealed .. tag
    return seal.uint32_be(#after) .. after
end
-- }}}

os.execute("mkdir -p " .. q(ROOT))
local has_node = os.execute("command -v node > /dev/null 2>&1") == 0
if not has_node then
    print("FAIL every referee: STOPPED: node is not installed, so the page's scripts cannot be run outside a browser here")
    print("counts 0 1")
    os.exit(1)
end

-- the records both sides are tried on: every kind, with every escape and
-- bytes that are not ASCII or not UTF-8 at all
local TRICKY = "tab\there, line\nbreak, \\back\\slash, \r return, ünïcode ☕, nul \0 and \255 bytes"
local SAMPLES = {
    { kind = "ping", id = "a-1" },
    { kind = "pong", id = "Z9", at = 1793900000 },
    { kind = "catch-up", rooms = string.rep("a", 32) .. " 1793900000-abc " .. string.rep("0", 64) .. "\n" .. TRICKY },
    { kind = "file", path = string.rep("b", 32) .. "/inbox/.tree", content = TRICKY },
    { kind = "index", room = string.rep("C", 32), entries = "x y\n" .. TRICKY },
    { kind = "want", id = "w1", room = string.rep("d", 32), names = "one\ntwo" },
    { kind = "sent", id = "w1" },
    { kind = "caught-up", at = 0 },
    { kind = "typed", id = "1793900000-000001-0a1b2c3d", content = "room: x\n\n" .. TRICKY },
    { kind = "typed-ok", id = "1793900000-000001-0a1b2c3d" },
    { kind = "typed-refused", id = "x", why = TRICKY },
}

-- {{{ referee 1: the page and the home agree
check("1: a frame the page seals opens with 124, at 124's padded size", function()
    for _, sample in ipairs(SAMPLES) do
        local record = records.encode(sample)
        local frame = page_seal(TOKEN, record)
        must(seal.read_uint32_be(frame:sub(1, 4)) == #frame - 4, "the length is not what follows")
        local opened, why = seal.open(room_key.key_pair(TOKEN), frame:sub(5))
        must(opened == record, sample.kind .. ": 124 opened " .. tostring(opened) .. " (" .. tostring(why) .. ")")
        must(#frame == 4 + 12 + seal.padded_size(32 + #record) + 16,
            sample.kind .. ": " .. #frame .. " bytes, not 124's size")
    end
end)
check("1b: a frame 124 seals opens in the page", function()
    for _, sample in ipairs(SAMPLES) do
        local record = records.encode(sample)
        local opened, said = page_open(TOKEN, seal.seal(room_key.key_pair(TOKEN), record))
        must(opened == record, sample.kind .. ": the page opened " .. tostring(opened) .. " " .. tostring(said))
    end
end)
check("1c: a 70000-byte record both ways (padded to 131072), and an unpadded body", function()
    local record = records.encode({ kind = "file", path = "p", content = string.rep("x\t", 35000) })
    local frame = page_seal(TOKEN, record)
    must(#frame == 4 + 12 + 131072 + 16, "page frame " .. #frame)
    must(seal.open(room_key.key_pair(TOKEN), frame:sub(5)) == record, "124 could not open it")
    must(page_open(TOKEN, seal.seal(room_key.key_pair(TOKEN), record)) == record, "the page could not open 124's")
    must(page_open(TOKEN, seal.seal(room_key.key_pair(TOKEN), "ping\tunpadded", { pad = false })) == "ping\tunpadded",
        "the page refused an unpadded body")
end)
check("1d: every kind's record reads the same on both sides, escapes and odd bytes included", function()
    local lines = {}
    for i, sample in ipairs(SAMPLES) do lines[i] = records.encode(sample) end
    local status, out = page("records --in " .. q(file_of(table.concat(lines, "\n") .. "\n")))
    must(status == 0, "records failed: " .. out)
    local n = 0
    for kind, line_hex, fields in out:gmatch("\nok (%S+) (%x+) ?([^\n]*)") do
        n = n + 1
        local mine = assert(records.decode(lines[n]))
        must(kind == mine.kind, "line " .. n .. " read as " .. kind)
        must(line_hex == hex(lines[n]), kind .. ": encoded again differently")
        for name, value_hex in fields:gmatch("([%w%-]+)=(%x*)") do
            must(value_hex == hex(mine[name]), kind .. "'s " .. name .. " differs")
        end
    end
    must(n == #SAMPLES, "the page read " .. n .. " of " .. #SAMPLES .. " records: " .. out)
end)
-- }}}

-- {{{ referee 2: opening is all or nothing
local function tamper(frame, at)
    return frame:sub(1, at - 1) .. string.char((frame:byte(at) + 1) % 256) .. frame:sub(at + 1)
end
local function all_or_nothing(broken)
    local problems = {}
    local pair = room_key.key_pair(TOKEN)
    local frame = seal.seal(pair, "ping\tt1")
    local tries = {
        { "a byte of the body flipped", tamper(frame, 4 + 12 + 5) },
        { "a byte of the check value flipped", tamper(frame, #frame - 3) },
        { "a byte of the nonce flipped", tamper(frame, 4 + 2) },
        { "another token", seal.seal(room_key.key_pair(OTHER), "ping\tt1") },
        { "another token's tying value under this key", hand_frame(TOKEN, room_key.key_pair(OTHER).tie, "ping\tt1") },
        { "padding that is not zeros", hand_frame(TOKEN, pair.tie, "ping\tt1\n\0\0x\0") },
    }
    for _, try in ipairs(tries) do
        local opened = page_open(TOKEN, try[2], broken)
        if opened ~= nil then problems[#problems + 1] = try[1] .. " opened as '" .. opened:sub(1, 30) .. "'" end
    end
    return problems
end
check("2: a flipped byte, another token, another token's tying value, bad padding: nothing", function()
    local problems = all_or_nothing()
    must(#problems == 0, table.concat(problems, "; "))
end)
check("2 broken: not checking the tying value (no-tie-check) is caught", function()
    local problems = all_or_nothing("no-tie-check")
    must(#problems == 1 and problems[1]:find("tying value"), "caught as: " .. table.concat(problems, "; "))
end)
-- }}}

-- {{{ referee 3: the tables agree
local function tables_agree(broken)
    local problems = {}
    local status, out = page("records --in " .. q(file_of("")), broken)
    if status ~= 0 then return { "records failed: " .. out } end
    local seen = 0
    for kind, fields in out:gmatch("table (%S+) ([^\n]*)") do
        seen = seen + 1
        local mine = records.KINDS[kind]
        if not mine then problems[#problems + 1] = "the page has a kind 186 has not: " .. kind
        elseif table.concat(mine, " ") ~= fields then
            problems[#problems + 1] = kind .. " is '" .. fields .. "' in the page, '" .. table.concat(mine, " ") .. "' in 186"
        end
    end
    local count = 0
    for _ in pairs(records.KINDS) do count = count + 1 end
    if seen ~= count then problems[#problems + 1] = "the page has " .. seen .. " kinds, 186 has " .. count end
    local rules = {}
    for name in pairs(records.RULES) do rules[#rules + 1] = name end
    table.sort(rules)
    if (out:match("rules ([^\n]*)") or "") ~= table.concat(rules, " ") then problems[#problems + 1] = "the rule fields differ" end
    -- the same lines refused and read on both sides
    local lines = {
        "ping\t" .. string.rep("a", 64), "ping\t" .. string.rep("a", 65), "ping\ta b", "ping\t",
        "pong\tx\t12a", "pong\tx\t" .. string.rep("1", 16), "index\t" .. string.rep("e", 31) .. "\tx",
        "index\t" .. string.rep("g", 32) .. "\tx", "sent\tone\textra", "nothing\tx", "file\tp\tbad \\q escape",
        "file\tp\tlone \\", "want\tw\t" .. string.rep("f", 32) .. "\ta\\nb",
    }
    status, out = page("records --in " .. q(file_of(table.concat(lines, "\n") .. "\n")), broken)
    local verdicts = {}
    for verdict in out:gmatch("\n(%a+) [^\n]*") do
        if verdict == "ok" or verdict == "refused" then verdicts[#verdicts + 1] = verdict end
    end
    for i, line in ipairs(lines) do
        local mine = records.decode(line) and "ok" or "refused"
        if verdicts[i] ~= mine then
            problems[#problems + 1] = "'" .. line:sub(1, 30) .. "' is " .. tostring(verdicts[i]) .. " in the page, " .. mine .. " in 186"
        end
    end
    return problems
end
check("3: the page's kinds, fields in order and rules are 186's; both read and refuse the same lines", function()
    local problems = tables_agree()
    must(#problems == 0, table.concat(problems, "; "))
end)
check("3 broken: a field missing from one kind (short-kind) is caught", function()
    local problems = tables_agree("short-kind")
    must(#problems > 0 and table.concat(problems, "; "):find("want is 'id room'"), "not caught")
end)
-- }}}

-- {{{ referee 4: tokens by 123's rule
check("4: the page's tying value is 123's, a non-ASCII token included, and nothing is trimmed", function()
    for _, token in ipairs({ TOKEN, "coffee", "coffee ", " tabs\tinside" }) do
        local status, out = page("key --token " .. q(file_of(token)))
        must(status == 0, "key failed: " .. out)
        must(out:match("tie (%x+)") == tokens.token_fingerprint(token), "'" .. token .. "' differs from 123")
    end
end)
check("4b: a token with a line break, or an empty one, is refused", function()
    for _, token in ipairs({ "two\nlines", "return\r", "" }) do
        local status, out = page("key --token " .. q(file_of(token)))
        must(status ~= 0 and (out:find("line break") or out:find("non%-empty")), "'" .. token .. "' was not refused: " .. out)
    end
end)
-- }}}

if ROOT:match("/rao%-chat%-sealing%-page%-test%-%d+$") then os.execute("rm -rf " .. q(ROOT)) end
print(string.format("counts %d %d", passed, failed))
os.exit(failed == 0 and 0 or 1)
