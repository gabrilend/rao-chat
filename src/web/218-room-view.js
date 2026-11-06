// 218-room-view.js - what the page shows, worked out apart from drawing
// it (issue 405): the room trees and the open room, as plain lists that
// the page's own script (207) places with textContent, and that the
// stand-in prints as text for the referees and the demo.
//
// What is read from the files follows the reference viewer (183): an
// inbox file is "key: value" header lines, a blank line, then the body
// (signature removed, edits applied by the home: 301); `.room` has no
// body, and its `pile:` lines are a list.  The tree joins every mailbox's
// `.tree` (mailboxes in order of their tags, a tag's first listing wins),
// a room under its parent when the parent is held, otherwise at the top;
// rooms at one level by label, then tag.  treeText prints it exactly as
// 183's `tree` does, so 405's referee 1 can compare the two.
//
// How a room looks (planning section 7):
//   - the person's own messages (`from: me`) on one side, everyone else's
//     on the other (405 decision 2: own on the right);
//   - a name only where the speaker changes: the speaker is the `from:`
//     and the signature together, and the name shown is the signature
//     (405 decision 1);
//   - notices are neither speaker: the members still owed messages
//     (`.room`'s pile) and the flagged members, after the last message
//     (405 decision 3);
//   - every message has an anchor, "m-<id>";
//   - edited messages are marked; a deleted one has no body; one from an
//     address marked in the ignore list shows only that someone you
//     ignore spoke (405 decision 4).
//
//   rao.view.readFields(text)            -> {fields, body}
//   rao.view.tree(files, unread)         -> rows [{tag, depth, label, kind, parent, last, unread, flagged, waiting}]
//   rao.view.treeText(files)             -> 183's tree text
//   rao.view.room(files, tag)            -> {title, kind, members, lines} or null
//   rao.view.roomText(room)              -> the room as text lines
//   rao.view.messageCounts(files)        -> {tag: how many message files}
//   rao.view.when(seconds)               -> "YYYY-MM-DD HH:MM" in the browser's time zone

