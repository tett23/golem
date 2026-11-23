# ADR 0424: 2026-11-18 の監査の低の指摘のうち、ADR が要る四つを直す

Status: proposed

## 文脈

2026-11-18 の ADR 違反と予算違反の監査（[docs/audits/2026-11-18-conformance-audit.md](../audits/2026-11-18-conformance-audit.md)）の、重大度が低の指摘は、PR #1086 で直した。
そのうち次の四つは、振る舞いか ADR の決めた形を変えるので、ADR が要るとして残した。

1. [ADR 0375](0375-printings-format.md) の書式のエラーの文言が、ADR の決めた `{{` ではなく `\{` を勧める。
2. [ADR 0346](0346-revise-named-layout-values.md) で、値の宣言の右辺の未定義の名前と種類違いが、ADR の決めたコードではなく G03256 になる。
3. [ADR 0387](0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md)、[ADR 0347](0347-revise-complete-manifest-values-and-manuscript-expressions.md)、[ADR 0348](0348-revise-emet-expression-repl.md)、[ADR 0350](0350-omit-page-link-annotations-from-pdf-x-4.md) が、不変条件のテストの名前に、I ではない番号（S、T、M、D、R、X）を使う。
4. [ADR 0392](0392-budget-the-pull-request-ci-at-five-minutes.md) の予算に、ADR の中の番号がない。

tett23 は 2026-11-23 に、これらの ADR を書くことを決めた。

## 調査した事項

`origin/main`（`34cd15426`）で確かめた。

