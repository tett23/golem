# ADR 0003: CFF2 のフォントを PDF の組版で拒む

ステータス: 採択（未実装）

## 文脈

[ADR 0001](0001-shaping-and-metrics.md) は、OpenType（TrueType と CFF の輪郭）を扱い、可変フォントは v1 では既定のインスタンスだけを使うと決めた。
CFF2 の輪郭を持つフォント（可変の OpenType/CFF2）をどう扱うかは、どの ADR も決めていない。

ADR と仕様の矛盾を調べる途中で、CFF2 のフォントが TrueType として扱われている疑いが見つかった。
実際に組んで確かめた（2026-10-23）。

### 再現

adobe-fonts/source-serif の 4.005R の配布物（`source-serif-4.005_Desktop.zip`）から、次の三つのフォントを本文の書体にして、欧文だけの小さなプロジェクトを `golem build --target pdf` で組んだ。

| フォント | 輪郭 | 埋め込み | 描画（macOS の PDFKit） |
|---|---|---|---|
| `SourceSerif4Variable-Roman.otf` | CFF2 の可変フォント | `CIDFontType2`、`FontFile2` に `OTTO` の sfnt（glyf がなく CFF2 だけ） | すべての字が「•」になる |
| `SourceSerif4-Regular.otf` | CFF | `CIDFontType0`、`FontFile3` の `CIDFontType0C` | 正しい |
| `SourceSerif4Variable-Roman.ttf` | glyf の可変フォント | `CIDFontType2`、`FontFile2`（gvar、fvar、HVAR などが残る） | 正しい |

三つとも、`golem build` と `golem check` は diagnostic を一つも出さずに終わった。
`golem preflight` も、CFF2 の埋め込みの誤りを報告しなかった。
`/W` の幅は三つとも一致したので、組版は既定のインスタンスで正しく行われており、壊れているのは埋め込みだけである。

### 原因

- golem-font の `golem_font_is_cff` は `CFF ` の表だけを見る。CFF2 のフォントでは偽になり、golem-driver の `Golem.Driver.Fonts` は `TrueTypeProgram` を作る。
- golem-pdf は `TrueTypeProgram` を `CIDFontType2` と `FontFile2` で書く。`FontFile2` は TrueType（glyf）の輪郭の入れ物なので、glyf を持たない CFF2 の sfnt を入れた PDF は、PDF として誤っている。CoreGraphics は埋め込んだフォントを捨て、Helvetica に置き換えた。
- `lfFaceFile` も CFF2 のフォントを `truetype` と申告するので、プリフライトのフォントの形式の検査（G0903）にも誤った形式が伝わる。
- サブセット（`golem_font_subset`）は軸を固定しない。可変フォントでは、fvar、HVAR、MVAR、avar、STAT、gvar または CFF2 の可変のデータが、使わないまま埋め込まれる。

仕様書の設計原則は、書き手の入力と違う出力を黙って作らないことを求める。
CFF2 の今の扱いは、読めない PDF を黙って作るので、この原則に反する。

### CFF2 を受け付ける道を試した結果

調査で、二つの直し方を一時的に試した（試作は残していない）。

- **軸を固定するだけ**（`hb_subset_input_pin_all_axes_to_default`）：出力は CFF2 のまま既定のインスタンスに固定される。CFF2 の入った sfnt を `FontFile3` の `/Subtype /OpenType` で埋め込んでも、PDFKit は Helvetica に置き換えた。CFF2 のまま PDF に埋め込む道は、今は使えない。
- **軸の固定と `HB_SUBSET_FLAGS_DOWNGRADE_CFF2`**：CFF に変換され、`CIDFontType0C` として PDFKit も埋め込んだフォントを使うが、「b」のグリフだけが崩れて描かれた。同梱の HarfBuzz 14.6.0 の CFF2 から CFF への変換の不具合と判断した。upstream には 14.6.0 の後に CFF2 のサブセットの修正が入っているが、それで直るかは確かめていない。

## 実装すること

### CFF2 のフォントを PDF の組版で拒む

- golem-font の読み込みで、`CFF2` の表を持つかを判定し、`fontIsCff2` として返す。
- PDF を組むとき（`golem build` の PDF、`golem check`、`golem preflight`）に、本の役割が CFF2 のフォントを使っていれば、新しいコード G0819 のエラーとし、PDF を書かない。
- HTML と EPUB は、フォントのファイルをそのまま同梱し、ブラウザと読書環境が CFF2 を描くので、拒まない。
- G0819 は、読めないフォント（G0803）とは原因が違うので、コードを分ける（仕様書の「設計原則」の「一つのコードに一つの原因」）。

