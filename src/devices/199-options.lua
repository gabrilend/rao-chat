-- 199-options.lua — the undecided choices of the device port (issue
-- 302), written down for the options tally (scripts/tally-options, issue
-- 106) and the demos.  Plain data: nothing here runs.  Numbered at the
-- end of the devices module's block, as 019, 039 and 059 are for theirs,
-- so the module's later files keep their reading order.
--
-- Every setting has no default (an unset one stops the program); the
-- first variant is what a demo home starts with.

local BUILT = "src/devices/187-device-server.lua"
local TESTS = "src/devices/tests/188-test-device-port.lua"

return {
    {
        id = "devices-port",
        question = "Which port do the home's phones and browsers connect to?",
        waits_on = "owner",
        detail = "issue 302 (decision 1; rubric question 24); 'no default port numbers' (the owner)",
        config_key = "devices.port",
        variants = {
            {
                name = "46302",
                summary = "A port of the home's own, never a mailbox's; the owner forwards it to reach the "
                    .. "home from outside. The value is the owner's to pick; this one is the demo's.",
                built_in = BUILT .. " (main: the listener)",
                tests = TESTS .. " (referees 1 to 6)",
                findings = "A device port equal to a mailbox's port stops the server (referee 6d).",
            },
        },
        leaning = "Whatever port the owner forwards; there is no default to lean on.",
    },
    {
        id = "devices-address",
        question = "Which address does the device port listen on?",
        waits_on = "owner",
        detail = "issue 302",
        config_key = "devices.address",
        variants = {
            {
                name = "any",
                summary = "Every address of the machine: reachable from the home network and, once "
                    .. "forwarded, from outside.",
                built_in = BUILT .. " (main: the listener)",
                tests = TESTS .. " (127.0.0.2 instead)",
                findings = "Homes sharing a machine each need their own address, as gatherer.address.",
            },
        },
        leaning = "any, for one home per machine.",
    },
    {
        id = "devices-frame-deadline",
        question = "How long may a device take to deliver one whole frame, in seconds?",
        waits_on = "owner",
        detail = "issue 302 (as gatherer.frame-deadline, issue 211)",
        config_key = "devices.frame-deadline",
        variants = {
            {
                name = "10",
                summary = "10 seconds for a whole frame, counted from when the server starts waiting "
                    .. "for it; a quiet connection is closed after it (306 adds an idle limit).",
                built_in = BUILT .. " (serve_connection)",
                tests = TESTS .. " (referees 3 and 5, with 2 s)",
                findings = "A connection stuck mid-frame holds up no other device (referee 5).",
            },
        },
        leaning = "10, as the gatherer's.",
    },
}