(function (rao) {
    "use strict";
    var mirror = rao.mirror;
    var bytes = rao.bytes;

    // {{{ readFields
    // an inbox file's bytes -> {fields: {name: text, pile: [...]}, body:
    // text or null}; header values and the body are turned into text
    function readFields(content) {
        var text = bytes.toText(content || "");
        var split = text.indexOf("\n\n");
        var head = split >= 0 ? text.slice(0, split) : text;
        var body = split >= 0 ? text.slice(split + 2) : null;
        var fields = { pile: [] };
        head.split("\n").forEach(function (line) {
            var found = /^([A-Za-z]+): (.*)$/.exec(line);
            if (!found) { return; }
            if (found[1] === "pile") { fields.pile.push(found[2]); } else { fields[found[1]] = found[2]; }
        });
        return { fields: fields, body: body };
    }
    // }}}

    // {{{ when
    function two(n) { return (n < 10 ? "0" : "") + n; }
    function when(seconds) {
        var number = Number(seconds);
        if (!/^[0-9]+$/.test(String(seconds))) { return "?"; }
        var date = new Date(number * 1000);
        return date.getFullYear() + "-" + two(date.getMonth() + 1) + "-" + two(date.getDate()) + " "
            + two(date.getHours()) + ":" + two(date.getMinutes());
    }
    // }}}

    // {{{ marks: a room's facts -> {flagged, waiting}
    function counts(facts) {
        var flagged = Number(facts.flagged || "0") || 0;
        var waiting = 0;
        (facts.pile || []).forEach(function (line) {
            var missing = /^\S+ [0-9]+ ([0-9]+)/.exec(line);
            if (missing) { waiting += Number(missing[1]); }
        });
        return { flagged: flagged, waiting: waiting };
    }
    function marksText(facts) {
        var c = counts(facts);
        var words = [];
        if (c.flagged > 0) { words.push("[" + facts.flagged + " flagged]"); }
        if (c.waiting > 0) { words.push("[" + c.waiting + " waiting]"); }
        return words.length > 0 ? " " + words.join(" ") : "";
    }
    // }}}

    // {{{ rooms: the joined trees
    // files -> {rooms: {tag: {tag, mailbox, parent, kind, label, facts}}, order: [tags]}
    function joined(files) {
        var trees = [];
        files.forEach(function (content, path) {
            var where = mirror.checkPath(path);
            if (where.kind === "tree") { trees.push({ mailbox: where.mailbox, content: content }); }
        });
        trees.sort(function (a, b) { return mirror.byBytes(a.mailbox, b.mailbox); });
        var found = {};
        var order = [];
        trees.forEach(function (tree) {
            bytes.toText(tree.content).split("\n").forEach(function (line) {
                var parts = /^([0-9A-Fa-f]+) (\S+) (\S+) (.*)$/.exec(line);
                if (!parts || found[parts[1]]) { return; }
                var facts = readFields(files.get(tree.mailbox + "/inbox/" + parts[1] + "/.room")).fields;
                found[parts[1]] = { tag: parts[1], mailbox: tree.mailbox, parent: parts[2] === "none" ? null : parts[2],
                    kind: parts[3], label: parts[4], facts: facts };
                order.push(parts[1]);
            });
        });
        return { rooms: found, order: order };
    }
    // }}}

    // {{{ messageCounts / lastLine
    function messageCounts(files) {
        var found = mirror.rooms(files);
        var out = {};
        Object.keys(found).forEach(function (tag) { out[tag] = found[tag].names.length; });
        return out;
    }
    // the last line said in a room, for its row in the tree
    function lastLine(files, room, names) {
        if (!names || names.length === 0) { return ""; }
        var read = readFields(files.get(room.mailbox + "/inbox/" + room.tag + "/" + names[names.length - 1]));
        if (read.fields.deleted === "yes") { return "(deleted)"; }
        if (read.fields.ignored === "mark") { return "(someone you ignore spoke)"; }
        var lines = (read.body || "").split("\n").filter(function (line) { return line.trim() !== ""; });
        return (lines.length > 0 ? lines[lines.length - 1] : "").slice(0, 80);
    }
    // }}}

    // {{{ tree
    // files, unread ({tag: n}, optional) -> the rows, in the order shown
    function tree(files, unread) {
        var all = joined(files);
        var held = mirror.rooms(files);
        var children = {};
        var tops = [];
        all.order.forEach(function (tag) {
            var room = all.rooms[tag];
            if (room.parent && all.rooms[room.parent]) {
                (children[room.parent] = children[room.parent] || []).push(tag);
            } else {
                tops.push(tag);
            }
        });
        function byLabel(a, b) {
            if (rao.broken === "tag-order") { return mirror.byBytes(a, b); }
            var la = all.rooms[a].label, lb = all.rooms[b].label;
            return la !== lb ? mirror.byBytes(la, lb) : mirror.byBytes(a, b);
        }
        var rows = [];
        function walk(list, depth) {
            list.sort(byLabel).forEach(function (tag) {
                var room = all.rooms[tag];
                var c = counts(room.facts);
                rows.push({ tag: tag, depth: depth, label: room.label, kind: room.kind, parent: room.parent,
                    facts: room.facts, flagged: c.flagged, waiting: c.waiting,
                    hasChildren: !!children[tag],
                    last: lastLine(files, room, held[tag] && held[tag].names),
                    unread: (unread && unread[tag]) || 0 });
                walk(children[tag] || [], depth + 1);
            });
        }
        walk(tops, 0);
        return rows;
    }
    // files -> the text 183's `tree` prints for the same folder
    function treeText(files) {
        return tree(files).map(function (row) {
            return new Array(row.depth + 1).join("  ") + row.label + (row.kind !== "group" ? " (" + row.kind + ")" : "")
                + "  " + row.tag.slice(0, 8) + marksText(row.facts);
        }).join("\n") + (files.size > 0 ? "\n" : "");
    }
    // }}}

    // {{{ room
    // files, a room's tag -> {tag, title, kind, members, lines}, or null
    // when the page holds no such room.  A line is a message
    // {type: "message", side, name (null where the speaker has not
    // changed), from, anchor, when, text, marks, mine} or a notice
    // {type: "notice", text}.
    function room(files, tag) {
        var all = joined(files);
        var found = all.rooms[tag];
        if (!found) { return null; }
        var names = (mirror.rooms(files)[tag] || { names: [] }).names;
        var lines = [];
        var speaker = null;
        names.forEach(function (name) {
            var read = readFields(files.get(found.mailbox + "/inbox/" + tag + "/" + name));
            var f = read.fields;
            var mine = f.from === "me";
            var key = (f.from || "?") + "\u0000" + (f.signature || "");
            var line = { type: "message", side: mine ? "mine" : "theirs", mine: mine, from: f.from || "?",
                anchor: "m-" + (f.id || name.replace(/^[0-9]+-/, "")), when: when(f.written), marks: [],
                name: null, text: read.body || "", signature: f.signature || "" };
            if (key !== speaker || rao.broken === "name-every-line") {
                line.name = f.signature || f.from || "?";
                speaker = key;
            }
            if (f.edited === "yes") { line.marks.push("edited"); }
            if (f.deleted === "yes") {
                line.text = "(deleted)";
                line.marks.push("deleted");
            } else if (f.ignored === "mark" && rao.broken !== "show-ignored") {
                line.text = "someone you ignore spoke";
                line.marks.push("ignored");
            }
            lines.push(line);
        });
        found.facts.pile.forEach(function (pile) {
            var parts = /^(\S+) ([0-9]+) ([0-9]+) ([0-9]+)$/.exec(pile);
            if (!parts) { return; }
            lines.push({ type: "notice", text: parts[3] + " message(s) could not be delivered yet to " + parts[1] + " "
                + parts[2] + " (waiting since " + when(parts[4]) + ")" });
        });
        var c = counts(found.facts);
        if (c.flagged > 0) {
            lines.push({ type: "notice", text: c.flagged + " flagged member(s) wait for your review: they are sent "
                + "nothing here until you approve them" });
        }
        return { tag: tag, title: found.facts.path || found.label, kind: found.kind, members: found.facts.members || "?",
            lines: lines };
    }
    // a room -> text lines: "<side> name <name> (<from>)", "<side> message
    // <anchor> <when>[ <marks>] | <text, line breaks as \n>", "notice | <text>"
    function roomText(shown) {
        var out = ["== " + shown.title + " (" + shown.kind + ", " + shown.members + " member(s))"];
        shown.lines.forEach(function (line) {
            if (line.type === "notice") { out.push("notice | " + line.text); return; }
            if (line.name !== null) { out.push(line.side + " name " + line.name + " (" + line.from + ")"); }
            out.push(line.side + " message " + line.anchor + " " + line.when
                + (line.marks.length > 0 ? " [" + line.marks.join(", ") + "]" : "") + " | " + line.text.replace(/\n/g, "\\n"));
        });
        return out.join("\n") + "\n";
    }
    // }}}

    rao.view = {
        readFields: readFields,
        when: when,
        tree: tree,
        treeText: treeText,
        room: room,
        roomText: roomText,
        messageCounts: messageCounts
    };
})(globalThis.rao);
