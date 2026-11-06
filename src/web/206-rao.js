// 206-rao.js - the one object the page's scripts share, and the bytes
// they pass between them (issue 401; 402 decision 3).
//
// Every script of the page is a classic script, not a module (a browser
// refuses module scripts from a page opened from a file, 401 decision 3).
// Each is wrapped in a function and adds its part to `rao`, the only
// global name the page makes; none touches a page element when it loads,
// so a stand-in outside a browser (tests/208) loads the same files.
//
// Bytes.  What crosses the network is held as a "byte string": a string
// whose every character is one byte, 0 to 255, the way Lua holds bytes.
// The record escaping (186), the digests (192) and the signature rule
// (169, which counts characters from bytes) then read exactly as the Lua
// beside them, and an array is made only where WebCrypto or the
// WebSocket needs one.  Text a person typed is turned into a byte string
// by fromText (UTF-8), and a byte string is turned back into text to be
// shown by toText.
//
//   rao.bytes.fromText(text)      text -> byte string (UTF-8)
//   rao.bytes.toText(bytes)       byte string -> text (bad UTF-8 shown as U+FFFD)
//   rao.bytes.toArray(bytes)      byte string -> Uint8Array
//   rao.bytes.fromArray(array)    Uint8Array or ArrayBuffer -> byte string
//   rao.bytes.hex(bytes)          byte string -> lower-case hex
//   rao.bytes.random(n)           n random bytes, from crypto.getRandomValues
//   rao.bytes.sha256(bytes)       -> a Promise of the 32-byte digest
//
// rao.broken names a broken version for the referees only (the
// RAO_WEB_BROKEN setting of the stand-in, tests/208), as the Lua modules
// read RAO_..._BROKEN.  In a browser nothing sets it, so it is "".

(function (global) {
    "use strict";
    var rao = global.rao || (global.rao = {});

    rao.broken = typeof global.RAO_WEB_BROKEN === "string" ? global.RAO_WEB_BROKEN : "";

    var encoder = new TextEncoder();
    var decoder = new TextDecoder("utf-8");

    // {{{ fromArray
    function fromArray(array) {
        var view = array instanceof Uint8Array ? array : new Uint8Array(array);
        var parts = [];
        // in pieces: String.fromCharCode takes its bytes as arguments
        for (var start = 0; start < view.length; start += 8192) {
            parts.push(String.fromCharCode.apply(null, view.subarray(start, start + 8192)));
        }
        return parts.join("");
    }
    // }}}

    // {{{ toArray
    function toArray(bytes) {
        var array = new Uint8Array(bytes.length);
        for (var i = 0; i < bytes.length; i++) {
            var code = bytes.charCodeAt(i);
            if (code > 255) { throw new Error("rao.bytes: a byte string holds only characters 0 to 255"); }
            array[i] = code;
        }
        return array;
    }
    // }}}

    // {{{ hex
    function hex(bytes) {
        var out = [];
        for (var i = 0; i < bytes.length; i++) {
            out.push((bytes.charCodeAt(i) + 256).toString(16).slice(1));
        }
        return out.join("");
    }
    // }}}

    // {{{ random
    function random(n) {
        var array = new Uint8Array(n);
        global.crypto.getRandomValues(array);
        return fromArray(array);
    }
    // }}}

    // {{{ sha256
    function sha256(bytes) {
        return global.crypto.subtle.digest("SHA-256", toArray(bytes)).then(fromArray);
    }
    // }}}

    // {{{ cryptoMissing
    // -> the words to show when this browser gives the page no WebCrypto,
    // or "" when it does.  A browser gives crypto.subtle only to a page it
    // counts as a "secure context": one opened from a file on this
    // computer, or from localhost, or over HTTPS (401 decision 1).
    function cryptoMissing() {
        if (global.crypto && global.crypto.subtle && global.crypto.getRandomValues) { return ""; }
        return "This browser gives this page no WebCrypto, so it cannot seal or open anything.  "
            + "Browsers give it only to pages they count as secure: open the page from a copy of "
            + "its folder on this computer (a file), not from an address on the network.";
    }
    // }}}

    rao.bytes = {
        fromText: function (text) { return fromArray(encoder.encode(text)); },
        toText: function (bytes) { return decoder.decode(toArray(bytes)); },
        toArray: toArray,
        fromArray: fromArray,
        hex: hex,
        random: random,
        sha256: sha256,
        cryptoMissing: cryptoMissing
    };
})(globalThis);
