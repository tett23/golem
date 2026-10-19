# セキュリティ監査（2026-10-18、rc3）

この記録は、2026-10-18 の main（a2b6106e）の Golem を、v0.1.0-rc3 の前に監査した結果である。
[docs/adr/0035](../adr/0035-security-hardening.md) が、`v` で始まるタグのリリースの前に毎回の監査を求めている。
前回の記録は [2026-10-17 のセキュリティ監査](2026-10-17-security-audit.md) で、脅威のモデルと重大度の決め方はそれに従う。
今回は、前回の後に増えた入力（PDF と SVG の図版の取り込み、表のファイル）と、前回の記録が触れなかった計算量の問題を中心に調べた。

この記録は問題を記録するだけで、修正はしない。
再現したテストは、ブランチ `security-audit-rc3-tests`（コミット 090b0410）にある。
テストはどれも、小さな敵対的な入力を読む時間と割り当てを限り、diagnostic で拒むか限界の中で読めることを求める。
main ではすべて失敗する。
仕様を変える修正は ADR の草稿にし、メンテナーのレビューを待つ。

## 重大度の決め方

前回と同じである。

- **高**：ビルドするだけで、プロジェクトの外のファイルが消えるか書き換わる。
- **中**：ビルドするだけで、Golem が止まらなくなるか落ちる、出力を読む人の環境でスクリプトが動く、またはサンドボックスの上限を越えられる。
- **低**：悪用に別の条件が要るか、被害が小さい。
- **情報**：今は問題にならないが、前提が変わると問題になる。

図版の PDF と SVG は、原稿のリポジトリに置かれるファイルであり、clone してビルドするだけで Golem に届く。
これらで Golem が止まらなくなるか、数 GB のメモリを使うものは、前回と同じく中とした。
時間とメモリの測定は Apple Silicon のマシンで行い、`GHC.Stats` の割り当てたバイト数と、プロセスの RSS を使った。

## 見つかった問題

テストで再現した問題（C）、ADR の草稿で扱う問題（C12）、コードを読んで見つけた CI の問題（CI）、ふつうの大きな入力で起きる資源の問題（T）に分けて書く。
「再現」の列は、テストの名前（ブランチ `security-audit-rc3-tests`）か、測定の結果である。

### 再現した問題

