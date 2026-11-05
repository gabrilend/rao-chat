-- 133-receive.lua — reading frames on a mailbox's connection, filing
-- what they carry and answering with the ids (issue 202, step 5).
--
-- The key that opens a frame says which room it is for (201, 201a).  The
-- record is filed (105) unless the arriving address is ignored at `hide`
-- (103a), and the answer names its id with the log's word, `filed` or
-- `duplicate` (R2: a repeat is acknowledged, not refused).  Filing comes
-- first, then the answer (R3).
--
-- Who sent it.  A connection shows the peer's address and a source port
-- the system picked, not the port it listens on, so the arriving pair is
-- found by address among the room's members (decision of 2026-11-05;
-- the owner may overturn it):
--   exactly one member at that address   `from` is that member's pair, and
--                                        103's heard_from records it
--   none, or several                     `from` is the address and the
--                                        source port, and nobody is
--                                        recorded heard: heard_from would
--                                        add the source port as a member.
--                                        205's hello says where to call
--                                        back.
--   no member, and exactly one pair      `from` is that pair; a message
--   in the room's `left` file (208)      written after the leave re-adds
--                                        it (heard_from) and clears its
--                                        line: speaking again is
--                                        rejoining.  An older one is filed
--                                        and re-adds nobody.
--
-- What is answered for each frame (decisions of 2026-11-05):
--   a did-you (204)          a did-you-answer, from this room's claims
--                            (141): yes or no; nothing is filed
--   a hello (205) or a       handed to seams.on_claim (147's on_claim,
--   leave (208)              in the sender stage: the call-backs), and
--                            answered with an ack naming its claim id,
--                            `filed` or `duplicate`; nothing is filed in
--                            the log, and no hello is ever sent back.
--                            Without on_claim it is refused (no word, so
--                            the sender tries again later)
--   filed / duplicate        the log's own word
--   hidden (ignored, hide)   `filed`: the record is dropped, and the sender
--                            is not told it is ignored, so it stops
--                            resending
--   refused (an edit before its message, 105's refuse; an id repeated
--   with different contents; a record that does not decode)
--                            no word for that id, so the sender keeps it
--                            missing and tries again later (question 7);
--                            the problem goes to seams.on_problem
--   a frame no key opens     no answer: the connection is closed (203
--                            logs it, through seams.on_unopened, once,
--                            after the whole keyring was tried)
--   a length under the       no answer: the connection is closed having
--   least or over the cap    read only the 4 length bytes (203 logs it,
--                            through seams.on_refused_length)
--
-- Seams (211 gives the real ones; the tests give stand-ins):
--   seams.home            the home (002's open_home)
--   seams.ring()          the keyring of this connection's port (127)
--   seams.peer            {host, port} as the connection shows them
--   seams.now()           whole seconds, for `arrived`
--   seams.workers         how many slices the trial is split into (127)
--   seams.on_problem(tag, words)       optional
--   seams.on_unopened(peer, length)    optional (139 gives it: 203)
--   seams.on_refused_length(peer, length)  optional (139 gives it: 203)
--   seams.on_opened(tag, peer)         optional (134 uses it: question 1)
--   seams.on_claim(tag, record, peer)  optional (145's receive, 205) →
--                                      the ack's word
-- Receiving never sends anything but these answers, and never waits on
-- the sender stage (R6): 211 runs this in its own stage.

local seal = require("124-seal")
local frames = require("125-frames")
local records = require("126-inner-records")
local keyring = require("127-keyring")
local recipients = require("041-recipients")
local ignore = require("042-ignore-list")
local message_log = require("081-message-log")
local send = require("132-send")
local call_back = require("142-call-back")
local leaving = require("147-leaving")

local M = {}

-- The records that carry a claim to call back (205's hello; 208's leave
-- joins it), handed to seams.on_claim.
M.CLAIMS = { hello = true, leave = true }

-- {{{ function M.sender_of
-- home, tag, host, source_port → from_address, from_port, is_member, and
-- the `left` line when the pair is one that left (208).
function M.sender_of(home, tag, host, source_port)
    local found = nil
    for _, member in ipairs(recipients.members(home, tag)) do
        if member.address == host then
            if found then return host, source_port, false end
            found = member
        end
    end
    if found then return found.address, found.port, true end
    local gone = leaving.at_address(home, tag, host)
    if gone then return gone.address, gone.port, false, gone end
    return host, source_port, false
end
-- }}}

local FILERS = {
    message = function(home, tag, r) return message_log.append(home, tag, r) end,
    correction = function(home, tag, r) return message_log.correct(home, tag, r) end,
    deletion = function(home, tag, r) return message_log.delete(home, tag, r) end,
}

-- {{{ function M.file_record
-- home, tag, opened (the record's line), peer, now → the answer's word
-- for it ("filed" / "duplicate"), and its id; or nil and why.
function M.file_record(home, tag, opened, peer, now)
    local ok, record = pcall(records.decode, opened)
    if not ok then return nil, nil, "does not decode: " .. tostring(record) end
    local filer = FILERS[record.kind]
    if not filer then return nil, nil, "a " .. record.kind .. " is not filed in a log" end
    local address, port, is_member, gone = M.sender_of(home, tag, peer.host, peer.port)
    if not ignore.files_message(home, tag, address, port) then return "filed", record.id end
    local filed, word = pcall(filer, home, tag, {
        id = record.id, from = address .. " " .. port, written = record.written, arrived = now,
        kind = record.kind, target = record.target, text = record.text,
    })
    if not filed then return nil, record.id, tostring(word) end
    if is_member then recipients.heard_from(home, tag, address, port, record.written) end
    if gone and record.written > gone.written then
        -- 208: the leaver speaks again, after its leave: back in
        recipients.heard_from(home, tag, address, port, record.written)
        if recipients.is_member(home, tag, address, port) then leaving.clear(home, tag, gone) end
    end
    return word, record.id
end
-- }}}

-- {{{ local function keys_for
local function keys_for(ring, tag)
    for _, entry in ipairs(ring.entries) do
        if entry.room == tag then return entry end
    end
end
-- }}}

-- {{{ function M.serve
-- conn, seams → why it ended ("closed", "timeout", "unopened", "length", ...).
-- Reads frames until the connection ends, answering each.
function M.serve(conn, seams)
    local home = seams.home
    while true do
        local after, why, refused_length = frames.read_frame(conn)
        if not after then
            if refused_length and seams.on_refused_length then seams.on_refused_length(seams.peer, refused_length) end
            if conn.close then conn:close() end
            return refused_length and "length" or why
        end
        local ring = seams.ring()
        local tag, opened = keyring.open_frame(ring, after, seams.workers or 1)
        if not tag then
            -- the length it announced: what was read after those 4 bytes
            if seams.on_unopened then seams.on_unopened(seams.peer, #after) end
            if conn.close then conn:close() end
            return "unopened"
        end
        if seams.on_opened then seams.on_opened(tag, seams.peer) end
        local answer
        local asked_ok, asked = pcall(records.decode, opened)
        if asked_ok and asked.kind == "did-you" then
            -- 204: answered from this room's claims (141); changes nothing
            answer = call_back.answer_frame(home, tag, asked)
        elseif asked_ok and M.CLAIMS[asked.kind] then
            -- 205: a claim to call back; the stage's, not the log's
            local answers = {}
            local ok, word = false, "nothing here hears claims"
            if seams.on_claim then ok, word = pcall(seams.on_claim, tag, asked, seams.peer) end
            if ok and send.WORDS[word] then
                answers[1] = { id = asked.claim, word = word }
            elseif seams.on_problem then
                seams.on_problem(tag, "a " .. asked.kind .. ": " .. tostring(word))
            end
            answer = records.encode({ kind = "ack", answers = send.write_answers(answers) })
        else
            local word, id, problem = M.file_record(home, tag, opened, seams.peer, seams.now())
            local answers = {}
            if word then
                answers[1] = { id = id, word = word }
            elseif seams.on_problem then
                seams.on_problem(tag, (id and ("record " .. id .. ": ") or "") .. tostring(problem))
            end
            answer = records.encode({ kind = "ack", answers = send.write_answers(answers) })
        end
        local ok, failed = frames.write_frame(conn, seal.seal(keys_for(ring, tag), answer))
        if not ok then
            if conn.close then conn:close() end
            return "answering: " .. tostring(failed)
        end
    end
end
-- }}}

return M
