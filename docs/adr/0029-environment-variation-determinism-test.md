# ADR 0029: 実行環境を変えて出力の一致を確かめる検査

ステータス: 採択→CI で `--quick` を付けるかどうかは [ADR 0038](0038-env-determinism-quick-on-pull-requests.md)

## 文脈

[ADR 0002](0002-determinism.md) は、環境変数、ロケール、タイムゾーンを出力に影響させないと定め、`SOURCE_DATE_EPOCH` も読まないと定めている。
同じ ADR のテスト設計には、`TZ`、`LANG`、`SOURCE_DATE_EPOCH` を変えてビルドしても出力が変わらないことを検査すると書いてある。
しかし、この検査はまだどこにもない。

今ある決定性の検査は三つである。

- CI の `determinism` ジョブは、`scripts/determinism.sh` の出力のハッシュを x86-64 と aarch64 で比べる。二つのランナーの環境変数とロケールはほぼ同じなので、環境の違いはこの比較に現れない。
- golem-driver のテストは、同じ入力を二回組んだ結果と、並列と逐次で組んだ結果を、プロセスの中で比べる。どちらも同じプロセスの同じ環境で組む。
- リリースのワークフローは、三つの配布物と CI のビルドの出力のハッシュを比べる（[ADR 0004](0004-binary-distribution-and-release.md)）。

どれも、時計、ロケール、パス、ファイルの時刻のような実行の環境を、意図して変えていない。
それでも開発者向けのマニュアルは、第 12 章「決定性を守る」の「確かめ方」で、環境変数を変えたビルドの比較が行われているかのように書いている。

検査がないことの実害は、すでに一つ見えている。
golem-driver は、テキストの出力を `Data.Text.IO.writeFile` で書いている。
この関数はロケールの文字コードで符号化するので、`LANG=C` では日本語を含む出力で失敗し、`ja_JP.eucJP` では EUC-JP のバイト列を書く。
この不具合は、別の変更で単体のテスト（EUC-JP のロケールでの書き出し）とともに直している。
この ADR は、その個別の修正とは別に、同じ種類の漏れを系統的に見つける検査を定める。

漏れの経路はロケールのほかにもある。
golem-plugin はプラグインのキャッシュの場所を `XDG_CACHE_HOME`（なければ `HOME`）から決める。
診断の JSON はファイルのパスを含むので、プロジェクトを置いた絶対パスが入り込む余地がある。
ディレクトリの列挙で入力を決めないという規則は、入力と関係のないファイルを置いて組まない限り確かめられない。

## 実装すること

### 検査の形

シェルスクリプト `scripts/env-determinism/check.sh` を新しく置く。
スクリプトは、決まった入力を「基準の環境」で組み、続けて「変えた環境」で組み、二つの結果を比べる。
一つでも違えば、違った変化の名前と違ったファイルを表示して、終了コード 1 で終わる。

```
GOLEM=/path/to/golem sh scripts/env-determinism/check.sh [--quick]
```

`golem` は絶対パスで渡す。
`PATH` を変える変化があるので、`PATH` から `golem` を探さない。

golem-cli のテストスイートの中にプロセスを起こすテストとして書く案は採らない。
入力にマニュアルのフォントや十冊の公有の本を含めると、`cabal test` のたびに数分かかるからである。
検査は `scripts/determinism.sh` と同じく、組み上がった `golem` を外から呼ぶ小さな道具にする。
`scripts/determinism.sh` には手を入れない。
あちらはアーキテクチャの間の比較のためにハッシュの一覧を出す道具であり、環境を変えて比べる役目を足すと、一つのスクリプトが二つの目的を持つことになる。

### 比べるもの

一回のビルドにつき、次のものを一つの一覧にして、基準の一覧と `diff` で比べる。

- `build/` の下のすべてのファイルの、プロジェクトルートからの相対パスと SHA-256
- 終了コード
- 標準出力の SHA-256
- 標準エラー出力の SHA-256（診断は `--format json` で出す）

ビルドは `golem build --format json` とし、`--target` を付けない。
[golem-cli ADR 0002](../golem-cli/adr/0002-build-all-targets-by-default.md) により、マニフェストの持つすべてのターゲット（PDF、HTML、EPUB、テキスト）を組む。
ファイルの権限と時刻は比べない。
比べるのは中身のバイト列だけである。

