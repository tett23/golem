-- | Drop caps through the ordinary evaluation and layout pipeline (root ADR 0465).
module DropCapsSpec (dropCapsTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (Look (..))
import Golem.Layout.Paginate (PageOutAt (..), Slotted (..))
import Golem.Length (Sp (..))
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), SetLine (..), Shaped (..), Shaping (..))
import Support
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

fs :: Sp
fs = 655360

dropStyle :: BS.ByteString -> BS.ByteString
dropStyle keys = horizontalStyle <> "\n[paragraph-styles.title]\nfirst-line-indent = \"1zw\"\n" <> keys

linesOf :: PdfLayout -> [SetLine]
linesOf = Map.elems . plLines

setLines :: PdfLayout -> [(Sp, [Item])]
setLines pl = [(slIndent sl, lineItems (slLine sl)) | sl <- linesOf pl]

buildDiagnostics :: Bool -> BS.ByteString -> T.Text -> IO [Diagnostic]
buildDiagnostics check style source = withSystemTempDirectory "golem-drop" $ \tmp -> do
  writeProject tmp miniManifest style source []
  brDiagnostics <$> build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optCheckOnly = check}

dropCapsTests :: [TestTree]
dropCapsTests =
  carriedNotePrefixTests
    <> prefixSourceTests
    <> prefixOutputTests
    <> additionalPrefixTests
    <> unplaceableDropCapsTests
    <> integrationHeadingTests
    <> wrappedDropCapsTests
    <> wrappedInitialRowsTests
    <> [ testCase "root ADR 0465 I2, I4: three-line drop cap shortens three lines and suppresses first-line indent" $ do
           (_, pl) <- layoutOk (dropStyle "drop-lines = 3\n") ("@style title\n" <> T.replicate 70 "あ" <> "\n") []
           let ls = linesOf pl
           assertBool "at least four lines" (length ls > 3)
           take 4 (map slIndent ls) @?= [4 * fs, 4 * fs, 4 * fs, 0]
           take 4 (map (lineTarget . slLine) ls) @?= [8 * fs, 8 * fs, 8 * fs, 12 * fs]
           let caps = [bcLook c | sl <- ls, Box _ c <- lineItems (slLine sl), lkSize (bcLook c) > fs]
           map lkSize caps @?= [4 * fs],
         testCase "root ADR 0465 I4: right alignment does not move the initial into later body lines" $ do
           (_, pl) <- layoutOk (dropStyle "drop-lines = 3\nalign = \"right\"\n") "@style title\nあいう\n" []
           let capStarts = [slIndent sl + bcPadStart c | sl <- linesOf pl, Box _ c <- lineItems (slLine sl), lkSize (bcLook c) > fs]
           capStarts @?= [0],
         testCase "root ADR 0465 I3: a one-character paragraph occupies the requested three lines" $ do
           (_, pl) <- layoutOk (dropStyle "drop-lines = 3\n") "@style title\nあ\n" []
           length (linesOf pl) @?= 3,
         testCase "root ADR 0465 I3: the three initial rows move together when only two rows remain" $ do
           let style = replaceIn "lines = 30" "lines = 5" (dropStyle "drop-lines = 3\n[paragraph-styles.body]\nfirst-line-indent = \"0zw\"\n")
           (_, pl) <- layoutOk style (T.replicate 36 "先" <> "\n\n@style title\nあ\n") []
           let positions = Map.fromList [(ident, (poNumber page, poColumn page)) | page <- plPages pl, (_, SLine ident) <- poSlots page]
           map (`Map.lookup` positions) [3, 4, 5] @?= replicate 3 (Just (2, 0)),
         testCase "root ADR 0465 I2: one row uses the ordinary glyph size but has no first-line indent" $ do
           (_, pl) <- layoutOk (dropStyle "drop-lines = 1\n") "@style title\nあいう\n" []
           take 1 (map slIndent (linesOf pl)) @?= [fs]
           [lkSize (bcLook c) | sl <- linesOf pl, Box _ c <- lineItems (slLine sl), not (T.null (bcText c))] @?= [fs, fs, fs],
         testCase "root ADR 0465 I2, I3: kept source lines apply the cap only to their first part" $ do
           (_, pl) <- layoutOk (dropStyle "drop-lines = 3\nline-breaks = \"keep\"\n") "@style title\n  あ\n  いうえ\n" []
           map slIndent (linesOf pl) @?= [4 * fs, 4 * fs, 4 * fs, fs]
           length [() | sl <- linesOf pl, Box _ c <- lineItems (slLine sl), lkSize (bcLook c) > fs] @?= 1,
         testCase "root ADR 0465 I2: the actual initial face supplies cap height, ignoring initial-style size" $ do
           let shape request text = [if shRole request == "heading" && text == "H" then glyph {shFace = 0} else glyph | glyph <- lfShape fakeFonts request text]
               fonts = fakeFonts {lfShape = shape, lfCapHeight = \face -> if face == 4 then 1 / 2 else 7 / 10}
               provider = FontProvider (\_ _ _ _ -> pure (Right fonts))
               style = dropStyle "drop-lines = 3\ninitial-style = \"cap\"\n[character-styles.cap]\nfont = \"heading\"\nsize = \"100pt\"\n[fonts.body]\nja = \"fonts/b.otf\"\n[fonts.heading]\nlatin = \"fonts/h.otf\"\n"
           laid <- layoutMiniFonts provider miniManifest style "@style title\nAbcd\n" fakeFontFiles
           (_, pl) <- either (assertFailure . show) pure laid
           [lkSize (bcLook c) | sl <- linesOf pl, Box _ c <- lineItems (slLine sl), bcText c == "A"] @?= [74 * 65536],
         testCase "root ADR 0465 I2: drop-gap is added to the advance on each shortened line" $ do
           (_, pl) <- layoutOk (dropStyle "drop-lines = 2\ndrop-gap = \"2pt\"\n") ("@style title\n" <> T.replicate 40 "あ" <> "\n") []
           take 3 (map slIndent (linesOf pl)) @?= [Sp 1769472, Sp 1769472, 0],
         testCase "root ADR 0465 I1, I7: list items ignore drop-lines and retain their lines" $ do
           let src = "@style title\n  - あいうえおかきくけこさしすせそ\n"
           (_, dropped) <- layoutOk (dropStyle "drop-lines = 3\n") src []
           (_, plain) <- layoutOk (dropStyle "") src []
           setLines dropped @?= setLines plain,
         testCase "root ADR 0465 I5: a reference diagnosed as non-text stays without a drop cap after resolution" $ do
           let source = "@label h\n# 題\n\n@style title\n[ref-title h]が先頭。\n"
               style = dropStyle "drop-lines = 3\n"
           ds <- buildDiagnostics True style source
           length (diagnosticsOf "G07143" ds) @?= 1
           (_, pl) <- layoutOk style source []
           [bcText box | sl <- linesOf pl, Box _ box <- lineItems (slLine sl), lkSize (bcLook box) == 4 * fs] @?= [],
         testCase "root ADR 0465 I5: unsupported initials warn once per paragraph, not for a list item" $ do
           ds <- buildDiagnostics True (dropStyle "drop-lines = 2\n") "@style title\n[ruby: 漢 | かん]です。\n\n@style title\n[tcy: 12]月。\n\n@style title\n  - [ruby: 字 | じ]です。\n"
           length (diagnosticsOf "G07143" ds) @?= 2,
         testCase "root ADR 0465 I2: HTML writes initial-letter and gap with excluded paragraphs marked" $ withSystemTempDirectory "golem-drop-html" $ \tmp -> do
           writeProject tmp (miniManifest <> "\n[targets.html]\n") (dropStyle "drop-lines = 3\ndrop-gap = \"2pt\"\n") "@style title\nあいうえお\n\n@style title\n  - あいうえお\n" []
           r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml], optFonts = fakeProvider}
           filter isError (brDiagnostics r) @?= []
           css <- TIO.readFile (tmp </> "build/html/style.css")
           assertBool "initial-letter rule" ("p.ps-title:not([data-no-drop])::first-letter { initial-letter: 3; margin-inline-end: 2pt; }" `T.isInfixOf` css)
           page <- TIO.readFile (tmp </> "build/html/a.html")
           T.count "data-no-drop" page @?= 1
       ]

