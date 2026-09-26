-- 007-tokens.lua — a room's token: its fingerprint, and readable suggestions.
--
-- A room's token is its shared secret: whoever holds it is invited.  Two
-- things are done with a token here, neither of which stores anything.
--
-- The fingerprint.  A child room has to name its parent without handing
-- out the parent's token.  So it names the parent by a fingerprint: the
-- token put through a one-way scrambler (SHA-256) twice.  Once gives the
-- room's sealing key (phase 2, exactly as rmail makes a key from a
-- contact's token); the second time turns the key into something that can
-- be shown to anyone.  Anyone holding the token gets the same fingerprint
-- on any machine; nobody can run the scrambler backwards to get the token
-- or the key.  The scrambler is borrowed from the system's OpenSSL library
-- (libcrypto) through LuaJIT's ffi, the same library rmail seals with.
--
-- The suggestion.  Tokens may be any text the maker types, but typing a
-- good random one is hard, so rao-chat offers one made of random common
-- words joined by dashes, easy to read aloud over the phone:
-- "maple-orbit-velvet-tin".  The words come from the EFF's passphrase list
-- (assets/eff-large-wordlist.txt; its origin and licence are in
-- assets/eff-large-wordlist.about.md), chosen with the kernel's random
-- source.  Each word adds about 12.9 bits of guessing work.

local ffi = require("ffi")

-- Declared one at a time: another module may already have declared the
-- same C function, and LuaJIT refuses a second declaration; "redefine" is
-- the only complaint accepted.
local C_DECLARATIONS = {
    "unsigned char *SHA256(const unsigned char *data, size_t length, unsigned char *digest);",
}
for _, declaration in ipairs(C_DECLARATIONS) do
    local ok, problem = pcall(ffi.cdef, declaration)
    -- ok: newly declared.  "redefine": already declared elsewhere, usable.
    -- anything else: a real problem, stop the load.
    if not ok and not tostring(problem):match("redefine") then
        error(problem)
    end
end

-- libcrypto is loaded when this file is; a machine without OpenSSL fails
-- here, at once, rather than at the first room made.
local libcrypto = ffi.load("crypto")

-- The project folder, worked out from where this file sits
-- (<project>/src/room-folders/007-tokens.lua), so the word list is found
-- whichever folder the program was started from.
local THIS_FILE = debug.getinfo(1, "S").source:gsub("^@", "")
local PROJECT_DIR = THIS_FILE:match("^(.*)/src/room%-folders/[^/]+$")
if PROJECT_DIR == nil then
    error("007-tokens.lua must live at <project>/src/room-folders/, found at " .. THIS_FILE)
end
local WORD_LIST_PATH = PROJECT_DIR .. "/assets/eff-large-wordlist.txt"

-- The separator between suggested words.  The word list holds letters
-- only, so a dash can never be mistaken for part of a word.
local WORD_SEPARATOR = "-"

-- {{{ local function to_hex
local function to_hex(bytes)
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
-- }}}

