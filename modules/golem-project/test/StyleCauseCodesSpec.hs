{- | The codes of the errors of the axes of a font and of the format of
[printings] in style.toml, one for each cause (root ADR 0413): each row of
the table of the ADR is a test, with the code, where the error starts and
the message, which is the one before the ADR.
-}
module StyleCauseCodesSpec (tests) where

import Data.Text (Text)
import Golem.Project.Style
import Golem.Syntax
import Support (offsetOf)
import Test.Tasty
import Test.Tasty.HUnit

-- | The code, the start and the message of each diagnostic of a style.toml.
diagnosticsOf :: Text -> [(Text, Int, Text)]
diagnosticsOf src = either (map (\d -> let DiagnosticCode c = diagCode d in (c, spanStart (diagSpan d), diagMessage d))) (const []) (parseStyle (FileId 0) src)

-- | A role of fonts with one more line.
font :: Text -> Text
font kv = "[fonts.body]\nja = \"b.otf\"\n" <> kv <> "\n"

-- | [printings] with a format, written as a TOML basic string.
printings :: Text -> Text
printings format = "[printings]\nformat = " <> format <> "\n"

-- | The message of an error of the format of [printings]: the reason and the format.
printingsMessage :: Text -> Text -> Text
printingsMessage why format = "[printings] の format が正しくありません（" <> why <> "）: " <> format <> " (printings.format)"

