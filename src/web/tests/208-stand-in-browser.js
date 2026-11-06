// 208-stand-in-browser.js - the page without the page: the scripts the web
// client runs, loaded outside a browser so the referees can drive them
// (issue 401, decision 4), as they drive the reference device (190).
//
//   node src/web/tests/208-stand-in-browser.js <project> <command> [...]
//
// It reads the page's HTML (src/web/<n>-rao-chat.html), finds the scripts
// it names, in the order it names them, and runs each as a browser runs a
// classic script, in this process's one global scope.  Node gives the
// same WebCrypto (crypto.subtle, crypto.getRandomValues) and, from
// version 22, the same WebSocket the page uses in a browser; there is no
// `document`, so the page's own drawing script (207) defines its parts
// and starts nothing.  Node is a tool of the referees and the demo only;
// the page never needs it, and nothing is installed with npm.
//
// RAO_WEB_BROKEN, when set, names a broken version for a referee
// (rao.broken, 206).
//
// Commands (each later issue adds its own to COMMANDS):
//   load [--no-subtle]   load the page's scripts and print what they made:
//                        "script <name>" for each, "rao <parts>", "globals
//                        <names>" (every global the scripts added), and
//                        "crypto ok" or "crypto missing: <words>" (with
//                        --no-subtle, crypto.subtle is taken away first,
//                        as a browser does on a page it does not count as
//                        secure)
//   key --token <file>   the tying value of the token in <file> (its bytes,
//                        read as UTF-8 text as typed), in hex (402)
//   seal --token <file> --record <file> --out <file> [--no-pad]
//                        the record sealed into a whole frame (402)
//   open --token <file> --frame <file> --out <file>
//                        a whole frame opened: "record" and the record
//                        written to --out, or "nothing: <why>" (402)
//   records --in <file>  each line of <file> decoded and encoded again:
//                        "ok <kind> <the line again, hex> <field>=<hex>..."
//                        or "refused <why>"; "table" lines give the kinds,
//                        their fields, and the rule fields (402)
//   settings --settings <file> [--token <file>]
//                        "ok", or "refused: <why>" (403)
//   remember --settings <file>
//                        what the page would keep of the lines (403)
//   test --settings <file> [--token <file>] [--public]
//                        the connection test's words; exit 1 unless
//                        answered (403)
//   reach --settings <file> [--token <file>]
//                        "reached <address> <port> by way of <setting>",
//                        or why not; exit 1 unless reached (403)
//   catch-up --settings <file> [--token <file>] [--mirror-in <folder>]
//            [--mirror-out <folder>] [--twice]
//                        reach the home and catch up once, starting from
//                        the mirror in <folder> (none: empty) and writing
//                        the mirror into --mirror-out at the end; prints
//                        "<n> file(s) received (<m> message(s)), <c>
//                        changed, <d> dropped", then "refused <why>" for
//                        each path refused (exit 1 if any); --twice
//                        catches up a second time on the same
//                        connection and prints both summaries (404)
//   positions --mirror-in <folder>
//                        the catch-up's lines for that mirror (404)
//   tree --mirror-in <folder> [--rows] [--backwards]
//                        the room tree as 183's `tree` prints it (with
//                        --backwards the mirror's paths are held in the
//                        reverse of the folder's order, as a home may
//                        send them in any order); with
//                        --rows, one line per row: "<depth> <tag> <kind>
//                        <flagged> <waiting> <label> | <last line>" (405)
//   room --mirror-in <folder> --room <tag>
//                        the open room's lines as text (rao.view.roomText);
//                        exit 1 when the mirror holds no such room (405)
//   draw --mirror-in <folder> [--then <folder>] [--open <tag>]
//                        the page's own script (207) started on a paper
//                        document (below), the mirror drawn, then (with
//                        --then) the second mirror drawn as a later
//                        catch-up would, then (with --open) that room
//                        opened as a click opens it; prints what the
//                        room tree and the room hold, one element a line:
//                        "<indent><name>[.<classes>][#<id>][ hidden] |
//                        <its own text>" (405)
//
// The paper document is the least of a browser's document that 207
// uses: elements made by the HTML's ids, made anew by createElement,
// appendChild, textContent (setting it empties the element; text is only
// ever text), className, classList, hidden, and listeners that `click`
// runs.  It draws nothing; it lets the referees read what the page placed.
//
// Exit status: 0 done, 1 the command failed (said on stderr), 2 usage.