EPUB も比べる対象に入れる。
[ADR 0002](0002-determinism.md) は v1 で EPUB の決定性を保証しないと定めているが、今の golem-epub は zip のエントリの時刻を 0 に固定して決まった順に並べており、`determinism` ジョブも EPUB のハッシュを二つのアーキテクチャで比べて通っている。
この検査で EPUB が環境によって変われば、それは時計やロケールの漏れであり、zip の仕様の揺れではない。
この検査で EPUB を比べることは、v1 の EPUB に事実上の決定性を求めることになる。
それでも、仕様としての約束は変えない。
`docs/specifications.md` は EPUB の決定性を v2 から保証するとしたままにし、v2 の項目の一覧（その時点で `docs/roadmap.md` が main にあればそちら）にも EPUB の決定性の項目を残す。
検査は今から EPUB に対して動き、仕様の約束は v2 から始まる。
この区別は、`docs/specifications.md` と開発者向けのマニュアルにも明記する。

### 入力

入力は次のプロジェクトとする。

| 名前 | 場所 | 主に確かめること |
| --- | --- | --- |
| `exprs` | `scripts/determinism/` | 式の評価と数の表記 |
| `sample` | `modules/golem-driver/test/fixtures/sample/` | HTML、EPUB、テキスト |
| `sample-pdf` | `sample` に golem-font のテスト用フォントと `scripts/determinism/pdf-style.toml` を加えたもの | PDF |
| `diagnostics` | `scripts/env-determinism/diagnostics/`（新しく置く） | 診断の JSON |
| `tempest` | `modules/golem-driver/test/fixtures/tempest/` | 横組みの一冊 |
| `kanikosen` | `modules/golem-driver/test/fixtures/kanikosen/` | 縦組みの一冊 |
| 十冊の公有の本 | `modules/golem-driver/test/fixtures/pd/*/` | [ADR 0026](0026-ten-public-domain-fixtures.md) の難所 |
| 二つのマニュアル | `manual/`、`manual-dev/` | 実際の本の規模の全機能 |

`sample-pdf` の作り方は `scripts/determinism.sh` と同じにする。
十冊の公有の本はフォントをコミットしていないので、`scripts/fixtures/copy-fonts.sh` と同じ規則で、『テンペスト』と『蟹工船』のフォントを写してから組む。
二つのマニュアルは、`scripts/manual/fetch-fonts.sh` で取得したフォントがあるときだけ入力にする。
フォントを必須にするかどうかは、専用の環境変数 `GOLEM_REQUIRE_FONTS` で決める。

- `GOLEM_REQUIRE_FONTS=1` のとき、マニュアルのフォントが一つでも見つからなければ、ほかの入力を検査した後に終了コード 1 で終わり、見つからなかったフォントのファイルの名前とそれを使うマニュアルを表示する。
- 変数がないとき、または `1` 以外の値のときは、フォントの欠けたマニュアルを `SKIP` と表示し、残りの結果だけで終了コードを決める。

`GOLEM_REQUIRE_EXTERNAL_TOOLS`（[ADR 0028](0028-shared-test-support-package.md)）は流用しない。
あちらは実行ファイルの有無を扱う変数であり、取得のスクリプトで置くフォントとは用意の手順が違う。
CI は `GOLEM_REQUIRE_FONTS=1` を付けて実行する。
マニュアルの奥付が読む `common/build-info.gm` は、基準の環境で `scripts/manual/build-info.sh` を一度だけ実行して作り、各変化にはその結果を写す。
図版は、リポジトリにコミットしたもの（開発者のマニュアルでは、文字を輪郭にした SVG）をそのまま使う。

`diagnostics` は、警告とエラーをそれぞれ一つ以上出し、関連する位置（`related`）を持つ診断を含む小さなプロジェクトである。
章のファイルを `chapters/` の下に置き、診断の `file` にディレクトリを含む相対パスが出るようにする。
このプロジェクトのビルドはエラーで終わるので、終了コードの一致も比べる。

### 基準の環境

基準の環境では、`env -i` で環境変数を空にしてから次の値だけを与える。

- `PATH=/usr/bin:/bin`
- `HOME` に作業用の一時ディレクトリの下の `home-a`
- `LANG=C.UTF-8`、`LC_ALL` は与えない
- `TZ=UTC`
- `umask 022`

