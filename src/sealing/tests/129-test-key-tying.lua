-- 129-test-key-tying.lua — the referees of issue 201a (the key-tying
-- value at the start of every sealed body), each run against the real
-- code and against a deliberately broken version it must catch.
--
-- Referee 1 builds, here in the test, a frame whose GCM check passes under
-- two room keys: the published construction (Dodis, Grubbs, Ristenpart and
-- Woodage 2018; Len, Grubbs and Ristenpart 2021), done with GCM's own
-- arithmetic in GF(2^128).  The arithmetic is checked against OpenSSL's
-- tags before it is used, so a mistake in it fails as a setup error, never
-- as a quiet pass.
--
-- Run: luajit src/sealing/tests/129-test-key-tying.lua [PROJECT_DIR]
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
local bit = require("bit")
local room_key = require("123-room-key")
local seal = require("124-seal")
local records = require("126-inner-records")
local keyring = require("127-keyring")
local rooms = require("002-room-folders")
local tokens = require("007-tokens")
local message_log = require("081-message-log")

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
-- A referee run against a broken version must raise an error.  What it
-- caught is printed under the check, so a broken version failing for the
-- wrong reason (a setup error) is seen.
local function must_fail(referee, broken, words)
    local ok, caught = pcall(referee, broken)
    if ok then error("the referee passed a broken version: " .. words, 2) end
    print("     caught: " .. tostring(caught):gsub("^[^:]*:%d+: ", ""))
end
-- }}}

------------------------------------------------------------------------------
-- GCM's arithmetic, for building a two-key frame
------------------------------------------------------------------------------

-- AES-256 on one block (for GCM's hash key H = E_K(0^128)).
for _, declaration in ipairs({
    "typedef struct evp_cipher_ctx_st EVP_CIPHER_CTX;",
    "typedef struct evp_cipher_st EVP_CIPHER;",
    "typedef struct engine_st ENGINE;",
    "EVP_CIPHER_CTX *EVP_CIPHER_CTX_new(void);",
    "void EVP_CIPHER_CTX_free(EVP_CIPHER_CTX *ctx);",
    "const EVP_CIPHER *EVP_aes_256_ecb(void);",
    "int EVP_EncryptInit_ex(EVP_CIPHER_CTX *ctx, const EVP_CIPHER *type, ENGINE *impl, const unsigned char *key, const unsigned char *iv);",
    "int EVP_EncryptUpdate(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl, const unsigned char *in, int inl);",
    "int EVP_CIPHER_CTX_set_padding(EVP_CIPHER_CTX *ctx, int padding);",
}) do
    local ok, problem = pcall(ffi.cdef, declaration)
    if not ok and not tostring(problem):match("redefine") then error(problem) end
end
local libcrypto = ffi.load("crypto")

-- {{{ local function aes_block
local function aes_block(key, block)
    local ctx = libcrypto.EVP_CIPHER_CTX_new()
    local out = ffi.new("unsigned char[32]")
    local outl = ffi.new("int[1]")
    local ok = libcrypto.EVP_EncryptInit_ex(ctx, libcrypto.EVP_aes_256_ecb(), nil, key, nil) == 1
        and libcrypto.EVP_CIPHER_CTX_set_padding(ctx, 0) == 1
        and libcrypto.EVP_EncryptUpdate(ctx, out, outl, block, 16) == 1
    libcrypto.EVP_CIPHER_CTX_free(ctx)
    if not ok or outl[0] ~= 16 then error("setup: AES-256-ECB failed in libcrypto") end
    return ffi.string(out, 16)
end
-- }}}

-- {{{ local function xor
local function xor(a, b)
    local out = {}
    for i = 1, #a do out[i] = string.char(bit.bxor(a:byte(i), b:byte(i))) end
    return table.concat(out)
end
-- }}}

-- {{{ local function gf_mul
-- Multiplication in GF(2^128) in GCM's bit order (NIST SP 800-38D,
-- algorithm 1): bit 0 is the high bit of the first byte, R = 0xE1 || 0^120.
local function gf_mul(x, y)
    local z = {}
    local v = {}
    for i = 1, 16 do z[i] = 0; v[i] = y:byte(i) end
    for i = 0, 127 do
        if bit.band(x:byte(math.floor(i / 8) + 1), bit.rshift(0x80, i % 8)) ~= 0 then
            for k = 1, 16 do z[k] = bit.bxor(z[k], v[k]) end
        end
        local low = bit.band(v[16], 1)
        for k = 16, 2, -1 do
            v[k] = bit.bor(bit.rshift(v[k], 1), bit.lshift(bit.band(v[k - 1], 1), 7))
        end
        v[1] = bit.rshift(v[1], 1)
        if low == 1 then v[1] = bit.bxor(v[1], 0xE1) end
    end
    local out = {}
    for i = 1, 16 do out[i] = string.char(z[i]) end
    return table.concat(out)
end
-- }}}

