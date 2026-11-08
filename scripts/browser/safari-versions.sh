#!/bin/sh
# The versions under which the safari job of .github/workflows/browser.yml
# checks, as a Markdown table for $GITHUB_STEP_SUMMARY (docs/adr/0234
# section 6, I7). Safari is not pinned: it is the one of the image of the
# macOS runner, and when the job fails, this table is compared with that of
# the last run that passed.
#
#   safari-versions.sh [BROWSER_VERSION]
#
# The rows: the version and the build of macOS (sw_vers), ImageOS and
# ImageVersion of the runner, CFBundleShortVersionString and CFBundleVersion
# of the Info.plist of Safari (read with plutil), and BROWSER_VERSION, the
# browserVersion of the WebDriver session, when it is given and not empty
# (the session may not have been made). A value that cannot be read is -;
# the table is written whatever fails. SW_VERS chooses the sw_vers to run
# and SAFARI_PLIST the Info.plist (for the tests).
set -u
SW_VERS=${SW_VERS:-sw_vers}
PLIST=${SAFARI_PLIST:-/Applications/Safari.app/Contents/Info.plist}
or_dash() { if [ -n "$1" ]; then printf '%s' "$1"; else printf -- '-'; fi; }
plist() { plutil -extract "$1" raw -o - "$PLIST" 2>/dev/null || true; }
echo '| What | Version |'
echo '| --- | --- |'
echo "| macOS | $(or_dash "$("$SW_VERS" -productVersion 2>/dev/null || true)") |"
echo "| macOS build | $(or_dash "$("$SW_VERS" -buildVersion 2>/dev/null || true)") |"
echo "| ImageOS | $(or_dash "${ImageOS:-}") |"
echo "| ImageVersion | $(or_dash "${ImageVersion:-}") |"
echo "| Safari CFBundleShortVersionString | $(or_dash "$(plist CFBundleShortVersionString)") |"
echo "| Safari CFBundleVersion | $(or_dash "$(plist CFBundleVersion)") |"
if [ -n "${1:-}" ]; then echo "| WebDriver browserVersion | $1 |"; fi