| 番号 | 重大度 | 問題 | 場所 | 再現 | 状態 |
| --- | --- | --- | --- | --- | --- |
| C1 | 中 | PDF のページの木が DAG だと、葉の数が深さの指数で増える | golem-pdf `Import.pageLeaves` | golem-pdf SecuritySpec「C1: a page tree that is a DAG of depth 24 …」。深さ 24 で 5 秒の制限を超え、RSS 2.96 GB | ADR 草稿 |
| C2 | 中 | リテラル文字列の短い 8 進エスケープで、読み込みが二乗の時間になる | golem-pdf `Import.literal` | 「C2: a literal string of 50000 short octal escapes …」。150 KB で 3.79 GB を割り当てる | 未修正（ADR なしで直す） |
| C3 | 中 | 一つのストリームを `Contents` で何度も名指しすると、上限が倍数で越えられる | golem-pdf `Import.pageContent`、`objectUses` | 「C3: one stream of 8 MiB named 40 times in Contents …」。320 MiB の内容を受け付け、6.4 GB を割り当てる | ADR 草稿 |
| C4 | 中 | TIFF の予測子の `Colors` が大きいと、行の処理が `Colors` に比例して遅くなる | golem-pdf `Import.predict`（`tiffRow`） | 「C4: the TIFF predictor with Colors 65536 …」。1 MiB で 10 秒の制限を超える | ADR 草稿 |
| C5 | 中 | Flate の後の ASCII85 に展開の上限がない | golem-pdf `Import.ascii85`、`decodeWith` | 「C5: Flate then ASCII85 of 80 MiB of z …」。320 MiB に展開し、RSS 6 GB、11 秒から 15 秒 | ADR 草稿 |
| C6 | 中 | 同じ相互参照ストリームを複数の改訂が名指しすると、そのたびに読み直す | golem-pdf `readXref`（`chain`）、`xrefRows` | 「C6: a cross-reference stream of 4 million rows named by 4 revisions …」。29.7 GB を割り当て、6 秒 | ADR 草稿 |
| C7 | 中 | 内容のストリームの小さなトークンの列で、割り当てが入力の百倍を超える | golem-pdf `scanContent`、`rewriteContent` | 「C7: a content stream of 16 MiB of tiny tokens …」。2 GB を割り当て、RSS 2.78 GB | ADR 草稿 |
| C8 | 中 | SVG の `marker` の自己参照と深い入れ子で止まらない | golem-svg `markers`、`placeMarker` | 「C8: a marker that refers to itself …」と「C8: markers nested 14 deep …」。どちらも 5 秒の制限を超える | ADR 草稿 |
| C9 | 中 | XML の実体参照、CSS のコメント、コメントで分かれた文字の結合が二乗の時間になる | golem-svg `Xml.references`、`Css.stripComments`、`Xml.text` | 「C9: …」の三つ。入力を 2 倍にすると割り当てが 3.5 倍から 4 倍になる | 未修正（ADR なしで直す） |
| C10 | 中 | 属性の重なりの検査が属性の数の二乗になる | golem-svg `Xml.attributes` | 「C10: an element of many attributes …」。2 万の属性で 1.13 秒、4 万で 4.68 秒 | 未修正（ADR なしで直す） |
| C11 | 中 | `1e9999` のような数を受け付け、円弧の計算が止まらず、PDF に 1 万桁の数を書く | golem-svg `Number.numberPrefix`、`sqrtR`、`Svg.arc`、golem-pdf `Drawing.fixed` | 「C11: six arcs with radii of 1e9999 …」（150 バイトで制限を超える）と「C11: a width of 1e9999 …」（そのまま書かれる） | ADR 草稿 |
| C13 | 低 | diagnostic の人間向けの描画が、パス、メッセージ、ソース行の制御文字をそのまま端末に書く | golem-syntax `Render.renderHuman` | golem-syntax RenderSpec「the human rendering and the terminal」の二つ | ADR 草稿 |
| C14 | 低 | 表のファイルの名前の `*`、`?`、`{`、`[` を、エスケープせずに glob として登録する | golem-lsp `Server.syncWatches` | golem-lsp TableWatchSpec「a table file named with * and ? is watched as that file, not as a glob」 | ADR 草稿 |
| C15 | 低 | XML 1.0 で許されない C0 制御文字が、XMP、OPF、nav に通る | golem-pdf `X4.escapeXml`、golem-html `Html.escapeXml` | golem-pdf SecuritySpec「C15: a control character in the title …」、golem-epub PackageSpec「a control character in the metadata …」 | ADR 草稿 |

### ADR の草稿で扱う問題

| 番号 | 重大度 | 問題 | 場所 | 再現 | 状態 |
| --- | --- | --- | --- | --- | --- |
| C12 | 中 | HTML と EPUB に写す SVG の図版の `script` などの動く中身を検査しない | golem-driver の HTML と EPUB のターゲット | コードを読んで確かめた。[golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) が検査しないと決めている | ADR 草稿（G0814。XML として読めない SVG も止める） |

### コードを読んで見つけた CI とリリースの問題

| 番号 | 重大度 | 問題 | 場所 | 再現 | 状態 |
| --- | --- | --- | --- | --- | --- |
| CI1 | 中 | `release` ジョブが `@anthropic-ai/claude-code` をバージョンを固定せずに入れる | `release.yml` の `Claude Code` のステップ | コードを読んだ | ADR 草稿 |
| CI2 | 低 | `write-notes.sh` が `GITHUB_ENV`、`GITHUB_PATH`、`GITHUB_OUTPUT` を外さず、`claude -p` の道具を明示的に禁じていない | `scripts/release/write-notes.sh` | コードを読んだ | ADR 草稿 |
| CI3 | 低 | `check-notes.sh` の外部リンクの検査を、生の URL、`<https://…>`、`<a href>` が通る | `scripts/release/check-notes.sh` | コードを読んだ | ADR 草稿 |
| CI4 | 低 | ghcup を `curl \| sh` で入れ、GHC と cabal をハッシュで固定していない | `scripts/release/build-linux.sh` | コードを読んだ | ADR 草稿 |
| CI5 | 低 | `fetch-wasmtime.sh` が、`VERSION` が一致すれば SHA-256 を確かめない | `scripts/fetch-wasmtime.sh` | コードを読んだ | ADR 草稿 |
| CI6 | 情報 | 前回の記録の「`scripts/` の中に `eval` はない」は誤りで、`licenses.sh` に一つある | `scripts/release/licenses.sh` | コードを読んだ | 記録のみ |

