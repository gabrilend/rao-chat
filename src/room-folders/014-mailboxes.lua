-- 014-mailboxes.lua — the mailboxes file: which listening ports a home keeps.
--
-- A home server listens for other people's servers on one or more network
-- ports.  Rooms are grouped into mailboxes: each top-level group room and
-- every room under it is one mailbox, and all direct messages share one
-- more.  Each mailbox has its own port.  When a sealed message arrives on
-- a port, the server only has to try the keys of the rooms in the
-- mailboxes on that port, instead of every key it holds — and someone
-- watching the network learns only which port was used, not which room.
--
-- The list of mailboxes is one small text file, `rao-home/mailboxes`,
-- written in the same "name.field = value" shape rmail uses for contacts:
-- each mailbox is named by a random local tag (like a room's folder name,
-- never sent) and has a label for people reading the file, a kind, its
-- port, and — for a mailbox made for a child room whose parent was not
-- held here — which room it is waiting to merge (below).  Each room's own
-- entry names the mailbox it is in.
--
-- Waiting to merge (round 4).  A child room whose declared parent this
-- home does not hold starts a tree mailbox of its own (the owner's
-- answer).  The owner: "we should make it so that they can merge into the
-- parent rooms later on if possible."  So such a mailbox remembers the
-- room it was made for, in `awaits-parent-of`; once that room's parent is
-- held here, the mailbox's rooms can move into the parent's mailbox
-- (002-room-folders, config mailboxes.merge-when-parent-arrives).  After
-- the merge, or for any other mailbox, the field is empty.
--
-- This file only turns the list into text and back and checks every
-- field; it never touches the disk (002-room-folders does), so everything
-- here can be tested with strings alone.
--
-- Two mailboxes on one port are allowed (the owner: "we can accept from
-- the same port and route to the right location if necessary. It's not
-- recommended though."), so this file can find them (shared_ports_of) but
-- does not refuse them; 002 reports them every time the file is read.

local formats = require("004-rmail-formats")

-- The kinds of mailbox, what each holds, and how many one home may have
-- ("many" or "one").  A table so the kinds are written once; the demo and
-- the tests read it too.  (Round 3's `waiting` kind — one shared mailbox
-- for every child whose parent was not held — is retired in round 4: such
-- a child always starts a tree mailbox of its own.)
local MAILBOX_KINDS = {
    ["tree"]    = { how_many = "many", meaning = "a top-level group room and every room under it (or a "
                                                 .. "child room whose parent is not held here, until it merges)" },
    ["direct"]  = { how_many = "one",  meaning = "every direct message (a simple rmail inbox, just one)" },
}

-- The fields of one mailbox as written in the file, in order, and the
-- Lua name of each (only awaits-parent-of differs: "-" cannot be in a
-- plain Lua name).
local FIELDS = {
    { file = "label",            lua = "label" },
    { file = "kind",             lua = "kind" },
    { file = "port",             lua = "port" },
    { file = "awaits-parent-of", lua = "awaits_parent_of" },
}

-- The first line of every mailboxes file, so a person opening it knows
-- what it is.  Written by mailboxes_text, skipped as a comment on reading.
local HEADER = "// rao-chat mailboxes: rmail's contacts format, one entry per mailbox named by its local tag"

-- {{{ local function is_local_tag
-- The same shape as a room's local tag (006-entry): 32 lower-case hex.
local function is_local_tag(value)
    return type(value) == "string" and #value == 32 and value:match("^[0-9a-f]+$") ~= nil
end
-- }}}

-- {{{ local function check_port
-- A listening port: a whole number 1–65535.  There is no default port, so
-- a missing or malformed one is always an error, never replaced.
local function check_port(port, what)
    if type(port) ~= "number" or port % 1 ~= 0 or port < 1 or port > 65535 then
        error(what .. " must be a whole number 1-65535 (there is no default port), got " .. tostring(port), 3)
    end
end
-- }}}

-- {{{ local function check_mailbox_kind
local function check_mailbox_kind(kind)
    -- not a listed kind: a typo, or a mailbox from a newer program.
    if MAILBOX_KINDS[kind] == nil then
        error("a mailbox kind must be 'tree' or 'direct', got " .. tostring(kind), 3)
    end
end
-- }}}

-- {{{ local function check_mailbox
-- One mailbox: { tag = local tag, label = one line of text, kind, port,
-- awaits_parent_of = a room's local tag or "" }.  Any other field is a
-- misspelling and refused.
local function check_mailbox(mailbox)
    if type(mailbox) ~= "table" then
        error("a mailbox must be a table {tag, label, kind, port, awaits_parent_of}, got " .. type(mailbox), 3)
    end
    -- not a tag: the name the mailbox is written under would be wrong.
    if not is_local_tag(mailbox.tag) then
        error("mailbox.tag must be a local tag (32 lower-case hex), got " .. tostring(mailbox.tag), 3)
    end
    -- the label is written in quotes: any one line of text but empty.
    if type(mailbox.label) ~= "string" or mailbox.label == "" or mailbox.label:find("[\r\n]") then
        error("mailbox " .. mailbox.tag .. ": label must be one non-empty line of text", 3)
    end
    check_mailbox_kind(mailbox.kind)
    check_port(mailbox.port, "mailbox " .. mailbox.tag .. ": port")
    local awaits = mailbox.awaits_parent_of
    -- "" (not waiting to merge) or a room's local tag; nil or anything
    -- else is a mistake (no field has a default).
    if awaits ~= "" and not is_local_tag(awaits) then
        error("mailbox " .. mailbox.tag .. ": awaits_parent_of must be \"\" or a room's local tag, got "
            .. tostring(awaits), 3)
    end
    -- only a tree mailbox can wait to merge: a direct message has no parent.
    if awaits ~= "" and mailbox.kind ~= "tree" then
        error("mailbox " .. mailbox.tag .. ": only a tree mailbox can await a parent", 3)
    end
    for key in pairs(mailbox) do
        local known = key == "tag"
        for _, field in ipairs(FIELDS) do
            if key == field.lua then known = true end
        end
        -- not one of the five: refused rather than silently dropped.
        if not known then
            error("mailbox " .. mailbox.tag .. ": unknown field '" .. tostring(key) .. "'", 3)
        end
    end
end
-- }}}

-- {{{ local function check_mailbox_list
-- A plain list of mailboxes: tags never repeat, and the kinds that may
-- appear only once ("direct") appear at most once.
local function check_mailbox_list(list)
    if type(list) ~= "table" then
        error("mailboxes must be a list, got " .. type(list), 3)
    end
    local seen_tag, seen_kind = {}, {}
    for _, mailbox in ipairs(list) do
        check_mailbox(mailbox)
        -- a tag twice: two mailboxes would share one name in the file.
        if seen_tag[mailbox.tag] then
            error("mailbox " .. mailbox.tag .. " is listed twice", 3)
        end
        seen_tag[mailbox.tag] = true
        -- a second of a one-per-home kind: messages of that kind would
        -- have two places to go.
        if MAILBOX_KINDS[mailbox.kind].how_many == "one" and seen_kind[mailbox.kind] then
            error("a home has at most one '" .. mailbox.kind .. "' mailbox; found "
                .. seen_kind[mailbox.kind] .. " and " .. mailbox.tag, 3)
        end
        seen_kind[mailbox.kind] = mailbox.tag
    end
end
-- }}}

-- {{{ local function sorted_by_tag
-- A copy of the list sorted by tag, so the file is the same bytes
-- whatever order mailboxes were made in.
local function sorted_by_tag(list)
    local copy = {}
    for position, mailbox in ipairs(list) do copy[position] = mailbox end
    table.sort(copy, function(a, b) return a.tag < b.tag end)
    return copy
end
-- }}}

-- {{{ local function mailboxes_text
-- list of mailboxes → the text of the mailboxes file (sorted by tag).
-- An empty list gives just the header line: a home with no mailboxes yet.
local function mailboxes_text(list)
    check_mailbox_list(list)
    local lines = { HEADER }
    for _, mailbox in ipairs(sorted_by_tag(list)) do
        lines[#lines + 1] = mailbox.tag .. ".label = " .. formats.quote_value(mailbox.label)
        lines[#lines + 1] = mailbox.tag .. ".kind = " .. mailbox.kind
        lines[#lines + 1] = mailbox.tag .. ".port = " .. mailbox.port
        lines[#lines + 1] = mailbox.tag .. ".awaits-parent-of = " .. mailbox.awaits_parent_of
    end
    return table.concat(lines, "\n") .. "\n"
end
-- }}}

-- {{{ local function parse_mailboxes
-- text of a mailboxes file and a place name for errors → list of
-- { tag, label, kind, port, awaits_parent_of } sorted by tag.  Every field
-- must be there once, no other field may be, and the list rules above
-- hold.  A file from round 3 (no awaits-parent-of) is an error: there is
-- no conversion, no home from round 3 is kept.
local function parse_mailboxes(text, where)
    local contacts = formats.parse_contacts(text, where)
    local list = {}
    for name, fields in pairs(contacts) do
        local mailbox = { tag = name }
        for field in pairs(fields) do
            local known = false
            for _, wanted in ipairs(FIELDS) do
                if field == wanted.file then known = true end
            end
            -- a field this reader does not know: refused, not skipped.
            if not known then
                error(where .. ": mailbox " .. name .. " has an unknown field '" .. field .. "'", 0)
            end
        end
        for _, field in ipairs(FIELDS) do
            -- a field missing: the file is incomplete; nothing is assumed.
            if fields[field.file] == nil then
                error(where .. ": mailbox " .. name .. " has no '" .. field.file .. "'", 0)
            end
        end
        mailbox.label = fields.label
        mailbox.kind = fields.kind
        mailbox.awaits_parent_of = fields["awaits-parent-of"]
        -- the port as rmail writes one (digits, no leading zero), else
        -- an error: a guessed port would listen in the wrong place.
        mailbox.port = formats.parse_port(fields.port)
        if mailbox.port == nil then
            error(where .. ": mailbox " .. name .. ": port must be a whole number 1-65535, got '"
                .. fields.port .. "'", 0)
        end
        list[#list + 1] = mailbox
    end
    list = sorted_by_tag(list)
    local ok, problem = pcall(check_mailbox_list, list)
    -- the writer's rules broken in the file: say which file.
    if not ok then
        error(where .. ": " .. tostring(problem), 0)
    end
    return list
end
-- }}}

-- {{{ local function shared_ports_of
-- list of mailboxes → list of { port = integer, mailboxes = sorted list
-- of tags }, one per port named by two or more mailboxes, sorted by port.
-- Empty when every mailbox has a port of its own (the recommended shape).
local function shared_ports_of(list)
    local by_port = {}
    for _, mailbox in ipairs(list) do
        by_port[mailbox.port] = by_port[mailbox.port] or {}
        table.insert(by_port[mailbox.port], mailbox.tag)
    end
    local shared = {}
    for port, tags in pairs(by_port) do
        -- two or more on one port: reported.  One: the normal case.
        if #tags > 1 then
            table.sort(tags)
            shared[#shared + 1] = { port = port, mailboxes = tags }
        end
    end
    table.sort(shared, function(a, b) return a.port < b.port end)
    return shared
end
-- }}}

return {
    MAILBOX_KINDS = MAILBOX_KINDS,
    is_local_tag = is_local_tag,
    check_port = check_port,
    check_mailbox_kind = check_mailbox_kind,
    check_mailbox = check_mailbox,
    mailboxes_text = mailboxes_text,
    parse_mailboxes = parse_mailboxes,
    shared_ports_of = shared_ports_of,
    HEADER = HEADER,
}
