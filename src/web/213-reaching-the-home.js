// 213-reaching-the-home.js - the page's settings, its WebSocket to the
// home, and its connection test (issue 403).
//
// Settings are the lines pairing printed (`189-pair.lua ... add <label>
// --browser`), pasted: "name = value" lines read by the rule of 190's
// config (blank lines and "#" lines carry nothing, a name set twice is
// refused), with the token in its own password box (403 decision 2):
//
//   port            the home's device port, 1 to 65535
//   home-network    the home's address on the home network, or "unknown"
//   public          the home's public address, or "unknown"
//   websocket-path  the path the home answers the upgrade on (309)
//   wait            seconds to wait for the WebSocket to open, and again
//                   for an answer
//   quick-wait      seconds to wait for the home-network address to open
//   keep-alive      seconds of sending nothing before a ping (407)
//   token           the device's token: from the token box; a token line
//                   is read only when the box is empty
//
// A connection is one WebSocket to ws://<address>:<port><path>, binary,
// one 302 frame per message (309), its first frame a sealed ping.  The
// address is chosen as 307 chooses: home-network with quick-wait, then
// public with wait.  An address whose WebSocket opens but whose home does
// not answer the ping is the home refusing (or stuck), so the next one is
// not tried and the page says so (307 decision 2).
//
// What a browser can tell apart is less than what 190 can: a refused
// port, an unreachable address and a path the home does not answer all
// end the same way, with no reason given to the page.  The words say so
// rather than guess (403's rubric).
//
//   rao.link.readSettings(text, token)  -> {settings} or {why}
//   rao.link.rememberText(text)         -> the lines without the token
//   rao.link.reach(settings)            -> Promise of {link, where, setting} or {why}
//   rao.link.test(settings, setting)    -> Promise of {ok, words}
//   link.send(record) -> Promise; link.next(seconds) -> Promise of
//     {record} or {lost: "closed" | "timeout" | "frame" | "sealed" | "record"};
//   link.close()

