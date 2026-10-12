#!/bin/sh
# Writes the list of changes for a release, in English Markdown, to stdout
# (docs/adr/0004-binary-distribution-and-release.md). It is the material
# for the release notes, and the notes themselves when the AI fails.
#
#   notes.sh TAG             from the previous v* tag (or the first commit)
#   notes.sh PREVIOUS TAG    from PREVIOUS; an empty PREVIOUS means the first commit
#
# Run it in the repository.
set -eu
REPO_URL=https://github.com/tett23/golem

case $# in
  1)
    TAG=$1
    PREVIOUS=$(git describe --tags --abbrev=0 --match 'v*' "$TAG^" 2>/dev/null || true)
    ;;
  2)
    PREVIOUS=$1
    TAG=$2
    ;;
  *)
    echo "usage: notes.sh [PREVIOUS] TAG" >&2
    exit 2
    ;;
esac
git rev-parse --verify --quiet "$TAG^{commit}" >/dev/null || {
  echo "notes: no such tag: $TAG" >&2
  exit 1
}

if [ -n "$PREVIOUS" ]; then
  RANGE="$PREVIOUS..$TAG"
  BASE=$PREVIOUS
else
  # from the first commit: everything reachable from TAG, and the files
  # added since the empty tree
  RANGE=$TAG
  BASE=$(git hash-object -t tree /dev/null)
fi

printf '## Added\n\n## Changed\n\n## Removed\n\n## Fixed\n\n## Unsorted\n\n'
git log --first-parent --merges --reverse --format='%s' "$RANGE" |
  sed -n "s|^Merge pull request #\([0-9][0-9]*\): \(.*\)\$|- \2 ([#\1]($REPO_URL/pull/\1))|p"

printf '\n## ADRs\n\n'
git diff --name-only --diff-filter=A "$BASE" "$TAG" |
  grep -E '^docs/([^/]+/)?adr/[^/]+\.md$' |
  LC_ALL=C sort |
  sed "s|.*|- [&]($REPO_URL/blob/$TAG/&)|" || true

cat <<EOF

## Verifying the downloads

\`SHA256SUMS\` lists the SHA-256 of every archive.
Check the archives you downloaded:

\`\`\`sh
sha256sum --ignore-missing -c SHA256SUMS
\`\`\`

On macOS, use \`shasum -a 256 --ignore-missing -c SHA256SUMS\`.

Each archive has a build provenance attestation.
Check it with the GitHub CLI:

\`\`\`sh
gh attestation verify golem-$TAG-x86_64-linux.tar.gz --repo tett23/golem
\`\`\`
EOF
