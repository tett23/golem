{- | Hostile SVG figures end within limits of time and allocation (the
security audit of 2026-10-18, candidates C8 to C11). Each input is small;
what is asserted is that reading it is bounded: it is refused with what
becomes G08010 or G08011, or it is read in a time and an allocation
proportional to the input.
-}
module SecuritySpec (tests) where

import Control.Exception (SomeException, evaluate, try)
import Data.ByteString (ByteString)
import Data.Ratio (denominator, numerator)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import GHC.Stats (allocated_bytes, getRTSStats, getRTSStatsEnabled)
import Golem.Svg
import Golem.Svg.Css (parseStylesheet)
import Golem.Svg.Xml (parseXml)
import System.CPUTime (getCPUTime)
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

{- | The same for time, when the quadratic part does not allocate: a
quadratic algorithm takes about four times as long, and the line is
drawn at 4 so that a busy runner does not fail a linear one (docs/adr
ADR 0073). The input is large enough for the two runs to take well over
a second together.
-}
linearTime :: (Int -> IO a) -> Int -> Assertion
linearTime act n = do
  t0 <- cpuSeconds
  _ <- act n
  t1 <- cpuSeconds
  _ <- act (2 * n)
  t2 <- cpuSeconds
  let small = t1 - t0
      large = t2 - t1
      ratio = large / max 0.001 small
  assertBool ("time grew by " <> show ratio <> " (" <> show small <> " s -> " <> show large <> " s)") (ratio < 4)

-- | The processor time, not the wall clock: other work on a busy machine does not count.
cpuSeconds :: IO Double
cpuSeconds = (/ 1e12) . fromInteger <$> getCPUTime

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

{- | A chain of markers of the number given, each placing the one before
once (at the end of its path), the first placing none; the drawing places
the last, so that the chain is that many markers deep.
-}
markerChain :: Int -> ByteString
markerChain n =
  svg $
    "<defs><marker id=\"c1\"><path d=\"M0 0 L1 1\" stroke=\"#000\"/></marker>"
      <> T.concat ["<marker id=\"c" <> tshow k <> "\"><path d=\"M0 0 L1 0\" stroke=\"#000\" marker-end=\"url(#c" <> tshow (k - 1) <> ")\"/></marker>" | k <- [2 .. n]]
      <> "</defs><path d=\"M0 0 L10 0\" stroke=\"#000\" marker-end=\"url(#c"
      <> tshow n
      <> ")\"/>"
  where
    tshow = T.pack . show

-- | The names of what is outside the subset (G08011), or nothing.
unsupportedNames :: Either SvgError Svg -> [Text]
unsupportedNames = \case
  Left (SvgUnsupported ps) -> map unName (spUnsupported ps)
  _ -> []

-- | The references within cycles of markers (G08016) and those too deep (G08017), by the id they place (docs/adr ADR 0054).
markerProblems :: Either SvgError Svg -> ([Text], [Text])
markerProblems = \case
  Left (SvgUnsupported ps) -> (map mrId (spMarkerCycles ps), map mrId (spMarkerDepth ps))
  _ -> ([], [])

-- | The depth of groups of a drawing.
groupDepth :: [DrawOp] -> Int
groupDepth = maximum . (0 :) . map (\case DPath _ _ -> 0; DGroup _ _ ops -> 1 + groupDepth ops)

-- | A path with an arc of the radius given.
arcOf :: Text -> ByteString
arcOf r = svg ("<path d=\"M0 0 A " <> r <> " " <> r <> " 0 0 1 10 0\" stroke=\"#000\" fill=\"none\"/>")

-- ------------------------------------------------------------------ tests

tests :: TestTree
tests = testGroup "security" [tests2018, auditTests]

tests2018 :: TestTree
tests2018 =
  testGroup
    "hostile SVG figures end within limits (security audit 2026-10-18)"
    [ testGroup "markers and numbers within limits (docs/adr ADR 0041)" adr0041Tests,
      localOption (mkTimeout (seconds 30))
        $ testCase "C8: a marker that refers to itself is refused or drawn finitely"
        $ total selfMarker >>= finished,
      localOption (mkTimeout (seconds 30))
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
      localOption (mkTimeout (seconds 30)) $
        testCase "C11: six arcs with radii of 1e9999 (150 bytes) are refused or drawn with numbers of a bounded size" $
          do
            r <- total (svg ("<path d=\"M0 0" <> T.replicate 3 " A 1e9999 1e9999 0 0 1 10 0 A 1e9999 1e9999 0 0 1 0 0" <> "\" stroke=\"#000\" fill=\"none\"/>"))
            case r of
              Left _ -> pure ()
              Right s -> assertBool "a number too large for a PDF" (all smallEnough (rationals (svgDrawing s))),
      localOption (mkTimeout (seconds 30)) $
        testCase "C11: a width of 1e9999 is refused or read as a size of a bounded number" $
          do
            r <- total "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1e9999\" height=\"1e9999\"><rect width=\"1\" height=\"1\"/></svg>"
            case r of
              Left _ -> pure ()
              Right s -> assertBool "a size too large for a PDF" (let (w, h) = svgSize s in smallEnough w && smallEnough h)
    ]

