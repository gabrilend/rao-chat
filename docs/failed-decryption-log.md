# The failed-decryption log

Issue 203.  Each mailbox writes one line for every frame that arrives on
its port and that no key it holds opens, and one line for every frame
refused for its announced length alone.  The file is read by fail2ban
first and by people second.  Its grammar is a contract with fail2ban,
written down here and only here.  `src/delivery/139-failed-decryption.lua`
writes and reads exactly this grammar, and `docs/fail2ban/` holds the
filter that matches it.

## Where

`<gatherer.ram-root>/<home>/<mailbox tag>/failed-decryption`: the
mailbox's RAM folder (issue 211).  It lives in RAM, so it is lost at a
reboot, and fail2ban needs only recent lines.  It is never committed or
pushed, because it is a list of addresses that tried this home.

The file is split by size, by 215a's rule.  A new file starts before a
write would carry the current one past `failed-decryption.file-size`
bytes (at least 1024).  The newest file keeps the name
`failed-decryption`.  When it is full it becomes `failed-decryption.1`,
`.1` becomes `.2`, and so on, and only `failed-decryption.files-kept`
files are kept in all.  Neither setting has a default.

## The line, version 1

One line per frame, fields separated by single spaces:

    <seconds> <stamp> rao-chat failed-decryption v1 from=<address> port=<port> to-port=<port> length=<length> reason=<reason>

| field | what it is |
|---|---|
| seconds | whole seconds since 1970, UTC |
| stamp | the same instant, ISO-8601 UTC, e.g. `2026-11-05T11:52:47Z` |
| `v1` | this grammar's version |
| from | the source address as the connection shows it: IPv4 or IPv6 text, never a looked-up name |
| port | the source port |
| to-port | this mailbox's listening port (already visible on the wire); never a room |
| length | the length the frame announced in its first 4 bytes |
| reason | `no-key`: the whole keyring was tried once and nothing opened the frame. `length`: the announced length was under 28 or over the cap (1 MiB), and only those 4 bytes were read |

Example:

    1793878367 2026-11-05T11:52:47Z rao-chat failed-decryption v1 from=127.0.0.3 port=5555 to-port=7501 length=40 reason=no-key

Nothing in a line comes from the frame's contents except its announced
length, which is a number, so a sender cannot write text into the log.
There is one line per frame, never one per key tried.  A frame that opens
is never written here, even if it is then refused (an ignored address).

A change to this grammar is a new version (`v2`), and every home that
uses fail2ban then needs the new filter.

## fail2ban

Copy `docs/fail2ban/rao-chat-failed-decryption.conf` to
`/etc/fail2ban/filter.d/`.  Then add a jail like
`docs/fail2ban/jail-example.local`, with the path pattern changed to your
`gatherer.ram-root`.  fail2ban expands a path's pattern when the jail
starts, so a mailbox added later needs `fail2ban-client reload`.  That is
also why the newest file always has the same name.

rao-chat builds no flood defence of its own beyond this log.  Blocking is
left to the firewall and to the internet provider.
