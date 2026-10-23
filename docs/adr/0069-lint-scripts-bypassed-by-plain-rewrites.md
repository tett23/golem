# ADR 0069: CI の検査のスクリプトを、素朴な書き換えで迂回できないようにする

ステータス: 採択（未実装）

## 文脈

CI の `changes` ジョブは、ソースと .cabal の約束を四つのスクリプトで検査する（README.md:328、CONTRIBUTING.md:160-177）。
2026-10-23 のテストの品質の点検で、どれも素朴な書き換えで検査をすり抜けることを確かめた。
スクリプトのテスト（[scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh)）の fixture は、すり抜ける形を含まないので、変異テストでも見つからない。

### [scripts/ci/unsafe-io.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/unsafe-io.sh)（[ADR 0034](0034-fewer-unsafe-perform-io.md)）

- 検出する名前は 7 つ（[検出の正規表現](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/unsafe-io.sh#L24)）。テストが試すのは `unsafePerformIO` と `unsafeDupablePerformIO` の二つ（[unsafe-io.sh のテスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L279-L310)）で、残る 5 つを `pat` から消してもテストは通る。
- 行のコメントは、文字列の中の `--` でも始まる（[行のコメントを除く箇所](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/unsafe-io.sh#L50-L52)）。`f = let _ = "--" in unsafePerformIO x` の `unsafePerformIO` は見えない。
- ブロックのコメントも、文字列の中の `{-` で始まる（[ブロックのコメントを除く箇所](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/unsafe-io.sh#L36-L46)）。
- Template Haskell の名前の引用 `'unsafePerformIO` は、名前の直前の `'` を識別子の文字として扱うので検出しない（[検出の正規表現](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/unsafe-io.sh#L24)）。
- 使った場所の名前は、行頭の小文字の識別子から取る（[名前を取る箇所](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/unsafe-io.sh#L54-L57)）。`instance` の行は名前を変えないので、許可された関数の直後の `instance Show T where show _ = unsafePerformIO ...` は、許可された関数の名前で報告され、一覧と一致して通る。

### [scripts/ci/rts-capabilities.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/rts-capabilities.sh)

- `ghc-options:` の行だけを読み、続きの行（字下げした次の行）を読まない（[`ghc-options:` を読む箇所](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/rts-capabilities.sh#L65-L70)）。`ghc-options:` の次の行に `-threaded` を書くと検査の外になる。
- セクションの名前を小文字でだけ照合する（[セクションを照合する箇所](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/rts-capabilities.sh#L58-L64)）。cabal はセクションの名前の大文字と小文字を区別しないので（実装のときに cabal 3.x で確かめる）、`Executable x` は検査されない。
- `-with-rtsopts` は行の最初の一つだけを見る（[`has_n`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/rts-capabilities.sh#L42-L53)）。GHC は後の `-with-rtsopts` で前のものを置き換えるので（GHC 9.10.3 で実際に確かめてから fixture にする）、`"-with-rtsopts=-N" "-with-rtsopts=-A64m"` は検査を通るが、実行時には `-N` がない。
- common のスタンザに `-threaded` があり `-N` がない場合の負のケースが、[rts-capabilities.sh のテスト](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh#L318-L350) にない。

### [scripts/ci/incomplete-patterns.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/incomplete-patterns.sh)（[ADR 0027](0027-exhaustive-command-dispatch-by-types.md)）

- フラグを部分文字列で探す（[フラグを探す箇所](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/incomplete-patterns.sh#L40-L45)）。`-Werror=incomplete-patterns -Wno-error=incomplete-patterns` は通る。
- ソースの `{-# OPTIONS_GHC -Wno-incomplete-patterns #-}` を見ない。
- cabal.project の `package *` の `ghc-options` を見ない。

### [scripts/ci/docs-refs.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/docs-refs.sh)（[ADR 0021](0021-docs-workflow-and-ci-gate.md)）

- 文書のパスを `docs/...` の文字列のリテラルとしてだけ拾う（[パスを拾う箇所](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/docs-refs.sh#L31)）。`"docs" </> "diagnostics.md"` のように組み立てたパスは漏れ、その文書を変えたプルリクエストでビルドが省かれる。

## 実装すること

迂回の形を、それぞれの負の fixture として [scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh) に先に足し、検出するようにスクリプトを直す。

- unsafe-io.sh
  - 7 つの名前をすべて fixture で試す。
  - コメントを取り除く前に、文字列のリテラル（`"..."`、エスケープを含む）と文字のリテラル（`'x'`）を空にする。
  - 名前の直前の `'` を、識別子の一部としてではなく名前の引用として扱い、`'unsafePerformIO` と `''` の形を使用に数える。
  - `instance`、`class`、`data`、`newtype`、`type`、`pattern` の行で、使った場所の名前を `instance` などの宣言の名前に切り替える。インスタンスの中の使用は `FILE:instance <行の残り>` で報告し、一覧に書かない限り失敗にする。
- rts-capabilities.sh と incomplete-patterns.sh
  - 二つのスクリプトの .cabal の読み方をそろえる。フィールドの続きの行を同じフィールドとして読み、セクションとフィールドの名前を大文字と小文字を区別せずに照合する。
  - rts-capabilities.sh は、`-with-rtsopts` のすべてを読み、最後のものに `-N` があることを求める。
  - incomplete-patterns.sh は、フラグの後に `-Wno-error=incomplete-patterns`、`-Wno-incomplete-patterns`、`-Wwarn=incomplete-patterns` があれば失敗にする。modules の下の .hs の `OPTIONS_GHC` にこれらがあれば失敗にする。cabal.project と cabal.project.local の `ghc-options` も同じく調べる。
  - 二つのスクリプトの .cabal の読み方は、共通の awk の断片にせず、それぞれに書く。二つの検査を独立に保つためである。
- docs-refs.sh
  - `docs/` の文字列のリテラルに加え、`"docs"` という文字列のリテラルを含む行を報告し、その行に読む文書を `-- docs-refs: docs/<パス>` の注釈で書くことを求める。注釈のない行は失敗にする。
  - CONTRIBUTING.md の、`needs-build.sh` の一覧に文書を加える段落（160 行め）に、この注釈を書く。

## 実装しないこと

- Haskell の構文解析器でソースを読むこと。awk の字句の近似のまま、見つかった迂回の形を塞ぐ。近似で塞げない形が見つかったときに、改めて ADR で検討する。
- `hs-source-dirs` に `src` と `app` 以外を書いたパッケージを unsafe-io.sh の対象に広げること。今のパッケージはすべて `src` と `app` であり（[各モジュールの .cabal](https://github.com/tett23/golem/tree/e874129709193ecc0b4a21a299028de7875aa8ce/modules)）、別の名前を足すときにこのスクリプトを直す。
- 変更の範囲の取り方（[scripts/ci/changed-paths.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/changed-paths.sh)）。[ADR 0070](0070-changed-paths-without-rename-detection.md) で扱う。

## テスト設計

[scripts/ci/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/test.sh) に、次の fixture を足す。
どれも今のスクリプトでは期待と逆の結果になるので、先に足して落ちることを確かめる。

- unsafe-io：残る 5 つの名前の使用、文字列の `"--"` の後の使用、文字列の `"{-"` の後の使用、`'unsafePerformIO`、許可された関数の直後のインスタンスの中の使用。どれも終了コード 1。
- rts-capabilities：続きの行の `-threaded`、`Executable x`、二つの `-with-rtsopts` の後のほうに `-N` がないもの、common のスタンザに `-threaded` だけがあるもの。どれも終了コード 1。逆に、続きの行に `-threaded` と `"-with-rtsopts=-N"` があるものは 0。
- incomplete-patterns：`-Wno-error=incomplete-patterns` を後ろに付けたもの、`OPTIONS_GHC -Wno-incomplete-patterns` を持つソース、cabal.project の `package *` で打ち消すもの。どれも終了コード 1。続きの行にフラグを書いたものは 0。
- docs-refs：`"docs" </> "new.md"` を読むテストのソースで注釈がないものは 1、注釈があり一覧にあるものは 0。

## トレードオフ

- 文字列のリテラルを空にする処理は、Haskell の文字列の文法（文字列の途中の改行の継続、`\&`）をすべては扱わない。扱えない形は誤検出の側に倒し、CI が落ちたときに直す。
- docs-refs の注釈は、パスを組み立てる書き方をした開発者に手間を一つ足す。漏れて検査が省かれるよりよい。
- インスタンスの中の使用を別に数えるので、今は一覧と一致していても、実装の後に一覧の更新が要る可能性がある。今のソースの使用は 4 つで、すべてトップレベルの関数の中にある（[scripts/ci/unsafe-io-allowed.txt](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/ci/unsafe-io-allowed.txt)）。

## 参考文献

- [ADR 0021](0021-docs-workflow-and-ci-gate.md)
- [ADR 0027](0027-exhaustive-command-dispatch-by-types.md)
- [ADR 0034](0034-fewer-unsafe-perform-io.md)
- [ADR 0070](0070-changed-paths-without-rename-detection.md)
- Cabal User Guide、package description の節（フィールドとセクションの名前の大文字と小文字）
- GHC User's Guide、`-with-rtsopts` の節
