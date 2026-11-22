# 左右固定モードの『蟹工船』

この fixture は、左右の余白を非対称にした A4 横組みの資料を作る。
柱とノンブルは版面の中央に置き、ページの偶奇で版面を反転しないことを確かめる（[root ADR 0400](../../../../../docs/adr/0400-single-page-layout-with-fixed-left-and-right.md)）。

本文は、小林多喜二『蟹工船』の冒頭から続く段落の抜粋である。
青空文庫の図書カードは No.1465 であり、配布ファイルは [1465_ruby_16804.zip](https://www.aozora.gr.jp/cards/000156/files/1465_ruby_16804.zip)、SHA-256 は `16eb0c4c83b3930818a70cefa78978b490d536de6cc52d19d30e2bcaf6b363a4` である。
取得と変換はリポジトリの `scripts/fixtures/fetch-public-domain.sh` が行う。
通常のテストでは本文を取得せず、コミットした原稿を読む。

抜粋元はコミット `f2a0e3b8949593063ed1888535d7ed48e690c782` の `modules/golem-driver/test/fixtures/kanikosen/kanikosen.gm` の 1〜164 行である。
章の見出し「一」と「二」、ルビ、圏点を保つ。
最初の本文段落は `「おい地獄さ` で始まり `ぐんだで！」` で終わる段落、最後は `——蟹工船はどれもボロ船だった。` で始まり `彼等の夢中になるのは無理がない。` で終わる段落である。
段落を反復せず、ページ数を増やす白ページを足さない。
リポジトリのルートで、次のコマンドにより同じ抜粋を再生成できる。

```sh
git show f2a0e3b8949593063ed1888535d7ed48e690c782:modules/golem-driver/test/fixtures/kanikosen/kanikosen.gm |
  head -n 164 > modules/golem-driver/test/fixtures/single-page/kanikosen.gm
```

フォントは既存 fixture と同じ Noto Serif CJK JP 2.003 の日本語サブセット OTF（SIL Open Font License 1.1）を使う。
取得方法と配布元は [fixture 全体の README](../README.md) のフォントの節にある。
取得済みのフォントとライセンスをコピーしてから、このフォルダで通常の CLI により PDF を作る。

```sh
mkdir -p fonts
cp ../kanikosen/fonts/NotoSerifJP-Regular.otf fonts/
cp ../kanikosen/fonts/LICENSE-NotoSerifJP.txt fonts/
golem build --target pdf
```

`fonts/` と `build/` はコミットしない。