"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const PROJECT = process.argv[2];
const COMMAND = process.argv[3];
const ARGS = process.argv.slice(4);

// {{{ the page's folder and its scripts
function webFolder(project) { return path.join(project, "src", "web"); }

function pageFile(project) {
    const names = fs.readdirSync(webFolder(project)).filter((name) => /^\d{3}-rao-chat\.html$/.test(name));
    if (names.length !== 1) { throw new Error("src/web holds " + names.length + " page files, not one"); }
    return path.join(webFolder(project), names[0]);
}

// the HTML's script names, in its order
function scriptsOf(html) {
    const names = [];
    const pattern = /<script\b([^>]*)>/g;
    let found;
    while ((found = pattern.exec(html)) !== null) {
        const source = /\bsrc="([^"]+)"/.exec(found[1]);
        if (!source) { throw new Error("a script tag with no src: the page has no inline scripts"); }
        names.push(source[1]);
    }
    return names;
}
// }}}

// {{{ load
// project -> the names of the scripts run, in order.  Each is run as a
// browser runs a classic script: in the one global scope, top to bottom.
function load(project) {
    globalThis.RAO_WEB_BROKEN = process.env.RAO_WEB_BROKEN || "";
    const names = scriptsOf(fs.readFileSync(pageFile(project), "utf8"));
    for (const name of names) {
        const file = path.join(webFolder(project), name);
        vm.runInThisContext(fs.readFileSync(file, "utf8"), { filename: file });
    }
    return names;
}
// }}}

// {{{ small helpers for the commands
function option(name) {
    const at = ARGS.indexOf(name);
    return at >= 0 ? ARGS[at + 1] : undefined;
}
function flag(name) { return ARGS.indexOf(name) >= 0; }
function say(line) { process.stdout.write(line + "\n"); }
// }}}

const COMMANDS = {};

// {{{ load
COMMANDS.load = function () {
    if (flag("--no-subtle")) {
        Object.defineProperty(globalThis, "crypto", { value: { getRandomValues: globalThis.crypto.getRandomValues.bind(globalThis.crypto) }, configurable: true });
    }
    globalThis.RAO_WEB_BROKEN = process.env.RAO_WEB_BROKEN || "";
    const before = new Set(Object.getOwnPropertyNames(globalThis));
    const names = load(PROJECT);
    names.forEach((name) => say("script " + name));
    say("rao " + Object.keys(globalThis.rao).sort().join(" "));
    const added = Object.getOwnPropertyNames(globalThis).filter((name) => !before.has(name)).sort();
    say("globals " + added.join(" "));
    const missing = globalThis.rao.bytes.cryptoMissing();
    say(missing ? "crypto missing: " + missing : "crypto ok");
};
// }}}

// {{{ bytes in and out of files: one character per byte (206)
function readBytes(file) { return fs.readFileSync(file).toString("latin1"); }
function writeBytes(file, bytes) { fs.writeFileSync(file, Buffer.from(bytes, "latin1")); }
function readToken(file) { return fs.readFileSync(file, "utf8"); }
function hexOf(bytes) { return Buffer.from(bytes, "latin1").toString("hex"); }
// }}}

