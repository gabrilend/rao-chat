-- 092-test-log.lua — checks filing, refusing repeats, raising a repeat that
-- says something different, reading in file order and in written order,
-- the change bell, and the address field, under both duplicate checks
-- (scan, remembered).  A repeat from another address is a duplicate with no
-- config key set.  Also checks that two homes holding the same messages
-- under different folder tags, filed in different orders, show them in the
-- same order.
--
-- Run: luajit 092-test-log.lua [DIR] [real|stand-in]

local DIR = "/home/ritz/programs/rao-chat"
-- Path: a DIR argument — use it.  None — the hard-coded project folder.
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end
local t = dofile(DIR .. "/src/message-log/tests/090-test-harness.lua").start(arg, "log")
local log, rooms = t.log, t.rooms

-- Count "log" rings per room tag.
local rings = {}
rooms.on_change(function(home, room_id, what)
    -- Path: a log ring — count it.  Other kinds — not ours to count.
    if what == "log" then
        rings[room_id] = (rings[room_id] or 0) + 1
    end
end)

-- {{{ local function ids_of
local function ids_of(views)
    local list = {}
    for position, view in ipairs(views) do
        list[position] = view.id
    end
    return table.concat(list, ",")
end
-- }}}

-- The message id alphabet and shape.
local id = log.new_message_id()
t.check(id:match("^[0-9a-f]+$") and #id == 32, "a message id is 32 hex characters")
t.check(log.new_message_id() ~= log.new_message_id(), "two message ids differ")

local FRIEND = "203.0.113.7 51234"

for _, check in ipairs(t.CHECKS) do
    local label = check .. ": "
    local home = t.fresh_home(t.settings(check))
    local room = t.new_room(home)

    -- Filing, then filing the same delivery again (arriving later).
    local first = t.message({ text = "first\tline\nsecond \\ line\n-- ritz", written = 100, arrived = 100 })
    t.check(log.append(home, room, first) == "filed", label .. "a new message is filed")
    t.check(log.append(home, room, first) == "duplicate", label .. "the same id again is a duplicate")
    local again = t.message({ id = first.id, text = first.text, written = 100, arrived = 999 })
    t.check(log.append(home, room, again) == "duplicate",
        label .. "a repeat arriving at another time is still a duplicate")
    t.check(rings[room] == 1, label .. "the bell rang once for one filing, not for repeats")
    t.check(log.has_message(home, room, first.id), label .. "has_message finds a filed id")
    t.check(not log.has_message(home, room, log.new_message_id()), label .. "has_message does not find a new id")

    -- The same id saying something different: an error naming both.
    local ok, problem = pcall(log.append, home, room,
        t.message({ id = first.id, text = "something else entirely", written = 100 }))
    t.check(not ok and problem:find("different text", 1, true)
        and problem:find("something else entirely", 1, true)
        and problem:find("second \\\\ line", 1, true) and problem:find(first.id, 1, true),
        label .. "same id, different text: error naming the id and both texts (" .. tostring(problem) .. ")")
    t.refuses(function() log.append(home, room, t.message({ id = first.id, text = first.text, written = 101 })) end,
        "different written", label .. "same id, different written time: error")
    t.check(#log.read(home, room) == 1 and rings[room] == 1,
        label .. "a conflicting repeat files nothing and rings nothing")

    -- The same id and contents from another address: a duplicate
    -- (owner's answer), with no config key needed, and the first
    -- copy's address stays in the file.
    local moved = t.message({ id = first.id, text = first.text, written = 100, arrived = 700,
        from = FRIEND })
    t.check(log.append(home, room, moved) == "duplicate",
        label .. "a repeat from another address is a duplicate, with no key set")
    t.check(#log.read(home, room) == 1 and log.read(home, room)[1].from == "me" and rings[room] == 1,
        label .. "it filed nothing, rang nothing, and the first copy's from stays")
    local moved_and_changed = t.message({ id = first.id, text = "changed on the way", written = 100,
        from = FRIEND })
    local ok2, problem2 = pcall(log.append, home, room, moved_and_changed)
    t.check(not ok2 and problem2:find("different text", 1, true) and problem2:find(FRIEND, 1, true),
        label .. "from another address AND different text: still an error, naming both ("
        .. tostring(problem2) .. ")")

    -- A late arrival: written before the first, filed after it.
    local late = t.message({ from = FRIEND, text = "héllo 🙂", written = 50, arrived = 200 })
    local tie_a = t.message({ id = "0000000000000000000000000000000a", written = 300, arrived = 300, text = "" })
    local tie_b = t.message({ id = "0000000000000000000000000000000b", written = 300, arrived = 300, text = "\n" })
    log.append(home, room, tie_b)
    log.append(home, room, late)
    log.append(home, room, tie_a)

    local in_file = log.read(home, room)
    t.check(#in_file == 4, label .. "read gives every record (4)")
    t.check(in_file[1].id == first.id and in_file[2].id == tie_b.id
        and in_file[3].id == late.id and in_file[4].id == tie_a.id, label .. "read keeps file order")
    t.check(in_file[1].text == first.text and in_file[3].text == late.text
        and in_file[4].text == "" and in_file[2].text == "\n", label .. "texts come back unchanged")
    t.check(in_file[3].from == FRIEND and in_file[1].from == "me" and in_file[1].kind == "message"
        and in_file[1].target == "" and in_file[3].author == nil,
        label .. "from, kind and target are read back; there is no author field")

    local ordered = log.read_ordered(home, room)
    t.check(ordered[1].id == late.id and ordered[2].id == first.id
        and ordered[3].id == tie_a.id and ordered[4].id == tie_b.id,
        label .. "read_ordered sorts by written time, ties by id")
    t.check(ordered[1].edited == false and ordered[1].deleted == false
        and ordered[1].changed_from == "" and ordered[1].room_id == nil,
        label .. "unedited messages say so, and views carry no local tag")
    t.check(log.copy_log == nil, label .. "copying logs is retired")

    -- Refusals.
    t.refuses(function() log.append(home, room, t.message({ id = "has space" })) end,
        "may hold only", label .. "an id with a space is refused")
    t.refuses(function() log.append(home, room, t.message({ id = "" })) end,
        "may hold only", label .. "an empty id is refused")
    t.refuses(function() log.append(home, room, t.message({ written = 1.5 })) end,
        "whole number", label .. "a fractional time is refused")
    t.refuses(function() log.append(home, room, t.message({ text = 5 })) end,
        "text must be a string", label .. "a non-string text is refused")
    t.refuses(function() log.append(home, room, t.message({ kind = "correction" })) end,
        "append files messages only", label .. "append refuses an edit")
    t.refuses(function() log.append(home, string.rep("f", 32), t.message()) end,
        "no log", label .. "filing into a room that is not there is refused")
end

-- The record in the file is one tsv line a person can read with cat.
do
    local home = t.fresh_home(t.settings("scan"))
    local room = t.new_room(home)
    log.append(home, room, t.message({ id = "abc", from = FRIEND, written = 5, arrived = 6,
        text = "two\nlines" }))
    local file = assert(io.open(rooms.log_path(home, room), "rb"))
    local content = file:read("*a")
    file:close()
    t.check(content == "abc\t" .. FRIEND .. "\t5\t6\tmessage\t\ttwo\\nlines\n",
        "the log holds one tab-separated line per message (" .. string.format("%q", content) .. ")")
end

-- The address field: what is accepted and refused.
do
    local home = t.fresh_home(t.settings("scan"))
    local room = t.new_room(home)
    local ACCEPTED = { "me", "203.0.113.7 1", "203.0.113.7 65535", "::1 7777", "[2001:db8::1] 443",
        "friend.example.org 9000", "abcdefghijklmnop.onion 80" }
    for _, from in ipairs(ACCEPTED) do
        t.check(log.append(home, room, t.message({ from = from })) == "filed", "from '" .. from .. "' is accepted")
    end
    local REFUSED = { "", "203.0.113.7", "203.0.113.7 0", "203.0.113.7 65536", "203.0.113.7  80",
        "203.0.113.7 080", "203.0.113.7\t80", "a b 80", " 80", "203.0.113.7 80 ", "sorelu", "Me" }
    for _, from in ipairs(REFUSED) do
        t.refuses(function() log.append(home, room, t.message({ from = from })) end,
            "neither", string.format("from %q is refused", from))
    end
    t.refuses(function() log.append(home, room, t.message({ from = 7 })) end, "from must be a string",
        "a non-string from is refused")
    t.refuses(function()
        log.append(home, room, { id = log.new_message_id(), author = "me", written = 1, arrived = 1, text = "x" })
    end,
        "from must be a string", "the old author field is not taken for from")
    local records = log.read(home, room)
    t.check(records[4].from == "::1 7777" and records[5].from == "[2001:db8::1] 443",
        "addresses with colons read back unchanged")
end

-- Two homes, different folder tags, same messages filed in different
-- orders: every reader sees the same order.
do
    local shape = "tsv"
    local messages = {}
    for position = 1, 12 do
        -- Groups of three share a written time, so ties are common.
        messages[position] = t.message({ written = 1000 + math.floor(position / 3),
            from = (position % 2 == 0) and FRIEND or "me", text = "m" .. position })
    end
    local home_a = t.fresh_home(t.settings("remembered"))
    local home_b = t.fresh_home(t.settings("scan"))
    local room_a = t.new_room(home_a)
    local room_b = t.new_room(home_b)
    for position = 1, #messages do
        log.append(home_a, room_a, messages[position])
    end
    for position = #messages, 1, -1 do
        log.append(home_b, room_b, messages[position])
    end
    local order_a = ids_of(log.read_ordered(home_a, room_a))
    local order_b = ids_of(log.read_ordered(home_b, room_b))
    t.check(room_a ~= room_b, shape .. ": the two homes' folder tags differ")
    t.check(order_a == order_b and #log.read_ordered(home_a, room_a) == 12,
        shape .. ": two homes with different tags and filing orders show the same order")
    t.check(log.read(home_a, room_a)[1].id ~= log.read(home_b, room_b)[1].id,
        shape .. ": (the file orders really do differ)")
end

-- A missing config key is an error, not a default.
local bare = t.fresh_home({})
local bare_room = t.new_room(bare)
t.refuses(function() log.append(bare, bare_room, t.message()) end, "log.duplicate-check",
    "a missing log.duplicate-check is an error")
t.check(#log.read(bare, bare_room) == 0, "reading needs no config key at all")
local typo = t.fresh_home(t.settings("index"))
local typo_room = t.new_room(typo)
t.refuses(function() log.append(typo, typo_room, t.message()) end, "not one of scan",
    "a misspelt duplicate check is an error")

t.finish()
