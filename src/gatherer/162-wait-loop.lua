-- 162-wait-loop.lua — the gatherer's one wait: cooperative threads over
-- real sockets and the real clock (issue 211, open question 2).
--
-- The stages (listener, each held connection, filer, sender, sync cycle)
-- are coroutines under this one loop, in one process per mailbox.  A
-- thread waits with `block(check, until_time, socket, "read"|"write")`;
-- the loop runs every thread that can run, then waits in select() on the
-- sockets the others wait for, at most until the nearest until_time and
-- never longer than TICK (so a thread waiting on a folder, which select
-- cannot watch, is looked at again soon).  It is the same shape as 143's
-- simulated world, with the clock and the relay made real, so 202's
-- stage and 133's receiving side run here unchanged.
--
-- Connections are LuaSocket's, non-blocking, behind the interface 125's
-- frame reader and 132's sender use: receive(n), send(data, i, j),
-- settimeout(seconds), close().  A connection may also carry `deadline`
-- (absolute seconds): past it every receive answers "timeout" (211's one
-- deadline for the whole frame, decision of 2026-11-05 for question 8).
--
-- A code error in a thread ends that thread, is handed to `on_error`, and
-- the loop goes on (R5).

local socket = require("socket")

local M = {}

M.TICK = 0.05

-- {{{ function M.now
function M.now() return socket.gettime() end
-- }}}

local Loop = {}
Loop.__index = Loop

-- {{{ function M.new
-- on_error(name, message) → a loop.
function M.new(on_error)
    return setmetatable({ threads = {}, on_error = on_error or function() end, running = true }, Loop)
end
-- }}}

