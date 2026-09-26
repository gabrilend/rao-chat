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
-- Choices the owner has answered are not varied: they are built in fixed.
--
-- Scenes, in the order the demo shows them (issue 106):
--   entries    a direct message and a group room side by side, one reader
--   tokens     suggested six-word tokens, a typed one, a token changed by hand
--   tree       a three-level tree, the same tree on a second home; a member
--              not in every room above flagged, off the send list, approved;
--              a leaver flagged below; a parent not held: "cannot-check"
--   mailboxes  a top room and its children in one mailbox, direct messages in
--              another, a shared port reported, a parent not held
--   members    a room of six, one withheld
--   leaving    a forged leave, a confirmed leave, speaking again
--   ignoring   mark and hide, every port of an address, the member filter
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

-- Ports for the demo's mailboxes.  Every home the demo makes gets its one
-- direct-message mailbox on DIRECT_PORT at birth (101 refuses a direct room
-- until it exists); each top group room then starts a tree mailbox on the
-- next free port from FIRST_TREE_PORT, counted per home, so no two
-- mailboxes share a port unless a scene asks for it on purpose.  A waiting
-- mailbox (only under mailboxes.unheld-parent = waiting-mailbox) is made on
-- WAITING_PORT the first time a room needs it.
local DIRECT_PORT, FIRST_TREE_PORT, WAITING_PORT = 7700, 7701, 7799

-- {{{ local function new_home
-- A fresh home for one scene.  Every undecided choice is set before anything
-- else happens, because loaded modules listen on the change bell and read
-- their config keys the moment the first room is made.  `overrides` (key →
-- value) replaces the baseline for the choices this scene varies.  Gives the
-- home table { dir = string }, with its direct-message mailbox made.
local function new_home(ctx, label, overrides)
    local place = ctx.probes.fresh_dir(ctx.scratch, ctx.scratch .. "/" .. label)
    local home = ctx.m.rooms.open_home(place .. "/rao-home")
    for _, setting in ipairs(ctx.baseline) do
        ctx.m.rooms.set_config(home, setting.key, setting.value)
    end
    for key, value in pairs(overrides) do
        ctx.m.rooms.set_config(home, key, value)
    end
    ctx.m.rooms.make_mailbox(home, { label = "direct messages", kind = "direct", port = DIRECT_PORT })
    return home
end
-- }}}

-- {{{ local function next_tree_port
-- The next unused tree-mailbox port of this home: one more than the
-- highest port any of its mailboxes names, never below FIRST_TREE_PORT,
-- never WAITING_PORT's neighbourhood (the demo makes far fewer than 98).
local function next_tree_port(ctx, home)
    local highest = FIRST_TREE_PORT - 1
    for _, mailbox in ipairs(ctx.m.rooms.read_mailboxes(home)) do
        if mailbox.kind == "tree" and mailbox.port > highest then
            -- a tree mailbox already on a higher port: go past it
            highest = mailbox.port
        end
        -- (direct, waiting, or a lower tree port: not counted)
    end
    return highest + 1
end
-- }}}

