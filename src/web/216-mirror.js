// 216-mirror.js - the page's mirror of the home's viewer folder, and
// catching it up (issue 404), as 192 and 190's catch-up do it for a
// device on disk.
//
// The mirror is a Map in memory (404 decision 1), from a path of 301's
// layout to the file's bytes:
//
//   <mailbox>/state                         the gatherer's state
//   <mailbox>/inbox/.tree                   the mailbox's rooms
//   <mailbox>/inbox/<room>/.room            a room's facts
//   <mailbox>/inbox/<room>/<written>-<id>   one file per message
//
// A mailbox and a room are 32 hex; a message name is whole seconds, a
// dash, and an id of letters, digits, "-" and "_", at most 128 (304
// decision 4).  checkPath is the one test every path from the network
// passes before it is used (192's check_path, written again here: 404
// decision 2).
//
// A room's position is the name of the last message file held (names sort
// as the room's order, 301); its digest is SHA-256 (hex) over the lines
// "<name> <SHA-256 hex of the file>\n" of the files held, sorted by name.
// The catch-up sends one line per room holding a message, "<room> <last
// name> <digest>"; the home answers with `file` records (taken after the
// path check), `index` records where the digests disagree, and
// `caught-up`.  Then, for each room indexed, files the index does not list
// are dropped and those held otherwise are asked for with `want`, until
// its `sent`; and rooms no `.tree` of their mailbox names leave the mirror.
//
//   rao.mirror.checkPath(path)        -> {kind, mailbox, room, name} or {why}
//   rao.mirror.rooms(files)           -> {room: {mailbox, names}}
//   rao.mirror.positionsText(files)   -> Promise of the catch-up's text
//   rao.mirror.take(files, record, summary) -> true when taken
//   rao.mirror.catchUp(link, files, settings) -> Promise of a summary
//     {files, messages, changed, dropped, refused: [why...]} or {why}