-- {{{ local function sha256
-- text (string, any bytes) → 32 raw bytes (string).
local function sha256(text)
    local digest = ffi.new("unsigned char[32]")
    libcrypto.SHA256(text, #text, digest)
    return ffi.string(digest, 32)
end
-- }}}

-- {{{ local function check_token
-- A token is any non-empty text on one line.  It is written into the
-- entry on one line, so a line break would split it.
local function check_token(token)
    if type(token) ~= "string" or token == "" then
        error("a token must be a non-empty string, got " .. tostring(token), 3)
    end
    if token:find("[\r\n]") then
        error("a token may hold any characters but a line break", 3)
    end
end
-- }}}

-- {{{ local function token_fingerprint
-- token (string) → 64 lower-case hex characters: SHA-256(SHA-256(token)).
-- The inner SHA-256 is the sealing key (raw bytes, as rmail uses it); the
-- outer one is over those 32 raw bytes, not over their hex spelling.
local function token_fingerprint(token)
    check_token(token)
    return to_hex(sha256(sha256(token)))
end
-- }}}

-- {{{ local function is_fingerprint
local function is_fingerprint(value)
    return type(value) == "string" and #value == 64 and value:match("^[0-9a-f]+$") ~= nil
end
-- }}}

-- The word list, read once on first use and kept: it never changes while
-- the program runs.
local word_list = nil

-- {{{ local function load_word_list
-- Reads and checks the list: letters a–z only, no repeats, nothing empty.
-- A damaged list would quietly weaken every suggestion (a repeated word
-- is a likelier word), so any flaw stops the load.
local function load_word_list()
    local handle, problem = io.open(WORD_LIST_PATH, "rb")
    -- no file: the asset is missing from this copy of the project.
    if not handle then
        error("cannot open the word list " .. WORD_LIST_PATH .. ": " .. tostring(problem), 3)
    end
    local words, seen = {}, {}
    local number = 0
    for line in handle:lines() do
        number = number + 1
        -- not a plain lower-case word: refuse, naming the line.
        if not line:match("^[a-z]+$") then
            handle:close()
            error(WORD_LIST_PATH .. " line " .. number .. ": not a lower-case word: " .. string.format("%q", line), 3)
        end
        -- seen before: a repeat.
        if seen[line] then
            handle:close()
            error(WORD_LIST_PATH .. " line " .. number .. ": '" .. line .. "' appears twice", 3)
        end
        seen[line] = true
        words[#words + 1] = line
    end
    handle:close()
    -- an empty list cannot suggest anything.
    if #words < 2 then
        error("the word list " .. WORD_LIST_PATH .. " holds fewer than two words", 3)
    end
    return words
end
-- }}}

-- {{{ local function words
-- The checked word list (list of string), loading it the first time.
local function words()
    -- not loaded yet: load now.  Loaded: reuse.
    if word_list == nil then
        word_list = load_word_list()
    end
    return word_list
end
-- }}}

-- {{{ local function random_below
-- A whole number from 1 to n, every value equally likely, from the
-- kernel's random source.  Four random bytes make a number from 0 to
-- 2^32-1; values at or past the largest multiple of n that fits are
-- thrown away and drawn again, because keeping them would make the first
-- few words slightly likelier ("modulo bias").
local function random_below(source, n)
    local range = 4294967296
    local limit = range - (range % n)
    while true do
        local bytes = source:read(4)
        -- a short read: the random source failed; never guess instead.
        if bytes == nil or #bytes ~= 4 then
            error("could not read 4 bytes from /dev/urandom", 3)
        end
        local b1, b2, b3, b4 = bytes:byte(1, 4)
        local value = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
        -- below the limit: fair, use it.  At or above: draw again.
        if value < limit then
            return (value % n) + 1
        end
    end
end
-- }}}

-- {{{ local function suggest_token_of
-- word_count (integer ≥ 1) → a string of that many random words joined by
-- "-".  Words may repeat within one suggestion (each is drawn
-- independently, which is what makes each word worth its full 12.9 bits).
local function suggest_token_of(word_count)
    -- not a positive whole number: a count cannot be guessed.
    if type(word_count) ~= "number" or word_count < 1 or word_count % 1 ~= 0 then
        error("suggest_token_of needs a whole number of words ≥ 1, got " .. tostring(word_count), 2)
    end
    local list = words()
    local source, problem = io.open("/dev/urandom", "rb")
    -- no random source: refuse rather than suggest a guessable token.
    if not source then
        error("cannot open /dev/urandom: " .. tostring(problem), 2)
    end
    local chosen = {}
    for index = 1, word_count do
        chosen[index] = list[random_below(source, #list)]
    end
    source:close()
    return table.concat(chosen, WORD_SEPARATOR)
end
-- }}}

-- {{{ local function bits_per_word
-- How many bits of guessing each suggested word is worth, log2(list
-- size); for the options tally's findings and the demo.
local function bits_per_word()
    return math.log(#words()) / math.log(2)
end
-- }}}

-- {{{ local function word_count_in_list
local function word_count_in_list()
    return #words()
end
-- }}}

return {
    check_token = check_token,
    token_fingerprint = token_fingerprint,
    is_fingerprint = is_fingerprint,
    sha256 = sha256,
    suggest_token_of = suggest_token_of,
    bits_per_word = bits_per_word,
    word_count_in_list = word_count_in_list,
    WORD_LIST_PATH = WORD_LIST_PATH,
    WORD_SEPARATOR = WORD_SEPARATOR,
}
