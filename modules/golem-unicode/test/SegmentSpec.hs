{- | The segmentations give the input back in non-empty pieces
(docs/adr ADR 0411 I3), the rows of the boundary table of the ADR, and the
unit tests of libgrapheme 3.0.0 (test/character.c and test/word.c) that
mean something for a 'Text'.
-}
module SegmentSpec (tests) where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Unicode.Grapheme (graphemeClusters)
import Golem.Unicode.Word (wordSegments)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit (testCase, (@?=))
import Test.Tasty.Hedgehog

tests :: TestTree
tests =
  testGroup
    "segmentation"
    [ testProperty "root ADR 0411 I3: the grapheme clusters of any text are non-empty and concatenate to it" $
        partitions graphemeClusters,
      testProperty "root ADR 0411 I3: the word segments of any text are non-empty and concatenate to it" $
        partitions wordSegments,
      testGroup
        "root ADR 0411 I3: the boundary table"
        [ testCase "the empty text has no grapheme cluster and no word segment" $ do
            graphemeClusters "" @?= []
            wordSegments "" @?= [],
          testCase "one character is one grapheme cluster and one word segment" $ do
            graphemeClusters "a" @?= ["a"]
            graphemeClusters "あ" @?= ["あ"]
            wordSegments "a" @?= ["a"]
            wordSegments "あ" @?= ["あ"],
          testCase "a character with combining marks is one grapheme cluster" $ do
            graphemeClusters "か\x3099" @?= ["か\x3099"]
            graphemeClusters "e\x0301" @?= ["e\x0301"],
          testCase "a family emoji joined by ZWJ is one grapheme cluster" $
            graphemeClusters family @?= [family],
          testCase "two pairs of regional indicators are two grapheme clusters" $
            graphemeClusters "\x1F1EF\x1F1F5\x1F1E9\x1F1EA" @?= ["\x1F1EF\x1F1F5", "\x1F1E9\x1F1EA"],
          testCase "CR and LF are one grapheme cluster" $
            graphemeClusters "\r\n" @?= ["\r\n"],
          testCase "an English sentence is split by the WB rules" $
            wordSegments "can't stop." @?= ["can't", " ", "stop", "."],
          testCase "Japanese and Latin text is split by the WB rules" $
            wordSegments "漢字とカナとGolem 1.0" @?= ["漢", "字", "と", "カナ", "と", "Golem", " ", "1.0"],
          testCase "U+FFFD (where an invalid sequence was) is split by the rules" $ do
            graphemeClusters "\x1F1E9\xFFFD" @?= ["\x1F1E9", "\xFFFD"]
            wordSegments "\x1F1E9\xFFFD" @?= ["\x1F1E9", "\xFFFD"]
            graphemeClusters "e\xFFFD\x0301" @?= ["e", "\xFFFD\x0301"]
        ],
      testGroup
        "the unit tests of libgrapheme 3.0.0"
        [ testCase "one character: two regional indicators and an asterisk" $
            graphemeClusters "\x1F1E9\x1F1EA*" @?= ["\x1F1E9\x1F1EA", "*"],
          testCase "one character, fragment: a regional indicator and a broken sequence" $
            take 1 (graphemeClusters "\x1F1E9\xFFFD") @?= ["\x1F1E9"],
          testCase "one word: two regional indicators, a space and a word" $
            wordSegments "\x1F1E9\x1F1EA is" @?= ["\x1F1E9\x1F1EA", " ", "is"],
          testCase "one word, fragment: a regional indicator and a broken sequence" $
            take 1 (wordSegments "\x1F1E9\xFFFD") @?= ["\x1F1E9"]
        ]
    ]
  where
    family = "\x1F468\x200D\x1F469\x200D\x1F467" :: Text

-- | The pieces are non-empty and concatenate to the input.
partitions :: (Text -> [Text]) -> Property
partitions segment = withTests 1000 . property $ do
  t <- forAll genText
  let pieces = segment t
  T.concat pieces === t
  assert (not (any T.null pieces))

{- | Any Unicode characters, mixed with those the rules of UAX #29 treat
specially, so that the rules meet each other.
-}
genText :: Gen Text
genText = T.pack <$> Gen.list (Range.linear 0 40) (Gen.frequency [(1, Gen.unicode), (3, Gen.element special)])
  where
    special =
      "a1.,:'\" \t\r\n\x0085\x00AD\x0300\x0301\x0308\x200C\x200D\x2018\x05D0\x0E33\x0600\x0915\x094D\x093F\x1100\x1161\x11A8\xAC00\xAC01\x1F1E6\x1F1E9\x1F468\x1F469\x2764\xFE0F\x1F3FB\x24C2\x3099あア漢_\xFFFD" :: String
