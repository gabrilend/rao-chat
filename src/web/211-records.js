// 211-records.js - the records inside a device frame, as the home's 186
// reads and writes them (issue 402).
//
// A record is one line: the kind, then that kind's fields in a fixed
// order, tab-separated, each escaped by the log's rule ("\\" "\t" "\n"
// "\r" become \\ \t \n \r, nothing else touched).  An unknown kind, a
// wrong number of fields, an unknown escape, or a field that breaks its
// rule is refused, never guessed at.  The table below is a copy of 186's
// (402 decision 2: the page cannot read the home's files), and 402's
// referee 3 holds the two equal.  Records are byte strings (206).
//
//   rao.records.encode({kind, ...fields}) -> one line (throws on a bad record)
//   rao.records.decode(line)              -> {record} or {why}

(function (rao) {
    "use strict";

    // kind -> its fields, in order (186's KINDS)
    var KINDS = {
        "ping": ["id"],
        "pong": ["id", "at"],
        "catch-up": ["rooms"],
        "file": ["path", "content"],
        "index": ["room", "entries"],
        "want": ["id", "room", "names"],
        "sent": ["id"],
        "caught-up": ["at"],
        "typed": ["id", "content"],
        "typed-ok": ["id"],
        "typed-refused": ["id", "why"]
    };
    if (rao.broken === "short-kind") { KINDS.want = ["id", "room"]; }

    // field -> its rule; a field not named here may hold any text (186's RULES)
    var RULES = {
        id: function (v) { return v.length >= 1 && v.length <= 64 && /^[A-Za-z0-9-]+$/.test(v); },
        at: function (v) { return /^[0-9]+$/.test(v) && v.length <= 15; },
        room: function (v) { return v.length === 32 && /^[0-9A-Fa-f]+$/.test(v); }
    };

    var ESCAPE = { "\\": "\\\\", "\t": "\\t", "\n": "\\n", "\r": "\\r" };
    var UNESCAPE = { "\\": "\\", "t": "\t", "n": "\n", "r": "\r" };

    // {{{ escape / unescape
    function escape(text) {
        return text.replace(/[\\\t\n\r]/g, function (c) { return ESCAPE[c]; });
    }
    // text -> the plain text, or null for an unknown escape or a lone "\"
    function unescape(text) {
        var bad = false;
        var plain = text.replace(/\\([\s\S]?)/g, function (whole, letter) {
            if (!Object.prototype.hasOwnProperty.call(UNESCAPE, letter)) { bad = true; return ""; }
            return UNESCAPE[letter];
        });
        return bad ? null : plain;
    }
    // }}}

    // {{{ encode
    function encode(record) {
        var fields = Object.prototype.hasOwnProperty.call(KINDS, record.kind) ? KINDS[record.kind] : null;
        if (!fields) { throw new Error("device record: unknown kind " + record.kind); }
        var parts = [record.kind];
        fields.forEach(function (name) {
            var value = record[name];
            if (value === undefined || value === null) { throw new Error("device record: " + record.kind + " needs " + name); }
            value = typeof value === "number" ? String(Math.floor(value)) : String(value);
            if (RULES[name] && !RULES[name](value)) {
                throw new Error("device record: " + name + " '" + value.slice(0, 40) + "' breaks its rule");
            }
            parts.push(escape(value));
        });
        return parts.join("\t");
    }
    // }}}

    // {{{ decode
    function decode(line) {
        if (typeof line !== "string") { return { why: "not a line" }; }
        var parts = line.split("\t");
        var kind = parts[0];
        var fields = Object.prototype.hasOwnProperty.call(KINDS, kind) ? KINDS[kind] : null;
        if (!fields) { return { why: "an unknown kind '" + kind.slice(0, 20) + "'" }; }
        if (parts.length !== fields.length + 1) {
            return { why: kind + " has " + (parts.length - 1) + " fields, not " + fields.length };
        }
        var record = { kind: kind };
        for (var i = 0; i < fields.length; i++) {
            var name = fields[i];
            var value = unescape(parts[i + 1]);
            if (value === null) { return { why: kind + "'s " + name + " has an unknown escape" }; }
            if (RULES[name] && !RULES[name](value)) { return { why: kind + "'s " + name + " breaks its rule" }; }
            record[name] = value;
        }
        return { record: record };
    }
    // }}}

    rao.records = {
        encode: encode,
        decode: decode,
        escape: escape,
        unescape: unescape,
        KINDS: KINDS,
        RULES: RULES
    };
})(globalThis.rao);
