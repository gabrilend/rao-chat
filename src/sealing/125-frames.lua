-- 125-frames.lua — reading a frame from a connection and writing one to it
-- (issue 201, step 3).
--
-- The connection is anything with LuaSocket's two calls, so a real socket
-- and a test's stand-in are used the same way:
--
--   conn:receive(n)        → n bytes; or nil, err, partial bytes
--   conn:send(data, i, j)  → index of the last byte sent; or nil, err,
--                            index of the last byte sent
--
-- Reading checks the length before reading anything it announces (R3): a
-- length under 28 or over the cap (124's CAP, the one cap every reader in
-- the project uses) is refused having read only its 4 bytes, so nobody can
-- make this server hold a body it never asked for.  Then exactly that many
-- bytes are read, gathering partial reads.
--
-- Writing sends every byte once (R10).  send gives back the index of the
-- last byte it sent, not a count: the next send starts one past that
-- index.  (rmail's loop added the index as if it were a count, which skips
-- bytes after two partial writes in a row.)
--
-- How long to wait is the connection's business (its timeout, and the
-- gatherer's deadline in 211); here, a "timeout" with no bytes gained
-- PATIENCE times in a row gives up.

local seal = require("124-seal")

local PATIENCE = 3

-- {{{ local function receive_exactly
-- conn, n → n bytes, or nil and why.  Partial reads are gathered; a
-- "timeout" that gained nothing counts against PATIENCE.
local function receive_exactly(conn, n)
    local pieces, have, idle = {}, 0, 0
    while have < n do
        local data, err, partial = conn:receive(n - have)
        local got = data or partial or ""
        if #got > 0 then
            pieces[#pieces + 1] = got
            have = have + #got
            idle = 0
        end
        -- Path: no error — keep reading if short.  A timeout — retry while
        -- patient.  Anything else (closed) — give up.
        if not data then
            if err ~= "timeout" then return nil, err or "closed" end
            if #got == 0 then
                idle = idle + 1
                if idle >= PATIENCE then return nil, "timeout" end
            end
        end
    end
    return table.concat(pieces)
end
-- }}}

-- {{{ local function read_frame
-- conn → the frame without its length (nonce, sealed body, check value),
-- ready for 124's open; or nil and why.  `cap` may be given smaller than
-- the project's CAP (a test does); it may never be larger.  A frame
-- refused for its length alone also gives back the length it announced,
-- as a third value (issue 203 logs it).
local function read_frame(conn, cap)
    cap = cap or seal.CAP
    if cap > seal.CAP then error("frames: a reader's cap may not exceed " .. seal.CAP, 2) end
    local head, err = receive_exactly(conn, seal.LENGTH_BYTES)
    if not head then return nil, err end
    local length = seal.read_uint32_be(head)
    -- Path: the length checked before a byte more is read.
    if length < seal.MIN_LENGTH then
        return nil, "a length of " .. length .. " is under " .. seal.MIN_LENGTH, length
    end
    if length > cap then
        return nil, "a length of " .. length .. " is over the cap of " .. cap, length
    end
    return receive_exactly(conn, length)
end
-- }}}

-- {{{ local function write_frame
-- conn, frame (the whole frame, length first) → true, or nil and why.
local function write_frame(conn, frame)
    local next_byte, idle = 1, 0
    while next_byte <= #frame do
        local last, err, partial_last = conn:send(frame, next_byte, #frame)
        local sent_to = last or partial_last or (next_byte - 1)
        local progress = sent_to >= next_byte
        -- Path: progress — continue one past the last byte sent.
        if progress then
            next_byte = sent_to + 1
            idle = 0
        end
        if not last then
            if err ~= "timeout" then return nil, err or "closed" end
            if not progress then
                idle = idle + 1
                if idle >= PATIENCE then return nil, "timeout" end
            end
        end
    end
    return true
end
-- }}}

return {
    read_frame = read_frame,
    write_frame = write_frame,
    receive_exactly = receive_exactly,
    PATIENCE = PATIENCE,
}
