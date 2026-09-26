-- 103-demo-sections.lua — builds each scene of the phase 1 demo and measures it.
--
-- A room is a contact: a label (your own name for it), a token (the shared
-- secret that is the invitation) and every member's (address, port) pairs.
-- A direct message is the same thing with one other person in it.  Each
-- scene here builds one situation of that design on real home folders in a
-- scratch space in RAM, using the phase 1 modules exactly as a later home
-- server will, and hands back a record of what is now true on disk: the
-- entry files as written, folder and link listings, file contents, counts,
-- byte sizes, refusals in the modules' own words, timings.  It prints
-- nothing; 104-demo-view.lua turns each record into text.  Keeping the two
-- apart means a scene that builds wrongly fails here, with its own error,
-- and a view that draws wrongly fails there.
--
-- Every scene that touches an undecided choice runs once per variant, each
-- in a home of its own, so the variants can be compared side by side.
--
-- Scenes, in the order the demo shows them (issue 106):
--   entries    a direct message and a group room side by side, one reader
--   tokens     suggested tokens, a typed one, a token changed by hand
--   tree       a three-level tree, the same tree on a second home, a refusal
--   members    a room of six, one withheld
--   leaving    a forged leave, a confirmed leave, speaking again
--   ignoring   mark and hide, and an ignored address refused as a member
--   people     people/ per direct-message contact, and label collisions
--   log        late, repeated, conflicting, edited; two homes; bytes
--   tally      the options tally over every module's options file

local sections = {}

-- A fixed starting clock for scripted messages and "last heard" times, so
-- every run of the demo writes the same figures and they can be checked by
-- eye.  2026-09-23 12:00:00 UTC, the day the planning document was written.
local SCRIPT_T0 = 1790164800

-- The people of the owner's example, each with the machines they are
-- reached at.  Addresses come from the ranges set aside for documentation
-- (192.0.2.x, 198.51.100.x, 203.0.113.x, example.org), so nothing here can
-- ever be a real machine.  Every address carries its own port: there is no
-- default port in rao-chat.  The girlfriend has two machines, so she is one
-- person with two member pairs.
local PEOPLE = {
    housemate  = { { address = "192.0.2.10",         port = 7001 } },
    girlfriend = { { address = "198.51.100.20",      port = 7002 },
                   { address = "girlfriend.example.org", port = 7002 } },
    coder      = { { address = "203.0.113.30",       port = 7003 } },
}

-- Six machines for the room-of-six scenes (members, leaving).
local SIX = {
    { address = "192.0.2.61", port = 7061 }, { address = "192.0.2.62", port = 7062 },
    { address = "192.0.2.63", port = 7063 }, { address = "192.0.2.64", port = 7064 },
    { address = "192.0.2.65", port = 7065 }, { address = "192.0.2.66", port = 7066 },
}

