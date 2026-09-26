-- 011-test-home-and-rooms.lua — tests for the home folder and making, reading,
-- changing and listing rooms.
--
-- Builds the owner's example tree (home > ritz > programming) plus two
-- direct messages in a fresh RAM home, and checks: the layout on disk;
-- that a direct message and a group room are read by the same code and
-- listed apart; that a token changed by hand keeps the room's folder,
-- label, members, withheld list and log, and that the children follow;
-- the refusals (a token held twice, a room inside itself, bad filings,
-- missing rooms, missing spec fields); and that a hand-edited entry with
-- an unpaired address is refused.
-- Run: luajit 011-test-home-and-rooms.lua [project folder]

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local kit = dofile(DIR .. "/src/room-folders/tests/008-kit-for-tests.lua")
local rooms = kit.setup(DIR)
local check, same, same_list, fails = kit.check, kit.same, kit.same_list, kit.fails

-- The home spec() works out ports against (set once it is made below).
local spec_home = nil

-- {{{ local function spec
local function spec(label, token, kind, parent, members)
    return { label = label, token = token, kind = kind, parent = parent, filed_under = "", members = members or {},
             mailbox_port = kit.port_for_home(rooms, spec_home, kind, parent) }
end
-- }}}

-- {{{ local function member
local function member(address, port)
    return { address = address, port = port, heard = 0 }
end
-- }}}

-- {{{ local function exists
local function exists(path)
    local handle = io.open(path, "rb")
    -- opened: it exists (close it again).  Not: it does not.
    if handle then
        handle:close()
        return true
    end
    return false
end
-- }}}

