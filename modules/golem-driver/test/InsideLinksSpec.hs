{- | The bookmarks of the PDF and its links inside the document
(docs/adr/0267): what the PDF writes, read back from its bytes.
-}
module InsideLinksSpec (insideLinksTests) where

import Control.Monad (forM_)
import Data.Bits (shiftL, (.|.))
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Char (chr, isSpace)
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Layout.Look (LinkDest (..))
import Golem.Syntax
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Support
import System.Directory (copyFile, createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | The objects of a PDF by their numbers, each up to its endobj, by the offsets of the xref table.
objectsOf :: BS.ByteString -> Map.Map Int BS.ByteString
objectsOf pdf =
  let afterXref = snd (BS.breakSubstring "\nxref\n" pdf)
      ls = drop 4 (BC.lines afterXref)
      entries = takeWhile (BC.isSuffixOf " n ") ls
      offsets = [read (BC.unpack (BS.take 10 l)) :: Int | l <- entries]
   in Map.fromList [(n, fst (BS.breakSubstring "\nendobj" (BS.drop o pdf))) | (n, o) <- zip [1 ..] offsets]

-- | The numbers of the references in an array after a key of an object, as "/Kids [3 0 R 5 0 R]".
refsAfter :: BS.ByteString -> BS.ByteString -> [Int]
refsAfter key obj = case BS.breakSubstring (key <> " [") obj of
  (_, rest)
    | BS.null rest -> []
    | otherwise ->
        let body = fst (BS.breakSubstring "]" (BS.drop (BS.length key + 2) rest))
         in every3 (BC.words body)
  where
    every3 = \case
      n : "0" : "R" : more -> read (BC.unpack n) : every3 more
      _ -> []

-- | The numbers of the array after a key, as "/Rect [72 700 172 710]".
numbersAfter :: BS.ByteString -> BS.ByteString -> [Double]
numbersAfter key obj = case BS.breakSubstring (key <> " [") obj of
  (_, rest)
    | BS.null rest -> []
    | otherwise -> map (read . BC.unpack) (BC.words (fst (BS.breakSubstring "]" (BS.drop (BS.length key + 2) rest))))

-- | A text string of a key: a literal string or UTF-16BE in hex.
textAfter :: BS.ByteString -> BS.ByteString -> Maybe T.Text
textAfter key obj = case BS.breakSubstring (key <> " ") obj of
  (_, rest)
    | BS.null rest -> Nothing
    | otherwise ->
        let v = BS.drop (BS.length key + 1) rest
         in case BC.uncons v of
              Just ('(', s) -> Just (TE.decodeUtf8 (unescape (literal s)))
              Just ('<', s) -> Just (utf16 (fst (BS.breakSubstring ">" s)))
              _ -> Nothing
  where
    literal s = case BC.uncons s of
      Just ('\\', more) -> BS.take 2 s <> literal (BS.drop 1 more)
      Just (')', _) -> ""
      Just (c, more) -> BC.cons c (literal more)
      Nothing -> ""
    unescape s = case BC.uncons s of
      Just ('\\', more) -> BS.take 1 more <> unescape (BS.drop 1 more)
      Just (c, more) -> BC.cons c (unescape more)
      Nothing -> ""
    utf16 h =
      let bytes = [read ("0x" <> BC.unpack (BS.take 2 (BS.drop i h))) :: Int | i <- [0, 2 .. BS.length h - 2]]
          units = pairs (drop 2 bytes)
       in T.pack (decode units)
    pairs = \case
      a : b : rest -> (a `shiftL` 8 .|. b) : pairs rest
      _ -> []
    decode = \case
      hi : lo : rest | hi >= 0xD800, hi < 0xDC00 -> chr (0x10000 + ((hi - 0xD800) `shiftL` 10) + (lo - 0xDC00)) : decode rest
      u : rest -> chr u : decode rest
      [] -> []

-- | A link annotation to a place of the document, as the PDF writes it.
data Inside = Inside
  { -- | the page it is on, from 0
    inOn :: Int,
    -- | the page of its destination, from 0
    inPage :: Int,
    -- | t of /XYZ
    inTop :: Double,
    inRect :: [Double],
    inContents :: Maybe T.Text,
    -- | the whole destination as written
    inDest :: BS.ByteString
  }
  deriving stock (Eq, Show)

-- | The width of the rectangle of an annotation.
widthOf :: Inside -> Double
widthOf i = case inRect i of
  [x0, _, x1, _] -> x1 - x0
  _ -> 0

-- | Whether the insides of two rectangles meet.
overlaps :: [Double] -> [Double] -> Bool
overlaps [a0, b0, a1, b1] [c0, d0, c1, d1] = a0 < c1 && c0 < a1 && b0 < d1 && d0 < b1
overlaps _ _ = False

-- | The pages of a PDF by their objects, in order.
pageObjects :: BS.ByteString -> [Int]
pageObjects pdf = refsAfter "/Kids" (Map.findWithDefault "" 2 (objectsOf pdf))

-- | The link annotations to places of the document, page by page in the order of /Annots.
insides :: BS.ByteString -> [Inside]
insides pdf =
  [ Inside on (fromMaybe (-1) (lookup p pageIndex)) t (numbersAfter "/Rect" a) (textAfter "/Contents" a) dest
  | (on, pobj) <- zip [0 ..] pages,
    n <- refsAfter "/Annots" (Map.findWithDefault "" pobj objs),
    let a = Map.findWithDefault "" n objs,
    "/Dest [" `BS.isInfixOf` a,
    let dest = fst (BS.breakSubstring "]" (BS.drop 7 (snd (BS.breakSubstring "/Dest [" a)))),
    [pw, "0", "R", "/XYZ", "null", tw, "null"] <- [BC.words dest],
    let p = read (BC.unpack pw) :: Int
        t = read (BC.unpack tw) :: Double
  ]
  where
    objs = objectsOf pdf
    pages = pageObjects pdf
    pageIndex = zip pages [0 ..]

-- | Every link annotation of a PDF: those with /A and those with /Dest.
linkCount :: BS.ByteString -> Int
linkCount pdf = length [() | o <- Map.elems (objectsOf pdf), "/Subtype /Link" `BS.isInfixOf` o]

-- | The items of the outline in preorder, each with its depth from 1 and its /Count, if any.
outlineOf :: BS.ByteString -> [(Int, T.Text, Maybe Int)]
outlineOf pdf = case refsAfter "/Outlines" catalog' of
  _ | not ("/Outlines " `BS.isInfixOf` catalog') -> []
  _ -> case BC.words (snd (BS.breakSubstring "/Outlines " catalog')) of
    _ : n : _ -> walk 1 (first (read (BC.unpack n)))
    _ -> []
  where
    objs = objectsOf pdf
    catalog' = Map.findWithDefault "" 1 objs
    refOf key o = case BC.words (snd (BS.breakSubstring (key <> " ") o)) of
      _ : n : "0" : "R" : _ -> Just (read (BC.unpack n) :: Int)
      _ -> Nothing
    first n = refOf "/First" (Map.findWithDefault "" n objs)
    countOf o = case BC.words (snd (BS.breakSubstring "/Count " o)) of
      _ : c : _ | "/Count " `BS.isInfixOf` o -> Just (read (BC.unpack c) :: Int)
      _ -> Nothing
    walk d = \case
      Nothing -> []
      Just n ->
        let o = Map.findWithDefault "" n objs
         in (d, fromMaybe "" (textAfter "/Title" o), countOf o) : walk (d + 1) (refOf "/First" o) <> walk d (refOf "/Next" o)

-- | The glyphs of each page.
pageGlyphs :: BS.ByteString -> IO [[Drawn]]
pageGlyphs pdf = map drawnGlyphs <$> pageContents pdf

-- | The y of a glyph of a page.
yOf :: Drawn -> Double
yOf = read . BC.unpack . dY

xOf :: Drawn -> Double
xOf = read . BC.unpack . dX

near :: Double -> Double -> Assertion
near a b = assertBool (show (a, b)) (abs (a - b) < 0.01)

-- | The glyphs of a character on each page, with the index of the page.
glyphsOf :: Char -> [[Drawn]] -> [(Int, Drawn)]
glyphsOf c pages = [(i, d) | (i, ds) <- zip [0 ..] pages, d <- ds, dGlyph d == fromEnum c]

{- | The top of the face of the line of a glyph of the body (10pt in
'horizontalStyle'): 0.88 of the size above its baseline.
-}
faceTopOf :: Drawn -> Double
faceTopOf d = yOf d + 8.8

-- | The manifest of a one-chapter project of the line style: a line of the source is a paragraph.
lineManifest :: BS.ByteString
lineManifest = TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["pdf"], tmSource = Just "line"})

-- | A one-chapter project of 'lineManifest' built to PDF with the fake fonts, without errors.
pdfOf :: BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO BS.ByteString
pdfOf = pdfWith id

-- | 'pdfOf' with the options changed.
pdfWith :: (BuildOptions -> BuildOptions) -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO BS.ByteString
pdfWith f style src files = withSystemTempDirectory "golem-inside" $ \tmp -> do
  writeProject tmp lineManifest style src files
  r <- build (f (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider})
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> BS.readFile p
    _ -> assertFailure "no PDF"

-- | 29 one-line paragraphs before what follows: it starts on the last line of a page of 30 lines.
lineFillers :: Int -> T.Text
lineFillers n = T.concat ["埋め草の段落" <> T.pack (show k) <> "。\n" | k <- [1 .. n]]

-- | The conformance fixture (docs/adr ADR 0183) with fonts, built to PDF; the other style and manifest when given.
conformancePdf :: Maybe FilePath -> Maybe FilePath -> IO BS.ByteString
conformancePdf style manifest = withSystemTempDirectory "golem-inside" $ \tmp -> do
  copyTree "test/fixtures/conformance" tmp
  createDirectoryIfMissing True (tmp </> "fonts")
  copyFile "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" (tmp </> "fonts/ja.otf")
  copyFile "../golem-font/test/fonts/SourceSansPro-Regular.otf" (tmp </> "fonts/latin.otf")
  mapM_ (\f -> copyFile (tmp </> f) (tmp </> "style.toml")) style
  mapM_ (\f -> copyFile (tmp </> f) (tmp </> "manifest.toml")) manifest
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf]}
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> BS.readFile p
    _ -> assertFailure "no PDF"

