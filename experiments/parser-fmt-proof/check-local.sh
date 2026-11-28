#!/bin/sh
# Full local checks. Native observers are deliberately outside the CI glob.
set -eu
cd "$(dirname "$0")/../.."
result=0
node --test experiments/parser-fmt-proof/native-runner.test.mjs || result=1
node experiments/parser-fmt-proof/grammar/test.mjs || result=1
node experiments/parser-fmt-proof/native-runner.mjs || result=1
sh experiments/parser-fmt-proof/check-suite.sh arguments 2 1 || result=1
exit "$result"
