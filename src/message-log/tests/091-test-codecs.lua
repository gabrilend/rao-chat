-- 091-test-codecs.lua — checks that the log's record shape (tsv) writes any
-- text and reads it back unchanged (tabs, newlines, backslashes, empty
-- text, non-ASCII, every byte value, random bytes), that text can never
-- pose as a record's id marker, and that damaged records — including lines
-- in the retired block and jsonl shapes — are refused, not guessed at.
--
-- Run: luajit 091-test-codecs.lua [DIR] [real|stand-in]

local DIR = "/home/ritz/programs/rao-chat"
-- Path: a DIR argument — use it.  None — the hard-coded project folder.
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end
local t = dofile(DIR .. "/src/message-log/tests/090-test-harness.lua").start(arg, "codecs")
local codecs = require("083-record-codecs")
local reader = require("084-log-reader")

-- Every byte value once, as one string.
local every_byte = {}
for value = 0, 255 do
    every_byte[#every_byte + 1] = string.char(value)
end

local TEXTS = {
    "", " ", "\t", "\n", "\r", "\r\n", "\\", "\\\\", "\\n", "\\t", "a\\", "\\",
    "tab\there", "line\nbreak", "trailing newline\n", "\n\n\n", "  indented",
    "\n  \n", "text:", "id: fake\n\nid: other", '{"id":"x"}', "\n{\"id\":\"y\"",
    "héllo wörld", "日本語のテキスト", "emoji 🙂🎉", "\0", "nul\0inside",
    "\255\254 not utf-8", table.concat(every_byte),
    string.rep("long ", 2000),
}

-- A few random byte strings, fixed seed so a failure can be repeated.
math.randomseed(105)
for _ = 1, 200 do
    local bytes = {}
    for _ = 1, math.random(0, 60) do
        bytes[#bytes + 1] = string.char(math.random(0, 255))
    end
    TEXTS[#TEXTS + 1] = table.concat(bytes)
end

-- {{{ local function record_with
local function record_with(text, kind, target)
    return {
        id = "0123456789abcdef0123456789abcdef", from = "203.0.113.7 51234",
        written = 1790000123, arrived = 1790000456,
        kind = kind or "message", target = target or "", text = text,
    }
end
-- }}}

-- {{{ local function same_record
local function same_record(a, b)
    for _, field in ipairs({ "id", "from", "written", "arrived", "kind", "target", "text" }) do
        -- Path: a field differs — not the same.
        if a[field] ~= b[field] then
            return false
        end
    end
    return true
end
-- }}}

do
    local shape = codecs.SHAPE
    local codec = codecs.get(shape)
    local all_ok = true
    for position, text in ipairs(TEXTS) do
        local record = record_with(text)
        local encoded = codec.encode(record)
        local parsed = reader.parse(encoded)
        local ok = #parsed == 1 and same_record(parsed[1], record)
        -- Path: round trip broke — report which text.
        if not ok then
            all_ok = false
            t.check(false, shape .. " round trip of text #" .. position .. " " .. string.format("%q", text):sub(1, 60))
        end
    end
    t.check(all_ok, shape .. " round-trips all " .. #TEXTS .. " texts")

    -- Many records in one file, then parsed back in order.
    local pieces = {}
    for position, text in ipairs(TEXTS) do
        local record = record_with(text)
        record.id = string.format("%032x", position)
        pieces[#pieces + 1] = codec.encode(record)
    end
    local parsed = reader.parse(table.concat(pieces))
    local in_order = #parsed == #TEXTS
    for position, record in ipairs(parsed) do
        in_order = in_order and record.text == TEXTS[position]
            and record.id == string.format("%032x", position)
    end
    t.check(in_order, shape .. " parses " .. #TEXTS .. " records in one file in order")

    -- Edit records round-trip too.
    local fix = record_with("fixed text\n", "correction", "abc")
    t.check(same_record(reader.parse(codec.encode(fix))[1], fix),
        shape .. " round-trips a correction record")
    local gone = record_with("", "deletion", "abc")
    t.check(same_record(reader.parse(codec.encode(gone))[1], gone),
        shape .. " round-trips a deletion record")

    -- Text that contains other shapes' and this shape's marker text for some
    -- id must not be found as that id.
    local fake_id = "ffffffffffffffffffffffffffffffff"
    local sneaky = "x" .. codecs.tsv.id_marker(fake_id) .. "y" .. fake_id .. "\t" .. fake_id
    local file_text = codec.encode(record_with(sneaky))
    local marker = codec.id_marker(fake_id)
    t.check(("\n" .. file_text):find(marker, 1, true) == nil,
        shape .. " text holding id markers never forms a real marker")
    t.check(("\n" .. file_text):find(codec.id_marker(record_with("").id), 1, true) == 1,
        shape .. " the real id marker is found at the record start")

    -- A record cut short is refused.
    t.refuses(function()
        reader.parse(codec.encode(record_with("abc")):sub(1, -2))
    end, "part-way", shape .. " refuses a record cut short")
end

-- Damaged records are refused, with a reason.
t.refuses(function() reader.parse("a\tb\tc\n") end, "fields", "tsv refuses a short line")
t.refuses(function()
    reader.parse("abc\tme\t1\t1\tmessage\t\tbad \\q escape\n")
end, "unknown escape", "tsv refuses an unknown escape")
t.refuses(function()
    reader.parse("abc\tme\tsoon\t1\tmessage\t\ttext\n")
end, "written", "tsv refuses a non-number time")
t.refuses(function()
    reader.parse("abc\tme\t1\t1\tshout\t\ttext\n")
end, "unknown kind", "tsv refuses an unknown kind")
t.refuses(function() reader.parse("\n") end, "empty line", "an empty line is refused")
t.refuses(function() reader.parse("abc\tme\t1\t1\tmessage\t\ttext") end, "part-way",
    "a last line without its newline is refused")
t.refuses(function() codecs.get("block") end, "not one of tsv", "the retired block shape is not offered")
t.refuses(function() codecs.get("jsonl") end, "not one of tsv", "the retired jsonl shape is not offered")
t.check(codecs.block == nil and codecs.jsonl == nil and codecs.detect == nil,
    "the retired codecs and shape detection are gone")

-- A log written by round 2 in a retired shape is refused loudly, never
-- read as something else.
t.refuses(function()
    reader.parse("id: a\nfrom: me\nwritten: 1\narrived: 1\nkind: message\ntarget:\ntext:\n  hi\n\n")
end, "fields, wanted 7", "a block-shaped record is refused")
t.refuses(function()
    reader.parse('{"id":"a","from":"me","written":1,"arrived":1,"kind":"message","target":"","text":"hi"}\n')
end, "fields, wanted 7", "a jsonl-shaped record is refused")

t.finish()
