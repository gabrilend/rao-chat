-- 009-test-formats-and-entry.lua — tests for rmail's formats and the room entry.
--
-- Checks, with strings only (no disk): that rmail's address lines must
-- come in pairs with no default port; that an entry turns into text and
-- back unchanged, including labels and tokens with awkward characters;
-- and that every malformed entry a hand edit could make is refused with
-- the file named.
-- Run: luajit 009-test-formats-and-entry.lua [project folder]

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local kit = dofile(DIR .. "/src/room-folders/tests/008-kit-for-tests.lua")
kit.setup(DIR)
local formats = require("004-rmail-formats")
local entries = require("006-entry")
local tokens  = require("007-tokens")
local check, same, fails = kit.check, kit.same, kit.fails

local TAG = "0123456789abcdef0123456789abcdef"
local OTHER_TAG = "fedcba9876543210fedcba9876543210"
local MAILBOX_TAG = "9c41d07a2be35f6e8810aa3c5d7e9f01"

-- {{{ local function sample_entry
local function sample_entry()
    return {
        tag = TAG, label = "programming", token = "maple-orbit-velvet-tin", kind = "group",
        parent = tokens.token_fingerprint("home"), mailbox = MAILBOX_TAG, filed_under = "",
        members = {
            { address = "203.0.113.9", port = 7777, heard = 1790000000 },
            { address = "sorelu.example.org", port = 7778, heard = 0 },
            { address = "2001:db8::1", port = 7777, heard = 5 },
        },
    }
end
-- }}}

-- {{{ local function pairs_of
local function pairs_of(text, also)
    local contacts = formats.parse_contacts(text, "test")
    local name = next(contacts)
    return formats.address_pairs(contacts[name], "test", also)
end
-- }}}

