// 221-writing.js - writing from the page (issue 406), as 305 has a
// device write: a typed file in 301's shape, sent as `typed`, kept until
// the home answers.
//
// A typed file is exactly what 183's typed_text makes:
//
//   room: <the room's 32-hex tag>
//   written: <whole seconds, the browser's clock>
//   (a blank line)
//   <the text, "\r\n" made "\n", trailing line breaks taken off>
//   (a blank line and the signature, when there is one)
//   (one final line break)
//
// and its name is 161's new_name, "<10-digit seconds>-<6-digit
// sequence>-<8 hex>", which the home takes as the file's name in the
// room's gatherer's typed/ (305 decision 3).  A signature must read back
// as itself by 214's rule (220), or nothing is made.
//
// The outbox holds what was typed until the home answers it, in this
// page's memory only (406 decision 2): `typed-ok` takes an item out,
// `typed-refused` keeps it with the home's reason until the person
// forgets it, and what is still unanswered when a connection ends is sent
// again, the same name and bytes, on the next (the home files it once:
// 305 decision 2, 301 decision 13).
//
//   rao.writing.typedText(tag, text, signature, written) -> {bytes} or {why}
//   rao.writing.newName(now)                  -> a typed file's name
//   rao.writing.checkSignature(signature)     -> "" or why not
//   new rao.writing.Outbox()
//     .add(tag, text, signature, now)         -> {item} or {why}
//     .send(link, files, settings)            -> Promise of {sent, refused, taken, lines} or {why}
//     .answer(record)                         -> true when the record answered an item
//     .forget(name)                           -> the refused item is dropped, at the person's word
//     .waiting() / .refused()                 -> items
//     .marker(files, tag)                     -> "sending…", "waiting", "sent" or ""
//   Text and signatures are byte strings (206); an item is {name, room,
//   text (as typed), content, state ("sending" or "refused"), why}.

(function (rao) {
    "use strict";
    var bytes = rao.bytes;

    // {{{ the typed file and its name (183's typed_text, 161's new_name)
    function typedText(tag, text, signature, written) {
        if (typeof tag !== "string" || !/^[0-9A-Fa-f]{32}$/.test(tag)) { return { why: "a room tag is 32 hex" }; }
        text = text.replace(/\r\n/g, "\n").replace(/\n+$/, "");
        if (text === "") { return { why: "there is nothing to send" }; }
        var whole = text;
        if (signature && signature !== "") {
            whole = text + "\n\n" + signature;
            var read = rao.signature.read(whole);
            if (read.signature !== signature || read.body !== text) {
                // the reason is words for the person: the signature as text
                return { why: "'" + bytes.toText(signature) + "' would not be read as a signature (one line, at most "
                    + rao.signature.MOST_CHARACTERS + " characters)" };
            }
        }
        return { bytes: "room: " + tag + "\nwritten: " + String(Math.floor(written)) + "\n\n" + whole + "\n" };
    }
    // a signature alone: "" when 214's rule reads it back after any text
    function checkSignature(signature) {
        if (signature === "") { return ""; }
        var made = typedText(new Array(33).join("0"), "x", signature, 0);
        return made.why || "";
    }
    function pad(number, width) {
        var text = String(number);
        while (text.length < width) { text = "0" + text; }
        return text;
    }
    var sequence = 0;
    function newName(now) {
        sequence += 1;
        return pad(Math.floor(now), 10) + "-" + pad(sequence % 1000000, 6) + "-" + bytes.hex(bytes.random(4));
    }
    // }}}

    // {{{ Outbox
    function Outbox() {
        this.items = [];
        this.sentIn = {};
    }
    Outbox.prototype.add = function (tag, text, signature, now) {
        var made = typedText(tag, text, signature, now);
        if (made.why) { return made; }
        var item = { name: newName(now), room: tag, text: text, content: made.bytes, state: "sending", why: "" };
        this.items.push(item);
        return { item: item };
    };
    Outbox.prototype.waiting = function () {
        return this.items.filter(function (item) { return item.state === "sending"; });
    };
    Outbox.prototype.refused = function () {
        return this.items.filter(function (item) { return item.state === "refused"; });
    };
    Outbox.prototype.answer = function (record) {
        if (record.kind !== "typed-ok" && record.kind !== "typed-refused") { return false; }
        for (var i = 0; i < this.items.length; i++) {
            var item = this.items[i];
            if (item.name !== record.id || item.state !== "sending") { continue; }
            if (record.kind === "typed-ok" || rao.broken === "drop-refused") {
                this.items.splice(i, 1);
                if (record.kind === "typed-ok") { this.sentIn[item.room] = true; }
            } else {
                item.state = "refused";
                item.why = record.why;
            }
            return true;
        }
        return false;
    };
    Outbox.prototype.forget = function (name) {
        this.items = this.items.filter(function (item) { return !(item.name === name && item.state === "refused"); });
    };
    // Sends every unanswered item, oldest first, each waiting for its
    // answer; a `file` the home pushes meanwhile is taken into the mirror
    // (checked as in a catch-up, 404), and a `pong` passes.
    Outbox.prototype.send = function (link, files, settings) {
        var outbox = this;
        var summary = { sent: 0, refused: 0, taken: 0, lines: [] };
        var mirrorSummary = { files: 0, messages: 0, changed: 0, dropped: 0, refused: [] };
        var queue = this.waiting().slice();
        function next() {
            var item = queue.shift();
            if (!item) { return Promise.resolve(summary); }
            return link.send({ kind: "typed", id: item.name, content: item.content }).then(function (sent) {
                if (!sent) { return { why: rao.link.silence(settings, link.where || "the home", "closed") }; }
                return answered(item);
            });
        }
        function answered(item) {
            return link.next(settings.wait).then(function (got) {
                if (got.lost) { return { why: rao.link.silence(settings, link.where || "the home", got.lost) }; }
                var record = got.record;
                if (record.kind === "file") {
                    if (rao.mirror.take(files, record, mirrorSummary)) { summary.taken += 1; }
                    return answered(item);
                }
                if (record.kind === "pong") { return answered(item); }
                if ((record.kind === "typed-ok" || record.kind === "typed-refused") && record.id === item.name) {
                    outbox.answer(record);
                    if (record.kind === "typed-ok") {
                        summary.sent += 1;
                        summary.lines.push("sent " + item.name);
                    } else {
                        summary.refused += 1;
                        summary.lines.push("kept " + item.name + ": " + record.why);
                    }
                    return next();
                }
                return { why: (link.where || "the home") + " sent a " + record.kind + " where it was not due" };
            });
        }
        return next().then(function (result) {
            mirrorSummary.refused.forEach(function (why) { summary.lines.push("refused " + why); });
            return result;
        });
    };
    // the words under the person's last message in a room
    Outbox.prototype.marker = function (files, tag) {
        if (this.items.some(function (item) { return item.room === tag && item.state === "sending"; })) { return "sending…"; }
        if (!this.sentIn[tag]) { return ""; }
        var room = rao.mirror.rooms(files)[tag];
        var facts = room ? rao.view.readFields(files.get(room.mailbox + "/inbox/" + tag + "/.room")).fields : { pile: [] };
        var owed = facts.pile.some(function (line) {
            var missing = /^\S+ [0-9]+ ([0-9]+)/.exec(line);
            return missing && Number(missing[1]) > 0;
        });
        return owed ? "waiting" : "sent";
    };
    // }}}

    rao.writing = {
        typedText: typedText,
        checkSignature: checkSignature,
        newName: newName,
        Outbox: Outbox
    };
})(globalThis.rao);
