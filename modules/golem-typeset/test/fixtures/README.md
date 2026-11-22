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
