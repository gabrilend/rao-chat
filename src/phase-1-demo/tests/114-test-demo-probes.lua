-- 114-test-demo-probes.lua — checks the demo's measuring tools on a folder made here.
--
-- Builds a tiny folder of known files and links in the test scratch space
-- and checks each probe reads it exactly: sizes, link targets, listings,
-- the clock only moving forward, and the clearing tool refusing any folder
-- outside the demo's own space.

return function(DIR, harness)
    local check, check_error = harness.check, harness.check_error
    local probes = require("102-demo-probes")
    local scratch = DIR .. "/tmp/shared-memory/phase-1-demo-tests"
    probes.must_run("mkdir -p '" .. scratch .. "'")
    local place = probes.fresh_dir(scratch, scratch .. "/probes")

    probes.write_text(place .. "/a.txt", "12345")
    probes.write_text(place .. "/b.txt", "")
    probes.must_run("mkdir '" .. place .. "/sub' && ln -s ../a.txt '" .. place .. "/sub/to-a'"
                    .. " && ln -s ../missing '" .. place .. "/sub/to-nowhere'")

    check("bytes of a 5-byte file", probes.bytes(place .. "/a.txt") == 5)
    check("bytes of an empty file", probes.bytes(place .. "/b.txt") == 0)
    check("read_text gives the content back", probes.read_text(place .. "/a.txt") == "12345")
    check_error("read_text of a missing file is an error",
                function() probes.read_text(place .. "/none") end, "cannot read")

    local sizes = probes.files_with_sizes(place)
    check("files_with_sizes lists two files, sorted", #sizes == 2 and sizes[1] == "a.txt  5 bytes"
          and sizes[2] == "b.txt  0 bytes", table.concat(sizes, " / "))

    local links = probes.links_with_targets(place)
    check("links_with_targets shows each stored target", #links == 2
          and links[1] == "sub/to-a -> ../a.txt" and links[2] == "sub/to-nowhere -> ../missing",
          table.concat(links, " / "))
    check("a link to a real file resolves", probes.link_resolves(place .. "/sub/to-a"))
    check("a link to nothing does not resolve", not probes.link_resolves(place .. "/sub/to-nowhere"))

    local entries = probes.entries(place)
    check("entries lists names directly inside", #entries == 3 and entries[3] == "sub",
          table.concat(entries, " / "))

    check("lines drops only the final empty piece", #probes.lines("a\nb\n") == 2
          and #probes.lines("a\n\nb") == 3 and #probes.lines("") == 0)

    local output, clean = probes.run("exit 3")
    check("run reports a failing command as not clean", clean == false)
    output, clean = probes.run("echo hello")
    check("run gives output of a clean command", clean and output == "hello\n", output)
    check_error("must_run stops on a failing command",
                function() probes.must_run("false") end, "command failed")

    local first = probes.now()
    local second = probes.now()
    check("the clock does not go backwards", second >= first)

    check_error("fresh_dir refuses a folder outside the scratch space",
                function() probes.fresh_dir(scratch, DIR .. "/src") end, "refusing to clear")
    check_error("fresh_dir refuses the scratch root itself",
                function() probes.fresh_dir(scratch, scratch) end, "refusing to clear")
    check_error("fresh_dir refuses a look-alike sibling folder",
                function() probes.fresh_dir(scratch, scratch .. "-other/x") end, "refusing to clear")
    probes.fresh_dir(scratch, place)
    check("fresh_dir empties the folder", #probes.entries(place) == 0)
    check_error("a path with a quote is refused",
                function() probes.entries(place .. "/it's") end, "quote")
end
