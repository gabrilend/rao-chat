-- 010-test-tokens.lua — tests for token fingerprints and readable suggestions.
--
-- Checks that the fingerprint is SHA-256 twice (against known values),
-- is the same on two separate homes for the same token and differs from
-- the sealing key; that the word list is intact; that suggestions are
-- made of list words joined by dashes and spread evenly; and that a
-- suggested token has six words with no setting consulted (the owner's
-- answer; the round-2 switch rooms.suggested-token-words is gone).
-- Run: luajit 010-test-tokens.lua [project folder]

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local kit = dofile(DIR .. "/src/room-folders/tests/008-kit-for-tests.lua")
local rooms = kit.setup(DIR)
local tokens = require("007-tokens")
local check, same, fails = kit.check, kit.same, kit.fails

-- {{{ local function to_hex
local function to_hex(bytes)
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
-- }}}

-- {{{ local function spec
local function spec(label, token, parent)
    return { label = label, token = token, kind = "group", parent = parent, filed_under = "", members = {},
             mailbox_port = kit.port_for("group", parent) }
end
-- }}}

check("sha256 matches the published test vector for 'abc'", function()
    same(to_hex(tokens.sha256("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
end)

check("sha256 of the empty text matches the published vector", function()
    same(to_hex(tokens.sha256("")), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
end)

check("fingerprint is SHA-256 of the raw SHA-256 (checked with sha256sum)", function()
    -- computed once outside Lua: printf abc | sha256sum | xxd -r -p | sha256sum
    same(rooms.token_fingerprint("abc"), "4f8b42c22dd3729b519ba6f68d2da7cc5b2d606d05daed5ad5128cc03e6c6358")
end)

check("fingerprint is not the sealing key itself", function()
    local key_hex = to_hex(tokens.sha256("maple-orbit-velvet-tin"))
    same(rooms.token_fingerprint("maple-orbit-velvet-tin") ~= key_hex, true, "differs")
end)

check("fingerprint: same token on two homes gives the same parent value; labels differ freely", function()
    local home_a = kit.test_home(rooms, "tokens-a", "")
    local home_b = kit.test_home(rooms, "tokens-b", "")
    local top_a = rooms.make_room(home_a, spec("home", "shared-top-token", ""))
    local top_b = rooms.make_room(home_b, spec("family", "shared-top-token", ""))
    local fingerprint_a = rooms.token_fingerprint(rooms.read_entry(home_a, top_a).token)
    local fingerprint_b = rooms.token_fingerprint(rooms.read_entry(home_b, top_b).token)
    same(fingerprint_a, fingerprint_b, "fingerprints")
    same(top_a ~= top_b, true, "local tags differ")
    local child_b = rooms.make_room(home_b, spec("kitchen", "child-token", fingerprint_a))
    same(rooms.find_by_fingerprint(home_b, rooms.read_entry(home_b, child_b).parent), top_b, "b finds its own top")
end)

check("fingerprint: different tokens differ, one character apart", function()
    same(rooms.token_fingerprint("token-a") ~= rooms.token_fingerprint("token-b"), true)
    same(rooms.token_fingerprint("Token") ~= rooms.token_fingerprint("token"), true, "case matters")
end)

check("fingerprint: refusals", function()
    fails(function() rooms.token_fingerprint("") end, "non-empty")
    fails(function() rooms.token_fingerprint("a\nb") end, "line break")
    fails(function() rooms.token_fingerprint(nil) end, "non-empty")
end)

check("is_fingerprint", function()
    same(rooms.is_fingerprint(rooms.token_fingerprint("x")), true)
    same(rooms.is_fingerprint(("A"):rep(64)), false, "upper")
    same(rooms.is_fingerprint(("a"):rep(63)), false, "short")
    same(rooms.is_fingerprint(nil), false, "nil")
end)

check("word list: 7772 lower-case words, no repeats", function()
    same(tokens.word_count_in_list(), 7772, "count")
    local text = kit.read_file(tokens.WORD_LIST_PATH)
    local seen = {}
    for word in text:gmatch("([^\n]*)\n") do
        same(word:match("^[a-z]+$") ~= nil, true, "letters only: " .. word)
        same(seen[word], nil, "repeat " .. word)
        seen[word] = true
    end
end)

check("word list: about 12.92 bits per word", function()
    same(math.floor(tokens.bits_per_word() * 100 + 0.5), 1292)
end)

check("suggest_token_of: n list words joined by '-'", function()
    local list = {}
    for word in kit.read_file(tokens.WORD_LIST_PATH):gmatch("([^\n]*)\n") do list[word] = true end
    for count = 1, 8 do
        local token = rooms.suggest_token_of(count)
        local parts = {}
        for word in token:gmatch("[^-]+") do
            same(list[word], true, "in list: " .. word)
            parts[#parts + 1] = word
        end
        same(#parts, count, "words in " .. token)
    end
end)

check("suggest_token_of: fresh each call (1000 four-word suggestions, no repeats)", function()
    local seen = {}
    for _ = 1, 1000 do
        local token = rooms.suggest_token_of(4)
        same(seen[token], nil, "repeat " .. token)
        seen[token] = true
    end
end)

check("suggest_token_of: words are spread evenly (first letters over 20000 draws)", function()
    -- expected share of each first letter, from the list itself
    local expected, total = {}, 0
    for word in kit.read_file(tokens.WORD_LIST_PATH):gmatch("([^\n]*)\n") do
        expected[word:sub(1, 1)] = (expected[word:sub(1, 1)] or 0) + 1
        total = total + 1
    end
    local got, draws = {}, 0
    for _ = 1, 5000 do
        for word in rooms.suggest_token_of(4):gmatch("[^-]+") do
            got[word:sub(1, 1)] = (got[word:sub(1, 1)] or 0) + 1
            draws = draws + 1
        end
    end
    for letter, count in pairs(expected) do
        local want = count / total * draws
        -- a letter far from its share (6 standard deviations) would mean
        -- a biased draw; with 26 letters a fair draw essentially never
        -- strays that far.
        local spread = math.sqrt(want)
        same(math.abs((got[letter] or 0) - want) < 6 * spread + 1, true,
             "letter " .. letter .. " got " .. tostring(got[letter]) .. " want ~" .. math.floor(want))
    end
end)

check("suggest_token_of: refusals", function()
    fails(function() rooms.suggest_token_of(0) end, "whole number")
    fails(function() rooms.suggest_token_of(2.5) end, "whole number")
    fails(function() rooms.suggest_token_of("4") end, "whole number")
end)

check("suggest_token: six words, no setting read (an empty config is enough)", function()
    local home = rooms.open_home(kit.fresh_home_dir("tokens-six"))
    same(rooms.SUGGESTED_WORD_COUNT, 6, "the exported count")
    for _ = 1, 20 do
        local token = rooms.suggest_token(home)
        same(select(2, token:gsub("-", "-")) + 1, 6, "words in " .. token)
    end
    -- the suggestion is a usable token: a room can be made with it.
    local tag = rooms.make_room(home, { label = "six", token = rooms.suggest_token(home), kind = "group",
                                        parent = "", filed_under = "", members = {},
                                        mailbox_port = kit.fresh_port() })
    same(rooms.room_exists(home, tag), true)
end)

check("suggest_token: the round-2 setting is gone (and, undeclared, refused in config)", function()
    local home = rooms.open_home(kit.fresh_home_dir("tokens-old-key"))
    fails(function() rooms.set_config(home, "rooms.suggested-token-words", "4") end,
          "not a setting any module reads")
    same(select(2, rooms.suggest_token(home):gsub("-", "-")) + 1, 6)
    same(rooms.SUGGESTED_WORDS_KEY, nil, "no exported key")
end)

check("suggest_token: still checks its home argument", function()
    fails(function() rooms.suggest_token("not a home") end, "expected a home")
end)

kit.finish()