### 大きな入力で起きる資源の問題

| 番号 | 重大度 | 問題 | 場所 | 再現 | 状態 |
| --- | --- | --- | --- | --- | --- |
| T1 | 中 | 表のファイルの読み込みが、入力の 75 倍から 160 倍のメモリを使い、大きさに上限がない | golem-eval `File.parseCsv` と表の評価 | 測定（下の T1 の節） | ADR 草稿 |
| T2 | 低 | diagnostic の人間向けの描画が、ソース行を長さを限らずに書く | golem-syntax `Render.renderHuman` | 測定（10 MB の CR だけのファイル） | ADR 草稿（C13 と同じ ADR） |
| T3 | 情報 | CR だけのファイルは G0282 ですぐ止まる | golem-eval `File.noLoneCr` | 測定 | 問題なし |

## 再現した問題の詳細

### C1：ページの木が DAG のとき（中）

`pageLeaves` は、ページの木を深さ優先にたどり、途中で見た参照を `seen` に入れて循環を拒む。
`seen` は経路ごとに持つので、同じノードを二つの `Kids` から指す DAG は循環ではなく、両方の経路からたどる。
各ノードが二つの子を持ち、子が同じノードを指す木を深さ 24 にすると、ノードは 25 でも葉の訪問は 2^24 になる。
深さの上限は 64 なので、2^64 まで増やせる。
テストでは深さ 24 の木が 5 秒の制限を超え、RSS は 2.96 GB に達した。
PDF の仕様では、ページの木のノードは `Parent` を一つだけ持つので、同じノードを二度訪れる木は正しい木ではない。

### C2：リテラル文字列の 8 進エスケープ（中、性能）

`literal` は、8 進のエスケープを読むときに、残りのバイト列から 3 バイトを切り出して数字を取り、`r'' <> BS.drop 3 r` で残りを作り直す。
`<>` は残りの全体を複製するので、エスケープが n 個あれば n 回の複製で n^2 のバイトを割り当てる。
1 桁のエスケープを 5 万個並べた 150 KB の文字列で、3.79 GB を割り当てた。
仕様の変更を伴わないので、ADR なしで線形の読み方に直す。

### C3：同じストリームを何度も名指しする `Contents`（中）

ストリームの展開の上限（256 MiB、[docs/adr/0035](../adr/0035-security-hardening.md)）はストリームごとである。
`pageContent` は `Contents` の配列の各要素を `resolve` して展開し、`objectUses` も ICC のプロファイルのストリームを参照ごとに展開する。
同じオブジェクトを 40 回並べた配列は、8 MiB のストリームを 40 回展開して 320 MiB の内容を作る。
配列の長さに上限はないので、ファイルの大きさに比べて任意の倍率で膨らむ。
テストでは 6.4 GB を割り当てた。

### C4：TIFF の予測子の `Colors`（中）

`predict` は `Colors` を 65536 まで受け付け、`tiffRow` は行の各バイトについて、`bpp` 個前の値をリストの `!!` で引く。
処理は行の長さと `Colors` の積に比例する。
`Colors` を 65536、`Columns` を 65536 にした 1 MiB のデータが、10 秒の制限を超えた。
PDF の仕様は `Colors` を 1 以上としか定めないが、実際の色空間の成分の数は DeviceN の上限の 32 を超えない。

### C5：Flate の後の ASCII85（中）

`decodeWith` は、フィルタの列を順に当てる。
Flate の展開は 256 MiB で止まるが、その後の `ascii85` には上限がない。
`z` は 1 バイトで 4 バイトの 0 になるので、Flate で 80 MiB に展開した `z` の列は、ASCII85 で 320 MiB になる。
テストでは RSS が 6 GB に達し、11 秒から 15 秒かかった。
`Builder` にためてから `toStrict` でまとめるので、途中の表現も含めて入力の数倍のメモリを使う。

### C6：複数の改訂が名指しする相互参照ストリーム（中）

`readXref` の `chain` は、各改訂の開始位置を `seen` に入れて循環を拒むが、`XRefStm` が指す位置は `seen'` に入れない。
四つの改訂がすべて同じ 4 百万行の相互参照ストリームを `XRefStm` で指すと、ストリームは四回展開され、四回 `Map` になる。
`Size` の上限は 1 億であり、行の数は展開したバイト列の長さにしか限られない。
テストでは 29.7 GB を割り当て、6 秒かかった。

