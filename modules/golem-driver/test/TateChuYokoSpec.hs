{- | The tate-chu-yoko of the vertical PDF, drawn horizontally in a box
of one character (golem-driver ADR 0045). Each invariant of the ADR is a
function that returns its violations, read from the glyphs drawn in the
content streams of the pages; each test sees it hold on the books built
with the fonts of scripts/visual/build.sh, and fail on the glyphs as the
drawing before the ADR placed them (stacked along the line in the
vertical font), so that a property that cannot fail checks nothing.

Where a box is comes from the layout: the glyph of an upright
character next to it in its line (in the vertical font, its origin the
top of its em box on the centre line) gives the line, and the offsets of
the boxes along the line give the box.
-}
module TateChuYokoSpec (tateChuYokoTests, Glyph (..), fontEncodings, glyphsOf, pdfOf) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.List (isSuffixOf, tails)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing, listToMaybe, mapMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Layout.Japanese (BoxKind (..), boxKind)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..), MarkBox (..), placeLine)
import Golem.Layout.Look (Look (..))
import Golem.Length (Sp (..))
import Golem.Preflight.View (LineView (..), PageView (..), View (..))
import Golem.Syntax (Diagnostic (..), isError)
import Golem.Typeset (PdfLayout (..), SetLine (..), Shaped (..), Shaping (..), shapingOf)
import SpecimenGeometrySpec (jaLatin, layoutAndFontsOf, specimensVertical, withInput)
import Support
import System.Directory (copyFile, createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

tateChuYokoTests :: TestTree
tateChuYokoTests =
  testGroup
    "the tate-chu-yoko of the vertical PDF (golem-driver ADR 0045)"
    [ testCase "I1–I6: [tcy: 12], [tcy: !?], [number-text 12 style=tcy], [number-text 7 style=tcy], [tcy: 123] and [tcy: 1234]" $
        withProject "" paragraphs $ \dir -> do
          occs <- occurrencesOf dir
          map oText occs @?= ["12", "!?", "12", "7", "123", "1234"]
          holdAll "the paragraphs" occs
          -- the drawing before the ADR breaks each invariant; I4 on the two that do not fit
          breakAll "the paragraphs, drawn as before" (map stacked occs),
      testCase "I1–I6: the marks of 12 notes in the text and at the start of the note bodies, as in specimens-vertical" $
        withInput specimensVertical $ \dir -> do
          occs <- occurrencesOf dir
          let marks = [oText o | o <- occs, oMark o]
              starts = [oText o | o <- occs, not (oMark o)]
          forM_ ["10", "11", "12"] $ \n -> do
            assertBool ("the mark " <> T.unpack n <> " in the text") (n `elem` marks)
            assertBool ("the mark " <> T.unpack n <> " at the start of its note") (n `elem` starts)
          holdAll "specimens-vertical" occs
          breakSome "specimens-vertical, drawn as before" [1, 2, 3, 5, 6] (map stacked (filter ((> 1) . T.length . oText) occs)),
      testCase "I1–I6: the markers 10 to 12 of a numbered list, [numbers] vertical = \"auto\"" $
        withProject "\n[numbers]\nvertical = \"auto\"\n" list $ \dir -> do
          occs <- occurrencesOf dir
          forM_ ["10", "11", "12"] $ \n -> assertBool ("the marker " <> T.unpack n <> ": " <> show (map oText occs)) (n `elem` map oText occs)
          holdAll "the list" occs
          breakSome "the list, drawn as before" [1, 2, 3, 5, 6] (map stacked (filter ((> 1) . T.length . oText) occs)),
      -- I7: the boxes of the lines and the faces of the lines, as before the ADR
      goldenVsString "I7: the layout of the paragraphs is that of before the ADR" "test/golden/tcy-layout.txt" $
        withProject "" paragraphs layoutText,
      testCase "I8: in horizontal text a tate-chu-yoko is drawn as the text around it: upright glyphs of the horizontal font, unscaled, no Tz" $
        withHorizontalProject "あ[tcy: 12]月。\n" $ \dir -> do
          (_, pl, fonts) <- layoutAndFontsOf dir
          pdf <- pdfOf dir
          encodings <- fontEncodings pdf
          contents <- pageContents pdf
          look <- case [bcLook c | l <- linesOf pl, (Box _ c, _) <- placeLine l, boxKind c == KindTcy] of
            l : _ -> pure l
            [] -> assertFailure "no tate-chu-yoko box"
          let codes = [lfCode fonts (shFace g) (shGlyph g) | g <- lfShape fonts (shapingOf (lfRoleFeatures fonts) False look '1') "12"]
              drawn = concatMap (glyphsOf encodings) contents
              gs = [g | g <- drawn, gCode g `elem` codes]
          length codes @?= 2
          map gCode gs @?= codes
          assertBool ("the horizontal font, upright: " <> show gs) (all (\g -> gEncoding g == "Identity-H" && gMatrix g == [1, 0, 0, 1]) gs)
          map gScale gs @?= [1000, 1000]
          assertBool ("one baseline, in order: " <> show gs) (and (zipWith (\a b -> gY a == gY b && gX a < gX b) gs (drop 1 gs)))
          assertBool "no horizontal scaling on the pages" (not (any (" Tz" `BS.isInfixOf`) contents))
    ]
  where
    paragraphs =
      T.unlines
        [ "あ[tcy: 12]月。",
          "",
          "い[tcy: !?]と。",
          "",
          "う[number-text 12 style=tcy]日。",
          "",
          "え[number-text 7 style=tcy]日。",
          "",
          "お[tcy: 123]年。",
          "",
          "か[tcy: 1234]年。"
        ]
    list = T.unlines ["+ 項目" <> T.singleton k <> "。" | k <- "甲乙丙丁戊己庚辛壬癸子丑"]

-- ------------------------------------------------------------------ the books

-- | A one-chapter vertical project with the fonts of the specimens and more of style.toml.
withProject :: BS.ByteString -> T.Text -> (FilePath -> IO a) -> IO a
withProject more source act = withSystemTempDirectory "golem-tcy" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") miniManifest
  BS.writeFile (tmp </> "style.toml") (pdfStyle <> "\n[fonts.body]\nja = \"fonts/ja.otf\"\nlatin = \"fonts/latin.otf\"\n" <> more)
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  createDirectoryIfMissing True (tmp </> "fonts")
  forM_ jaLatin $ \(to, from) -> copyFile from (tmp </> "fonts" </> to)
  act tmp

-- | A one-chapter horizontal project (30 characters a line) with the fonts of the specimens.
withHorizontalProject :: T.Text -> (FilePath -> IO a) -> IO a
withHorizontalProject source act = withSystemTempDirectory "golem-tcy-h" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") miniManifest
  BS.writeFile (tmp </> "style.toml") (horizontal30 "\n[fonts.body]\nja = \"fonts/ja.otf\"\nlatin = \"fonts/latin.otf\"\n")
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  createDirectoryIfMissing True (tmp </> "fonts")
  forM_ jaLatin $ \(to, from) -> copyFile from (tmp </> "fonts" </> to)
  act tmp

-- | The PDF of a project, with the real fonts.
pdfOf :: FilePath -> IO BS.ByteString
pdfOf dir = do
  r <- build (defaultOptions dir) {optTargets = Just [TargetPdf], optFonts = realProvider}
  assertEqual "no errors" [] [(diagCode d, diagMessage d) | d <- brDiagnostics r, isError d]
  case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> BS.readFile p
    other -> assertFailure (show other)

-- | The boxes of each line of the layout and the face of each line of the view.
layoutText :: FilePath -> IO BL.ByteString
layoutText dir = do
  (_, pl, _) <- layoutAndFontsOf dir
  p <- preflight (defaultPreflightOptions dir) {poFonts = realProvider}
  v <- maybe (assertFailure (show (filter isError (prDiagnostics p)))) pure (prView p)
  let boxes l = T.unwords [T.pack (show (boxKind c)) <> ":" <> bcText c <> "@" <> T.pack (show (unSp off)) <> "+" <> T.pack (show (unSp w)) | (Box w c, off) <- placeLine l]
      ls = [T.pack (show i) <> " " <> T.pack (show (unSp (slIndent sl))) <> " " <> boxes (slLine sl) | (i, sl) <- Map.toList (plLines pl)]
      faces = [T.pack (show (pvIndex pg)) <> " " <> lvKind l <> " " <> T.pack (show (lvRect l)) | pg <- vwPages v, l <- pvLines pg]
  pure (BL.fromStrict (TE.encodeUtf8 (T.unlines (ls <> faces))))

-- ------------------------------------------------------------------ the occurrences

-- | A glyph drawn: its font resource and the encoding of the font, its code, size, matrix, origin and horizontal scale in permille.
data Glyph = Glyph
  { gEncoding :: BS.ByteString,
    gCode :: Int,
    gSize :: Rational,
    gMatrix :: [Rational],
    gX :: Rational,
    gY :: Rational,
    gScale :: Rational
  }
  deriving stock (Show)

{- | A tate-chu-yoko drawn: its text, whether it is in the mark of a note
in the text, the size s of its box, the start y0 of the box, the centre
x_c across the line, the centre c of the em box of the Japanese face, the
advances of its glyphs in pt, and its glyphs.
-}
data Occurrence = Occurrence
  { oText :: T.Text,
    oMark :: Bool,
    oS :: Rational,
    oY0 :: Rational,
    oXc :: Rational,
    oC :: Rational,
    oAdvances :: [Rational],
    oGlyphs :: [Glyph]
  }
  deriving stock (Show)

-- | What a line draws, in order: a box, or a part of the mark of a note; each with its kind, text, look and offset along the line.
data Unit = Unit {uKind :: BoxKind, uText :: T.Text, uLook :: Look, uOff :: Sp, uMark :: Maybe MarkBox}

unitsOf :: Line -> [Unit]
unitsOf l =
  concat
    [ case bcMark c of
        Just mb -> [Unit (toEnum tag) t (bcLook c) (off + o) (Just mb) | (tag, t, o) <- mbParts mb, not (T.null t)]
        Nothing -> [Unit (boxKind c) (bcText c) (bcLook c) (off + bcPadStart c) Nothing | not (T.null (bcText c))]
    | (Box _ c, off) <- placeLine l
    ]

-- | The lines of a layout: those of the text and those of their notes.
linesOf :: PdfLayout -> [Line]
linesOf pl = concat [slLine sl : concatMap snd (slNotes sl) | sl <- Map.elems (plLines pl)]

{- | The tate-chu-yoko of a project found in its PDF: each one in the
layout whose glyphs and those of the upright character next to it, and
of the units between, are drawn once in a row.
-}
occurrencesOf :: FilePath -> IO [Occurrence]
occurrencesOf dir = do
  (_, pl, fonts) <- layoutAndFontsOf dir
  pdf <- pdfOf dir
  encodings <- fontEncodings pdf
  contents <- pageContents pdf
  let drawn = concatMap (glyphsOf encodings) contents
      sp x = toRational (unSp x) / 65536
      shaped vertical u = case T.uncons (uText u) of
        Just (ch, _) -> lfShape fonts (shapingOf (lfRoleFeatures fonts) vertical (uLook u) ch) (uText u)
        Nothing -> []
      -- upright text is shaped vertically; turned Latin and tate-chu-yoko horizontally
      codes u = [lfCode fonts (shFace g) (shGlyph g) | g <- shaped (uKind u `notElem` [KindRotated, KindTcy]) u]
      upright u = uKind u == KindText && T.length (uText u) == 1 && isNothing (uMark u) && fmap shTurned (shaped True u) == [False]
      opaque u = uKind u `elem` [KindRuby, KindGroupRuby, KindKenten, KindDashes]
      -- the nearest upright character before (or else after) a unit, with the units between
      anchored us i =
        let before = reverse (take i us)
            following = drop (i + 1) us
            nearest xs = case break (\u -> upright u || opaque u) xs of
              (between, a : _) | upright a -> Just (a, between)
              _ -> Nothing
         in case nearest before of
              Just (a, between) -> Just (a, codes a <> concatMap codes (reverse between) <> codes (us !! i))
              Nothing -> (\(a, between) -> (a, codes (us !! i) <> concatMap codes between <> codes a)) <$> nearest following
      found = mapMaybe (match drawn) [(us !! i, a, seqCodes, length (codes (us !! i)), before) | l <- linesOf pl, let us = unitsOf l, (i, u) <- zip [0 ..] us, uKind u == KindTcy, Just (a, seqCodes) <- [anchored us i], let before = uOff a < uOff u]
      match ds (u, a, seqCodes, n, before) = case [take (length seqCodes) t | t <- tails ds, map gCode (take (length seqCodes) t) == seqCodes] of
        [run@(firstGlyph : _)] ->
          let (anchorGlyph, glyphs) = if before then (firstGlyph, take n (drop (length seqCodes - n) run)) else (last run, take n run)
              look = uLook u
              s = sp (lkSize look)
              y0 = gY anchorGlyph - sp (uOff u - uOff a)
              xc = case uMark u of
                Just mb -> gX anchorGlyph + sp (Sp (unSp (lkSize (mbPlace mb) - lkSize look) `div` 2))
                Nothing -> gX anchorGlyph
              jaFace = maybe 0 shFace (listToMaybe (lfShape fonts (Shaping (lkFace look) False [] False) "漢"))
           in Just (Occurrence (uText u) (isJust (uMark u)) s y0 xc (lfEmBoxCentral fonts jaFace) [s * shAdvance g | g <- shaped False u] glyphs)
        _ -> Nothing
  pure found

-- | The encoding (Identity-H or Identity-V) of each font resource of a PDF.
fontEncodings :: BS.ByteString -> IO (Map.Map BS.ByteString BS.ByteString)
fontEncodings pdf = do
  let objectBody n = fst (BS.breakSubstring "\nendobj" (snd (BS.breakSubstring ("\n" <> BC.pack (show n) <> " 0 obj\n") pdf)))
      dicts = drop 1 (splitOn "/Font <<" pdf)
      names = [(name, read (BC.unpack n) :: Int) | d <- dicts, (name, n, "0", "R") <- quads (BC.words (fst (BS.breakSubstring ">>" d))), "/F" `BS.isPrefixOf` name]
      quads (a : b : c : d : rest) = (a, b, c, d) : quads rest
      quads _ = []
      encodingOf n = listToMaybe [enc | enc <- ["Identity-V", "Identity-H"], ("/" <> enc) `BS.isInfixOf` objectBody n]
  pure (Map.fromList [(BS.drop 1 name, enc) | (name, n) <- names, Just enc <- [encodingOf n]])
  where
    splitOn pat s = case BS.breakSubstring pat s of
      (a, rest) | BS.null rest -> [a]
      (a, rest) -> a : splitOn pat (BS.drop (BS.length pat) rest)

{- | The glyphs a content stream draws, each with the font, size and
horizontal scale in force (q and Q save and restore them).
-}
glyphsOf :: Map.Map BS.ByteString BS.ByteString -> BS.ByteString -> [Glyph]
glyphsOf encodings content = go [] ("", 0, 1000) [] (BC.words content)
  where
    go _ _ _ [] = []
    go saved st@(f, size, tz) ops (w : ws) = case w of
      "q" -> go (st : saved) st [] ws
      "Q" -> case saved of
        (s : rest) -> go rest s [] ws
        [] -> go [] st [] ws
      "Tf" | (sz : name : _) <- ops -> go saved (BS.drop 1 name, ptToRational sz, tz) [] ws
      "Tz" | (z : _) <- ops -> go saved (f, size, ptToRational z * 10) [] ws
      "Tm" | (y : x : d : c : b : a : _) <- ops -> case ws of
        (hexg : "Tj" : rest) ->
          Glyph (Map.findWithDefault "" f encodings) (read ("0x" <> BC.unpack (BC.filter (`notElem` ("<>" :: String)) hexg))) size (map ptToRational [a, b, c, d]) (ptToRational x) (ptToRational y) tz : go saved st [] rest
        _ -> go saved st [] ws
      _
        | isOperator w -> go saved st [] ws
        | otherwise -> go saved st (w : ops) ws
    isOperator w = not (BS.null w) && BC.all (`elem` ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ*'\"" :: String)) w

-- ------------------------------------------------------------------ the invariants

-- | The tolerance of a comparison of lengths in pt: the four decimals of the output and 1 sp.
tolerance :: Rational
tolerance = 1 / 1000

near :: Rational -> Rational -> Bool
near a b = abs (a - b) <= tolerance

-- | The sum of the advances W, the scale the ADR gives it, and W'.
widths :: Occurrence -> (Rational, Rational, Rational)
widths o =
  let w = sum (oAdvances o)
      scale = if w <= oS o then 1000 else fromInteger (floor (1000 * oS o / w))
   in (w, scale, w * scale / 1000)

-- | The baseline of the ADR: y0 − s/2 − c × s.
baseline :: Occurrence -> Rational
baseline o = oY0 o - oS o / 2 - oC o * oS o

-- | The violations of an invariant by its number.
violations :: Int -> Occurrence -> [String]
violations n o = [show n <> " " <> T.unpack (oText o) <> ": " <> e | e <- check n]
  where
    gs = oGlyphs o
    (_, scale, w') = widths o
    check = \case
      -- 1: in the horizontal font, not turned
      1 -> [show g | g <- gs, gEncoding g /= "Identity-H" || take 2 (gMatrix g) /= [1, 0] || drop 3 (gMatrix g) /= [1]]
      -- 2: one baseline, the origins in the order of the text
      2 -> [show (map gY gs) | not (all (near (maybe 0 gY (listToMaybe gs)) . gY) gs)] <> [show (map gX gs) | not (and (zipWith (<) (map gX gs) (drop 1 (map gX gs))))]
      -- 3: the baseline y0 − s/2 − c × s
      3 -> [show (gY g, baseline o) | g <- gs, not (near (gY g) (baseline o))]
      -- 4: the scale, and W' ≤ s
      4 -> [show (gScale g, scale) | g <- gs, gScale g /= scale] <> [show (w', oS o) | w' > oS o + tolerance]
      -- 5: the first origin at x_c − W'/2
      5 -> [show (gX g, oXc o - w' / 2) | g <- take 1 gs, not (near (gX g) (oXc o - w' / 2))]
      -- 6: the advances and the em box of the glyphs inside the box
      6 ->
        let s = oS o
            extent g a
              | gEncoding g == "Identity-V" = (gX g - s / 2, gX g + s / 2, gY g - s, gY g)
              | otherwise = (gX g, gX g + a * gScale g / 1000, gY g + oC o * s - s / 2, gY g + oC o * s + s / 2)
         in [ show (x1, x2, y1, y2)
            | (x1, x2, y1, y2) <- zipWith extent gs (oAdvances o),
              x1 < oXc o - s / 2 - tolerance || x2 > oXc o + s / 2 + tolerance || y1 < oY0 o - s - tolerance || y2 > oY0 o + tolerance
            ]
      _ -> []

-- | Every invariant holds on every occurrence.
holdAll :: String -> [Occurrence] -> IO ()
holdAll name occs = do
  assertBool (name <> ": no tate-chu-yoko") (not (null occs))
  let bad = concat [violations n o | n <- [1 .. 6], o <- occs]
  assertBool (name <> ":\n" <> unlines bad) (null bad)

-- | Every invariant is broken by some occurrence.
breakAll :: String -> [Occurrence] -> IO ()
breakAll name = breakSome name [1 .. 6]

-- | Each invariant of the numbers is broken by some occurrence.
breakSome :: String -> [Int] -> [Occurrence] -> IO ()
breakSome name ns occs = forM_ ns $ \n ->
  assertBool (name <> ": nothing breaks I" <> show n) (not (all (null . violations n) occs))

{- | The glyphs of an occurrence as the drawing before the ADR placed them:
in the vertical font, upright, on the centre line, each its advance
below the one before it from the start of the box, unscaled.
-}
stacked :: Occurrence -> Occurrence
stacked o =
  o
    { oGlyphs =
        [ g {gEncoding = "Identity-V", gMatrix = [1, 0, 0, 1], gX = oXc o, gY = oY0 o - off, gScale = 1000}
        | (g, off) <- zip (oGlyphs o) (scanl (+) 0 (oAdvances o))
        ]
    }