-- | A short start-side figure must not put later body rows under the initial.
wrappedDropCapsTests :: [TestTree]
wrappedDropCapsTests =
  [ testCase ("root ADR 0465 I4: short " <> T.unpack side <> " figure, " <> T.unpack writing <> ", " <> T.unpack placement) $ do
      imageFiles <- tinyImage
      let base = replaceIn "characters = 12" "characters = 20" (replaceIn "lines = 30" "lines = 10" (dropStyle "drop-lines = 3\n"))
          placed = if placement == "free" then replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" base else base
          style = figStyle (replaceIn "writing-mode = \"horizontal\"" ("writing-mode = \"" <> writing <> "\"") placed)
          source = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=" <> side <> " width=1zw\n\n@style title\n" <> T.replicate 90 "あ" <> "\n"
      (_, pl) <- layoutOk style source imageFiles
      case [slIndent sl + bcPadStart box + lkSize (bcLook box) | sl <- linesOf pl, Box _ box <- lineItems (slLine sl), lkSize (bcLook box) > fs] of
        [rightEdge] -> assertBool (show (rightEdge, take 3 (map slIndent (linesOf pl)))) (all (>= rightEdge) (take 3 (map slIndent (linesOf pl))))
        other -> assertFailure (show other)
  | writing <- ["horizontal", "vertical"],
    placement <- ["grid", "free"],
    side <- ["start", "end"]
  ]

