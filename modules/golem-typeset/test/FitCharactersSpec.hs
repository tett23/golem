{- | A paragraph of fit-characters set to the width of its characters in
the PDF (root ADR 0466): the line and the spaces between its graphemes.
-}
module FitCharactersSpec (fitCharactersTests) where

import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Layout.Japanese (composeInlines, defaultComposeEnv)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..))
import Golem.Project.Style (Sp (..))
import Golem.Syntax.Span (FileId (..), SrcSpan, mkSpan)
import Golem.Typeset.Internal (fitItems)
import Test.Tasty
import Test.Tasty.HUnit

-- | The size of the paragraph, 10pt.
fs :: Sp
fs = 655360

sp0 :: SrcSpan
sp0 = mkSpan (FileId 0) 0 0

txt :: Text -> Inline
txt = Text sp0

-- | The items of a text, as a paragraph composes them.
itemsOf :: [Inline] -> [Item]
itemsOf = fst . composeInlines (defaultComposeEnv fs)

-- | The items of a text fitted to a width.
fitted :: Sp -> [Inline] -> Maybe [Item]
fitted w is = fst <$> fitItems (defaultComposeEnv fs) w (itemsOf is)

-- | The boxes of a line with their widths: the text of each, empty for a space.
boxes :: [Item] -> [(Text, Sp)]
boxes its = [(bcText c, w) | Box w c <- its]

-- | The length of a line: its items, the end of the paragraph left out.
lineLength :: [Item] -> Sp
lineLength its = sum [w | Box w _ <- its] + sum [w | Glue {itemWidth = w} <- its]

-- | The spaces between the boxes of text, in order.
gapsOf :: [Item] -> [Sp]
gapsOf its =
  let runs = boxes its
      textAt = [not (T.null t) | (t, _) <- runs]
      between = [sum [w | (t, w) <- seg, T.null t] | seg <- segments runs]
   in if or textAt then between else []
  where
    -- the boxes between two boxes of text
    segments xs = case dropWhile (T.null . fst) xs of
      [] -> []
      _ : rest ->
        let (spaces, more) = span (T.null . fst) rest
         in if null more then [] else spaces : segments more

-- | The spaces before the first box of text and after the last.
edgesOf :: [Item] -> (Sp, Sp)
edgesOf its =
  let runs = boxes its
      lead = sum [w | (_, w) <- takeWhile (T.null . fst) runs]
      trail = sum [w | (_, w) <- takeWhile (T.null . fst) (reverse runs)]
   in (lead, trail)

fitCharactersTests :: TestTree
fitCharactersTests =
  testGroup
    "fit-characters (root ADR 0466)"
    [ testCase "root ADR 0466 I2, I3: 2 characters fitted to 4: the width of 4, the space of 2 between them" $ case fitted (4 * fs) [txt "目次"] of
        Just its -> do
          lineLength its @?= 4 * fs
          gapsOf its @?= [2 * fs]
          edgesOf its @?= (0, 0)
        Nothing -> assertFailure "not fitted",
      testCase "root ADR 0466 I2, I3: 4 characters fitted to 4: the width of 4, no space between them" $ case fitted (4 * fs) [txt "前書き章"] of
        Just its -> do
          lineLength its @?= 4 * fs
          gapsOf its @?= [0, 0, 0]
        Nothing -> assertFailure "not fitted",
      testCase "root ADR 0466 I4: 5 characters do not fit 4" $ isNothing (fitted (4 * fs) [txt "あいうえお"]) @?= True,
      testCase "root ADR 0466 I2: 1 character fitted to 3 is at the centre of the width" $ case fitted (3 * fs) [txt "序"] of
        Just its -> do
          lineLength its @?= 3 * fs
          edgesOf its @?= (fs, fs)
        Nothing -> assertFailure "not fitted",
      testCase "root ADR 0466 I3: the remainder of the rounding goes 1 sp at a time from the first space" $ case fitted (4 * fs + 2) [txt "あいう"] of
        Just its -> do
          lineLength its @?= 4 * fs + 2
          gapsOf its @?= [Sp (unSp fs `div` 2 + 1), Sp (unSp fs `div` 2 + 1)]
        Nothing -> assertFailure "not fitted",
      testCase "root ADR 0466 I3: an odd remainder: the first space 1 sp wider than the second" $ case fitted (4 * fs + 1) [txt "あいう"] of
        Just its -> do
          lineLength its @?= 4 * fs + 1
          gapsOf its @?= [Sp (unSp fs `div` 2 + 1), Sp (unSp fs `div` 2)]
        Nothing -> assertFailure "not fitted",
      testCase "root ADR 0466 I3: the spaces of any width differ by 1 sp at most" $
        sequence_
          [ case fitted (Sp w) [txt t] of
              Just its -> do
                lineLength its @?= Sp w
                let gs = gapsOf its
                assertBool (show (t, w, gs)) (maximum gs - minimum gs <= 1)
              Nothing -> assertFailure ("not fitted: " <> show (t, w))
          | t <- ["あい", "あいう", "あいうえ", "あいうえおかき"],
            k <- [7 .. 9 :: Integer],
            d <- [0, 1, 5, 6],
            let w = k * unSp fs + d
          ],
      testCase "root ADR 0466 I3: a Latin word is spread between its graphemes" $ case fitted (6 * fs) [txt "abc"] of
        Just its -> do
          lineLength its @?= 6 * fs
          [t | (t, _) <- boxes its, not (T.null t)] @?= ["a", "b", "c"]
          let gs = gapsOf its
          length gs @?= 2
          assertBool (show gs) (maximum gs - minimum gs <= 1)
        Nothing -> assertFailure "not fitted",
      testCase "root ADR 0466 I3: a space between words is a grapheme of its own" $ case fitted (8 * fs) [txt "ab cd"] of
        Just its -> do
          lineLength its @?= 8 * fs
          [t | (t, _) <- boxes its, not (T.null t)] @?= ["a", "b", "c", "d"]
        Nothing -> assertFailure "not fitted",
      testCase "root ADR 0466 I2: the fitted line has no break in it" $ case fitted (4 * fs) [txt "目次"] of
        Just its -> [p | Penalty _ p _ <- its, p < 10000] @?= [-10000]
        Nothing -> assertFailure "not fitted"
    ]
