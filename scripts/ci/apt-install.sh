#!/bin/sh
# Installs Debian packages on a CI runner, without the recommended packages
# and without updating the index of man-db (docs/adr/0009-ci-speed.md). The
# build job runs it in the background with scripts/ci/bg.sh
# (docs/adr/0037-ci-build-job-speedup.md).
#
#   apt-install.sh PACKAGE...
set -eu
[ $# -ge 1 ] || { echo "usage: apt-install.sh PACKAGE..." >&2; exit 2; }
echo 'man-db man-db/auto-update boolean false' | sudo debconf-set-selections
sudo apt-get update
sudo apt-get install -y --no-install-recommends "$@"
