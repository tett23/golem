{- | The copy of the default aki set that the check of the figures of the
manuals reads (docs/adr ADR 0241): test/golden/default-aki-set.tsv,
written from 'defaultAkiSet', 'charClass' and 'punctSpace'.
-}
module AkiTableSpec (akiTableTests) where

import Data.ByteString.Lazy qualified as BL
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Ratio (denominator, numerator)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Layout.Aki (Aki (..), AkiPos (..), akiBetween, akiPositions, defaultAkiSet)
import Golem.Layout.CharClass (CharClass (..), charClass)
import Golem.Layout.Japanese (punctSpace)
import Golem.Project.Style (akiClassNames)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

akiTableTests :: TestTree
akiTableTests =
  testGroup
    "the copy of the default aki set for the figures (docs/adr ADR 0241)"
    [ goldenVsString "ADR0241-F4: test/golden/default-aki-set.tsv is written from the default set" "test/golden/default-aki-set.tsv" $
        pure (BL.fromStrict (TE.encodeUtf8 akiTable)),
      testCase "ADR0241-F5: the char rows are the characters of the ranges in the six classes" $ do
        let rows = [T.splitOn "\t" l | l <- T.lines akiTable, "char\t" `T.isPrefixOf` l]
            written = [c | (_ : t : _) <- rows, [c] <- [T.unpack t]]
        length written @?= length rows
        written @?= [c | c <- ranges, charClass c `elem` punctuation]
        -- 〞 is a closing bracket since golem-layout ADR 0049, and a char row
        mapM_ (\c -> assertBool (c : " is not a char row") (c `notElem` written)) ("〚〛“" :: String)
        assertBool "〞 is a char row" ('〞' `elem` written)
        mapM_ (\c -> assertBool (c : " is not in the ranges") (c `elem` ranges)) written,
      testCase "ADR0241-F5: each char row has the class of charClass and the space of punctSpace" $
        sequence_
          [ T.splitOn "\t" l @?= ["char", T.singleton c, className (charClass c), fraction b, fraction a]
          | (l, c) <- zip [l | l <- T.lines akiTable, "char\t" `T.isPrefixOf` l] [c | c <- ranges, charClass c `elem` punctuation],
            let (b, a) = punctSpace (charClass c)
          ],
      testCase "ADR0241-F4: the aki rows are the 324 pairs of positions in their order" $ do
        let rows = [T.splitOn "\t" l | l <- T.lines akiTable, "aki\t" `T.isPrefixOf` l]
        length rows @?= 324
        [(x, y) | (_ : x : y : _) <- rows] @?= [(posName p, posName q) | p <- positions, q <- positions],
      testCase "ADR0241-F4: the names of the positions are those of style.toml" $
        sequence_ [akiPositions (posName p) @?= [p] | p <- positions],
      testCase "ADR0241-F4: the first line is a comment and every line ends with LF" $ do
        assertBool "a comment" ("# " `T.isPrefixOf` akiTable)
        assertBool "ends with LF" ("\n" `T.isSuffixOf` akiTable)
        assertBool "no CR" (not (T.any (== '\r') akiTable))
    ]

-- | The six classes of the punctuation of the figures.
punctuation :: [CharClass]
punctuation = [Opening, Closing, MiddleDot, FullStop, Comma, IdeographicSpace]

ranges :: String
ranges = ['\x3000' .. '\x30FF'] <> ['\xFF00' .. '\xFFEF']

-- | Every position, in the order of 'AkiPos'.
positions :: [AkiPos]
positions = map AkiChar [minBound .. maxBound] <> [AkiLineStart, AkiParagraphStart, AkiLineEnd]

-- | The name of a class in the rules of style.toml.
className :: CharClass -> Text
className c = fromMaybe (error ("no name of " <> show c)) (listToMaybe [n | n <- akiClassNames, akiPositions n == [AkiChar c]])

posName :: AkiPos -> Text
posName = \case
  AkiChar c -> className c
  AkiLineStart -> "line-start"
  AkiParagraphStart -> "paragraph-start"
  AkiLineEnd -> "line-end"

-- | 1/2, or 0 for an integer.
fraction :: Rational -> Text
fraction r
  | denominator r == 1 = T.pack (show (numerator r))
  | otherwise = T.pack (show (numerator r)) <> "/" <> T.pack (show (denominator r))

-- | The contents of test/golden/default-aki-set.tsv.
akiTable :: Text
akiTable =
  T.unlines $
    "# The default aki set (gyomatsu-yakumono-hankaku) for scripts/manual/outline-prepare.sh, written by golem-layout-test (docs/adr/0241); rewrite it with: cabal test golem-layout:golem-layout-test --test-options=--accept"
      : [ T.intercalate "\t" ["char", T.singleton c, className (charClass c), fraction b, fraction a]
        | c <- ranges,
          charClass c `elem` punctuation,
          let (b, a) = punctSpace (charClass c)
        ]
        <> [ T.intercalate "\t" ["aki", posName p, posName q, fraction (akiMinimum x), fraction (akiOptimum x), fraction (akiMaximum x)]
           | p <- positions,
             q <- positions,
             let x = akiBetween defaultAkiSet p q
           ]
