# 図版の色変換の fixture

`gray-progressive.jpg` は [root ADR 0406](../../../../docs/adr/0406-limit-jpeg-figure-color-decoding.md) の progressive JPEG の試験用に作った画像である。
幅 3、高さ 1 の PNG の画素を、左から RGBA `(0, 0, 0, 255)`、`(128, 128, 128, 128)`、`(255, 255, 255, 255)` とし、macOS の ImageIO で JPEG に書き出した。
書き出しには `kCGImagePropertyJFIFIsProgressive = true` と `kCGImageDestinationLossyCompressionQuality = 1.0` を指定した。
試験は SOF2 のマーカーを確認してから、復号した白黒の濃淡が指定色になることを確かめる。
