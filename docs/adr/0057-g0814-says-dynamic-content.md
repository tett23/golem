# ADR 0057: G0814 の文言を「動的なコンテンツ」にする

ステータス: 採択

## 文脈

[ADR 0039](0039-svg-active-content-in-html-and-epub.md) は、HTML と EPUB に写す SVG の図版のうち、スクリプト、イベントの属性、外部の参照などを持つものを G0814 で拒むと決めた。
ADR は、これらを「動く中身」と呼び、G0814 のメッセージを次のように決めた。

> `SVG の図版に、HTML と EPUB に写せない動く中身があります: <パス>:<行>:<桁>（<名前>）`

[ADR 0039](0039-svg-active-content-in-html-and-epub.md) の採択と実装の後、プルリクエスト #271 は、用語を「動的なコンテンツ」に改めた。
メンテナーが、「動く中身」は日本語として意味が通らないと判断し、「動的なコンテンツ」に改めるよう指示したためである。
改めたのは、仕様書、`docs/diagnostics.md`（G0814）、[markup.md](../markup.md)、golem-svg の仕様書、二つのマニュアル、golem-driver の `Golem.Driver.Svg` のメッセージとそのテストである。
コミット済みの [ADR 0039](0039-svg-active-content-in-html-and-epub.md) は変えられないので、旧い文言のまま残った。
今のメッセージは次のとおりである。

```
SVG の図版に、HTML と EPUB に写せない動的なコンテンツがあります: <パス>:<行>:<桁>（<名前>）
```

ADR のメッセージとコードのメッセージが食い違っているので、どちらを正とするかを記録する。

## 実装すること

G0814 の文言を、今の実装のとおり「動的なコンテンツ」とすると決める。
コードの振る舞いは変えない。

- G0814 のメッセージは `SVG の図版に、HTML と EPUB に写せない動的なコンテンツがあります: <パス>:<行>:<桁>（<名前>）ほか <n> 件` とする。読めない SVG では `SVG の図版に、HTML と EPUB に写せない動的なコンテンツがあります: <パス>（<G0810 と同じ理由>）` とする。
- 文書で G0814 が拒むものを指すときも、「動的なコンテンツ」と書く。
- 拒むものの表と、検査の範囲と出し方は [ADR 0039](0039-svg-active-content-in-html-and-epub.md) のとおりである。

### ADR のステータス

- [ADR 0039](0039-svg-active-content-in-html-and-epub.md) のステータスの行を次のようにする。

  ```
  ステータス: 採択→G0814 の文言（動的なコンテンツ）は [ADR 0057](0057-g0814-says-dynamic-content.md)
  ```

### ドキュメント

- `docs/diagnostics.md` の G0814 の節の ADR の欄に、この ADR を足す。
- 仕様書の G0814 を説明する箇所に、この ADR へのリンクを足す。

## 実装しないこと

- [golem-pdf ADR 0009](../golem-pdf/adr/0009-svg-figures.md) のステータスの行にある「動く中身」を改めること。ステータスの行は、[ADR 0039](0039-svg-active-content-in-html-and-epub.md) の当時の用語で、置き換えた範囲を指しているだけであり、リンクを辿れば意味は変わらない。
- 監査の記録（[docs/audits/2026-10-18-security-audit.md](../audits/2026-10-18-security-audit.md)）の文言を改めること。監査の記録はコミット後に変えない。

## テスト設計

コードは変えないので、今のテストが文言を固定していることを確かめる。

- golem-driver の `test/FigureSpec.hs` の「an SVG figure with a script is G0814 ...」は、メッセージが `SVG の図版に、HTML と EPUB に写せない動的なコンテンツがあります: images/s.svg:2:1（script）` であることを確かめている（今のテスト）。
- 同じファイルの「a broken SVG is G0814 with the reason of G0810; more than one thing adds ほか」は、二つ見つかった SVG のメッセージが `...images/s.svg:1:70（onclick）ほか 1 件` であることを確かめている（今のテスト）。
- 同じテストは、読めない SVG のメッセージが `images/b.svg（` を含むことだけを確かめている。メッセージが `SVG の図版に、HTML と EPUB に写せない動的なコンテンツがあります: images/b.svg（` で始まることを確かめるように強める。

## トレードオフ

- 「動く中身」は短いが、日本語として何を指すのかが通らない。「動的なコンテンツ」は、Web の文書で実行や取り込みによって内容が変わるものを指す語として通りやすい。
- 語が長くなり、メッセージも長くなる。

## 参考文献

- [ADR 0039](0039-svg-active-content-in-html-and-epub.md)
- プルリクエスト #271（Say 動的なコンテンツ for SVG active content）