-- | The initial rows must remain together when a short figure ends at a page boundary.
wrappedInitialRowsTests :: [TestTree]
wrappedInitialRowsTests =
  [ testCase ("root ADR 0465 I3: wrapped initial rows move together, " <> T.unpack writing <> ", " <> T.unpack placement) $ do
      imageFiles <- tinyImage
      let base = replaceIn "characters = 12" "characters = 20" (replaceIn "lines = 30" "lines = 4" (dropStyle "drop-lines = 3\n[paragraph-styles.body]\nfirst-line-indent = \"0zw\"\n"))
          placed = if placement == "free" then replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" base else base
          style = figStyle (replaceIn "writing-mode = \"horizontal\"" ("writing-mode = \"" <> writing <> "\"") placed)
          source = T.replicate 36 "先" <> "\n\n@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=1zw\n\n@style title\n" <> T.replicate 90 "あ" <> "\n"
      (_, pl) <- layoutOk style source imageFiles
      let positions = Map.fromList [(ident, (poNumber page, poColumn page)) | page <- plPages pl, (_, SLine ident) <- poSlots page]
      case [ident | (ident, sl) <- Map.toList (plLines pl), Box _ box <- lineItems (slLine sl), lkSize (bcLook box) > fs] of
        [initial] -> map (`Map.lookup` positions) [initial, initial + 1, initial + 2] @?= replicate 3 (Just (2, 0))
        other -> assertFailure (show other)
  | writing <- ["horizontal", "vertical"],
    placement <- ["grid", "free"]
  ]

