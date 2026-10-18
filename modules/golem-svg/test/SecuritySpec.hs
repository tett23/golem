{- | Hostile SVG figures end within limits of time and allocation (the
security audit of 2026-10-18, candidates C8 to C11). Each input is small;
what is asserted is that reading it is bounded: it is refused with what
becomes G0810 or G0811, or it is read in a time and an allocation
proportional to the input.
-}
module SecuritySpec (tests) where

import Control.Exception (SomeException, evaluate, try)
import Data.ByteString (ByteString)
import Data.Ratio (denominator, numerator)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import GHC.Clock (getMonotonicTime)
import GHC.Stats (allocated_bytes, getRTSStats, getRTSStatsEnabled)
import Golem.Svg
import Golem.Svg.Css (parseStylesheet)
import Golem.Svg.Xml (parseXml)
import Test.Tasty
import Test.Tasty.HUnit

-- ------------------------------------------------------------------ helpers

svg :: Text -> ByteString
svg body = TE.encodeUtf8 ("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"50\">" <> body <> "</svg>")

-- | The result of reading, fully evaluated through 'show'; an exception is a failure.
total :: ByteString -> IO (Either SvgError Svg)
total b = do
  _ <- evaluate b
  r <- try (evaluate (let x = readSvg b in length (show x) `seq` x))
  case r of
    Left (e :: SomeException) -> assertFailure ("readSvg threw: " <> show e)
    Right x -> pure x

-- | Reading finished (refused or read).
finished :: Either SvgError Svg -> Assertion
finished = either (const (pure ())) (const (pure ()))

