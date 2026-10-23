# ADR 0074: テストを切り替える環境変数の値の読み方をそろえ、省いたテストを数える

ステータス: 採択（未実装）

## 文脈

テストの一部は、環境変数で範囲を切り替える。
2026-10-23 のテストの品質の点検で、次の二つを確かめた。

- `GOLEM_REQUIRE_EXTERNAL_TOOLS`（[modules/golem-test-support/src/Golem/TestSupport/ExternalTool.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-test-support/src/Golem/TestSupport/ExternalTool.hs#L76-L90)）は、値が `"1"` のときだけ、qpdf、cddl、openssl のないことを失敗にする。それ以外では、テストを `testPassed` にして、短い説明を `SKIP` に替える。tasty の結果の表示には `SKIP` と出るが、最後の件数では通ったテストとして数える。CI は `"1"` を設定している（[.github/workflows/ci.yml](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/.github/workflows/ci.yml#L241)）ので CI では問題ない。手元では、PDF の妥当性の検査を一度も走らせずに、すべて通ったという結果を得られる。
- `GOLEM_PD_BOOKS`（[modules/golem-driver/test/BuildSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/BuildSpec.hs#L199)）は `isJust` で読むので、`GOLEM_PD_BOOKS=0` でも有効になる。README.md:234 は「環境変数 `GOLEM_PD_BOOKS` があれば」と書いており、実装と README は一致している。ただし、同じ種類の変数の `GOLEM_REQUIRE_EXTERNAL_TOOLS`、`GOLEM_REQUIRE_LOCALES`、`GOLEM_REQUIRE_FONTS` は `"1"` のときだけ有効になり、読み方がそろっていない。`GOLEM_REQUIRE_LOCALES=0` と `=yes` を無効として扱うことは、[scripts/env-determinism/test.sh](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/scripts/env-determinism/test.sh#L162-L168) がテストで固定している。

## 実装すること

- テストを切り替える環境変数は、値が `"1"` のときだけ有効とし、それ以外（未設定、空、`0`、`yes` など）は無効とする。今の `GOLEM_REQUIRE_*` の規則に `GOLEM_PD_BOOKS` を合わせる。
- 読み方は golem-test-support の一つの関数（`envFlag :: String -> IO Bool`）にまとめ、[`toolsRequiredBy`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-test-support/src/Golem/TestSupport/ExternalTool.hs#L81-L82) もこれを使う。`GOLEM_PD_BOOKS` もこの関数で読む。golem-driver のテストは golem-test-support にすでに依存しているので、依存は変えない。
- 外部のツールがないために省いたテストの数を、テストのスイートの最後に標準エラー出力へ一行で書く（`3 tests skipped: qpdf is not installed (GOLEM_REQUIRE_EXTERNAL_TOOLS=1 makes them failures)` の形）。数は golem-test-support の中の `IORef` で数え、各スイートの `main` で、tasty の結果を書いた後に書く。golem-driver では、`GOLEM_PD_BOOKS` が無効で十冊を check だけで済ませたことも、同じ形の一行で書く。
- README.md の 234 行めと 252 行め、CONTRIBUTING.md の 101 行めを、値は `1` だけであることと、省いた数が最後に出ることに合わせて書き直す。

## 実装しないこと

- 手元の既定で外部のツールを必須にすること。qpdf や cddl のない環境でも開発を始められることを優先する。
- 省いたテストを tasty の結果で失敗や別の状態にすること。tasty 1.5 には「省いた」状態がないので、件数を別に書く。

## テスト設計

- golem-test-support のテストに、`envFlag` の値を決める純粋な関数（`envFlagBy :: Maybe String -> Bool`）が `Just "1"` で真、`Nothing`、`Just ""`、`Just "0"`、`Just "yes"` で偽であることを足す。関数がまだないので落ちる。
- golem-driver：`GOLEM_PD_BOOKS=0` で BuildSpec の該当するテストを走らせ、出力を書かない（check だけの）経路になることを、実装の後に手で確かめてプルリクエストの説明に書く。テストのスイートの外の環境に関わるので、自動テストにしない。

## トレードオフ

- `GOLEM_PD_BOOKS=true` のような今は有効になる書き方が、黙って無効になる。値の誤りをエラーにする案もあるが、今の `GOLEM_REQUIRE_*` の規則とそのテストを変えることになるので採らない。最後の一行で、無効になったことには気付ける。
- 省いた数を書く一行のために、各スイートの `main` に数行を足す。

## 参考文献

- [ADR 0058](0058-run-skipped-checks-in-ci.md)
- [ADR 0029](0029-environment-variation-determinism-test.md)