各プロジェクトは、作業用の一時ディレクトリの下の `base/<名前>/` に写してから組む。
写すときに `cp -R` を使い、ファイルの時刻は写した時刻のままにする。

### 一つずつ変える変化

次の変化を、基準の環境から一つずつ変えて適用する。

| 名前 | 変えるもの |
| --- | --- |
| `tz-east` | `TZ=Pacific/Kiritimati`（UTC+14） |
| `tz-west` | `TZ=Etc/GMT+12`（UTC-12） |
| `tz-unset` | `TZ` を与えない |
| `locale-c` | `LANG=C`、`LC_ALL=C`（ASCII） |
| `locale-eucjp` | `LC_ALL` に EUC-JP の日本語ロケール |
| `locale-ja` | `LC_ALL` に UTF-8 の日本語ロケール（照合の順序が C と異なる） |
| `locale-unset` | `LANG` と `LC_*` をどれも与えない |
| `sde-zero` | `SOURCE_DATE_EPOCH=0` |
| `sde-future` | `SOURCE_DATE_EPOCH=4102444800`（2100-01-01） |
| `home-other` | `HOME` に `home-b` |
| `home-unset` | `HOME` を与えない |
| `xdg` | `XDG_CACHE_HOME`、`XDG_CONFIG_HOME`、`XDG_DATA_HOME` に空のディレクトリ |
| `path-empty` | `PATH=/nonexistent` |
| `umask` | `umask 077` |
| `root-path` | プロジェクトを `空白 と 日本語/深い/階層/<名前>/` に写す |
| `mtime-past` | 入力のすべてのファイルの時刻を 1970-01-02 にする |
| `mtime-future` | 入力のすべてのファイルの時刻を 2099-12-31 にする |
| `decoys` | 入力のどこからも参照しないファイルを置き、写す順を逆にする |

`decoys` で置くファイルは、プロジェクトルートの `zz-unused.gm`、`chapters/` があればその下の `aa-unused.gm`、`images/` があればその下の `unused.png`、`fonts/` があればその下の `unused.otf`（中身は空でない任意のバイト列）とする。
組んだ結果が変われば、Golem がディレクトリの内容を列挙して入力を決めていることになる。

ロケールの名前はシステムで異なる（Linux の `ja_JP.eucjp` と macOS の `ja_JP.eucJP` など）。
スクリプトは `locale -a` の結果から候補の名前を順に探し、見つからなければその変化を `SKIP` と表示する。
ロケールを必須にするかどうかは、専用の環境変数 `GOLEM_REQUIRE_LOCALES` で決める。

- `GOLEM_REQUIRE_LOCALES=1` のとき、ロケールの変化に必要なロケールが一つでも見つからなければ、ほかの変化を実行した後に終了コード 1 で終わり、見つからなかった変化とロケールの候補の名前を表示する。
- 変数がないとき、または `1` 以外の値のときは、見つからなかった変化を `SKIP` と表示し、残りの結果だけで終了コードを決める。
- `combined` は、EUC-JP のロケールがないときに `C` で代える。`GOLEM_REQUIRE_LOCALES=1` のときは代えずに失敗にする。

`GOLEM_REQUIRE_EXTERNAL_TOOLS` は流用しない。
あちらは `cddl` や `qpdf` のような実行ファイルの有無を扱う変数であり、システムのロケールの有無とは用意の手順も直し方も違う。
CI は `GOLEM_REQUIRE_LOCALES=1` を付けて実行する。

### すべてを同時に変える変化

一つずつの変化を、すべての入力で組むと時間がかかりすぎる。
そこで、一つずつの変化は小さな入力（`exprs`、`sample`、`sample-pdf`、`diagnostics`）だけに適用する。
大きな入力（`tempest`、`kanikosen`、十冊、二つのマニュアル）には、次の変化をすべて同時に適用した `combined` を一回だけ適用する。

- `TZ=Pacific/Kiritimati`
- `LC_ALL` に EUC-JP の日本語ロケール（なければ `C`）
- `SOURCE_DATE_EPOCH=0`
- `HOME` に `home-b`、`XDG_*` に空のディレクトリ
- `PATH=/nonexistent`
- `umask 077`
- `root-path` の置き場所、`mtime-past` の時刻、`decoys` のファイル

