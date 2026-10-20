# tools/textlint

Golem の文書とマニュアルの原稿の表記を検査する textlint の設定、規則、辞書を置く（[docs/adr/0036](../../docs/adr/0036-textlint-for-documents.md)）。
Golem の開発の道具であり、Golem の配布物には入らない。
表記の規則そのものは [CONTRIBUTING.md](../../CONTRIBUTING.md) の「日本語の文章」と [docs/manual-policy.md](../../docs/manual-policy.md) にある。

## 使い方

リポジトリのどこからでも、次を実行する。

```sh
sh scripts/ci/textlint.sh                    # 検査する
TEXTLINT_ARGS=--fix sh scripts/ci/textlint.sh  # prh と空白の規則の直しを当てる
node --test tools/textlint/test/*.test.js     # Golem の規則と辞書のテスト
```

初めての実行で `npm ci` がパッケージを `node_modules/` に入れる。
引数に BASE のコミットを渡すと、BASE との分岐点から加えた ADR を検査する。
省くと `origin/main` との分岐点を使う。

## 置いてあるもの

| パス | 中身 |
| --- | --- |
| `package.json`、`package-lock.json` | textlint 15.8.0、textlint-rule-preset-ja-technical-writing 12.0.2、textlint-rule-preset-ja-spacing 3.0.3、@textlint-ja/textlint-rule-preset-ai-writing 1.7.0、textlint-rule-prh 6.1.1（どれも MIT）を正確なバージョンで固定する |
| `rules/` | Golem の規則のプリセット `textlint-rule-preset-golem`（`file:rules` で参照する） |
| `prh/` | 用語の辞書。`common.yml` は全文書、`dev.yml` は開発者が読む文書、`user.yml` は使い手のマニュアル |
| `config/` | プロファイルごとの設定。`common.js` が共通の部分で、止めた規則の理由もここに書く |
| `test/` | Golem の規則と辞書のテスト |

## プロファイル

| プロファイル | 対象 |
| --- | --- |
| `docs` | `docs/` の Markdown（ADR、`docs/diagnostics.md`、記録を除く）、README.md、CONTRIBUTING.md |
| `diagnostics` | `docs/diagnostics.md` |
| `adr` | ブランチが加えた ADR |
| `manual` | `manual/` の `.gm` |
| `manual-dev` | `manual-dev/` の `.gm` |

コミット済みの ADR は変えられないので検査しない。
CONTRIBUTING.en.md は英語なので検査しない。
マニュアルの `.gm` は平文として読み、Golem の規則と prh だけを当てる。
インラインのコマンド（`[code: ...]`、`[note: ...]`、`[index ...]`）が文に混ざるので、公開のプリセットは数千件の誤検知を出すからである。

## Golem の規則

| 規則 | 内容 |
| --- | --- |
| `golem/one-sentence-per-line` | 段落の一行に二つ目の文があれば報告する。箇条書きの項目、表、見出し、脚注の定義、Golem のブロックコマンドとコメントは対象にしない |
| `golem/no-dash` | U+2014 と U+2015 を報告する。（——）のように文字そのものを指す場合は除く |
| `golem/no-nakaguro-listing` | 前後のどちらかがカタカナでない中黒を報告する。カタカナどうしのあいだの中黒は、外来語の区切りとみなして報告しない |
| `golem/review-words` | 意味で置き換えの先が変わる語を、直さずに報告する（「機械」「診断」「お知らせ」「シェル」「効く」「鍵」。プロファイルで選ぶ） |

どの規則も、コードブロック、インラインのコード、Golem の `[code: ...]` の中は見ない。
`review-words` と prh は、鉤括弧の中の語（引いた題、語そのもの）を見ない。

## 公開のプリセットの調整

全角と半角のあいだ、インラインのコードの前後、リンクの前後に空白を入れる（Golem の表記）。
文体は常体（である）とする。

| 規則 | 扱い | 理由 |
| --- | --- | --- |
| `arabic-kanji-numbers` | 止める | 数を数える語を漢数字で書く（二つ、一文） |
| `sentence-length` | 止める | 100 字を超える文が 251 あり、多くは仕様の項目を並べた文である。単純な手直しでは短くできないので、レビューに残す |
| `no-doubled-joshi` | 止める | 123 件の報告のほぼすべてが「A も B も」「A と B と」と、連体修飾の中の「が」だった |
| `max-comma` | 止める | 半角のカンマは `(八分, 四分, 二分)` のような組の表記にしか現れない |
| `max-ten` | 6 以上で報告 | 項目を読点で並べる文が多い |
| `ja-no-successive-word` | ○、一つ、… を許す | ○○、一つ一つ、…… は誤りではない |
| `max-kanji-continuous-len` | 団体、規格、書名を許す | 日本産業標準調査会のような固有名詞 |
| `no-ai-list-formatting` | 止める | `- **語**：説明` は用語集と仕様書の定義の並べ方である |
| `no-ai-hype-expressions` | 「完全に静的」「完全に同じ」を許す | 事実を言う表現である |
| `ja-no-mixed-period` | `diagnostics` と `adr` で止める | `docs/diagnostics.md` の題はメッセージそのもので句点がない。ADR のステータスの行も句点で終わらない |
| `no-mix-dearu-desumasu` | `diagnostics` で止める | メッセージは敬体である |
| `no-unmatched-pair`、`ja-no-space-around-parentheses` | `diagnostics` で止める | メッセージが Golem の括弧（`[`、`]`）を含む |

## パッケージを上げるとき

`package.json` のバージョンを変えて `npm install` で `package-lock.json` を作り直し、`sh scripts/ci/textlint.sh` を走らせる。
増えた報告は、文書を直すか、理由を添えて `config/common.js` で止めてから入れる。
