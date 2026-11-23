# 図版の色変換の fixture

`gray-progressive.jpg` は [root ADR 0406](../../../../docs/adr/0406-limit-jpeg-figure-color-decoding.md) の progressive JPEG の試験用に作った画像である。
幅 3、高さ 1 の PNG の画素を、左から RGBA `(0, 0, 0, 255)`、`(128, 128, 128, 128)`、`(255, 255, 255, 255)` とし、macOS の ImageIO で JPEG に書き出した。
書き出しには `kCGImagePropertyJFIFIsProgressive = true` と `kCGImageDestinationLossyCompressionQuality = 1.0` を指定した。
試験は SOF2 のマーカーを確認してから、復号した白黒の濃淡が指定色になることを確かめる。

`pdf-adobe-cmyk.jpg` と `pdf-adobe-ycck.jpg` は、[root ADR 0403](../../../../docs/adr/0403-include-grayscale-tones-in-single-color-figures.md) の PDF 用 DCT 復号を検査するために作った画像である。
libjpeg-turbo 3.2.0 の `jpeg_compress_struct` に、幅 24、高さ 8、`input_components = 4`、`in_color_space = JCS_CMYK` を指定した。
`jpeg_set_defaults` の後に、それぞれ `jpeg_set_colorspace(JCS_CMYK)` と `jpeg_set_colorspace(JCS_YCCK)` を呼び、品質は 100 とした。
入力の各行は、左から 8 画素ずつ CMYK `(255,255,255,0)`、`(255,255,255,127)`、`(255,255,255,255)` である。
両画像の Adobe APP14 の transform は、それぞれ 0 と 2 である。
Adobe の反転した CMYK の規約では黒、灰、白を表す。
この画像を PDF の DeviceCMYK として使う場合、同じ見た目を得るには全成分の Decode を `[1,0]` にする。
macOS ImageIO の単独 JPEG の表示と、PDFKit のこの Decode を付けた PDF の表示が同じ RGB 値になることを確かめた。
テストでは Decode を適用する前のサンプル値と、YCCK の中立な三成分が等しいことを検査する。

`ccitt/` の `bw-gopher*` は、[root ADR 0425](../../../../docs/adr/0425-classify-colors-of-imported-pdf-figures.md) の CCITTFaxDecode の復号を検査するために、golang.org/x/image の `ccitt/testdata`（コミット [884d13f](https://github.com/golang/image/tree/884d13f747188b6b8581f58ddb403e7a98874f3c/ccitt/testdata)）から写したファイルである。
ライセンスは BSD 3-Clause で、`ccitt/LICENSE` に原文を置いた。
`bw-gopher.png` は幅 153、高さ 55 の白黒の画像で、ほかのファイルはその画像を Group 3 の一次元の符号化（`.ccitt_group3`）と Group 4 の符号化（`.ccitt_group4`）で書いたものである。
Group 3 のファイルは、最初の行の前と各行の後に EOL を置き、RTC で終わる。
`inverted` は白と黒を入れ替えた画像を符号化したもので、BlackIs1 を true にして読むと元の画像になる。
`aligned` は各行をバイトの境界から始め、`truncated0` と `truncated1` は終わりの RTC か EOFB を欠く。
Go の `aligned` の Group 3 のファイルは EOL の後に埋め草を置くので、EOL の前の埋め草を読む xpdf の読み方と合わず、写していない。
試験は、各ファイルを復号した標本が、PNG の画素を白を 1 として詰めた標本と一致することを確かめる。