-- {{{ function Loop:spawn
function Loop:spawn(name, fn)
    local thread = { name = name, co = coroutine.create(fn) }
    self.threads[#self.threads + 1] = thread
    return thread
end
-- }}}

-- {{{ function M.block
-- Inside a thread: wait until check() is true, the socket is ready, or
-- until_time passes.
function M.block(check, until_time, sock, direction)
    coroutine.yield({ check = check, until_time = until_time or math.huge, sock = sock, direction = direction })
end
-- }}}

-- {{{ function M.sleep
function M.sleep(seconds)
    M.block(nil, M.now() + seconds)
end
-- }}}

-- {{{ local function runnable
local function runnable(thread, now, ready)
    local wait = thread.wait
    if wait == nil then return true end
    if now >= wait.until_time then return true end
    if wait.sock and ready[wait.sock] then return true end
    return wait.check ~= nil and wait.check()
end
-- }}}

-- {{{ function Loop:step
-- Runs every runnable thread once, then waits for sockets or time.
function Loop:step()
    local now = M.now()
    local ready = self.ready or {}
    self.ready = {}
    local list = {}
    for i, thread in ipairs(self.threads) do list[i] = thread end
    local kept = {}
    for _, thread in ipairs(list) do
        if not thread.done and runnable(thread, now, ready) then
            local ok, wait = coroutine.resume(thread.co)
            if not ok then
                thread.done = true
                self.on_error(thread.name, tostring(wait))
            elseif coroutine.status(thread.co) == "dead" then
                thread.done = true
            else
                thread.wait = wait
            end
        end
    end
    for _, thread in ipairs(self.threads) do
        if not thread.done then kept[#kept + 1] = thread end
    end
    self.threads = kept
    -- wait: for the sockets threads wait on, or the nearest time, or TICK
    local reads, writes = {}, {}
    local soonest = M.now() + M.TICK
    for _, thread in ipairs(self.threads) do
        local wait = thread.wait
        if wait then
            if wait.until_time < soonest then soonest = wait.until_time end
            if wait.sock then
                if wait.direction == "write" then writes[#writes + 1] = wait.sock else reads[#reads + 1] = wait.sock end
            end
        end
    end
    local timeout = math.max(0, soonest - M.now())
    if #reads + #writes > 0 then
        local r, w = socket.select(reads, writes, timeout)
        for _, s in ipairs(r or {}) do self.ready[s] = true end
        for _, s in ipairs(w or {}) do self.ready[s] = true end
    elseif timeout > 0 then
        socket.sleep(timeout)
    end
end
-- }}}

-- {{{ function Loop:run
-- Steps until stop() is true (checked each step).
function Loop:run(stop)
    while not (stop and stop()) do self:step() end
end
-- }}}

------------------------------------------------------------------------------
-- Connections
------------------------------------------------------------------------------

local Conn = {}
Conn.__index = Conn

-- {{{ function M.wrap
-- A LuaSocket client socket (connected or accepted) → a connection.
function M.wrap(sock)
    sock:settimeout(0)
    return setmetatable({ sock = sock, buffer = "", timeout = 2.5, closed = false }, Conn)
end
-- }}}

-- {{{ function Conn:settimeout
function Conn:settimeout(seconds) self.timeout = seconds end
-- }}}

-- {{{ function Conn:receive
-- n bytes; or nil, "timeout" | "closed", and what came.
function Conn:receive(n)
    local give_up = M.now() + (self.timeout or 2.5)
    if self.deadline and self.deadline < give_up then give_up = self.deadline end
    while true do
        if self.closed then
            local partial = self.buffer
            self.buffer = ""
            return nil, "closed", partial
        end
        if #self.buffer < n then
            local data, err, partial = self.sock:receive(n - #self.buffer)
            self.buffer = self.buffer .. (data or partial or "")
            if err == "closed" then
                self.closed = true
                if #self.buffer >= n then
                    local out = self.buffer:sub(1, n)
                    self.buffer = self.buffer:sub(n + 1)
                    return out
                end
                local rest = self.buffer
                self.buffer = ""
                return nil, "closed", rest
            end
        end
        if #self.buffer >= n then
            local out = self.buffer:sub(1, n)
            self.buffer = self.buffer:sub(n + 1)
            return out
        end
        if M.now() >= give_up then
            local partial = self.buffer
            self.buffer = ""
            return nil, "timeout", partial
        end
        M.block(nil, give_up, self.sock, "read")
    end
end
-- }}}

-- {{{ function Conn:send
-- LuaSocket's send: the index of the last byte sent; or nil, why, and the
-- last index sent.
function Conn:send(data, i, j)
    i, j = i or 1, j or #data
    if self.closed then return nil, "closed", i - 1 end
    local give_up = M.now() + (self.timeout or 2.5)
    local at = i
    while at <= j do
        local last, err, partial = self.sock:send(data, at, j)
        local reached = last or partial or (at - 1)
        at = reached + 1
        if err == "closed" then self.closed = true; return nil, "closed", reached end
        if at <= j then
            if M.now() >= give_up then return nil, "timeout", reached end
            M.block(nil, give_up, self.sock, "write")
        end
    end
    return j
end
-- }}}

-- {{{ function Conn:close
function Conn:close()
    if not self.closed then self.closed = true end
    if self.sock then self.sock:close() end
end
-- }}}

-- {{{ function M.connect
-- from_host ("any" for no binding), pair {address, port}, seconds → a
-- connection, or nil and why.  The socket is bound to from_host first, so
-- a home sends from its own address (210's rubric).
function M.connect(from_host, pair, seconds)
    local sock = (pair.address:find(":", 1, true) and socket.tcp6 or socket.tcp4)()
    if not sock then return nil, "no socket" end
    if from_host and from_host ~= "any" then
        local ok, err = sock:bind(from_host, 0)
        if not ok then sock:close(); return nil, "cannot send from " .. from_host .. ": " .. tostring(err) end
    end
    sock:settimeout(0)
    local ok, err = sock:connect(pair.address, pair.port)
    if not ok and err ~= "timeout" and err ~= "Operation already in progress" then
        sock:close()
        return nil, tostring(err)
    end
    if not ok then
        local give_up = M.now() + (seconds or 2.5)
        while M.now() < give_up do
            M.block(nil, give_up, sock, "write")
            if sock:getpeername() then break end
            -- writable without a peer: the connection failed
            local _, again = sock:connect(pair.address, pair.port)
            if again == "already connected" then break end
            if again ~= "timeout" and again ~= "Operation already in progress" then
                sock:close()
                return nil, tostring(again)
            end
        end
        if not sock:getpeername() then sock:close(); return nil, "timeout" end
    end
    return M.wrap(sock)
end
-- }}}

return M