`combined` は小さな入力にも適用する。
`combined` だけが失敗したときは、どの変化が原因かを、小さな入力での一つずつの結果から絞り込む。
大きな入力でだけ現れる漏れ（たとえば特定の機能の経路だけが時計を読む）の原因を絞るには、手元で一つずつの変化を大きな入力に適用する。
そのために `check.sh` は、`--only 名前` で変化を、`--input 名前` で入力を絞る選択肢を持つ。

`--quick` を付けると、大きな入力を飛ばす。
手元で数秒で回すためのものであり、CI では付けない。

### SOURCE_DATE_EPOCH の扱い

reproducible-builds.org の仕様は、ビルドの道具が `SOURCE_DATE_EPOCH` を読み、現在の時刻の代わりに使うことを求めている。
Golem はこれに従わず、[ADR 0002](0002-determinism.md) のとおり、成果物の日時をマニフェストの `metadata.date` だけから作る。
したがって、`SOURCE_DATE_EPOCH` を与えても出力は一つも変わらないことを、この検査で確かめる。
仕様が想定する用途（時計の値を固定する）は、Golem では時計を読まないことで最初から満たされている。

### 変化で出力が変わったとき

どの変化でも、どの入力でも、基準と一致しなければ検査は失敗する。
許容の一覧や、変わってよいファイルの除外は設けない。
失敗したら、その変化を出力に流している経路を直す。
その経路が入力の一覧に加えるべきもの（たとえば出力を変える新しいオプション）であれば、[ADR 0002](0002-determinism.md) を改める ADR を書く。

### CI

`.github/workflows/ci.yml` の `build` ジョブの x86-64 のランナー（`ubuntu-24.04`）に、`scripts/determinism.sh` の後で次のステップを足す。

1. `sudo locale-gen ja_JP.UTF-8 ja_JP.EUC-JP` で日本語のロケールを作る。
2. `GOLEM_REQUIRE_LOCALES=1 GOLEM_REQUIRE_FONTS=1 GOLEM="$(cabal list-bin -v0 golem)" sh scripts/env-determinism/check.sh` を実行する。

aarch64 のランナーでは実行しない。
環境の変化は二つのアーキテクチャで同じ経路を通るので、一つで足りる。
マニュアルのフォントは、同じジョブの前のステップがキャッシュから置いている。

ジョブを別に立てる案は採らない。
`build` ジョブは `golem` の実行ファイルを成果物として上げていないので、別のジョブにすると、実行ファイルの受け渡しを新しく作る必要がある。

`scripts/env-determinism/test.sh`（次の節）は、`changes` ジョブで `scripts/ci/test.sh` と並べて実行する。

### 文書

- 開発者向けのマニュアルの第 12 章「決定性を守る」の「確かめ方」を、この検査に合わせて書き直す。今の「環境変数（TZ、LANG、SOURCE_DATE_EPOCH）を変えてビルドしても、出力が変わらないことを確かめる」は、存在しない検査を指している。書き直した後は、`check.sh` の名前、変える条件の一覧（一つずつの変化と `combined`）、入力の分け方、手元での `--quick` と `--only` の使い方を書く。
- 純粋性の章（`manual-dev/part2/12-purity.gm`、まだ main にない）が入るときは、環境変数を変えて手で比べる例を、`check.sh` を呼ぶ例に置き換える。
- 第 11 章「CI のジョブ」の `build` の手順に、この検査のステップを足す。
- `docs/specifications.md` の決定性の節に、実行の環境を変えて比べる検査があることを、この ADR へのリンクとともに書く。
- README の CI の表の `build` の説明に、この検査を加える。

## 実装しないこと

- 時計そのものを変えること。プロセスの見る時刻をずらすには libfaketime のような `LD_PRELOAD` の道具が要るが、GHC の実行時システムは vDSO 経由で時刻を読むことがあり、確実にずらせる保証がない。時計を読まないことは、`SOURCE_DATE_EPOCH` と `TZ` の変化と、コードレビューで守る。
- ファイルシステムの列挙の順そのものを変えること。disorderfs のような FUSE の道具は CI のランナーで特権を要する。`decoys` で、列挙に頼れば結果が変わる状況を作ることで代える。
- capability の数（`+RTS -N`）を変えること。`golem` の実行ファイルは `-threaded` だが `-rtsopts` を持たず、`-N` も指定していないので、capability は常に一つである。並列と逐次の一致は、golem-driver のテストがプロセスの中で確かめている。`-N` を有効にするときは、この検査に capability の数の変化を足す ADR を書く。
- プラグインを使う入力。プラグインのキャッシュの場所は `XDG_CACHE_HOME` で変わるが、読んだ中身は `plugins.lock` のハッシュで照合される。キャッシュを用意した入力は golem-cli のテストが扱っている。
- ユーザーとグループ、ホスト名、カーネルの版を変えること。Golem はこれらを読む API を使っておらず、変えるには特権かコンテナが要る。
- `golem fmt`、`golem preflight`、`golem inspect`、LSP の出力。この ADR は `golem build` の出力に限る。
- macOS と Windows のランナーでの実行。CI は Linux だけで実行する。スクリプトは macOS の手元でも動くように書く。
- [ADR 0002](0002-determinism.md) の保証の範囲（v1 の EPUB）を変えること。