-- | The reasons of [printings] for a { not closed and a } without its {: they recommend {{ and }} (root ADR 0424).
unclosedPrintings, unopenedPrintings :: Text
unclosedPrintings = "閉じていない { があります。文字の { は {{ と書きます"
unopenedPrintings = "対応する { のない } があります。文字の } は }} と書きます"

-- | A row: the name, the style.toml, the code, the value the error starts at, and the message.
data Row = Row String Text Text Text Text

rowTest :: String -> Row -> TestTree
rowTest invariant (Row name src code needle message) =
  testCase ("root ADR 0413 " <> invariant <> ": " <> name) $
    diagnosticsOf src @?= [(code, offsetOf src needle, message)]

-- | The rows of the table of the ADR for I1: one cause in each input.
oneCause :: [Row]
oneCause =
  [ Row "an instance that is not a string is G03260" (font "instance = 1") "G03260" "1\n" "fonts.body.instance には文字列を書きます（整数が書かれています）",
    Row "axes that are not a table are G03261" (font "axes = 650") "G03261" "650" "axes には軸のタグと数の表を書きます（{ wght = 650 } のように書きます） (fonts.body.axes)",
    Row "a value of an axis that is not a number is G03262" (font "axes = { wght = \"a\" }") "G03262" "\"a\"" "軸の値には数を書きます (fonts.body.axes.wght)",
    Row "an infinite value of an axis is G03263" (font "axes = { wght = inf }") "G03263" "inf" "軸の値には有限の数を書きます (fonts.body.axes.wght)",
    Row "a value of an axis that is NaN is G03263" (font "axes = { wght = nan }") "G03263" "nan" "軸の値には有限の数を書きます (fonts.body.axes.wght)",
    Row "a newline in the format of [printings] is G03264" (printings "\"{year}\\n\"") "G03264" "\"{year}" "[printings] の format が正しくありません（改行は書けません） (printings.format)",
    Row "a field not in the table is G03265" (printings "\"{volume}\"") "G03265" "\"{volume}" (printingsMessage "表にない欄です: {volume}" "{volume}"),
    Row "a field with an empty name is G03265" (printings "\"{:kanji}\"") "G03265" "\"{:kanji}" (printingsMessage "表にない欄です: {}" "{:kanji}"),
    Row "a notation on a field is G03266" (printings "\"{edition:kanji}\"") "G03266" "\"{edition" (printingsMessage "数でない差し込みには表記を書けません: {edition:kanji}" "{edition:kanji}"),
    Row "an empty notation on a field is G03266" (printings "\"{year:}\"") "G03266" "\"{year" (printingsMessage "数でない差し込みには表記を書けません: {year:}" "{year:}"),
    Row "a { not closed is G03267" (printings "\"{year\"") "G03267" "\"{year" (printingsMessage unclosedPrintings "{year"),
    Row "a } without its { is G03268" (printings "\"year}\"") "G03268" "\"year}" (printingsMessage unopenedPrintings "year}"),
    Row "an empty field {} is G03269" (printings "\"{}\"") "G03269" "\"{}" (printingsMessage "空の差し込み {} があります" "{}"),
    Row "a character after \\ that is not {, } or \\ is G03270" (printings "\"\\\\a\"") "G03270" "\"\\\\a" (printingsMessage "\\ の後には {、}、\\ のどれかを書きます: \\a" "\\a"),
    Row "a \\ at the end of the format is G03271" (printings "\"{year}\\\\\"") "G03271" "\"{year}" (printingsMessage "書式の末尾に \\ があります。文字の \\ は \\\\ と書きます" "{year}\\")
  ]

-- | The rows of the table of the ADR for I2: two causes, one code.
twoCauses :: [Row]
twoCauses =
  [ Row "a newline comes before the other causes: G03264 only" (printings "\"{volume}\\n\"") "G03264" "\"{volume}" "[printings] の format が正しくありません（改行は書けません） (printings.format)",
    Row "the first cause read from the front: G03265 only" (printings "\"{volume}{\"") "G03265" "\"{volume}" (printingsMessage "表にない欄です: {volume}" "{volume}{")
  ]

-- | The other formats keep their codes and messages (I3).
otherFormats :: [Row]
otherFormats =
  [ Row "a slot not in the table of [notes] mark-format is still G03006" "[notes]\nmark-format = \"{x}\"\n" "G03006" "\"{x}" "[notes] の mark-format が正しくありません（表にない差し込みです: {x}。注の番号は {n} か {n:<表記>} と書きます）: {x} (notes.mark-format)",
    Row "a { not closed in [notes] mark-format is still G03006" "[notes]\nmark-format = \"{n\"\n" "G03006" "\"{n" "[notes] の mark-format が正しくありません（閉じていない { があります。文字の { は \\{ と書きます）: {n (notes.mark-format)",
    Row "a wrong escape in [notes] mark-format is still G03006" "[notes]\nmark-format = \"\\\\a{n}\"\n" "G03006" "\"\\\\a" "[notes] の mark-format が正しくありません（\\ の後には {、}、\\ のどれかを書きます: \\a）: \\a{n} (notes.mark-format)",
    Row "a slot not in the table of a heading number is still G03006" "[headings.1]\nnumber = \"{x}\"\n" "G03006" "\"{x}" "番号の書式が不正です: {x}"
  ]

-- | The rows of root ADR 0424 I1: [printings] recommends {{ and }}, the other formats \\{ and \\} as before.
bracesMessages :: [Row]
bracesMessages =
  [ Row "a { not closed in [printings] recommends {{" (printings "\"{year\"") "G03267" "\"{year" (printingsMessage unclosedPrintings "{year"),
    Row "a } without its { in [printings] recommends }}" (printings "\"year}\"") "G03268" "\"year}" (printingsMessage unopenedPrintings "year}"),
    Row "a { not closed in a running head still recommends \\{" "[masters.book]\nrunning-head = { position = \"top-outside\", content = [\"{title\"] }\n" "G03014" "[\"{title" "柱の書式が正しくありません: 閉じていない { があります。文字の { は \\{ と書きます (masters.book.running-head.content)",
    Row "a { not closed in [notes] mark-format still recommends \\{" "[notes]\nmark-format = \"{n\"\n" "G03006" "\"{n" "[notes] の mark-format が正しくありません（閉じていない { があります。文字の { は \\{ と書きます）: {n (notes.mark-format)",
    Row "a } without its { in [notes] mark-format still recommends \\}" "[notes]\nmark-format = \"n}\"\n" "G03006" "\"n}" "[notes] の mark-format が正しくありません（対応する { のない } があります。文字の } は \\} と書きます）: n} (notes.mark-format)"
  ]

-- | A row of root ADR 0424.
rowTest0424 :: Row -> TestTree
rowTest0424 (Row name src code needle message) =
  testCase ("root ADR 0424 I1: " <> name) $
    diagnosticsOf src @?= [(code, offsetOf src needle, message)]

tests :: TestTree
tests =
  testGroup
    "root ADR 0413: codes for the axes of fonts and the format of [printings]"
    [ testGroup "I1" (map (rowTest "I1") oneCause),
      testGroup "I2" (map (rowTest "I2") twoCauses),
      testGroup
        "I3"
        ( testCase "root ADR 0413 I3: a right instance, axes and format have no diagnostic" (diagnosticsOf (font "instance = \"Bold\"\naxes = { wght = 650, opsz = -1.5 }" <> printings "\"{date} 第{edition}版第{printing}刷 \\\\{year\\\\}\"") @?= [])
            : map (rowTest "I3") otherFormats
        ),
      testGroup "root ADR 0424 I1: the messages of braces" (map rowTest0424 bracesMessages)
    ]