// {{{ key / seal / open / records (402)
COMMANDS.key = function () {
    load(PROJECT);
    return globalThis.rao.sealing.keyPair(readToken(option("--token"))).then((pair) => say("tie " + hexOf(pair.tie)));
};
COMMANDS.seal = function () {
    load(PROJECT);
    const rao = globalThis.rao;
    return rao.sealing.keyPair(readToken(option("--token")))
        .then((pair) => rao.sealing.seal(pair, readBytes(option("--record")), { pad: !flag("--no-pad") }))
        .then((frame) => { writeBytes(option("--out"), frame); say("sealed " + frame.length); });
};
COMMANDS.open = function () {
    load(PROJECT);
    const rao = globalThis.rao;
    const frame = readBytes(option("--frame"));
    if (rao.sealing.lengthOf(frame.slice(0, 4)) !== frame.length - 4) { say("nothing: not a frame's length"); return 0; }
    return rao.sealing.keyPair(readToken(option("--token")))
        .then((pair) => rao.sealing.open(pair, frame.slice(4)))
        .then((opened) => {
            if (opened.why) { say("nothing: " + opened.why); return; }
            writeBytes(option("--out"), opened.record);
            say("record");
        });
};
COMMANDS.records = function () {
    load(PROJECT);
    const records = globalThis.rao.records;
    Object.keys(records.KINDS).sort().forEach((kind) => say("table " + kind + " " + records.KINDS[kind].join(" ")));
    say("rules " + Object.keys(records.RULES).sort().join(" "));
    const text = readBytes(option("--in"));
    text.split("\n").forEach((line) => {
        if (line === "") { return; }
        const decoded = records.decode(line);
        if (decoded.why) { say("refused " + decoded.why); return; }
        const fields = records.KINDS[decoded.record.kind].map((name) => name + "=" + hexOf(decoded.record[name]));
        say("ok " + decoded.record.kind + " " + hexOf(records.encode(decoded.record)) + " " + fields.join(" "));
    });
};
// }}}

// {{{ settings / remember / test / reach (403)
// the page's settings from the files given, or a thrown reason
function settingsOf() {
    const token = option("--token") ? readToken(option("--token")) : "";
    const read = globalThis.rao.link.readSettings(fs.readFileSync(option("--settings"), "utf8"), token);
    if (read.why) { throw new Error("the settings were refused: " + read.why); }
    return read.settings;
}
COMMANDS.settings = function () {
    load(PROJECT);
    const token = option("--token") ? readToken(option("--token")) : "";
    const read = globalThis.rao.link.readSettings(fs.readFileSync(option("--settings"), "utf8"), token);
    say(read.why ? "refused: " + read.why : "ok");
};
COMMANDS.remember = function () {
    load(PROJECT);
    process.stdout.write(globalThis.rao.link.rememberText(fs.readFileSync(option("--settings"), "utf8")));
};
COMMANDS.test = function () {
    load(PROJECT);
    return globalThis.rao.link.test(settingsOf(), flag("--public") ? "public" : "home-network").then((result) => {
        say(result.words);
        return result.ok ? 0 : 1;
    });
};
COMMANDS.reach = function () {
    load(PROJECT);
    return globalThis.rao.link.reach(settingsOf()).then((result) => {
        if (!result.link) { say(result.why); return 1; }
        say("reached " + result.where + " by way of " + result.setting);
        result.link.close();
        return 0;
    });
};
// }}}

