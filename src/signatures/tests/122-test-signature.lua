-- 122-test-signature.lua — grades the signature reader (120) by the shared
-- table of examples (121-signature-examples.tsv), then grades the table:
-- each deliberately broken reader below must fail at least one example,
-- or the table is not checking what it claims to (issue 214's referees).
--
-- Run: luajit 122-test-signature.lua [DIR]
-- Exit status 0 when every check passes, 1 otherwise.

local DIR = "/home/ritz/programs/rao-chat"
-- Path: a DIR argument — use it.  None — the hard-coded project folder.
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)
local signature = require("120-signature")

local passed, failed = 0, 0
local function check(ok, what)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("  FAIL: " .. what)
    end
end

-- {{{ the examples
local ESCAPES = { ["\\"] = "\\", t = "\t", n = "\n", r = "\r" }
-- a field of the table as text: \\ \t \n \r as the log writes them, \xHH a byte
local function unescape(field)
    local out, at = {}, 1
    while at <= #field do
        local c = field:sub(at, at)
        -- Path: a backslash — the escape after it.  Anything else — itself.
        if c == "\\" then
            local letter = field:sub(at + 1, at + 1)
            if letter == "x" then
                local hex = field:sub(at + 2, at + 3)
                assert(hex:match("^%x%x$"), "a bad \\x escape in the examples: " .. field:sub(1, 60))
                out[#out + 1] = string.char(tonumber(hex, 16))
                at = at + 4
            else
                out[#out + 1] = assert(ESCAPES[letter], "an unknown escape in the examples: \\" .. letter)
                at = at + 2
            end
        else
            out[#out + 1] = c
            at = at + 1
        end
    end
    return table.concat(out)
end

local examples = {}
local file = assert(io.open(DIR .. "/src/signatures/121-signature-examples.tsv", "rb"))
for line in file:lines() do
    -- Path: a comment or an empty line — skipped.  Anything else — five fields.
    if line ~= "" and line:sub(1, 1) ~= "#" then
        local fields = {}
        for field in (line .. "\t"):gmatch("([^\t]*)\t") do fields[#fields + 1] = field end
        assert(#fields == 5, "an example without five fields: " .. line:sub(1, 60))
        examples[#examples + 1] = {
            text = unescape(fields[1]), body = unescape(fields[2]), signature = unescape(fields[3]),
            how = fields[4], note = fields[5],
        }
    end
end
file:close()
-- }}}

-- {{{ grading one reader
-- Gives the number of examples a reader gets wrong, and checks each one when
-- `report` is set.
local function grade(read, report)
    local wrong = 0
    for _, e in ipairs(examples) do
        local body, sig, how = read(e.text)
        local right = body == e.body and sig == e.signature and how == e.how
        if not right then wrong = wrong + 1 end
        if report then
            check(right, string.format("%s: got body %q, signature %q, %s", e.note, tostring(body), tostring(sig), tostring(how)))
        end
    end
    return wrong
end
-- }}}

print("the signature reader against " .. #examples .. " examples")
grade(signature.read, true)

-- {{{ the escapes the table is written in
check(unescape("a\\\\b\\tc\\nd\\re\\x41\\xff") == "a\\b\tc\nd\re" .. "A\255",
      "the examples' escapes read as the log's, plus \\xHH")
-- }}}

-- {{{ character counting
check(signature.characters("") == 0 and signature.characters("abc") == 3, "ASCII: one byte, one character")
check(signature.characters("héllo") == 5 and signature.characters("日本") == 2 and signature.characters("🙂") == 1,
      "2-, 3- and 4-byte characters count one each")
check(signature.characters("\128\128") == 2 and signature.characters("\226\130") == 2 and signature.characters("\192\128") == 2,
      "stray, cut-short and overlong bytes count one each")
check(signature.characters("\237\160\128") == 3 and signature.characters("\244\144\128\128") == 4,
      "a surrogate and a code point past U+10FFFF are bytes, not characters")
-- }}}

-- {{{ the broken readers: each must fail the table
-- The rule as 120 has it, with one part replaceable, so each broken reader
-- differs from the real one in exactly the part it names.
local function rule(parts)
    parts = parts or {}
    return function(text)
        if not parts.keep_crlf then text = text:gsub("\r\n", "\n") end
        if not parts.keep_final_breaks then text = text:gsub("\n+$", "") end
        local split
        if parts.first_blank then
            split = text:find("\n\n", 1, true)
        else
            local from = 1
            while true do
                local at = text:find("\n\n", from, true)
                if not at then break end
                split, from = at, at + 1
            end
        end
        local count = parts.count or signature.characters
        if split then
            local after = text:sub(split + 2)
            if after ~= "" and not after:find("\n", 1, true) and (parts.spaces_sign or after:find("[^ \t]"))
               and count(after) <= signature.LONGEST then
                local body = text:sub(1, split - 1)
                if not parts.keep_body_breaks then body = body:gsub("\n+$", "") end
                return body, after, "line"
            end
        end
        local word = parts.strip_punctuation and (signature.last_word(text):gsub("%p+$", "")) or signature.last_word(text)
        if word == "" then return text, "", "none" end
        return text, word, "last-word"
    end
end

check(grade(rule()) == 0, "the rule as written here agrees with 120 on every example (the broken ones below differ from it in one part)")
local BROKEN = {
    { "counting bytes, not characters", { count = function(s) return #s end } },
    { "counting only lead bytes", { count = function(s) return #s:gsub("[\128-\191]", "") end } },
    { "splitting at the first blank line", { first_blank = true } },
    { "leaving a browser's \\r\\n as it is", { keep_crlf = true } },
    { "counting a final line break as a second line", { keep_final_breaks = true } },
    { "leaving the blank line's breaks on the body", { keep_body_breaks = true } },
    { "letting a line of spaces sign", { spaces_sign = true } },
    { "stripping the last word's punctuation", { strip_punctuation = true } },
}
for _, b in ipairs(BROKEN) do
    local wrong = grade(rule(b[2]))
    check(wrong > 0, "the table catches a reader " .. b[1] .. " (it gets " .. wrong .. " wrong)")
end
-- }}}

print(string.format("signature: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
