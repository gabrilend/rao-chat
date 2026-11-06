// 210-sealing.js - sealing a record into a device frame, and opening one,
// in the browser's own WebCrypto (issue 402): 123's key and tying value,
// 124's frame.  The home does the same with libcrypto; the two must agree
// to the byte, and 402's referees hold them to it.
//
// The key (123): SHA-256 of the token's bytes exactly as typed (UTF-8),
// nothing trimmed or normalised; a token that is empty or holds a line
// break is refused, never cut.  The tying value: SHA-256 of the key, 32
// bytes, which begins every sealed body (201a).
//
// A frame, outside to inside (124):
//
//   length       4 bytes, big-endian: how many bytes follow (nonce +
//                sealed body + check value), at least 28, at most CAP
//   nonce        12 bytes from crypto.getRandomValues, new for every frame
//                (R1: every device seals with its key on its own, so only
//                random nonces are safe)
//   sealed body  AES-256-GCM: the tying value, the record (one line), then
//                padding: "\n" and zero bytes up to the next power of two,
//                at least 256 bytes (124's PADDING; 402 decision 1: the
//                page's frames are the sizes a phone's are)
//   check value  16 bytes: GCM's tag (WebCrypto puts it after the sealed
//                body, which is exactly where the frame has it)
//
// Opening gives the record or nothing (R2): WebCrypto refuses a body whose
// check value does not match and returns no plaintext at all; then the
// tying value must be this key's, and padding must be "\n" and zeros.
//
//   rao.sealing.keyPair(token)        -> Promise of {key, tie} (token: text)
//   rao.sealing.seal(pair, record)    -> Promise of the whole frame (bytes)
//   rao.sealing.open(pair, afterLength) -> Promise of {record} or {why}
//   rao.sealing.lengthOf(first4)      -> what follows, or -1 if no frame's
//   rao.sealing.paddedSize(n)         -> the size a body of n bytes is padded to

(function (rao) {
    "use strict";
    var bytes = rao.bytes;

    var NONCE_BYTES = 12;
    var TAG_BYTES = 16;
    var TIE_BYTES = 32;
    var MIN_LENGTH = NONCE_BYTES + TAG_BYTES;     // 28: an empty body
    var CAP = 1024 * 1024;                       // 124's cap, the largest length
    var BODY_MAX = CAP - MIN_LENGTH;
    var PAD_FLOOR = 256;

    // {{{ checkToken
    // 007's check_token: any non-empty text on one line.
    function checkToken(token) {
        if (typeof token !== "string" || token === "") {
            throw new Error("a token must be non-empty text");
        }
        if (/[\r\n]/.test(token)) {
            throw new Error("a token may hold any characters but a line break");
        }
    }
    // }}}

    // {{{ keyPair
    // token (text, as typed) -> Promise of { key: a CryptoKey for
    // AES-256-GCM, tie: 32 bytes }.  The key's bytes never leave this
    // function: WebCrypto holds them, not marked extractable.
    function keyPair(token) {
        checkToken(token);
        return bytes.sha256(bytes.fromText(token)).then(function (raw) {
            return Promise.all([
                globalThis.crypto.subtle.importKey("raw", bytes.toArray(raw), { name: "AES-GCM" }, false,
                    ["encrypt", "decrypt"]),
                bytes.sha256(raw)
            ]);
        }).then(function (both) {
            return { key: both[0], tie: both[1] };
        });
    }
    // }}}

    // {{{ paddedSize
    // the size a sealed body of `needed` bytes is padded to (124)
    function paddedSize(needed) {
        if (needed > BODY_MAX) {
            throw new Error("a body of " + needed + " bytes is over the cap (" + BODY_MAX + ")");
        }
        var size = PAD_FLOOR;
        while (size < needed) { size = size * 2; }
        return Math.min(size, BODY_MAX);
    }
    // }}}

    // {{{ uint32 / lengthOf
    function uint32(n) {
        return String.fromCharCode((n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255);
    }
    // the frame's first 4 bytes -> how many follow, or -1 when that is no
    // length 124 accepts (R3: refused before anything else is read)
    function lengthOf(first4) {
        if (typeof first4 !== "string" || first4.length !== 4) { return -1; }
        var n = ((first4.charCodeAt(0) * 256 + first4.charCodeAt(1)) * 256 + first4.charCodeAt(2)) * 256
            + first4.charCodeAt(3);
        return n < MIN_LENGTH || n > CAP ? -1 : n;
    }
    // }}}

    // {{{ seal
    // pair, record (one line of bytes, no "\n"), options ({pad: false} to
    // leave the body unpadded) -> Promise of the whole frame, length first.
    function seal(pair, record, options) {
        if (typeof record !== "string" || record.indexOf("\n") >= 0) {
            return Promise.reject(new Error("a record is one line (the log's escaping keeps \\n out of it)"));
        }
        var body = pair.tie + record;
        if (body.length > BODY_MAX) {
            return Promise.reject(new Error("a record of " + record.length + " bytes does not fit under the cap"));
        }
        var pad = !(options && options.pad === false);
        if (pad) {
            var size = paddedSize(body.length);
            if (size > body.length) { body = body + "\n" + new Array(size - body.length).join("\0"); }
        }
        var nonce = bytes.random(NONCE_BYTES);
        return globalThis.crypto.subtle.encrypt({ name: "AES-GCM", iv: bytes.toArray(nonce), tagLength: 128 },
            pair.key, bytes.toArray(body)).then(function (sealed) {
            var afterLength = nonce + bytes.fromArray(sealed);
            return uint32(afterLength.length) + afterLength;
        });
    }
    // }}}

    // {{{ open
    // pair, the frame without its 4 length bytes -> Promise of {record}, or
    // {why} when it is not a frame under this pair.  Never rejects.
    function open(pair, afterLength) {
        if (typeof afterLength !== "string" || afterLength.length < MIN_LENGTH || afterLength.length > CAP) {
            return Promise.resolve({ why: "not a frame's length" });
        }
        var nonce = afterLength.slice(0, NONCE_BYTES);
        var sealed = afterLength.slice(NONCE_BYTES);
        return globalThis.crypto.subtle.decrypt({ name: "AES-GCM", iv: bytes.toArray(nonce), tagLength: 128 },
            pair.key, bytes.toArray(sealed)).then(function (plain) {
            var body = bytes.fromArray(plain);
            // the tying value (201a; 124 explains why 32 bytes are enough)
            if (body.slice(0, TIE_BYTES) !== pair.tie && rao.broken !== "no-tie-check") {
                return { why: "the tying value is another token's" };
            }
            var rest = body.slice(TIE_BYTES);
            var stop = rest.indexOf("\n");
            if (stop < 0) { return { record: rest }; }
            if (/[^\0]/.test(rest.slice(stop + 1))) { return { why: "the padding is not zero bytes" }; }
            return { record: rest.slice(0, stop) };
        }, function () {
            return { why: "the check value does not match" };
        });
    }
    // }}}

    rao.sealing = {
        checkToken: checkToken,
        keyPair: keyPair,
        seal: seal,
        open: open,
        lengthOf: lengthOf,
        paddedSize: paddedSize,
        NONCE_BYTES: NONCE_BYTES,
        TAG_BYTES: TAG_BYTES,
        MIN_LENGTH: MIN_LENGTH,
        CAP: CAP,
        BODY_MAX: BODY_MAX,
        PAD_FLOOR: PAD_FLOOR
    };
})(globalThis.rao);
