// 207-page.js - the page's own script: the part that draws (issue 401).
//
// Everything the page shows is worked out by the other scripts as plain
// lists and words; this one only places them in the page, always as text
// (textContent, never markup: 401's referee 3), and wires the page's
// buttons to them.  It is the one script the stand-in browser (tests/208)
// loads but never starts, since outside a browser there is no page.
//
// Section 9's frame: a top bar (the home's name, the connection state,
// the tabs), the error strip, the room trees on the left, the open room
// on the right with its compose line, and the Homes, People and Settings
// panels opening over the room view.  A panel closes with its own button
// or Escape, and the room behind it keeps its place.

(function (rao) {
    "use strict";
    var page = rao.page = {};

    // {{{ small helpers
    function byId(id) { return page.doc.getElementById(id); }
    // a new element holding text (never markup)
    function element(name, className, text) {
        var made = page.doc.createElement(name);
        if (className) { made.className = className; }
        if (text !== undefined && text !== null) { made.textContent = text; }
        return made;
    }
    page.byId = byId;
    page.element = element;
    // }}}

    // {{{ panels
    var PANELS = { homes: "homes-panel", people: "people-panel", settings: "settings-panel" };
    function openPanel(name) {
        Object.keys(PANELS).forEach(function (key) {
            byId(PANELS[key]).hidden = key !== name;
        });
        Array.prototype.forEach.call(page.doc.querySelectorAll(".tab"), function (tab) {
            tab.classList.toggle("selected", tab.getAttribute("data-panel") === (name || "rooms"));
        });
    }
    page.openPanel = openPanel;
    // }}}

    // {{{ the top bar and the error strip
    page.setState = function (words, live) {
        var state = byId("connection-state");
        state.textContent = words;
        state.classList.toggle("live", !!live);
    };
    // lines: a list of strings; an empty list hides the strip
    page.showErrors = function (lines, retrying) {
        var list = byId("error-lines");
        list.textContent = "";
        lines.forEach(function (line) { list.appendChild(element("li", null, line)); });
        byId("error-strip").hidden = lines.length === 0;
        byId("retry-now").hidden = !retrying;
    };
    // }}}

    // {{{ settings: what is remembered, and the form (issue 403)
    // The browser's storage holds the lines without the token, and only
    // when "remember" is ticked (403 decision 2).  Storage a browser
    // refuses (some do for pages opened from files) is said, not fatal.
    var STORE = "rao-chat settings";
    function stored() {
        try { return globalThis.localStorage.getItem(STORE); } catch (problem) { return null; }
    }
    function store(text) {
        try {
            if (text === null) { globalThis.localStorage.removeItem(STORE); } else { globalThis.localStorage.setItem(STORE, text); }
            return "";
        } catch (problem) {
            return "This browser keeps nothing for this page (" + problem.message + "); paste the lines each time.";
        }
    }
    // the signature is kept with the remembered lines (406), under its own name
    var SIGNATURE = "rao-chat signature";
    function storedSignature() {
        try { return globalThis.localStorage.getItem(SIGNATURE); } catch (problem) { return null; }
    }
    function storeSignature(text) {
        try {
            if (text === null) { globalThis.localStorage.removeItem(SIGNATURE); } else { globalThis.localStorage.setItem(SIGNATURE, text); }
        } catch (problem) { /* said by store() when the lines are kept */ }
    }
    function say(words, problem) {
        var place = byId("settings-words");
        place.textContent = words;
        place.classList.toggle("problem", !!problem);
    }
    page.say = say;
    // -> the settings from the form, or null (said)
    function formSettings() {
        var read = rao.link.readSettings(byId("settings-lines").value, byId("settings-token").value);
        if (read.why) { say(read.why, true); return null; }
        if (byId("remember").checked) {
            var trouble = store(rao.link.rememberText(byId("settings-lines").value));
            if (trouble) { say(trouble, true); }
        }
        return read.settings;
    }
    function testConnection() {
        var settings = formSettings();
        if (!settings) { return; }
        say("testing…", false);
        var choices = ["home-network", "public"].filter(function (name) { return settings[name] !== "unknown"; });
        Promise.all(choices.map(function (name) { return rao.link.test(settings, name); })).then(function (results) {
            var lines = results.map(function (result, i) { return choices[i] + ": " + result.words; });
            say(lines.join("\n"), results.every(function (result) { return !result.ok; }));
        });
    }
    // }}}

    // {{{ page.connect
    // Reaches the home with the form's settings (403); later issues carry
    // on from the link it gives.
    page.connect = function () {
        var settings = formSettings();
        if (!settings) { return; }
        page.settings = settings;
        page.setState("connecting…", false);
        rao.link.reach(settings).then(function (result) {
            if (!result.link) {
                page.setState("not connected", false);
                page.showErrors([result.why], false);
                return;
            }
            if (page.link) { page.link.close(); }
            page.link = result.link;
            page.showErrors([], false);
            say("reached " + result.where + " by way of " + result.setting, false);
            page.catchUp(result.link);
        });
    };
    // }}}

    // {{{ page.catchUp
    // The mirror stays in this page's memory for as long as it is open
    // (404 decision 1), so a second connection catches up from it.
    page.files = new Map();
    page.catchUp = function (link) {
        page.setState("catching up…", false);
        return rao.mirror.catchUp(link, page.files, page.settings).then(function (summary) {
            if (summary.why) {
                page.setState("not connected", false);
                page.showErrors([summary.why], false);
                return summary;
            }
            page.setState("caught up with " + link.where, true);
            page.showErrors(summary.refused.map(function (why) { return "refused from the home: " + why; }), false);
            if (page.draw) { page.draw(); }
            page.flush();
            return summary;
        });
    };
    // }}}

    // {{{ page.draw: the room tree and the open room (issue 405)
    // rao.view works out what is shown; this only places it, as text.
    // Unread counts live in this page only (405 decision 5): the messages
    // a room holds beyond what it held when last open here.  At the first
    // catch-up everything held counts as read, since the page has no
    // memory of earlier visits (405, while building, decision 7).
    page.seen = null;
    page.folded = {};
    page.openRoom = null;
    page.draw = function () {
        var counts = rao.view.messageCounts(page.files);
        if (page.seen === null) { page.seen = counts; }
        if (page.openRoom !== null) { page.seen[page.openRoom] = counts[page.openRoom] || 0; }
        var unread = {};
        Object.keys(counts).forEach(function (tag) {
            unread[tag] = Math.max(0, counts[tag] - (page.seen[tag] === undefined ? 0 : page.seen[tag]));
        });
        drawTree(rao.view.tree(page.files, unread));
        drawRoom();
        composeNote();
    };
    page.open = function (tag) {
        page.openRoom = tag;
        page.openPanel(null);
        page.draw();
    };
    // rows (in the order shown, each with its depth) -> nested lists
    function drawTree(rows) {
        var top = byId("tree-rows");
        top.textContent = "";
        byId("tree-empty").hidden = rows.length > 0;
        var lists = [top];
        rows.forEach(function (row) {
            lists.length = row.depth + 1;
            var item = element("li");
            if (row.hasChildren) {
                var fold = element("button", "tree-fold", page.folded[row.tag] ? "+" : "-");
                fold.type = "button";
                fold.title = page.folded[row.tag] ? "open" : "fold";
                fold.addEventListener("click", function () {
                    page.folded[row.tag] = !page.folded[row.tag];
                    page.draw();
                });
                item.appendChild(fold);
            }
            var button = element("button", "tree-row" + (row.tag === page.openRoom ? " open" : ""));
            button.type = "button";
            button.appendChild(element("span", "label", row.label + (row.kind !== "group" ? " (" + row.kind + ")" : "")));
            if (row.unread > 0) { button.appendChild(element("span", "unread", " (" + row.unread + ")")); }
            if (row.flagged > 0) { button.appendChild(element("span", "marks", " [" + row.flagged + " flagged]")); }
            if (row.waiting > 0) { button.appendChild(element("span", "marks", " [" + row.waiting + " waiting]")); }
            button.appendChild(element("span", "last-line", row.last));
            button.addEventListener("click", function () { page.open(row.tag); });
            item.appendChild(button);
            lists[row.depth].appendChild(item);
            var children = element("ul");
            children.hidden = !!page.folded[row.tag];
            item.appendChild(children);
            lists[row.depth + 1] = children;
        });
    }
    function drawRoom() {
        var title = byId("room-title");
        var list = byId("room-lines");
        var shown = page.openRoom === null ? null : rao.view.room(page.files, page.openRoom);
        if (!shown) {
            // no room open, or the home has left the one that was
            page.openRoom = null;
            title.textContent = "";
            list.textContent = "";
            return;
        }
        var atBottom = list.scrollTop + list.clientHeight >= list.scrollHeight - 4;
        title.textContent = shown.title + "  (" + shown.kind + ", " + shown.members + " member(s))";
        list.textContent = "";
        shown.lines.forEach(function (line) {
            if (line.type === "notice") { list.appendChild(element("li", "line notice", line.text)); return; }
            var item = element("li", "line " + line.side);
            item.id = line.anchor;
            if (line.name !== null) {
                var name = element("span", "name", line.name);
                if (line.name !== line.from) { name.appendChild(element("span", "from", "  " + line.from)); }
                item.appendChild(name);
            }
            var marked = line.marks.indexOf("deleted") >= 0 || line.marks.indexOf("ignored") >= 0;
            item.appendChild(element("span", marked ? "body marked" : "body", line.text));
            var foot = element("span", "when", "  " + line.when);
            if (line.marks.length > 0) { foot.appendChild(element("span", "marks", "  " + line.marks.join(", "))); }
            item.appendChild(foot);
            list.appendChild(item);
        });
        var marker = page.outbox.marker(page.files, shown.tag);
        if (marker) { list.appendChild(element("li", "line mine marker", marker)); }
        if (atBottom) { list.scrollTop = list.scrollHeight; }
    }
    // }}}

    // {{{ writing (issue 406)
    // What the person types goes into the outbox (221) and is sent once
    // the page holds a connection; it stays there, in this page only,
    // until the home answers (406 decision 2).
    page.outbox = new rao.writing.Outbox();
    page.sending = false;
    function composeNote() {
        var note = byId("compose-note");
        note.textContent = "";
        page.outbox.refused().filter(function (item) { return item.room === page.openRoom; }).forEach(function (item) {
            var text = rao.bytes.toText(item.text);
            var line = element("span", "refused", "not sent (" + item.why + "): " + text.split("\n")[0].slice(0, 60) + " ");
            // back into the compose line as typed, to change and send again
            var back = element("button", null, "put it back");
            back.type = "button";
            back.addEventListener("click", function () {
                byId("compose-text").value = text;
                grow();
                page.outbox.forget(item.name);
                page.draw();
            });
            var forget = element("button", null, "forget it");
            forget.type = "button";
            forget.addEventListener("click", function () { page.outbox.forget(item.name); page.draw(); });
            line.appendChild(back);
            line.appendChild(forget);
            note.appendChild(line);
        });
        var compose = byId("compose-text");
        compose.disabled = page.openRoom === null;
        byId("compose-send").disabled = page.openRoom === null;
    }
    page.composeNote = composeNote;
    // sends what waits, one sending at a time, then draws
    page.flush = function () {
        if (!page.link || page.sending || page.outbox.waiting().length === 0) { return; }
        page.sending = true;
        page.outbox.send(page.link, page.files, page.settings).then(function (result) {
            page.sending = false;
            if (result.why) {
                page.setState("not connected", false);
                page.showErrors([result.why], false);
                page.link = null;
            }
            page.draw();
            if (!result.why) { page.flush(); }
        });
    };
    page.send = function () {
        if (page.openRoom === null) { return; }
        var compose = byId("compose-text");
        var signature = byId("signature").value;
        var added = page.outbox.add(page.openRoom, rao.bytes.fromText(compose.value), rao.bytes.fromText(signature),
            Date.now() / 1000);
        if (added.why) { byId("compose-note").textContent = added.why; return; }
        compose.value = "";
        grow();
        page.draw();
        page.flush();
    };
    // the compose line grows with its text, to eight lines
    function grow() {
        var compose = byId("compose-text");
        compose.rows = Math.max(1, Math.min(8, compose.value.split("\n").length));
    }
    // }}}

    // {{{ page.start
    // doc: the page's document.  Wires the tabs and panels, and says
    // whether this browser gives the page what it needs.
    page.start = function (doc) {
        page.doc = doc;
        Array.prototype.forEach.call(doc.querySelectorAll(".tab"), function (tab) {
            tab.addEventListener("click", function () {
                var name = tab.getAttribute("data-panel");
                openPanel(name === "rooms" ? null : name);
            });
        });
        Array.prototype.forEach.call(doc.querySelectorAll(".panel-close"), function (button) {
            button.addEventListener("click", function () { openPanel(null); });
        });
        doc.addEventListener("keydown", function (event) {
            if (event.key === "Escape") { openPanel(null); }
        });
        byId("home-name").addEventListener("click", function () { openPanel("homes"); });
        openPanel(null);
        page.setState("not connected", false);
        var missing = rao.bytes.cryptoMissing();
        page.showErrors(missing ? [missing] : [], false);
        var remembered = stored();
        if (remembered) {
            byId("settings-lines").value = remembered;
            byId("remember").checked = true;
        }
        byId("settings-form").addEventListener("submit", function (event) {
            event.preventDefault();
            page.connect();
        });
        byId("test-connection").addEventListener("click", testConnection);
        byId("forget-home").addEventListener("click", function () {
            store(null);
            storeSignature(null);
            byId("settings-lines").value = "";
            byId("settings-token").value = "";
            byId("remember").checked = false;
            say("forgotten: this page keeps nothing of that home now", false);
        });
        byId("compose").addEventListener("submit", function (event) {
            event.preventDefault();
            page.send();
        });
        // Enter sends, Shift+Enter starts a new line (406 decision 1)
        byId("compose-text").addEventListener("keydown", function (event) {
            if (event.key === "Enter" && !event.shiftKey) {
                event.preventDefault();
                page.send();
            }
        });
        byId("compose-text").addEventListener("input", grow);
        var signature = storedSignature();
        if (signature !== null) { byId("signature").value = signature; }
        byId("signature").addEventListener("change", function () {
            var value = byId("signature").value;
            var why = rao.writing.checkSignature(rao.bytes.fromText(value));
            say(why || "signature kept" + (byId("remember").checked ? " on this computer" : " while this page is open"), !!why);
            if (!why && byId("remember").checked) { storeSignature(value); }
        });
        // something still sending when the page closes: the browser asks
        if (typeof globalThis.addEventListener === "function") {
            globalThis.addEventListener("beforeunload", function (event) {
                if (page.outbox.waiting().length > 0) {
                    event.preventDefault();
                    event.returnValue = "";
                }
            });
        }
        // the token is pasted each time the page is opened (403 decision 2)
        if (!missing) { openPanel("settings"); }
    };
    // }}}

    if (typeof document !== "undefined") {
        document.addEventListener("DOMContentLoaded", function () { page.start(document); });
    }
})(globalThis.rao);