adr0041Tests :: [TestTree]
adr0041Tests =
  [ localOption (mkTimeout (seconds 30)) $
      testCase "C8: a marker that refers to itself is one reference in a cycle (G08016, docs/adr ADR 0054)" $
        do
          r <- total selfMarker
          markerProblems r @?= (["m"], [])
          unsupportedNames r @?= [],
    testCase "a places b, b places a, the drawing places a: both references are in the cycle, in document order" $ do
      r <- total (svg "<defs><marker id=\"a\"><path d=\"M0 0 L1 1\" marker-end=\"url(#b)\"/></marker><marker id=\"b\"><path d=\"M0 0 L1 1\" marker-end=\"url(#a)\"/></marker></defs><path d=\"M0 0 L10 0\" marker-end=\"url(#a)\"/>")
      markerProblems r @?= (["b", "a"], [])
      case r of
        Left (SvgUnsupported ps) -> map (\m -> (mrLine m, mrColumn m)) (spMarkerCycles ps) @?= [(1, 86), (1, 152)]
        other -> assertFailure (show other),
    testCase "a cycle of three markers is three references" $ do
      r <- total (svg "<defs><marker id=\"a\"><path d=\"M0 0 L1 1\" marker-end=\"url(#b)\"/></marker><marker id=\"b\"><path d=\"M0 0 L1 1\" marker-end=\"url(#c)\"/></marker><marker id=\"c\"><path d=\"M0 0 L1 1\" marker-end=\"url(#a)\"/></marker></defs><path d=\"M0 0 L10 0\" marker-end=\"url(#a)\"/>")
      markerProblems r @?= (["b", "c", "a"], []),
    testCase "a marker in a cycle that the drawing never places is not a problem" $ do
      r <- total (svg "<defs><marker id=\"m\"><path d=\"M0 0 L1 1\" marker-end=\"url(#m)\"/></marker></defs><path d=\"M0 0 L10 0\" stroke=\"#000\"/>")
      either (assertFailure . show) (const (pure ())) r,
    localOption (mkTimeout (seconds 30)) $
      testCase "C8: markers nested 14 deep, four at each level, are references too deep only (G08017)" $
        do
          r <- total (nestedMarkers 14)
          let (cycles, deep) = markerProblems r
          assertBool (show (take 3 deep)) (not (null deep))
          cycles @?= []
          unsupportedNames r @?= [],
    localOption (mkTimeout (seconds 30)) $
      testCase "a chain of 9 markers is drawn" $
        do
          r <- total (markerChain 9)
          case r of
            -- each marker is two groups (its place and its viewBox)
            Right s -> groupDepth (svgDrawing s) @?= 18
            Left e -> assertFailure (show e),
    localOption (mkTimeout (seconds 30)) $
      testCase "a chain of 10 markers is one reference too deep (G08017)" $
        do
          r <- total (markerChain 10)
          markerProblems r @?= ([], ["c1"])
          unsupportedNames r @?= [],
    localOption (mkTimeout (seconds 30)) $
      testCase "a chain of 12 markers is three references too deep" $
        do
          r <- total (markerChain 12)
          markerProblems r @?= ([], ["c1", "c2", "c3"]),
    testCase "text and a cycle of markers are both reported, each in its list" $ do
      r <- total (svg "<text>a</text><defs><marker id=\"m\"><path d=\"M0 0 L1 1\" marker-end=\"url(#m)\"/></marker></defs><path d=\"M0 0 L10 0\" marker-end=\"url(#m)\"/>")
      unsupportedNames r @?= ["text"]
      markerProblems r @?= (["m"], []),
    localOption (mkTimeout (seconds 30)) $
      testCase "C11: six arcs with radii of 1e9999 are G08011, d（読めない数）" $
        do
          r <- total (svg ("<path d=\"M0 0" <> T.replicate 3 " A 1e9999 1e9999 0 0 1 10 0 A 1e9999 1e9999 0 0 1 0 0" <> "\" stroke=\"#000\" fill=\"none\"/>"))
          unsupportedNames r @?= ["d（読めない数）"],
    localOption (mkTimeout (seconds 30)) $
      testCase "C11: a width of 1e9999 is G08010, 大きさの数が大きすぎます" $
        do
          r <- total "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1e9999\" height=\"1e9999\"><rect width=\"1\" height=\"1\"/></svg>"
          r @?= Left (SvgMalformed "大きさの数が大きすぎます"),
    testCase "a viewBox of a number too large is G08010, 大きさの数が大きすぎます" $
      readSvg "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1e10 1\"/>" @?= Left (SvgMalformed "大きさの数が大きすぎます"),
    testCase "a radius of 1e9 is read" $ do
      r <- total (arcOf "1e9")
      unsupportedNames r @?= [],
    testCase "a radius of 1.000000001e9 is G08011, d（読めない数）" $ do
      r <- total (arcOf "1.000000001e9")
      unsupportedNames r @?= ["d（読めない数）"],
    testCase "a radius of -1e9999 is G08011, d（読めない数）" $ do
      r <- total (arcOf "-1e9999")
      unsupportedNames r @?= ["d（読めない数）"],
    testCase "a number of an exponent of five digits is malformed, not too large" $ do
      r <- total (arcOf "1e99999")
      unsupportedNames r @?= ["d"],
    testCase "the components of a transform, a stroke width, a dash array and points have the same limit" $ do
      let names b = unsupportedNames (readSvg (svg b))
      names "<path transform=\"scale(2e9)\" d=\"M0 0 L1 1\"/>" @?= ["transform（読めない数）"]
      names "<path stroke=\"#000\" stroke-width=\"2e9\" d=\"M0 0 L1 1\"/>" @?= ["stroke-width（読めない数）"]
      names "<path stroke=\"#000\" stroke-dasharray=\"1 2e9\" d=\"M0 0 L1 1\"/>" @?= ["stroke-dasharray（読めない数）"]
      names "<polyline points=\"0 0 2e9 1\"/>" @?= ["points（読めない数）"]
      names "<rect width=\"2e9\" height=\"1\"/>" @?= ["width（読めない数）"]
      names "<defs><marker id=\"m\" refX=\"2e9\"><path d=\"M0 0 L1 1\"/></marker></defs>" @?= ["refX（読めない数）"]
      names "<rect fill=\"rgb(2e9, 0, 0)\" width=\"1\" height=\"1\"/>" @?= ["fill（読めない数）"]
  ]