local ONE = "\128" .. string.rep("\0", 15)       -- the polynomial 1
local ZERO_BLOCK = string.rep("\0", 16)

-- {{{ local function gf_inverse
-- a^(2^128 - 2) = a^2 · a^4 · ... · a^(2^127): the inverse of a ≠ 0.
local function gf_inverse(a)
    local result, power = ONE, a
    for _ = 1, 127 do
        power = gf_mul(power, power)
        result = gf_mul(result, power)
    end
    return result
end
-- }}}

-- {{{ local function ghash
-- GHASH with no additional data: the ciphertext's blocks, then the length
-- block (0 as 64 bits, the ciphertext's length in bits as 64 bits).
local function ghash(h, ciphertext)
    assert(#ciphertext % 16 == 0, "whole blocks only")
    local x = ZERO_BLOCK
    for i = 1, #ciphertext, 16 do x = gf_mul(xor(x, ciphertext:sub(i, i + 15)), h) end
    local bits = #ciphertext * 8
    local length_block = string.rep("\0", 12) .. seal.uint32_be(bits)
    return gf_mul(xor(x, length_block), h)
end
-- }}}

-- {{{ local function gcm_parts
-- One key and nonce → what GCM's tag is made of: H, E_K(J0) (the tag of an
-- empty message), and `blocks` blocks of keystream (zeros encrypted).
local function gcm_parts(key, iv, blocks)
    local h = aes_block(key, ZERO_BLOCK)
    local _, masked_j0 = seal.gcm_encrypt(key, iv, "")
    local keystream = seal.gcm_encrypt(key, iv, string.rep("\0", 16 * blocks))
    return { h = h, j0 = masked_j0, keystream = keystream }
end
-- }}}

-- The record the two-key frame carries for room A: 16 bytes of a message
-- record's fixed fields, then 16 bytes the construction solves for, read
-- as the message's text.
local RECORD_HEAD = "message\tx2k\t17\t\t"
assert(#RECORD_HEAD == 16)

-- {{{ local function two_key_frame
-- pair_a, pair_b → after_length (nonce, sealed body, tag) whose GCM check
-- passes under both keys, and whose body opened under A's key is A's tying
-- value, RECORD_HEAD and 16 solved bytes; and that record.
--
-- The body is four blocks C1..C4.  C1..C3 are fixed by what A's opening
-- must read (tying value and record head, each xor A's keystream).  GCM's
-- tag under a key K is E_K(J0) + C1·H^5 + C2·H^4 + C3·H^3 + C4·H^2 + L·H,
-- linear in C4; so with t_K the tag computed with C4 = 0,
--     t_A + C4·H_A^2 = t_B + C4·H_B^2   gives   C4 = (t_A + t_B) / (H_A^2 + H_B^2).
-- A fresh nonce is drawn until A's 16 solved bytes hold no tab, line break
-- or backslash, so the record reads as a message (about 1 try in 6 redrawn).
local function two_key_frame(pair_a, pair_b)
    for _ = 1, 200 do
        local iv = seal.nonce()
        local a = gcm_parts(pair_a.key, iv, 4)
        local b = gcm_parts(pair_b.key, iv, 4)
        local fixed = xor(pair_a.tie .. RECORD_HEAD, a.keystream:sub(1, 48))
        local tag_a0 = xor(a.j0, ghash(a.h, fixed .. ZERO_BLOCK))
        local tag_b0 = xor(b.j0, ghash(b.h, fixed .. ZERO_BLOCK))
        local denominator = xor(gf_mul(a.h, a.h), gf_mul(b.h, b.h))
        local c4 = gf_mul(xor(tag_a0, tag_b0), gf_inverse(denominator))
        local ciphertext = fixed .. c4
        local tag = xor(a.j0, ghash(a.h, ciphertext))
        local solved = xor(c4, a.keystream:sub(49, 64))
        if not solved:find("[\t\n\\]") then
            return iv .. ciphertext .. tag, RECORD_HEAD .. solved
        end
    end
    error("setup: no nonce gave a readable record in 200 tries")
end
-- }}}

-- The arithmetic is checked against OpenSSL before any referee uses it.
check("setup: GF(2^128) inverse, GHASH and the tag agree with OpenSSL's AES-256-GCM", function()
    local key = room_key.room_key("arithmetic check")
    local some = aes_block(key, string.rep("\7", 16))
    must(gf_mul(some, gf_inverse(some)) == ONE, "a · a^-1 is not 1")
    must(gf_mul(ONE, some) == some and gf_mul(some, ONE) == some, "1 is not the identity")
    for _, blocks in ipairs({ 1, 2, 4, 7 }) do
        local iv = seal.nonce()
        local plain = seal.nonce():rep(2):sub(1, 16):rep(blocks)
        local ciphertext, tag = seal.gcm_encrypt(key, iv, plain)
        local parts = gcm_parts(key, iv, blocks)
        must(xor(plain, parts.keystream) == ciphertext, "the keystream is not zeros encrypted")
        must(xor(parts.j0, ghash(parts.h, ciphertext)) == tag,
            "GHASH does not give OpenSSL's tag for " .. blocks .. " blocks")
    end
end)

------------------------------------------------------------------------------
-- The openers: the real one, and broken ones
------------------------------------------------------------------------------

-- {{{ local function open_gcm_only
-- Broken: GCM's check alone decides; the first 32 bytes are cut off
-- unread (the first key to pass wins, as in rmail).
local function open_gcm_only(pair, after_length)
    if #after_length < seal.MIN_LENGTH then return nil end
    local body = seal.gcm_decrypt(pair.key, after_length:sub(1, 12), after_length:sub(13, -17),
        after_length:sub(-16))
    if body == nil then return nil end
    local rest = body:sub(room_key.TIE_BYTES + 1)
    local stop = rest:find("\n", 1, true)
    if stop then return rest:sub(1, stop - 1) end
    return rest
end
-- }}}

-- {{{ local function open_without_strip
-- Broken: checks everything, then hands on the body with the tying value
-- still in front of the record.
local function open_without_strip(pair, after_length)
    local record = seal.open(pair, after_length)
    if record == nil then return nil end
    return pair.tie .. record
end
-- }}}

local PAIR_A = room_key.key_pair("two-key room A")
local PAIR_B = room_key.key_pair("two-key room B")
local TWO_KEY, TWO_KEY_RECORD = two_key_frame(PAIR_A, PAIR_B)

------------------------------------------------------------------------------
-- 1. Two keys, one frame
------------------------------------------------------------------------------

-- {{{ referee 1
-- impl: {open = function(pair, after_length) → record or nil}
local function referee_two_keys(impl)
    -- the frame really is a two-key frame (a setup check, not the referee's)
    local nonce, sealed, tag = TWO_KEY:sub(1, 12), TWO_KEY:sub(13, -17), TWO_KEY:sub(-16)
    must(seal.gcm_decrypt(PAIR_A.key, nonce, sealed, tag) ~= nil, "setup: GCM refuses the frame under A's key")
    must(seal.gcm_decrypt(PAIR_B.key, nonce, sealed, tag) ~= nil, "setup: GCM refuses the frame under B's key")
    for _, order in ipairs({ { "B", "A" }, { "A", "B" } }) do
        local list = {}
        for _, label in ipairs(order) do
            list[#list + 1] = { room = label, token = "two-key room " .. label }
        end
        local ring = keyring.from_tokens(list)
        for _, workers in ipairs({ 1, 2 }) do
            local room, record = keyring.open_frame(ring, TWO_KEY, workers, impl.open)
            must(room == "A", "trying " .. order[1] .. " first with " .. workers
                .. " worker(s), the frame was filed under " .. tostring(room))
            must(record == TWO_KEY_RECORD, "room A's record did not come back as built")
            local message = records.decode(record)
            must(message.kind == "message" and message.id == "x2k", "the record does not read as a message")
        end
    end
    must(impl.open(PAIR_B, TWO_KEY) == nil, "B's key opened a frame whose body begins with A's tying value")
end
-- }}}

check("1. a frame passing GCM under two keys opens as the room whose tying value it holds, in either order", function()
    referee_two_keys({ open = seal.open })
end)
check("1. referee catches: GCM's check alone (the first key to pass wins)", function()
    must_fail(referee_two_keys, { open = open_gcm_only }, "GCM only")
end)
check("1. the wrong room's key gives the same answer as a failed check: nothing, and a reason", function()
    local record, reason = seal.open(PAIR_B, TWO_KEY)
    must(record == nil and reason == "the tying value is another room's", tostring(reason))
    local _, failed_reason = seal.open(room_key.key_pair("a third room"), TWO_KEY)
    must(failed_reason == "the check value does not match", tostring(failed_reason))
end)

------------------------------------------------------------------------------
-- 2. The value is stripped
------------------------------------------------------------------------------

local SCRATCH = DIR .. "/tmp/shared-memory/key-tying"
os.execute("rm -rf '" .. SCRATCH .. "' && mkdir -p '" .. SCRATCH .. "'")
local HOME = rooms.open_home(SCRATCH .. "/home")
rooms.set_config(HOME, "log.duplicate-check", "scan")
local STRIP_TOKEN = "strip check room"
local STRIP_ROOM = rooms.make_room(HOME, { label = "strip check", token = STRIP_TOKEN, kind = "group",
    parent = "", members = {}, filed_under = "", mailbox_port = 7401 })
local STRIP_PAIR = room_key.key_pair(rooms.read_entry(HOME, STRIP_ROOM).token)

-- {{{ local function read_file
local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local all = file:read("*a")
    file:close()
    return all
end
-- }}}

-- {{{ referee 2
-- impl: {open}.  Seals messages, opens them, files them in a room's log:
-- the record and the log hold exactly the text sealed, and never the
-- tying value.
local function referee_stripped(impl)
    local texts = { "", "short", "a line\twith a tab and a \\ backslash", string.rep("long ", 400) }
    for index, text in ipairs(texts) do
        local sent = { kind = "message", id = "strip" .. index, written = 1730000000 + index, target = "", text = text }
        local after = seal.seal(STRIP_PAIR, records.encode(sent)):sub(5)
        local record = impl.open(STRIP_PAIR, after)
        must(record ~= nil, "the frame did not open")
        must(not record:find(STRIP_PAIR.tie, 1, true), "the opened record holds the tying value")
        local back = records.decode(record)
        must(back.text == text, "the text came back different")
        must(message_log.append(HOME, STRIP_ROOM, { id = back.id, from = "127.0.0.1 7402", written = back.written,
            arrived = 1730000100, text = back.text }) == "filed", "the message was not filed")
    end
    local log_bytes = read_file(rooms.log_path(HOME, STRIP_ROOM))
    must(not log_bytes:find(STRIP_PAIR.tie, 1, true), "the log file holds the tying value")
    for line in log_bytes:gmatch("[^\n]+") do
        must(line:sub(1, room_key.TIE_BYTES) ~= STRIP_PAIR.tie, "a log line starts with the tying value")
    end
end
-- }}}

check("2. a message sealed, opened and filed holds exactly its text; no record or log line holds the tying value", function()
    referee_stripped({ open = seal.open })
end)
check("2. referee catches: an opener that forgets to strip", function()
    must_fail(referee_stripped, { open = open_without_strip }, "no strip")
end)

------------------------------------------------------------------------------
-- 3. Early stop is correct
------------------------------------------------------------------------------

local ROOM_COUNT = 1000
local B_AT, A_AT = 400, 700      -- the two-key frame's rooms, B tried first

-- {{{ local function big_ring
local function big_ring()
    local list = {}
    for k = 1, ROOM_COUNT do
        local token = "room number " .. k
        if k == B_AT then token = "two-key room B" end
        if k == A_AT then token = "two-key room A" end
        list[k] = { room = k, token = token }
    end
    return keyring.from_tokens(list)
end
-- }}}
local RING = big_ring()

-- {{{ referee 3
-- impl: {open}.  With one worker the trial goes in keyring order, so a
-- frame for room k is tried against exactly k keys; random bytes against
-- all of them.  The two-key frame comes first: an early stop on GCM alone
-- passes every honest frame and fails only there.
local function referee_early_stop(impl)
    local room, _, tried = keyring.open_frame(RING, TWO_KEY, 1, impl.open)
    must(room == A_AT, "the two-key frame was filed under room " .. tostring(room) .. ", not " .. A_AT)
    must(tried == A_AT, "the two-key frame tried " .. tried .. " keys, not " .. A_AT)
    for k = 1, ROOM_COUNT do
        local entry = RING.entries[k]
        local after = seal.seal(entry, "for room " .. k):sub(5)
        local opened_room, record, count = keyring.open_frame(RING, after, 1, impl.open)
        must(opened_room == k and record == "for room " .. k, "room " .. k .. "'s frame opened as " .. tostring(opened_room))
        must(count <= k, "room " .. k .. "'s frame tried " .. count .. " keys")
        -- several workers: the answer is the same (each slice stops at its own first opening)
        if k % 97 == 0 then
            must(keyring.open_frame(RING, after, 4, impl.open) == k, "four workers disagree on room " .. k)
        end
    end
    local noise = seal.nonce():rep(30)
    local none, _, all = keyring.open_frame(RING, noise, 1, impl.open)
    must(none == nil and all == ROOM_COUNT, "random bytes opened, or tried " .. all .. " keys")
end
-- }}}

check("3. in 1,000 rooms each frame opens as its room after at most its position's keys; noise tries all", function()
    referee_early_stop({ open = seal.open })
end)
check("3. referee catches: an early stop on GCM success alone", function()
    must_fail(referee_early_stop, { open = open_gcm_only }, "GCM-only early stop")
end)

------------------------------------------------------------------------------
-- 4. The raw token is never in the body
------------------------------------------------------------------------------

-- {{{ local function opened_body
-- The whole GCM plaintext of a frame (tying value, record, padding).
local function opened_body(key, frame)
    local after = frame:sub(5)
    return seal.gcm_decrypt(key, after:sub(1, 12), after:sub(13, -17), after:sub(-16))
end
-- }}}

-- {{{ referee 4
-- impl: {seal = function(token, record) → frame}.  For a room whose token
-- is a known short string, the opened body holds neither the token nor
-- the key, and begins with the fingerprint's bytes.
local function referee_no_token(impl)
    local token = "coffee"
    local key = room_key.room_key(token)
    local fingerprint = tokens.token_fingerprint(token)
    for index = 1, 40 do
        local body = opened_body(key, impl.seal(token, "a line about tea, number " .. index))
        must(body ~= nil, "the frame did not open under the room's key")
        must(not body:find(token, 1, true), "the opened body holds the raw token")
        must(not body:find(key, 1, true), "the opened body holds the key")
        local first = body:sub(1, 32):gsub(".", function(c) return string.format("%02x", c:byte()) end)
        must(first == fingerprint, "the body does not begin with the room's fingerprint")
    end
end
-- }}}

check("4. the opened body begins with the fingerprint and holds neither the token nor the key", function()
    referee_no_token({ seal = function(token, record) return seal.seal(room_key.key_pair(token), record) end })
end)
check("4. referee catches: the raw token in front of the record", function()
    must_fail(referee_no_token, { seal = function(token, record)
        local key = room_key.room_key(token)
        local iv = seal.nonce()
        local ciphertext, tag = seal.gcm_encrypt(key, iv, token .. record)
        local after = iv .. ciphertext .. tag
        return seal.uint32_be(#after) .. after
    end }, "raw token")
end)

os.execute("rm -rf '" .. SCRATCH .. "'")
print(string.format("counts %d %d", passed, failed))
os.exit(failed == 0 and 0 or 1)
