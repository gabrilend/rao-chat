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
            page.setState("connected to " + result.where, true);
        });
    };
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
            byId("settings-lines").value = "";
            byId("settings-token").value = "";
            byId("remember").checked = false;
            say("forgotten: this page keeps nothing of that home now", false);
        });
        // the token is pasted each time the page is opened (403 decision 2)
        if (!missing) { openPanel("settings"); }
    };
    // }}}

    if (typeof document !== "undefined") {
        document.addEventListener("DOMContentLoaded", function () { page.start(document); });
    }
})(globalThis.rao);
