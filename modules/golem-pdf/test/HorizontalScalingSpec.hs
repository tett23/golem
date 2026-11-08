{- | The horizontal scaling of the glyph marks does not outlive them
(golem-pdf ADR 0015). The content stream is read as the invariants of
the ADR read it: the q and Q stack, BT and ET, Tz, Tm and Tj (and Do,
for the figures), from the initial scaling of 100. The reader is the
'glyphsOf' of golem-driver's TateChuYokoSpec, copied here: golem-pdf
does not depend on golem-driver.

The scaling of a mark: that of a 'ScaledGlyphRun' or of the 'rsScale' of
a 'StyledGlyphRun'; 100 for the other glyph marks. All the numbers here
are in permille, 1000 being 100.
-}
module HorizontalScalingSpec (tests) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (mapAccumL)
import Data.Map.Strict qualified as Map
import Golem.Pdf.Rect (Rect (..))
import Golem.Pdf.Structure (LeafId (..))
import Golem.Pdf.Writer
import Golem.TestSupport.Enum
import Numeric (readHex)
import Test.Tasty
import Test.Tasty.HUnit

-- ------------------------------------------------------------------ the reader

-- | What a content stream draws: a glyph and the scaling in force, or a form and the scaling in force.
data Drawn = DrawnGlyph !GlyphId !Rational | DrawnForm !Rational
  deriving stock (Eq, Show)

-- | What is drawn, and the scaling and the depth of q at the end.
data Reading = Reading {rDrawn :: [Drawn], rScale :: Rational, rDepth :: Int}
  deriving stock (Eq, Show)

