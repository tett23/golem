{- | Punctuation whose glyph is narrower than full width (docs/adr/0302):
its box is max a (1zw - aki) wide and its glyph is drawn inside it.
-}
module NarrowPunctuationSpec (narrowPunctuationTests) where

import Control.Monad (forM_)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (compose, fs)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Golem.Length (zwToSp)
import Test.Tasty
import Test.Tasty.HUnit

-- | The advances of a font whose quotes are narrow (Source Serif 4: “” 0.415 em, ’ 0.212 em).
narrowAdvance :: Char -> Maybe Rational
narrowAdvance = \case
  '\x201C' -> Just (415 / 1000)
  '\x201D' -> Just (415 / 1000)
  '\x2019' -> Just (212 / 1000)
  _ -> Nothing

narrowEnv :: Bool -> ComposeEnv
narrowEnv v =
  let base = defaultComposeEnv fs
   in base {ceAdvance = \lk c -> fromMaybe (ceAdvance base lk c) (narrowAdvance c), ceVertical = v}

-- | The items with their natural start along the line.
placedNatural :: [Item] -> [(Item, Sp)]
placedNatural items = zip items (scanl (+) 0 (map width items))
  where
    width = \case
      Box w _ -> w
      Glue {itemWidth = w} -> w
      _ -> 0

{- | Each punctuation box of one narrow character: its start, the end of
its box, where its glyph starts and its advance, and the end of the box
before it and the start of the box after it.
-}
narrowBoxes :: ComposeEnv -> [Item] -> [(Text, Sp, Sp, Sp, Sp, Maybe Sp, Maybe Sp)]
narrowBoxes env items =
  [ (bcText c, s, s + w, s + off, a, prevEnd, nextStart)
  | (i, (Box w c, s)) <- zip [0 :: Int ..] placed,
    [ch] <- [T.unpack (bcText c)],
    boxKind c == KindPunctuation,
    let lk = bcLook c
        a = zwToSp (lkSize lk) (ceAdvance env lk ch),
    Just (_, off) <- [narrowPunctuation (lookClass lk ch) (lkSize lk) a],
    let prevEnd = case [s' + w' | (Box w' _, s') <- reverse (take i placed)] of (e : _) -> Just e; [] -> Nothing
        nextStart = case [s' | (Box _ _, s') <- drop (i + 1) placed] of (n : _) -> Just n; [] -> Nothing
  ]
  where
    placed = placedNatural items

narrowPunctuationTests :: TestTree
narrowPunctuationTests =
  testGroup
    "punctuation narrower than full width (docs/adr/0302)"
    [ testCase "N1, N4, N5: the glyph of narrow punctuation is inside its box and does not reach its neighbours" $
        forM_ [False, True] $ \v ->
          forM_ ["he said \x201D here", "he said \x2019 here", "he said \x201C here", "x \x201D y \x201D z", "あ\x201Cい\x201Dう", "\x201Cあ\x201D", "あ\x201D"] $ \t -> do
            let env = narrowEnv v
                bs = narrowBoxes env (compose env t)
            assertBool ("narrow punctuation in " <> show t) (not (null bs))
            forM_ bs $ \(ch, s, e, x, a, prev, next) -> do
              assertBool ("N1 start " <> show (t, ch, v)) (s <= x)
              assertBool ("N1 end " <> show (t, ch, v)) (x + a <= e)
              assertBool ("N4 next " <> show (t, ch, v)) (maybe True (x + a <=) next)
              assertBool ("N4 previous " <> show (t, ch, v)) (maybe True (<= x) prev),
      testCase "N4, N5: at the end and at the start of a line the glyph stays inside the line" $
        forM_ [False, True] $ \v ->
          forM_ ["あいう\x201Dえお", "あいうえ\x201Cおか", "abc \x201D def"] $ \t -> do
            let env = narrowEnv v
                measure = 4 * fs
                ls = brLines (breakParagraph defaultParams (const measure) (compose env t))
                inLine =
                  [ (bcText c, x, x + a)
                  | l <- ls,
                    (Box _ c, s) <- placeLine l,
                    [ch] <- [T.unpack (bcText c)],
                    boxKind c == KindPunctuation,
                    let lk = bcLook c
                        a = zwToSp (lkSize lk) (ceAdvance env lk ch),
                    Just (_, off) <- [narrowPunctuation (lookClass lk ch) (lkSize lk) a],
                    let x = s + off
                  ]
            assertBool ("narrow punctuation in " <> show t) (not (null inLine))
            forM_ inLine $ \(ch, x, e) -> assertBool (show (t, ch, v, x, e)) (x >= 0 && e <= measure),
      testCase "N2: narrow punctuation takes a full width with its aki" $
        forM_ [False, True] $ \v -> do
          let env = narrowEnv v
          forM_ [b | Box _ b <- compose env "あ\x201Cい\x201Dう", boxKind b == KindPunctuation] $ \c -> do
            let ch = T.head (bcText c)
                (pre, post) = punctSpace (lookClass (bcLook c) ch)
            case [w | Box w c' <- compose env "あ\x201Cい\x201Dう", bcText c' == bcText c] of
              [w] -> assertBool (show (bcText c, w)) (w + zwToSp fs (pre + post) >= fs)
              other -> assertFailure (show other),
      testCase "N1, N2, N3: the box of every class and advance" $
        forM_ [Opening, Closing, FullStop, Comma, MiddleDot] $ \cls ->
          forM_ [212 / 1000, 415 / 1000, 1 / 2, 3 / 4, 1, 6 / 5 :: Rational] $ \r -> do
            let a = zwToSp fs r
                (pre, post) = punctSpace cls
            case narrowPunctuation cls fs a of
              Just (w, off)
                | r < 1 -> do
                    assertBool ("N1 " <> show (cls, r)) (off >= 0 && off + a <= w)
                    assertBool ("N2 " <> show (cls, r)) (w + zwToSp fs (pre + post) >= fs)
                    w @?= max a (fs - zwToSp fs (pre + post))
              Nothing | r >= 1 -> pure ()
              other -> assertFailure ("N3 " <> show (cls, r, other)),
      testCase "N3: punctuation that is not narrow, and characters that are not punctuation, have no narrow box" $ do
        narrowPunctuation Ideograph fs (zwToSp fs (1 / 2)) @?= Nothing
        narrowPunctuation Western fs (zwToSp fs (1 / 2)) @?= Nothing
        [w | Box w _ <- compose (defaultComposeEnv fs) "あ「い」う"] @?= [fs, zwToSp fs (1 / 2), fs, zwToSp fs (1 / 2), fs]
    ]