### C7：内容のストリームの小さなトークン（中）

`scanContent` は、トークンごとに `(Int, Int, CTok)` の組をリストに積み、`rewriteContent` がそれを歩いて編集の列を作る。
`0 g\n` を 4 百万回並べた 16 MiB の内容で、2 GB を割り当て、RSS は 2.78 GB になった。
展開の上限 256 MiB までの内容を受け付けるので、その 16 倍の内容で RSS は数十 GB になる。
割り当てそのものは線形だが、入力の百倍を超える係数と、トークンの列を全部持つことが問題である。

### C8：`marker` の自己参照と入れ子（中）

`placeMarker` は、`marker` の子を `elementChildren` で描く。
子の `path` が `marker-start` などで同じ `marker` を参照すると、再帰に終わりがない。
`marker` が別の `marker` を参照する入れ子にも深さの上限がなく、各段で四つの `marker` を置けば描く図形は 4^深さ になる。
自己参照と、深さ 14 の入れ子の両方が、5 秒の制限を超えた。
`use` の参照には深さの上限があるが、`marker` にはない。

### C9：二乗の時間になる XML と CSS の処理（中、性能）

`Xml.references` は、実体参照を見つけるごとに、前の部分と後ろの結果を `<>` でつなぐ。
`Css.stripComments` は、コメントを見つけるごとに、前の部分と残りの処理の結果をつなぐ。
`Xml.text` は、隣り合うテキストのノードを `t' <> t` でつなぎ、コメントで分けたテキストの断片を一つずつ足す。
どれも、入力を 2 倍にすると割り当てが 3.5 倍から 4 倍になった。
仕様の変更を伴わないので、ADR なしで `Builder` か一度の走査に直す。

### C10：属性の重なりの検査（中、性能）

`Xml.attributes` は、属性を読むごとに、それまでの属性のリストから名前を線形に探す。
2 万の属性で 1.13 秒、4 万で 4.68 秒かかった。
仕様の変更を伴わないので、ADR なしで `Set` を使った検査に直す。

### C11：大きさに限りのない数（中）

`numberPrefix` は、指数を 4 桁まで、仮数を 60 桁まで受け付け、`10 ^^ 指数` を有理数で計算する。
`1e9999` は 10 の 9999 乗の有理数になる。
`arc` はこの半径で `sqrtR` を呼び、`sqrtR` は値を 2 の精度ビット乗の自乗で割った整数平方根をニュートン法で求めるので、桁の数に比例した回数の多倍長の除算を繰り返す。
六つの円弧を書いた 150 バイトの SVG が、制限を超えた。
ルートの `width` に `1e9999` を書くと、拒まれずに読まれ、golem-pdf の `Drawing.fixed` が約 1 万桁の数を PDF に書く。
PDF の読み手は実数を 32 ビットの浮動小数点数で読むものが多く、仕様が示す範囲は ±3.403 × 10^38 である。

### C13：人間向けの描画の制御文字（低）

`renderHuman` は、パス、メッセージ、ソース行を、そのまま端末に書く。
JSON の描画はエスケープする。
ファイルの名前と原稿の行は原稿のリポジトリの作者が書けるので、ESC で始まるエスケープシーケンスで、端末の表示を書き換えたり、タイトルを変えたりできる。
BEL で音を鳴らすこともできる。
端末によっては、エスケープシーケンスで貼り付けを起こすものもあるので、ここでは低としたが、端末の種類によっては危険が増す。

### C14：表のファイルの名前の glob（低）

`syncWatches` は、評価が読んだ表のファイルのパスを、そのまま `RelativePattern` の glob にして、エディタに監視を登録する。
`*`、`?`、`{`、`[` を含む名前は、その名前の一つのファイルより多くのファイルに一致する。
基準はプロジェクトのルートなので、ルートの外は監視しない。
一致したファイルが変わると、プロジェクトを評価し直すだけである。

### C15：XML で許されない制御文字（低）

golem-pdf の `escapeXml` と golem-html の `escapeXml` は、`<`、`>`、`&`、`"` だけを置き換える。
XML 1.0 は、タブ、改行、復帰のほかの C0 制御文字を文書のどこにも許さない。
`manifest.toml` のタイトルや著者に U+0001 を書くと、XMP のパケット、EPUB の OPF、nav に、XML として正しくない文書が書かれる。
PDF/X-4 の検証と EPUB の検証（epubcheck）はこれを誤りとして報告する。
読む人の環境で何かが動くわけではないので、低とした。