check("open_home: makes config, an empty ignore, empty mailboxes, rooms/ and people/; no contacts file", function()
    local dir = kit.fresh_home_dir("layout")
    local home = rooms.open_home(dir .. "/")
    same(home.dir, dir, "trailing slash dropped")
    same(kit.read_file(dir .. "/ignore"), "", "ignore empty")
    same(exists(dir .. "/config"), true, "config")
    same(exists(dir .. "/contacts"), false, "no contacts file any more")
    same(rooms.ignore_path(home), dir .. "/ignore", "ignore_path")
    same(rooms.mailboxes_path(home), dir .. "/mailboxes", "mailboxes_path")
    same(#rooms.read_mailboxes(home), 0, "no mailboxes yet")
    same(rooms.direct_mailbox(home), "", "no direct mailbox yet")
    same(#rooms.list_rooms(home), 0, "no rooms")
end)

check("open_home: opening twice changes nothing (ignore contents kept)", function()
    local dir = kit.fresh_home_dir("twice")
    local home = rooms.open_home(dir)
    kit.write_file(dir .. "/ignore", "somebody\n")
    rooms.set_config(home, "mailboxes.merge-when-parent-arrives", "ask")
    rooms.open_home(dir)
    same(kit.read_file(dir .. "/ignore"), "somebody\n")
    same(rooms.config_value(home, "mailboxes.merge-when-parent-arrives"), "ask")
end)

check("open_home: refusals", function()
    fails(function() rooms.open_home("relative/path") end, "absolute path")
    fails(function() rooms.open_home(kit.scratch .. "/no-such-folder/home") end, "folder above the home does not exist")
end)

check("config_value: an absent (declared) key is an error naming the line to add", function()
    local home = rooms.open_home(kit.fresh_home_dir("config"))
    fails(function() rooms.config_value(home, rooms.MERGE_KEY) end,
          "add a line: " .. rooms.MERGE_KEY .. " = <value>")
end)

---------------------------------------------------------------- declared settings

check("declared settings: room-folders declares its one setting, from its own list", function()
    local all = rooms.declared_settings()
    same(all[rooms.MERGE_KEY].module, "room-folders", "owner")
    same(all[rooms.MERGE_KEY].file, DIR .. "/src/room-folders/016-settings.lua", "file")
    same(all["mailboxes.unheld-parent"], nil, "retired in round 4: not declared")
    same(all["rooms.suggested-token-words"], nil, "retired in round 3: not declared")
    -- a copy: writing into it declares nothing.
    all["x.y"] = { module = "me", file = "nowhere" }
    same(rooms.declared_settings()["x.y"], nil, "the copy is not the list")
end)

check("declared settings: a known config line is accepted by open_home and every read", function()
    local dir = kit.fresh_home_dir("config-known")
    local home = rooms.open_home(dir)
    rooms.set_config(home, rooms.MERGE_KEY, "automatic")
    rooms.open_home(dir)
    same(rooms.read_config(home)[rooms.MERGE_KEY], "automatic")
end)

check("declared settings: an unknown config line stops open_home, naming the file, line and line text", function()
    local dir = kit.fresh_home_dir("config-unknown")
    local home = rooms.open_home(dir)
    rooms.set_config(home, rooms.MERGE_KEY, "automatic")
    local text = kit.read_file(dir .. "/config")
    kit.write_file(dir .. "/config", text .. "mailboxes.unheld-parent = own-mailbox\n")
    local line = select(2, text:gsub("\n", "\n")) + 1
    fails(function() rooms.open_home(dir) end, dir .. "/config line " .. line .. ":")
    fails(function() rooms.open_home(dir) end, "'mailboxes.unheld-parent' is not a setting any module reads")
    fails(function() rooms.open_home(dir) end, "mailboxes.unheld-parent = own-mailbox")
    -- every later read refuses it too, not only opening.
    fails(function() rooms.read_config(home) end, "line " .. line)
    fails(function() rooms.config_value(home, rooms.MERGE_KEY) end, "line " .. line)
    fails(function() rooms.set_config(home, rooms.MERGE_KEY, "ask") end, "line " .. line)
end)

check("declared settings: a typo and a made-up name are refused the same way", function()
    local dir = kit.fresh_home_dir("config-typo")
    rooms.open_home(dir)
    kit.write_file(dir .. "/config", "# a comment\n\nmailboxes.merge-when-parent-arives = ask\n")
    fails(function() rooms.open_home(dir) end, "config line 3: 'mailboxes.merge-when-parent-arives'")
end)

check("declared settings: set_config refuses an undeclared name and writes nothing", function()
    local dir = kit.fresh_home_dir("config-set")
    local home = rooms.open_home(dir)
    local before = kit.read_file(dir .. "/config")
    fails(function() rooms.set_config(home, "a.b", "c") end, "set_config: 'a.b' is not a setting any module reads")
    fails(function() rooms.set_config(home, "rooms.suggested-token-words", "4") end, "not a setting any module reads")
    same(kit.read_file(dir .. "/config"), before, "config unchanged")
end)

check("declared settings: config_value refuses a name nobody declared (a module forgot its list)", function()
    local home = rooms.open_home(kit.fresh_home_dir("config-lookup"))
    fails(function() rooms.config_value(home, "tree.anything") end,
          "config_value: 'tree.anything' is not a setting any module reads")
end)

-- A scratch src/ folder with declaration files of every shape, to test
-- the gathering rules without touching the real modules.
local declared = require("017-declared-settings")

-- {{{ local function scratch_src
-- files: table "module/filename" → text.  Returns the scratch src path.
local function scratch_src(name, files)
    local src = kit.fresh_home_dir(name)
    os.execute("mkdir -p '" .. src .. "'")
    for path, text in pairs(files) do
        os.execute("mkdir -p '" .. src .. "/" .. path:match("^(.*)/[^/]+$") .. "'")
        kit.write_file(src .. "/" .. path, text)
    end
    return src
end
-- }}}

check("declarations: gathered from every module's <index>-settings.lua, one folder deep only", function()
    local src = scratch_src("decl-good", {
        ["alpha/016-settings.lua"] = 'return { "alpha.one", "alpha.two" }',
        ["beta/036-settings.lua"] = "return {}",
        ["beta/tests/037-settings.lua"] = 'return { "beta.test-only" }',
        ["beta/036-settings.lua-old"] = 'return { "beta.old" }',
        ["gamma/020-other.lua"] = 'return { "gamma.not-a-list-file" }',
    })
    kit.write_file(src .. "/README", "a plain file in src/")
    local got = declared.gather_declarations(src)
    same(got["alpha.one"].module, "alpha") same(got["alpha.two"].file, src .. "/alpha/016-settings.lua")
    same(got["beta.test-only"], nil, "tests/ is not read")
    same(got["beta.old"], nil, "only files named exactly <3 digits>-settings.lua")
    same(got["gamma.not-a-list-file"], nil, "other files are not declarations")
end)

check("declarations: every broken shape is an error naming the file", function()
    local cases = {
        { 'return "alpha.one"', "must return a list" },
        { 'return { a = "alpha.one" }', "must be a plain list" },
        { 'return { [1] = "alpha.one", [3] = "alpha.three" }', "without gaps" },
        { 'return { "alpha one" }', "is not a setting name" },
        { 'return { 7 }', "is not a setting name" },
        { 'return { "alpha.one", "alpha.one" }', "twice" },
        { 'return {', "do not load" },
    }
    for number, case in ipairs(cases) do
        local src = scratch_src("decl-bad-" .. number, { ["alpha/016-settings.lua"] = case[1] })
        fails(function() declared.gather_declarations(src) end, case[2])
        fails(function() declared.gather_declarations(src) end, src .. "/alpha/016-settings.lua")
    end
end)

check("declarations: one name declared by two modules is an error naming both files", function()
    local src = scratch_src("decl-two-owners", {
        ["alpha/016-settings.lua"] = 'return { "shared.name" }',
        ["beta/036-settings.lua"] = 'return { "shared.name" }',
    })
    fails(function() declared.gather_declarations(src) end, "declared by two modules")
    fails(function() declared.gather_declarations(src) end, "alpha/016-settings.lua")
    fails(function() declared.gather_declarations(src) end, "beta/036-settings.lua")
end)

check("declarations: two settings files in one module is an error", function()
    local src = scratch_src("decl-two-files", {
        ["alpha/016-settings.lua"] = 'return { "alpha.one" }',
        ["alpha/017-settings.lua"] = 'return { "alpha.two" }',
    })
    fails(function() declared.gather_declarations(src) end, "two setting declaration files")
end)

check("declarations: check_config_lines names the first undeclared line", function()
    local lines = { { key = "alpha.one", value = "x", number = 2 }, { key = "zeta", value = "y", number = 5 } }
    declared.check_config_lines({ lines[1] }, "/h/config", { ["alpha.one"] = { module = "alpha", file = "f" } })
    fails(function() declared.check_config_lines(lines, "/h/config", { ["alpha.one"] = {} }) end,
          "/h/config line 5: 'zeta'")
end)

check("declarations: this program's src/ is the one room-folders was loaded from", function()
    same(declared.this_src_dir(), DIR .. "/src")
end)

-- Children of unheld parents below start their own mailboxes and merge
-- automatically if a parent arrives (015-test-mailboxes tests both values
-- of the merge setting).
local home = kit.test_home(rooms, "rooms", "automatic")
spec_home = home
local top, middle, bottom, girlfriend, coder
local GIRLFRIEND_PHONE = member("203.0.113.20", 7777)
local GIRLFRIEND_LAPTOP = member("gf.example.org", 7801)
local CODER = member("198.51.100.4", 9000)

check("make the owner's example tree and two direct messages", function()
    top = rooms.make_room(home, spec("home", "home-token", "group", "", { GIRLFRIEND_PHONE }))
    middle = rooms.make_room(home, spec("ritz", "ritz-token", "group", rooms.token_fingerprint("home-token")))
    bottom = rooms.make_room(home, spec("programming", "prog-token", "group", rooms.token_fingerprint("ritz-token"),
                                        { GIRLFRIEND_PHONE, CODER }))
    girlfriend = rooms.make_room(home, spec("girlfriend", "gf-dm-token", "direct", "", { GIRLFRIEND_PHONE, GIRLFRIEND_LAPTOP }))
    coder = rooms.make_room(home, spec("coder", "coder-dm-token", "direct", "", { CODER }))
    for _, tag in ipairs({ top, middle, bottom, girlfriend, coder }) do
        same(rooms.is_local_tag(tag), true, "tag shape " .. tag)
    end
end)

check("every room folder holds entry, an empty withheld, flagged and log (and nothing half-built is left)", function()
    for _, tag in ipairs({ top, middle, bottom, girlfriend, coder }) do
        same(kit.read_file(rooms.withheld_path(home, tag)), "", "withheld")
        same(kit.read_file(rooms.flagged_path(home, tag)), "", "flagged")
        same(rooms.flagged_path(home, tag), home.dir .. "/rooms/" .. tag .. "/flagged", "flagged_path")
        same(kit.read_file(rooms.log_path(home, tag)), "", "log")
        same(exists(rooms.entry_path(home, tag)), true, "entry")
    end
    local listing = io.popen("ls -A '" .. home.dir .. "/rooms'"):read("*a")
    same(listing:find("%.new%-") == nil, true, "no .new- folder")
end)

check("paths: room_dir, entry, withheld, where, log", function()
    same(rooms.room_dir(home, top), home.dir .. "/rooms/" .. top)
    same(rooms.where_path(home, top), home.dir .. "/rooms/" .. top .. "/where")
    fails(function() rooms.room_dir(home, "home") end, "not a local tag")
end)

check("a direct message and a group room are read by the same code", function()
    local dm = rooms.read_entry(home, girlfriend)
    local group = rooms.read_entry(home, bottom)
    same(dm.kind, "direct") same(group.kind, "group")
    same(dm.label, "girlfriend") same(group.label, "programming")
    same(#dm.members, 2, "two machines, one person") same(dm.members[2].address, "gf.example.org")
    same(dm.members[2].port, 7801) same(group.members[2].port, 9000)
    same(group.parent, rooms.token_fingerprint("ritz-token"))
    same(dm.parent, "") same(dm.filed_under, "")
    same(dm.mailbox, rooms.direct_mailbox(home), "the direct message is in the direct mailbox")
    same(group.mailbox, rooms.read_entry(home, top).mailbox, "programming is in home's mailbox")
end)

check("list_rooms: every tag sorted; list_rooms_by_kind splits direct from group", function()
    local all = { top, middle, bottom, girlfriend, coder }
    table.sort(all)
    same_list(rooms.list_rooms(home), all)
    local directs = { girlfriend, coder }
    table.sort(directs)
    same_list(rooms.list_rooms_by_kind(home, "direct"), directs)
    same(#rooms.list_rooms_by_kind(home, "group"), 3)
    fails(function() rooms.list_rooms_by_kind(home, "channel") end, "kind must be")
end)

check("find_by_fingerprint: the room holding that token, or \"\"", function()
    same(rooms.find_by_fingerprint(home, rooms.token_fingerprint("ritz-token")), middle)
    same(rooms.find_by_fingerprint(home, rooms.token_fingerprint("nobody-holds-this")), "")
    fails(function() rooms.find_by_fingerprint(home, "ritz-token") end, "needs a fingerprint")
end)

check("a token already held here is refused (make_room and change_token)", function()
    fails(function() rooms.make_room(home, spec("again", "ritz-token", "group", "")) end, "already held here by room " .. middle)
    fails(function() rooms.change_token(home, top, "prog-token") end, "already held here by room " .. bottom)
end)

check("the refusal never shows the token itself", function()
    local ok, problem = pcall(rooms.make_room, home, spec("again", "ritz-token", "group", ""))
    same(ok, false) same(tostring(problem):find("ritz-token", 1, true), nil, "token absent from error")
end)

check("a child whose parent is not held here is allowed (it is a top room on this screen)", function()
    local orphan = rooms.make_room(home, spec("stranger's child", "orphan-token", "group", rooms.token_fingerprint("unheld")))
    same(rooms.read_entry(home, orphan).parent, rooms.token_fingerprint("unheld"))
end)

check("a room cannot be placed inside itself", function()
    -- top under bottom: bottom is below top already.
    fails(function() rooms.write_parent(home, top, rooms.token_fingerprint("prog-token")) end, "inside itself")
    -- a room as its own parent.
    fails(function() rooms.write_parent(home, middle, rooms.token_fingerprint("ritz-token")) end, "inside itself")
    -- a new room naming, as parent, a room that already names the new token.
    local waiting = rooms.make_room(home, spec("waiting child", "w-child", "group", rooms.token_fingerprint("w-parent")))
    fails(function() rooms.make_room(home, spec("w", "w-parent", "group", rooms.token_fingerprint("w-child"))) end, "inside itself")
    same(rooms.find_by_fingerprint(home, rooms.token_fingerprint("w-parent")), "", "not made")
    same(rooms.room_exists(home, waiting), true)
end)

check("change_token keeps folder, label, members, withheld and log; only the token changes", function()
    kit.write_file(rooms.log_path(home, middle), "a message record\n")
    kit.write_file(rooms.withheld_path(home, middle), "someone 1\n")
    rooms.write_members(home, middle, { CODER })
    local before = rooms.read_entry(home, middle)
    rooms.change_token(home, middle, "ritz-token-2")
    local after = rooms.read_entry(home, middle)
    same(after.tag, middle, "folder") same(after.label, before.label, "label")
    same(after.token, "ritz-token-2", "token") same(after.parent, before.parent, "parent")
    same(#after.members, 1) same(after.members[1].address, CODER.address, "members")
    same(kit.read_file(rooms.log_path(home, middle)), "a message record\n", "log")
    same(kit.read_file(rooms.withheld_path(home, middle)), "someone 1\n", "withheld")
    same(rooms.find_by_fingerprint(home, rooms.token_fingerprint("ritz-token")), "", "old fingerprint gone")
    same(rooms.find_by_fingerprint(home, rooms.token_fingerprint("ritz-token-2")), middle, "new fingerprint")
end)

check("change_token: the children held here follow the new fingerprint", function()
    same(rooms.read_entry(home, bottom).parent, rooms.token_fingerprint("ritz-token-2"))
end)

check("change_token: the same token again changes nothing", function()
    rooms.change_token(home, middle, "ritz-token-2")
    same(rooms.read_entry(home, bottom).parent, rooms.token_fingerprint("ritz-token-2"))
end)

check("change_token refusals: empty, line break, missing room", function()
    fails(function() rooms.change_token(home, middle, "") end, "non-empty")
    fails(function() rooms.change_token(home, middle, "a\nb") end, "line break")
    fails(function() rooms.change_token(home, "00000000000000000000000000000000", "x") end, "no such room")
end)

check("write_label: any one-line text, labels may repeat", function()
    rooms.write_label(home, coder, "programming")
    same(rooms.read_entry(home, coder).label, "programming")
    rooms.write_label(home, coder, "home/ritz \"odd\"")
    same(rooms.read_entry(home, coder).label, "home/ritz \"odd\"")
    fails(function() rooms.write_label(home, coder, "") end, "non-empty")
end)

check("write_members: written in the order given; shape checked", function()
    rooms.write_members(home, top, { CODER, GIRLFRIEND_LAPTOP, GIRLFRIEND_PHONE })
    local got = rooms.read_entry(home, top).members
    same(got[1].address, CODER.address) same(got[3].address, GIRLFRIEND_PHONE.address)
    fails(function() rooms.write_members(home, top, { { address = "x", port = 80 } }) end, "heard must be")
    fails(function() rooms.write_members(home, top, { { address = "x", heard = 0 } }) end, "port must be")
    rooms.write_members(home, top, {})
    same(#rooms.read_entry(home, top).members, 0, "may be empty")
end)

check("write_heard: records the time for one pair; others untouched", function()
    rooms.write_heard(home, bottom, CODER.address, CODER.port, 1790000123)
    local got = rooms.read_entry(home, bottom).members
    same(got[2].heard, 1790000123) same(got[1].heard, 0)
end)

check("write_heard refusals: not a member (same address, other port), bad time", function()
    fails(function() rooms.write_heard(home, bottom, CODER.address, 9001, 5) end, "is not a member")
    fails(function() rooms.write_heard(home, bottom, CODER.address, CODER.port, -1) end, "whole seconds")
    fails(function() rooms.write_heard(home, bottom, CODER.address, CODER.port, "now") end, "whole seconds")
end)

check("write_filed_under: a held room, not itself, no loop; \"\" unfiles", function()
    rooms.write_filed_under(home, coder, bottom)
    same(rooms.read_entry(home, coder).filed_under, bottom)
    fails(function() rooms.write_filed_under(home, coder, coder) end, "inside itself")
    fails(function() rooms.write_filed_under(home, bottom, coder) end, "inside itself")
    fails(function() rooms.write_filed_under(home, coder, "0123456789abcdef0123456789abcdef") end, "not held here")
    fails(function() rooms.write_filed_under(home, coder, "programming") end, "filed_under must be")
    rooms.write_filed_under(home, coder, "")
    same(rooms.read_entry(home, coder).filed_under, "")
end)

check("make_room: every spec field required, unknown fields refused", function()
    for _, field in ipairs({ "label", "token", "kind", "parent", "filed_under", "members", "mailbox_port" }) do
        local s = spec("x", "spec-" .. field, "group", "")
        s[field] = nil
        fails(function() rooms.make_room(home, s) end, "spec." .. field .. " is missing")
    end
    local s = spec("x", "spec-extra", "group", "")
    s.parent_id = ""
    fails(function() rooms.make_room(home, s) end, "unknown spec field 'parent_id'")
end)

check("make_room: a refused room leaves nothing on disk", function()
    local count = #rooms.list_rooms(home)
    local mailbox_count = #rooms.read_mailboxes(home)
    fails(function() rooms.make_room(home, spec("bad", "bad-kind", "channel", "")) end, "kind must be")
    fails(function() rooms.make_room(home, spec("bad", "bad-parent", "group", "not-a-fingerprint")) end, "parent must be")
    -- a top room refused for its token: no mailbox is made for it either.
    fails(function() rooms.make_room(home, spec("again", "home-token", "group", "")) end, "already held here")
    same(#rooms.list_rooms(home), count)
    same(#rooms.read_mailboxes(home), mailbox_count, "no orphan mailbox")
end)

check("reading and writing a room that does not exist is an error", function()
    local ghost = "00000000000000000000000000000000"
    fails(function() rooms.read_entry(home, ghost) end, "no such room")
    fails(function() rooms.write_label(home, ghost, "x") end, "no such room")
    fails(function() rooms.write_members(home, ghost, {}) end, "no such room")
    fails(function() rooms.write_parent(home, ghost, "") end, "no such room")
end)

check("a hand-edited entry with an address missing its port is refused on read", function()
    local path = rooms.entry_path(home, girlfriend)
    local text = kit.read_file(path)
    kit.write_file(path, (text:gsub(girlfriend .. "%.port%[2%] = 7801\n", "")))
    fails(function() rooms.read_entry(home, girlfriend) end, "port[2] is missing")
    kit.write_file(path, text)
    same(rooms.read_entry(home, girlfriend).members[2].port, 7801, "restored")
end)

check("two folders holding one token (a copied folder) is an error, not a guess", function()
    local copy = "abcdefabcdefabcdefabcdefabcdef00"
    os.execute("cp -r '" .. rooms.room_dir(home, coder) .. "' '" .. home.dir .. "/rooms/" .. copy .. "'")
    local path = home.dir .. "/rooms/" .. copy .. "/entry"
    kit.write_file(path, (kit.read_file(path):gsub(coder, copy)))
    fails(function() rooms.find_by_fingerprint(home, rooms.token_fingerprint("coder-dm-token")) end, "hold the same token")
    os.execute("rm -rf '" .. home.dir .. "/rooms/" .. copy .. "'")
end)

check("list_rooms skips half-built .new- folders but refuses strangers", function()
    os.execute("mkdir '" .. home.dir .. "/rooms/.new-leftover'")
    same(#rooms.list_rooms(home) > 0, true)
    kit.write_file(home.dir .. "/rooms/notes.txt", "x")
    fails(function() rooms.list_rooms(home) end, "unexpected entry")
    os.remove(home.dir .. "/rooms/notes.txt")
end)

check("new_local_tag: 32 lower-case hex, different each time", function()
    local seen = {}
    for _ = 1, 200 do
        local tag = rooms.new_local_tag()
        same(rooms.is_local_tag(tag), true, tag)
        same(seen[tag], nil, "repeat")
        seen[tag] = true
    end
    same(rooms.is_local_tag(("A"):rep(32)), false, "upper")
end)

kit.finish()
