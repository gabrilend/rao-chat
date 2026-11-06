// 225-panels.js - what the People and Settings panels and the top bar
// show (issue 408; planning sections 8 and 9), worked out apart from
// drawing it, as 218 does for the rooms.
//
// Remembered homes.  The page keeps one home's lines per label the person
// gives it (408 decision 3), in the browser's storage, and never a token
// (403 decision 2):
//
//   "rao-chat homes"           the labels, one a line, sorted
//   "rao-chat home <label>"    that home's lines, without the token
//   "rao-chat signature <label>" its signature (406), when one is kept
//   "rao-chat last home"       the label last connected
//
// `storage` is anything with getItem, setItem and removeItem (the
// browser's localStorage; the stand-in's own).  A browser that refuses
// storage (some do for pages opened from files) makes each call say why.
//
//   rao.panels.homes.list(storage)                 -> {labels} or {why}
//   rao.panels.homes.remember(storage, label, lines, signature) -> "" or why
//   rao.panels.homes.read(storage, label)          -> {lines, signature} or {why}
//   rao.panels.homes.forget(storage, label)        -> "" or why
//   rao.panels.homes.last(storage)                 -> the last label, or ""
//   rao.panels.people(files)       -> [{tag, label, last}]: every mailbox's direct rooms
//   rao.panels.stateWords(state)   -> the top bar's words for a session's state (223)
//   rao.panels.homeName(label, where) -> the top bar's name

(function (rao) {
    "use strict";
    var LIST = "rao-chat homes";
    var LAST = "rao-chat last home";
    function homeKey(label) { return rao.broken === "one-home" ? "rao-chat home" : "rao-chat home " + label; }
    function signatureKey(label) { return rao.broken === "one-home" ? "rao-chat signature" : "rao-chat signature " + label; }

    // {{{ homes
    function checkLabel(label) {
        if (typeof label !== "string" || label.trim() === "") { return "give this home a name first, to remember it by"; }
        if (/[\r\n]/.test(label)) { return "a home's name is one line"; }
        return "";
    }
    // runs fn(storage) -> its result, or {why} when the browser refuses
    function guarded(fn) {
        try { return fn(); } catch (problem) {
            return { why: "this browser keeps nothing for this page (" + problem.message + "); paste the lines each time" };
        }
    }
    function labelsOf(storage) {
        var text = storage.getItem(LIST);
        return text ? text.split("\n").filter(function (label) { return label !== ""; }) : [];
    }
    function list(storage) {
        return guarded(function () { return { labels: labelsOf(storage) }; });
    }
    function remember(storage, label, lines, signature) {
        var bad = checkLabel(label);
        if (bad) { return bad; }
        var done = guarded(function () {
            var labels = labelsOf(storage);
            if (labels.indexOf(label) < 0) { labels.push(label); }
            labels.sort(rao.mirror.byBytes);
            storage.setItem(LIST, labels.join("\n"));
            storage.setItem(homeKey(label), rao.link.rememberText(lines));
            if (signature) { storage.setItem(signatureKey(label), signature); } else { storage.removeItem(signatureKey(label)); }
            storage.setItem(LAST, label);
            return {};
        });
        return done.why || "";
    }
    function read(storage, label) {
        return guarded(function () {
            var lines = storage.getItem(homeKey(label));
            if (lines === null) { return { why: "this page remembers no home called '" + label + "'" }; }
            return { lines: lines, signature: storage.getItem(signatureKey(label)) || "" };
        });
    }
    function forget(storage, label) {
        var done = guarded(function () {
            var labels = labelsOf(storage).filter(function (other) { return other !== label; });
            if (labels.length > 0) { storage.setItem(LIST, labels.join("\n")); } else { storage.removeItem(LIST); }
            storage.removeItem(homeKey(label));
            storage.removeItem(signatureKey(label));
            if (storage.getItem(LAST) === label) { storage.removeItem(LAST); }
            return {};
        });
        return done.why || "";
    }
    function last(storage) {
        var found = guarded(function () { return { label: storage.getItem(LAST) || "" }; });
        return found.label || "";
    }
    // }}}

    // {{{ people, the top bar
    // the direct-message rooms of every mailbox (408 decision 1), in the
    // tree's order, each with the last line said in it
    function people(files) {
        return rao.view.tree(files).filter(function (row) { return row.kind === "direct"; }).map(function (row) {
            return { tag: row.tag, label: row.label, last: row.last };
        });
    }
    var WORDS = { connecting: "connecting…", "catching-up": "catching up", live: "live", waiting: "not connected",
        stopped: "not connected" };
    function stateWords(state) { return WORDS[state] || "not connected"; }
    function homeName(label, where) {
        if (label && label.trim() !== "") { return label; }
        return where || "rao-chat";
    }
    // }}}

    rao.panels = {
        homes: { list: list, remember: remember, read: read, forget: forget, last: last, checkLabel: checkLabel },
        people: people,
        stateWords: stateWords,
        homeName: homeName
    };
})(globalThis.rao);