-- {{{ local function pair_text
-- A member as the modules write it in withheld, heard and a log's `from`:
-- "<address> <port>", one space (105's shape, posted 2026-09-25 20:13).
local function pair_text(member)
    return member.address .. " " .. tostring(member.port)
end
-- }}}

-- {{{ local function fresh_members
-- Copies a list of {address, port} into the entry's member shape, with
-- heard = 0 ("never heard", 101's entry rule), so make_room gets new tables
-- and the constants above are never changed by anyone.
local function fresh_members(list)
    local members = {}
    for _, member in ipairs(list) do
        members[#members + 1] = { address = member.address, port = member.port, heard = 0 }
    end
    return members
end
-- }}}

-- {{{ local function joined_members
-- Several people's machines as one member list, in the order named.
local function joined_members(names)
    local list = {}
    for _, name in ipairs(names) do
        for _, member in ipairs(PEOPLE[name]) do
            list[#list + 1] = member
        end
    end
    return fresh_members(list)
end
-- }}}

-- {{{ local function new_home
-- A fresh home for one scene.  Every undecided choice is set before anything
-- else happens, because loaded modules listen on the change bell and read
-- their config keys the moment the first room is made.  `overrides` (key →
-- value) replaces the baseline for the choices this scene varies.  Gives the
-- home table { dir = string }.
local function new_home(ctx, label, overrides)
    local place = ctx.probes.fresh_dir(ctx.scratch, ctx.scratch .. "/" .. label)
    local home = ctx.m.rooms.open_home(place .. "/rao-home")
    for _, setting in ipairs(ctx.baseline) do
        ctx.m.rooms.set_config(home, setting.key, setting.value)
    end
    for key, value in pairs(overrides) do
        ctx.m.rooms.set_config(home, key, value)
    end
    return home
end
-- }}}

-- {{{ local function variants_of
-- The variant names of one config key, as the options files list them.  The
-- demo runs whatever variants the builders recorded, so a variant added
-- later is demonstrated without editing this file.
local function variants_of(ctx, key)
    local names = ctx.variants_by_key[key]
    if names == nil then
        -- no options file records this key: the scene cannot run every variant
        error("no options file records the config key '" .. key .. "'")
    end
    -- (recorded: hand back the names)
    return names
end
-- }}}

-- {{{ local function make_room
-- One room, every field of 101's spec given (make_room refuses a missing
-- one).  `parent` is a token fingerprint or "", as in the entry.
local function make_room(ctx, home, label, token, kind, parent, members)
    return ctx.m.rooms.make_room(home, { label = label, token = token, kind = kind,
                                         parent = parent, filed_under = "",
                                         members = members })
end
-- }}}

-- {{{ local function attempt
-- Runs `action` and gives { ok = bool, answer = string }: the action's own
-- answer when it ran, or the refusal's words when it raised an error.  The
-- refusals ARE what several scenes exist to show, so they are kept, not
-- hidden.
local function attempt(action)
    local ok, answer = pcall(action)
    return { ok = ok, answer = tostring(answer) }
end
-- }}}

-- {{{ local function member_texts
-- A room's members as "address port" strings, in entry order.
local function member_texts(ctx, home, tag)
    local texts = {}
    for _, member in ipairs(ctx.m.rooms.read_entry(home, tag).members) do
        texts[#texts + 1] = pair_text(member)
    end
    return texts
end
-- }}}

-- {{{ local function send_texts
-- The send list (103: members minus withheld) as "address port" strings.
local function send_texts(ctx, home, tag)
    local texts = {}
    for _, member in ipairs(ctx.m.members.send_list(home, tag)) do
        texts[#texts + 1] = pair_text(member)
    end
    return texts
end
-- }}}

-- {{{ local function message
-- One log record as 105 files it: `from` is "me" or "<address> <port>".
local function message(ctx, from, written, arrived, text)
    return { id = ctx.m.log.new_message_id(), from = from, written = written,
             arrived = arrived, text = text }
end
-- }}}

-- {{{ function sections.entries
-- A direct message and a group room side by side: the flat rooms/ listing,
-- each entry exactly as written, both read back by the one entry reader,
-- listed by kind; then an address without its port refused twice — when
-- making a room, and when reading an entry edited by hand.
function sections.entries(ctx)
    local rooms = ctx.m.rooms
    local home = new_home(ctx, "entries", {})
    local started = ctx.probes.now()
    local direct = make_room(ctx, home, "girlfriend", "willow-lantern-cobalt-fig", "direct", "",
                             joined_members({ "girlfriend" }))
    local group = make_room(ctx, home, "home", "maple-orbit-velvet-tin", "group", "",
                            joined_members({ "housemate", "girlfriend" }))
    local record = { home_dir = home.dir, seconds_to_make = ctx.probes.now() - started,
                     folder = ctx.probes.entries(home.dir .. "/rooms"),
                     files = ctx.probes.files_with_sizes(home.dir .. "/rooms"), rooms = {} }
    for _, tag in ipairs({ direct, group }) do
        record.rooms[#record.rooms + 1] = {
            tag = tag,
            entry_text = ctx.probes.read_text(rooms.entry_path(home, tag)),
            entry_bytes = ctx.probes.bytes(rooms.entry_path(home, tag)),
            read = rooms.read_entry(home, tag),
        }
    end
    record.direct_list = rooms.list_rooms_by_kind(home, "direct")
    record.group_list = rooms.list_rooms_by_kind(home, "group")
    -- refused on the way in: a member with an address and no port
    record.unpaired_make = attempt(function()
        return make_room(ctx, home, "no-port", "no-port-token", "direct", "",
                         { { address = "192.0.2.99", heard = 0 } })
    end)
    -- refused on the way out: a copy of the group's entry, edited by hand to
    -- lose port[2], in a home of its own so the real one stays whole
    local broken_home = new_home(ctx, "entries-hand-edited", {})
    local broken = make_room(ctx, broken_home, "home", "maple-orbit-velvet-tin", "group", "",
                             joined_members({ "housemate", "girlfriend" }))
    local path = rooms.entry_path(broken_home, broken)
    local text = ctx.probes.read_text(path)
    local cut, count = text:gsub("[^\n]*%.port%[2%][^\n]*\n", "")
    if count ~= 1 then
        -- the entry is not shaped as 101's contract says: the scene is wrong
        error("entries: expected one port[2] line in the entry, found " .. count)
    end
    -- (exactly one line removed: write the damaged entry back)
    ctx.probes.write_text(path, cut)
    record.unpaired_read = attempt(function() return rooms.read_entry(broken_home, broken) end)
    record.removed_line = text:match("([^\n]*%.port%[2%][^\n]*)")
    return record
end
-- }}}

-- {{{ function sections.tokens
-- Suggested readable tokens under each word count; a typed token accepted
-- as written; a token changed by hand, with the room's folder, label,
-- members and log unchanged before and after.
function sections.tokens(ctx)
    local rooms = ctx.m.rooms
    local record = { suggested = {} }
    for _, count in ipairs(variants_of(ctx, "rooms.suggested-token-words")) do
        local home = new_home(ctx, "tokens-words-" .. count,
                              { ["rooms.suggested-token-words"] = count })
        local list = {}
        for _ = 1, 3 do
            list[#list + 1] = rooms.suggest_token(home)
        end
        record.suggested[#record.suggested + 1] = { words = count, tokens = list }
    end
    local home = new_home(ctx, "tokens", {})
    record.typed = "our kitchen table, 2026 (no rules on tokens)"
    local tag = make_room(ctx, home, "kitchen", record.typed, "group", "",
                          joined_members({ "housemate", "girlfriend" }))
    record.typed_back = rooms.read_entry(home, tag).token
    record.duplicate_token = attempt(function()
        return make_room(ctx, home, "kitchen again", record.typed, "group", "", {})
    end)
    for position = 1, 5 do
        ctx.m.log.append(home, tag, message(ctx, pair_text(PEOPLE.housemate[1]),
                                             SCRIPT_T0 + position * 60, SCRIPT_T0 + position * 60,
                                             "kitchen note " .. position))
    end
    -- {{{ local function state
    local function state()
        local entry = rooms.read_entry(home, tag)
        return { token = entry.token, fingerprint = rooms.token_fingerprint(entry.token),
                 label = entry.label, members = #entry.members,
                 messages = #ctx.m.log.read(home, tag),
                 log_bytes = ctx.probes.bytes(rooms.log_path(home, tag)),
                 folder = rooms.room_dir(home, tag) }
    end
    -- }}}
    record.before = state()
    local new_token = rooms.suggest_token_of(4)
    local started = ctx.probes.now()
    rooms.change_token(home, tag, new_token)
    record.seconds_to_change = ctx.probes.now() - started
    record.after = state()
    return record
end
-- }}}

-- {{{ local function tree_lines
-- The home's tree drawn with 102's text drawing, labels as this home
-- names its rooms: 102 works the tree out (forest), 024 draws it.
local function tree_lines(ctx, home)
    return ctx.m.forest_text.lines(ctx.m.tree.forest(home))
end
-- }}}

-- The three rooms of the tree scene: each child names its parent by the
-- parent's token fingerprint.  The second home holds the same three tokens
-- under labels of its own.
local TREE = {
    { token = "maple-orbit-velvet-tin",  label_a = "home",     label_b = "family",
      parent = nil,                       people = { "housemate", "girlfriend", "coder" } },
    { token = "copper-kettle-sage-moss", label_a = "kitchen",  label_b = "cooking",
      parent = "maple-orbit-velvet-tin",  people = { "housemate", "girlfriend" } },
    { token = "basil-thyme-ledger-oak",  label_a = "shopping", label_b = "groceries",
      parent = "copper-kettle-sage-moss", people = { "girlfriend" } },
}

-- {{{ local function build_tree
-- The TREE on one home under one set of labels (`label_key`).  Gives a list
-- of { tag, label, fingerprint, parent, where } in TREE order.
local function build_tree(ctx, home, label_key)
    local rooms = ctx.m.rooms
    local built = {}
    for _, room in ipairs(TREE) do
        local parent = ""
        if room.parent then
            -- a child room: its entry names the parent by fingerprint
            parent = rooms.token_fingerprint(room.parent)
        end
        -- (a top room: no parent)
        local tag = make_room(ctx, home, room[label_key], room.token, "group", parent,
                              joined_members(room.people))
        built[#built + 1] = { tag = tag, label = room[label_key], parent = parent,
                              fingerprint = rooms.token_fingerprint(room.token) }
    end
    for _, room in ipairs(built) do
        room.where = ctx.probes.read_text(rooms.where_path(home, room.tag))
    end
    return built
end
-- }}}

-- {{{ function sections.tree
-- home → kitchen → shopping, drawn; the same tree on a second home with
-- other labels, matched by fingerprint; an address refused in a child room
-- because it is not in the parent.
function sections.tree(ctx)
    local home_a = new_home(ctx, "tree-a", {})
    local home_b = new_home(ctx, "tree-b", {})
    local record = { a = build_tree(ctx, home_a, "label_a"), b = build_tree(ctx, home_b, "label_b") }
    record.lines_a = tree_lines(ctx, home_a)
    record.lines_b = tree_lines(ctx, home_b)
    -- the coder is in home but not in kitchen: kitchen's child, shopping,
    -- must refuse the coder; the girlfriend (in kitchen) is let in
    local shopping = record.a[3].tag
    local coder, housemate = PEOPLE.coder[1], PEOPLE.housemate[1]
    local may, why = ctx.m.tree.may_join(home_a, shopping, coder.address, coder.port)
    record.may_join_coder = { answer = may, reason = why }
    local may_h, why_h = ctx.m.tree.may_join(home_a, shopping, housemate.address, housemate.port)
    record.may_join_housemate = { answer = may_h, reason = why_h }
    record.add_coder = attempt(function()
        return ctx.m.members.add_member(home_a, shopping, coder.address, coder.port)
    end)
    record.add_housemate = attempt(function()
        return ctx.m.members.add_member(home_a, shopping, housemate.address, housemate.port)
    end)
    record.shopping_members = member_texts(ctx, home_a, shopping)
    record.kitchen_members = member_texts(ctx, home_a, record.a[2].tag)
    return record
end
-- }}}

-- {{{ function sections.members
-- A room of six: every member is on the send list; one is withheld; the
-- send list shrinks by one while the member list does not; un-withholding
-- brings them back.
function sections.members(ctx)
    local home = new_home(ctx, "members", {})
    local tag = make_room(ctx, home, "the-six", "six-candles-river-slate", "group", "",
                          fresh_members(SIX))
    local chosen = SIX[3]
    local record = { members_before = member_texts(ctx, home, tag),
                     send_before = send_texts(ctx, home, tag),
                     withheld_before = ctx.probes.read_text(ctx.m.rooms.withheld_path(home, tag)),
                     chosen = pair_text(chosen) }
    ctx.m.members.withhold(home, tag, chosen.address, chosen.port)
    record.members_after = member_texts(ctx, home, tag)
    record.send_after = send_texts(ctx, home, tag)
    record.withheld_after = ctx.probes.read_text(ctx.m.rooms.withheld_path(home, tag))
    ctx.m.members.unwithhold(home, tag, chosen.address, chosen.port)
    record.send_restored = send_texts(ctx, home, tag)
    return record
end
-- }}}

-- {{{ function sections.leaving
-- A leave notice that nobody confirms changes nothing; a confirmed leave
-- removes the address; the same address speaking again is added back.
function sections.leaving(ctx)
    local rooms, members = ctx.m.rooms, ctx.m.members
    local home = new_home(ctx, "leaving", {})
    local tag = make_room(ctx, home, "the-six", "six-candles-river-slate", "group", "",
                          fresh_members(SIX))
    local forged, real = SIX[2], SIX[5]
    local entry_path = rooms.entry_path(home, tag)
    local record = { forged = pair_text(forged), real = pair_text(real),
                     count_start = #member_texts(ctx, home, tag),
                     entry_before = ctx.probes.read_text(entry_path) }
    -- Someone sends a leave notice "from" SIX[2].  The only way an address
    -- is removed is confirm_leave, which phase 2 calls only after its
    -- call-back check (issue 204) asks SIX[2] and SIX[2] says it left.
    -- Here SIX[2] answers that it is still here, so nothing is called:
    -- this is 103's design (it keeps no pending-leave file), and the scene
    -- shows its effect — the room's files byte for byte unchanged.
    record.count_after_forged = #member_texts(ctx, home, tag)
    record.entry_unchanged = ctx.probes.read_text(entry_path) == record.entry_before
    record.forged_still_member = members.is_member(home, tag, forged.address, forged.port)
    -- SIX[5] really leaves: the call-back check confirms, phase 2 calls this
    record.confirmed = attempt(function()
        return members.confirm_leave(home, tag, real.address, real.port)
    end)
    record.members_after_leave = member_texts(ctx, home, tag)
    record.send_after_leave = send_texts(ctx, home, tag)
    -- SIX[5] speaks in the room again
    record.spoke = attempt(function()
        return members.heard_from(home, tag, real.address, real.port, SCRIPT_T0 + 900)
    end)
    record.members_after_speaking = member_texts(ctx, home, tag)
    record.entry_after = ctx.probes.read_text(rooms.entry_path(home, tag))
    return record
end
-- }}}

-- {{{ local function ignoring_once
-- One home under one `ignore.hide-files` variant: one address ignored at
-- `mark`, one at `hide`, a short conversation delivered the way a home
-- server will (asking 103a whether to file each message before 105 files
-- it), then the room as shown, and the member filter.
local function ignoring_once(ctx, variant)
    local rooms, members, ignore, log = ctx.m.rooms, ctx.m.members, ctx.m.ignore, ctx.m.log
    local home = new_home(ctx, "ignoring-" .. variant, { ["ignore.hide-files"] = variant })
    local speakers = { SIX[1], SIX[2], SIX[3] }
    local tag = make_room(ctx, home, "the-three", "three-owls-amber-gate", "group", "",
                          fresh_members(speakers))
    local marked, hidden = SIX[2], SIX[3]
    ignore.ignore(home, marked.address, marked.port, "mark", "*", SCRIPT_T0)
    ignore.ignore(home, hidden.address, hidden.port, "hide", "*", SCRIPT_T0)
    local script = {
        { who = SIX[1], offset = 0,  text = "morning, all" },
        { who = marked, offset = 10, text = "(something you chose not to read)" },
        { who = "me",   offset = 20, text = "morning!" },
        { who = hidden, offset = 30, text = "(something you chose never to see)" },
        { who = SIX[1], offset = 40, text = "coffee at ten?" },
    }
    local record = { variant = variant, delivered = #script, shown = {}, levels = {} }
    for _, line in ipairs(script) do
        local from, files = "me", true
        if line.who ~= "me" then
            -- someone else's message: the ignore list decides whether it is filed
            from = pair_text(line.who)
            files = ignore.files_message(home, tag, line.who.address, line.who.port)
        end
        -- (your own message: always filed)
        if files then
            -- filed in the log (hide under "filed" still files it; it is never shown)
            log.append(home, tag, message(ctx, from, SCRIPT_T0 + line.offset,
                                           SCRIPT_T0 + line.offset, line.text))
        end
        -- (not filed: hide under "not-filed" drops it before the log)
    end
    record.ignore_file = ctx.probes.read_text(rooms.ignore_path(home))
    local level_of = { me = "none" }
    for _, member in ipairs(speakers) do
        local level = ignore.how_ignored(home, tag, member.address, member.port)
        level_of[pair_text(member)] = level
        record.levels[#record.levels + 1] = { who = pair_text(member), level = level }
    end
    -- the room as a client shows it: 105's ordered view with each message's
    -- ignore level beside it; 104-demo-view applies the levels
    for _, shown in ipairs(log.read_ordered(home, tag)) do
        record.shown[#record.shown + 1] = { from = shown.from, text = shown.text,
                                            level = level_of[shown.from] }
    end
    record.filed = #log.read(home, tag)
    record.log_bytes = ctx.probes.bytes(rooms.log_path(home, tag))
    -- another room that does not yet hold the ignored addresses; a member's
    -- list (phase 2's contact syncing) brings them back
    local other = make_room(ctx, home, "the-other", "fern-quartz-harbor-mint", "group", "",
                            fresh_members({ SIX[1] }))
    record.readd_hidden = attempt(function()
        return members.add_member(home, other, hidden.address, hidden.port)
    end)
    record.readd_marked = attempt(function()
        return members.add_member(home, other, marked.address, marked.port)
    end)
    record.other_members = member_texts(ctx, home, other)
    ignore.unignore(home, hidden.address, hidden.port, "*")
    record.readd_after_unignore = attempt(function()
        return members.add_member(home, other, hidden.address, hidden.port)
    end)
    record.other_members_after = member_texts(ctx, home, other)
    return record
end
-- }}}

-- {{{ function sections.ignoring
-- Ignoring at `mark` and `hide`, once per `ignore.hide-files` variant (is
-- a hidden address's message filed at all?).
function sections.ignoring(ctx)
    local record = { variants = {} }
    for _, variant in ipairs(variants_of(ctx, "ignore.hide-files")) do
        record.variants[#record.variants + 1] = ignoring_once(ctx, variant)
    end
    return record
end
-- }}}

-- {{{ local function people_home
-- The owner's household as rooms: three direct messages (one per person)
-- and the group rooms of the tree scene, plus a top room "programming".
local function people_home(ctx, label, overrides)
    local rooms = ctx.m.rooms
    local home = new_home(ctx, label, overrides)
    local tokens = { housemate = "dm-housemate-birch-lamp", girlfriend = "dm-girlfriend-willow-fig",
                     coder = "dm-coder-cobalt-reed" }
    for _, name in ipairs({ "housemate", "girlfriend", "coder" }) do
        make_room(ctx, home, name, tokens[name], "direct", "", joined_members({ name }))
    end
    build_tree(ctx, home, "label_a")
    make_room(ctx, home, "programming", "parser-lantern-quill-dune", "group", "",
              joined_members({ "girlfriend", "coder" }))
    return home
end
-- }}}

-- {{{ function sections.people
-- people/ per direct-message contact: which top rooms each person shares
-- with you (the girlfriend's two machines count once); then a second top
-- room also labelled "programming", under each collision mode.
function sections.people(ctx)
    local record = { collisions = {} }
    local home = people_home(ctx, "people", {})
    record.folders = ctx.probes.entries(home.dir .. "/people")
    record.links = ctx.probes.links_with_targets(home.dir .. "/people")
    record.labels = {}
    for _, tag in ipairs(ctx.m.rooms.list_rooms(home)) do
        record.labels[tag] = ctx.m.rooms.read_entry(home, tag).label
    end
    for _, variant in ipairs(variants_of(ctx, "people.link-collision")) do
        local other = people_home(ctx, "people-collision-" .. variant,
                                  { ["people.link-collision"] = variant })
        make_room(ctx, other, "programming", "second-programming-room", "group", "",
                  joined_members({ "coder" }))
        record.collisions[#record.collisions + 1] = {
            variant = variant,
            links = ctx.probes.links_with_targets(other.dir .. "/people/coder"),
        }
    end
    return record
end
-- }}}

-- The scripted conversation for the log scene.  Offsets are seconds after
-- SCRIPT_T0.  The fourth message was written at +30 but only arrives at
-- +200 (its sender's server was away), so it is last in the file and
-- second on screen.
local SCRIPT = {
    { who = "me",         written = 0,   arrived = 0,   text = "anyone around to pair on the parser?" },
    { who = "coder",      written = 60,  arrived = 61,  text = "yes, give me ten minutes" },
    { who = "me",         written = 120, arrived = 120, text = "great, I pushed the branch parsre" },
    { who = "girlfriend", written = 30,  arrived = 200, text = "I can look after dinner" },
}

-- How many messages the size measurement files per record shape: enough
-- for bytes per message to settle, small enough to take well under a second.
local BULK_COUNT = 200

-- {{{ local function from_of
-- "me", or the first machine of a named person as "<address> <port>".
local function from_of(who)
    if who == "me" then
        -- your own messages are filed as from "me"
        return "me"
    end
    -- (someone else: the address the message arrived from)
    return pair_text(PEOPLE[who][1])
end
-- }}}

-- {{{ local function file_script
-- Files SCRIPT into a room in the order given by `order` (a list of
-- positions in SCRIPT), reusing the ids in `ids` so two homes file the
-- very same messages.  Gives the answers, one per filing.
local function file_script(ctx, home, tag, ids, order)
    local answers = {}
    for _, position in ipairs(order) do
        local line = SCRIPT[position]
        answers[#answers + 1] = ctx.m.log.append(home, tag, {
            id = ids[position], from = from_of(line.who), written = SCRIPT_T0 + line.written,
            arrived = SCRIPT_T0 + line.arrived, text = line.text })
    end
    return answers
end
-- }}}

-- {{{ local function order_of
-- A room's messages as shown: { id, written offset, from, text, edited }.
local function order_of(ctx, home, tag)
    local list = {}
    for _, shown in ipairs(ctx.m.log.read_ordered(home, tag)) do
        list[#list + 1] = { id = shown.id, written = shown.written - SCRIPT_T0,
                            from = shown.from, text = shown.text, edited = shown.edited }
    end
    return list
end
-- }}}

-- {{{ function sections.log
-- For each record shape: the script filed (the late message placed in
-- order), a repeat answered `duplicate`, the same id with different text
-- raised as an error, an edit with its original kept, the raw file, and
-- bytes per message over BULK_COUNT messages.  Then the same messages on
-- two homes in different arrival orders, shown in the same order.
function sections.log(ctx)
    local log = ctx.m.log
    local record = { t0 = SCRIPT_T0, shapes = {} }
    for _, shape in ipairs(variants_of(ctx, "log.record-shape")) do
        local home = new_home(ctx, "log-" .. shape, { ["log.record-shape"] = shape })
        local tag = make_room(ctx, home, "programming", "parser-lantern-quill-dune", "group", "",
                              joined_members({ "girlfriend", "coder" }))
        local ids = {}
        for position = 1, #SCRIPT do
            ids[position] = log.new_message_id()
        end
        local result = { shape = shape, answers = file_script(ctx, home, tag, ids, { 1, 2, 3, 4 }) }
        -- the coder's message delivered again (the first answer was lost)
        result.repeat_answer = attempt(function()
            return file_script(ctx, home, tag, ids, { 2 })[1]
        end)
        -- the same id arriving with different words
        result.conflict = attempt(function()
            return log.append(home, tag, { id = ids[2], from = from_of("coder"),
                                           written = SCRIPT_T0 + 60, arrived = SCRIPT_T0 + 300,
                                           text = "yes, give me twenty minutes" })
        end)
        -- the owner corrects the branch name
        result.edit = attempt(function()
            return log.correct(home, tag, { id = log.new_message_id(), from = "me",
                                            written = SCRIPT_T0 + 150, arrived = SCRIPT_T0 + 150,
                                            target = ids[3],
                                            text = "great, I pushed the branch parser" })
        end)
        result.in_file = {}
        for _, filed in ipairs(log.read(home, tag)) do
            result.in_file[#result.in_file + 1] = { kind = filed.kind, from = filed.from,
                                                    written = filed.written - SCRIPT_T0,
                                                    text = filed.text }
        end
        result.shown = order_of(ctx, home, tag)
        local path = ctx.m.rooms.log_path(home, tag)
        result.raw = ctx.probes.read_text(path)
        result.bytes = ctx.probes.bytes(path)
        -- bytes per message, measured over a room of plain one-line messages
        local bulk = make_room(ctx, home, "bulk", "bulk-measure-" .. shape, "group", "",
                               joined_members({ "coder" }))
        local started = ctx.probes.now()
        for number = 1, BULK_COUNT do
            log.append(home, bulk, message(ctx, from_of("coder"), SCRIPT_T0 + number,
                                            SCRIPT_T0 + number, "bulk message number " .. number))
        end
        result.bulk = { count = BULK_COUNT, seconds = ctx.probes.now() - started,
                        bytes = ctx.probes.bytes(ctx.m.rooms.log_path(home, bulk)) }
        record.shapes[#record.shapes + 1] = result
    end
    -- two homes, the same room (same token, different local tags), the same
    -- four messages arriving in opposite orders
    local ids = {}
    for position = 1, #SCRIPT do
        ids[position] = log.new_message_id()
    end
    local homes = {}
    for _, side in ipairs({ { label = "log-two-a", order = { 1, 2, 3, 4 } },
                            { label = "log-two-b", order = { 4, 3, 2, 1 } } }) do
        local home = new_home(ctx, side.label, {})
        local tag = make_room(ctx, home, "programming", "parser-lantern-quill-dune", "group", "",
                              joined_members({ "girlfriend", "coder" }))
        file_script(ctx, home, tag, ids, side.order)
        local in_file = {}
        for _, filed in ipairs(log.read(home, tag)) do
            in_file[#in_file + 1] = filed.id
        end
        homes[#homes + 1] = { tag = tag, arrival = side.order, in_file = in_file,
                              shown = order_of(ctx, home, tag) }
    end
    local same = #homes[1].shown == #homes[2].shown
    for position, shown in ipairs(homes[1].shown) do
        if homes[2].shown[position] == nil or homes[2].shown[position].id ~= shown.id then
            -- the two homes disagree at this place
            same = false
        end
        -- (the same message at the same place: keep comparing)
    end
    record.two_homes = { homes = homes, identical = same }
    return record
end
-- }}}

-- {{{ function sections.tally
-- The options tally over the real project, gathered once by the main
-- program (it also sets the demo's baseline from it) and passed through.
function sections.tally(ctx)
    return { record = ctx.options, counts = ctx.gather.counts(ctx.options) }
end
-- }}}

-- The order the scenes are shown in, with their titles.  A list, not the
-- keys of `sections`, so the order is the story's order.
sections.ORDER = {
    { key = "entries",  title = "Rooms are entries: a direct message and a group room, one reader" },
    { key = "tokens",   title = "Tokens: suggested, typed, changed by hand (rooms.suggested-token-words)" },
    { key = "tree",     title = "The tree: child rooms by fingerprint, and the parent-membership rule" },
    { key = "members",  title = "Members and withheld: a room of six" },
    { key = "leaving",  title = "Leaving: forged, confirmed, and speaking again" },
    { key = "ignoring", title = "Ignoring: mark and hide, and the member filter" },
    { key = "people",   title = "people/: what we share with each person (people.link-collision)" },
    { key = "log",      title = "The message log: late, repeated, conflicting, edited (log.record-shape)" },
    { key = "tally",    title = "Every choice still open (scripts/tally-options)" },
}

-- Exposed for the tests, so they check against the same figures.
sections.SCRIPT_T0 = SCRIPT_T0
sections.PEOPLE = PEOPLE
sections.SIX = SIX

return sections