integrationHeadingTests :: [TestTree]
integrationHeadingTests =
  [ testCase "root ADR 0465 I7, root ADR 0468 I2: heading ignores drop-lines in its selected style" $ do
      let style = horizontalStyle <> "\n[paragraph-styles.h]\ndrop-lines = 3\n[headings.1]\nsize = \"10pt\"\n"
      (_, selected) <- layoutOk (style <> "paragraph-style = \"h\"\n") "# 題名\n" []
      (_, plain) <- layoutOk style "# 題名\n" []
      setLines selected @?= setLines plain,
    testCase "root ADR 0465 I2, I3, root ADR 0468 I2: heading next-style activates body drop caps" $ do
      let style = horizontalStyle <> "\n[paragraph-styles.h]\nnext-style = \"cap\"\n[paragraph-styles.cap]\ndrop-lines = 3\n[headings.1]\nsize = \"10pt\"\nparagraph-style = \"h\"\n"
      (_, pl) <- layoutOk style "# 題名\n\nあ\n" []
      length (linesOf pl) @?= 4
      length [() | sl <- linesOf pl, Box _ c <- lineItems (slLine sl), lkSize (bcLook c) > fs] @?= 1
  ]

-- | A hard drop-cap prefix must not use the ordinary empty-column keep fallback.
unplaceableDropCapsTests :: [TestTree]
unplaceableDropCapsTests =
  [ localOption hangTimeout $ testCase ("root ADR 0476 " <> invariant <> ": " <> label <> ", " <> T.unpack writing <> ", " <> T.unpack placement <> ", columns=" <> show (columns :: Int)) $ do
      let base = replaceIn "columns = 1" ("columns = " <> T.pack (show columns) <> "\ncolumn-gap = \"2zw\"") $ replaceIn "line-pitch = \"15pt\"" "line-pitch = \"10pt\"" (replaceIn "lines = 30" ("lines = " <> T.pack (show (capacity :: Int))) (dropStyle "drop-lines = 3\n")) <> pitch
          placed = if placement == "free" then replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" base else base
          style = replaceIn "writing-mode = \"horizontal\"" ("writing-mode = \"" <> writing <> "\"") placed
      result <- layoutMini style (controls <> "@style title\nあ\n") []
      if fails
        then case result of
          Left ds -> map diagCode (filter isError ds) @?= [DiagnosticCode "G07145"]
          Right _ -> assertFailure "the hard initial rows were silently split"
        else do
          (_, layout) <- either (assertFailure . show) pure result
          let positions = [(poNumber page, poColumn page) | page <- plPages layout, (_, SLine ident) <- poSlots page, ident >= (if label == "enlargement is local to one column" then 1 else 0), ident < (if label == "enlargement is local to one column" then 4 else 3)]
          length positions @?= 3
          case positions of
            first : rest -> assertBool (show positions) (all (== first) rest)
            [] -> assertFailure "no initial rows"
          case expectedPage of
            Nothing -> pure ()
            Just n -> map fst positions @?= replicate 3 n
  | writing <- ["horizontal", "vertical"],
    placement <- ["grid", "free"],
    columns <- [1, 2],
    (label, invariant, capacity, controls, pitch, fails, expectedPage) <-
      [ ("exactly three rows", "I1, I3", 3, "", "", False, Just 1),
        ("one row over capacity", "I2", 2, "", "", True, Nothing),
        ("temporarily shortened column", "I1, I3", 3, "@page-lines -1\n", "", False, Just (if columns == 2 then 1 else 2)),
        ("temporarily enlarged column", "I1, I3", 2, "@page-lines +1\n", "", False, Just 1)
      ]
        <> [("enlargement is local to one column", "I2", 2, "@page-lines +1\n先\n\n", "", True, Nothing) | columns == 2]
        <> [("own line bands exceed capacity despite a fitting initial face", "I2", 4, "", "line-pitch = \"15pt\"\n", True, Nothing) | placement == "free"]
  ]

