#!/bin/sh
# Maps the static archives that the linker put into golem to the components
# whose license documents THIRD_PARTY_LICENSES/ holds
# (docs/adr/0007-third-party-licenses.md).
#
#   link-components.sh MAP          one line per component:
#                                   component<TAB>archive<TAB>archive...
#   link-components.sh MAP --apk    one line per archive of an Alpine package:
#                                   origin<TAB>package<TAB>version<TAB>license<TAB>archive
#
# MAP is the link map of GNU ld (-Map) or of ld64 (-map); the first line
# tells which. The rules, the first that applies:
#
#   libHSrts*.a under the libdir of GHC          ghc
#   libHS<name>-<version>-*.a                    haskell
#   libgmp.a                                     gmp
#   third_party/wasmtime/lib/libwasmtime.a       wasmtime
#   a file of a package in APK_DB (Alpine)       apk:<origin>
#   libclang_rt.*.a of Xcode (ld64)              compiler-rt
#
# The components come in the order their archives first appear in the
# map, so the output is fixed by the map. An archive no rule applies to is an
# error: its path goes to stderr and the exit code is 1.
#
# Environment:
#   GHC_LIBDIR  the libdir of GHC (default: ghc-9.10.3 --print-libdir or ghc --print-libdir)
#   APK_DB      the installed database of apk (default: /lib/apk/db/installed)
#   APK_ROOT    the root the paths in APK_DB are relative to (default: /)
set -eu

fail() {
  printf 'link-components: %s\n' "$*" >&2
  exit 1
}

[ $# -ge 1 ] && [ $# -le 2 ] && { [ $# -eq 1 ] || [ "$2" = --apk ]; } || {
  echo "usage: link-components.sh MAP [--apk]" >&2
  exit 2
}
MAP=$1
MODE=${2:-}
[ -f "$MAP" ] || fail "no such file: $MAP"
APK_DB=${APK_DB:-/lib/apk/db/installed}
APK_ROOT=${APK_ROOT:-/}
if [ -z "${GHC_LIBDIR:-}" ]; then
  if command -v ghc-9.10.3 >/dev/null 2>&1; then
    GHC_LIBDIR=$(ghc-9.10.3 --print-libdir)
  elif command -v ghc >/dev/null 2>&1; then
    GHC_LIBDIR=$(ghc --print-libdir)
  else
    fail "GHC_LIBDIR is needed (no ghc on PATH)"
  fi
fi

# resolve PATH: the path with its symbolic links resolved, or PATH itself
# when it does not exist
resolve() {
  if [ -e "$1" ]; then
    readlink -f "$1" 2>/dev/null || realpath "$1" 2>/dev/null || printf '%s\n' "$1"
  else
    printf '%s\n' "$1"
  fi
}

TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT

# the archives in the map, once each, in the order they first appear
FIRST=$(head -n 1 "$MAP")
case "$FIRST" in
  '# Path: '*)
    FORMAT=ld64
    awk '
      /^# Object files:/ { on = 1; next }
      /^# / { on = 0 }
      on && /^\[ *[0-9]+\] / {
        sub(/^\[ *[0-9]+\] /, "")
        if (match($0, /\.a(\[[0-9]+\])?\(/)) {
          a = substr($0, 1, RSTART + 1)
          if (!(a in seen)) { seen[a] = 1; print a }
        }
      }' "$MAP" >"$TMP/archives"
    ;;
  'Archive member included to satisfy reference by file (symbol)' | 'Allocating common symbols' | \
    'Discarded input sections' | 'Memory Configuration' | 'As-needed library included to satisfy reference by file (symbol)')
    FORMAT=gnu
    awk '
      /^Archive member included to satisfy reference by file \(symbol\)$/ { on = 1; next }
      /^(Allocating common symbols|Discarded input sections|Memory Configuration|As-needed library included|Linker script and memory map)/ { on = 0 }
      on && /^[^ \t]/ {
        if (match($0, /\.a\(/)) {
          a = substr($0, 1, RSTART + 1)
          if (!(a in seen)) { seen[a] = 1; print a }
        }
      }' "$MAP" >"$TMP/archives"
    ;;
  *) fail "not a link map of GNU ld or ld64: $MAP" ;;
esac

