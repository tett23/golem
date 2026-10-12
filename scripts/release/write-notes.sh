#!/bin/sh
# Writes the release notes for TAG to OUT (docs/adr/0004-binary-distribution-and-release.md).
# Claude Code writes them from the list of notes.sh, the pull requests
# (gh pr view) and the ADRs added in the range; check-notes.sh checks
# them. When the AI or the check fails, the notes are the list of
# notes.sh as it is, and the reason goes to $GITHUB_STEP_SUMMARY. The
# release is not stopped.
#
#   write-notes.sh TAG OUT
#
# Environment: CLAUDE_MODEL (the model, fixed in the workflow),
# ANTHROPIC_API_KEY, GH_TOKEN. Run it in the repository with the history
# and the tags.
set -eu
[ $# -eq 2 ] || {
  echo "usage: write-notes.sh TAG OUT" >&2
  exit 2
}
TAG=$1
OUT=$2
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/stderr}

PREVIOUS=$(git describe --tags --abbrev=0 --match 'v*' "$TAG^" 2>/dev/null || true)
sh "$HERE/notes.sh" "$PREVIOUS" "$TAG" >"$WORK/list.md"

fallback() {
  cp "$WORK/list.md" "$OUT"
  printf '### Release notes\n\nThe notes are the list of notes.sh: %s\n' "$1" >>"$SUMMARY"
  exit 0
}

{
  cat <<'EOF'
Write the release notes of Golem, a typesetting system, for the GitHub release named below.

Rules (CONTRIBUTING.md, "Tags and releases"):
- Write in English, in GitHub Markdown. Output only the notes, with no preamble.
- Group the changes under the headings "## Added", "## Changed", "## Removed" and "## Fixed". Leave out a heading with no changes, and add another heading only when a change fits none of them.
- Classify every pull request of the "## Unsorted" list into those headings, reading its description and the ADRs. Do not leave a "## Unsorted" section.
- Write one item per change, in a sentence for the users of golem. Link each item to its pull request and, when there is one, to its ADR, with the absolute links given in the list (https://github.com/tett23/golem/...). Never write a relative link nor a bare "#123".
- Keep the "## Verifying the downloads" section of the list as it is, at the end.

EOF
  printf 'The release: %s\n\n# The list of changes (notes.sh)\n\n' "$TAG"
  cat "$WORK/list.md"
  printf '\n# The pull requests\n'
  for n in $(grep -Eo 'https://github.com/tett23/golem/pull/[0-9]+' "$WORK/list.md" | sed 's#.*/##' | sort -un); do
    printf '\n## Pull request #%s\n\n' "$n"
    gh pr view "$n" --json title,body --template '{{.title}}{{"\n\n"}}{{.body}}{{"\n"}}' || printf '(not available)\n'
  done
  printf '\n# The ADRs added in this release\n'
  if [ -n "$PREVIOUS" ]; then BASE=$PREVIOUS; else BASE=$(git hash-object -t tree /dev/null); fi
  git diff --name-only --diff-filter=A "$BASE" "$TAG" | grep -E '^docs/([^/]+/)?adr/[^/]+\.md$' | LC_ALL=C sort |
    while read -r path; do
      printf '\n## %s (https://github.com/tett23/golem/blob/%s/%s)\n\n' "$path" "$TAG" "$path"
      git show "$TAG:$path"
    done
} >"$WORK/prompt.md"

[ -n "${CLAUDE_MODEL:-}" ] || fallback "CLAUDE_MODEL is not set"
[ -n "${ANTHROPIC_API_KEY:-}" ] || fallback "ANTHROPIC_API_KEY is not set"
command -v claude >/dev/null 2>&1 || fallback "Claude Code is not installed"
if ! claude -p --model "$CLAUDE_MODEL" "Write the release notes as the input says." <"$WORK/prompt.md" >"$WORK/ai.md" 2>"$WORK/ai.err"; then
  fallback "Claude Code failed: $(head -c 500 "$WORK/ai.err")"
fi
if ! sh "$HERE/check-notes.sh" "$WORK/ai.md" "$WORK/list.md" 2>"$WORK/check.err"; then
  fallback "the AI's notes did not pass check-notes.sh: $(cat "$WORK/check.err")"
fi
cp "$WORK/ai.md" "$OUT"
printf '### Release notes\n\nClaude Code (%s) wrote the notes, and they passed check-notes.sh.\n' "$CLAUDE_MODEL" >>"$SUMMARY"