additionalPrefixTests :: [TestTree]
additionalPrefixTests =
  [ localOption hangTimeout $ testCase ("root ADR 0476 " <> invariant <> ": " <> label <> ", " <> T.unpack writing <> ", " <> T.unpack placement) $ do
      imageFiles <- if withFigure then tinyImage else pure []
      let base = replaceIn "characters = 12" "characters = 20" $ replaceIn "line-pitch = \"15pt\"" "line-pitch = \"10pt\"" $ replaceIn "lines = 30" ("lines = " <> T.pack (show (capacity :: Int))) (dropStyle keys)
          placed = if placement == "free" then replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" base else base
          style = (if withFigure then (\st -> figStyle st <> "wrap-gap = \"0pt\"\n") else id) $ replaceIn "writing-mode = \"horizontal\"" ("writing-mode = \"" <> writing <> "\"") placed
          source = (if withFigure then "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=1zw\n\n" else "") <> "@style title\n" <> body
      result <- layoutMini style source imageFiles
      case expected of
        Just code -> case result of
          Left ds -> do
            let errors = filter isError ds
            if label == "joined padding makes initial too tall"
              then do
                assertBool (show errors) (not (null errors) && all ((== DiagnosticCode code) . diagCode) errors)
                Map.size (Map.fromList [(diagSpan err, ()) | err <- errors]) @?= length errors
              else map diagCode errors @?= [DiagnosticCode code]
          Right _ -> assertFailure "the unplaceable initial prefix succeeded"
        Nothing -> do
          _ <- either (assertFailure . show) pure result
          pure ()
  | writing <- ["horizontal", "vertical"],
    placement <- ["grid", "free"],
    (label, invariant, capacity, keys, body, withFigure, expected) <-
      [ ("withFigure initial one row over", "I2", 2, "drop-lines = 3\n", "あ\n", True, Just "G07145"),
        ("padding makes initial too tall", "I2", 4, "drop-lines = 3\nbackground = \"gray\"\npadding = \"10pt\"\n[color.swatches]\ngray = { cmyk = [0, 0, 0, 10] }\n", "あ\n", False, Just "G07145"),
        ("joined padding makes initial too tall", "I2", 4, "drop-lines = 3\nbackground = \"gray\"\npadding = \"10pt\"\n[color.swatches]\ngray = { cmyk = [0, 0, 0, 10] }\n", "あ\n\n@style title\nい\n", False, Just "G07145"),
        ("independently impossible note retains its code", "I5", 2, "drop-lines = 3\n", "あ[note: 注]\n", False, Just (if placement == "free" then "G07130" else "G07125")),
        ("initial rows and their own note", "I2", 4, "drop-lines = 3\n", "あ[note: 注]\n", False, Just "G07145"),
        ("ordinary keep remains soft", "I5", 2, "keep-first-lines = 3\n", T.replicate 60 "あ" <> "\n", False, Nothing),
        ("unsupported ruby initial remains ordinary", "I5", 2, "drop-lines = 3\n", "[ruby: あ | ア]\n", False, Nothing)
      ]
  ]

prefixOutputTests :: [TestTree]
prefixOutputTests =
  [ localOption hangTimeout $
      testCase "root ADR 0476 I4, A2: failure cleans both PDF outputs and preserves other media" $
        withSystemTempDirectory "golem-hard-prefix-output" $ \tmp -> do
          let manifest = miniManifest <> "\n[targets.pdf-screen]\n"
              style rows = replaceIn "lines = 30" ("lines = " <> rows) (dropStyle "drop-lines = 3\n")
              source = "@style title\nあ\n"
              options = (defaultOptions tmp) {optTargets = Just [TargetPdf, TargetPdfScreen], optFonts = fakeProvider}
          writeProject tmp manifest (style "5") source []
          good <- build options
          filter isError (brDiagnostics good) @?= []
          length (brWritten good) @?= 3
          mapM_ (\path -> doesFileExist path >>= (@?= True)) (brWritten good)
          createDirectoryIfMissing True (tmp </> "build/html")
          createDirectoryIfMissing True (tmp </> "build/epub")
          BS.writeFile (tmp </> "build/html/keep.html") "keep html"
          BS.writeFile (tmp </> "build/epub/keep.epub") "keep epub"
          writeProject tmp manifest (style "2") source []
          bad <- build options
          map diagCode (filter isError (brDiagnostics bad)) @?= [DiagnosticCode "G07145"]
          brWritten bad @?= []
          mapM_ (\path -> doesFileExist path >>= (@?= False)) (brWritten good)
          BS.readFile (tmp </> "build/html/keep.html") >>= (@?= "keep html")
          BS.readFile (tmp </> "build/epub/keep.epub") >>= (@?= "keep epub"),
    localOption hangTimeout $
      testCase "root ADR 0476 I5, A3: web-only generation does not evaluate PDF capacity" $
        withSystemTempDirectory "golem-hard-prefix-web" $ \tmp -> do
          let manifest = miniManifest <> "\n[targets.html]\n[targets.epub]\n"
              style = replaceIn "lines = 30" "lines = 2" (dropStyle "drop-lines = 3\n")
          writeProject tmp manifest style "@style title\nあ\n" []
          output <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub], optFonts = fakeProvider}
          filter isError (brDiagnostics output) @?= []
          assertBool "web outputs were generated" (not (null (brWritten output)))
  ]

