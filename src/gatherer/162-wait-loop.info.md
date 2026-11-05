# 162-wait-loop.lua

The gatherer's one wait (issue 211, question 2): its stages are
coroutines under one loop over real sockets and the real clock, the same
shape as 143's simulated world.  A thread waits with `block(check,
until_time, socket, direction)`; the loop runs every thread that can run,
then waits in `select()` on the sockets the rest wait for, at most
`TICK` (0.05 s).  `wrap` gives a LuaSocket socket the receive / send /
settimeout / close interface 125 and 132 use, with an optional
`deadline` for the whole frame.  `connect` binds to the home's own
address first.  An error in one thread ends that thread and goes to
`on_error`; the loop goes on.