# the files of APK_DB: path<TAB>package<TAB>version<TAB>origin<TAB>license
if [ "$FORMAT" = gnu ] && [ -f "$APK_DB" ]; then
  awk '
    function flush() { for (i = 1; i <= n; i++) print files[i] "\t" p "\t" v "\t" o "\t" l; n = 0; p = v = o = l = d = "" }
    /^$/ { flush(); next }
    /^P:/ { p = substr($0, 3) }
    /^V:/ { v = substr($0, 3) }
    /^o:/ { o = substr($0, 3) }
    /^L:/ { l = substr($0, 3) }
    /^F:/ { d = substr($0, 3) }
    /^R:/ { files[++n] = (d == "" ? "" : d "/") substr($0, 3) }
    END { flush() }' "$APK_DB" >"$TMP/apk"
else
  : >"$TMP/apk"
fi
ROOT_PREFIX=$(resolve "$APK_ROOT")
ROOT_PREFIX=${ROOT_PREFIX%/}

# apk_owner ARCHIVE: the line of $TMP/apk that owns ARCHIVE, by its path
# or by the path with the symbolic links resolved, on either side
apk_owner() {
  real=$(resolve "$1")
  base=$(basename "$1")
  realbase=$(basename "$real")
  awk -F '\t' -v a="$base" -v b="$realbase" '{ n = split($1, s, "/"); if (s[n] == a || s[n] == b) print }' "$TMP/apk" |
    while IFS='	' read -r path rest; do
      cand=$ROOT_PREFIX/$path
      if [ "$cand" = "$1" ] || [ "$cand" = "$real" ] || [ "$(resolve "$cand")" = "$real" ]; then
        printf '%s\t%s\n' "$path" "$rest"
        break
      fi
    done
}

GHC_REAL=$(resolve "$GHC_LIBDIR")
GHC_REAL=${GHC_REAL%/}
: >"$TMP/rows"
: >"$TMP/unknown"
: >"$TMP/apkrows"
while IFS= read -r a; do
  base=$(basename "$a")
  real=$(resolve "$a")
  comp=
  case "$base" in
    libHSrts*.a)
      case "$real/" in "$GHC_REAL"/* | "${GHC_LIBDIR%/}"/*) comp=ghc ;; esac
      case "$a/" in "$GHC_REAL"/* | "${GHC_LIBDIR%/}"/*) comp=ghc ;; esac
      ;;
  esac
  if [ -z "$comp" ]; then
    case "$base" in
      libHS*-[0-9]*-*.a) comp=haskell ;;
      libgmp.a) comp=gmp ;;
    esac
  fi
  if [ -z "$comp" ]; then
    case "$a" in */third_party/wasmtime/lib/libwasmtime.a | third_party/wasmtime/lib/libwasmtime.a) comp=wasmtime ;; esac
  fi
  if [ -z "$comp" ] && [ -s "$TMP/apk" ]; then
    owner=$(apk_owner "$a")
    if [ -n "$owner" ]; then
      origin=$(printf '%s\n' "$owner" | cut -f4)
      comp=apk:$origin
      printf '%s\t%s\t%s\t%s\t%s\n' "$origin" "$(printf '%s\n' "$owner" | cut -f2)" \
        "$(printf '%s\n' "$owner" | cut -f3)" "$(printf '%s\n' "$owner" | cut -f5)" "$a" >>"$TMP/apkrows"
    fi
  fi
  if [ -z "$comp" ] && [ "$FORMAT" = ld64 ]; then
    case "$base" in
      libclang_rt.*.a)
        case "$a" in */Xcode*.app/* | */CommandLineTools/*) comp=compiler-rt ;; esac
        ;;
    esac
  fi
  if [ -z "$comp" ]; then
    printf '%s\n' "$a" >>"$TMP/unknown"
  else
    printf '%s\t%s\n' "$comp" "$a" >>"$TMP/rows"
  fi
done <"$TMP/archives"

if [ -s "$TMP/unknown" ]; then
  echo "link-components: no component for these archives (add a rule to link-components.sh, docs/adr/0007):" >&2
  sed 's/^/  /' "$TMP/unknown" >&2
  exit 1
fi

if [ "$MODE" = --apk ]; then
  cat "$TMP/apkrows"
  exit 0
fi

# one line per component, in the order the components first appear
awk -F '\t' '
  { if (!($1 in line)) { line[$1] = $1; comps[++n] = $1 } line[$1] = line[$1] "\t" $2 }
  END { for (i = 1; i <= n; i++) print line[comps[i]] }' "$TMP/rows"