## テスト設計

### check.sh が漏れを見つけること

`scripts/env-determinism/test.sh` で、`check.sh` 自身を検査する。
`golem` の代わりに、偽のシェルスクリプトを `GOLEM` に渡す。
偽の `golem` は、引数を無視して `build/` の下にファイルを一つ書き、終了コード 0 で終わる。
書く内容を変えて、各変化が実際に適用されていることを確かめる。

- 決まった文字列だけを書く偽物では、`check.sh --quick` が終了コード 0 で終わる。
- 次の値をそれぞれ書く偽物では、`check.sh --quick` が終了コード 1 で終わり、対応する変化の名前を表示する。
  - `$TZ` の値：`tz-east`、`tz-west`、`tz-unset`
  - `locale` の出力：`locale-c`、`locale-eucjp`、`locale-ja`、`locale-unset`
  - `$SOURCE_DATE_EPOCH` の値：`sde-zero`、`sde-future`
  - `$HOME` の値：`home-other`、`home-unset`
  - `$XDG_CACHE_HOME` の値：`xdg`
  - `$PATH` の値：`path-empty`
  - `umask` の出力：`umask`
  - `pwd` の出力：`root-path`
  - `manifest.toml` の時刻：`mtime-past`、`mtime-future`
  - プロジェクトルートの `ls` の出力：`decoys`
- 標準エラー出力に `$TZ` を書く偽物では失敗し、違いが標準エラー出力にあると表示する。
- `$TZ` が `UTC` でないときだけ終了コード 1 で終わる偽物では失敗し、違いが終了コードにあると表示する。
- `build/` の下に、変化のときだけ余分なファイルを書く偽物では失敗し、そのファイルの名前を表示する。
- 存在しないロケールの候補だけを与えたときは、`SKIP` と表示して終了コード 0 で終わり、`GOLEM_REQUIRE_LOCALES=1` のときは終了コード 1 で終わる。`GOLEM_REQUIRE_LOCALES=0` と `GOLEM_REQUIRE_LOCALES=yes` は、変数がないときと同じく `SKIP` で終わる。`GOLEM_REQUIRE_EXTERNAL_TOOLS=1` だけを与えたときも `SKIP` で終わる。
- マニュアルのフォントを置いていない木で `check.sh` を実行したときは、マニュアルを `SKIP` と表示して終了コード 0 で終わり、`GOLEM_REQUIRE_FONTS=1` のときは終了コード 1 で終わって、欠けたフォントのファイルの名前を表示する。`check.sh` はリポジトリの根を自身の場所から決めるので、テストは `scripts/env-determinism/` と入力のプロジェクトを一時ディレクトリに写し、`manual/fonts/` と `manual-dev/fonts/` を写さずにこの状況を作る。`GOLEM_REQUIRE_FONTS=0` と `GOLEM_REQUIRE_FONTS=yes` は `SKIP` で終わる。`GOLEM_REQUIRE_EXTERNAL_TOOLS=1` だけ、または `GOLEM_REQUIRE_LOCALES=1` だけを与えたときも `SKIP` で終わる。
- 逆に、ロケールの欠けは `GOLEM_REQUIRE_FONTS=1` だけでは失敗にならない。二つの変数が互いに独立していることを確かめる。

偽の `golem` はシェルスクリプトなので、`PATH=/nonexistent` のもとでも動くように `#!/bin/sh` の絶対パスで書き、外部のコマンドは `/bin` と `/usr/bin` の絶対パスで呼ぶ。

このテストを先に書き、`check.sh` がない状態で失敗することを確かめてから `check.sh` を書く。

