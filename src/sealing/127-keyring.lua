-- 127-keyring.lua — the keys a mailbox's port tries on a frame, and the
-- trial opening across them (issue 201, steps 4 and 5).
--
-- Nothing in front of a frame says which room it is for (R11): the key
-- that opens it is the only statement.  So a frame arriving on a port is
-- tried against the keys of the rooms in the mailboxes on that port, and
-- only those (phase 1's mailboxes: a port's keys only).  A key "opens" a
-- frame when GCM's check passes and the opened body begins with that
-- key's tying value (201a), so trying can stop at the first key that
-- opens it: no frame can open under two rooms' keys and be filed by
-- whichever was tried first (R7).
--
-- A keyring is built once per mailbox from its rooms' tokens, kept, and
-- dropped when the change bell rings `token`, `created`, `mailbox` or
-- `removed-room` for that home, so the next frame rebuilds it (rmail
-- re-reads its contacts file and re-hashes every token for every frame).
--
-- Workers.  The trial is split into slices, one per worker (the owner:
-- "if we need more speed, we make the decoding multithreaded").  This file
-- does the split and the combining; the gatherer (211) runs each slice in
-- its own worker.  Here the slices run one after another in this process,
-- and the answer is the same either way: the slices cover every key once,
-- sizes differing by at most one, and an opening in any slice is the
-- answer whatever the other slices found.

local room_key = require("123-room-key")
local seal = require("124-seal")
local bell = require("005-change-bell")

-- {{{ local function from_tokens
-- list of {room = <any label or tag>, token = <string>} → a keyring:
-- {entries = {{room, key, tie}, ...}} in the list's order.
local function from_tokens(list)
    local ring = { entries = {} }
    for _, item in ipairs(list) do
        local pair = room_key.key_pair(item.token)
        ring.entries[#ring.entries + 1] = { room = item.room, key = pair.key, tie = pair.tie }
    end
    return ring
end
-- }}}

-- {{{ local function slices
-- n keys, w workers → list of {first, last} (1-based, inclusive), covering
-- 1..n once each, in order, sizes differing by at most one.  A worker with
-- nothing to do gets no slice.
local function slices(n, w)
    if type(w) ~= "number" or w < 1 or w ~= math.floor(w) then
        error("keyring: workers must be a whole number ≥ 1, got " .. tostring(w), 2)
    end
    local list = {}
    local base, extra = math.floor(n / w), n % w
    local first = 1
    for index = 1, math.min(w, n) do
        local size = base + (index <= extra and 1 or 0)
        list[#list + 1] = { first = first, last = first + size - 1 }
        first = first + size
    end
    return list
end
-- }}}

-- {{{ local function try_slice
-- One worker's share: the keys first..last in order, stopping at the
-- first that opens the frame.  → {room, record, tried} or {tried}.
local function try_slice(ring, after_length, first, last, opener)
    local tried = 0
    for index = first, last do
        local entry = ring.entries[index]
        tried = tried + 1
        local record = opener(entry, after_length)
        if record ~= nil then return { room = entry.room, record = record, tried = tried } end
    end
    return { tried = tried }
end
-- }}}

-- {{{ local function combine
-- The slices' answers → room, record, tried; or nil, nil, tried when none
-- opened it.  Two slices opening one frame cannot happen with tying values
-- and distinct tokens; if it does, it is an error, never a choice.
local function combine(answers)
    local found, tried = nil, 0
    for _, answer in ipairs(answers) do
        tried = tried + answer.tried
        if answer.record ~= nil then
            if found then error("keyring: one frame opened under two rooms' keys", 0) end
            found = answer
        end
    end
    if found then return found.room, found.record, tried end
    return nil, nil, tried
end
-- }}}

-- {{{ local function open_frame
-- ring, after_length (the frame without its length), workers (default 1)
-- → room, record, keys tried; or nil, nil, keys tried.  `opener` replaces
-- 124's open for a test's broken version.
local function open_frame(ring, after_length, workers, opener)
    opener = opener or seal.open
    local answers = {}
    for _, slice in ipairs(slices(#ring.entries, workers or 1)) do
        answers[#answers + 1] = try_slice(ring, after_length, slice.first, slice.last, opener)
    end
    return combine(answers)
end
-- }}}

-- Built keyrings, per home folder and mailbox tag: cache[dir][mailbox].
local cache = {}

-- The rings that change what a mailbox's keys are.
local DROP_ON = { token = true, created = true, mailbox = true, ["removed-room"] = true }

bell.on_change(function(home, _, what)
    -- Path: a ring that changes some mailbox's keys — drop the home's
    -- keyrings (rebuilt on next use).  Any other ring — nothing to do.
    if DROP_ON[what] then cache[home.dir] = nil end
end)

-- {{{ local function for_mailbox
-- home (002's open_home), mailbox_tag → that mailbox's keyring, built from
-- its rooms' tokens (each entry's room is the room's local tag).
local function for_mailbox(rooms, home, mailbox_tag)
    local per_home = cache[home.dir]
    if not per_home then
        per_home = {}
        cache[home.dir] = per_home
    end
    local ring = per_home[mailbox_tag]
    if not ring then
        local list = {}
        for _, tag in ipairs(rooms.list_rooms_by_mailbox(home, mailbox_tag)) do
            list[#list + 1] = { room = tag, token = rooms.read_entry(home, tag).token }
        end
        ring = from_tokens(list)
        per_home[mailbox_tag] = ring
    end
    return ring
end
-- }}}

-- {{{ local function for_port
-- home, port → one keyring of every mailbox on that port (usually one; a
-- shared port is allowed and reported by phase 1).
local function for_port(rooms, home, port)
    local ring = { entries = {} }
    for _, mailbox_tag in ipairs(rooms.mailboxes_by_port(home, port)) do
        for _, entry in ipairs(for_mailbox(rooms, home, mailbox_tag).entries) do
            ring.entries[#ring.entries + 1] = entry
        end
    end
    return ring
end
-- }}}

return {
    from_tokens = from_tokens,
    slices = slices,
    try_slice = try_slice,
    combine = combine,
    open_frame = open_frame,
    for_mailbox = for_mailbox,
    for_port = for_port,
}
