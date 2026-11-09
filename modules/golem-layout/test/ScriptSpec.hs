{- | The ranges of superscript and subscript in the line breaking
(docs/adr/0269): no break before a range nor inside it, and after it the
spacing and the breaks of the pair around it, over every small input.
-}
module ScriptSpec (scriptTests) where

import Control.Monad (forM_, replicateM)
import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Golem.Project.Position (Position (..))
import Test.Tasty
import Test.Tasty.HUnit

-- | The character styles sup and sub, as golem-typeset's restyle sets them; size 1zw nested in sz.
env :: ComposeEnv
env =
  (defaultComposeEnv fs)
    { ceRestyle = \lk -> \case
        IR.CharStyle _ "sup" _ -> lk {lkPosition = PositionSuperscript, lkNominalSize = lkSize lk}
        IR.CharStyle _ "sub" _ -> lk {lkPosition = PositionSubscript, lkNominalSize = lkSize lk}
        IR.CharStyle _ "sz" _ -> lk {lkNominalSize = lkSize lk}
        _ -> lk
    }

items :: [IR.Inline] -> [Item]
items = fst . composeInlines env

boxesOf :: [Item] -> [BoxContent]
boxesOf its = [c | Box _ c <- its]

isScriptBox :: BoxContent -> Bool
isScriptBox = (/= PositionNormal) . lkPosition . bcLook

-- | The characters of the inputs: an ideograph, a kana, brackets, a full stop and a Latin letter.
alphabet :: [Text]
alphabet = ["漢", "あ", "「", "」", "。", "a"]

-- | Every text of the alphabet up to a length.
upTo :: Int -> [Text]
upTo n = concat [map T.concat (replicateM k alphabet) | k <- [0 .. n]]

-- | The contents of a range: one or two digits and ideographs.
ranges :: [Text]
ranges = [T.concat r | k <- [1, 2], r <- replicateM k ["2", "漢"]]

inputs :: [(Text, Text, Text)]
inputs = [(b, r, a) | b <- upTo 2, r <- ranges, a <- upTo 2]

scripted :: (Text, Text, Text) -> [IR.Inline]
scripted (b, r, a) = [IR.Text sp b | not (T.null b)] <> [IR.CharStyle sp "sup" [IR.Text sp r]] <> [IR.Text sp a | not (T.null a)]

removed :: (Text, Text, Text) -> [IR.Inline]
removed (b, _, a) = [IR.Text sp b | not (T.null b)] <> [IR.Text sp a | not (T.null a)]

-- | The items between the box at an index and the next box, and the next box.
itemsAfter :: Int -> [Item] -> ([Item], Maybe BoxContent)
itemsAfter i its =
  let rest = drop (i + 1) its
      (between, more) = break isBox rest
   in (between, case more of Box _ c : _ -> Just c; _ -> Nothing)
  where
    isBox = \case
      Box {} -> True
      _ -> False

-- | The index among the items of the n-th box (from 0).
boxIndex :: Int -> [Item] -> Int
boxIndex n its = case drop n [i | (i, Box {}) <- zip [0 ..] its] of
  i : _ -> i
  [] -> -1

