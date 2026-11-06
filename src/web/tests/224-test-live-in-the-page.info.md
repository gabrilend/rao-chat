# 224-test-live-in-the-page.lua

Issue 407's referees: a message filed on the home reaches the live page
within two seconds; pings keep it connected past three idle limits
(broken: `no-keep-alive`); after the home stops and starts the page comes
back by itself, gets what was filed meanwhile and waits 5 s after its
next drop (broken: `no-retry`); the waits and countdown; the home's
problem lines in the strip, as 183's `problems`; the page and a phone
(190) live together hear each other.  Run under the loopback-only wrapper
(127.0.0.2, port 46407): `luajit src/web/tests/224-test-live-in-the-page.lua [project]`.
