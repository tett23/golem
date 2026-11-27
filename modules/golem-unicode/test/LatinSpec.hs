module LatinSpec (tests) where

import Data.Char (chr)
import Data.Text qualified as T
import Golem.Unicode.Latin
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "Latin bibliography keys"
    [ testCase "root ADR 0470 I9: precomposed and decomposed Latin accents have the same key" $ do
        stripLatinDiacritics "Kádár" @?= "Kadar"
        latinSortKey "Kádár" @?= "kadar"
        latinSortKey "Ka\x0301\&da\x0301\&r" @?= "kadar",
      testCase "root ADR 0470 I9: recursive Latin decompositions lose every accent" $ do
        stripLatinDiacritics "ỆǺǼ" @?= "EAÆ"
        latinSortKey "ỆǺǼ" @?= "eaæ",
      testCase "root ADR 0470 I9: non-Latin names and marks remain unchanged by stripping" $ do
        stripLatinDiacritics "山田 が か\x3099\& ά α\x0301" @?= "山田 が か\x3099\& ά α\x0301"
        stripLatinDiacritics "\x0301\&A" @?= "\x0301\&A",
      testCase "root ADR 0470 I9: punctuation and spacing are retained" $
        latinSortKey " Éclair, D.  " @?= " eclair, d.  ",
      testCase "root ADR 0470 I9: variation selectors are not diacritics" $
        stripLatinDiacritics "A\xFE0F\x0301" @?= "A\xFE0F",
      testCase "root ADR 0470 I9: the grapheme joiner is kept without hiding following accents" $
        stripLatinDiacritics "A\x034F\x0301" @?= "A\x034F",
      testCase "root ADR 0470 I9: a ZWJ does not hide an accent in the Latin grapheme" $
        stripLatinDiacritics "A\x200D\x0301" @?= "A\x200D",
      testCase "root ADR 0470 I9: Latin letters without canonical accent decompositions are not transliterated" $
        latinSortKey "ØŁŒ" @?= "øłœ",
      testCase "root ADR 0470 I9: the Latin script includes ordinal indicators" $
        stripLatinDiacritics "ª\x0301" @?= "ª",
      testCase "root ADR 0470 I9: Unicode 17 simple lowercase mappings supplement the host tables" $
        latinSortKey "\xA7CB\xA7CE\xA7D2\xA7D4" @?= "\x0264\xA7CF\xA7D3\xA7D5",
      testCase "root ADR 0470 I9: dotted I and the canonical Angstrom sign normalize" $
        latinSortKey "İÅẞ" @?= "iaß",
      testCase "root ADR 0470 I9: empty input remains empty" $
        latinSortKey "" @?= "",
      testCase "root ADR 0470 I9: stripping is idempotent across Latin blocks and combining marks" $ do
        let text = T.pack (map chr ([0 .. 0x036F] <> [0x1E00 .. 0x1EFF] <> [0xA720 .. 0xA7FF] <> [0x1DF00 .. 0x1DFFF]))
        stripLatinDiacritics (stripLatinDiacritics text) @?= stripLatinDiacritics text
    ]
