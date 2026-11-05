-- 128-test-sealing.lua — the referees of issue 201 (and the padding
-- referee of the sealing note), each run against the real code and
-- against a deliberately broken version it must catch.
--
-- Written from the rules in the issue and notes/rmail-rubric/
-- sealing-and-framing.md, not from rmail's code.  A referee that passes
-- its broken version grades nothing, so every broken version is run and
-- must fail.
--
-- Run: luajit src/sealing/tests/128-test-sealing.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>"; exit status
-- 0 only when nothing failed.

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    -- a relative path is relative to where the program was started
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/sealing/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local ffi = require("ffi")
local bit_library = require("bit")
local room_key = require("123-room-key")
local seal = require("124-seal")
local frames = require("125-frames")
local records = require("126-inner-records")
local keyring = require("127-keyring")
local rooms = require("002-room-folders")
local tokens = require("007-tokens")
local codecs = require("083-record-codecs")

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
-- A referee run against a broken version must raise an error.
-- What it caught is printed under the check, so a broken version failing
-- for the wrong reason (a setup error) is seen.
local function must_fail(referee, broken, words)
    local ok, caught = pcall(referee, broken)
    if ok then error("the referee passed a broken version: " .. words, 2) end
    print("     caught: " .. tostring(caught):gsub("^[^:]*:%d+: ", ""))
end
-- }}}

-- {{{ local function hex
local function hex(bytes)
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
-- }}}

local PAIR = room_key.key_pair("test-room-token")
local OTHER = room_key.key_pair("another-room-token")

------------------------------------------------------------------------------
-- 1. Key from token (R5)
------------------------------------------------------------------------------

