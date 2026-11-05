# 141-claims.lua

The claims a home has made (a hello: "I am at this pair"; a leave: "I have
left") and its answer when asked about one (issue 204, steps 1 and 2).
`make` writes a line to the room's `claims` file and returns a new claim
id of 32 hex characters. `answer` says `yes` only if that file holds the
id stating the pair asked about, and `no` otherwise. Answering only reads
the file, so a restart forgets nothing and a replayed question gets the
same answer.
