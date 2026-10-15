#!/bin/sh
# Fetches the fonts of the manual and their licences into manual/fonts and
# checks their SHA-256 (docs/adr/0022-manual-as-typesetting-sample.md).
# The URLs name tagged releases, as golem new does (golem-cli ADR 0003).
# All six fonts are under the SIL Open Font License 1.1; Source Code Pro
# and Noto Sans JP Regular set code (golem-driver ADR 0017, docs/adr/0024).
#
#   fetch-fonts.sh [DIR]    DIR is manual/fonts by default
#
# A file that is already there is only checked. A file whose SHA-256 does
# not match is removed, and the exit code is 1; run it again to fetch it.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DEST=${1:-$HERE/../../manual/fonts}
NOTO_SERIF=https://raw.githubusercontent.com/notofonts/noto-cjk/Serif2.003
NOTO_SANS=https://raw.githubusercontent.com/notofonts/noto-cjk/Sans2.004
SOURCE_SERIF=https://raw.githubusercontent.com/adobe-fonts/source-serif/4.005R
SOURCE_SANS=https://raw.githubusercontent.com/adobe-fonts/source-sans/3.052R
SOURCE_CODE=https://raw.githubusercontent.com/adobe-fonts/source-code-pro/2.042R-u/1.062R-i/1.026R-vf
# file, SHA-256, URL
FILES="
NotoSerifJP-Regular.otf 2c9a12dbd4f2408c4610c7ee84a108b62d7236c3775baed618c64d9cb44b2f04 $NOTO_SERIF/Serif/SubsetOTF/JP/NotoSerifJP-Regular.otf
LICENSE-NotoSerifJP.txt 6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2 $NOTO_SERIF/Serif/LICENSE
NotoSansJP-Bold.otf 1b0edfb500b73a4fa8a4fcaae1bbbd403994e08e73e3e0da37e70d3853f42c5f $NOTO_SANS/Sans/SubsetOTF/JP/NotoSansJP-Bold.otf
NotoSansJP-Regular.otf dff723ba59d57d136764a04b9b2d03205544f7cd785a711442d6d2d085ac5073 $NOTO_SANS/Sans/SubsetOTF/JP/NotoSansJP-Regular.otf
LICENSE-NotoSansJP.txt 6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2 $NOTO_SANS/LICENSE
SourceSerif4-Regular.otf edf160d0d584deee8a3bb2c3371b2a7624ca63580fbe02c57c1f4c91e84d8787 $SOURCE_SERIF/OTF/SourceSerif4-Regular.otf
LICENSE-SourceSerif4.md 75784a295293a8992f5a8d99210566e0064a012e6dab6731305e3787f15896c7 $SOURCE_SERIF/LICENSE.md
SourceSans3-Bold.otf 7776ddb9f3eb58683e59f28d558d8896b768c2d0c80799fb3f1c56c54dfd98c9 $SOURCE_SANS/OTF/SourceSans3-Bold.otf
LICENSE-SourceSans3.md 89ad2c4f66dd29127527493e729c31e731f111cf10faf5774c3db9275ed0c22c $SOURCE_SANS/LICENSE.md
SourceCodePro-Regular.otf 9f9664e2edf6f045c11e774f9bd0be6993971f2544a39061a5ce478b96b051f8 $SOURCE_CODE/OTF/SourceCodePro-Regular.otf
LICENSE-SourceCodePro.md 7c940e28a5388e9bba866cf0e408edda45fe0899ba98665b8f6ab31dc5e4b8ff $SOURCE_CODE/LICENSE.md
"
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
mkdir -p "$DEST"

# the files that are there first, so that a broken file stops it before
# anything is fetched
BAD=
for name_sha in $(printf '%s\n' "$FILES" | awk 'NF { print $1 "=" $2 }'); do
  name=${name_sha%%=*} sha=${name_sha#*=}
  [ -e "$DEST/$name" ] || continue
  if [ "$(sha256 "$DEST/$name")" != "$sha" ]; then
    echo "fetch-fonts: the SHA-256 of $DEST/$name does not match; removed it" >&2
    rm -f "$DEST/$name"
    BAD=1
  fi
done
[ -z "$BAD" ] || { echo "fetch-fonts: run it again to fetch the removed files" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
printf '%s\n' "$FILES" | while read -r name sha url; do
  [ -n "$name" ] || continue
  [ ! -e "$DEST/$name" ] || continue
  curl -sSfL --retry 3 -o "$TMP/$name" "$url" || { echo "fetch-fonts: could not fetch $url" >&2; exit 1; }
  actual=$(sha256 "$TMP/$name")
  if [ "$actual" != "$sha" ]; then
    echo "fetch-fonts: the SHA-256 of $url is $actual, not $sha" >&2
    exit 1
  fi
  mv "$TMP/$name" "$DEST/$name"
done
