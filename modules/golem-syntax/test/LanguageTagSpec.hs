-- | The form of a language tag (docs/adr ADR 0183).
module LanguageTagSpec (tests) where

import Golem.Syntax.LanguageTag (isLanguageTag)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "the form of a language tag, BCP 47 (docs/adr ADR 0183)"
    [ testCase "well-formed tags" $
        mapM_
          (\t -> (t, isLanguageTag t) @?= (t, True))
          [ "ja",
            "en",
            "en-US",
            "zh-Hant-TW",
            "sr-Latn-RS",
            "es-419",
            "de-CH-1996",
            "sl-rozaj-biske",
            "zh-yue-HK",
            "en-a-bbb-x-a-ccc",
            "x-whatever",
            "qaa-Qaaa-QM-x-southern",
            "i-klingon",
            "en-GB-oed",
            "art-lojban",
            "EN-us",
            "abcdefgh",
            "ja-JP-u-ca-japanese"
          ],
      testCase "tags that are not of the form" $
        mapM_
          (\t -> (t, isLanguageTag t) @?= (t, False))
          [ "",
            "日本 語!",
            "ja_JP",
            "j",
            "abcdefghi",
            "en-",
            "-en",
            "en--US",
            "en-US-",
            "en-a",
            "en-a-b",
            "x",
            "x-",
            "x-abcdefghi",
            "en-x",
            "123",
            "en-Latn-Latn-US-US",
            "ja JP"
          ]
    ]
