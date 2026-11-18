{- | The kanji numbers of the marks of notes set flat in vertical text
(docs/adr/0381): each kanji of the number half its advance along the line,
the text around the number and Arabic numbers as they are.
-}
module CompressedNoteMarksSpec (compressedNoteMarksTests) where

import Control.Monad (forM_)
import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, sp0)
import Golem.Doc.IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Golem.Syntax (FileId (..), mkSpan)
import Test.Tasty
import Test.Tasty.HUnit

-- | A note of a number, its body one character.
note :: Int -> Inline
note n = Note (mkSpan (FileId 0) 1 2) n (noteBody (mkSpan (FileId 0) 1 2) [sp0 "注"])

{- | The environment of a mark format, vertical or not, flat or not: the
characters of uneven advances, so that halving each one is seen.
-}
envOf :: Text -> Bool -> Bool -> IO ComposeEnv
envOf format vertical flat = do
  fmt <- either (assertFailure . T.unpack) pure (parseMarkFormat format)
  pure
    (defaultComposeEnv fs)
      { ceNoteMarkFormat = fmt,
        ceNoteMarkFlat = flat,
        ceVertical = vertical,
        ceAdvance = \_ c -> if c == '十' then 9 / 10 else if c == '（' then 3 / 4 else 1,
        ceWordAdvance = \_ t -> fromIntegral (T.length t) / 2
      }

-- | The box of the mark of a note n in the text.
markOf :: ComposeEnv -> Int -> IO (Sp, BoxContent)
markOf env n = case [(w, c) | Box w c <- fst (composeInlines env [sp0 "漢", note n, sp0 "字"]), boxKind c == KindNoteMark] of
  [m] -> pure m
  other -> assertFailure (show (length other) <> " marks")

{- | Each part of a mark with its advance along the line: the start of the
next part, or the width of the box, less its start.
-}
advancesOf :: (Sp, BoxContent) -> [(BoxKind, Text, Sp)]
advancesOf (w, c) =
  let parts = maybe [] mbParts (bcMark c)
      ends = drop 1 [o | (_, _, o) <- parts] <> [w - bcPadEnd c]
   in [(toEnum k, t, e - o) | ((k, t, o), e) <- zip parts ends]

compressedNoteMarksTests :: [TestTree]
compressedNoteMarksTests =
  [ testCase "ADR 0381 I1: inv1_compressed_note_marks_property" $
      forM_ ["{n:kanji}", "（{n:kanji}）", "注{n:kanji-digits}", "{n:kanji-digits}）"] $ \format -> do
        normal <- envOf format True False
        flat <- envOf format True True
        forM_ ([1 .. 40] <> [99, 100, 101, 110, 120, 1000, 2026]) $ \n -> do
          plain <- advancesOf <$> markOf normal n
          flattened <- advancesOf <$> markOf flat n
          let msg = T.unpack format <> " " <> show n
          -- the same characters, one box each
          assertEqual msg (map (\(_, t, _) -> t) plain) (map (\(_, t, _) -> t) flattened)
          -- the kanji of the number: half their advance, flat; the text around: as it is
          let number = T.unpack (T.concat [t | (KindFlat, t, _) <- flattened])
          assertBool msg (not (null number))
          forM_ (zip plain flattened) $ \((k0, t, a0), (k1, _, a1)) ->
            if k1 == KindFlat
              then do
                assertEqual msg KindText k0
                assertEqual (msg <> " " <> T.unpack t) (Sp (unSp a0 `div` 2)) a1
              else assertEqual (msg <> " " <> T.unpack t) (k0, a0) (k1, a1),
    testCase "ADR 0381 I1: inv1_compressed_note_marks_case_1: one kanji advances half an em" $ do
      env <- envOf "{n:kanji}" True True
      (w, c) <- markOf env 3
      let m = lkSizeOf c
      advancesOf (w, c) @?= [(KindFlat, "三", Sp (unSp m `div` 2))]
      w @?= Sp (unSp m `div` 2),
    testCase "ADR 0381 I1: inv1_compressed_note_marks_case_2: two kanji advance one em" $ do
      env <- envOf "{n:kanji-digits}" True True
      (w, c) <- markOf env 12
      let m = lkSizeOf c
      advancesOf (w, c) @?= [(KindFlat, "一", Sp (unSp m `div` 2)), (KindFlat, "二", Sp (unSp m `div` 2))]
      w @?= m,
    testCase "ADR 0381 I1: inv1_compressed_note_marks_case_3: horizontal text sets the usual mark" $
      forM_ ["{n:kanji}", "（{n:kanji}）"] $ \format -> do
        normal <- envOf format False False
        flat <- envOf format False True
        forM_ [1 :: Int, 3, 12, 120] $ \n -> do
          a <- markOf normal n
          b <- markOf flat n
          b @?= a,
    testCase "ADR 0381: Arabic numbers, tate-chu-yoko or turned, and other notations are as they are" $
      forM_ ["{n}", "（{n}）", "{n:circled}", "{n:upper-roman}", "{n:iroha}"] $ \format -> do
        normal <- envOf format True False
        flat <- envOf format True True
        forM_ [1 :: Int, 3, 12, 123] $ \n -> do
          a <- markOf normal n
          b <- markOf flat n
          assertEqual (T.unpack format <> " " <> show n) a b,
    testCase "ADR 0381: the mark at the start of a note body is set flat as the mark in the text" $ do
      normal <- envOf "（{n:kanji}）" True False
      flat <- envOf "（{n:kanji}）" True True
      fmt <- either (assertFailure . T.unpack) pure (parseMarkFormat "（{n:kanji}）")
      let MarkFormat pre notation suf = fmt
          -- the mark at the start of the body: one text in the look of the body, made one box
          labelOf env = markLabelBox env {ceSite = [5]} ChannelNote 12 (fst (composeInlines env {ceSite = [5]} [Text (mkSpan (FileId 0) 1 2) (markPartsText (markParts True pre notation 12 suf))]))
      case ([(w, c) | Box w c <- labelOf flat], [(w, c) | Box w c <- labelOf normal]) of
        ([(w, c)], [(w0, c0)]) -> do
          [k | (k, _, _) <- advancesOf (w0, c0)] @?= replicate 4 KindText
          -- the kanji of the number half their advance in the body too, the parentheses as they are
          advancesOf (w, c) @?= [if t `elem` ["十", "二"] then (KindFlat, t, Sp (unSp a `div` 2)) else (k, t, a) | (k, t, a) <- advancesOf (w0, c0)]
          -- not numbered per page: no number to give again
          mbNumber <$> bcMark c @?= Just Nothing
        other -> assertFailure (show other)
  ]
  where
    lkSizeOf c = lkSize (bcLook c)
