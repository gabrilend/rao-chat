-- 124-seal.lua — sealing one inner record into a frame, and opening it
-- (issue 201, steps 2 and the frame's layout; 201a's tying value).
--
-- A frame, outside to inside:
--
--   length       4 bytes, big-endian, in the clear: how many bytes follow
--                it (nonce + sealed body + check value).  At least 28, at
--                most CAP.
--   nonce        12 bytes, in the clear, fresh from the operating system
--                for every frame (getrandom(2)), never a counter and never
--                a generator seeded once: every member seals with the same
--                room key on their own, so only random nonces are safe (R1).
--   sealed body  AES-256-GCM under the room key.  Inside it:
--                  tying value  32 bytes, the room's (123), checked after
--                               opening and stripped (201a)
--                  record       the inner record (126), one line, no "\n"
--                  padding      absent, or "\n" then zero bytes up to the
--                               body's size (see PADDING below)
--   check value  16 bytes, in the clear: GCM's tag over the sealed body.
--
-- Opening either gives the record or gives nothing (R2): the plaintext is
-- turned into a Lua string only after GCM's check has passed, and only
-- after the tying value matches is it handed on.
--
-- AES-256-GCM comes from the system's OpenSSL (libcrypto) through LuaJIT's
-- ffi, as 007-tokens takes SHA-256 from it.
--
-- PADDING (decision of 2026-11-05, issue 201 open question 2; the owner
-- may overturn it).  Chat lines are short and patterned, so a frame's
-- length would tell an observer roughly what was said.  The sealed body is
-- padded to the next power of two, at least 256 bytes, so every short line
-- looks alike; a body that would pass 512 KiB is padded to BODY_MAX.  The
-- padding is a "\n" and zero bytes: a record never holds a raw "\n" (the
-- log's escaping), so the first "\n" ends the record without a length
-- field.  A reader accepts a body with or without padding, so turning it
-- off, or changing the sizes, changes only the writer.  Padding that is
-- not exactly "\n" and zeros is refused, never skipped.
--
-- CAP (same decision).  rao-chat carries text, not attachments: the cap is
-- 1 MiB (rmail's daemon allows 64 MiB, its phone 16 MiB).  A garbage frame
-- costs a receiver work in proportion to its size times the keys it tries
-- (R12), so the smaller cap cuts that 64 times.  Every reader in the
-- project reads CAP from here.

local ffi = require("ffi")
local room_key = require("123-room-key")

-- Declared one at a time, as in 007-tokens: another module may already
-- have declared one, and only "redefine" is an acceptable complaint.
local C_DECLARATIONS = {
    "typedef struct evp_cipher_ctx_st EVP_CIPHER_CTX;",
    "typedef struct evp_cipher_st EVP_CIPHER;",
    "typedef struct engine_st ENGINE;",
    "EVP_CIPHER_CTX *EVP_CIPHER_CTX_new(void);",
    "void EVP_CIPHER_CTX_free(EVP_CIPHER_CTX *ctx);",
    "const EVP_CIPHER *EVP_aes_256_gcm(void);",
    "int EVP_EncryptInit_ex(EVP_CIPHER_CTX *ctx, const EVP_CIPHER *type, ENGINE *impl, const unsigned char *key, const unsigned char *iv);",
    "int EVP_EncryptUpdate(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl, const unsigned char *in, int inl);",
    "int EVP_EncryptFinal_ex(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl);",
    "int EVP_DecryptInit_ex(EVP_CIPHER_CTX *ctx, const EVP_CIPHER *type, ENGINE *impl, const unsigned char *key, const unsigned char *iv);",
    "int EVP_DecryptUpdate(EVP_CIPHER_CTX *ctx, unsigned char *out, int *outl, const unsigned char *in, int inl);",
    "int EVP_DecryptFinal_ex(EVP_CIPHER_CTX *ctx, unsigned char *outm, int *outl);",
    "int EVP_CIPHER_CTX_ctrl(EVP_CIPHER_CTX *ctx, int type, int arg, void *ptr);",
    "long getrandom(void *buf, size_t buflen, unsigned int flags);",
}
for _, declaration in ipairs(C_DECLARATIONS) do
    local ok, problem = pcall(ffi.cdef, declaration)
    -- ok: newly declared.  "redefine": declared elsewhere, usable.
    -- anything else: a real problem, stop the load.
    if not ok and not tostring(problem):match("redefine") then
        error(problem)
    end
end

local libcrypto = ffi.load("crypto")

-- OpenSSL's control codes for GCM's check value (evp.h).
local GCM_GET_TAG = 0x10
local GCM_SET_TAG = 0x11

local NONCE_BYTES = 12
local TAG_BYTES = 16
local LENGTH_BYTES = 4
local MIN_LENGTH = NONCE_BYTES + TAG_BYTES       -- 28: an empty body
local CAP = 1024 * 1024                          -- the largest length
local BODY_MAX = CAP - MIN_LENGTH                -- the largest sealed body
local PAD_FLOOR = 256                            -- the smallest padded body

-- {{{ local function nonce
-- 12 bytes from the kernel, every call.  getrandom(2) keeps no state in
-- this process, so two processes (or a forked copy of this one) never
-- share a sequence, as a buffered read of /dev/urandom would after a fork.
local function nonce()
    local buffer = ffi.new("unsigned char[?]", NONCE_BYTES)
    local got = tonumber(ffi.C.getrandom(buffer, NONCE_BYTES, 0))
    -- short or failed: never seal with a nonce that is not wholly random.
    if got ~= NONCE_BYTES then
        error("seal: getrandom gave " .. tostring(got) .. " bytes, wanted " .. NONCE_BYTES, 2)
    end
    return ffi.string(buffer, NONCE_BYTES)
end
-- }}}

-- {{{ local function check_bytes
local function check_bytes(value, length, what)
    if type(value) ~= "string" or #value ~= length then
        error("seal: " .. what .. " must be " .. length .. " bytes, got " .. tostring(value and #tostring(value)), 3)
    end
end
-- }}}

-- {{{ local function gcm_encrypt
-- key (32 bytes), iv (12 bytes), plain (string) → ciphertext, tag (16).
local function gcm_encrypt(key, iv, plain)
    check_bytes(key, 32, "a key")
    check_bytes(iv, NONCE_BYTES, "a nonce")
    local ctx = libcrypto.EVP_CIPHER_CTX_new()
    if ctx == nil then error("seal: EVP_CIPHER_CTX_new failed", 2) end
    local out = ffi.new("unsigned char[?]", #plain + 16)
    local outl = ffi.new("int[1]")
    local tag = ffi.new("unsigned char[?]", TAG_BYTES)
    local ok = libcrypto.EVP_EncryptInit_ex(ctx, libcrypto.EVP_aes_256_gcm(), nil, key, iv) == 1
        and libcrypto.EVP_EncryptUpdate(ctx, out, outl, plain, #plain) == 1
    local written = outl[0]
    ok = ok and libcrypto.EVP_EncryptFinal_ex(ctx, out + written, outl) == 1
    written = written + (ok and outl[0] or 0)
    ok = ok and libcrypto.EVP_CIPHER_CTX_ctrl(ctx, GCM_GET_TAG, TAG_BYTES, tag) == 1
    libcrypto.EVP_CIPHER_CTX_free(ctx)
    if not ok then error("seal: AES-256-GCM sealing failed in libcrypto", 2) end
    return ffi.string(out, written), ffi.string(tag, TAG_BYTES)
end
-- }}}

-- {{{ local function gcm_decrypt
-- key, iv, ciphertext, tag → plain, or nil when the check value does not
-- match.  The plaintext buffer is read into a Lua string only after
-- EVP_DecryptFinal_ex has accepted the tag: before that, nothing leaves.
local function gcm_decrypt(key, iv, ciphertext, tag)
    check_bytes(key, 32, "a key")
    if #iv ~= NONCE_BYTES or #tag ~= TAG_BYTES then return nil end
    local ctx = libcrypto.EVP_CIPHER_CTX_new()
    if ctx == nil then error("seal: EVP_CIPHER_CTX_new failed", 2) end
    local out = ffi.new("unsigned char[?]", #ciphertext + 16)
    local outl = ffi.new("int[1]")
    local tag_buffer = ffi.new("unsigned char[?]", TAG_BYTES)
    ffi.copy(tag_buffer, tag, TAG_BYTES)
    local ok = libcrypto.EVP_DecryptInit_ex(ctx, libcrypto.EVP_aes_256_gcm(), nil, key, iv) == 1
        and libcrypto.EVP_DecryptUpdate(ctx, out, outl, ciphertext, #ciphertext) == 1
    local written = outl[0]
    ok = ok and libcrypto.EVP_CIPHER_CTX_ctrl(ctx, GCM_SET_TAG, TAG_BYTES, tag_buffer) == 1
    -- Path: the tag is checked here; only a pass lets the bytes out.
    ok = ok and libcrypto.EVP_DecryptFinal_ex(ctx, out + written, outl) == 1
    libcrypto.EVP_CIPHER_CTX_free(ctx)
    if not ok then return nil end
    return ffi.string(out, written + outl[0])
end
-- }}}

-- {{{ local function padded_size
-- The size a sealed body of `needed` bytes (tying value and record) is
-- padded to: the next power of two, at least PAD_FLOOR, at most BODY_MAX.
local function padded_size(needed)
    if needed > BODY_MAX then
        error("seal: a body of " .. needed .. " bytes is over the cap (" .. BODY_MAX .. ")", 2)
    end
    local size = PAD_FLOOR
    while size < needed do size = size * 2 end
    return math.min(size, BODY_MAX)
end
-- }}}

-- {{{ local function uint32_be
local function uint32_be(n)
    return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
                       math.floor(n / 256) % 256, n % 256)
end
-- }}}

-- {{{ local function read_uint32_be
local function read_uint32_be(bytes)
    local a, b, c, d = bytes:byte(1, 4)
    return ((a * 256 + b) * 256 + c) * 256 + d
end
-- }}}

-- {{{ local function seal
-- pair ({key, tie} from 123's key_pair), record (string, one line: no
-- "\n"), options ({pad = false} to leave the body unpadded; padded by
-- default) → the whole frame, length first.
local function seal(pair, record, options)
    if type(record) ~= "string" or record:find("\n", 1, true) then
        error("seal: a record is one line of text (the log's escaping keeps \\n out of it)", 2)
    end
    check_bytes(pair and pair.tie, room_key.TIE_BYTES, "a tying value")
    local body = pair.tie .. record
    local pad = not (options and options.pad == false)
    if #body > BODY_MAX then
        error("seal: a record of " .. #record .. " bytes does not fit under the cap", 2)
    end
    -- Path: padding on and the body short of its size — "\n" and zeros.
    -- Exactly at its size, or padding off — the body as it is.
    if pad then
        local size = padded_size(#body)
        if size > #body then body = body .. "\n" .. string.rep("\0", size - #body - 1) end
    end
    local iv = nonce()
    local ciphertext, tag = gcm_encrypt(pair.key, iv, body)
    local after_length = iv .. ciphertext .. tag
    return uint32_be(#after_length) .. after_length
end
-- }}}

-- {{{ local function open
-- pair, after_length (the frame without its 4 length bytes) → the record,
-- or nil and a reason.  Nothing of the plaintext is returned unless GCM's
-- check passed, the tying value is this pair's, and the padding (if any)
-- is "\n" and zeros.
local function open(pair, after_length)
    if type(after_length) ~= "string" or #after_length < MIN_LENGTH or #after_length > CAP then
        return nil, "not a frame's length"
    end
    local iv = after_length:sub(1, NONCE_BYTES)
    local ciphertext = after_length:sub(NONCE_BYTES + 1, -TAG_BYTES - 1)
    local tag = after_length:sub(-TAG_BYTES)
    local body = gcm_decrypt(pair.key, iv, ciphertext, tag)
    -- Path: the check value failed — nothing.  Passed — go on.
    if body == nil then return nil, "the check value does not match" end
    if body:sub(1, room_key.TIE_BYTES) ~= pair.tie then
        return nil, "the tying value is another room's"
    end
    local rest = body:sub(room_key.TIE_BYTES + 1)
    local stop = rest:find("\n", 1, true)
    -- Path: no "\n" — no padding, the whole rest is the record.  A "\n" —
    -- the record ends there and only zero bytes may follow.
    if stop == nil then return rest end
    if rest:find("[^%z]", stop + 1) then return nil, "the padding is not zero bytes" end
    return rest:sub(1, stop - 1)
end
-- }}}

return {
    seal = seal,
    open = open,
    nonce = nonce,
    padded_size = padded_size,
    gcm_encrypt = gcm_encrypt,
    gcm_decrypt = gcm_decrypt,
    uint32_be = uint32_be,
    read_uint32_be = read_uint32_be,
    NONCE_BYTES = NONCE_BYTES,
    TAG_BYTES = TAG_BYTES,
    LENGTH_BYTES = LENGTH_BYTES,
    MIN_LENGTH = MIN_LENGTH,
    CAP = CAP,
    BODY_MAX = BODY_MAX,
    PAD_FLOOR = PAD_FLOOR,
}