## CI とリリースの問題の詳細

### CI1：`@anthropic-ai/claude-code` のバージョン（中）

`release` ジョブは、`npm install -g @anthropic-ai/claude-code` でバージョンを指定せずに Claude Code を入れる。
このジョブは `contents: write`、`id-token: write`、`attestations: write` を持ち、`actions/attest-build-provenance` で配布物の来歴を署名する。
`npm install` が動くのはその後だが、同じジョブの中なので、トークンを要求する環境変数とランナーのメモリに `GH_TOKEN` が残る。
パッケージが乗っ取られれば、インストールのスクリプトが OIDC のトークンを取って来歴を偽造するか、リリースを書き換えられる。
[docs/adr/0035](../adr/0035-security-hardening.md) が SHA で固定しないと決めたのは GitHub Actions の action であり、npm のパッケージには及ばない。

### CI2：`write-notes.sh` の環境と道具（低）

`write-notes.sh` は、`GH_TOKEN`、`GITHUB_TOKEN`、OIDC の二つの変数を外して `claude -p` を動かす（[docs/adr/0035](../adr/0035-security-hardening.md)）。
`GITHUB_ENV`、`GITHUB_PATH`、`GITHUB_OUTPUT` は外していない。
これらのファイルに書けば、後のステップの環境変数と `PATH` を変えられる。
`claude -p` は、許可のない道具を使わないが、`--allowedTools` や `--permission-mode`、`--strict-mcp-config` で明示していないので、既定の変化や設定ファイルの混入に頼っている。
プロンプトには、誰でも書けるプルリクエストの本文が入る。

### CI3：`check-notes.sh` の外部リンクの検査（低）

`check-notes.sh` は、`[text](https://github.com/tett23/golem/...)` の形のリンクを消してから、残りに `](` と参照形式のリンクがないことを確かめる。
生の URL、`<https://example.com>`、`<a href="...">` は、どれもこの検査を通る。
GitHub のリリースのノートはこれらをリンクとして描く。
Claude Code が書いたノートに、プロンプトから注入された外部のリンクが残っても、検査は止めない。

### CI4：ghcup と GHC の取得（低）

`build-linux.sh` は、`https://get-ghcup.haskell.org` のスクリプトを `curl | sh` で動かし、ghcup が GHC 9.10.3 と cabal を取得する。
スクリプトの内容をハッシュで確かめていない。
ghcup 自身は、取得する GHC と cabal を自分のメタデータの SHA-256 で確かめる。
このジョブのコンテナは `contents: read` で、イメージはダイジェストで固定しているが、ビルドした配布物はそのままリリースに載る。

### CI5：`fetch-wasmtime.sh` のキャッシュ（低）

`fetch-wasmtime.sh` は、`third_party/wasmtime/VERSION` が期待する名前と一致すれば、SHA-256 を確かめずにそのディレクトリを使う。
取得したときには確かめているので、キャッシュが正しく書かれていれば中身は正しい。
CI のキャッシュは main とタグのジョブだけが書けるので、プルリクエストから差し替えることはできない。
ただし、スクリプトの SHA を変えても、名前が同じならキャッシュは差し替わらない。

### CI6：前回の記録の `eval` の記述（情報）

前回の記録は「`scripts/` の中に `eval` はなく」と書いたが、`scripts/release/licenses.sh` に `eval "f=\${$v:-}"` が一つある。
変数の名前は `WASMTIME_NM`、`WASMTIME_STRINGS`、`WASMTIME_AR` の固定の三つで、外部の入力を評価しない。
前回の記録はコミット後に変更できないので、ここで訂正する。

### 問題のなかった項目

- ワークフローの `permissions` は、どのジョブも最小である。
- `pull_request_target` は使っていない。
- `run:` の中で `${{ github.event.* }}` を直接展開している箇所はない。
- `actions/checkout` は `persist-credentials: false` である。
- action は最新のメジャー版のタグで、adr-guard は v0.8.2（最新）で固定している。
- `write-notes.sh` は、`GH_TOKEN`、`GITHUB_TOKEN`、OIDC の変数を外している。
- キャッシュの書き込みは main とタグのジョブに限られる。
- hlint、wasmtime、GMP の取得はハッシュで固定している。

## 前回の問題の確認