check("address_pairs: rmail's plain ip/port is pair 0, indexed pairs sorted", function()
    local found = pairs_of("s.ip = 1.2.3.4\ns.port = 80\ns.ip[2] = b\ns.port[2] = 90\ns.ip[1] = a\ns.port[1] = 85\n")
    same(#found, 3, "count")
    same(found[1].index, 0) same(found[1].address, "1.2.3.4") same(found[1].port, 80)
    same(found[2].address, "a") same(found[3].port, 90)
end)

check("address_pairs: an address without its own port is refused (no default port)", function()
    fails(function() pairs_of("s.ip = 1.2.3.4\ns.port = 80\ns.ip[2] = b\n") end, "port[2] is missing")
end)

check("address_pairs: a port without an address is refused", function()
    fails(function() pairs_of("s.port[3] = 80\n") end, "ip[3] is missing")
end)

check("address_pairs: a plain port alone (rmail's default port) is refused", function()
    fails(function() pairs_of("s.port = 80\ns.token = x\n") end, "ip is missing")
end)

check("address_pairs: bad ports refused", function()
    fails(function() pairs_of("s.ip[1] = a\ns.port[1] = 0\n") end, "1-65535")
    fails(function() pairs_of("s.ip[1] = a\ns.port[1] = 65536\n") end, "1-65535")
    fails(function() pairs_of("s.ip[1] = a\ns.port[1] = 080\n") end, "1-65535")
    fails(function() pairs_of("s.ip[1] = a\ns.port[1] = http\n") end, "1-65535")
end)

check("address_pairs: malformed indexes refused, not silently merged", function()
    fails(function() pairs_of("s.ip[01] = a\ns.port[01] = 80\n") end, "malformed index")
    fails(function() pairs_of("s.ip[0] = a\ns.port[0] = 80\n") end, "malformed index")
end)

check("address_pairs: an extra per-address field is required with every pair", function()
    fails(function() pairs_of("s.ip[1] = a\ns.port[1] = 80\n", { "heard" }) end, "heard[1] is missing")
    fails(function() pairs_of("s.heard[1] = 0\n", { "heard" }) end, "is missing")
end)

check("entry: text and back gives the same entry", function()
    local entry = sample_entry()
    local back = entries.parse_entry(entries.entry_text(entry), TAG, "test")
    for _, field in ipairs({ "tag", "label", "token", "kind", "parent", "mailbox", "filed_under" }) do
        same(back[field], entry[field], field)
    end
    same(#back.members, 3, "members")
    for index, member in ipairs(entry.members) do
        same(back.members[index].address, member.address, "address " .. index)
        same(back.members[index].port, member.port, "port " .. index)
        same(back.members[index].heard, member.heard, "heard " .. index)
    end
end)

check("entry: awkward labels and tokens survive (spaces, quotes, '/', '=', '#', unicode)", function()
    local awkward = { '  edge spaces  ', '"quoted"', 'a/b/c', 'x = y', '# not a comment', '// nor this',
                      'café ☕', '"', 'tab\there' }
    for _, text in ipairs(awkward) do
        local entry = sample_entry()
        entry.label = text
        entry.token = text
        local back = entries.parse_entry(entries.entry_text(entry), TAG, "test")
        same(back.label, text, "label " .. text)
        same(back.token, text, "token " .. text)
    end
end)

check("entry: the text is rmail's contacts format, named by the tag, addresses from 1", function()
    local text = entries.entry_text(sample_entry())
    same(text:find(TAG .. ".parent = " .. tokens.token_fingerprint("home") .. "\n" .. TAG .. ".mailbox = "
        .. MAILBOX_TAG .. "\n" .. TAG .. ".filed-under =\n", 1, true) ~= nil, true, "mailbox between parent and filed-under")
    same(text:find(TAG .. '.label = "programming"\n', 1, true) ~= nil, true, "label line")
    same(text:find(TAG .. ".ip[1] = 203.0.113.9\n" .. TAG .. ".port[1] = 7777\n" .. TAG .. ".heard[1] = 1790000000\n", 1, true) ~= nil, true, "pair 1")
    same(text:find(TAG .. ".filed-under\n", 1, true) == nil and text:find(TAG .. ".filed-under =\n", 1, true) ~= nil, true, "empty field")
    -- rmail's own reader shape: every line parses as a contact line
    local contacts = formats.parse_contacts(text, "test")
    same(contacts[TAG]["ip[3]"], "2001:db8::1", "ipv6")
end)

check("entry: two entries joined are one valid contacts file", function()
    local a, b = sample_entry(), sample_entry()
    b.tag = OTHER_TAG
    local joined = formats.parse_contacts(entries.entry_text(a) .. entries.entry_text(b), "joined")
    same(joined[TAG].label, "programming") same(joined[OTHER_TAG].label, "programming")
end)

check("entry: a room with no members writes and reads", function()
    local entry = sample_entry()
    entry.members = {}
    same(#entries.parse_entry(entries.entry_text(entry), TAG, "test").members, 0)
end)

check("entry: writer refusals", function()
    local cases = {
        { function(e) e.label = "" end, "label must be a non-empty" },
        { function(e) e.label = "two\nlines" end, "line break" },
        { function(e) e.token = "a\rb" end, "line break" },
        { function(e) e.kind = "channel" end, "kind must be" },
        { function(e) e.parent = "abc" end, "parent must be" },
        { function(e) e.parent = TAG end, "parent must be" },
        { function(e) e.filed_under = "programming" end, "filed_under must be" },
        { function(e) e.mailbox = "" end, "mailbox must be" },
        { function(e) e.mailbox = 7777 end, "mailbox must be" },
        { function(e) e.mailbox = nil end, "mailbox must be" },
        { function(e) e.members[1].port = nil end, "port must be" },
        { function(e) e.members[1].port = 7777.5 end, "port must be" },
        { function(e) e.members[1].heard = -1 end, "heard must be" },
        { function(e) e.members[1].heard = nil end, "heard must be" },
        { function(e) e.members[1].address = "a b" end, "address must be" },
        { function(e) e.members[1].address = "" end, "address must be" },
        { function(e) e.members[1].nick = "x" end, "unknown field 'nick'" },
        { function(e) e.members[2] = { address = "203.0.113.9", port = 7777, heard = 0 } end, "already member 1" },
        { function(e) e.members[5] = { address = "z", port = 1, heard = 0 } end, "no gaps" },
        { function(e) e.tag = "ROOM" end, "entry.tag" },
    }
    for number, case in ipairs(cases) do
        local entry = sample_entry()
        case[1](entry)
        fails(function() entries.entry_text(entry) end, case[2])
    end
end)

check("entry: the same address with two ports is two members", function()
    local entry = sample_entry()
    entry.members[2] = { address = "203.0.113.9", port = 7778, heard = 0 }
    same(#entries.parse_entry(entries.entry_text(entry), TAG, "t").members, 3)
end)

-- {{{ local function with_line
-- The sample entry's text with one line replaced (or removed when
-- replacement is ""), or a line added when `from` is nil.
local function with_line(from, to)
    local text = entries.entry_text(sample_entry())
    -- nil: append the new line.  Otherwise swap the old one.
    if from == nil then
        return text .. to .. "\n"
    end
    local start, stop = text:find(from, 1, true)
    assert(start, "sample lacks " .. from)
    return text:sub(1, start - 1) .. to .. text:sub(stop + 1)
end
-- }}}

check("entry: reader refusals for hand-edited files", function()
    local cases = {
        { with_line(TAG .. ".port[2] = 7778\n", ""), "port[2] is missing" },
        { with_line(TAG .. ".ip[2] = sorelu.example.org\n", ""), "ip[2] is missing" },
        { with_line(TAG .. ".heard[2] = 0\n", ""), "heard[2] is missing" },
        { with_line(nil, TAG .. ".ip = 1.2.3.4"), "without an index" },
        { with_line(nil, TAG .. ".port = 80"), "without an index" },
        { with_line(nil, TAG .. ".colour = blue"), "unknown field 'colour'" },
        { with_line(nil, TAG .. ".nick[1] = x"), "unknown indexed field" },
        { with_line(TAG .. ".kind = group\n", ""), "'kind' is missing" },
        { with_line(TAG .. ".mailbox = " .. MAILBOX_TAG .. "\n", ""), "'mailbox' is missing" },
        { with_line(TAG .. ".mailbox = " .. MAILBOX_TAG, TAG .. ".mailbox ="), "mailbox must be" },
        { with_line(TAG .. ".kind = group", TAG .. ".kind = channel"), "kind must be" },
        { with_line(TAG .. ".heard[1] = 1790000000", TAG .. ".heard[1] = soon"), "heard[1] must be" },
        { with_line(TAG .. ".heard[1] = 1790000000", TAG .. ".heard[1] = 007"), "heard[1] must be" },
        { with_line(nil, TAG .. ".label = \"again\""), "set twice" },
        { with_line(nil, OTHER_TAG .. ".label = \"x\""), "exactly one entry" },
        { with_line(TAG .. ".ip[3] = 2001:db8::1\n" .. TAG .. ".port[3] = 7777\n" .. TAG .. ".heard[3] = 5\n",
                    TAG .. ".ip[4] = 2001:db8::1\n" .. TAG .. ".port[4] = 7777\n" .. TAG .. ".heard[4] = 5\n"), "no gaps" },
        { with_line(TAG .. ".ip[3] = 2001:db8::1", TAG .. ".ip[3] = 203.0.113.9"), "already member 1" },
    }
    for number, case in ipairs(cases) do
        fails(function() entries.parse_entry(case[1], TAG, "rooms/x/entry") end, case[2])
    end
end)

check("entry: the reader names the file in its errors", function()
    fails(function() entries.parse_entry(with_line(nil, TAG .. ".colour = blue"), TAG, "/some/home/rooms/x/entry") end,
          "/some/home/rooms/x/entry")
end)

check("entry: an entry named by another tag than its folder is refused", function()
    fails(function() entries.parse_entry(entries.entry_text(sample_entry()), OTHER_TAG, "moved") end,
          "folder is " .. OTHER_TAG)
end)

check("config: parse, rewrite in place, strictness (kept from round 1)", function()
    local text = "# c\na = 1\nb.c-d = two words\n"
    local config = formats.parse_config(text, "cfg")
    same(config.a, "1") same(config["b.c-d"], "two words")
    same(formats.config_with(text, "a", "9"), "# c\na = 9\nb.c-d = two words\n")
    fails(function() formats.parse_config("a = 1\na = 2\n", "cfg") end, "set twice")
    fails(function() formats.parse_config("nonsense\n", "cfg") end, "not a 'key = value'")
    fails(function() formats.config_with(text, "bad key", "x") end, "config key must be")
    fails(function() formats.config_with(text, "k", " x") end, "leading or trailing")
end)

kit.finish()