-- | The structure tree of the conformance fixture (docs/adr ADR 0183).
conformanceTree :: Maybe FilePath -> Maybe FilePath -> IO [T.Text]
conformanceTree style manifest = withSystemTempDirectory "golem-inside" $ \tmp -> do
  copyTree "test/fixtures/conformance" tmp
  createDirectoryIfMissing True (tmp </> "fonts")
  copyFile "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" (tmp </> "fonts/ja.otf")
  copyFile "../golem-font/test/fonts/SourceSansPro-Regular.otf" (tmp </> "fonts/latin.otf")
  mapM_ (\f -> copyFile (tmp </> f) (tmp </> "style.toml")) style
  mapM_ (\f -> copyFile (tmp </> f) (tmp </> "manifest.toml")) manifest
  r <- pdfStructure (defaultOptions tmp)
  either (\ds -> assertFailure (show (map diagCode ds)) >> pure []) (pure . T.lines) r

-- | Each line of a structure tree with the type of its parent element.
withParents :: [T.Text] -> [(T.Text, T.Text)]
withParents = go []
  where
    depth l = T.length (T.takeWhile (== ' ') l) `div` 2
    go _ [] = []
    go stack (l : rest) =
      let d = depth l
          kept = take d stack
          parent = case reverse kept of
            p : _ -> p
            [] -> ""
          name = T.takeWhile (not . isSpace) (T.strip l)
       in (T.strip l, parent) : go (kept <> [name]) rest

