# ADR 0064: 出力の一部しか固定していないゴールデンを、出力の全体を固定する形にする

ステータス: 採択（未実装）

## 文脈

ゴールデンは「この入力からこの出力が出る」ことを固定する。
2026-10-23 のテストの品質の点検で、次の三つのゴールデンが、名前から期待されるより少ないものしか固定していないことを確かめた。

- golem-cli の messages のゴールデン（[modules/golem-cli/test/Main.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-cli/test/Main.hs#L130-L134)）は、[`golem`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-cli/test/Main.hs#L36-L39) で標準出力と標準エラー出力を連結した文字列を固定する。[golem-cli ADR 0001](../golem-cli/adr/0001-command-line-interface.md) の 36 行めは「診断は標準エラー出力に、それ以外の出力は標準出力に書く」と定める。どちらのストリームに出たかは検査していないので、`golem --help` が標準エラー出力に書くように変わってもゴールデンは通る。[help.txt](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-cli/test/golden/help.txt) と [no-arguments.txt](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-cli/test/golden/no-arguments.txt) は同じ内容のファイルだが、「引数なしの出力は help と同じ」という関係は断言していない。
- golem-driver の雛形のゴールデン（[`templateText`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/CliSpec.hs#L28-L29) と [ゴールデンの定義](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/CliSpec.hs#L50)）は、`templateText = fromMaybe ""` で雛形の一覧からファイルを引く。雛形の一覧からファイルが消えると、空の文字列とゴールデンを比べて落ちる。ところが、このとき `--accept` を付けると空のゴールデンが黙って作られ、以後は通る。
- golem-driver の text、xhtml、css のゴールデン（[modules/golem-driver/test/Support.hs](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/Support.hs#L63)）は、`buildAndRead Dev` だけで作る。prod のプロファイルで出力が変わる経路（校正用のコメントの扱い、[golem-eval の校正用のコメントの評価](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-eval/src/Golem/Eval/File.hs#L1603-L1605) など）は、ゴールデンで固定していない。

## 実装すること

- golem-cli の messages のゴールデンを、標準出力と標準エラー出力の二つのファイルに分ける（`<名前>.stdout.txt` と `<名前>.stderr.txt`）。空のストリームは空のファイルとして固定する。
- `golem` と `golem --help` の関係を、ゴールデンではなく断言で書く。引数なしは終了コード 2 で、標準エラー出力に使い方を書く。`--help` は終了コード 0 で、標準出力に同じ使い方を書く。今の実装がこれと違うストリームに書いていれば、実装を [golem-cli ADR 0001](../golem-cli/adr/0001-command-line-interface.md) に合わせて直し、ゴールデンは直した実装に合わせて更新する。[golem-cli ADR 0001](../golem-cli/adr/0001-command-line-interface.md) は変えない。
- [CliSpec の `templateText`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/CliSpec.hs#L28-L29) は、一覧にないファイルを `assertFailure` で失敗にする。値を返す関数は `IO` にする。
- golem-driver の [Support.hs の `golden`](https://github.com/tett23/golem/blob/e874129709193ecc0b4a21a299028de7875aa8ce/modules/golem-driver/test/Support.hs#L62-L63) に prod のプロファイルの版を足し、sample の fixture の text と xhtml を prod でも固定する。dev と prod の出力が同じファイルは、二つのゴールデンが同じであることを断言して、片方だけを置く。

## 実装しないこと

- PDF と EPUB のゴールデン。別の作業で扱っている。
- golem-cli の他のテスト（終了コードのテスト）の形を変えること。

## ストリームの食い違いを実装の側で直す理由

diagnostic のコードの意味は、根本から変わってはならない。
意味を変えるときは、手続きとして必ず ADR を通す。
ゴールデンがメッセージを含めた出力の全体を固定するのは、そのためである。
意味の変更が ADR を経ずに入れば、ゴールデンの差分として現れる。

一方、出力をどちらのストリームに書くかを変えても、出力の意味は変わらない。
メッセージの文面が変わるのも、利用者にとってわかりやすくなる方向に限られる。
そのため、ストリームが [golem-cli ADR 0001](../golem-cli/adr/0001-command-line-interface.md) と食い違うときは、実装を直し、ゴールデンを実装に追従させる。

## テスト設計

- golem-cli：`golem --help` の標準エラー出力が空である。引数なしの `golem` の標準出力が空である。どちらかが今の実装で落ちれば、実装を [golem-cli ADR 0001](../golem-cli/adr/0001-command-line-interface.md) に合わせて直す。
- golem-cli：分けた二つのファイルを連結した内容が、今の help.txt と一致する（分けたときに中身を失っていないことの確認、移行のときに一度だけ行う）。
- golem-driver：`templateText Japanese "no-such-file"` が失敗する。今は空の文字列を返すので、このテストは落ちる。
- golem-driver：sample の fixture を prod で組んだ text のゴールデンがある。sample に `%` の校正用のコメントを含む行を足し、dev と prod で出力が違うことを断言する。

## トレードオフ

- golem-cli のゴールデンのファイルの数が倍になる。どちらのストリームに出たかを読めるようになる。
- prod のゴールデンを足すぶん、出力の変更のたびに更新するファイルが増える。prod は入稿とデプロイに使うプロファイルなので、固定する価値がある。

## 参考文献

- [golem-cli ADR 0001](../golem-cli/adr/0001-command-line-interface.md)
- [golem-cli ADR 0004](../golem-cli/adr/0004-usage-error-exit-code.md)