-- What a new group room with a declared parent this home does not hold
-- needs from its maker, by `mailboxes.unheld-parent` (101's switch):
-- its own new tree mailbox needs a port; the waiting mailbox needs to exist.
local UNHELD_PARENT_PORT = {
    ["own-mailbox"] = function(ctx, home)
        return next_tree_port(ctx, home)
    end,
    ["waiting-mailbox"] = function(ctx, home)
        if ctx.m.rooms.waiting_mailbox(home) == "" then
            -- the first room to wait in this home: make the waiting mailbox
            ctx.m.rooms.make_mailbox(home, { label = "waiting for a parent", kind = "waiting",
                                             port = WAITING_PORT })
        end
        -- (already made: the room just joins it)
        return ""
    end,
}

-- {{{ local function mailbox_port_for
-- The `mailbox_port` field of 101's make_room spec: an integer exactly when
-- the room starts a new mailbox (a top group room, or a group room whose
-- parent is not held under own-mailbox), "" when it joins one (every direct
-- message; a child of a held room; a waiting room).  Mirrors 101's table in
-- the contract's "Mailboxes" section.
local function mailbox_port_for(ctx, home, kind, parent)
    if kind == "direct" then
        -- the one direct mailbox, made by new_home
        return ""
    end
    -- (a group room: where does it go?)
    if parent == "" then
        -- a top room starts a tree mailbox of its own
        return next_tree_port(ctx, home)
    end
    -- (a declared child)
    if ctx.m.rooms.find_by_fingerprint(home, parent) ~= "" then
        -- its parent is held here: it joins the parent's mailbox
        return ""
    end
    -- (the parent is not held here: 101's switch decides)
    local variant = ctx.m.rooms.config_value(home, "mailboxes.unheld-parent")
    local choose = UNHELD_PARENT_PORT[variant]
    if choose == nil then
        -- a variant the demo does not know: stop rather than guess
        error("demo: unknown mailboxes.unheld-parent variant '" .. variant .. "'")
    end
    -- (known: its port, or "" after making the waiting mailbox)
    return choose(ctx, home)
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

-- {{{ local function make_room_with_port
-- One room, every field of 101's spec given (make_room refuses a missing
-- one), `mailbox_port` as given: an integer to start a new mailbox, "" to
-- join one.
local function make_room_with_port(ctx, home, label, token, kind, parent, members, mailbox_port)
    return ctx.m.rooms.make_room(home, { label = label, token = token, kind = kind,
                                         parent = parent, filed_under = "",
                                         members = members, mailbox_port = mailbox_port })
end
-- }}}

-- {{{ local function make_room
-- One room with the usual mailbox for its kind and parent (101's table,
-- mailbox_port_for).  `parent` is a token fingerprint or "", as in the entry.
local function make_room(ctx, home, label, token, kind, parent, members)
    return make_room_with_port(ctx, home, label, token, kind, parent, members,
                               mailbox_port_for(ctx, home, kind, parent))
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
-- Suggested readable tokens (six words, fixed by the owner's answer; the
-- word count is read off the suggestions themselves, not assumed); a typed
-- token accepted as written; a token changed by hand, with the room's
-- folder, label, members and log unchanged before and after.
function sections.tokens(ctx)
    local rooms = ctx.m.rooms
    local home = new_home(ctx, "tokens", {})
    local record = { suggested = {} }
    for _ = 1, 3 do
        record.suggested[#record.suggested + 1] = rooms.suggest_token(home)
    end
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
    local new_token = rooms.suggest_token(home)
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

-- {{{ local function room_view
-- One room's member list, send list and flagged file at this moment: what
-- the tree scene shows after each step.
local function room_view(ctx, home, tag)
    return { members = member_texts(ctx, home, tag), send = send_texts(ctx, home, tag),
             flagged = ctx.probes.read_text(ctx.m.rooms.flagged_path(home, tag)) }
end
-- }}}

-- {{{ local function checked
-- 102's three-way check of one address in one room, as { answer, reason }.
local function checked(ctx, home, tag, person)
    local answer, reason = ctx.m.tree.check_member(home, tag, person.address, person.port)
    return { answer = answer, reason = reason }
end
-- }}}

-- {{{ function sections.tree
-- home → kitchen → shopping, drawn; the same tree on a second home with
-- other labels, matched by fingerprint.  Then detection, not refusal: an
-- address that is not in every room above shopping is added but flagged,
-- left off the send list until approved; someone who leaves home shows up
-- flagged in home's children and grandchildren; a room whose parent this
-- home does not hold flags its newcomers "cannot-check".
function sections.tree(ctx)
    local members = ctx.m.members
    local home_a = new_home(ctx, "tree-a", {})
    local home_b = new_home(ctx, "tree-b", {})
    local record = { a = build_tree(ctx, home_a, "label_a"), b = build_tree(ctx, home_b, "label_b") }
    record.lines_a = tree_lines(ctx, home_a)
    record.lines_b = tree_lines(ctx, home_b)
    local home_room, kitchen, shopping = record.a[1].tag, record.a[2].tag, record.a[3].tag
    local coder, housemate, girlfriend = PEOPLE.coder[1], PEOPLE.housemate[1], PEOPLE.girlfriend[1]
    record.kitchen_members = member_texts(ctx, home_a, kitchen)
    -- the coder is in home but not in kitchen, so not in every room above
    -- shopping; the housemate is in both
    record.check_coder = checked(ctx, home_a, shopping, coder)
    record.check_housemate = checked(ctx, home_a, shopping, housemate)
    record.add_coder = attempt(function()
        return members.add_member(home_a, shopping, coder.address, coder.port)
    end)
    record.add_housemate = attempt(function()
        return members.add_member(home_a, shopping, housemate.address, housemate.port)
    end)
    record.shopping_flagged = room_view(ctx, home_a, shopping)
    record.approve_coder = attempt(function()
        return members.approve(home_a, shopping, coder.address, coder.port)
    end)
    record.shopping_approved = room_view(ctx, home_a, shopping)
    -- the girlfriend's first machine leaves home (a confirmed leave): nothing
    -- removes her from kitchen or shopping, she is flagged there instead
    record.leaver = pair_text(girlfriend)
    record.leave = attempt(function()
        return members.confirm_leave(home_a, home_room, girlfriend.address, girlfriend.port)
    end)
    record.kitchen_after_leave = room_view(ctx, home_a, kitchen)
    record.shopping_after_leave = room_view(ctx, home_a, shopping)
    -- declining: kitchen declines her, which withholds her there
    record.decline = attempt(function()
        return members.decline(home_a, kitchen, girlfriend.address, girlfriend.port)
    end)
    record.kitchen_declined = room_view(ctx, home_a, kitchen)
    record.kitchen_withheld = ctx.probes.read_text(ctx.m.rooms.withheld_path(home_a, kitchen))
    -- a room whose declared parent this home does not hold: its newcomers
    -- cannot be checked, and are flagged for that
    local orphan = make_room(ctx, home_b, "attic", "attic-dust-lantern-moth", "group",
                             ctx.m.rooms.token_fingerprint("a parent token this home never held"),
                             joined_members({ "housemate" }))
    record.check_unheld = checked(ctx, home_b, orphan, coder)
    record.add_unheld = attempt(function()
        return members.add_member(home_b, orphan, coder.address, coder.port)
    end)
    record.orphan = room_view(ctx, home_b, orphan)
    return record
end
-- }}}

-- {{{ local function mailbox_table
-- Every mailbox of a home with the labels of the rooms in it, as
-- { tag, label, kind, port, rooms = list of room labels }.
local function mailbox_table(ctx, home)
    local rooms = ctx.m.rooms
    local list = {}
    for _, mailbox in ipairs(rooms.read_mailboxes(home)) do
        local labels = {}
        for _, tag in ipairs(rooms.list_rooms_by_mailbox(home, mailbox.tag)) do
            labels[#labels + 1] = rooms.read_entry(home, tag).label
        end
        list[#list + 1] = { tag = mailbox.tag, label = mailbox.label, kind = mailbox.kind,
                            port = mailbox.port, rooms = labels }
    end
    return list
end
-- }}}

-- {{{ local function mailbox_of
-- The mailbox a room is in, as { kind, port, tag }.
local function mailbox_of(ctx, home, tag)
    local mailbox = ctx.m.rooms.read_mailbox(home, ctx.m.rooms.read_entry(home, tag).mailbox)
    return { kind = mailbox.kind, port = mailbox.port, tag = mailbox.tag }
end
-- }}}

-- {{{ local function keys_tried_on
-- The rooms (by label) whose keys phase 2 would try for a frame arriving
-- on `port`: every room of every mailbox listening there.
local function keys_tried_on(ctx, home, port)
    local rooms = ctx.m.rooms
    local labels = {}
    for _, mailbox_tag in ipairs(rooms.mailboxes_by_port(home, port)) do
        for _, tag in ipairs(rooms.list_rooms_by_mailbox(home, mailbox_tag)) do
            labels[#labels + 1] = rooms.read_entry(home, tag).label
        end
    end
    return labels
end
-- }}}

-- {{{ local function unheld_parent_once
-- One home under one `mailboxes.unheld-parent` variant: a room "attic"
-- whose declared parent ("loft") this home does not hold yet, then the
-- parent arriving.  Gives where attic's mailbox was before and after.
local function unheld_parent_once(ctx, variant)
    local home = new_home(ctx, "mailboxes-unheld-" .. variant, { ["mailboxes.unheld-parent"] = variant })
    local loft_token = "loft-rafters-cedar-owl"
    local attic = make_room(ctx, home, "attic", "attic-dust-lantern-moth", "group",
                            ctx.m.rooms.token_fingerprint(loft_token), joined_members({ "housemate" }))
    local row = { variant = variant, before = mailbox_of(ctx, home, attic) }
    local loft = make_room(ctx, home, "loft", loft_token, "group", "", joined_members({ "housemate" }))
    row.after = mailbox_of(ctx, home, attic)
    row.loft = mailbox_of(ctx, home, loft)
    row.mailboxes = mailbox_table(ctx, home)
    return row
end
-- }}}

-- {{{ local function mailboxes_body
-- The mailboxes scene itself; `warnings` collects what 101 reports.
local function mailboxes_body(ctx, warnings)
    local rooms = ctx.m.rooms
    local home = new_home(ctx, "mailboxes", {})
    local tree = build_tree(ctx, home, "label_a")
    for _, name in ipairs({ "girlfriend", "coder" }) do
        make_room(ctx, home, name, "dm-" .. name .. "-mailbox-scene", "direct", "", joined_members({ name }))
    end
    local programming = make_room(ctx, home, "programming", "parser-lantern-quill-dune", "group", "",
                                  joined_members({ "girlfriend", "coder" }))
    local record = { home_dir = home.dir, rooms = {} }
    for _, tag in ipairs(rooms.list_rooms(home)) do
        local entry = rooms.read_entry(home, tag)
        local mailbox = rooms.read_mailbox(home, entry.mailbox)
        record.rooms[#record.rooms + 1] = { label = entry.label, kind = entry.kind, mailbox = entry.mailbox,
                                            mailbox_kind = mailbox.kind, port = mailbox.port }
    end
    table.sort(record.rooms, function(a, b) return a.port < b.port or (a.port == b.port and a.label < b.label) end)
    record.file = ctx.probes.read_text(rooms.mailboxes_path(home))
    record.table = mailbox_table(ctx, home)
    record.warnings_before = #warnings
    local home_port = mailbox_of(ctx, home, tree[1].tag).port
    record.tried = { { port = DIRECT_PORT, rooms = keys_tried_on(ctx, home, DIRECT_PORT) },
                     { port = home_port, rooms = keys_tried_on(ctx, home, home_port) } }
    -- a second top room put on programming's port on purpose: allowed, and
    -- reported every time the mailboxes are read
    local shared_port = mailbox_of(ctx, home, programming).port
    local before_make = #warnings
    make_room_with_port(ctx, home, "games", "dice-meadow-copper-kite", "group", "",
                        joined_members({ "coder" }), shared_port)
    -- making games reads the mailboxes file several times on the way (101
    -- and the bell listeners); count those reports, then take exactly one
    -- read on its own to show what a single read reports
    local before_read = #warnings
    rooms.read_mailboxes(home)
    local after_read = #warnings
    record.shared = { port = shared_port, warnings = {}, reports_while_making = before_read - before_make,
                      ports = rooms.shared_ports(home), tried = keys_tried_on(ctx, home, shared_port),
                      file = ctx.probes.read_text(rooms.mailboxes_path(home)) }
    for position = before_read + 1, after_read do
        record.shared.warnings[#record.shared.warnings + 1] = warnings[position]
    end
    record.unheld = {}
    for _, variant in ipairs(variants_of(ctx, "mailboxes.unheld-parent")) do
        record.unheld[#record.unheld + 1] = unheld_parent_once(ctx, variant)
    end
    return record
end
-- }}}

-- {{{ local function warning_to_stderr
-- Where 101's shared-port reports go outside this scene: a line on stderr,
-- as 101 itself does by default.
local function warning_to_stderr(text)
    io.stderr:write(text, "\n")
end
-- }}}

-- {{{ function sections.mailboxes
-- A top room and its children in one mailbox, every direct message in the
-- one direct mailbox, the mailboxes file as written, which rooms' keys a
-- frame on each port is tried against; two mailboxes on one port, allowed
-- and reported; and a room whose parent is not held, under each
-- `mailboxes.unheld-parent` variant, before and after the parent arrives.
-- 101's warning sink is pointed at this scene's list while it runs, then
-- back at stderr whether or not the scene built.
function sections.mailboxes(ctx)
    local warnings = {}
    ctx.m.rooms.set_warning_sink(function(text) warnings[#warnings + 1] = text end)
    local built, record = pcall(mailboxes_body, ctx, warnings)
    ctx.m.rooms.set_warning_sink(warning_to_stderr)
    if not built then
        -- the scene failed: pass its error on, the sink already restored
        error(record, 0)
    end
    -- (built: hand the record back)
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

-- {{{ function sections.ignoring
-- One address ignored at `mark`, one at `hide`, a short conversation
-- delivered the way a home server will (asking 103a whether to file each
-- message before 105 files it), then the room as shown, the member filter,
-- and one ignore covering every port of an address.  Both of the choices
-- this scene once varied are answered and fixed in the modules: a hidden
-- address's messages are not filed at all, and an ignore names a whole
-- address (every port), not one (address, port) pair.
function sections.ignoring(ctx)
    local rooms, members, ignore, log = ctx.m.rooms, ctx.m.members, ctx.m.ignore, ctx.m.log
    local home = new_home(ctx, "ignoring", {})
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
    local record = { delivered = #script, shown = {}, levels = {} }
    for _, line in ipairs(script) do
        local from, files = "me", true
        if line.who ~= "me" then
            -- someone else's message: the ignore list decides whether it is filed
            from = pair_text(line.who)
            files = ignore.files_message(home, tag, line.who.address, line.who.port)
        end
        -- (your own message: always filed)
        if files then
            -- filed in the log (none and mark are filed; mark is only drawn differently)
            log.append(home, tag, message(ctx, from, SCRIPT_T0 + line.offset,
                                           SCRIPT_T0 + line.offset, line.text))
        end
        -- (not filed: a hidden address's message is dropped before the log)
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
    -- the hidden address's machine on another port: one ignore covers it
    record.other_port = { who = hidden.address .. " " .. tostring(hidden.port + 1000),
                          level = ignore.how_ignored(home, tag, hidden.address, hidden.port + 1000),
                          files = ignore.files_message(home, tag, hidden.address, hidden.port + 1000) }
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
-- The log in its one record shape (tab-separated, the owner's answer): the
-- script filed (the late message placed in order), a repeat answered
-- `duplicate`, the same id with different text raised as an error, an edit
-- with its original kept, the raw file, and bytes per message over
-- BULK_COUNT messages.  Then the same messages on two homes in different
-- arrival orders, shown in the same order.
function sections.log(ctx)
    local log = ctx.m.log
    local record = { t0 = SCRIPT_T0 }
    local home = new_home(ctx, "log", {})
    local tag = make_room(ctx, home, "programming", "parser-lantern-quill-dune", "group", "",
                          joined_members({ "girlfriend", "coder" }))
    local ids = {}
    for position = 1, #SCRIPT do
        ids[position] = log.new_message_id()
    end
    record.answers = file_script(ctx, home, tag, ids, { 1, 2, 3, 4 })
    -- the coder's message delivered again (the first answer was lost)
    record.repeat_answer = attempt(function()
        return file_script(ctx, home, tag, ids, { 2 })[1]
    end)
    -- the same id arriving with different words
    record.conflict = attempt(function()
        return log.append(home, tag, { id = ids[2], from = from_of("coder"),
                                       written = SCRIPT_T0 + 60, arrived = SCRIPT_T0 + 300,
                                       text = "yes, give me twenty minutes" })
    end)
    -- the owner corrects the branch name
    record.edit = attempt(function()
        return log.correct(home, tag, { id = log.new_message_id(), from = "me",
                                        written = SCRIPT_T0 + 150, arrived = SCRIPT_T0 + 150,
                                        target = ids[3],
                                        text = "great, I pushed the branch parser" })
    end)
    record.in_file = {}
    for _, filed in ipairs(log.read(home, tag)) do
        record.in_file[#record.in_file + 1] = { kind = filed.kind, from = filed.from,
                                                written = filed.written - SCRIPT_T0,
                                                text = filed.text }
    end
    record.shown = order_of(ctx, home, tag)
    local path = ctx.m.rooms.log_path(home, tag)
    record.raw = ctx.probes.read_text(path)
    record.bytes = ctx.probes.bytes(path)
    -- bytes per message, measured over a room of plain one-line messages
    local bulk = make_room(ctx, home, "bulk", "bulk-measure-tsv", "group", "",
                           joined_members({ "coder" }))
    local started = ctx.probes.now()
    for number = 1, BULK_COUNT do
        log.append(home, bulk, message(ctx, from_of("coder"), SCRIPT_T0 + number,
                                        SCRIPT_T0 + number, "bulk message number " .. number))
    end
    record.bulk = { count = BULK_COUNT, seconds = ctx.probes.now() - started,
                    bytes = ctx.probes.bytes(ctx.m.rooms.log_path(home, bulk)) }
    -- two homes, the same room (same token, different local tags), the same
    -- four messages arriving in opposite orders (fresh ids, so these homes
    -- share nothing with the room above)
    local shared_ids = {}
    for position = 1, #SCRIPT do
        shared_ids[position] = log.new_message_id()
    end
    local homes = {}
    for _, side in ipairs({ { label = "log-two-a", order = { 1, 2, 3, 4 } },
                            { label = "log-two-b", order = { 4, 3, 2, 1 } } }) do
        local home = new_home(ctx, side.label, {})
        local tag = make_room(ctx, home, "programming", "parser-lantern-quill-dune", "group", "",
                              joined_members({ "girlfriend", "coder" }))
        file_script(ctx, home, tag, shared_ids, side.order)
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
    { key = "entries",   title = "Rooms are entries: a direct message and a group room, one reader" },
    { key = "tokens",    title = "Tokens: suggested (six words), typed, changed by hand" },
    { key = "tree",      title = "The tree: child rooms by fingerprint; flagged, not refused" },
    { key = "mailboxes", title = "Mailboxes: one per top room, one for direct messages (mailboxes.unheld-parent)" },
    { key = "members",   title = "Members and withheld: a room of six" },
    { key = "leaving",   title = "Leaving: forged, confirmed, and speaking again" },
    { key = "ignoring",  title = "Ignoring: mark and hide, every port, and the member filter" },
    { key = "people",    title = "people/: what we share with each person (people.link-collision)" },
    { key = "log",       title = "The message log: late, repeated, conflicting, edited" },
    { key = "tally",     title = "Every choice still open (scripts/tally-options)" },
}

-- Exposed for the tests, so they check against the same figures.
sections.SCRIPT_T0 = SCRIPT_T0
sections.PEOPLE = PEOPLE
sections.SIX = SIX

return sections
