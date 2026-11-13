#!/bin/sh
# Compare the rc4 CLI with the v1 candidate on the same ADR 0344 fixtures.
# Usage: sh scripts/compat/adr0344.sh /absolute/path/to/rc4/golem /absolute/path/to/candidate/golem
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 RC4_GOLEM CANDIDATE_GOLEM" >&2
  exit 2
fi
case "$1:$2" in
  /*:/*) ;;
  *) echo "both executable paths must be absolute" >&2; exit 2 ;;
esac
rc4_bin=$1
candidate_bin=$2
"$rc4_bin" --version | grep -Fq '0.1.0-rc4' || { echo "the first executable is not rc4" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

repo_root=$(CDPATH= cd "$(dirname "$0")/../.." && pwd)
fixture="$repo_root/scripts/compat/adr0344"
font="$repo_root/modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf"
work=$(mktemp -d "${TMPDIR:-/tmp}/golem-adr0344.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
checks=0

check_one() {
  bin=$1 label=$2 expected_exit=$3 expected_diags=$4
  output="$case_dir/$label.json"
  if [ "$quiet" = yes ]; then
    if (cd "$case_dir" && "$bin" check --format json --no-notices > "$output" 2>&1); then actual_exit=0; else actual_exit=$?; fi
  else
    if (cd "$case_dir" && "$bin" check --format json > "$output" 2>&1); then actual_exit=0; else actual_exit=$?; fi
  fi
  actual_diags=$(jq -r '[.[] | "\(.code):\(.severity)@\(.span.file):\(.span.line)"] | join(",")' "$output") || {
    cat "$output" >&2
    exit 1
  }
  if [ "$actual_exit" -ne "$expected_exit" ] || [ "$actual_diags" != "$expected_diags" ]; then
    echo "$scenario $label: expected exit=$expected_exit diagnostics=$expected_diags; got exit=$actual_exit diagnostics=$actual_diags" >&2
    cat "$output" >&2
    exit 1
  fi
  checks=$((checks + 1))
}

for scenario in list_braces list_sample head_braces mark_size mark_conflict \
  suppress_G03114 suppress_G03115 suppress_G03116 suppress_G03117 \
  no_notices_list_braces no_notices_list_sample no_notices_head_braces no_notices_mark_size; do
  case_dir="$work/$scenario"
  mkdir -p "$case_dir/fonts"
  cp "$fixture/manifest.toml" "$fixture/style.toml" "$fixture/a.gm" "$case_dir/"
  cp "$font" "$case_dir/fonts/"
  quiet=no
  kind=$scenario
  case "$scenario" in
    no_notices_*) quiet=yes; kind=${scenario#no_notices_} ;;
  esac
  case "$kind" in
    list_braces)
      printf '\n[lists]\nnumbers = ["{{{n}}}"]\n' >> "$case_dir/style.toml"
      line=$(grep -nF 'numbers = ' "$case_dir/style.toml" | cut -d: -f1)
      old=G03114 new=G03250 ;;
    list_sample)
      printf '\n[lists]\nnumbers = ["{a}"]\n' >> "$case_dir/style.toml"
      line=$(grep -nF 'numbers = ' "$case_dir/style.toml" | cut -d: -f1)
      old=G03115 new=G03251 ;;
    head_braces)
      printf '\n[masters.body]\nrunning-head = { position = "top-outside", content = ["{{書名}}"] }\n' >> "$case_dir/style.toml"
      line=$(grep -nF 'running-head = ' "$case_dir/style.toml" | cut -d: -f1)
      old=G03116 new=G03252 ;;
    mark_size)
      printf '\n[notes]\nmark-size = "0.5zw"\n' >> "$case_dir/style.toml"
      line=$(grep -nF 'mark-size = ' "$case_dir/style.toml" | cut -d: -f1)
      old=G03117 new=G03253 ;;
    mark_conflict)
      printf '\n[character-styles.mark]\nsize = "0.5zw"\n\n[notes]\nmark-size = "0.5zw"\nmark-style = "mark"\n' >> "$case_dir/style.toml"
      line=$(grep -nF 'mark-size = ' "$case_dir/style.toml" | cut -d: -f1)
      old=G03006 new=G03253 ;;
    suppress_*)
      code=${kind#suppress_}
      printf '\n[diagnostics]\nsilence-notices = ["%s"]\n' "$code" >> "$case_dir/manifest.toml"
      line=$(grep -nF 'silence-notices = ' "$case_dir/manifest.toml" | cut -d: -f1)
      old= new=G03024 ;;
  esac
  case "$kind" in
    suppress_*) expected_old=; expected_new="$new:error@manifest.toml:$line"; old_exit=0 ;;
    mark_conflict) expected_old="$old:error@style.toml:$line"; expected_new="$new:error@style.toml:$line"; old_exit=1 ;;
    *) expected_old="$old:notice@style.toml:$line"; expected_new="$new:error@style.toml:$line"; old_exit=0 ;;
  esac
  if [ "$quiet" = yes ]; then expected_old=; fi
  check_one "$rc4_bin" rc4 "$old_exit" "$expected_old"
  check_one "$candidate_bin" candidate 1 "$expected_new"
done

echo "$checks checks passed (13 identical fixtures, 2 CLIs)"
