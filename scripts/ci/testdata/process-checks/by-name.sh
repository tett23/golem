#!/bin/sh
# a fake test that looks for a process by its command line over the whole
# machine: the check of docs/adr/0303 section 4 fails on line 5
sleep 300 &
if pgrep -f "sleep 300" >/dev/null 2>&1; then echo FAIL; fi