### 実際の golem での確かめ

本物の `golem` での検査は、CI の `build` ジョブのステップそのものである。
実装のプルリクエストで、次のことを確かめる。

- ロケールの漏れ（`Data.Text.IO.writeFile`）を直す変更が main に入る前の `golem` では、`locale-c` か `locale-eucjp` で失敗する。直した後の `golem` では、すべての変化が通る。直す変更が先に main に入っている場合は、手元で `writeFile` をロケール依存の書き方に戻した `golem` を作り、失敗することを確かめてから戻す。
- CI のログで、一つずつの変化とすべての入力（二つのマニュアルを含む）が `SKIP` なしに実行されたことを確かめる。
- 追加のステップの所要時間を記録する。CI の所要時間の上限は、この ADR では決めず、`CONTRIBUTING.md` の開発の約束（CI が 5 分を超えたら CI を速くする）に従う。この検査を足して上限を超えたときは、その約束に従って速くする。入力の分け方（一つずつの変化を当てる入力と `combined` だけを当てる入力）は、そのときの調整の対象になる。

## トレードオフ

大きな入力には、すべての変化を同時に適用した `combined` しか適用しない。
このため、大きな入力でだけ現れる漏れは、どの変化が原因かを CI のログだけでは特定できない。
すべての組み合わせを組めば特定できるが、入力の十八のプロジェクトを十九回ずつ組むことになり、CI の時間が数十分延びる。
原因の特定は手元の `--only` と `--input` に任せ、CI は漏れの有無だけを確実に知らせる形を選ぶ。

時計とファイルの列挙の順は、直接は変えていない。
これらは環境の変化の中で最も漏れやすいものに入るが、変える道具が特権や `LD_PRELOAD` を要し、CI のランナーで安定して動かせない。
`decoys` と `SOURCE_DATE_EPOCH` は、それぞれの漏れの典型的な形を捕まえるが、すべてを捕まえる保証はない。

検査をシェルスクリプトにしたので、`cabal test` では実行されない。
手元で変更を試すときは、`check.sh --quick` を別に実行する必要がある。
その代わり、`cabal test` の所要時間は変わらず、検査は組み上がった実行ファイルという、利用者が動かすものと同じ対象を調べる。

EPUB を比べる対象に入れたので、v1 では保証していない EPUB の揺れで検査が失敗する可能性がある。
その場合は、揺れが環境に由来するかどうかを調べる。
環境に由来しない揺れであれば、EPUB の決定性を v2 の約束より前に検査することをやめるか、揺れを直すかを決める ADR を書く。

Debian の reprotest は、同じ考え方の変化（環境変数、ビルドのパス、ファイルの時刻、umask、ロケール、タイムゾーン、ホームディレクトリ）をまとめて提供している。
これを使えば自前のスクリプトは要らないが、reprotest は Python で書かれ、ビルドの手順をパッケージの単位で扱う前提にある。
Golem に必要な変化は十数個の `env` と `cp` と `touch` で表せるので、必要な分だけをシェルスクリプトで書く。

## 参考文献

- [ADR 0002: 決定性の規則](0002-determinism.md)
- [ADR 0026: 組みにくい公有の作品を fixture に十作加える](0026-ten-public-domain-fixtures.md)
- [ADR 0028: テストの補助を共有するパッケージ](0028-shared-test-support-package.md)
- [golem-cli ADR 0002](../golem-cli/adr/0002-build-all-targets-by-default.md)
- Reproducible Builds, "SOURCE_DATE_EPOCH specification", https://reproducible-builds.org/specs/source-date-epoch/
- Reproducible Builds, "Timestamps", https://reproducible-builds.org/docs/timestamps/
- Reproducible Builds, "Timezones", https://reproducible-builds.org/docs/timezones/
- Reproducible Builds, "Locales", https://reproducible-builds.org/docs/locales/
- Reproducible Builds, "Stable order for inputs", https://reproducible-builds.org/docs/stable-inputs/
- Reproducible Builds, "Build path", https://reproducible-builds.org/docs/build-path/
- reprotest, https://salsa.debian.org/reproducible-builds/reprotest
- disorderfs, https://salsa.debian.org/reproducible-builds/disorderfs
- GHC, `GHC.IO.Encoding`（`getLocaleEncoding`）, https://hackage.haskell.org/package/base/docs/GHC-IO-Encoding.html