前回の S1 から S12 の修正は、すべて今の main でも成り立つ。
golem-driver（697）、golem-pdf（180）、golem-plugin（58）、golem-eval（391）、`scripts/ci`（102）、環境の決定性（42）のテストが通る。
テストのない隙は三つある。

- S2 の EPUB の XHTML、`linkTo`、nav のエスケープは、コードが `escapeXml` を使うことを読んで確かめたが、テストはない。
- S6 の `table.grow` で要素を増やす経路は、上限の設定を読んで確かめたが、テストはない。
- S9 の `copy_msg` の NULL の扱いは、Haskell の側で確かめていない。

## 大きな入力で起きる資源の問題の詳細

### T1：表のファイルのメモリ（中）

表のファイルの読み込みは、敵対的でないふつうの大きな入力でもメモリを使いすぎる。
`parseCsv` は `T.unpack` で `String` にしてから、ファイルの全体を `Either` の再帰で読む。
TSV は入力の約 75 倍、CSV は約 130 倍から 160 倍のメモリを使う（HTML とプレーンテキストのターゲット）。
PDF では 1 行あたり約 50 KB を使い、20 万行の表は 110 秒と 10.3 GB を使った。
ファイルの大きさにも行の数にも上限がない。
LSP は、原稿の変更のたびに表のファイルを評価し直す。
原稿の作者が自分の表で自分のマシンを止めるだけなら低だが、clone した表でも同じことが起きるので、中とした。

### T2：長いソース行の描画（低）

`renderHuman` は、diagnostic の位置のソース行をそのまま書く。
10 MB の CR だけのファイルでは、G0282 の diagnostic が 10 MB の行を標準エラー出力に書く。
長さに上限がないので、1 行の長いファイルは、その全体が端末に出る。
C13 と同じ場所の問題なので、同じ ADR で扱う。

### T3：CR だけのファイル（情報）

CR だけのファイルは、`noLoneCr` の G0282 ですぐに止まり、行の分割には進まない。
問題はない。

## 直し方

- C1、C3 から C7 の PDF の取り込みの上限は、ADR の草稿「PDF の図版の取り込みの資源の上限」にまとめる。
- C8 と C11 の golem-svg の上限は、ADR の草稿「SVG の図版の `marker` と数の上限」にまとめる。
- C13、C14、C15、T2 の制御文字と glob は、ADR の草稿「制御文字と glob のメタ文字の扱い」にまとめる。
- T1 の表のファイルの上限は、ADR の草稿「表のファイルの大きさの上限」にまとめる。
- CI1 から CI5 は、ADR の草稿「リリースのワークフローの固め方」にまとめる。
- C12 は、ADR の草稿（G0814）で扱う。
- C2、C9、C10 は仕様を変えない性能の修正なので、ADR なしで直し、`security-audit-rc3-tests` のテストで確かめる。
- CI6 と T3 は記録のみである。

## 調べ方

- 前回の後に増えた入力（PDF と SVG の図版の取り込み、表のファイル、LSP の監視）のコードを読み、再帰、`<>` による連結、`!!`、上限のないループ、外部に書く箇所を洗った。
- 問題らしいものは、小さな入力を作るテストにして、時間の制限と割り当ての測定（`GHC.Stats`）で再現した。
- CI は、`release.yml` と `ci.yml`、`scripts/release/`、`scripts/fetch-*.sh` を読んだ。
- 前回の修正は、各モジュールのテストを main で実行して確かめた。

## 参考文献

- ISO 32000-1:2008, Document management, Portable document format, Part 1: PDF 1.7（ページの木の `Parent`、フィルタ、相互参照ストリーム、実数の範囲）。https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf
- W3C, Scalable Vector Graphics (SVG) 2, 2018（`marker` の要素）。https://www.w3.org/TR/SVG2/
- W3C, Extensible Markup Language (XML) 1.0 (Fifth Edition), 2008（`Char` の生成規則）。https://www.w3.org/TR/xml/
- GitHub Docs, "Security hardening for GitHub Actions". https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions
- GitHub Docs, "Workflow commands for GitHub Actions"（`GITHUB_ENV`、`GITHUB_PATH`、`GITHUB_OUTPUT`）。https://docs.github.com/en/actions/reference/workflow-commands-for-github-actions
- Microsoft, Language Server Protocol Specification 3.17, `FileSystemWatcher` と `Pattern`。https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
- Anthropic, Claude Code CLI reference（`claude -p` のフラグ）。https://docs.claude.com/en/docs/claude-code/cli-reference
