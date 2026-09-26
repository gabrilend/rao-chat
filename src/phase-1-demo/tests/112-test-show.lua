-- 112-test-show.lua — checks the tally's showing half: the table and the walk.
--
-- Uses the good sample project.  The walk is driven by a pretend person: a
-- list of answers handed out one per question, and nil once they run out,
-- exactly as io.read gives nil when a pipe ends.

return function(DIR, harness)
    local check = harness.check
    local has = harness.contains_line
    local gather = require("100-gather-options")
    local show = require("101-show-options")
    local record = gather.gather(DIR .. "/src/phase-1-demo/tests/samples/good-src")
    local counts = gather.counts(record)

    -- the summary table
    local lines = show.summary_lines(record, counts)
    check("summary names both files", has(lines, "alpha/019-options.lua  (2 choices)")
          and has(lines, "beta/039-options.lua  (1 choices)"))
    check("summary has the column titles", has(lines, "choice") and has(lines, "waits on")
          and has(lines, "config key"))
    check("variants joined with slashes", has(lines, "lines / blocks"))
    check("non-switchable choice marked", has(lines, "(not switchable)"))
    check("state choice says what it waits for",
          has(lines, "waits for: issue 102: beta's listener order"))
    check("owner choice has no waits-for line", not has(lines, "waits for: open question 8"))
    check("leaning shown", has(lines, "leaning: lines, because it is half the size."))
    check("owner and state counted apart",
          has(lines, "waiting on the owner: 2    waiting on some other state: 1"))
    check("variant total shown", has(lines, "variants listed: 6"))
    local no_trailing = true
    for _, line in ipairs(lines) do
        if line:match(" $") then no_trailing = false end
    end
    check("no line ends in spaces", no_trailing)

    -- the empty tally
    local empty = gather.gather(DIR .. "/src/phase-1-demo/tests/samples/empty-src")
    local empty_lines = show.summary_lines(empty, gather.counts(empty))
    check("empty tally says so", has(empty_lines, "no undecided choices recorded yet."))
    check("empty tally still counts", has(empty_lines, "waiting on the owner: 0"))

    -- one page
    local page = show.page_lines(record.choices[1], 1, 3)
    check("page heading", has(page, "choice 1 of 3: alpha-shape   (alpha)"))
    check("page shows the question", has(page, "Which shape should alpha records take?"))
    check("page numbers variants", has(page, "[1] lines") and has(page, "[2] blocks"))
    check("page shows built-in, tests, findings", has(page, "built in:") and has(page, "tests:")
          and has(page, "- tests/a2.lua") and has(page, "- multi-line text is easy."))
    local widest = 0
    for _, line in ipairs(page) do widest = math.max(widest, #line) end
    check("page lines fit 78 columns", widest <= 78, widest)

    -- the walk, with a pretend person
    local function person(answers)
        local position = 0
        return function()
            position = position + 1
            return answers[position]
        end
    end
    local shown = {}
    local function write(line) shown[#shown + 1] = line end

    local pages = show.walk(record, person({ "", "" }), write, true)
    check("walk with two Enters shows all 3", pages == 3, pages)
    check("walk reaches the last choice", has(shown, "choice 3 of 3: beta-mode"))

    shown = {}
    pages = show.walk(record, person({ "q" }), write, true)
    check("q stops after the first page", pages == 1, pages)
    check("q says where it stopped", has(shown, "(stopped after choice 1 of 3)"))
    check("q does not show page 2", not has(shown, "choice 2 of 3"))

    shown = {}
    pages = show.walk(record, person({}), write, true)
    check("ended input stops the walk", pages == 1, pages)
    check("ended input is reported", has(shown, "(input ended after choice 1 of 3)"))

    shown = {}
    pages = show.walk(record, person({}), write, false)
    check("no-pause shows every page without asking", pages == 3 and not has(shown, "[Enter]"))

    shown = {}
    pages = show.walk(empty, person({}), write, true)
    check("walking an empty tally shows zero pages", pages == 0 and has(shown, "no undecided"))
end
