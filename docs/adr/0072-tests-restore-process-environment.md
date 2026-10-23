# ADR 0072: 環境変数を書き換えるテストは、書き換えを元に戻す

ステータス: 採択（未実装）

## 文脈

環境変数はプロセス全体で一つであり、`setEnv` の書き換えは同じプロセスで走るすべてのテストに及ぶ。
tasty は、`-threaded` で capability が二つ以上あるとき、テストを並行に走らせる。

2026-10-23 のテストの品質の点検で、次の書き換えが元に戻されないことを確かめた。

- [modules/golem-lsp/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/test/Main.hs#L554) は `setEnv "XDG_CACHE_HOME" (tmp </> "cache")` を戻さない。golem-lsp のテストのスイートは `-threaded "-with-rtsopts=-N"`（[modules/golem-lsp/golem-lsp.cabal](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-lsp/golem-lsp.cabal#L52)）であり、テストは並行に走る。`tmp` はテストの後に消えるので、以後のテストは消えたディレクトリをキャッシュとして読む。今は書き換えが 1 箇所なので症状が出ていない。
- [modules/golem-driver/test/PluginsSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/PluginsSpec.hs) の [51 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/PluginsSpec.hs#L51)、[194 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/PluginsSpec.hs#L194)、[208 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/PluginsSpec.hs#L208) も `XDG_CACHE_HOME` を戻さない。golem-driver-test は `-threaded` でない（[golem-driver.cabal の golem-driver-test](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/golem-driver.cabal#L70-L124)）ので今は順に走るが、`-threaded` にしたときに競合する。

点検の報告は [modules/golem-driver/test/LocaleSpec.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/LocaleSpec.hs) の `setLocaleEncoding` も戻さないとしたが、誤りである。
[その 60 行め](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/LocaleSpec.hs#L60) は `bracket` で元の符号化を戻している。
[modules/golem-plugin/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-plugin/test/Main.hs#L417-L424) の `SSL_CERT_FILE` も `finally` で戻している。

## 実装すること

- golem-lsp と golem-driver の `XDG_CACHE_HOME` の書き換えを、`finally` で元の値（なければ `unsetEnv`）に戻す形にする。[modules/golem-plugin/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-plugin/test/Main.hs#L417-L424) と同じ形で書く。
- golem-lsp では、`XDG_CACHE_HOME` を読むテストが並行に走って互いの値を見ないよう、該当するテストを `sequentialTestGroup`（tasty 1.5）で順に走らせる。
- 補助の関数はそれぞれのテストのスイートに置く。golem-lsp のテストは golem-test-support に依存していないので、依存を足さない。

## 実装しないこと

- キャッシュのディレクトリを環境変数ではなく引数で渡すように、golem-plugin の API を変えること。テストのための API の変更になり、利用者の振る舞いに関係しない。
- golem-driver-test を `-threaded` にすること。

## テスト設計

- golem-lsp のテストに、スイートの最後で `XDG_CACHE_HOME` がスイートを始めたときの値と同じであることを確かめるテストを足す（`sequentialTestGroup` で最後に置く）。今は書き換えたままなので落ちる。
- golem-driver も同じテストを PluginsSpec の後に足す。

## トレードオフ

- 順に走らせるテストが増えるぶん、golem-lsp のテストのスイートの時間がわずかに延びる。

## 参考文献

- tasty 1.5、`sequentialTestGroup`