(function (rao) {
    "use strict";
    var bytes = rao.bytes;
    var sealing = rao.sealing;
    var records = rao.records;

    // {{{ readSettings
    function readSettings(text, token) {
        var values = {};
        var lines = String(text).split(/\r?\n/);
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim();
            if (line === "" || line.charAt(0) === "#") { continue; }
            var found = /^([^\s=]+)\s*=\s*(.*)$/.exec(line);
            if (!found) { return { why: "line " + (i + 1) + " is not a 'name = value' line: " + line.slice(0, 60) }; }
            if (Object.prototype.hasOwnProperty.call(values, found[1])) {
                return { why: "line " + (i + 1) + ": '" + found[1] + "' is set twice" };
            }
            values[found[1]] = found[2];
        }
        var names = ["port", "home-network", "public", "websocket-path", "wait", "quick-wait", "keep-alive"];
        for (var n = 0; n < names.length; n++) {
            if (!Object.prototype.hasOwnProperty.call(values, names[n])) {
                return { why: "the settings have no " + names[n] + " line (paste every line pairing printed with --browser)" };
            }
        }
        var settings = {};
        if (!/^[1-9][0-9]*$/.test(values.port) || Number(values.port) > 65535) {
            return { why: "port must be a whole number 1 to 65535, not '" + values.port + "'" };
        }
        settings.port = Number(values.port);
        var addresses = ["home-network", "public"];
        for (var a = 0; a < addresses.length; a++) {
            var address = values[addresses[a]];
            if (!/^[A-Za-z0-9.:_-]+$/.test(address)) {
                return { why: addresses[a] + " must be an address or \"unknown\", not '" + address + "'" };
            }
            settings[addresses[a]] = address;
        }
        if (settings["home-network"] === "unknown" && settings["public"] === "unknown") {
            return { why: "home-network and public are both \"unknown\": there is no address to try" };
        }
        // 309 decision 7's rule for the path
        if (!/^\/[A-Za-z0-9._~\/-]*$/.test(values["websocket-path"])) {
            return { why: "websocket-path must start with / and hold only letters, digits and - . _ ~ /" };
        }
        settings["websocket-path"] = values["websocket-path"];
        var waits = ["wait", "quick-wait"];
        for (var w = 0; w < waits.length; w++) {
            var seconds = Number(values[waits[w]]);
            if (!/^[0-9.]+$/.test(values[waits[w]]) || !(seconds > 0)) {
                return { why: waits[w] + " must be a number of seconds above 0" };
            }
            settings[waits[w]] = seconds;
        }
        if (!/^[1-9][0-9]*$/.test(values["keep-alive"])) { return { why: "keep-alive must be whole seconds above 0" }; }
        settings["keep-alive"] = Number(values["keep-alive"]);
        settings.token = token ? token : values.token;
        try {
            sealing.checkToken(settings.token);
        } catch (problem) {
            return { why: settings.token ? "token: " + problem.message : "there is no token: paste it into the token box" };
        }
        return { settings: settings };
    }
    // }}}

    // {{{ rememberText
    // the pasted lines -> the same lines without any token line, for the
    // browser's storage (403 decision 2: the token is never stored)
    function rememberText(text) {
        if (rao.broken === "keep-token") { return String(text); }
        return String(text).split(/\r?\n/).filter(function (line) {
            return !/^\s*token\s*=/.test(line);
        }).join("\n");
    }
    // }}}

    // {{{ urlOf / whereOf
    function urlOf(settings, address) {
        var host = address.indexOf(":") >= 0 ? "[" + address + "]" : address;
        return "ws://" + host + ":" + settings.port + settings["websocket-path"];
    }
    function whereOf(settings, address) { return address + " " + settings.port; }
    // }}}

    // {{{ Link: one WebSocket carrying one frame per message
    function Link(socket, pair) {
        var link = this;
        link.socket = socket;
        link.pair = pair;
        link.arrived = [];      // whole messages not yet read, as byte strings
        link.waiting = null;    // the one reader waiting, if any
        link.closed = false;
        socket.addEventListener("message", function (event) {
            if (typeof event.data === "string") { link.arrived.push(null); } else { link.arrived.push(bytes.fromArray(event.data)); }
            link.wake();
        });
        socket.addEventListener("close", function () { link.closed = true; link.wake(); });
        socket.addEventListener("error", function () { link.closed = true; link.wake(); });
    }
    Link.prototype.wake = function () {
        if (this.waiting) { var waiting = this.waiting; this.waiting = null; waiting(); }
    };
    // record -> Promise of true, or false when the connection is gone
    Link.prototype.send = function (record) {
        var link = this;
        if (link.closed) { return Promise.resolve(false); }
        return sealing.seal(link.pair, records.encode(record)).then(function (frame) {
            if (link.closed) { return false; }
            link.socket.send(bytes.toArray(frame));
            link.lastSent = Date.now();
            return true;
        });
    };
    // seconds (none: no limit) -> Promise of {record} or {lost}
    Link.prototype.next = function (seconds) {
        var link = this;
        return new Promise(function (resolve) {
            var timer = null;
            function take() {
                if (link.arrived.length > 0) {
                    if (timer) { clearTimeout(timer); }
                    var message = link.arrived.shift();
                    // exactly one 302 frame per binary message (309)
                    if (message === null || sealing.lengthOf(message.slice(0, 4)) !== message.length - 4) {
                        resolve({ lost: "frame" });
                        return;
                    }
                    sealing.open(link.pair, message.slice(4)).then(function (opened) {
                        if (opened.why) { resolve({ lost: "sealed" }); return; }
                        var decoded = records.decode(opened.record);
                        resolve(decoded.why ? { lost: "record" } : { record: decoded.record });
                    });
                    return;
                }
                if (link.closed) {
                    if (timer) { clearTimeout(timer); }
                    resolve({ lost: "closed" });
                    return;
                }
                link.waiting = take;
            }
            if (seconds !== undefined && seconds !== null) {
                timer = setTimeout(function () {
                    if (link.waiting === take) { link.waiting = null; }
                    resolve({ lost: "timeout" });
                }, seconds * 1000);
            }
            take();
        });
    };
    Link.prototype.close = function () {
        this.closed = true;
        try { this.socket.close(); } catch (ignored) { /* already closing */ }
        this.wake();
    };
    // }}}

    // {{{ openSocket
    // settings, address, seconds -> Promise of {socket} or {why, opened: false}
    function openSocket(settings, address, seconds) {
        var where = whereOf(settings, address);
        if (address === "unknown") {
            return Promise.resolve({ why: "no address to try: the setting is \"unknown\"" });
        }
        return new Promise(function (resolve) {
            var socket;
            try {
                socket = new globalThis.WebSocket(urlOf(settings, address));
            } catch (problem) {
                resolve({ why: "no WebSocket could be made for " + where + ": " + problem.message });
                return;
            }
            socket.binaryType = "arraybuffer";
            var done = false;
            var timer = setTimeout(function () {
                if (done) { return; }
                done = true;
                try { socket.close(); } catch (ignored) { /* never opened */ }
                resolve({ why: "nothing answered the opening at " + where + " within " + seconds + " s" });
            }, seconds * 1000);
            function failed() {
                if (done) { return; }
                done = true;
                clearTimeout(timer);
                resolve({ why: "no WebSocket could be opened at " + where + " on " + settings["websocket-path"]
                    + " (a browser is not told why: nothing listens there, the address cannot be reached, "
                    + "or the path is not the home's)" });
            }
            socket.addEventListener("error", failed);
            socket.addEventListener("close", failed);
            socket.addEventListener("open", function () {
                if (done) { return; }
                done = true;
                clearTimeout(timer);
                socket.removeEventListener("error", failed);
                socket.removeEventListener("close", failed);
                resolve({ socket: socket });
            });
        });
    }
    // }}}

    // {{{ silence: the words for a home that sent nothing, or not a frame
    function silence(settings, where, lost) {
        if (lost === "closed") {
            return where + " closed the connection without a word: the token is not one this home knows";
        }
        if (lost === "timeout") {
            return where + " said nothing within " + settings.wait
                + " s: this may not be a device port, or the home is stuck";
        }
        return where + " answered with something that is not a frame under this token";
    }
    // }}}

    // {{{ ping: one sealed ping, answered by its pong
    // link, settings, where -> Promise of {ok, ms} or {why}
    function ping(link, settings, where) {
        var id = bytes.hex(bytes.random(8));
        var started = Date.now();
        return link.send({ kind: "ping", id: id }).then(function (sent) {
            return sent ? link.next(settings.wait) : { lost: "closed" };
        }).then(function (reply) {
            if (reply.record && reply.record.kind === "pong" && reply.record.id === id) {
                return { ok: true, ms: Date.now() - started };
            }
            if (reply.record) { return { why: where + " answered, but not this ping's pong" }; }
            return { why: silence(settings, where, reply.lost) };
        });
    }
    // }}}

    // {{{ connect: open, then a ping answered
    // settings, address, seconds -> Promise of {link, where, ms} or
    // {why, opened} (opened: the WebSocket opened, so the home itself
    // refused or is stuck)
    function connect(settings, address, seconds) {
        var where = whereOf(settings, address);
        return Promise.all([openSocket(settings, address, seconds), sealing.keyPair(settings.token)])
            .then(function (both) {
                var opened = both[0];
                if (!opened.socket) { return { why: opened.why, opened: false }; }
                var link = new Link(opened.socket, both[1]);
                return ping(link, settings, where).then(function (answer) {
                    if (answer.ok) { return { link: link, where: where, ms: answer.ms }; }
                    link.close();
                    return { why: answer.why, opened: true };
                });
            });
    }
    // }}}

    // {{{ oneMessage: the referees' broken version, one message for all
    function told(result) {
        if (rao.broken === "one-message" && result.why) { return { why: "could not connect" }; }
        return result;
    }
    // }}}

    // {{{ reach
    // settings -> Promise of {link, where, setting} or {why}: home-network
    // with quick-wait first, then public with wait (307)
    function reach(settings) {
        var order = [["home-network", settings["quick-wait"]], ["public", settings.wait]];
        if (rao.broken === "public-first") { order.reverse(); }
        var tried = [];
        function attempt(i) {
            if (i >= order.length) {
                return told({ why: "the home could not be reached (" + tried.join("; ") + ")" });
            }
            var setting = order[i][0];
            return connect(settings, settings[setting], order[i][1]).then(function (result) {
                if (result.link) {
                    result.link.where = result.where;
                    return { link: result.link, where: result.where, setting: setting };
                }
                if (result.opened) { return told({ why: result.why }); }
                tried.push(setting + ": " + result.why);
                return attempt(i + 1);
            });
        }
        return attempt(0);
    }
    // }}}

    // {{{ test
    // settings, setting ("home-network" or "public") -> Promise of {ok, words}
    function test(settings, setting) {
        var address = settings[setting];
        return connect(settings, address, settings.wait).then(function (result) {
            if (result.link) {
                result.link.close();
                return { ok: true, words: "answered in " + result.ms + " ms by " + result.where };
            }
            return { ok: false, words: told(result).why };
        });
    }
    // }}}

    rao.link = {
        readSettings: readSettings,
        rememberText: rememberText,
        urlOf: urlOf,
        reach: reach,
        test: test,
        connect: connect,
        silence: silence,
        Link: Link
    };
})(globalThis.rao);
