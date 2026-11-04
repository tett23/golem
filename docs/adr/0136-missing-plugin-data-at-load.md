# ADR 0136: 渡されていないデータを `golem_check_data` で読み込みのときに報告する

ステータス: 採択

## 文脈

[docs/adr/0120](0120-plugin-data-check-at-load.md) は、プラグインのデータを読み込みのときに一度だけ検査する任意の export `golem_check_data` を設けた。
動機の一つは、データの誤りが見えるかどうかが、原稿にコマンドを書いたかどうかで変わることだった。
`[term]` を書いていない本では、用語集の TSV の誤りがまったく報告されなかった。

`golem_check_data` の応答 `data-diagnostic` は、`name` でデータを指し、ホストはそのデータのファイルの行を位置にする。
[docs/adr/0120](0120-plugin-data-check-at-load.md) は「`name` が宣言にない名前なら、不正な応答（G06009）とする」と書いた。
実装は、これを「渡していない名前なら G06009」と読んだ（[`located`](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/modules/golem-driver/src/Golem/Driver/Plugins.hs#L198-L210)、メッセージは `渡していないデータの名前です: <名前>`）。
実装者はこれを逸脱として申告した。

この読み替えは妥当である。

- `*` を宣言するプラグイン（[docs/adr/0119](0119-plugin-data-of-any-name.md)）では、「宣言にある名前」が定まらない。
- 宣言にあっても渡していない名前には、位置にするファイルがない。

ただし、この規則のもとでは、プラグインは「必須のデータが渡されていない」ことを `golem_check_data` で報告できない。
そのデータの名前を `name` に書くと G06009 になり、ほかに書ける位置がないからである。
用語集の見本は、`terms` がないことを呼び出しごとの `no-data` で報告している（[glossary/lib.rs の 110 行めから 124 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/plugins/glossary/src/lib.rs#L110-L124)、[同 188 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/plugins/glossary/src/lib.rs#L188)）。
2026-11-04 の監査は、`data` を書かずに `[term: 組版]` を書くと、読み込みのときには何も出ず、呼び出しの位置に `glossary/no-data` が出ることを確かめた。
`[term]` のない本では、何も出ない。
[docs/adr/0120](0120-plugin-data-check-at-load.md) が塞ごうとした穴の一部が残っている（[docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md) の F-21）。

同じ穴は、ルビの二つの見本にもある。
`sou-ruby` と `first-ruby` は、`words`（`sou-ruby` では辞書も）がないことを、フィルタを当てたファイルごとに、その先頭のエラー `no-words` で報告する（[sou-ruby/lib.rs の 142 行めから 155 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/plugins/sou-ruby/src/lib.rs#L142-L155)、[first-ruby/lib.rs の 68 行めから 85 行め](https://github.com/tett23/golem/blob/97be81e8de344a22a15079b2e56bf0e5ce20ea62/plugins/first-ruby/src/lib.rs#L68-L85)）。
`words` を渡さずに三つのファイルに `first-ruby` を当てると、`golem check` で同じエラーが三度出ることを確かめた。

## 実装すること

### 応答の形

`data-diagnostic` の `name` に null を許す。

```cddl
data-diagnostic = [code: tstr, severity: 0 / 1, name: tstr / null, line: uint64 / null, message: tstr]
```

- `name` が null の diagnostic は、特定のデータのファイルでなく、プラグインに渡したデータの全体についてのものである。ホストは、`manifest.toml` の先頭を位置とする。G06101 から G06103（[docs/adr/0105](0105-plugin-data.md)）と同じ位置である。
- `name` が null で `line` が null でない応答は、不正な応答（G06009）とする。行を数えるファイルがないからである。
- `name` が文字列のときは、今と同じである。渡していない名前の応答は G06009 とする。[docs/adr/0120](0120-plugin-data-check-at-load.md) の「宣言にない名前」は、この「渡していない名前」と読む。
- `code`、`severity`、エラーのときに読み込みの誤りとして扱うことは、[docs/adr/0120](0120-plugin-data-check-at-load.md) のとおりである。

ABI のバージョンは 8 のままとする。
8 はまだリリースしておらず（v0.1.0-rc3 は 7）、[docs/adr/0052](0052-plugin-abi-version-bump-rule.md) のとおり、リリースしていないバージョンは上げない。
`name` に null を返さないプラグインは、変えずに動く。

### 見本のプラグイン

必須のデータがないことを、`golem_check_data` で `name` を null にして報告する。

| プラグイン | 条件 | コード | メッセージ |
| --- | --- | --- | --- |
| `glossary` | `terms` を渡していない | `no-data` | `manifest.toml で data の terms を渡してください` |
| `sou-ruby` | `words` も辞書も渡していない | `sou-ruby-no-words` | `manifest.toml の data で words を渡してください` |
| `first-ruby` | `words` を渡していない | `first-ruby-no-words` | `manifest.toml の data で words を渡してください` |

コードとメッセージは、今の呼び出しのときのものと同じにする。
ルビの二つの見本のコードの前置き（監査の F-38）を別の変更が直すときは、その形に従う。

- `sou-ruby` と `first-ruby` は、今は `golem_check_data` を公開していない。`export_plugin!` に三つめの関数を渡して公開する。
- 呼び出しのときの `no-data` と `no-words` は残す。`golem_check_data` を呼ばないホストのためである（用語集の見本の今のコメントと同じ扱い）。Golem のホストでは、読み込みの誤りになったプラグインは呼ばれないので、二重には出ない。
- 補助のクレート `golem-plugin-sdk` の `DataDiagnostic` の `name` を `Option<String>` にする。

### ホスト

- golem-plugin は、`data-diagnostic` の `name` の null を読む。`DataDiagnostic` の `ddName` を `Maybe Text` にする。
- golem-driver の `located` は、`name` が null なら `manifest.toml` の先頭に置き、`line` も持つなら G06009 とする。

### 文書

- docs/specifications.md の `golem_check_data` の節、golem-doc の CDDL、manual-dev の 05-plugins.gm の `golem_check_data` の段落に、null の `name` を足す。
- docs/specifications.md の三つの見本の節に、データがないときのエラーが読み込みのときに一度だけ出ることを書く。
- docs/diagnostics.md の G06009 の節に、`name` が null で `line` があるときの理由の文言を足す。
- [docs/adr/0120](0120-plugin-data-check-at-load.md) のステータスの行に、「`name` の null と、宣言にない名前の読み方は [ADR 0136](0136-missing-plugin-data-at-load.md)」を足す。

## 実装しないこと

- `golem_describe` に必須のデータを宣言する欄を設け、ホストが渡されていないことを報告すること。下の「検討した案」を参照。
- `sou-ruby` と `first-ruby` の `words` の TSV の誤りを `golem_check_data` に移すこと。今はフィルタを当てたファイルの数だけ同じ誤りが出る（[docs/adr/0131](0131-first-occurrence-ruby-plugin.md) が「ファイルの数だけ重ねて報告される」と記録した）。移せば一度だけ TSV の行の位置に出せるが、`sou-ruby` の辞書の検査も読み込みに移すかどうかと合わせて、別に決める。
- `tsv-table` と `bar-chart` の `no-data`。どちらも `*` のプラグインで、どの名前が要るかは呼び出しの引数で決まる。呼び出しのときにしか判定できない。
- `name` が null の diagnostic の位置を、`manifest.toml` の `[plugins.<名前>]` の行にすること。今のマニフェストの diagnostic は、どれもファイルの先頭に出す。行を指す仕組みを入れるなら、マニフェストの diagnostic の全体で決める。

## テスト設計

先に次のテストを書き、今の main で失敗することを確かめてから実装する。

golem-plugin の `CheckDataSpec` では、次のことを確かめる。

- `name` が null で `line` が null の応答が、名前のない `DataDiagnostic` に復号される。
- `name` が null で `line` が数の応答が、不正な応答になる。

golem-driver の `PluginsSpec` では、wat のテスト用のプラグインで次のことを確かめる。

- `golem_check_data` が `name` を null にしたエラーを返すと、`manifest.toml` の先頭に `<宣言名>/<コード>` のエラーが一つ出て、コマンドが呼ばれず、G02022 が出ない。
- `name` が null で `line` を持つ応答が、G06009 になる。

見本のプラグインでは、次のことを確かめる。

- Rust の単体テストで、`glossary` の `check_data` が `terms` のないデータに `no-data` を一つ返し、`sou-ruby` は `words` も辞書もないデータに、`first-ruby` は `words` のないデータに `no-words` を一つ返す。今の `glossary` のテスト（`check_data(&terms(None))` が空）は、この期待に改める。
- golem-driver の `PluginsSpec` で、`data` を書かずに `glossary` を宣言した本が、`[term]` を書かなくても `manifest.toml` の先頭に `glossary/no-data` を一つ出す。`[term]` を三つ書いた本でも一つである。
- golem-driver の `PluginsSpec` で、`words` を渡さずに `first-ruby` を二つのファイルに当てた本が、`no-words` を一つだけ出す。

## トレードオフ

`data-diagnostic` の形が一つ広がる。
`name` が null の diagnostic は行を持てないので、組み合わせの一つを不正な応答として拒む規則が増える。
ABI 8 はまだリリースしていないので、広げる費用は今がいちばん小さい。

データがないプラグインは、読み込みの誤りになり、そのプラグインのコマンドとフィルタは一つも動かない。
今は、データを要しないコマンドや、データがなくても動く呼び出しがあれば、それは動く。
三つの見本には、データなしで意味のある呼び出しはない。
データの有無で一部だけ動くプラグインを書くときは、`severity` を警告にすれば読み込まれる。

### 検討した案

- **今のまま（呼び出しのときに報告）**：ABI を変えない。しかし、コマンドを書いていない本ではデータの欠けが見えず、フィルタでは同じエラーがファイルの数だけ出る。[docs/adr/0120](0120-plugin-data-check-at-load.md) の動機と同じ問題が残る。採らない。
- **`golem_describe` に必須のデータを宣言し、ホストが検査する**：プラグインのコードなしに、ホストが G06101 などと並ぶコードで報告できる。しかし `sou-ruby` の条件は「`words` か辞書のどちらか」で、名前ごとの必須では書けない。`*` のプラグインも、どの名前が必須かを宣言できない。条件の形をホストの宣言に持ち込むと、プラグインごとの規則がホストに漏れる。採らない。
- **`name` に `manifest.toml` を表す特別な名前（`""` など）を書く**：CDDL の型を変えずに済むが、データの名前の空間に予約語を作る。null は「名前がない」をそのまま表す。採らない。

## 決めたことの記録

- **採択**：メンテナーが、この ADR の案のとおり採択した（2026-11-04）。

## 参考文献

- [docs/audits/2026-11-04-rc4-plugin-adr-conformance.md](../audits/2026-11-04-rc4-plugin-adr-conformance.md)（F-21）
