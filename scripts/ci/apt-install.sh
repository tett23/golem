#!/bin/sh
# Installs Debian packages on a CI runner, without the recommended packages
# and without updating the index of man-db (docs/adr/0009-ci-speed.md). The
# build job runs it in the background with scripts/ci/bg.sh
# (docs/adr/0037-ci-build-job-speedup.md). A stalled download is dropped in
# 30 seconds and fetched again, up to 3 times, instead of using up the 5
# minutes the build job gives it
# (docs/adr/0062-epubcheck-from-release-with-cache.md).
#
#   apt-install.sh PACKAGE...
set -eu
[ $# -ge 1 ] || { echo "usage: apt-install.sh PACKAGE..." >&2; exit 2; }
echo 'man-db man-db/auto-update boolean false' | sudo debconf-set-selections
sudo apt-get -o Acquire::http::Timeout=30 -o Acquire::Retries=3 update
sudo apt-get -o Acquire::http::Timeout=30 -o Acquire::Retries=3 install -y --no-install-recommends "$@"
