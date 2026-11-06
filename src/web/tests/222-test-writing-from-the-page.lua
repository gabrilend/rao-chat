-- 222-test-writing-from-the-page.lua — the referees of issue 406, writing
-- from the page: 214's signature rule in the page reads every example of
-- 170's table; the page's typed file is 183's `typed_text` to the byte,
-- and what 183 refuses the page refuses; typed in the page, put by the
-- home into the room's gatherer's typed/; refused stays, with the home's
-- reason; sent again after a cut connection, filed once; the marker under
-- the person's last message.  Each referee with a broken version also
-- runs against it.
--
-- The page is the stand-in browser (208) under Node, speaking WebSocket
-- to a real device server (187).  Run it under the loopback-only wrapper
-- (a network namespace with only `lo`): the device port listens on
-- 127.0.0.2.
--
-- Run: luajit src/web/tests/222-test-writing-from-the-page.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>".

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/web/tests/[^/]+$")
end
local t = dofile(DIR .. "/src/web/tests/214-kit-for-page-tests.lua").new(DIR, "writing-test", { port = 46406 })
local check, must, with_broken, q = t.check, t.must, t.with_broken, t.q
local viewer = require("183-viewer")
local disk = require("003-disk")

if not t.has_node then
    t.check("every referee", function() error("STOPPED: node is not installed, so the page's scripts cannot be run outside a browser here") end)
    -- {{{ referee 7: the compose line (207 on the stand-in's paper document)
check("7: Enter sends and empties the compose line, Shift+Enter is left to the text box, the line grows, a bad signature keeps the text", function()
    local function drawn(words)
        local status, out = t.page("draw --mirror-in " .. q(t.HOME_RAM) .. " --open " .. q(home.coffee) .. " " .. words)
        must(status == 0, "draw failed: " .. out)
        return out
    end
    local out = drawn("--type " .. q(t.file_of("hello there")) .. " --signature " .. q(t.file_of("Ann")))
    must(out:find('enter taken, compose "", rows 1, waiting 1\n', 1, true), "Enter: " .. out)
    must(out:find("\n  li.line.mine.marker | sending…\n", 1, true), "no sending… marker: " .. out)
    out = drawn("--shift --type " .. q(t.file_of("one\ntwo\nthree")))
    must(out:find('enter left to the text box, compose "one\\ntwo\\nthree", rows 3, waiting 0\n', 1, true), "Shift+Enter: " .. out)
    out = drawn("--type " .. q(t.file_of("kept")) .. " --signature " .. q(t.file_of(string.rep("x", 81))))
    must(out:find('enter taken, compose "kept", rows 1, waiting 0\n', 1, true), "a bad signature: " .. out)
    must(out:find("would not be read as a signature", 1, true), "the reason is not shown: " .. out)
end)
-- }}}

t.finish()
end

local home = t.make_home()
t.start()
local SETTINGS = t.file_of(t.pair("laptop"))
local EXAMPLES = DIR .. "/src/signature/170-signature-examples.txt"

-- {{{ helpers
local function typed_folder(tag) return t.HOME_RAM .. "/" .. home.mailbox_of[tag] .. "/typed" end
local function typed_names(tag)
    local names = {}
    for _, name in ipairs(disk.list_dir(typed_folder(tag))) do
        if name:sub(1, 1) ~= "." and disk.is_file(typed_folder(tag) .. "/" .. name) then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end
-- room, text, signature (nil: none), more words → status, what the page printed
local function write(tag, text, signature, more, broken)
    return t.page("write --settings " .. q(SETTINGS) .. " --room " .. q(tag) .. " --text " .. q(t.file_of(text))
        .. (signature and (" --signature " .. q(t.file_of(signature))) or "") .. (more or ""), broken)
end
-- }}}

-- {{{ referee 1: the rule is 214's
local function examples(broken)
    local status, out = t.page("signature --examples " .. q(EXAMPLES), broken)
    local count = select(2, out:gsub("\nok ", "")) + (out:find("^ok ") and 1 or 0)
    must(status == 0 and not out:find("wrong"), "the page's rule: " .. out)
    must(count == #require("169-signature").examples(EXAMPLES), count .. " examples read")
end
with_broken("1: every example of 170's table reads, in the page, to its body and signature", examples, "bytes")
-- }}}

-- {{{ referee 2: the same typed file as 183
check("2: the page's typed file is 183's typed_text to the byte, and what 183 refuses the page refuses", function()
    local tag = home.coffee
    local cases = {
        { "hello", nil },
        { "hello", "Ann" },
        { "two\r\nlines\r\n\r\n\n", "Ann" },
        { "a long one\n\nwith a blank line inside", "Ann B." },
        { "café\n", "Zoë" },
        { "hi", string.rep("€", 80) },
        { "hi", string.rep("€", 81) },
        { "hi", "two\nlines" },
        { "hi", "" },
        { "\n\n", "Ann" },
        { "", nil },
        { "fine", "has\n\nblank" },
    }
    for i, case in ipairs(cases) do
        local at = 1000000000 + i
        local want, why = viewer.typed_text(tag, case[1], case[2], at)
        local out = t.ROOT .. "/typed-" .. i
        local status, said = t.page("typed --room " .. tag .. " --text " .. q(t.file_of(case[1]))
            .. (case[2] and (" --signature " .. q(t.file_of(case[2]))) or "") .. " --at " .. at .. " --out " .. q(out))
        if want then
            must(status == 0 and t.read_file(out) == want, "case " .. i .. ": the page made " .. said
                .. (t.read_file(out) or "nothing") .. ", 183 made " .. want)
        else
            must(status ~= 0 and said == "refused: " .. why .. "\n", "case " .. i .. ": 183 refused (" .. why
                .. ") but the page said " .. said)
        end
    end
    local _, said = t.page("typed --room not-a-room --text " .. q(t.file_of("x")) .. " --at 1 --out " .. q(t.ROOT .. "/none"))
    must(said == "refused: " .. select(2, viewer.typed_text("not-a-room", "x", nil, 1)) .. "\n", "a bad tag: " .. said)
end)
-- }}}

-- {{{ referee 3: typed in the page, put by the home
check("3: written against the device server, the file appears in the room's gatherer's typed/, and nothing waits", function()
    local before = #typed_names(home.coffee)
    local status, out = write(home.coffee, "from the page", "Ann", " --at 1000000500")
    must(status == 0, "write failed: " .. out)
    local name = out:match("typed (%S+)")
    must(name and name:match("^1000000500%-%d%d%d%d%d%d%-%x%x%x%x%x%x%x%x$"), "not 161's name: " .. out)
    must(out:find("\nsent " .. name .. "\n", 1, true) and out:find("\npending 0, refused 0\n", 1, true), out)
    must(#typed_names(home.coffee) == before + 1, "typed/ holds " .. #typed_names(home.coffee) .. " files")
    must(t.read_file(typed_folder(home.coffee) .. "/" .. name) == viewer.typed_text(home.coffee, "from the page", "Ann", 1000000500),
        "the file put is not the typed file")
    must(out:find("\nmarker sent\n", 1, true), "the marker after it was taken: " .. out)
end)
-- }}}

-- {{{ referee 4: refused stays
local NO_ROOM = string.rep("c", 32)
local function refused_stays(broken)
    local status, out = write(NO_ROOM, "to nowhere", nil, nil, broken)
    must(status == 0, "write failed: " .. out)
    local name = out:match("typed (%S+)")
    must(out:find("\nkept " .. name .. ": this home has no room " .. NO_ROOM .. "\n", 1, true), "not kept with why: " .. out)
    must(out:find("\npending 0, refused 1\n", 1, true), "the refused one is not still held: " .. out)
end
with_broken("4: a room the home does not have: the typed file is kept, with the home's reason", refused_stays, "drop-refused")
-- }}}

-- {{{ referee 5: sent again is filed once
check("5: a typed file whose answer was lost (the connection cut first) is sent again on the next connection, and is in typed/ once", function()
    local before = #typed_names(home.quiet)
    local status, out = write(home.quiet, "said once", "Ann", " --cut")
    must(status == 0, "write failed: " .. out)
    local name = out:match("typed (%S+)")
    must(out:find("cut after " .. name .. "\nmarker sending…\n", 1, true), "not sending while unanswered: " .. out)
    must(out:find("\nsent " .. name .. "\n", 1, true) and out:find("\npending 0, refused 0\n", 1, true), out)
    local names = typed_names(home.quiet)
    must(#names == before + 1, (#names - before) .. " files put, not one")
end)
-- }}}

-- {{{ referee 6: the marker says waiting while members are owed
check("6: the marker under the person's last message says waiting while the room's .room shows members owed", function()
    local room_file = t.HOME_RAM .. "/" .. home.mailbox_of[home.lobby] .. "/inbox/" .. home.lobby .. "/.room"
    local facts = t.read_file(room_file)
    must(facts:find("\npile: none\n", 1, true), "the lobby's .room: " .. facts)
    t.write_file(room_file, (facts:gsub("\npile: none\n", "\npile: 10.0.0.5 7000 2 1000000200\n")))
    local status, out = write(home.lobby, "is anyone there", "Ann")
    must(status == 0 and out:find("\nmarker waiting\n", 1, true), "the marker: " .. out)
    t.write_file(room_file, facts)
end)
-- }}}

-- {{{ referee 7: the compose line (207 on the stand-in's paper document)
check("7: Enter sends and empties the compose line, Shift+Enter is left to the text box, the line grows, a bad signature keeps the text", function()
    local function drawn(words)
        local status, out = t.page("draw --mirror-in " .. q(t.HOME_RAM) .. " --open " .. q(home.coffee) .. " " .. words)
        must(status == 0, "draw failed: " .. out)
        return out
    end
    local out = drawn("--type " .. q(t.file_of("hello there")) .. " --signature " .. q(t.file_of("Ann")))
    must(out:find('enter taken, compose "", rows 1, waiting 1\n', 1, true), "Enter: " .. out)
    must(out:find("\n  li.line.mine.marker | sending…\n", 1, true), "no sending… marker: " .. out)
    out = drawn("--shift --type " .. q(t.file_of("one\ntwo\nthree")))
    must(out:find('enter left to the text box, compose "one\\ntwo\\nthree", rows 3, waiting 0\n', 1, true), "Shift+Enter: " .. out)
    out = drawn("--type " .. q(t.file_of("kept")) .. " --signature " .. q(t.file_of(string.rep("x", 81))))
    must(out:find('enter taken, compose "kept", rows 1, waiting 0\n', 1, true), "a bad signature: " .. out)
    must(out:find("would not be read as a signature", 1, true), "the reason is not shown: " .. out)
end)
-- }}}

t.finish()
