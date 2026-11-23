{- | The counts of the manuscript statistics (docs/adr ADR 0355) equal those
of libgrapheme 3.0.0, which they replaced (docs/adr ADR 0411 I4). The
golden test/data/libgrapheme-3.0.0-counts.tsv holds the counts of the C
implementation of golem-cli before docs/adr/0411 for every sequence of up
to four of fifteen characters, the comparison of the ADR.
-}
module CountsSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Unicode.Category (isLetterOrNumber)
import Golem.Unicode.Grapheme (graphemeClusters)
import Golem.Unicode.Word (wordSegments)
import Numeric (readHex)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "counts"
    [ testCase "root ADR 0411 I4: the counts equal those of libgrapheme 3.0.0 for every sequence of up to four of the fifteen characters" $ do
        (alphabet, rows) <- golden <$> TIO.readFile "test/data/libgrapheme-3.0.0-counts.tsv"
        Map.size alphabet @?= 15
        length rows @?= sum [15 ^ n | n <- [0 .. 4 :: Int]]
        let decode s = T.pack [Map.findWithDefault (error ("no letter " <> [c])) c alphabet | c <- T.unpack s]
            failures = [(s, (g, w), counts (decode s)) | (s, g, w) <- rows, counts (decode s) /= (g, w)]
        case failures of
          [] -> pure ()
          _ -> assertFailure (show (length failures) <> " sequences differ (sequence, libgrapheme, golem-unicode):\n" <> unlines (map show (take 10 failures))),
      testCase "root ADR 0411 I4: the boundary table" $ do
        counts "" @?= (0, 0)
        counts "a" @?= (1, 1)
        counts "あ" @?= (1, 1)
        counts "\x1F468\x200D\x1F469\x200D\x1F467" @?= (1, 0)
        counts "can't stop." @?= (11, 2)
        counts "漢字とカナとGolem 1.0" @?= (15, 7)
    ]

-- | The grapheme clusters, and the word segments with a letter or a number.
counts :: Text -> (Int, Int)
counts t = (length (graphemeClusters t), length (filter (T.any isLetterOrNumber) (wordSegments t)))

{- | The letters of the sequences (@# a 0061@) and the rows (@sequence TAB
graphemes TAB words@) of the golden.
-}
golden :: Text -> (Map.Map Char Char, [(Text, Int, Int)])
golden src = (Map.fromList (mapMaybe letter comments), map row body)
  where
    (comments, body) = span ("#" `T.isPrefixOf`) (T.lines src)
    letter line = case T.words line of
      ["#", l, cp] | T.length l == 1, [(n, "")] <- readHex (T.unpack cp) -> Just (T.head l, toEnum n)
      _ -> Nothing
    row line = case T.splitOn "\t" line of
      [s, g, w] -> (s, read (T.unpack g), read (T.unpack w))
      _ -> error ("bad row: " <> T.unpack line)
