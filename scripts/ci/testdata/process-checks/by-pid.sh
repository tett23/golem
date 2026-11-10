#!/bin/sh
# a fake test that checks only the processes it started, by their PIDs: the
# check of docs/adr/0303 section 4 passes it
sleep 300 &
pid=$!
if pgrep -P "$$" | grep -qxF "$pid"; then echo listed; fi
kill "$pid"
if kill -0 "$pid" 2>/dev/null; then echo FAIL; fi