- 書式を読む [`parseFormat`](https://github.com/tett23/golem/blob/34cd15426c0ac42fec87ef6bc51a9a388e0dfd1b/modules/golem-numerals/src/Golem/Numerals/Format.hs#L86-L87) は、閉じていない `{` と対応する `{` のない `}` に、「文字の { は \{ と書きます」「文字の } は \} と書きます」と勧める文を返す。
  `{{` も読む読み方（`DoubledToo`）を使う書式は、`[printings]`、柱、リストの番号の三つである。
  `{{` を今の書き方とするのは `[printings]`（[ADR 0375](0375-printings-format.md)）だけで、柱とリストの番号では `{{` は退役予定の形（G03252、G03114）である。
  [ADR 0413](0413-new-codes-for-font-axes-and-printing-formats.md) は、`[printings]` の書式の誤りに原因ごとのコード（閉じていない `{` は G03267、対応する `{` のない `}` は G03268）を振り、メッセージは今の文を使うと決めた。
  その実装は、`parseFormat` が原因の値と文の組を返すように変える。
- 値の名前を引く [`reference`](https://github.com/tett23/golem/blob/34cd15426c0ac42fec87ef6bc51a9a388e0dfd1b/modules/golem-project/src/Golem/Project/Style.hs#L3062-L3065) は、宣言の右辺（`stack` が空でない）の未定義の名前と種類違いを G03256 にする。
  使用箇所は、長さとアキ量を [`rewriteValue`](https://github.com/tett23/golem/blob/34cd15426c0ac42fec87ef6bc51a9a388e0dfd1b/modules/golem-project/src/Golem/Project/Style.hs#L3103-L3105) が、行数を `stack` が空の `reference` が、G03257 と G03258 にする。
  宣言どうしの循環は G03256 である（[ADR 0346](0346-revise-named-layout-values.md) も循環を G03256 とする）。
  [ADR 0346](0346-revise-named-layout-values.md) は、参照先がない場合は G03257、種類が違う場合は G03258 を参照位置に出すと決め、宣言の右辺と使用箇所を分けていない。
  仕様書も「未定義の参照は G03257、違う種類の参照は G03258」と書く。
- [ADR 0387](0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md) の不変条件は 1 から 4 で、テストの名前には `S1` から `S4` を入れると決めた（[ADR 0246](0246-bound-the-prompt-of-the-release-notes.md) の I4 から I6 と区別するため）。
- [ADR 0347](0347-revise-complete-manifest-values-and-manuscript-expressions.md) の不変条件の 1 から 3 は T1、M1、D1、[ADR 0348](0348-revise-emet-expression-repl.md) の 1 から 7 は R1 から R7、[ADR 0350](0350-omit-page-link-annotations-from-pdf-x-4.md) の 1 から 4 は X1 から X4 と名付けられ、テストの名前に入っている。
  adr スキルの「番号とテストの名前」は、不変条件に I のほかの番号を使わないと決めている。
- 0387 のテストは `scripts/release/test.sh` にあり、名前は `notes: S1 S2 S3 …` の形で、ADR の番号を含まない。
- [ADR 0415](0415-fix-the-medium-findings-of-the-conformance-audit-of-2026-11-18.md) は、0348 の R4 と R7 を確かめる段の名前を、すでに `root ADR 0348 I4, I7` と書いた。
- 予算の一覧（`docs/budgets.md`）の「プルリクエストの CI の時間」の行の ADR の列は、`ADR 0392` だけで番号がない。
  [ADR 0392](0392-budget-the-pull-request-ci-at-five-minutes.md) は、予算を「実装すること」に書き、受けいれ条件の A1 は予算を満たすかを問わない。

## 実装すること

### 1. 書式のエラーの文言

- `[printings]` の書式の、閉じていない `{` と対応する `{` のない `}` の文言は、文字の波括弧を `{{` と `}}` で書くよう勧める。
- ほかの書式の文言は、今と同じく `\{` と `\}` を勧める。
- 文言は、`printingTemplate` が `parseFormat` の原因の値（閉じていない `{`、対応する `{` のない `}`）を見て差し替える。
  `parseFormat` の文と、柱とリストの番号の書式の文言は変えない。

### 2. 値の宣言の右辺のコード

- 値の宣言の右辺の未定義の名前は G03257、種類違いは G03258 にする。
  使用箇所と同じコードにし、位置は右辺の名前に置く。
- G03256 は、宣言の値の誤りと循環に使う。
  宣言の右辺の未定義の名前と種類違いには使わない。
- `docs/diagnostics.md` の G03256、G03257、G03258 の「意味」と「主な原因」を直し、仕様書の値の名前の段落に、宣言の右辺の扱いを書く。

### 3. テストの名前の番号

- 次の対応で、テストの名前の番号を I に付け直す。
  ADR の本文の番号は変えず、この ADR が対応を記録する。

| ADR | 本文の番号 | テストの名前の番号 |
| --- | --- | --- |
| [0387](0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md) | S1、S2、S3、S4 | I1、I2、I3、I4 |
| [0347](0347-revise-complete-manifest-values-and-manuscript-expressions.md) | T1、M1、D1 | I1、I2、I3 |
| [0348](0348-revise-emet-expression-repl.md) | R1 から R7 | I1 から I7 |
| [0350](0350-omit-page-link-annotations-from-pdf-x-4.md) | X1 から X4 | I1 から I4 |

- テストの名前は `root ADR NNNN I<番号>: ...` とし、二つ以上の番号は `, ` で区切る。
  対象のファイルは、`modules/*/test`、`scripts/*/test.sh`、`scripts/release/test.sh`、`.github/workflows` の段の名前とする。
  [ADR 0387](0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md) のテストは、名前に ADR の番号が入るので、[ADR 0246](0246-bound-the-prompt-of-the-release-notes.md) の I4 から I6 とは区別できる。

### 4. 0392 の予算の番号

- [ADR 0392](0392-budget-the-pull-request-ci-at-five-minutes.md) の予算（プルリクエストの `ci.yml` の時間の中央値を 300 秒以下とする）を、この ADR の A1 として番号で指す。
- 予算の一覧の ADR の列を、`ADR 0392` と `ADR 0424 A1` にする。

### ステータスの行

採択したら、次の ADR のステータスの行に、この ADR による補足を足す。

- [ADR 0375](0375-printings-format.md)：部分「書式のエラーの文言」。
- [ADR 0413](0413-new-codes-for-font-axes-and-printing-formats.md)：部分「新しいコードのメッセージ（G03267、G03268）」。
- [ADR 0346](0346-revise-named-layout-values.md)：部分「宣言の右辺の参照のコード」。
- [ADR 0387](0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md)、[ADR 0347](0347-revise-complete-manifest-values-and-manuscript-expressions.md)、[ADR 0348](0348-revise-emet-expression-repl.md)、[ADR 0350](0350-omit-page-link-annotations-from-pdf-x-4.md)：部分「テストの名前の番号」。
- [ADR 0392](0392-budget-the-pull-request-ci-at-five-minutes.md)：部分「予算の番号」。

## 実装しないこと

- ADR の本文の番号（S、T、M、D、R、X）は変えない。
- 予算の値と測り方は変えない。
- ほかの書式のエラーの文言は変えない。

## 不変条件

- I1：`[printings]` の書式で、閉じていない `{` か対応する `{` のない `}` を書いた入力の文言は `{{` と `}}` を勧め、柱、リストの番号、注の印などほかの書式の同じ誤りの文言は、この ADR の前と同じである。
- I2：値の宣言の右辺で未定義の名前を参照した入力は G03257 を、種類の違う名前を参照した入力は G03258 を、それぞれちょうど一つ含み、G03256 を含まない。
  宣言どうしの循環と、宣言の値そのものの誤りは、この ADR の前と同じく G03256 である。
- I3：上の対象のファイルの、四つの ADR の不変条件を確かめるテストの名前は、どれも `root ADR NNNN I<番号>` で始まり、二つ以上の番号を `, ` で区切る。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `[printings] format = "{year"` | G03267、`{{` を勧める文言 | I1 |
| 柱の書式 `"{title"` | `\{` を勧める文言（前と同じ） | I1 |
| `[notes] mark-format = "{n"` | `\{` を勧める文言（前と同じ） | I1 |
| `[values.length] a = "missing"` | G03257 | I2 |
| `[values.aki] h = "二分"` と `[values.length] a = "h"` | G03258 | I2 |
| `[values.length] a = "3mm"` と使用箇所の `[paragraph-styles.quote] indent = "x"` | G03257（前と同じ） | I2 |
| `[values.count] n = "a+m"`（`m` が未定義） | G03257 | I2 |
| `[values.length] a = "b"` と `b = "a"`（循環） | G03256（前と同じ） | I2 |
| `[values.length] a = "b"` と `b = "3mx"`（参照先の値の誤り） | G03256（前と同じ） | I2 |
| 付け直した後のテストの名前 | `root ADR NNNN I<番号>` の形 | I3 |
| `notes: S1 S2 S3`（0387 の今の名前） | 検査が失敗 | I3 |

## 受けいれ条件

- A1：プルリクエストの `ci.yml` の時間の中央値は、300 秒以下である（[ADR 0392](0392-budget-the-pull-request-ci-at-five-minutes.md) の予算。値と測り方は 0392 のとおり）。
  A1 は、予算の一覧から番号で指すための予算であり、守り続けるものである。
  この ADR を `accepted` にする条件には含めない（今は満たしておらず、2026-11-23 の記録で 398.5 秒であり、[ADR 0416](0416-shorten-the-build-of-the-pull-request-ci.md) で縮める）。

## テスト設計

- 名前は `root ADR 0424 I<番号>: ...` とする。
  I1 と I2 のテストは、実装の前に失敗することを確かめてから実装する。
- I1 は、golem-numerals と golem-project のテストで、二つの読み方の文言を確かめる。
- I2 は、golem-project のテストで、境界の表の行ごとにコードと位置を確かめる。
  [ADR 0346](0346-revise-named-layout-values.md) の今のテストのうち、右辺で G03256 を期待するものは書き換える。
- I3 は、`scripts/ci/test.sh` に、対象のファイルから四つの ADR のテストの名前（0387 は `scripts/release/test.sh` の `notes:` と `write-notes:` の名前）を集めて形を確かめる検査を置く。
  検査は、付け直す前に失敗することを確かめる。
  検査自身のファイルは集める対象から除く。
- A1 は、予算の一覧の計測のコマンド（`sh scripts/ci/ci-critical-path.sh`）で測る。

## トレードオフ

ADR の本文の番号とテストの名前の番号が違うので、読み手はこの ADR の対応の表を引くことになる。
コミット済みの ADR の本文は変えられないので、対応を記録する形にする。
adr スキルには、決まりを入れたときに一度だけ ADR の番号を書き換えてよい例外がある。
この ADR はその例外を使わず、本文の番号を残したまま対応を記録する。

## 参考文献

- [docs/audits/2026-11-18-conformance-audit.md](../audits/2026-11-18-conformance-audit.md)
- [ADR 0375](0375-printings-format.md)
- [ADR 0413](0413-new-codes-for-font-axes-and-printing-formats.md)
- [ADR 0346](0346-revise-named-layout-values.md)
- [ADR 0387](0387-update-adr-guard-to-v0.13.1-and-migrate-status-lines.md)
- [ADR 0246](0246-bound-the-prompt-of-the-release-notes.md)
- [ADR 0347](0347-revise-complete-manifest-values-and-manuscript-expressions.md)
- [ADR 0348](0348-revise-emet-expression-repl.md)
- [ADR 0350](0350-omit-page-link-annotations-from-pdf-x-4.md)
- [ADR 0392](0392-budget-the-pull-request-ci-at-five-minutes.md)
- [ADR 0416](0416-shorten-the-build-of-the-pull-request-ci.md)
- [ADR 0415](0415-fix-the-medium-findings-of-the-conformance-audit-of-2026-11-18.md)