| コード | 重大度 | 対象 | メッセージ | 位置 |
|---|---|---|---|---|
| G0819 | エラー | CFF2 の輪郭を持つフォント | `CFF2 の輪郭のフォントは PDF に埋め込めません: <パス>。CFF か TrueType の輪郭のフォントを使ってください` | `style.toml` の先頭（`style.toml` がなければマニフェストの先頭） |

- 図版と出力の区分（08）は G0814 まで使っている。G0815 は [docs/adr 0051](../../adr/0051-reuse-repeated-pdf-content-streams.md) の草案、G0816 と G0817 は [docs/adr 0054](../../adr/0054-svg-marker-cycle-and-depth-codes.md) の草案、G0818 は [golem-pdf ADR 0011](../../golem-pdf/adr/0011-cff-fontfile3-subtype.md) の草案が使うので、G0819 とする。草案の採択の順で番号が変わる場合は、採択のときに付け直す。
- `lfFaceFile` が CFF2 のフォントを `truetype` と申告しないよう、形式に `cff2` を加える。プリフライトの G0903 の形式の値にも加える。

### ドキュメント

- 仕様書の「フォント」の節に、CFF2 のフォントは PDF で G0819 になることを書く。
- `docs/diagnostics.md` に G0819 の節を足す。G0903 の形式の値に `cff2` を足す。
- 使い手のマニュアルのフォントの章と付録 E に、CFF2 のフォントを PDF に使えないことと、その直し方（同じ書体の CFF か TrueType の版を使う。Source Serif 4 なら `SourceSerif4-Regular.otf` か `SourceSerif4Variable-Roman.ttf`）を書く。
- [ADR 0001](0001-shaping-and-metrics.md) のステータスの行を「採択→CFF2 の輪郭のフォントの扱いは [ADR 0003](0003-reject-cff2-fonts-in-pdf.md)」とする。
- この ADR を実装するまで、CFF2 のフォントの不具合を仕様書の「既知の不具合」に載せる。

## 実装しないこと

- CFF2 のフォントを CFF に変換して PDF に埋め込むこと。同梱の HarfBuzz の変換でグリフが崩れたので、HarfBuzz を更新して、描画を比べる回帰テスト（Source Serif 4 の「b」など）で変換が正しいと確かめてから、別の ADR で受け付ける。
- 可変フォントの扱いの全体。可変フォントは v1.0.0 で扱う（ロードマップ）。サブセットで軸を既定の値に固定し、使わない可変のデータ（fvar、gvar、HVAR、MVAR など）を埋め込まないことも、そこで決める。調査では、glyf の可変フォントでこの固定を試すと、描画を変えずに PDF が 35K から 8K に縮んだ。glyf の可変フォントは今も正しく描けるので、それまでは今のまま埋め込む。
- 可変フォントの軸を書き手が指定すること。

## テスト設計

テストを先に書き、今の実装で失敗することを確かめる。

- golem-font：CFF2 のフォント、CFF のフォント、glyf の可変フォントで、`fontIsCff2` がそれぞれ真、偽、偽になること。CFF2 の小さな試料のフォントを `modules/golem-font/test/fonts/` に足す（SIL Open Font License のフォントから作り、ライセンスの表示を添える）。
- golem-driver：CFF2 のフォントを本文の役割にした本を PDF に組むと G0819 が一つ出て、PDF を書かないこと。HTML に組むと G0819 が出ないこと。今の実装では PDF が書かれるので失敗する。
- golem-preflight：CFF2 のフォントの形式が `cff2` として渡ること。

## トレードオフ

- CFF2 の可変フォントしか持たない書体は、PDF に使えなくなる。今は黙って読めない PDF を作っているので、使えないことを知らせるほうがよい。多くの書体は、CFF か TrueType の版も配っている。

## 参考文献

- adobe-fonts/source-serif 4.005R（`source-serif-4.005_Desktop.zip`）
- HarfBuzz の hb-subset の API（`hb_subset_input_pin_all_axes_to_default`、`HB_SUBSET_FLAGS_DOWNGRADE_CFF2`）
- ISO 32000-1:2008 §9.9（埋め込みフォントのプログラム）
