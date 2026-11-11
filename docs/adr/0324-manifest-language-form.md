# ADR 0324: どの出力でもマニフェストの言語タグの形を検査する

ステータス: 採択

## 文脈

HTML の言語指定にも、EPUB の書誌にも `[metadata].language` を使う。
現行のマニフェストは `language = "ja_JP"` でも読める。
PDF/A または PDF/UA を指定した PDF を組むときだけ、その値に G03119 を出す。
同じタグを原稿中の `[lang]` に書くと G02132 になる。

[Golem ADR 0308](0308-tell-a-japanese-book-by-the-primary-subtag-of-its-language.md) が決めた主の副タグとは、言語タグの最初のハイフンより前の部分である。
たとえば `JA-jp` を日本語として組むことと、値がタグの形をしているかを検査することは、別々の判定である。

ISO 3166-1 alpha-2 は国や地域を識別する二文字である。
BCP 47 では言語と地域を別の副タグに書けるため、`ja-JP` は日本語を言語、日本を地域として指定する。
同様に `en-US` は英語と米国を組み合わせる。
国名から使用言語は一つに決まらない。

## 実装すること

1.0.0 の前に、マニフェストを読むときに既存の `isLanguageTag` で文字列を検査する。
`ja-JP`、`en-US` のようなロケールの綴りと、`JP`、`US` のような ISO 3166-1 alpha-2 の単独指定を受け付ける。
単独の二文字は既存の形の検査を通るため、国コードから言語を推定する処理は加えない。
たとえば `JP` を `ja` に置き換えず、`DE` と `de` の入力の綴りも出力用に保つ。
国だけを BCP 47 の言語タグとして明示する必要がある書き手は、言語不明を表す `und` と組み合わせて `und-JP` と書ける。

形が合わなければ、値の位置に G03119 のエラーを一度出す。
PDF の適合宣言の有無やターゲットにかかわらず、入力の修正が必要である。
G03119 の文言を「language を言語のタグの形で書きます」に改め、PDF を組む箇所の同じ検査を除く。
文字列以外の値や必須キーの不足は、従来のスキーマエラーのままとする。

## 実装しないこと

ロジバンには言語タグ `jbo` がある。
スロベニア語のレジア方言には `sl-rozaj` と書ける。
登録されていない独自方言は、たとえば `ja-x-my-dialect` の私用部分に当事者が決めた名前を置ける。
独自名を別のタグに対応付ける設定や表示名、組版の継承規則は v1.x の拡張として扱う。

地域や用字系を補ったり、大文字と小文字を変えて保存したりしない。
登録済みの副タグかどうかを IANA の一覧に問い合わせない。
既存の形の検査が受け付けるタグの集合も、この提案では変えない。
たとえば試作で通った `sl-rozaj-rozaj` と `en-a-foo-a-bar` は同じ variant または singleton の重複を含む。
既存の形の検査に通ることを、RFC 5646 のすべての妥当性の要件を満たすこととして案内しない。

## 不変条件

1. L1：ほかのスキーマ検査を通ったマニフェストの文字列値に対して G03119 が一度出ることと、`isLanguageTag` が偽であることは同値である。
2. L2：この diagnostic のコードと位置は、ターゲットと dev または prod の選択によらない。
3. L3：検査を通った言語の綴りと日本語組版の判定は変わらない。

| 言語 | 検査結果 |
| --- | --- |
| 不正なタグと未知のキー `metadata.bogus` | スキーマ検査の G03001 だけ |
| 空文字列、`x`、`ja_JP` | G03119 |
| `ja`、`ja-JP`、`i-klingon` | 通る |
| `en-US`、`JP`、`US`、`DE`、`de` | 綴りのまま通る |
| `jbo`、`sl-rozaj`、`ja-x-my-dialect` | 通る |
| `x-local` | 私用のタグとして通る |
| `ja-` | 空の副タグにより G03119 |

## テスト設計

試作は `parseManifest` がスキーマを読み終えた直後で値を検査する。
`experiments/diagnostics/baseline.mjs` の HTML ビルドに対する L1 は、現行版で不正な形二つを通して失敗する。
L2 は PDF/A、PDF/UA、その他の PDF、HTML、EPUB、text、check をそれぞれ dev と prod で試し、同じ位置に G03119 が一度出ることを確かめる。
宣言を持つ PDF でも重複がないことと、正しい言語による現行出力を L3 で確かめる。

[追加試験](../../experiments/diagnostics-review/probe.mjs) ではロケール、国コード、人工言語、方言の九通りについて、HTML の lang 属性が入力の綴りと一致した。

## トレードオフ

国コードだけを書いた入力の綴りを出力にも残すと、HTML の読み手にはその値が言語の位置に現れる。
たとえば `DE` はドイツという地域を意図していても、言語タグの読み手にはドイツ語の `de` と区別が付かない。
地域だけを出力先に確実に伝える表記は `und-DE` である。

今まで HTML だけをビルドしてきた利用者にも変更が及ぶ。
たとえば `ja_JP` は `ja-JP` に書き直す必要がある。
警告から始める案もあるが、通常の警告をエラーへ引き上げる prod の扱いと公開時期を別に定める必要がある。
この提案は適用時期を 1.0.0 より前の互換性変更として明示し、移行例をリリース時に示す案を選ぶ。

## 参考文献

- [PDF の宣言の検査](https://github.com/tett23/golem/blob/0a8d21a091d830573fb6229111ed744f74162afd/modules/golem-typeset/src/Golem/Typeset/Draw.hs#L339-L349)
- [Golem の言語タグの形の検査](https://github.com/tett23/golem/blob/0a8d21a091d830573fb6229111ed744f74162afd/modules/golem-syntax/src/Golem/Syntax/LanguageTag.hs#L19-L56)
- [ISO の国コードの定義](https://www.iso.org/glossary-for-iso-3166.html)
- [IANA の言語タグの登録簿](https://www.iana.org/assignments/language-subtag-registry/language-subtag-registry)
- [RFC 5646 の variant と extension の規則](https://www.rfc-editor.org/rfc/rfc5646#section-2.2.5)
