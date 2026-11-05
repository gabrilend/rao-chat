# 164-home-starter.lua

One small process per home (issue 211): starts a gatherer (163) per
mailbox, starts again one that is gone and says so in the home's running
log, waiting longer each time one dies within 5 s (up to 60 s).  It runs
212's public-address recheck, the one home-wide task; a first confirmed
address or a move restarts the gatherers so each sends fresh hellos.  A
`stop` file in the home's RAM folder stops every gatherer, then it.