// {{{ catch-up / positions (404)
// a folder of 301's layout -> the page's mirror (a Map of path -> bytes)
function readMirror(folder) {
    const files = new Map();
    if (!folder || !fs.existsSync(folder)) { return files; }
    (function walk(relative) {
        for (const name of fs.readdirSync(path.join(folder, relative))) {
            const inside = relative ? relative + "/" + name : name;
            const full = path.join(folder, inside);
            if (fs.statSync(full).isDirectory()) { walk(inside); }
            else if (!globalThis.rao.mirror.checkPath(inside).why) { files.set(inside, readBytes(full)); }
        }
    })("");
    return files;
}
// the page's mirror -> a folder of 301's layout, made afresh
function writeMirror(folder, files) {
    fs.rmSync(folder, { recursive: true, force: true });
    for (const [inside, content] of files) {
        // only a path the rule passes is written (a broken version may
        // hold others: said, never written outside the folder)
        if (globalThis.rao.mirror.checkPath(inside).why) { say("held-unchecked " + inside); continue; }
        fs.mkdirSync(path.dirname(path.join(folder, inside)), { recursive: true });
        writeBytes(path.join(folder, inside), content);
    }
    fs.mkdirSync(folder, { recursive: true });
}
function summaryLine(summary) {
    return summary.files + " file(s) received (" + summary.messages + " message(s)), " + summary.changed
        + " changed, " + summary.dropped + " dropped";
}
COMMANDS["catch-up"] = function () {
    load(PROJECT);
    const rao = globalThis.rao;
    const settings = settingsOf();
    const files = readMirror(option("--mirror-in"));
    return rao.link.reach(settings).then((reached) => {
        if (!reached.link) { say(reached.why); return 1; }
        return rao.mirror.catchUp(reached.link, files, settings).then((summary) => {
            if (summary.why || !flag("--twice")) { return summary; }
            // --twice: at once again on the same connection, from the
            // mirror the first made, as a page holding it does
            say(summaryLine(summary));
            return rao.mirror.catchUp(reached.link, files, settings);
        }).then((summary) => {
            reached.link.close();
            if (summary.why) { say(summary.why); return 1; }
            if (option("--mirror-out")) { writeMirror(option("--mirror-out"), files); }
            say(summaryLine(summary));
            summary.refused.forEach((why) => say("refused " + why));
            return summary.refused.length > 0 ? 1 : 0;
        });
    });
};
COMMANDS.positions = function () {
    load(PROJECT);
    return globalThis.rao.mirror.positionsText(readMirror(option("--mirror-in"))).then((text) => {
        process.stdout.write(text);
    });
};
// }}}

// {{{ tree / room (405)
COMMANDS.tree = function () {
    load(PROJECT);
    let files = readMirror(option("--mirror-in"));
    if (flag("--backwards")) { files = new Map(Array.from(files).reverse()); }
    if (!flag("--rows")) { process.stdout.write(globalThis.rao.view.treeText(files)); return 0; }
    globalThis.rao.view.tree(files).forEach((row) => {
        say(row.depth + " " + row.tag + " " + row.kind + " " + row.flagged + " " + row.waiting + " " + row.label
            + " | " + row.last);
    });
    return 0;
};
COMMANDS.room = function () {
    load(PROJECT);
    const shown = globalThis.rao.view.room(readMirror(option("--mirror-in")), option("--room"));
    if (!shown) { say("no room here is '" + option("--room") + "'"); return 1; }
    process.stdout.write(globalThis.rao.view.roomText(shown));
    return 0;
};
// }}}