{- | Reads a content stream from a scaling (permille) and the depth 0. A
Q without its q lowers the depth below 0 and keeps the scaling.
-}
readStream :: Rational -> ByteString -> Reading
readStream tz0 content = go [] tz0 0 [] (BC.words content)
  where
    go _ tz depth _ [] = Reading [] tz depth
    go saved tz depth ops (w : ws) = case w of
      "q" -> go (tz : saved) tz (depth + 1) [] ws
      "Q" -> case saved of
        (s : rest) -> go rest s (depth - 1) [] ws
        [] -> go [] tz (depth - 1) [] ws
      "Tz" | (z : _) <- ops -> go saved (number z * 10) depth [] ws
      "Tj" | (g : _) <- ops -> DrawnGlyph (glyph g) tz `cons` go saved tz depth [] ws
      "Do" -> DrawnForm tz `cons` go saved tz depth [] ws
      _
        | isOperator w -> go saved tz depth [] ws
        | otherwise -> go saved tz depth (w : ops) ws
    cons d r = r {rDrawn = d : rDrawn r}
    isOperator w = not (BS.null w) && BC.all (`elem` ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ*'\"" :: String)) w
    glyph g = case readHex (BC.unpack (BC.filter (`notElem` ("<>" :: String)) g)) of
      [(n, "")] -> n
      _ -> -1
    number t = case BC.split '.' t of
      [i] -> fromInteger (read (BC.unpack i))
      [i, f] -> fromInteger (read (BC.unpack i)) + fromInteger (read (BC.unpack f)) / 10 ^ BS.length f
      _ -> 0

-- ------------------------------------------------------------------ the marks

font :: FontRef
font = FontRef 7

size :: Sp
size = 10 * 65536

stream :: [Mark] -> ByteString
stream = contentStream (Map.fromList [(font, 1)]) Map.empty

-- | Each glyph a mark draws, with the scaling it is drawn with, in order.
expected :: Mark -> [(GlyphId, Rational)]
expected = \case
  GlyphRun _ _ gs -> [(g, 1000) | (g, _, _) <- gs]
  ScaledGlyphRun _ _ s gs -> [(g, fromIntegral s) | (g, _, _) <- gs]
  RotatedGlyphRun _ _ gs -> [(g, 1000) | (g, _, _) <- gs]
  StyledGlyphRun st _ _ gs -> [(g, fromIntegral (rsScale st)) | (g, _, _) <- gs]
  TransformedGlyphRun _ _ _ gs -> [(g, 1000) | (_, g, _, _) <- gs]
  Saved ms -> concatMap expected ms
  Translated _ _ ms -> concatMap expected ms
  ActualText _ ms -> concatMap expected ms
  Turned _ _ ms -> concatMap expected ms
  _ -> []

-- | Gives the glyphs the numbers 1, 2, ... in order, so that each glyph drawn is known.
numbered :: [Mark] -> [Mark]
numbered = snd . mapAccumL mark 1
  where
    mark n = \case
      GlyphRun f s gs -> let (n', gs') = plain n gs in (n', GlyphRun f s gs')
      ScaledGlyphRun f s sc gs -> let (n', gs') = plain n gs in (n', ScaledGlyphRun f s sc gs')
      RotatedGlyphRun f s gs -> let (n', gs') = plain n gs in (n', RotatedGlyphRun f s gs')
      StyledGlyphRun st f s gs -> let (n', gs') = plain n gs in (n', StyledGlyphRun st f s gs')
      TransformedGlyphRun f s w gs -> let (n', gs') = mapAccumL (\k (t, _, x, y) -> (k + 1, (t, k, x, y))) n gs in (n', TransformedGlyphRun f s w gs')
      Saved ms -> Saved <$> mapAccumL mark n ms
      Translated x y ms -> Translated x y <$> mapAccumL mark n ms
      ActualText t ms -> ActualText t <$> mapAccumL mark n ms
      Turned t r ms -> Turned t r <$> mapAccumL mark n ms
      other -> (n, other)
    plain = mapAccumL (\k (_, x, y) -> (k + 1, (k, x, y)))

glyphs :: Bool -> [(GlyphId, Sp, Sp)]
glyphs b = [(0, 65536, -65536) | b]

-- | The marks without marks inside, each with no glyph or one.
atoms :: Tiers Mark
atoms =
  Tiers
    [ [ m
      | b <- [False, True],
        m <-
          [ GlyphRun font size (glyphs b),
            ScaledGlyphRun font size 985 (glyphs b),
            ScaledGlyphRun font size 1000 (glyphs b),
            ScaledGlyphRun font size 1015 (glyphs b),
            StyledGlyphRun (RunStyle 1000 False 0 0) font size (glyphs b),
            StyledGlyphRun (RunStyle 1050 False 0 0) font size (glyphs b),
            RotatedGlyphRun font size (glyphs b),
            TransformedGlyphRun font size 0 [((1, 0, 0, 1), g, x, y) | (g, x, y) <- glyphs b]
          ]
      ]
        <> [Form (FormRef 1) (Rect 0 0 65536 65536)]
    ]

-- | The atoms, and Saved, Translated and ActualText around up to three marks.
marks :: Tiers Mark
marks =
  atoms
    \/ cons1 Saved upToThree
    \/ cons1 (Translated 65536 65536) upToThree
    \/ cons1 (ActualText "x") upToThree

upToThree :: Tiers [Mark]
upToThree = filterT ((<= 3) . length) (listsOf marks)

-- | The largest tier checked.
tierLimit :: Int
tierLimit = 5

-- ------------------------------------------------------------------ the invariants

{- | I1: each glyph of a sequence is drawn with the scaling of its mark;
and, by I2, a form is drawn with the scaling of the page.
-}
i1 :: [Mark] -> [Violation]
i1 ms =
  let drawn = rDrawn (readStream 1000 (stream ms))
      want = concatMap expected ms
      got = [(g, tz) | DrawnGlyph g tz <- drawn]
   in [Violation "I1" (show (want, got)) | want /= got]
        <> [Violation "I2: Do" (show tz) | DrawnForm tz <- drawn, tz /= 1000]

-- | I2: a mark ends with the scaling and the depth of q it began with, from 100 and from 105.
i2 :: Mark -> [Violation]
i2 m =
  [ Violation "I2" (show (tz0, r))
  | tz0 <- [1000, 1050],
    let r = readStream tz0 (stream [m]),
    (rScale r, rDepth r) /= (tz0, 0)
  ]

checked :: (Show a) => String -> Tiers a -> (a -> [Violation]) -> Assertion
checked rule xs check = case checkAll tierLimit xs check of
  Passed n -> assertBool (rule <> ": the values checked: " <> show n) (n > 1000)
  Failed t x vs -> assertFailure (rule <> ": the value of tier " <> show t <> ": " <> show x <> "\n" <> unlines (map show vs))

-- ------------------------------------------------------------------ the tests

one :: Mark -> Mark
one = \case
  GlyphRun f s _ -> GlyphRun f s (glyphs True)
  ScaledGlyphRun f s sc _ -> ScaledGlyphRun f s sc (glyphs True)
  other -> other

scaled :: Int -> Mark
scaled sc = one (ScaledGlyphRun font size sc [])

plainRun :: Mark
plainRun = one (GlyphRun font size [])

-- | The scalings of the glyphs drawn, in order.
scalings :: [Mark] -> [Rational]
scalings ms = [tz | DrawnGlyph _ tz <- rDrawn (readStream 1000 (stream (numbered ms)))]

ends :: [Mark] -> (Rational, Int)
ends ms = let r = readStream 1000 (stream ms) in (rScale r, rDepth r)

tests :: TestTree
tests =
  testGroup
    "the horizontal scaling of a scaled glyph run does not outlive it (golem-pdf ADR 0015)"
    [ testCase "I1, I2: every sequence of up to three marks draws each glyph with the scaling of its mark, and each form with 100" $
        checked "I1" (mapT numbered upToThree) i1,
      testCase "I2: every mark ends with the scaling and the depth of q it began with" $ checked "I2" marks i2,
      testCase "I2, I3: the empty sequence writes nothing" $ do
        stream [] @?= ""
        ends [] @?= (1000, 0),
      testCase "I1, I2: a scaled run of 985 alone" $ do
        scalings [scaled 985] @?= [985]
        ends [scaled 985] @?= (1000, 0),
      testCase "I1, I2: a glyph run after a scaled run of 985 without glyphs" $ do
        scalings [ScaledGlyphRun font size 985 [], plainRun] @?= [1000]
        ends [ScaledGlyphRun font size 985 []] @?= (1000, 0),
      testCase "I1: a glyph run after a scaled run of 985" $
        scalings [scaled 985, plainRun] @?= [985, 1000],
      testCase "I1: a styled run of rsScale 1000 after a scaled run of 985" $
        scalings [scaled 985, StyledGlyphRun (RunStyle 1000 False 0 0) font size (glyphs True)] @?= [985, 1000],
      testCase "I1: a styled run of rsScale 1050 after a scaled run of 985" $
        scalings [scaled 985, StyledGlyphRun (RunStyle 1050 False 0 0) font size (glyphs True)] @?= [985, 1050],
      testCase "I1: a rotated run and a transformed run after a scaled run of 985" $
        scalings [scaled 985, RotatedGlyphRun font size (glyphs True), TransformedGlyphRun font size 0 [((1, 0, 0, 1), 0, 0, 0)]] @?= [985, 1000, 1000],
      testCase "I1: a scaled run of 1015 after a scaled run of 985" $
        scalings [scaled 985, scaled 1015] @?= [985, 1015],
      testCase "I1, I2: a glyph run after a scaled run of 985 in ActualText" $ do
        scalings [ActualText "x" [scaled 985], plainRun] @?= [985, 1000]
        ends [ActualText "x" [scaled 985]] @?= (1000, 0),
      testCase "I1, I2: a glyph run after a scaled run of 985 in Saved" $ do
        scalings [Saved [scaled 985], plainRun] @?= [985, 1000]
        ends [Saved [scaled 985]] @?= (1000, 0),
      testCase "I1: a glyph run after a scaled run of 985 in the same Translated" $
        scalings [Translated 65536 0 [scaled 985, plainRun]] @?= [985, 1000],
      testCase "I2: a form after a scaled run of 985 is drawn with the scaling of the page" $
        [d | d@(DrawnForm _) <- rDrawn (readStream 1000 (stream [scaled 985, Form (FormRef 1) (Rect 0 0 65536 65536)]))] @?= [DrawnForm 1000],
      testCase "I1: a scaled run of 985 and a glyph run in separate tagged pieces" $ do
        let (cs, _) = pageStream (Map.fromList [(font, 1)]) Map.empty Map.empty (const "P") [Tagged (LeafId [0]) [scaled 985], Tagged (LeafId [1]) [GlyphRun font size [(1, 0, 0)]]]
        [tz | DrawnGlyph _ tz <- rDrawn (readStream 1000 cs)] @?= [985, 1000],
      testCase "I1, I2: a scaled run of 1000 is drawn and left at 100" $ do
        scalings [scaled 1000, plainRun] @?= [1000, 1000]
        ends [scaled 1000] @?= (1000, 0),
      testCase "I3: a sequence of glyph runs only writes the bytes of before the ADR" $
        stream [GlyphRun font size [(2, 65536, -65536)], GlyphRun font size [(3, 0, 0)]]
          @?= "BT /F1 10 Tf\n1 0 0 1 1 -1 Tm <0002> Tj\nET\nBT /F1 10 Tf\n1 0 0 1 0 0 Tm <0003> Tj\nET\n",
      testCase "I3: the other marks without a scaled run write the bytes of before the ADR" $
        stream [StyledGlyphRun (RunStyle 1050 False 0 0) font size [(2, 0, 0)], RotatedGlyphRun font size [(3, 0, 0)], Saved [GlyphRun font size [(4, 0, 0)]]]
          @?= "q BT /F1 10 Tf 105 Tz\n1 0 0 1 0 0 Tm <0002> Tj\nET Q\nBT /F1 10 Tf\n0 -1 1 0 0 0 Tm <0003> Tj\nET\nq\nBT /F1 10 Tf\n1 0 0 1 0 0 Tm <0004> Tj\nET\nQ\n",
      testCase "a scaled run is written inside q and Q" $
        stream [ScaledGlyphRun font size 985 [(2, 65536, -65536)]] @?= "q BT /F1 10 Tf 98.5 Tz\n1 0 0 1 1 -1 Tm <0002> Tj\nET Q\n"
    ]