-- | The style of 'horizontalStyle' with a bleed of 3mm, for the crop marks.
markedStyle :: BS.ByteString
markedStyle = replaceIn "binding = \"left\"\n" "binding = \"left\"\nbleed = \"3mm\"\n" horizontalStyle

insideLinksTests :: TestTree
insideLinksTests =
  testGroup
    "the bookmarks of the PDF and its links inside the document (docs/adr/0267)"
    [ testGroup "destinations" destinationTests,
      testGroup "sources" sourceTests,
      testGroup "bookmarks" outlineTests,
      testGroup "the conformance fixture" conformanceTests
    ]

destinationTests :: [TestTree]
destinationTests =
  [ testCase "I2 horizontal: a reference to the first line of a page and to the last goes to the top of the face of that line" $ do
      let src = "@label top\n始まりの段落。\n" <> lineFillers 28 <> "@label bottom\n終わりの段落。\n次のページ。[ref-page top]と[ref-page bottom]。\n"
      pdf <- pdfOf horizontalStyle src []
      pages <- pageGlyphs pdf
      let is = insides pdf
      case (glyphsOf '始' pages, glyphsOf '終' pages) of
        ((0, s) : _, (0, e) : _) -> do
          case is of
            [a, b] -> do
              (inPage a, inPage b) @?= (0, 0)
              near (inTop a) (faceTopOf s)
              near (inTop b) (faceTopOf e)
              -- the last line of the page is 29 line pitches of 15pt below the first
              near (inTop a - inTop b) (29 * 15)
            other -> assertFailure (show other)
        other -> assertFailure (show other),
    testCase "I2 horizontal: a reference to a figure goes to the top of its image, to a table to the top of its first grid row" $ do
      img <- tinyImage
      let src = "# 章\n参照は[ref-page fig]と[ref-page tbl]。\n\n@label fig\n@figure images/tiny.jpg alt=\"t\"\n\n@label tbl\n| 表の頭 | 二 |\n|---|---|\n| 一 | 二 |\n"
      pdf <- pdfOf horizontalStyle src img
      pages <- pageGlyphs pdf
      contents <- pageContents pdf
      let imageTop = case [ws | c <- contents, l <- BC.lines c, let ws = BC.words l, "Do" `elem` ws, "cm" `elem` ws] of
            ws : _ -> case dropWhile (/= "cm") (reverse ws) of
              -- w 0 0 h x y cm
              _ : y : _ : h : _ -> read (BC.unpack y) + read (BC.unpack h) :: Double
              _ -> 0
            [] -> 0
      case (insides pdf, glyphsOf '表' pages) of
        ([f, t], (_, cell) : _) -> do
          near (inTop f) imageTop
          near (inTop t) (faceTopOf cell)
        other -> assertFailure (show other),
    testCase "I2 vertical: a reference goes to the top of the face of the line, its start, on the page of the target" $ do
      let src = "@label top\n始まりの段落。\n" <> T.replicate 20 "埋め草の段落。\n" <> "参照は[ref-page top]。\n"
      pdf <- pdfOf pdfStyle src []
      pages <- pageGlyphs pdf
      case (insides pdf, glyphsOf '始' pages) of
        ([a], (0, s) : _) -> do
          inPage a @?= 0
          -- the top of the em box of the first character of the line: its glyph is drawn from it down the line
          near (inTop a) (yOf s)
        other -> assertFailure (show other),
    testCase "I2 the top is on the page with the crop marks and the bleed: the origin of the frame added" $ do
      let src = "@label top\n始まりの段落。\n参照は[ref-page top]。\n"
      plain <- pdfOf horizontalStyle src []
      marked <- pdfWith (\o -> o {optMarks = JapaneseMarks}) markedStyle src []
      case (insides plain, insides marked) of
        ([a], [b]) -> do
          -- 3mm of bleed and the marks' 2415027sp around it
          let origin = (3 * 72 / 25.4) + 2415027 / 65536
          assertBool (show (inTop a, inTop b, origin)) (abs (inTop b - inTop a - origin) < 0.02)
          case (inRect a, inRect b) of
            (x : _, x' : _) -> assertBool (show (x, x')) (abs (x' - x - origin) < 0.02)
            other -> assertFailure (show other)
        other -> assertFailure (show other),
    testCase "I1 every destination is [p 0 R /XYZ null t null], p a page and t on it" $ do
      let src = "@label top\n# 始まりの章\n" <> lineFillers 40 <> "参照は[ref-number top]と[ref-page top]。\n"
      pdf <- pdfOf horizontalStyle src []
      let is = insides pdf
          n = length (pageObjects pdf)
      length is @?= 2
      forM_ is $ \i -> do
        assertBool (show i) (inPage i >= 0 && inPage i < n)
        assertBool (show i) (inTop i > 0 && inTop i < 595.28)
      -- no annotation has both, none neither
      length [() | o <- Map.elems (objectsOf pdf), "/Subtype /Link" `BS.isInfixOf` o, "/Dest [" `BS.isInfixOf` o == ("/A <<" `BS.isInfixOf` o)] @?= 0,
    testCase "G07120: a destination missing from the table is one error at the first source, and no PDF" $
      withSystemTempDirectory "golem-inside" $ \tmp -> do
        let src = "@label top\n始まりの段落。\n参照は[ref-page top]と[ref-page top]。\n"
        writeProject tmp lineManifest horizontalStyle src []
        whole <- pdfWithDests id (defaultOptions tmp) {optFonts = fakeProvider}
        assertBool "the whole table gives a PDF" (either (const False) (const True) whole)
        r <- pdfWithDests (Map.delete (DestLabel "top")) (defaultOptions tmp) {optFonts = fakeProvider}
        case r of
          Left ds -> do
            [(diagCode d, diagSeverity d, spanStart (diagSpan d)) | d <- ds] @?= [(DiagnosticCode "G07120", Error, offsetIn "[ref-page top]" src)]
            map diagMessage ds @?= ["リンクの元かしおりの項目の行先が、描いたページにありません（2 か所）。Golem の誤りです。この入力を添えて報告してください"]
          Right _ -> assertFailure "a PDF was written",
    testCase "G07120: a bookmark whose heading is missing from the table is at the heading" $
      withSystemTempDirectory "golem-inside" $ \tmp -> do
        let src = "前の段落。\n# 章の見出し\n本文。\n"
        writeProject tmp lineManifest horizontalStyle src []
        r <- pdfWithDests (Map.filterWithKey (\k _ -> case k of DestHeading _ -> False; _ -> True)) (defaultOptions tmp) {optFonts = fakeProvider}
        case r of
          Left ds -> [(diagCode d, spanStart (diagSpan d)) | d <- ds] @?= [(DiagnosticCode "G07120", offsetIn "# 章の見出し" src)]
          Right _ -> assertFailure "a PDF was written"
  ]
  where
    offsetIn needle hay = BS.length (TE.encodeUtf8 (fst (T.breakOn needle hay)))

sourceTests :: [TestTree]
sourceTests =
  [ testCase "I3 a reference on one line is one annotation over the face of its text" $ do
      let src = "@label h\n# 題\n参照は[ref-title h]。\n"
      pdf <- pdfOf horizontalStyle src []
      pages <- pageGlyphs pdf
      case insides pdf of
        [a] -> case (inRect a, glyphsOf '照' pages, glyphsOf '題' pages) of
          ([x0, y0, x1, y1], (_, s) : _, _ : _) -> do
            -- 参照は: three characters of 10pt before it, its text one character
            near x0 (xOf s + 20)
            near (x1 - x0) 10
            near y0 (yOf s - 1.2)
            near (y1 - y0) 10
            inContents a @?= Just "題"
          other -> assertFailure (show other)
        other -> assertFailure (show other),
    testCase "I3 a reference that ends at the end of the line, and one that runs one character over: one annotation a line" $ do
      -- 12 characters a line: 参照は then a title of 9 characters ends the line, of 10 runs over
      let exact = "@label h\n# " <> T.replicate 9 "題" <> "\n参照は[ref-title h]\n"
          over = "@label h\n# " <> T.replicate 10 "題" <> "\n参照は[ref-title h]\n"
      e <- pdfOf horizontalStyle exact []
      o <- pdfOf horizontalStyle over []
      map (\i -> round (widthOf i) :: Int) (insides e) @?= [90]
      map (\i -> round (widthOf i) :: Int) (insides o) @?= [90, 10]
      map inContents (insides o) @?= replicate 2 (Just (T.replicate 10 "題")),
    testCase "I3 a reference over two pages: an annotation on each line, on its page" $ do
      -- two lines at the foot of the first page, two at the top of the second; the heading after them
      let src = lineFillers 28 <> "参照は[ref-title h]\n@label h\n# " <> T.replicate 45 "題" <> "\n"
      pdf <- pdfOf horizontalStyle src []
      let is = insides pdf
      map inOn is @?= [0, 0, 1, 1]
      map inPage is @?= [1, 1, 1, 1],
    testCase "I3 the mark of a footnote goes to the body, the mark of the body back to the mark in the text" $ do
      let src = "本文[note: 注の本文。]の後。\n"
      pdf <- pdfOf horizontalStyle src []
      pages <- pageGlyphs pdf
      case (insides pdf, glyphsOf '後' pages, glyphsOf '注' pages) of
        ([toBody, back], (_, b) : _, (_, n) : _) -> do
          near (inTop toBody) (yOf n + 0.88 * 10)
          near (inTop back) (faceTopOf b)
          -- the marks as drawn, in the format of [notes] mark-format
          (inContents toBody, inContents back) @?= (Just "*1", Just "*1")
        other -> assertFailure (show other),
    testCase "I3 the notes at the end of the chapter: the mark goes to the note, its mark back" $ do
      let style = horizontalStyle <> "\n[notes]\nplacement = \"chapter-end\"\n"
          src = "本文[note: 注の本文。]の後。\n"
      pdf <- pdfOf style src []
      pages <- pageGlyphs pdf
      case (insides pdf, glyphsOf '後' pages, glyphsOf '注' pages) of
        ([toNote, back], (_, b) : _, ns) -> do
          near (inTop back) (faceTopOf b)
          -- the body of the note: the line of its 注 of 10pt (the title of the notes is 注 too, larger)
          case [n | (_, n) <- ns, dSize n == "10"] of
            n : _ -> near (inTop toNote) (faceTopOf n)
            [] -> assertFailure "no note"
        other -> assertFailure (show other),
    testCase "I3 a note of two paragraphs goes to its first line" $ do
      let src = "本文[note k]の後。\n\n@note k\n  一つめの段落。\n  二つめの段落。\n"
      pdf <- pdfOf horizontalStyle src []
      pages <- pageGlyphs pdf
      case (insides pdf, glyphsOf '一' pages) of
        (toBody : _, (_, n) : _) -> near (inTop toBody) (faceTopOf n)
        other -> assertFailure (show other),
    testCase "I3 the index: each page number goes to the first mark of the entry on that page; a range to its two ends" $ do
      let src = "語[index reading=ご: 語]と語[index reading=ご: 語]。\n" <> lineFillers 30 <> "範囲の始め[index reading=はんい range=begin: 範囲]。\n" <> lineFillers 30 <> "範囲の終わり[index reading=はんい range=end: 範囲]。\n\n@index\n"
      pdf <- pdfOf horizontalStyle src []
      pages <- pageGlyphs pdf
      let is = [i | i <- insides pdf, inContents i `elem` map Just ["1", "2", "3"]]
      case (glyphsOf '語' pages, glyphsOf '始' pages, glyphsOf 'わ' pages) of
        ((0, g) : _, (1, s) : _, (2, e) : _) ->
          map (\i -> (inContents i, inPage i, round (inTop i * 100) :: Int)) is
            @?= [(Just "1", 0, round (faceTopOf g * 100)), (Just "2", 1, round (faceTopOf s * 100)), (Just "3", 2, round (faceTopOf e * 100))]
        other -> assertFailure (show other),
    testCase "I3 a citation goes to the entry of the @bibliography, each work its number; none without @bibliography" $
      withSystemTempDirectory "golem-inside" $ \tmp -> do
        writeProject tmp ("bibliography = [\"refs.json\"]\n" <> lineManifest) horizontalStyle "本文[cite a b]。\n\n@bibliography\n" [("refs.json", refs)]
        r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
          [p] -> BS.readFile p
          _ -> assertFailure "no PDF"
        pages <- pageGlyphs pdf
        case (insides pdf, glyphsOf 'A' pages, glyphsOf 'B' pages) of
          ([one, two], (_, a) : _, (_, b) : _) -> do
            map inContents [one, two] @?= [Just "1", Just "2"]
            near (inTop one) (faceTopOf a)
            near (inTop two) (faceTopOf b)
            -- the number alone: a digit of 5pt, the half of 10pt
            map (\i -> round (widthOf i * 10) :: Int) [one, two] @?= [50, 50]
          other -> assertFailure (show other)
        withSystemTempDirectory "golem-inside" $ \tmp2 -> do
          writeProject tmp2 ("bibliography = [\"refs.json\"]\n" <> lineManifest) horizontalStyle "本文[cite a b]。\n" [("refs.json", refs)]
          r2 <- build (defaultOptions tmp2) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
          pdf2 <- case filter (".pdf" `isSuffixOf`) (brWritten r2) of
            [p] -> BS.readFile p
            _ -> assertFailure "no PDF"
          insides pdf2 @?= [],
    testCase "I3 an entry of the table of contents: one annotation a line, the last from its first box to the end of the page number" $ do
      let src = "@toc\n\n# " <> T.replicate 14 "題" <> "\n本文。\n"
      pdf <- pdfOf horizontalStyle src []
      pages <- pageGlyphs pdf
      case (insides pdf, [d | (0, d) <- glyphsOf '題' pages]) of
        ([l1, l2], d1 : _) -> do
          -- the heading after the table of contents on its page
          (inPage l1, inPage l2) @?= (0, 0)
          case (inRect l1, inRect l2) of
            ([x0, _, x1, _], [x0', _, x1', _]) -> do
              -- from the first box, the number of the heading, on each line
              assertBool (show (x0, xOf d1)) (x0 < xOf d1)
              -- the first line short of the room for the page number, its boxes alone
              assertBool (show (x1 - x0)) (x1 - x0 < 120)
              near x0' x0
              -- the measure of 12 characters: the page number ends it
              near (x1' - x0') 120
            other -> assertFailure (show other)
          inContents l2 @?= Just ("1　" <> T.replicate 14 "題" <> "1")
        other -> assertFailure (show other),
    testCase "I4 a note in a heading: no annotation of its mark in the entry of the table of contents, nor in a [ref-title]" $ do
      -- a heading cannot hold a cross-reference (G02014): the note is the source inside an entry
      let src = "@toc\n\n@label h\n# 題[note: 注。]\n本文[ref-title h]。\n"
      pdf <- pdfOf horizontalStyle src []
      let is = insides pdf
      -- the entry: one annotation over its line, its text and page number, to its heading
      case [i | i <- is, maybe False ("1　題" `T.isPrefixOf`) (inContents i)] of
        [e] -> near (widthOf e) 120
        other -> assertFailure (show other)
      -- the [ref-title]: one annotation over the title it copies and the mark in it
      case [i | i <- is, inContents i == Just "題"] of
        [r] -> near (widthOf r) 15
        other -> assertFailure (show other)
      -- I4: no two annotations of a page meet inside
      [(a, b) | (k, a) <- zip [0 :: Int ..] is, b <- drop (k + 1) is, inOn a == inOn b, overlaps (inRect a) (inRect b)] @?= [],
    testCase "I4 inside a [ref-title] a link of the title it copies is no annotation" $ do
      let src = "@label h\n# 章[link \"https://example.com/\": 題]\n本文[ref-title h]。\n"
      pdf <- pdfOf horizontalStyle src []
      linkCount pdf @?= 2
      map inContents (insides pdf) @?= [Just "章題"]
  ]
  where
    refs = TE.encodeUtf8 "[{\"id\": \"a\", \"title\": \"A\"}, {\"id\": \"b\", \"title\": \"B\"}]"

outlineTests :: [TestTree]
outlineTests =
  [ testCase "I5 I6 I7 without @toc: every heading but those of @notoc, nested by level, closed" $ do
      let src = "# 一\n## 二\n#### 四\n@notoc\n## 外\n# 五\n### 六\n## 七\n本文。\n"
      pdf <- pdfOf horizontalStyle src []
      -- 四 a child of 二, 六 of 五, each closed with the count of its children made negative
      outlineOf pdf @?= [(1, "1　一", Just (-1)), (2, "1.1　二", Just (-1)), (3, "1.1.0.1　四", Nothing), (1, "2　五", Just (-2)), (2, "2.0.1　六", Nothing), (2, "2.1　七", Nothing)]
      assertBool "/PageMode" ("/PageMode /UseOutlines" `BS.isInfixOf` Map.findWithDefault "" 1 (objectsOf pdf))
      assertBool "/Count 2 at the root" ("/Count 2 " `BS.isInfixOf` pdf),
    testCase "I5 @toc depth=6 and @toc depth=1: the outline is the entries of the table of contents" $ do
      deep <- pdfOf horizontalStyle "@toc depth=6\n\n# 一\n## 二\n本文。\n" []
      map (\(d, t, _) -> (d, t)) (outlineOf deep) @?= [(1, "1　一"), (2, "1.1　二")]
      shallow <- pdfOf horizontalStyle "@toc depth=1\n\n# 一\n## 二\n本文。\n" []
      map (\(d, t, _) -> (d, t)) (outlineOf shallow) @?= [(1, "1　一")],
    testCase "I8 no entry: no /Outlines and no /PageMode" $ do
      none <- pdfOf horizontalStyle "@toc depth=1\n\n## 二\n本文。\n" []
      outlineOf none @?= []
      assertBool "no Outlines" (not ("/Outlines" `BS.isInfixOf` none))
      assertBool "no PageMode" (not ("/PageMode" `BS.isInfixOf` none))
      plain <- pdfOf horizontalStyle "本文。\n" []
      assertBool "no Outlines" (not ("/Outlines" `BS.isInfixOf` plain)),
    testCase "I5 the title of an item: the short title of @toc-title, ruby its base alone" $ do
      pdf <- pdfOf horizontalStyle "@toc-title 短い題\n# 長い[ruby: 題|だい]\n## [ruby: 漢字|かんじ]の節\n本文。\n" []
      map (\(_, t, _) -> t) (outlineOf pdf) @?= ["1　短い題", "1.1　漢字の節"],
    testCase "I5 a bookmark goes to its heading" $ do
      pdf <- pdfOf horizontalStyle ("# 一\n" <> lineFillers 40 <> "# 二\n本文。\n") []
      pages <- pageGlyphs pdf
      let objs = objectsOf pdf
          dests = [BC.words (fst (BS.breakSubstring "]" (BS.drop 7 (snd (BS.breakSubstring "/Dest [" o))))) | o <- Map.elems objs, "/Title " `BS.isInfixOf` o, "/Dest [" `BS.isInfixOf` o]
          pageIndex = zip (pageObjects pdf) [0 :: Int ..]
      case (dests, glyphsOf '二' pages) of
        ([[p1, _, _, _, _, _, _], [p2, _, _, _, _, t2, _]], (i, d) : _) -> do
          lookup (read (BC.unpack p1)) pageIndex @?= Just 0
          lookup (read (BC.unpack p2)) pageIndex @?= Just i
          -- the heading of 2: its size from its style; its face's top above its baseline
          assertBool (show (t2, yOf d)) (read (BC.unpack t2) > yOf d)
        other -> assertFailure (show other)
  ]

conformanceTests :: [TestTree]
conformanceTests =
  [ testCase "I3 I9 each kind of source has a Link with annotations, under a Reference or a Lbl" $
      forM_ [(Nothing, Nothing), (Just "style-vertical.toml", Just "manifest-vertical.toml")] $ \(st, mf) -> do
        t <- conformanceTree st mf
        let ps = withParents t
            depths = [T.length (T.takeWhile (== ' ') l) `div` 2 | l <- t]
            -- each Link and the annotations of its OBJR
            links =
              [ (p, l, n)
              | (i, ((l, p), d)) <- zip [0 :: Int ..] (zip ps depths),
                l == "Link",
                let kids = takeWhile (\(_, d') -> d' > d) (drop (i + 1) (zip (map fst ps) depths))
                    n = sum [read (T.unpack (T.drop 5 k)) :: Int | (k, d') <- kids, d' == d + 1, "OBJR " `T.isPrefixOf` k]
              ]
            inside = [(p, n) | (p, _, n) <- links, p `elem` ["Reference", "Lbl"]]
        -- every Link has an annotation
        [l | l@(_, _, n) <- links, n < 1] @?= []
        -- the external links of the fixture: two in the text, and none else
        length [() | (p, _, _) <- links, p `notElem` ["Reference", "Lbl"]] @?= 2
        -- the notes (two marks and two marks back), the citation, the index page, the cross-references, the entries
        assertBool (show inside) (length [() | ("Lbl", _) <- inside] >= 2)
        assertBool (show inside) (length [() | ("Reference", _) <- inside] >= 10),
    testCase "I3 the PDF of the conformance fixture: an annotation for each Link of the tree, each destination on its pages" $ do
      pdf <- conformancePdf Nothing Nothing
      let is = insides pdf
          n = length (pageObjects pdf)
      assertBool (show (length is)) (length is >= 12)
      [i | i <- is, inPage i < 0 || inPage i >= n] @?= []
      assertBool "an outline" (not (null (outlineOf pdf))),
    testCase "I10 the PDF of the conformance fixture is the same bytes twice" $ do
      a <- conformancePdf Nothing Nothing
      b <- conformancePdf Nothing Nothing
      assertBool "the same bytes" (a == b)
      qpdfCheck a
  ]