// {{{ the paper document, and draw (405)
function paperElement(name) {
    const made = {
        tagName: name.toUpperCase(), id: "", className: "", children: [], ownText: "", hidden: false,
        type: "", title: "", value: "", checked: false, disabled: false, listeners: {}, attributes: {},
        scrollTop: 0, clientHeight: 100, scrollHeight: 100,
        appendChild(child) { made.children.push(child); return child; },
        addEventListener(kind, run) { (made.listeners[kind] = made.listeners[kind] || []).push(run); },
        getAttribute(attribute) { return made.attributes[attribute] === undefined ? null : made.attributes[attribute]; },
        click() { (made.listeners.click || []).forEach((run) => run({ preventDefault() {} })); },
    };
    Object.defineProperty(made, "textContent", {
        get() { return made.ownText + made.children.map((child) => child.textContent).join(""); },
        set(text) { made.children = []; made.ownText = String(text); },
    });
    made.classList = {
        contains(word) { return made.className.split(/\s+/).indexOf(word) >= 0; },
        toggle(word, on) {
            const words = made.className.split(/\s+/).filter((w) => w !== "" && w !== word);
            if (on === undefined ? !made.classList.contains(word) : on) { words.push(word); }
            made.className = words.join(" ");
        },
    };
    return made;
}
function paperDocument(html) {
    const byId = {};
    const all = [];
    const pattern = /<([a-z0-9]+)\b([^>]*)>/g;
    let found;
    while ((found = pattern.exec(html)) !== null) {
        const made = paperElement(found[1]);
        const attributes = /\b([a-z-]+)="([^"]*)"/g;
        let pair;
        while ((pair = attributes.exec(found[2])) !== null) { made.attributes[pair[1]] = pair[2]; }
        made.id = made.attributes.id || "";
        made.className = made.attributes.class || "";
        made.hidden = /\shidden\b/.test(found[2]);
        if (made.id) { byId[made.id] = made; }
        all.push(made);
    }
    return {
        getElementById(id) { return byId[id] || null; },
        createElement: paperElement,
        querySelectorAll(selector) { return all.filter((made) => made.classList.contains(selector.replace(/^\./, ""))); },
        addEventListener() {},
    };
}
function paperText(made, depth, out) {
    out.push("  ".repeat(depth) + made.tagName.toLowerCase() + (made.className ? "." + made.className.split(" ").join(".") : "")
        + (made.id ? "#" + made.id : "") + (made.hidden ? " hidden" : "") + " | " + made.ownText);
    made.children.forEach((child) => paperText(child, depth + 1, out));
    return out;
}
// the paper element whose own text is this, under made (a row's button holds its label)
function paperFind(made, text) {
    if (made.ownText === text) { return made; }
    for (const child of made.children) { const inside = paperFind(child, text); if (inside) { return inside; } }
    return null;
}
COMMANDS.draw = function () {
    load(PROJECT);
    const rao = globalThis.rao;
    const doc = paperDocument(fs.readFileSync(pageFile(PROJECT), "utf8"));
    rao.page.start(doc);
    rao.page.files = readMirror(option("--mirror-in"));
    rao.page.draw();
    if (option("--then")) {
        rao.page.files = readMirror(option("--then"));
        rao.page.draw();
    }
    if (option("--open")) {
        const row = rao.view.tree(rao.page.files).filter((one) => one.tag === option("--open"))[0];
        if (!row) { say("no room here is '" + option("--open") + "'"); return 1; }
        // the label's span sits in the row's button: click that button
        const tree = doc.getElementById("tree-rows");
        const label = paperFind(tree, row.label + (row.kind !== "group" ? " (" + row.kind + ")" : ""));
        const button = (function up(made, inside) {
            for (const child of made.children) {
                if (child === inside) { return made; }
                const found = up(child, inside);
                if (found) { return found; }
            }
            return null;
        })(tree, label);
        button.click();
    }
    paperText(doc.getElementById("tree-rows"), 0, []).forEach(say);
    say(doc.getElementById("room-title").textContent);
    paperText(doc.getElementById("room-lines"), 0, []).forEach(say);
    return 0;
};
// }}}

module.exports = { paperDocument, paperText, readMirror, writeMirror, summaryLine, settingsOf, load, scriptsOf, pageFile, webFolder, COMMANDS, option, flag, say };

// {{{ main
if (require.main === module) {
    if (!PROJECT || !COMMAND || !COMMANDS[COMMAND]) {
        process.stderr.write("usage: node 208-stand-in-browser.js <project> <command> [...]\ncommands: "
            + Object.keys(COMMANDS).join(", ") + "\n");
        process.exit(2);
    }
    Promise.resolve()
        .then(() => COMMANDS[COMMAND]())
        .then((status) => process.exit(typeof status === "number" ? status : 0))
        .catch((problem) => {
            process.stderr.write("stand-in: " + (problem && problem.message ? problem.message : String(problem)) + "\n");
            process.exit(1);
        });
}
// }}}