-- | Candidates of the security audit of 2026-10-24.
auditTests :: TestTree
auditTests =
  testGroup
    "security audit 2026-10-24"
    [ localOption (mkTimeout (seconds 30))
        $ testCase "A-SA: thirty arcs with radii of 1e-9999 (1 KB) are refused or drawn in time"
        $ total (svg ("<path d=\"M0 0" <> T.replicate 15 " A 1e-9999 1e-9999 0 0 1 10 0 A 1e-9999 1e-9999 0 0 1 0 0" <> "\" stroke=\"#000\" fill=\"none\"/>")) >>= finished,
      localOption (mkTimeout (seconds 30))
        $ testCase "A-SB: markers 9 deep with 20 vertices each are refused or bounded"
        $ total fanMarkers >>= finished
    ]

-- | Nine markers; each is a path of 20 vertices whose marker-mid is the marker below.
fanMarkers :: ByteString
fanMarkers =
  svg $
    "<defs>"
      <> T.concat [marker k | k <- [1 .. 9 :: Int]]
      <> "</defs><path d=\""
      <> pathD
      <> "\" marker-mid=\"url(#m9)\" stroke=\"#000\"/>"
  where
    pathD = "M0 0" <> T.concat [" L" <> T.pack (show i) <> " 0" | i <- [1 .. 19 :: Int]]
    marker k =
      "<marker id=\"m"
        <> T.pack (show k)
        <> "\" markerWidth=\"1\" markerHeight=\"1\"><path d=\""
        <> pathD
        <> "\" stroke=\"#000\""
        <> (if k > 1 then " marker-mid=\"url(#m" <> T.pack (show (k - 1)) <> ")\"" else "")
        <> "/></marker>"