prefixSourceTests :: [TestTree]
prefixSourceTests =
  [ localOption hangTimeout $ testCase "root ADR 0476 I2: a later wrapped prefix reports its own paragraph" $ do
      files <- tinyImage
      let style = figStyle (replaceIn "characters = 12" "characters = 20" $ replaceIn "line-pitch = \"15pt\"" "line-pitch = \"10pt\"" $ replaceIn "lines = 30" "lines = 3" $ dropStyle "drop-lines = 4\n") <> "wrap-gap = \"0pt\"\n"
          before = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n\nBefore.\n\n@style title\n"
      result <- layoutMini style (before <> "A.\n") files
      case result of
        Right _ -> assertFailure "the later hard prefix was split"
        Left ds -> do
          let errors = filter isError ds
          map diagCode errors @?= [DiagnosticCode "G07145"]
          assertBool (show errors) (all ((>= T.length before) . spanStart . diagSpan) errors)
  ]

-- | A carried note is temporary occupancy, not the normal empty-column capacity.
carriedNotePrefixTests :: [TestTree]
carriedNotePrefixTests =
  [ localOption hangTimeout $ testCase ("root ADR 0476 I1, I3: carried notes drain before the initial rows, " <> T.unpack writing <> ", " <> T.unpack placement) $ do
      let base = replaceIn "line-pitch = \"15pt\"" "line-pitch = \"10pt\"" $ replaceIn "lines = 30" "lines = 3" $ dropStyle "drop-lines = 3\n"
          placed = if placement == "free" then replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" base else base
          style = replaceIn "writing-mode = \"horizontal\"" ("writing-mode = \"" <> writing <> "\"") placed
          source = "先[note k]。\n\n@style title\nあ\n\n@note k\n:::\n" <> T.concat ["注" <> T.pack (show i) <> "。\n\n" | i <- [1 .. 6 :: Int]] <> ":::\n"
      (_, pl) <- layoutOk style source []
      let initials = [ident | (ident, sl) <- Map.toList (plLines pl), Box _ box <- lineItems (slLine sl), lkSize (bcLook box) > fs]
          positions = Map.fromList [(ident, (poNumber page, poColumn page)) | page <- plPages pl, (_, SLine ident) <- poSlots page]
          notePages = [poNumber page | page <- plPages pl, not (null (poFootnotes page))]
      case initials of
        [initial] -> do
          let prefix = map (`Map.lookup` positions) [initial, initial + 1, initial + 2]
          case prefix of
            Just first : rest -> do
              assertBool (show prefix) (all (== Just first) rest)
              assertBool (show notePages) (length notePages >= 2)
              assertBool (show (prefix, notePages)) (all (< fst first) notePages)
            other -> assertFailure (show other)
        other -> assertFailure (show other)
  | writing <- ["horizontal", "vertical"],
    placement <- ["grid", "free"]
  ]