scriptTests :: TestTree
scriptTests =
  testGroup
    "superscript and subscript in the line breaking (docs/adr/0269)"
    [ testCase "I5: no line starts at the first character of a range nor inside it" $
        forM_ inputs $ \inp -> forM_ [2 .. 5 :: Int] $ \em -> do
          let ls = brLines (breakParagraph defaultParams (const (fromIntegral em * fs)) (items (scripted inp)))
          forM_ (drop 1 ls) $ \l -> case boxesOf (lineItems l) of
            c : _ -> assertBool (show (inp, em)) (not (isScriptBox c))
            [] -> pure (),
      testCase "I6: after a range, the spacing and the breaks of the pair around it" $
        forM_ inputs $ \inp@(b, _, a) -> do
          let s = items (scripted inp)
              plain = items (removed inp)
              k = length (boxesOf (items [IR.Text sp b | not (T.null b)]))
              lastScript = last [i | (i, Box _ c) <- zip [0 ..] s, isScriptBox c]
              (betweenS, nextS) = itemsAfter lastScript s
              (betweenP, nextP) = if k == 0 then (takeWhile (not . isBoxItem) plain, firstBox plain) else itemsAfter (boxIndex (k - 1) plain) plain
          if T.null a
            then pure ()
            else do
              {- at the start of a paragraph no line breaks before the first
              character; after a range there, a penalty keeps it so -}
              if T.null b
                then assertEqual (show inp) betweenP (filter (not . unbreakable) betweenS)
                else assertEqual (show inp) betweenP betweenS
              assertEqual (show inp) (fmap bcText nextP) (fmap bcText nextS),
      testCase "I4: the same position nested is as the range not nested" $ do
        let nested = boxesOf (items [IR.Text sp "漢", IR.CharStyle sp "sup" [IR.Text sp "2", IR.CharStyle sp "sup" [IR.Text sp "3"]]])
            flat = boxesOf (items [IR.Text sp "漢", IR.CharStyle sp "sup" [IR.Text sp "2", IR.Text sp "3"]])
        map (\c -> (lkSize (bcLook c), lkBaselineShift (bcLook c), lkPosition (bcLook c))) nested
          @?= map (\c -> (lkSize (bcLook c), lkBaselineShift (bcLook c), lkPosition (bcLook c))) flat,
      testCase "I3: synthesis sets 7/12 of the nominal size and moves it by a third" $ do
        let looks inl = map bcLook (drop 1 (boxesOf (items [IR.Text sp "漢", inl])))
        map (\l -> (lkSize l, lkBaselineShift l)) (looks (IR.CharStyle sp "sup" [IR.Text sp "2"])) @?= [(Sp ((7 * unSp fs) `div` 12), Sp (unSp fs `div` 3))]
        map (\l -> (lkSize l, lkBaselineShift l)) (looks (IR.CharStyle sp "sub" [IR.Text sp "2"])) @?= [(Sp ((7 * unSp fs) `div` 12), negate (Sp (unSp fs `div` 3)))],
      testCase "a superscript inside a subscript is a range of its own, from the nominal size" $ do
        let ls = map bcLook (boxesOf (items [IR.CharStyle sp "sub" [IR.Text sp "2", IR.CharStyle sp "sup" [IR.Text sp "3"]]]))
        map (\l -> (lkPosition l, lkSize l)) ls @?= [(PositionSubscript, Sp ((7 * unSp fs) `div` 12)), (PositionSuperscript, Sp ((7 * unSp fs) `div` 12))],
      testCase "the font's glyphs: the size stays and no shift" $ do
        let glyphEnv = env {ceScriptGlyphs = \_ _ -> True}
            ls = map bcLook (boxesOf (fst (composeInlines glyphEnv [IR.CharStyle sp "sup" [IR.Text sp "2"]])))
        map (\l -> (lkSize l, lkBaselineShift l, lkScriptGlyphs l)) ls @?= [(fs, 0, True)],
      testCase "the method is decided once for the range: every character is asked" $ do
        let asked = env {ceScriptGlyphs = \_ cs -> map snd cs == "2a"}
            ls = map bcLook (boxesOf (fst (composeInlines asked [IR.CharStyle sp "sup" [IR.Text sp "2", IR.CharStyle sp "sz" [IR.Text sp "a"]]])))
        map lkScriptGlyphs ls @?= [True, True],
      testCase "a range at the start of a paragraph stays whole on the first line" $ do
        let ls = brLines (breakParagraph defaultParams (const (2 * fs)) (items [IR.CharStyle sp "sup" [IR.Text sp "漢漢漢漢漢漢"], IR.Text sp "漢漢"]))
        case ls of
          l : _ -> length (filter isScriptBox (boxesOf (lineItems l))) @?= 6
          [] -> assertFailure "no line"
    ]
  where
    unbreakable = \case
      Penalty _ p NoHyphen -> p >= infPenalty
      _ -> False
    isBoxItem = \case
      Box {} -> True
      _ -> False
    firstBox its = case [c | Box _ c <- its] of
      c : _ -> Just c
      [] -> Nothing