-- | Bytes allocated by an action (GHC.Stats; the suite runs with -T).
allocatedBy :: IO a -> IO (a, Integer)
allocatedBy act = do
  enabled <- getRTSStatsEnabled
  if not enabled
    then assertFailure "the test suite needs +RTS -T"
    else do
      before <- allocated_bytes <$> getRTSStats
      x <- act
      after' <- allocated_bytes <$> getRTSStats
      pure (x, toInteger (after' - before))

-- | Forces a parse of XML and counts its attributes and nodes.
parsed :: ByteString -> IO Int
parsed b = do
  _ <- evaluate b
  r <- try (evaluate (either T.length (length . show) (parseXml b)))
  case r of
    Left (e :: SomeException) -> assertFailure ("parseXml threw: " <> show e)
    Right n -> pure n

{- | Doubling the input of a linear algorithm about doubles its allocation;
a quadratic one allocates about four times as much. Fixed costs make the
ratio of a linear one a little over 2, so 3 is the line drawn.
-}
linearIn :: (Int -> IO a) -> Int -> Assertion
linearIn act n = do
  (_, small) <- allocatedBy (act n)
  (_, large) <- allocatedBy (act (2 * n))
  let ratio = fromInteger large / fromInteger (max 1 small) :: Double
  assertBool ("allocation grew by " <> show ratio <> " (" <> show small <> " -> " <> show large <> " bytes)") (ratio < 3)

{- | The same for time, when the quadratic part does not allocate: the
line is drawn at 3 again, and the input is large enough for the two
runs to take well over a second together.
-}
linearTime :: (Int -> IO a) -> Int -> Assertion
linearTime act n = do
  t0 <- getMonotonicTime
  _ <- act n
  t1 <- getMonotonicTime
  _ <- act (2 * n)
  t2 <- getMonotonicTime
  let small = t1 - t0
      large = t2 - t1
      ratio = large / max 0.001 small
  assertBool ("time grew by " <> show ratio <> " (" <> show small <> " s -> " <> show large <> " s)") (ratio < 3)

seconds :: Integer -> Integer
seconds = (* 1000000)

-- | Every rational in a drawing, for checking their size.
rationals :: [DrawOp] -> [Rational]
rationals = concatMap $ \case
  DPath _ segs -> concatMap ofSegment segs
  DGroup (Matrix a b c d e f) _ ops -> [a, b, c, d, e, f] <> rationals ops
  where
    ofSegment = \case
      MoveTo (x, y) -> [x, y]
      LineTo (x, y) -> [x, y]
      CurveTo (a, b) (c, d) (e, f) -> [a, b, c, d, e, f]
      ClosePath -> []

-- | A rational whose numerator and denominator fit in 128 bits each is of a size a PDF can carry.
smallEnough :: Rational -> Bool
smallEnough r = abs (numerator r) < 2 ^ (128 :: Int) && denominator r < 2 ^ (128 :: Int)

-- ------------------------------------------------------------------ C8: markers

-- | A marker whose own path ends with the same marker.
selfMarker :: ByteString
selfMarker = svg "<defs><marker id=\"m\" orient=\"auto\"><path d=\"M0 0 L1 1\" marker-end=\"url(#m)\"/></marker></defs><path d=\"M0 0 L10 0\" stroke=\"#000\" marker-end=\"url(#m)\"/>"

{- | A chain of markers of the depth given: marker k holds a path of four
vertices, each with marker k - 1, so that the drawing has 4^depth groups.
-}
nestedMarkers :: Int -> ByteString
nestedMarkers depth =
  svg $
    "<defs><marker id=\"m0\"><path d=\"M0 0 L1 1\"/></marker>"
      <> T.concat ["<marker id=\"m" <> tshow k <> "\"><path d=\"M0 0 L1 0 L2 0 L3 0\" stroke=\"#000\" marker=\"url(#m" <> tshow (k - 1) <> ")\"/></marker>" | k <- [1 .. depth]]
      <> "</defs><path d=\"M0 0 L10 0\" stroke=\"#000\" marker-end=\"url(#m"
      <> tshow depth
      <> ")\"/>"
  where
    tshow = T.pack . show

-- ------------------------------------------------------------------ tests

tests :: TestTree
tests =
  testGroup
    "hostile SVG figures end within limits (security audit 2026-10-18)"
    [ localOption (mkTimeout (seconds 5))
        $ testCase "C8: a marker that refers to itself is refused or drawn finitely"
        $ total selfMarker >>= finished,
      localOption (mkTimeout (seconds 5))
        $ testCase "C8: markers nested 14 deep, four at each level, are refused or bounded (not 4^14 groups)"
        $ total (nestedMarkers 14) >>= finished,
      localOption (mkTimeout (seconds 30))
        $ testCase "C9: entity references are resolved in allocation linear in their number"
        $ linearIn (\n -> parsed (svg ("<desc>" <> T.replicate n "&amp;" <> "</desc>"))) 20000,
      localOption (mkTimeout (seconds 30))
        $ testCase "C9: CSS comments are stripped in allocation linear in their number"
        $ linearIn (\n -> evaluate (length (show (parseStylesheet (T.replicate n "/**/" <> "rect { fill: red }"))))) 20000,
      localOption (mkTimeout (seconds 30))
        $ testCase "C9: text split by comments is joined in allocation linear in the number of pieces"
        $ linearIn (\n -> parsed (svg ("<desc>" <> T.replicate n "a<!---->" <> "</desc>"))) 20000,
      localOption (mkTimeout (seconds 60))
        $ testCase "C10: an element of many attributes is checked for duplicates in time linear in their number"
        $ linearTime (\n -> parsed (TE.encodeUtf8 ("<svg" <> T.concat [" a" <> T.pack (show i) <> "=\"1\"" | i <- [1 .. n]] <> "/>"))) 20000,
      localOption (mkTimeout (seconds 5))
        $ testCase "C11: six arcs with radii of 1e9999 (150 bytes) are refused or drawn with numbers of a bounded size"
        $ do
          r <- total (svg ("<path d=\"M0 0" <> T.replicate 3 " A 1e9999 1e9999 0 0 1 10 0 A 1e9999 1e9999 0 0 1 0 0" <> "\" stroke=\"#000\" fill=\"none\"/>"))
          case r of
            Left _ -> pure ()
            Right s -> assertBool "a number too large for a PDF" (all smallEnough (rationals (svgDrawing s))),
      localOption (mkTimeout (seconds 5))
        $ testCase "C11: a width of 1e9999 is refused or read as a size of a bounded number"
        $ do
          r <- total "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1e9999\" height=\"1e9999\"><rect width=\"1\" height=\"1\"/></svg>"
          case r of
            Left _ -> pure ()
            Right s -> assertBool "a size too large for a PDF" (let (w, h) = svgSize s in smallEnough w && smallEnough h)
    ]
