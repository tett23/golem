# 言語ごとの分綴の参照データ

このディレクトリは、言語ごとのパターンの分綴のテスト（[ADR 0276](../../../../../docs/adr/0276-hyphenate-words-by-the-patterns-of-their-language.md) の F2）の期待値を置く。
同梱のパターン（`../../../data/hyphenation/`）と同じファイルを TeX に読ませ、`\showhyphens` が示した分綴の位置を記録した。
テストは `../../LanguagesSpec.hs` が `showhyphens.txt` を読み、`hyphenate` の結果と比べる。
扱いは、行分割の参照テスト（[golem-layout ADR 0007](../../../../../docs/golem-layout/adr/0007-knuth-plass-reference-test.md)、`../knuth-plass/`）と同じである。

| ファイル | 内容 |
|---|---|
| `showhyphens.tex` | 生成に使う LaTeX のファイル。言語ごとに語を並べ、`\showhyphens` にかける |
| `showhyphens.lua` | `data/hyphenation/` のパターンと例外を、LuaTeX の新しい言語に読み込む |
| `showhyphens.log` | TeX のログ |
| `showhyphens.txt` | ログから抜き出した、言語の名前と、分綴の位置に `-` を入れた語の組。一行に一語 |

## TeX

- `lualatex --version` の一行目は `This is LuaHBTeX, Version 1.24.0 (TeX Live 2026)` である。
- Docker のイメージ `texlive/texlive@sha256:07e8062637249c4f780ca59f42cc2ed592bc2dc1db4320769406aee3f98aa70e`（`texlive/texlive:latest`、2026-11-10）の中で動かした。

TeX Live に入っている hyph-utf8 は使わない。
`showhyphens.lua` が `lang.new` で言語を作り、同梱のファイルを `lang.patterns` と `lang.hyphenation` で読み込む。
TeX Live の hyph-utf8 の版が同梱のコミット（`5684c0f5`）と違っても、期待値は同梱のファイルから求まる。
パターンに現れる文字は、数字と `.` と `-` と空白を除いて、すべて `\lccode` を自身にする。

前と後に残す字の数（`\lefthyphenmin` と `\righthyphenmin`）は、言語ごとに hyph-utf8 の値にする（`data/hyphenation/README.md` の表）。
語はすべて小文字で書き、ハイフンもアポストロフィも含めない。
Golem がパターンに渡す字の並び（[docs/adr/0222](../../../../../docs/adr/0222-line-breaking-points-the-invariants-did-not-decide.md)）と、TeX が分綴する語が同じになるようにするためである。
英語（米国）のほかの各言語の語には、前と後に残す字の数の和の長さの語と、それより一字長い語を含める。

## 手順

`/private/tmp` は Docker にマウントできないので、ファイルを tar にして標準入力から渡す。
このディレクトリで次を実行する。

```sh
dir=$(mktemp -d)
cp showhyphens.tex showhyphens.lua ../../../data/hyphenation/hyph-*.txt "$dir"
(cd "$dir" && tar cf - showhyphens.tex showhyphens.lua hyph-*.txt) |
  docker run -i --rm texlive/texlive:latest sh -c \
    'mkdir /w && cd /w && tar xf - && max_print_line=10000 lualatex -interaction=nonstopmode showhyphens.tex >/dev/null 2>&1; cat showhyphens.log' \
    >showhyphens.log
awk '/^GOLEM-LANG /{tag=$2; next} tag!="" && /^\[\] /{sub(/^\[\] [^ ]+ /,""); n=split($0,w," "); for(i=1;i<=n;i++) printf "%s\t%s\n", tag, w[i]; tag=""}' \
  showhyphens.log >showhyphens.txt
```

`max_print_line` を大きくするのは、`\showhyphens` の行をログで折り返させないためである。
言語の名前は `showhyphens.tex` のマクロの名前（`enus`、`engb`、`fr`、`de1996`、`es`、`it`、`pt`、`nl`）であり、テストが Golem のタグ（`en-US`、`en-GB`、`fr`、`de`、`es`、`it`、`pt`、`nl`）に読み替える。

## 結果の要点

- `[lang fr: proverbe]` は、フランス語のパターンで `pro-verbe` に分かれる（ロードマップにあった Nightmare Abbey の「prover-be」は英語のパターンの分け方である）。
- `hyphenation` は、英語（米国）では `hy-phen-ation`、英語（英国）では `hy-phen-a-tion` に分かれる。
- 英語（英国）の `table` は分かれない。英語（米国）の同梱の例外 `ta-ble` は、英語（英国）の例外の一覧にない。
