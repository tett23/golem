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
HERE=$(cd "$(dirname "$0")" && pwd)

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
# Two shapes of merge commits: GitHub writes "Merge pull request #N from
# OWNER/BRANCH" with the title of the pull request as the first line of
# the body; a merge by hand writes "Merge pull request #N: TITLE". Each
# commit starts with a line holding the record separator (\036), then the
# subject, then the body. C locale: macOS awk stops at bytes that are not
# UTF-8.
git log --first-parent --merges --reverse --format='%x1e%n%s%n%b' "$RANGE" |
  LC_ALL=C awk -v url="$REPO_URL" '
    function flush() {
      if (n != "") printf "- %s ([#%s](%s/pull/%s))\n", (title != "" ? title : subject), n, url, n
      n = ""
    }
    $0 == "\036" { flush(); line = 0; next }
    { line++ }
    line == 1 {
      subject = $0; title = ""
      if (match($0, /^Merge pull request #[0-9]+ from [^ ]+$/)) {
        n = substr($0, 21); sub(/ .*/, "", n); subject = substr($0, index($0, " from ") + 6)
      } else if (match($0, /^Merge pull request #[0-9]+: /)) {
        n = substr($0, 21, RLENGTH - 22); title = substr($0, RLENGTH + 1)
      }
      next
    }
    line > 1 && n != "" && title == "" && $0 != "" { title = $0 }
    END { flush() }'

printf '\n## ADRs\n\n'
git diff --name-only --diff-filter=A "$BASE" "$TAG" |
  grep -E '^docs/([^/]+/)?adr/[^/]+\.md$' |
  LC_ALL=C sort |
  sed "s|.*|- [&]($REPO_URL/blob/$TAG/&)|" || true

# The ADRs changed in the range whose status line (the first line that
# starts with "ステータス:") differs between the two tags
# (docs/adr/0246-bound-the-prompt-of-the-release-notes.md). The first
# release has no changed ADR. The relative links of a status line become
# absolute, at the tag of the line (docs/adr/0259).
status_line() { # status_line REV PATH: the status line of PATH at REV
  git show "$1:$2" | LC_ALL=C awk '/^ステータス:/ { print; exit }'
}
status_of() { # status_of LINE: the status, without the spaces around it
  printf '%s\n' "$1" | LC_ALL=C sed 's/^ステータス://; s/^[[:space:]]*//; s/[[:space:]]*$//'
}
CHANGED=
if [ -n "$PREVIOUS" ]; then
  CHANGED=$(git diff --name-only --diff-filter=M "$PREVIOUS" "$TAG" |
    grep -E '^docs/([^/]+/)?adr/[^/]+\.md$' |
    LC_ALL=C sort |
    while read -r path; do
      before=$(status_line "$PREVIOUS" "$path")
      after=$(status_line "$TAG" "$path")
      [ "$before" != "$after" ] || continue
      printf -- '- [%s](%s/blob/%s/%s): %s → %s\n' "$path" "$REPO_URL" "$TAG" "$path" \
        "$(status_of "$before" | sh "$HERE/absolute-links.sh" "$PREVIOUS" "$path")" \
        "$(status_of "$after" | sh "$HERE/absolute-links.sh" "$TAG" "$path")"
    done)
fi
printf '\n## ADRs whose status changed\n'
[ -z "$CHANGED" ] || printf '\n%s\n' "$CHANGED"

cat <<EOF

## Verifying the downloads

\`SHA256SUMS\` lists the SHA-256 of every archive.
Check the archives you downloaded:

\`\`\`sh
sha256sum --ignore-missing -c SHA256SUMS
\`\`\`

On macOS, use \`shasum -a 256 --ignore-missing -c SHA256SUMS\`.

Each \`golem-*.tar.gz\` archive has a build provenance attestation.
The manuals, the sample plugins (\`.wasm\`) and the GMP source have none; check them with \`SHA256SUMS\` only.
Check an archive with the GitHub CLI:

\`\`\`sh
gh attestation verify golem-$TAG-x86_64-linux.tar.gz --repo tett23/golem
\`\`\`
EOF
