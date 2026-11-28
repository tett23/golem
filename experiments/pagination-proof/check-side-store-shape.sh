#!/bin/sh
# Keep the model's association-store boundary tied to the production call.
set -eu
root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
source=${1:-$root/modules/golem-typeset/src/Golem/Typeset/Flow.hs}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
grep -F 'import Data.Map.Strict qualified as Map' "$source" >/dev/null
awk '
  /^buildFlow inp geom fonts images prev assumed = do$/ { body = 1 }
  body && /^  besides <- / { capture = 1 }
  capture && /^  -- 2\./ { exit }
  capture { sub(/--.*/, ""); print }
' "$source" | tr -d '[:space:]' >"$tmp/observed"
cat <<'EXPECTED' | tr -d '[:space:]' >"$tmp/expected"
besides <- Map.fromList . concat <$> mapper (\(i, pf) -> maybe (composeBeside fe widths unitAt i pf) pure (reusedBeside i)) jobs
EXPECTED
diff -u "$tmp/expected" "$tmp/observed"
