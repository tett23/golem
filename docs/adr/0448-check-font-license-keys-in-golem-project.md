# ADR 0448: フォントのライセンスのキーの検査を golem-project に置き、golem-lsp が golem-driver に依存しないようにする

Status: proposed

## 文脈

[root ADR 0434](0434-split-evaluation-from-golem-driver.md) は、評価を golem-driver から新しいパッケージ golem-evaluate に分け、golem-lsp のライブラリを golem-driver ではなく golem-evaluate に依存させると決めた（0434 の「golem-lsp」の節と I2）。
0434 の「調査した事項」は、golem-lsp のライブラリが golem-driver から使うものを数え、どれも評価の側だとしている。

一方で、0434 と同時に採択した [root ADR 0433](0433-bundle-font-licenses-with-embedded-fonts.md) は、golem-lsp に G03282（埋め込むフォントにライセンスの文書のキーが無い）を style.toml に出させる。
0434 の調べは、この要求を数えていない。
0433 の実装で、golem-lsp のライブラリは golem-driver の `fontLicenseKeyDiagnostics` と `targetsOf` を使うようになった。
どちらも 0434 が golem-evaluate に移すものに入っておらず、golem-driver の `Target` の型を使う。
そのため、0434 は書かれたとおりには実装できない。
この ADR は、この検査をどこに置くかを決める。

## 調査した事項

