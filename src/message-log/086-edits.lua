-- 086-edits.lua — correcting and deleting messages, and how a room looks
-- once those are taken into account.
--
-- Anything may be edited, at any time (planning document section 3,
-- "Edits"; owner: "Everything is edit-able by design with no record, so
-- nothing can be trusted unless you make local copies yourself").  The log
-- is that local copy, so it is never rewritten: an edit is itself a new
-- record added to the end of the file — a "correction" carrying the new
-- text, or a "deletion" — each with its own id, naming the id of the
-- message it changes (its target).  The original stays in the file,
-- readable with cat; the room view shows the latest text.
--
-- Anyone may edit any message (owner, 2026-09-25, answering who may edit
-- or delete: "let's make the local copies part of the UI we build. That's
-- the 'the room shows which address the change came from' part").  The
-- writer of a message cannot be known, only the address its copy came
-- from, so a rule tying edits to an address would prove nothing.  Round 2
-- also built "only from the message's own address" behind the key
-- log.who-may-edit; round 3 fixed the answer in place and removed both.
-- Every correction or deletion in the file is applied when reading, and
-- each view carries `changed_from` so a client can show the original, the
-- change, and the address the change came from.

local edits = {}

-- {{{ local function find_target
-- Gives the "message" record with id `edit.target` from `records`, or
-- raises an error naming why the edit cannot be filed.
local function find_target(records, edit)
    local found
    local deleted = false
    for _, record in ipairs(records) do
        -- Path: the original message — remember it.  A deletion of it —
        -- note that it is gone.  Anything else — not relevant.
        if record.id == edit.target and record.kind == "message" then
            found = record
        elseif record.kind == "deletion" and record.target == edit.target then
            deleted = true
        end
    end
    -- Path: no such message here — refuse (phase 1 files edits only for
    -- messages already in the log, and an edit of an edit is not a thing;
    -- see issue 105 open question 6 for edits that arrive before their
    -- message).
    if not found then
        error("message-log: no message '" .. edit.target .. "' in this room to "
            .. (edit.kind == "deletion" and "delete" or "correct"), 0)
    end
    -- Path: already deleted — refuse; there is nothing left to change.
    if deleted then
        error("message-log: message '" .. edit.target .. "' was already deleted", 0)
    end
    return found
end
-- }}}

-- {{{ function edits.check
-- records: list, the room's records in file order.
-- edit:    record of kind "correction" or "deletion".
-- Gives nothing; raises an error when the edit cannot be filed (its
-- message is not in the room, is itself an edit, or is already deleted).
function edits.check(records, edit)
    find_target(records, edit)
end
-- }}}

-- {{{ local function later
-- The order in which edits of one message take effect: by written time,
-- then by id, so every reader agrees on which edit is the latest.
local function later(a, b)
    -- Path: different times — the later time wins.  Same time — larger id.
    if a.written ~= b.written then
        return a.written > b.written
    end
    return a.id > b.id
end
-- }}}

-- {{{ local function keep_latest
-- Puts `record` into `held[record.target]` when it is later than what is
-- there.
local function keep_latest(held, record)
    local current = held[record.target]
    -- Path: nothing held yet, or this one is later — it becomes the latest.
    -- Otherwise the held one stays.
    if not current or later(record, current) then
        held[record.target] = record
    end
end
-- }}}

-- {{{ function edits.apply
-- records: list, the room's records in file order.
-- Gives:   list of message views (only kind "message"), in file order, each
--          { id, from, written, arrived  (as in the record),
--            text         = string, the latest correction's text ("" when
--                           deleted),
--            edited       = bool, at least one correction applies,
--            deleted      = bool, a deletion applies,
--            changed_from = string, the `from` of the deletion if deleted,
--                           else of the latest correction, else "" }.
-- A deleted message stays in the list, empty and marked, so links to it
-- still land somewhere; whether a person sees a marked gap or nothing is
-- their own setting in the client (owner, 2026-09-25: "This is a UI
-- concern, the user should be able to choose. It doesn't matter to the
-- backend, really.").  Its original text stays in the file.
-- A correction or deletion whose message is not in the file is left out
-- quietly: it may belong to a message that has not arrived yet (phase 2).
function edits.apply(records)
    local latest_fix = {}
    local latest_deletion = {}
    for _, record in ipairs(records) do
        -- Path: a correction — keep it if latest for its target.  A
        -- deletion — likewise.  A message — nothing to collect.
        if record.kind == "correction" then
            keep_latest(latest_fix, record)
        elseif record.kind == "deletion" then
            keep_latest(latest_deletion, record)
        end
    end
    local views = {}
    for _, record in ipairs(records) do
        -- Path: a message — build its view.  Edits — already folded in.
        if record.kind == "message" then
            local fix = latest_fix[record.id]
            local deletion = latest_deletion[record.id]
            local text, changed_from = record.text, ""
            -- Path: deleted — no text, the deleter's address.  Corrected —
            -- the latest text and its address.  Neither — as written.
            if deletion then
                text, changed_from = "", deletion.from
            elseif fix then
                text, changed_from = fix.text, fix.from
            end
            views[#views + 1] = {
                id = record.id, from = record.from,
                written = record.written, arrived = record.arrived,
                text = text, edited = fix ~= nil, deleted = deletion ~= nil,
                changed_from = changed_from,
            }
        end
    end
    return views
end
-- }}}

return edits
