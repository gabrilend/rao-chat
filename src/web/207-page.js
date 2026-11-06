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

    // {{{ settings: what is remembered, and the form (issues 403, 406, 408)
    // The browser's storage holds each remembered home's lines, under the
    // name the person gave it, without the token, and only when "remember"
    // is ticked (403 decision 2, 408 decision 3; 225 keeps them).  Storage
    // a browser refuses (some do for pages opened from files) is said, not
    // fatal.
    var REFUSING = {
        getItem: function () { throw new Error("no storage"); },
        setItem: function () { throw new Error("no storage"); },
        removeItem: function () { throw new Error("no storage"); }
    };
    function storage() {
        try { return globalThis.localStorage || REFUSING; } catch (problem) { return REFUSING; }
    }
    page.storage = storage;
    function label() { return byId("home-label").value.trim(); }
    // the form's home kept, when "remember" is ticked
    function keep() {
        if (!byId("remember").checked) { return ""; }
        var signature = byId("signature").value;
        if (rao.writing.checkSignature(rao.bytes.fromText(signature))) { signature = ""; }
        return rao.panels.homes.remember(storage(), label(), byId("settings-lines").value, signature);
    }
    // a remembered home into the form (its token is pasted again)
    function choose(name) {
        var found = rao.panels.homes.read(storage(), name);
        if (found.why) { say(found.why, true); return; }
        byId("home-label").value = name;
        byId("settings-lines").value = found.lines;
        byId("signature").value = found.signature;
        byId("settings-token").value = "";
        byId("remember").checked = true;
        page.topBar();
        openPanel("settings");
        say("paste the token for " + name + ", then Connect", false);
    }
    page.choose = choose;
    function drawHomes() {
        var list = byId("homes-list");
        list.textContent = "";
        var found = rao.panels.homes.list(storage());
        if (found.why) { list.appendChild(element("li", "quiet", found.why)); return; }
        if (found.labels.length === 0) {
            list.appendChild(element("li", "quiet", "No home remembered: tick \"remember\" in Settings to keep one."));
        }
        found.labels.forEach(function (name) {
            var item = element("li");
            var button = element("button", name === label() ? "open" : null, name);
            button.type = "button";
            button.addEventListener("click", function () { choose(name); });
            item.appendChild(button);
            list.appendChild(item);
        });
    }
    page.drawHomes = drawHomes;
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
        var trouble = keep();
        if (trouble) { say(trouble, true); }
        drawHomes();
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

    // {{{ page.connect: live while the page is open (issues 403, 404, 407)
    // The mirror stays in this page's memory for as long as it is open
    // (404 decision 1), so each new connection catches up from it.  The
    // session (223) reaches the home, catches up, sends what the outbox
    // waits on, listens, and tries again after a drop.
    page.files = new Map();
    page.connect = function () {
        var settings = formSettings();
        if (!settings) { return; }
        page.settings = settings;
        if (page.session) { page.session.stop(); }
        page.session = new rao.live.Session(settings, page.files, page.outbox, {
            state: function () { page.topBar(); },
            errors: page.showErrors,
            changed: function () { page.draw(); },
            caughtUp: function (summary) {
                say("caught up: " + summary.messages + " new message file(s)", false);
            }
        });
        page.session.start();
    };
    // the top bar: the home's name (the person's label for it, or the
    // address reached) and the connection state's words (408)
    page.topBar = function () {
        var session = page.session;
        if (session && session.link && session.link.where) { page.where = session.link.where; }
        byId("home-name").textContent = rao.panels.homeName(label(), page.where);
        var state = session ? session.state : "stopped";
        page.setState(rao.panels.stateWords(state), state === "live");
    };
    // the strip's countdown, once a second while a retry waits
    function tick() {
        if (page.session && page.session.state === "waiting") { page.session.showErrors([]); }
    }
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
        drawPeople();
    };
    // the People panel: every mailbox's direct-message rooms (408 decision 1)
    function drawPeople() {
        var list = byId("people-list");
        list.textContent = "";
        rao.panels.people(page.files).forEach(function (person) {
            var item = element("li");
            var button = element("button", "tree-row" + (person.tag === page.openRoom ? " open" : ""));
            button.type = "button";
            button.appendChild(element("span", "label", person.label));
            button.appendChild(element("span", "last-line", person.last));
            button.addEventListener("click", function () { page.open(person.tag); });
            item.appendChild(button);
            list.appendChild(item);
        });
    }
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
    // sends what waits on the live connection (223), if there is one
    page.flush = function () {
        if (page.session) { page.session.sendWaiting(); }
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
        var missing = rao.bytes.cryptoMissing();
        page.showErrors(missing ? [missing] : [], false);
        var last = rao.panels.homes.last(storage());
        if (last) {
            var found = rao.panels.homes.read(storage(), last);
            if (!found.why) {
                byId("home-label").value = last;
                byId("settings-lines").value = found.lines;
                byId("signature").value = found.signature;
                byId("remember").checked = true;
            }
        }
        page.topBar();
        drawHomes();
        byId("home-label").addEventListener("change", function () { page.topBar(); });
        byId("settings-form").addEventListener("submit", function (event) {
            event.preventDefault();
            page.connect();
        });
        byId("test-connection").addEventListener("click", testConnection);
        byId("forget-home").addEventListener("click", function () {
            var name = label();
            var trouble = name ? rao.panels.homes.forget(storage(), name) : "";
            byId("settings-lines").value = "";
            byId("settings-token").value = "";
            byId("signature").value = "";
            byId("remember").checked = false;
            drawHomes();
            say(trouble || (name ? "forgotten: this page keeps nothing of " + name + " now"
                : "the form is cleared; give a home's name to forget one this page remembers"), !!trouble);
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
        byId("signature").addEventListener("change", function () {
            var why = rao.writing.checkSignature(rao.bytes.fromText(byId("signature").value));
            var trouble = why ? "" : keep();
            say(why || trouble || "signature kept" + (byId("remember").checked ? " on this computer" : " while this page is open"),
                !!(why || trouble));
        });
        byId("retry-now").addEventListener("click", function () {
            if (page.session) { page.session.retryNow(); }
        });
        // something still sending when the page closes: the browser asks;
        // the browser saying it is online again is a "retry now" (407);
        // the strip's countdown moves once a second
        if (typeof globalThis.addEventListener === "function") {
            globalThis.addEventListener("online", function () {
                if (page.session) { page.session.retryNow(); }
            });
            globalThis.setInterval(tick, 1000);
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