origin/main（[08d871c46](https://github.com/tett23/golem/commit/08d871c4691180f48022db37a887495f2a5eb220)）で、次のことを確かめた。

- golem-lsp の `Workspace.hs` は、`Golem.Driver` から `fontLicenseKeyDiagnostics` と `targetsOf` を import し（[Workspace.hs#L35](https://github.com/tett23/golem/blob/08d871c4691180f48022db37a887495f2a5eb220/modules/golem-lsp/src/Golem/Lsp/Workspace.hs#L35)）、`fontLicenseKeyDiagnostics (evStyleFile e) (manifestTargets m) (targetsOf m) (evStyle e) (const True)` を呼ぶ（[Workspace.hs#L351](https://github.com/tett23/golem/blob/08d871c4691180f48022db37a887495f2a5eb220/modules/golem-lsp/src/Golem/Lsp/Workspace.hs#L351)）。
  golem-lsp のライブラリが `Golem.Driver` から import するもののうち、0434 の一覧に無いのはこの二つだけである。
- `fontLicenseKeyDiagnostics :: FileId -> Targets -> [Target] -> Style -> (FilePath -> Bool) -> [Diagnostic]` は、`Target` の一覧のうち HTML と EPUB だけを見て、その `fonts` が `embed` かを `Targets`（マニフェストの宣言）から読み、埋め込むときだけ G03282 を出す（[Driver.hs#L1185-L1204](https://github.com/tett23/golem/blob/08d871c4691180f48022db37a887495f2a5eb220/modules/golem-driver/src/Golem/Driver.hs#L1185-L1204)）。
- golem-driver は、ターゲットごとに、HTML か EPUB の `fonts` が `embed` の枝の中だけで、この関数を `[target]` で呼ぶ（[Driver.hs#L1264-L1268](https://github.com/tett23/golem/blob/08d871c4691180f48022db37a887495f2a5eb220/modules/golem-driver/src/Golem/Driver.hs#L1264-L1268)）。
  ターゲットごとの diagnostic は、`nub` で一つにまとめる（[Driver.hs#L988](https://github.com/tett23/golem/blob/08d871c4691180f48022db37a887495f2a5eb220/modules/golem-driver/src/Golem/Driver.hs#L988)）。
  G03284 の検査にも、埋め込むかの同じ判定が一つある（[Driver.hs#L984](https://github.com/tett23/golem/blob/08d871c4691180f48022db37a887495f2a5eb220/modules/golem-driver/src/Golem/Driver.hs#L984)）。
- `targetsOf :: Manifest -> [Target]` は、マニフェストの `Targets` から組むターゲットの一覧を作る（[Driver.hs#L860-L863](https://github.com/tett23/golem/blob/08d871c4691180f48022db37a887495f2a5eb220/modules/golem-driver/src/Golem/Driver.hs#L860-L863)）。
  `Target` は golem-driver で定める（[Driver.hs#L134](https://github.com/tett23/golem/blob/08d871c4691180f48022db37a887495f2a5eb220/modules/golem-driver/src/Golem/Driver.hs#L134)）。
- `fonts` の値は `generic` と `embed` だけである（`webFontsValues`、golem-project の `Manifest.hs`）。
- 検査が使う `fontFilesWithLicenses` は golem-project の `Style.hs` にある（[Style.hs#L4200-L4206](https://github.com/tett23/golem/blob/08d871c4691180f48022db37a887495f2a5eb220/modules/golem-project/src/Golem/Project/Style.hs#L4200-L4206)）。
  `Style.hs` は `Manifest` をすでに import し、golem-syntax の `diagnostic` で G03250 などをすでに作っている。
  `Targets` と `WebFonts` は golem-project の型なので、検査を golem-project に置くのに新しい build-depends は要らない。
- 0434 の実装（ブランチ `impl-0434`、41ab8d97a）は 0433 を含まず、そこでは golem-lsp のライブラリは golem-driver に依存していない。
  0433 を含む main では、Workspace.hs が上の二つを import するので、I2 を満たせない。

## 実装すること

### 検査を golem-project に置く

golem-project の `Golem.Project.Style` に、次の関数を置く。

```haskell
fontLicenseKeyDiagnostics :: FileId -> Style -> (FilePath -> Bool) -> [Diagnostic]
```

この関数は、埋め込むかを問わず、`present` のファイルを持ち `*-license` のキーを欠くフォントごとに G03282 を一つ返す。
コード、重大度、位置、メッセージは、今の golem-driver の関数と同じにする。

埋め込むかの判定は、golem-project の `Golem.Project.Manifest` に置く。

```haskell
embedsFonts :: Targets -> Bool -> Bool -> Bool
embedsFonts t html epub = (html && tgHtmlFonts t == WebFontsEmbed) || (epub && tgEpubFonts t == WebFontsEmbed)
```

二つめの引数は HTML を、三つめは EPUB を組むかである。

golem-driver は、今の `WebFontsEmbed` の枝の中で、golem-project の `fontLicenseKeyDiagnostics` を呼ぶ。
G03284 の検査の判定（Driver.hs の 984 行）も、`embedsFonts` に替える。
golem-driver の `fontLicenseKeyDiagnostics` は消す。

golem-lsp は、`embedsFonts (manifestTargets m) (tgHtml t) (isJust (tgEpub t))`（`t` はマニフェストの `Targets`）が真のときだけ、golem-project の `fontLicenseKeyDiagnostics` を呼び、`targetsOf` を使わない。
これは、今の `targetsOf m` を使った判定と同じ値になる。

### 0434 との関係

この ADR を実装した後に、0434 を実装する。
0434 の I2（golem-lsp のライブラリが golem-driver に依存しない）は、この ADR の後の golem-lsp で成り立つ。

### 文書とステータスの行

仕様書の G03282 の記述は変えない。
仕様書と二冊のマニュアルには、この検査の置き場所の記述が無いので、直す文書は無い。

0433 の決定（G03282 を LSP にも出す）は変わらないので、0433 のステータスは変えない。
採択したら、[root ADR 0434](0434-split-evaluation-from-golem-driver.md) のステータスに、「文脈」と「調査した事項」の、golem-lsp のライブラリが golem-driver から使うものの数え方を、この ADR が補ったと記録する。
0434 は実装を待っているので、`superseded-pending` にする。

```text
superseded-pending [{"part":"文脈と調査した事項の、golem-lsp のライブラリが golem-driver から使うものの一覧","by":["docs/adr/0448-check-font-license-keys-in-golem-project.md"],"kind":"supplement"}]
```

## 実装しないこと

`Target` の型を golem-evaluate や golem-project に移さない。
`Target` は組むターゲットを選ぶ golem-driver の概念で、評価とスタイルの検査には要らないためである。
G03282 の条件、重大度、メッセージは変えない。

## 不変条件

- I1: golem-project の `fontLicenseKeyDiagnostics` が返す G03282 は、`present` のファイルを持ち `*-license` のキーを欠くフォントごとにちょうど一つで、それ以外のフォントには無い。
- I2: `embedsFonts t html epub` は、`html` が真で `t` の HTML の `fonts` が `embed` のとき、または `epub` が真で `t` の EPUB の `fonts` が `embed` のときに限り真である。
- I3: golem-driver の `golem build` が出す G03282 は、組むターゲットに `fonts = "embed"` の HTML か EPUB があるとき、キーを欠くフォントごとにちょうど一つで、そうでないとき無い。
- I4: golem-lsp が style.toml に出す G03282 は、マニフェストが `fonts = "embed"` の HTML か EPUB を宣言しているとき、キーを欠くフォントごとにちょうど一つで、そうでないとき無い。

| 入力 | 期待 | 不変条件 |
| --- | --- | --- |
| `[fonts]` が無い | G03282 は 0 | I1, I3, I4 |
| キーを欠くフォント 1 つ、HTML を `embed` で組む | 1 | I1, I3, I4 |
| キーを欠くフォント 2 つ、HTML を `embed` で組む | 2 | I1, I3, I4 |
| キーを欠くフォント 1 つ、HTML と EPUB の両方を `embed` で組む | 1（ターゲットごとに重ねない） | I3 |
| HTML を `generic`、EPUB を `embed` で組む | 1 | I2, I3, I4 |
| HTML を `generic` で組む | 0 | I2, I3, I4 |
| PDF だけを組む | 0 | I3 |
| マニフェストが `embed` の HTML を宣言し、`--target epub`（EPUB は `generic`）で組む | golem-driver は 0、LSP は 1 | I3, I4 |

## 受けいれ条件

なし。
不変条件のテストで足りるためである。

## テスト設計

root ADR 0448 I1 から I4 を名前の先頭に置いたテストを足す。
I1 と I2 は、golem-project のテストで、表の入力を関数に直接当てる。
I3 は golem-driver の `FontLicensesSpec`、I4 は golem-lsp のテストで、表の行の原稿を組む。
0433 の番号を付けた今のテストは、名前を変えずに残す。

## トレードオフ

埋め込むかの判定を呼び出しの側に置くので、ターゲットが増えたときは呼び出しの側を直す。
その代わりに、golem-project と golem-lsp が `Target` の型を知らずに済み、0434 の分け方を保てる。

`Target` を golem-evaluate に移す案もある。
しかし、評価のパッケージに、組むターゲットを選ぶ概念を持ち込むことになるので採らない。

## 参考文献

- [root ADR 0433](0433-bundle-font-licenses-with-embedded-fonts.md)
- [root ADR 0434](0434-split-evaluation-from-golem-driver.md)