(function (rao) {
    "use strict";
    var bytes = rao.bytes;

    var MOST_ID = 128;

    // {{{ the path rule (192)
    function isTag(text) { return typeof text === "string" && /^[0-9A-Fa-f]{32}$/.test(text); }
    function isMessageName(name) {
        if (typeof name !== "string") { return false; }
        var found = /^([0-9]+)-([A-Za-z0-9_-]+)$/.exec(name);
        return found !== null && found[1].length <= 15 && found[2].length <= MOST_ID;
    }
    function checkPath(path) {
        if (typeof path !== "string" || path.length > 300) { return { why: "not a path" }; }
        var parts = path.split("/");
        var shown = "'" + path.slice(0, 80) + "'";
        if (!isTag(parts[0])) { return { why: shown + " does not start with a 32-hex mailbox" }; }
        if (parts.length === 2 && parts[1] === "state") { return { kind: "state", mailbox: parts[0] }; }
        if (parts[1] !== "inbox") { return { why: shown + " is not in 301's layout" }; }
        if (parts.length === 3 && parts[2] === ".tree") { return { kind: "tree", mailbox: parts[0] }; }
        if (parts.length !== 4 || !isTag(parts[2])) { return { why: shown + " names no 32-hex room" }; }
        var where = { mailbox: parts[0], room: parts[2], name: parts[3] };
        if (parts[3] === ".room") { where.kind = "room"; return where; }
        if (isMessageName(parts[3])) { where.kind = "message"; return where; }
        return { why: shown + " is not a message file's name" };
    }
    // }}}

    // {{{ rooms
    // files (the Map) -> {room: {mailbox, names (sorted message names)}};
    // a room whose folder holds only .room has names []
    function rooms(files) {
        var found = {};
        files.forEach(function (content, path) {
            var where = checkPath(path);
            if (where.kind !== "room" && where.kind !== "message") { return; }
            var room = found[where.room] || (found[where.room] = { mailbox: where.mailbox, names: [] });
            if (where.kind === "message") { room.names.push(where.name); }
        });
        Object.keys(found).forEach(function (tag) { found[tag].names.sort(byBytes); });
        return found;
    }
    // names compare as the home's Lua compares them: byte by byte
    function byBytes(a, b) { return a < b ? -1 : a > b ? 1 : 0; }
    // }}}

    // {{{ hash / entries / digest / positionsText
    function hash(content) { return bytes.sha256(content).then(bytes.hex); }
    // files, a room's mailbox, tag and names, position (none: all) ->
    // Promise of [{name, hash}] up to and including the position
    function entries(files, mailbox, tag, names, position) {
        var held = names.filter(function (name) { return position === undefined || name <= position; });
        return Promise.all(held.map(function (name) {
            var content = files.get(mailbox + "/inbox/" + tag + "/" + name);
            return hash(content).then(function (h) { return { name: name, hash: h }; });
        }));
    }
    function digest(list) {
        return hash(list.map(function (entry) { return entry.name + " " + entry.hash + "\n"; }).join(""));
    }
    function positionsText(files) {
        if (rao.broken === "from-start") { return Promise.resolve(""); }
        var found = rooms(files);
        var tags = Object.keys(found).filter(function (tag) { return found[tag].names.length > 0; }).sort(byBytes);
        return Promise.all(tags.map(function (tag) {
            var room = found[tag];
            return entries(files, room.mailbox, tag, room.names).then(digest).then(function (d) {
                return tag + " " + room.names[room.names.length - 1] + " " + d;
            });
        })).then(function (lines) { return lines.join("\n"); });
    }
    // }}}

    // {{{ take
    // files, a `file` record, a summary -> true when the file passed the
    // path check and is in the mirror (refusals counted, with why)
    function take(files, record, summary) {
        summary.files += 1;
        var where = checkPath(record.path);
        if (where.why && rao.broken !== "no-path-check") {
            summary.refused.push(where.why);
            return false;
        }
        if (where.kind === "message") { summary.messages += 1; }
        if (files.get(record.path) !== record.content) {
            files.set(record.path, record.content);
            summary.changed += 1;
        }
        return true;
    }
    // }}}

    // {{{ prune
    // files -> how many rooms were removed: those no .tree of their
    // mailbox names (a room the home has left); a mailbox with no .tree
    // is left alone (304 decision 6)
    function prune(files) {
        var named = {};
        var trees = {};
        files.forEach(function (content, path) {
            var where = checkPath(path);
            if (where.kind !== "tree") { return; }
            trees[where.mailbox] = true;
            content.split("\n").forEach(function (line) {
                var tag = /^([0-9A-Fa-f]+) /.exec(line);
                if (tag) { named[where.mailbox + "/" + tag[1]] = true; }
            });
        });
        var gone = {};
        Array.from(files.keys()).forEach(function (path) {
            var where = checkPath(path);
            if ((where.kind === "room" || where.kind === "message") && trees[where.mailbox]
                && !named[where.mailbox + "/" + where.room]) {
                files.delete(path);
                gone[where.mailbox + "/" + where.room] = true;
            }
        });
        return Object.keys(gone).length;
    }
    // }}}

    // {{{ catchUp
    function catchUp(link, files, settings) {
        var summary = { files: 0, messages: 0, changed: 0, dropped: 0, refused: [] };
        var indexes = {};
        var positions = {};
        // reads records until stop(record); files taken, indexes kept
        function answerUntil(stop) {
            return link.next(settings.wait).then(function (got) {
                if (got.lost) { return { why: rao.link.silence(settings, link.where || "the home", got.lost) }; }
                var record = got.record;
                if (record.kind === "file") { take(files, record, summary); return answerUntil(stop); }
                if (record.kind === "index") {
                    var index = indexes[record.room] || (indexes[record.room] = {});
                    record.entries.split("\n").forEach(function (line) {
                        var entry = /^(\S+) ([0-9a-f]+)$/.exec(line);
                        if (entry && isMessageName(entry[1]) && entry[2].length === 64) { index[entry[1]] = entry[2]; }
                        else if (line !== "") { summary.refused.push("an index line '" + line.slice(0, 60) + "'"); }
                    });
                    return answerUntil(stop);
                }
                if (stop(record)) { return { done: true }; }
                return { why: "the home sent a " + record.kind + " where it was not due" };
            });
        }
        // one room the home indexed: drop, then want
        function settleRoom(tag) {
            var held = positions[tag];
            var room = rooms(files)[tag];
            if (!held || !room) {
                summary.refused.push("an index for room " + tag + ", which this page did not list");
                return Promise.resolve({ done: true });
            }
            var index = indexes[tag];
            return entries(files, room.mailbox, tag, room.names, held.last).then(function (list) {
                var mine = {};
                list.forEach(function (entry) {
                    mine[entry.name] = entry.hash;
                    if (!Object.prototype.hasOwnProperty.call(index, entry.name)) {
                        files.delete(room.mailbox + "/inbox/" + tag + "/" + entry.name);
                        summary.dropped += 1;
                    }
                });
                var wanted = Object.keys(index).filter(function (name) { return mine[name] !== index[name]; }).sort(byBytes);
                if (wanted.length === 0) { return { done: true }; }
                var id = bytes.hex(bytes.random(8));
                return link.send({ kind: "want", id: id, room: tag, names: wanted.join("\n") }).then(function (sent) {
                    if (!sent) { return { why: rao.link.silence(settings, link.where || "the home", "closed") }; }
                    return answerUntil(function (record) { return record.kind === "sent" && record.id === id; });
                });
            });
        }
        return positionsText(files).then(function (text) {
            text.split("\n").forEach(function (line) {
                var parts = line.split(" ");
                if (parts.length === 3) { positions[parts[0]] = { last: parts[1], digest: parts[2] }; }
            });
            return link.send({ kind: "catch-up", rooms: text });
        }).then(function (sent) {
            if (!sent) { return { why: rao.link.silence(settings, link.where || "the home", "closed") }; }
            return answerUntil(function (record) { return record.kind === "caught-up"; });
        }).then(function (result) {
            if (result.why) { return result; }
            var tags = Object.keys(indexes).sort(byBytes);
            if (rao.broken === "no-digest") { tags = []; }
            var chain = Promise.resolve({ done: true });
            tags.forEach(function (tag) {
                chain = chain.then(function (before) { return before.why ? before : settleRoom(tag); });
            });
            return chain;
        }).then(function (result) {
            if (result.why) { return result; }
            summary.dropped += prune(files);
            return summary;
        });
    }
    // }}}

    rao.mirror = {
        isTag: isTag,
        isMessageName: isMessageName,
        checkPath: checkPath,
        rooms: rooms,
        byBytes: byBytes,
        hash: hash,
        entries: entries,
        digest: digest,
        positionsText: positionsText,
        take: take,
        prune: prune,
        catchUp: catchUp
    };
})(globalThis.rao);