-- {{{ referee 1
-- impl: {key = function(token), read_back = function(token) → the token as
-- a reader gets it back from a room's entry}
local function referee_key(impl)
    local key = impl.key("abc")
    must(#key == 32, "the key is 32 raw bytes, got " .. #key)
    must(hex(key) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        "the key for abc is SHA-256's test vector")
    must(impl.key(impl.read_back("maple-orbit velvet tin")) == impl.key("maple-orbit velvet tin"),
        "a token read back from an entry gives the same key as typed")
end
-- }}}

-- A real round trip through a room's entry.
local SCRATCH = DIR .. "/tmp/shared-memory/sealing"
os.execute("rm -rf '" .. SCRATCH .. "' && mkdir -p '" .. SCRATCH .. "'")
local next_port = 7300
-- {{{ local function fresh_home
local function fresh_home(name)
    local home = rooms.open_home(SCRATCH .. "/" .. name)
    rooms.make_mailbox(home, { label = "direct messages", kind = "direct", port = 7299 })
    return home
end
-- }}}
-- {{{ local function make_top
local function make_top(home, label, token)
    next_port = next_port + 1
    return rooms.make_room(home, { label = label, token = token, kind = "group", parent = "", members = {},
        filed_under = "", mailbox_port = next_port }), next_port
end
-- }}}
local KEY_HOME = fresh_home("key")

-- The token as a room's entry gives it back (one room per token: a token
-- asked for twice reads the room made the first time).
local made_for = {}
local function read_back(token)
    made_for[token] = made_for[token] or make_top(KEY_HOME, "a room " .. next_port, token)
    return rooms.read_entry(KEY_HOME, made_for[token]).token
end

check("1. the key is SHA-256 of the token's bytes, and an entry gives back the typed token", function()
    referee_key({ key = room_key.room_key, read_back = read_back })
end)
check("1. the tying value is the room's fingerprint as bytes, and a token with a line ending is refused", function()
    must(hex(room_key.tying_value("abc")) == tokens.token_fingerprint("abc"), "tying value = fingerprint")
    must(not pcall(room_key.room_key, "abc\n"), "a token ending in a line break is an error")
    must(not pcall(room_key.room_key, ""), "an empty token is an error")
end)
check("1. referee catches: the key as 64 hex characters", function()
    must_fail(referee_key, { key = function(t) return hex(room_key.room_key(t)) end, read_back = read_back },
        "a hex key")
end)
check("1. referee catches: a token read back with its line ending", function()
    must_fail(referee_key, { key = room_key.room_key, read_back = function(t) return read_back(t) .. "\n" end },
        "a line ending kept")
end)

------------------------------------------------------------------------------
-- 2. Frame layout
------------------------------------------------------------------------------

-- {{{ referee 2
-- impl.seal(pair, record) → frame (unpadded)
local function referee_layout(impl)
    for _, record in ipairs({ "", "x", "message\tid1\t1700000000\t\thello", string.rep("y", 300) }) do
        local frame = impl.seal(PAIR, record)
        must(#frame == #record + 32 + 32, "a record of " .. #record .. " bytes gives a frame of n + 64")
        must(seal.read_uint32_be(frame:sub(1, 4)) == #frame - 4, "the length, big-endian, counts what follows it")
        local plain = seal.gcm_decrypt(PAIR.key, frame:sub(5, 16), frame:sub(17, -17), frame:sub(-16))
        must(plain == PAIR.tie .. record, "bytes 5-16 are the nonce, the check value is last, the body is tie .. record")
    end
end
-- }}}

local function unpadded(pair, record) return seal.seal(pair, record, { pad = false }) end

check("2. frame layout: n + 32 + 32, length big-endian and not counting itself, nonce, body, check value", function()
    referee_layout({ seal = unpadded })
end)
check("2. referee catches: a little-endian length", function()
    must_fail(referee_layout, { seal = function(p, r)
        local f = unpadded(p, r)
        return f:sub(1, 4):reverse() .. f:sub(5)
    end }, "little-endian")
end)
check("2. referee catches: a length that counts itself", function()
    must_fail(referee_layout, { seal = function(p, r)
        local f = unpadded(p, r)
        return seal.uint32_be(#f) .. f:sub(5)
    end }, "counts itself")
end)
check("2. referee catches: the check value before the sealed body", function()
    must_fail(referee_layout, { seal = function(p, r)
        local f = unpadded(p, r)
        return f:sub(1, 16) .. f:sub(-16) .. f:sub(17, -17)
    end }, "tag first")
end)

------------------------------------------------------------------------------
-- 3. Every bit counts (R2)
------------------------------------------------------------------------------

local libcrypto = ffi.load("crypto")

-- {{{ local function open_without_check
-- Broken: GCM's decryption with its check ignored — the plaintext produced
-- before the check is returned whatever the check says (counter mode with
-- no check, in effect).
local function open_without_check(pair, after)
    local iv, ct = after:sub(1, 12), after:sub(13, -17)
    local ctx = libcrypto.EVP_CIPHER_CTX_new()
    local out = ffi.new("unsigned char[?]", #ct + 16)
    local outl = ffi.new("int[1]")
    libcrypto.EVP_DecryptInit_ex(ctx, libcrypto.EVP_aes_256_gcm(), nil, pair.key, iv)
    libcrypto.EVP_DecryptUpdate(ctx, out, outl, ct, #ct)
    local body = ffi.string(out, outl[0])
    libcrypto.EVP_CIPHER_CTX_free(ctx)
    return body:sub(33)
end
-- }}}

-- {{{ referee 3
-- impl.open(pair, after_length) → record or nil.  Every single-bit flip of
-- a small frame must open to nothing.
local function referee_bits(impl)
    local after = unpadded(PAIR, "hi"):sub(5)
    must(impl.open(PAIR, after) == "hi", "the untouched frame opens")
    for byte = 1, #after do
        for bit = 0, 7 do
            local flipped = after:sub(1, byte - 1) .. string.char(bit_library.bxor(after:byte(byte), 2 ^ bit))
                .. after:sub(byte + 1)
            must(impl.open(PAIR, flipped) == nil, "bit " .. bit .. " of byte " .. byte .. " flipped still opened")
        end
    end
end
-- }}}

check("3. every one of a frame's bits, flipped, makes it open to nothing", function()
    referee_bits({ open = seal.open })
end)
check("3. referee catches: plaintext returned without the check", function()
    must_fail(referee_bits, { open = open_without_check }, "no check")
end)
check("3. a frame under another room's key, or with the wrong tying value, opens to nothing", function()
    local frame = seal.seal(PAIR, "hello")
    must(seal.open(OTHER, frame:sub(5)) == nil, "another room's key")
    -- the right key, the wrong tying value: sealed by a broken writer
    local frame2 = seal.seal({ key = PAIR.key, tie = OTHER.tie }, "hello")
    must(seal.open(PAIR, frame2:sub(5)) == nil, "the right key with another room's tying value")
end)

------------------------------------------------------------------------------
-- 4. Nonces do not repeat (R1)
------------------------------------------------------------------------------

pcall(ffi.cdef, "int fork(void);")
pcall(ffi.cdef, "int waitpid(int pid, int *status, int options);")
pcall(ffi.cdef, "void _exit(int status);")

-- {{{ local function two_processes
-- Starts two processes at once (fork, so in the same second), each making
-- `count` nonces with make_nonce(); `before_fork` runs once in this
-- process first.  → true when no nonce appears twice across both.
local function two_processes(make_nonce, count, before_fork)
    if before_fork then before_fork() end
    local files, pids = {}, {}
    for child = 1, 2 do
        files[child] = SCRATCH .. "/nonces-" .. child
        local pid = ffi.C.fork()
        if pid == 0 then
            local out = io.open(files[child], "wb")
            for _ = 1, count do out:write(make_nonce()) end
            out:close()
            ffi.C._exit(0)
        end
        pids[child] = pid
    end
    for child = 1, 2 do ffi.C.waitpid(pids[child], nil, 0) end
    local seen = {}
    for child = 1, 2 do
        local bytes = io.open(files[child], "rb"):read("*a")
        must(#bytes == count * 12, "child " .. child .. " wrote " .. #bytes .. " bytes")
        for at = 1, #bytes, 12 do
            local n = bytes:sub(at, at + 11)
            if seen[n] then return false end
            seen[n] = true
        end
    end
    return true
end
-- }}}

-- {{{ referee 4
local function referee_nonces(impl)
    local seen = {}
    for _ = 1, impl.single_count or 100000 do
        local n = impl.from_frame()
        must(not seen[n], "a nonce repeated within one process")
        seen[n] = true
    end
    must(two_processes(impl.nonce, 20000, impl.before_fork), "a nonce repeated across two processes")
end
-- }}}

check("4. 100,000 frames, and two processes started together: no nonce repeats", function()
    referee_nonces({ from_frame = function() return seal.seal(PAIR, "x"):sub(5, 16) end, nonce = seal.nonce })
end)
check("4. referee catches: a counter starting at zero in each process", function()
    local counter = 0
    must_fail(referee_nonces, { single_count = 10, from_frame = seal.nonce, nonce = function()
        counter = counter + 1
        return string.rep("\0", 8) .. seal.uint32_be(counter)
    end }, "a counter")
end)
check("4. referee catches: a nonce from a generator seeded with the clock", function()
    local seeded = false
    must_fail(referee_nonces, { single_count = 10, from_frame = seal.nonce, nonce = function()
        if not seeded then math.randomseed(os.time()); seeded = true end
        local t = {}
        for i = 1, 12 do t[i] = string.char(math.random(0, 255)) end
        return table.concat(t)
    end }, "clock-seeded")
end)
check("4. referee catches: workers forked after one generator was started (a buffered /dev/urandom)", function()
    local source
    must_fail(referee_nonces, { single_count = 10, from_frame = seal.nonce,
        before_fork = function() source = io.open("/dev/urandom", "rb"); source:read(1) end,
        nonce = function() return source:read(12) end }, "a shared buffer")
end)

------------------------------------------------------------------------------
-- 5. Size before reading (R3)
------------------------------------------------------------------------------

-- {{{ local function stand_in_reader
-- A connection holding `bytes`, giving at most `chunk` per receive, and
-- counting what was taken.
local function stand_in_reader(bytes, chunk)
    local conn = { at = 1, taken = 0 }
    function conn:receive(n)
        local give = math.min(n, chunk or n, #bytes - self.at + 1)
        local piece = bytes:sub(self.at, self.at + give - 1)
        self.at = self.at + give
        self.taken = self.taken + give
        if #piece < n then return nil, (self.at > #bytes) and "closed" or "timeout", piece end
        return piece
    end
    return conn
end
-- }}}

-- {{{ referee 5
-- impl.read(conn) → bytes or nil; impl.cap the reader's cap.
local function referee_size(impl)
    local filler = string.rep("z", seal.CAP + 8)
    for _, length in ipairs({ 27, seal.CAP + 1 }) do
        local conn = stand_in_reader(seal.uint32_be(length) .. filler)
        must(impl.read(conn) == nil, "a length of " .. length .. " was accepted")
        must(conn.taken == 4, "a length of " .. length .. " was refused only after reading " .. conn.taken .. " bytes")
    end
    local conn = stand_in_reader(seal.uint32_be(seal.CAP) .. filler)
    local got = impl.read(conn)
    must(got and #got == seal.CAP, "the cap exactly is read whole")
    -- the largest frame a writer makes is the cap exactly, and this reader takes it
    local biggest = seal.seal(PAIR, string.rep("m", seal.BODY_MAX - 32))
    must(#biggest == seal.CAP + 4, "the largest frame written is the cap, got " .. #biggest - 4)
    local opened = impl.read(stand_in_reader(biggest, 65536))
    must(opened and seal.open(PAIR, opened) == string.rep("m", seal.BODY_MAX - 32), "the largest frame is read and opens")
end
-- }}}

check("5. a length under 28 or over the cap is refused after 4 bytes; the cap exactly, and the largest frame, are read", function()
    referee_size({ read = function(c) return frames.read_frame(c) end })
end)
check("5. referee catches: reading first, then checking", function()
    must_fail(referee_size, { read = function(c)
        local head = frames.receive_exactly(c, 4)
        local length = seal.read_uint32_be(head)
        local body = frames.receive_exactly(c, math.min(length, seal.CAP + 8))
        if length < 28 or length > seal.CAP then return nil end
        return body
    end }, "read then check")
end)
check("5. referee catches: a reader with a smaller cap than the writers'", function()
    must_fail(referee_size, { read = function(c) return frames.read_frame(c, seal.CAP - 1) end }, "smaller cap")
end)
check("5. no reader may be given a cap above the project's", function()
    must(not pcall(frames.read_frame, stand_in_reader("xxxx"), seal.CAP + 1), "a larger cap was allowed")
end)

------------------------------------------------------------------------------
-- 6. Nothing in the clear (R11)
------------------------------------------------------------------------------

-- {{{ referee 6
-- impl.frame(pair, record) → wire bytes.  Known strings of three rooms
-- must not appear in any frame, nor their hex.
local function referee_clear(impl)
    local home = fresh_home("clear-" .. tostring(impl):sub(-6))
    local known = {}
    for index, token in ipairs({ "plain-words-token", "maple-orbit-velvet-tin", "coffee" }) do
        local label = "the kitchen " .. index
        local tag = make_top(home, label, token)
        local pair = room_key.key_pair(token)
        for _, s in ipairs({ token, label, tag, tokens.token_fingerprint(token), pair.key, pair.tie,
                             "192.168.1.20", "203.0.113.7 7300" }) do
            known[#known + 1] = s
        end
        for _, record in ipairs({ records.encode({ kind = "message", id = "id" .. index, written = 1700000000,
                                                   target = "", text = "about " .. label }), "" }) do
            local wire = impl.frame(pair, record)
            for _, s in ipairs(known) do
                must(not wire:find(s, 1, true), "a known string travels in the clear: " .. hex(s):sub(1, 16))
                must(not wire:find(hex(s), 1, true), "a known string's hex travels in the clear")
            end
        end
    end
end
-- }}}

check("6. no token, label, local tag, fingerprint, key or address, nor its hex, is in the wire bytes", function()
    referee_clear({ frame = seal.seal })
end)
check("6. referee catches: a fingerprint hint in front of the frame", function()
    must_fail(referee_clear, { frame = function(pair, record)
        return hex(pair.tie) .. seal.seal(pair, record)
    end }, "a hint")
end)

------------------------------------------------------------------------------
-- 7. Trial opening finds the right room
------------------------------------------------------------------------------

local THOUSAND = {}
for k = 1, 1000 do THOUSAND[k] = { room = "room-" .. k, token = "token-number-" .. k } end
-- two rooms with one label: told apart by their key, not their label
THOUSAND[999].room, THOUSAND[1000].room = "same label (a)", "same label (b)"
local RING = keyring.from_tokens(THOUSAND)
local FRAMES = {}
for k = 1, 1000 do FRAMES[k] = seal.seal(RING.entries[k], "for room " .. k):sub(5) end

-- {{{ referee 7
-- impl.open(ring, after, workers) → room, record, tried
local function referee_trial(impl)
    for _, workers in ipairs({ 1, 2, 3, 8 }) do
        for k = 1, 1000 do
            local room, record = impl.open(RING, FRAMES[k], workers)
            must(room == THOUSAND[k].room and record == "for room " .. k,
                "with " .. workers .. " workers the frame for room " .. k .. " opened as " .. tostring(room))
        end
        local room, _, tried = impl.open(RING, seal.nonce() .. string.rep("r", 300) .. seal.nonce():sub(1, 4) .. seal.nonce(), workers)
        must(room == nil and tried == 1000, "random bytes opened as " .. tostring(room) .. " after " .. tostring(tried) .. " keys")
    end
end
-- }}}

check("7. 1,000 rooms: each frame opens as its own room with 1, 2, 3 and 8 workers; random bytes as none", function()
    referee_trial({ open = keyring.open_frame })
end)
check("7. referee catches: a split that skips the last key when the count does not divide evenly", function()
    must_fail(referee_trial, { open = function(ring, after, workers)
        local answers = {}
        local size = math.floor(#ring.entries / workers)
        for w = 1, workers do
            answers[w] = keyring.try_slice(ring, after, (w - 1) * size + 1, w * size, seal.open)
        end
        return keyring.combine(answers)
    end }, "uneven split")
end)
check("7. referee catches: a combiner that reports one worker's failure while another succeeded", function()
    must_fail(referee_trial, { open = function(ring, after, workers)
        local last
        for _, s in ipairs(keyring.slices(#ring.entries, workers)) do
            last = keyring.try_slice(ring, after, s.first, s.last, seal.open)
        end
        return last.room, last.record, last.tried
    end }, "last answer wins")
end)
check("7. a split covers every key once, sizes differing by at most one", function()
    for n = 0, 40 do
        for w = 1, 9 do
            local covered, smallest, largest = 0, math.huge, 0
            for _, s in ipairs(keyring.slices(n, w)) do
                must(s.first == covered + 1, "slices in order without gaps")
                covered = s.last
                local size = s.last - s.first + 1
                smallest, largest = math.min(smallest, size), math.max(largest, size)
            end
            must(covered == n, n .. " keys over " .. w .. " workers covered " .. covered)
            must(n == 0 or largest - smallest <= 1, "uneven slices")
        end
    end
end)

------------------------------------------------------------------------------
-- 8. The port limits the keys
------------------------------------------------------------------------------

local PORT_HOME = fresh_home("ports")
local top1, port1 = make_top(PORT_HOME, "first top", "first-top-token")
local top2, port2 = make_top(PORT_HOME, "second top", "second-top-token")
for index, token in ipairs({ "a-child-of-two", "another-child-of-two" }) do
    rooms.make_room(PORT_HOME, { label = "child " .. index, token = token, kind = "group",
        parent = tokens.token_fingerprint("second-top-token"), filed_under = "", members = {}, mailbox_port = "" })
end
local mailbox2 = rooms.read_entry(PORT_HOME, top2).mailbox

-- {{{ referee 8
-- impl.ring_for_port(port) → the keyring tried on that port
local function referee_port(impl)
    local frame = seal.seal(room_key.key_pair("first-top-token"), "for the first top"):sub(5)
    local room, _, tried = keyring.open_frame(impl.ring_for_port(port2), frame)
    must(room == nil, "a frame for mailbox 1 opened on mailbox 2's port")
    must(tried == #rooms.list_rooms_by_mailbox(PORT_HOME, mailbox2),
        "keys tried " .. tried .. ", rooms in mailbox 2 " .. #rooms.list_rooms_by_mailbox(PORT_HOME, mailbox2))
    room = keyring.open_frame(impl.ring_for_port(port1), frame)
    must(room == top1, "the frame opens on its own port as its room")
end
-- }}}

check("8. a frame for mailbox 1 on mailbox 2's port is a failure there, after trying mailbox 2's rooms only", function()
    referee_port({ ring_for_port = function(port) return keyring.for_port(rooms, PORT_HOME, port) end })
end)
check("8. referee catches: one keyring for the whole home", function()
    must_fail(referee_port, { ring_for_port = function()
        local list = {}
        for _, tag in ipairs(rooms.list_rooms(PORT_HOME)) do
            list[#list + 1] = { room = tag, token = rooms.read_entry(PORT_HOME, tag).token }
        end
        return keyring.from_tokens(list)
    end }, "one keyring")
end)
check("8. a changed token is picked up: the change bell drops the keyring, the next frame rebuilds it", function()
    local old = seal.seal(room_key.key_pair("first-top-token"), "old"):sub(5)
    must(keyring.open_frame(keyring.for_port(rooms, PORT_HOME, port1), old) == top1, "opens before the change")
    rooms.change_token(PORT_HOME, top1, "first-top-token-changed")
    must(keyring.open_frame(keyring.for_port(rooms, PORT_HOME, port1), old) == nil, "the old token's frame still opens")
    local new = seal.seal(room_key.key_pair("first-top-token-changed"), "new"):sub(5)
    must(keyring.open_frame(keyring.for_port(rooms, PORT_HOME, port1), new) == top1, "the new token's frame does not open")
end)

------------------------------------------------------------------------------
-- 9. Inner records round-trip
------------------------------------------------------------------------------

local AWKWARD = "tab\there, line\nbreak, cr\r, back\\slash, \\n literal, nul\0byte, bad utf-8 \255\254, é"

-- {{{ referee 9
-- impl {encode, decode}
local function referee_records(impl)
    for _, kind in ipairs(records.kinds()) do
        local record = { kind = kind, id = "abc123", written = 1700000000, target = kind == "message" and "" or "xyz",
                         text = AWKWARD }
        local line = impl.encode(record)
        must(not line:find("\n", 1, true), "an encoded record holds a raw line break")
        local back = impl.decode(line)
        for name, value in pairs(record) do
            must(back[name] == value, kind .. "." .. name .. " did not come back")
        end
        for name in pairs(back) do must(record[name] ~= nil, kind .. " came back with an extra " .. name) end
    end
    local good = impl.encode({ kind = "message", id = "a", written = 1, target = "", text = "t" })
    must(not pcall(impl.decode, "shout\ta\t1\t\tt"), "an unknown kind was read")
    must(not pcall(impl.decode, good:match("^(.*)\t[^\t]*$")), "a missing field was read")
    must(not pcall(impl.decode, good .. "\textra"), "an extra field was read")
    must(not pcall(impl.decode, "message\ta\tsoon\t\tt"), "a written that is not a number was read")
    must(not pcall(impl.decode, "message\ta\t1\t\tbad \\q escape"), "an unknown escape was read")
    must(not pcall(impl.encode, { kind = "message", id = "a", written = 1, target = "" }), "a record missing text was written")
    must(not pcall(impl.encode, { kind = "message", id = "a", written = 1, target = "", text = "", from = "me" }),
        "a record with a field its kind lacks was written")
end
-- }}}

check("9. every kind in the table round-trips; unknown kind, missing and extra fields are errors", function()
    referee_records({ encode = records.encode, decode = records.decode })
end)
check("9. referee catches: a decoder that fills missing fields with defaults", function()
    must_fail(referee_records, { encode = records.encode, decode = function(line)
        local ok, record = pcall(records.decode, line)
        if ok then return record end
        local parts = {}
        for p in (line .. "\t"):gmatch("([^\t]*)\t") do parts[#parts + 1] = p end
        return { kind = parts[1], id = parts[2] or "", written = tonumber(parts[3]) or 0,
                 target = parts[4] or "", text = parts[5] or "" }
    end }, "defaults")
end)
check("9. a message on the wire is the log's record without from and arrived, byte for byte", function()
    local message = { id = "q7Kd2", written = 1730000000, kind = "message", target = "", text = AWKWARD }
    local wire = records.encode(message)
    local log_line = codecs.tsv.encode({ id = message.id, from = "me", written = message.written,
        arrived = 1730000005, kind = message.kind, target = message.target, text = message.text })
    local f = {}
    for p in log_line:gsub("\n$", ""):gmatch("([^\t]*)\t?") do f[#f + 1] = p end
    must(wire == table.concat({ f[5], f[1], f[3], f[6], f[7] }, "\t"), "wire " .. wire .. " / log " .. log_line)
end)
check("9. a record sealed, framed, read and opened comes back the same", function()
    local message = { kind = "correction", id = "x1", written = 1730000000, target = "q7Kd2", text = AWKWARD }
    local frame = seal.seal(PAIR, records.encode(message))
    local after = frames.read_frame(stand_in_reader(frame, 5))
    local back = records.decode(seal.open(PAIR, after))
    for name, value in pairs(message) do must(back[name] == value, name) end
end)

------------------------------------------------------------------------------
-- 10. Short writes (R10)
------------------------------------------------------------------------------

-- {{{ local function stand_in_writer
-- Takes 1-7 bytes per send, or none with a timeout (never PATIENCE times
-- in a row), the way a busy socket does.  conn.got holds what arrived.
local function stand_in_writer(seed)
    local conn = { got = {}, idle = 0, rng = seed }
    local function next_random(n)
        conn.rng = (conn.rng * 1103515245 + 12345) % 2147483648
        return conn.rng % n
    end
    function conn:send(data, i, j)
        if next_random(4) == 0 and self.idle < frames.PATIENCE - 1 then
            self.idle = self.idle + 1
            return nil, "timeout", i - 1
        end
        self.idle = 0
        local take = math.min(1 + next_random(7), j - i + 1)
        self.got[#self.got + 1] = data:sub(i, i + take - 1)
        local last = i + take - 1
        if last < j then return nil, "timeout", last end
        return last
    end
    return conn
end
-- }}}

-- {{{ referee 10
local function referee_writes(impl)
    for seed = 1, 30 do
        local frame = seal.seal(PAIR, "short writes, seed " .. seed)
        local conn = stand_in_writer(seed)
        must(impl.write(conn, frame), "the write gave up")
        local arrived = table.concat(conn.got)
        must(arrived == frame, "the frame arrived " .. #arrived .. " bytes of " .. #frame .. ", or changed")
        must(seal.open(PAIR, frames.read_frame(stand_in_reader(arrived, 3))) == "short writes, seed " .. seed,
            "the frame does not open")
    end
end
-- }}}

check("10. a frame written 1-7 bytes at a time, with timeouts, arrives whole and opens", function()
    referee_writes({ write = frames.write_frame })
end)
check("10. referee catches: adding the last byte's index as if it were a count", function()
    must_fail(referee_writes, { write = function(conn, frame)
        local next_byte = 1
        for _ = 1, 100000 do
            if next_byte > #frame then return true end
            local last, _, partial = conn:send(frame, next_byte, #frame)
            next_byte = next_byte + (last or partial or next_byte - 1)
        end
        return true
    end }, "index as count")
end)

------------------------------------------------------------------------------
-- Padding (the sealing note's referee 14)
------------------------------------------------------------------------------

local BUCKETS = {}
do
    local size = seal.PAD_FLOOR
    while size < seal.BODY_MAX do BUCKETS[size + 32] = true; size = size * 2 end
    BUCKETS[seal.BODY_MAX + 32] = true
end

-- {{{ referee 14
local function referee_padding(impl)
    local lengths = {}
    for n = 0, 1100 do lengths[#lengths + 1] = n end
    local size = 1024
    while size <= seal.BODY_MAX do
        for d = -1, 1 do lengths[#lengths + 1] = size - 32 + d end
        size = size * 2
    end
    lengths[#lengths + 1] = seal.BODY_MAX - 33
    lengths[#lengths + 1] = seal.BODY_MAX - 32
    for _, n in ipairs(lengths) do
        if n >= 0 and n <= seal.BODY_MAX - 32 then
            local record = string.rep("p", n)
            local frame = impl.seal(PAIR, record)
            must(BUCKETS[#frame], "a record of " .. n .. " bytes made a frame of " .. #frame .. " bytes, not a bucket size")
            must(seal.open(PAIR, frame:sub(5)) == record, "a padded record of " .. n .. " bytes did not open as itself")
        end
    end
end
-- }}}

check("14. every record length gives a frame of a documented size, and opens as itself", function()
    referee_padding({ seal = seal.seal })
end)
check("14. referee catches: padding appended after the check value", function()
    must_fail(referee_padding, { seal = function(pair, record)
        local f = seal.seal(pair, record, { pad = false })
        local wanted = seal.padded_size(#f - 32) + 32
        local padded = f .. string.rep("\0", wanted - #f)
        return seal.uint32_be(#padded - 4) .. padded:sub(5)
    end }, "padding outside the seal")
end)
check("14. padding that is not \"\\n\" and zero bytes is refused; an unpadded body is read", function()
    local bad = seal.gcm_encrypt(PAIR.key, string.rep("n", 12), PAIR.tie .. "hi\nzz")
    local _, tag = seal.gcm_encrypt(PAIR.key, string.rep("n", 12), PAIR.tie .. "hi\nzz")
    must(seal.open(PAIR, string.rep("n", 12) .. bad .. tag) == nil, "padding of letters was skipped")
    must(seal.open(PAIR, unpadded(PAIR, "plain"):sub(5)) == "plain", "an unpadded body was not read")
end)

os.execute("rm -rf '" .. SCRATCH .. "'")
print(string.format("counts %d %d", passed, failed))
os.exit(failed == 0 and 0 or 1)
