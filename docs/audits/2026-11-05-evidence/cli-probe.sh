#!/bin/sh
# The CLI probe of the 2026-11-05 security audit: CSL-JSON control
# characters in XHTML (V-03), an SVG with external references (V-02), and
# the guard against a symlinked output folder. Run from the repository
# root: sh docs/audits/2026-11-05-evidence/cli-probe.sh "$(cabal list-bin golem)"
# Works with the BSD and GNU tools; needs xmllint and unzip.
set -u

exe=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
repo=$(pwd)
base=$(mktemp -d "${TMPDIR:-/tmp}/golem-audit-20261105-XXXXXX")
p=$base/project
cp -R "$repo/modules/golem-driver/test/fixtures/bibliographies" "$p"

# run ARGS...: run golem in the project, print the command, exit status and
# standard error on one line, and keep standard error in $base/stderr
run() {
	(cd "$p" && "$exe" "$@") >/dev/null 2>"$base/stderr"
	status=$?
	printf 'command: %s exit: %s diagnostics: %s\n' "$*" "$status" "$(cat "$base/stderr")"
}

ctl=$(printf '\001')

# V-03: a control character in the title of the first reference
sed 's/"title": "日本語組版処理の要件"/"title": "audit-control-\\u0001"/' "$p/refs.json" >"$base/refs.json"
mv "$base/refs.json" "$p/refs.json"
run build --target html --target epub
find "$p/build/html" -name '*.xhtml' | LC_ALL=C sort | while read -r f; do
	if LC_ALL=C grep -q "$ctl" "$f"; then
		xmllint --noout "$f" >/dev/null 2>"$base/xmllint" ||
			printf 'invalid HTML: %s %s\n' "${f#"$p"/}" "$(head -n 1 "$base/xmllint" | sed "s|^$f:|line |")"
	fi
done
unzip -Z1 "$p/build/epub/book.epub" | LC_ALL=C sort | while read -r n; do
	case $n in
	*.xhtml)
		unzip -p "$p/build/epub/book.epub" "$n" | LC_ALL=C grep -q "$ctl" &&
			printf 'EPUB control byte: %s\n' "$n"
		;;
	esac
done
sed 's/"title": "audit-control-\\u0001"/"title": "safe"/' "$p/refs.json" >"$base/refs.json"
mv "$base/refs.json" "$p/refs.json"

# V-02: an SVG with an xml-stylesheet instruction and a url() in fill
printf '%s' '<?xml-stylesheet type="text/css" href="https://example.invalid/a.css"?><svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="url(https://example.invalid/a#g)"/></svg>' >"$p/test.svg"
printf '\n\n@figure test.svg alt="audit"\n' >>"$p/chapters/01.gm"
run build --target html
preserved=False
for f in $(find "$p/build/html" -name '*.svg'); do
	cmp -s "$f" "$p/test.svg" && preserved=True
done
printf 'SVG preserved: %s\n' "$preserved"

# the output guard: build is a symbolic link to a folder outside
rm -rf "$p/build"
mkdir "$base/outside"
printf 'unchanged' >"$base/outside/sentinel"
ln -s "$base/outside" "$p/build"
run build --target html
guard=False
grep -q G08013 "$base/stderr" && guard=True
printf 'output guard: %s sentinel: %s\n' "$guard" "$(cat "$base/outside/sentinel")"
printf 'artifacts: %s\n' "$base"
