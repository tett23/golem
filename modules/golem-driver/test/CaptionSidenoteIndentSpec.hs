{- | G07127 and G07128: the indents of the paragraph styles caption and
sidenote that leave no character on a line of the part (docs/adr/0389),
and the indents of a caption from the style of its file.
-}
module CaptionSidenoteIndentSpec (captionSidenoteIndentTests) where

import Control.Monad (forM_, join)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.List (isSuffixOf, nub, sort)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.LayoutSpec (PageGeometry (..), Rect (..))
import Golem.Length (Sp (..))
import Golem.Syntax
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Golem.Typeset (CodeCaption (..), CodeInfo (..), PartLine (..), PdfLayout (..), PlacedFigure (..), PlacedSidenote (..), layoutPdf)
import Support
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

-- | The indents of a paragraph style in characters of its size: indent, first-line-indent and end-indent.
data Indents = Indents {inS :: Integer, inF :: Integer, inE :: Integer}
  deriving stock (Eq, Show)

-- | The keys of the indents, in the zw of the style.
indentKeys :: Indents -> BS.ByteString
indentKeys (Indents s f e) = BC.pack (concat ["indent = \"", show s, "zw\"\nfirst-line-indent = \"", show f, "zw\"\nend-indent = \"", show e, "zw\"\n"])

{- | Every combination of small indents around the boundary of an inner
width of @n@ characters and a little more, without a negative start: no
indent, and indents of the last characters.
-}
indentsNear :: Integer -> [Indents]
indentsNear n = [Indents s f e | s <- nub (0 : [max 0 (n - 2) .. n]), f <- [-1, 0, 1], s + f >= 0, e <- [0, 1]]

{- | Whether the indents leave no character (docs/adr/0389): the inner
width @w@ holds a character of the size @z@, and the narrowest line @m@,
the inner width less the indent, a positive first-line indent and the end
indent, does not.
-}
leavesNone :: Sp -> Sp -> Indents -> Bool
leavesNone w z (Indents s f e) = w >= z && w - fromInteger (s + max 0 f + e) * z < z

-- | The text of a line of a part.
partText :: PartLine -> T.Text
partText l = T.concat [bcText c | Box _ c <- lineItems (ptLine l)]

-- | An SVG of 300 by 100 with an unpainted frame.
wideSvg :: [(FilePath, BS.ByteString)]
wideSvg = [("images/wide.svg", TE.encodeUtf8 "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"300\" height=\"100\"><rect width=\"300\" height=\"100\" fill=\"none\"/></svg>")]

{- | horizontalStyle with the numbers of figures, tables and code blocks
without the chapter: the test sources have no chapter heading.
-}
numbered :: BS.ByteString
numbered = horizontalStyle <> "\n[figures]\nnumber = \"F{n}\"\n\n[tables]\nnumber = \"T{n}\"\n\n[code]\nnumber = \"L{n}\"\n"

-- | numbered with another number of characters and of lines.
gridOf :: Int -> Int -> BS.ByteString
gridOf chars lns = replaceIn "lines = 30" ("lines = " <> T.pack (show lns)) (replaceIn "characters = 12" ("characters = " <> T.pack (show chars)) numbered)

-- | A style with the paragraph style caption of a size in pt and keys.
withCaption :: BS.ByteString -> Integer -> BS.ByteString -> BS.ByteString
withCaption base size keys = base <> "\n[paragraph-styles.caption]\nsize = \"" <> BC.pack (show size) <> "pt\"\n" <> keys

{- | The diagnostics of the layout of a one-chapter project: those that
stop it, or its notices and warnings.
-}
layoutDiagnostics :: BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO [Diagnostic]
layoutDiagnostics style source files = do
  r <- withMiniInput fakeProvider miniManifest style source files layoutPdf
  case r of
    Left ds -> assertFailure ("not laid out: " <> show (map diagCode ds))
    Right (Left ds) -> pure ds
    Right (Right pl) -> pure (plNotices pl)

{- | A kind of caption: its name, its style for a setting and the keys of
caption, its source for the setting, the settings, the sizes of the
caption in pt, and its lines in a layout.
-}
data Kind = Kind
  { kName :: String,
    kStyle :: Int -> BS.ByteString,
    kSource :: Int -> T.Text,
    kSettings :: [Int],
    kSizes :: [Integer],
    kLines :: PdfLayout -> [PartLine]
  }

figureLines, tableLines, codeLines :: PdfLayout -> [PartLine]
figureLines pl = concatMap pfCaption (Map.elems (plFigures pl))
tableLines pl = concatMap ccLines (Map.elems (plTableCaptions pl))
codeLines pl = concat (take 1 [ciCaption ci | ci <- Map.elems (plCodes pl), not (null (ciCaption ci))])

{- | The six kinds of captions of I1: the settings are the characters of a
line, the width in pt of a wrapped figure or the lines of a page. The size
of caption is at most that of the grid, 10pt (G03011), so only a wrapped
figure is narrower than a character.
-}
kinds :: [Kind]
kinds =
  [ Kind "a figure" (`gridOf` 30) (const "@figure images/wide.svg alt=\"t\"\n  図\n") [8, 12] [10, 7] figureLines,
    Kind "a wrapped figure" (const (gridOf 24 30)) wrappedSource [6, 10, 24] [10, 7] figureLines,
    Kind "a figure turned onto a page" (gridOf 12) (const "@figure images/wide.svg alt=\"t\" rotate=true\n  図\n") [8, 12] [10, 7] figureLines,
    Kind "a table" (`gridOf` 30) (const "@caption 表\n| a | b |\n|---|---|\n| 1 | 2 |\n") [8, 12] [10, 7] tableLines,
    Kind "a code block" (`gridOf` 30) (const "@caption 例\n```\na\n```\n") [10, 12] [10, 7] codeLines,
    Kind "a code block in a list" (`gridOf` 30) (const "- 項目\n\n  @caption 例\n  ```\n  a\n  ```\n") [12, 16] [10, 7] codeLines
  ]

-- | A figure wrapped beside a paragraph, of a width in pt.
wrappedSource :: Int -> T.Text
wrappedSource w = "@figure images/wide.svg alt=\"t\" wrap=start width=" <> T.pack (show w) <> "pt\n  図\n\n本文。\n"

-- | The inner width of the caption of a kind for a setting: the width of its first line, without indents.
innerWidth :: Kind -> Int -> IO Sp
innerWidth k setting = do
  (_, pl) <- layoutOk (withCaption (kStyle k setting) 10 "") (kSource k setting) wideSvg
  case kLines k pl of
    l : _ -> pure (ptIndent l + lineTarget (ptLine l))
    [] -> assertFailure (kName k <> ": no caption")

-- | The number of G07127 of a source in a style.
captionWarnings :: BS.ByteString -> T.Text -> IO Int
captionWarnings style source = length . diagnosticsOf "G07127" <$> layoutDiagnostics style source wideSvg

-- | A figure of a source with a caption of 10pt in the keys, the page of 12 characters (120pt).
figure120 :: BS.ByteString -> T.Text -> IO Int
figure120 keys = captionWarnings (withCaption numbered 10 keys)

-- | The sidenote column of a width in zw of the grid, sidenote of a size in pt and keys.
sidenoteColumn :: BS.ByteString -> BS.ByteString -> Integer -> BS.ByteString -> BS.ByteString
sidenoteColumn base width size keys =
  base <> "\n[paragraph-styles.sidenote]\nsize = \"" <> BC.pack (show size) <> "pt\"\n" <> keys <> "\n[sidenotes]\nwidth = \"" <> width <> "zw\"\ngap = \"1zw\"\n"

-- | What a build of a project of chapters left: its diagnostics, its JSON and whether it wrote a PDF.
data Outcome = Outcome {oDiagnostics :: [Diagnostic], oJson :: T.Text, oPdf :: Bool}

-- | Builds (or checks) a project of chapters to PDF in a profile.
buildChapters :: Profile -> Bool -> BS.ByteString -> [(FilePath, T.Text)] -> IO Outcome
buildChapters prof checkOnly style chapters = withSystemTempDirectory "golem-0389" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["pdf"], tmChapters = map (T.pack . fst) chapters}))
  BS.writeFile (tmp </> "style.toml") (withBodyFont style)
  writeTexts tmp chapters
  writeFiles tmp (bodyFontFiles style <> wideSvg)
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optProfile = prof, optCheckOnly = checkOnly}
  dir <- doesDirectoryExist (tmp </> "build/pdf")
  pdfs <- if dir then filter (".pdf" `isSuffixOf`) <$> listDirectory (tmp </> "build/pdf") else pure []
  pure (Outcome (brDiagnostics r) (renderJson (brSources r) (brDiagnostics r)) (not (null pdfs)))

-- | Whether the JSON has a diagnostic of the code in the severity.
jsonHas :: T.Text -> T.Text -> T.Text -> Bool
jsonHas json code severity = ("{\"code\":\"" <> code <> "\",\"severity\":\"" <> severity <> "\"") `T.isInfixOf` json

-- | A table whose caption indents leave no character: 2zw of 10pt on a line of 12 characters with 10zw of indent.
narrowCaption :: BS.ByteString
narrowCaption = "\n[paragraph-styles.caption]\nsize = \"10pt\"\nindent = \"6zw\"\nend-indent = \"6zw\"\n"

-- | A sidenote style whose indents leave no character on its column of 6zw.
narrowSidenote :: BS.ByteString
narrowSidenote = sidenoteColumn numbered "6" 10 "indent = \"3zw\"\nend-indent = \"3zw\"\n"

-- | A table with a caption and a short sidenote, which reach neither G07038 nor G07033.
tableAndSidenote :: T.Text
tableAndSidenote = "本文[sidenote: 注]。\n\n@caption 表\n| a | b |\n|---|---|\n| 1 | 2 |\n"

-- | The G07 codes of diagnostics, as a set.
g07 :: [Diagnostic] -> Set.Set T.Text
g07 ds = Set.fromList [c | DiagnosticCode c <- map diagCode ds, "G07" `T.isPrefixOf` c]

-- | The lines of each part of a layout, for the golden of I7.
partsDump :: PdfLayout -> T.Text
partsDump pl =
  T.unlines
    ( concat
        [ name : [T.pack (show (ptRow l, unSp (ptIndent l), unSp (lineTarget (ptLine l)))) <> " " <> partText l | l <- ls]
        | (name, ls) <-
            [ ("figure", figureLines pl),
              ("table", tableLines pl),
              ("code", codeLines pl),
              ("sidenote", concat [psLines ps | pss <- Map.elems (plSidenotes pl), ps <- pss])
            ]
        ]
    )

-- | A figure, a table and a code block, each with a caption, and a sidenote, of several characters.
partsSource :: T.Text
partsSource =
  "本文[sidenote: 注記の本文]。\n\n@figure images/wide.svg alt=\"t\"\n  図版の題\n\n@caption 表の題\n| a | b |\n|---|---|\n| 1 | 2 |\n\n@caption 例の題\n```\na\n```\n"

{- | Lays out a project of chapters with the fake fonts, as withMiniInput
lays out one chapter: the first is a.gm.
-}
layoutChapters :: BS.ByteString -> [(FilePath, T.Text)] -> IO PdfLayout
layoutChapters style chapters = case chapters of
  (_, first) : rest -> do
    let manifest = TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["pdf"], tmChapters = map (T.pack . fst) chapters})
    r <- withMiniInput fakeProvider manifest style first (wideSvg <> [(p, TE.encodeUtf8 t) | (p, t) <- rest]) layoutPdf
    either (assertFailure . show . map diagCode) pure (join r)
  [] -> assertFailure "no chapter"

captionSidenoteIndentTests :: [TestTree]
captionSidenoteIndentTests =
  [ testCase "ADR 0389 I1: inv1_caption_indent_property: G07127 is on a caption exactly when w >= z and m < z, for each kind of caption" $
      forM_ kinds $ \k -> forM_ (kSettings k) $ \setting -> do
        w <- innerWidth k setting
        forM_ (kSizes k) $ \size -> forM_ (indentsNear (unSp w `div` unSp (fromInteger size * pt))) $ \i -> do
          n <- captionWarnings (withCaption (kStyle k setting) size (indentKeys i)) (kSource k setting)
          let z = fromInteger size * pt
          (kName k, setting, size, i, n) @?= (kName k, setting, size, i, if leavesNone w z i then 1 else 0),
    testCase "ADR 0389 I1: inv1_caption_indent_case_1: no indent, w >= z: none" $
      figure120 "" "@figure images/wide.svg alt=\"t\"\n  図\n" >>= (@?= 0),
    testCase "ADR 0389 I1: inv1_caption_indent_case_2: no indent, w < z: none" $
      -- a wrapped figure of 6pt and a caption of 10pt
      captionWarnings (withCaption (gridOf 24 30) 10 "") (wrappedSource 6) >>= (@?= 0),
    testCase "ADR 0389 I1: inv1_caption_indent_case_3: an indent, w < z: none" $
      captionWarnings (withCaption (gridOf 24 30) 10 "indent = \"1zw\"\n") (wrappedSource 6) >>= (@?= 0),
    testCase "ADR 0389 I1: inv1_caption_indent_case_4: m exactly z: none" $
      figure120 "indent = \"6zw\"\nend-indent = \"5zw\"\n" "@figure images/wide.svg alt=\"t\"\n  図\n" >>= (@?= 0),
    testCase "ADR 0389 I1: inv1_caption_indent_case_5: m 1sp less than z: G07127" $
      -- 110pt and 1sp (1/65536 pt) of indent leave 10pt less 1sp of 120pt
      figure120 "indent = \"110.0000152587890625pt\"\n" "@figure images/wide.svg alt=\"t\"\n  図\n" >>= (@?= 1),
    testCase "ADR 0389 I1: inv1_caption_indent_case_6: m 0: G07127" $
      figure120 "indent = \"6zw\"\nend-indent = \"6zw\"\n" "@figure images/wide.svg alt=\"t\"\n  図\n" >>= (@?= 1),
    testCase "ADR 0389 I1: inv1_caption_indent_case_7: m negative: G07127" $
      figure120 "indent = \"7zw\"\nend-indent = \"6zw\"\n" "@figure images/wide.svg alt=\"t\"\n  図\n" >>= (@?= 1),
    testCase "ADR 0389 I1: inv1_caption_indent_case_8: a negative first-line indent with s + e = w - z: none" $
      figure120 "indent = \"6zw\"\nfirst-line-indent = \"-2zw\"\nend-indent = \"5zw\"\n" "@figure images/wide.svg alt=\"t\"\n  図\n" >>= (@?= 0),
    testCase "ADR 0389 I1: inv1_caption_indent_case_9: a caption of its number alone with m < z: G07127" $
      figure120 "indent = \"6zw\"\nend-indent = \"6zw\"\n" "@figure images/wide.svg alt=\"t\"\n" >>= (@?= 1),
    testCase "ADR 0389 I1: G07127 is at the block of the caption, once for each caption" $ do
      -- the block of a table starts at its rows and that of a code block at its fence, after @caption
      let src = "前。\n\n@figure images/wide.svg alt=\"t\"\n  図\n\n@caption 表\n| a | b |\n|---|---|\n| 1 | 2 |\n\n@caption 例\n```\na\n```\n"
      ds <- diagnosticsOf "G07127" <$> layoutDiagnostics (withCaption numbered 10 "indent = \"6zw\"\nend-indent = \"6zw\"\n") src wideSvg
      map (spanStart . diagSpan) ds @?= map (\p -> BS.length (TE.encodeUtf8 (fst (T.breakOn p src)))) ["@figure", "| a |", "```"]
      map diagMessage ds @?= replicate 3 "キャプションの字下げが行の幅を使い切ります。段落スタイル caption の字下げを小さくしてください",
    testCase "ADR 0389 I2: inv2_sidenote_indent_property: G07128 exactly when w >= z and m < z for the sidenote column, in golem check" $
      -- widths in zw of the grid, 10pt; the size of sidenote is at most that of the grid (G03011)
      forM_ [("0.5", 5 * pt), ("1", 10 * pt), ("2", 20 * pt), ("4", 40 * pt)] $ \(width, w) -> forM_ [10, 7] $ \size -> do
        let z = fromInteger size * pt
        forM_ (indentsNear (unSp w `div` unSp z)) $ \i -> do
          o <- buildChapters Dev True (sidenoteColumn numbered width size (indentKeys i)) [("a.gm", "本文。\n")]
          (width, size, i, length (diagnosticsOf "G07128" (oDiagnostics o))) @?= (width, size, i, if leavesNone w z i then 1 else 0),
    testCase "ADR 0389 I2: the column of [sidenotes] is its width in zw of the grid" $ do
      (geom, _) <- layoutOk (sidenoteColumn numbered "4" 10 "") "本文。\n" []
      fmap (rectW . fst) (pgSidenotes geom) @?= Just (40 * pt),
    testCase "ADR 0389 I2: inv2_sidenote_indent_case_1: the style of a file is checked too" $ do
      o <- buildChapters Dev True (sidenoteColumn numbered "6" 10 "") [("a.gm", "@style-def paragraph sidenote indent=3zw end-indent=3zw\n\n本文。\n")]
      length (diagnosticsOf "G07128" (oDiagnostics o)) @?= 1,
    testCase "ADR 0389 I2: inv2_sidenote_indent_case_2: without [sidenotes], no G07128" $ do
      o <- buildChapters Dev True (numbered <> "\n[paragraph-styles.sidenote]\nsize = \"10pt\"\nindent = \"30zw\"\n") [("a.gm", "本文。\n")]
      diagnosticsOf "G07128" (oDiagnostics o) @?= [],
    testCase "ADR 0389 I2: inv2_sidenote_indent_case_3: [sidenotes] on a vertical page, no G07128" $ do
      o <- buildChapters Dev True (sidenoteColumn pdfStyle "6" 8 "indent = \"3zw\"\nend-indent = \"3zw\"\n") [("a.gm", "本文。\n")]
      diagnosticsOf "G07128" (oDiagnostics o) @?= [],
    testCase "ADR 0389 I2: G07128 is at the top of style.toml, with its message" $ do
      o <- buildChapters Dev False narrowSidenote [("a.gm", "本文。\n")]
      [(spanStart (diagSpan d), spanEnd (diagSpan d), diagMessage d) | d <- diagnosticsOf "G07128" (oDiagnostics o)] @?= [(0, 0, "傍注の字下げが傍注の領域の幅を使い切ります。字下げを小さくするか、[sidenotes] の width を広げてください")]
      assertBool "in the JSON at style.toml" ("\"style.toml\"" `T.isInfixOf` oJson o),
    testCase "ADR 0389 I3: inv3_severity: G07127 and G07128 are warnings in dev and errors in prod" $ do
      dev <- buildChapters Dev False (narrowSidenote <> narrowCaption) [("a.gm", tableAndSidenote)]
      prod <- buildChapters Prod False (narrowSidenote <> narrowCaption) [("a.gm", tableAndSidenote)]
      [(diagCode d, diagSeverity d) | d <- oDiagnostics dev, diagCode d `elem` map DiagnosticCode ["G07127", "G07128"]] @?= [(DiagnosticCode "G07127", Warning), (DiagnosticCode "G07128", Warning)]
      [(diagCode d, diagSeverity d) | d <- oDiagnostics prod, diagCode d `elem` map DiagnosticCode ["G07127", "G07128"]] @?= [(DiagnosticCode "G07127", Error), (DiagnosticCode "G07128", Error)]
      assertBool (T.unpack (oJson dev)) (all (\c -> jsonHas (oJson dev) c "warning") ["G07127", "G07128"])
      assertBool (T.unpack (oJson prod)) (all (\c -> jsonHas (oJson prod) c "error") ["G07127", "G07128"]),
    testCase "ADR 0389 I4: inv4_dev_writes: in dev a build whose only errors would be G07127 and G07128 writes the PDF" $
      forM_ [(sidenoteColumn numbered "6" 10 "" <> narrowCaption, "G07127"), (narrowSidenote, "G07128")] $ \(style, code) -> do
        o <- buildChapters Dev False style [("a.gm", tableAndSidenote)]
        assertBool (T.unpack (oJson o)) (jsonHas (oJson o) code "warning")
        filter isError (oDiagnostics o) @?= []
        assertBool "a PDF in dev" (oPdf o),
    testCase "ADR 0389 I5: inv5_prod_stops: in prod G07127 or G07128 leaves no PDF" $
      forM_ [(sidenoteColumn numbered "6" 10 "" <> narrowCaption, "G07127"), (narrowSidenote, "G07128")] $ \(style, code) -> do
        o <- buildChapters Prod False style [("a.gm", tableAndSidenote)]
        assertBool (T.unpack (oJson o)) (jsonHas (oJson o) code "error")
        assertBool "no PDF in prod" (not (oPdf o)),
    testCase "ADR 0389 I6: inv6_same_g07: prod lays out with G07128 and reports the G07 codes of dev" $ do
      dev <- buildChapters Dev False (narrowSidenote <> narrowCaption) [("a.gm", tableAndSidenote)]
      prod <- buildChapters Prod False (narrowSidenote <> narrowCaption) [("a.gm", tableAndSidenote)]
      assertBool "G07127 and G07128 in dev" (Set.fromList ["G07127", "G07128"] `Set.isSubsetOf` g07 (oDiagnostics dev))
      g07 (oDiagnostics prod) @?= g07 (oDiagnostics dev),
    goldenVsString "ADR 0389 I7: inv7_lines_unchanged: the lines of captions and a sidenote whose indents leave no character" "test/golden/adr-0389-i7.txt" $ do
      (_, pl) <- layoutOk (sidenoteColumn numbered "6" 10 "indent = \"3zw\"\nend-indent = \"3zw\"\n" <> narrowCaption) partsSource wideSvg
      pure (BL.fromStrict (TE.encodeUtf8 (partsDump pl))),
    testCase "ADR 0389 I8: inv8_once: G07128 once for the style of the book and those of two files" $ do
      o <- buildChapters Dev False narrowSidenote [("a.gm", "@style-def paragraph sidenote indent=4zw end-indent=3zw\n\n本文。\n"), ("b.gm", "@style-def paragraph sidenote indent=3zw end-indent=4zw\n\n本文。\n")]
      length (diagnosticsOf "G07128" (oDiagnostics o)) @?= 1,
    testCase "ADR 0389 I9: inv9_check: golem check reports G07128 and not G07127" $ do
      o <- buildChapters Dev True (narrowSidenote <> narrowCaption) [("a.gm", tableAndSidenote)]
      assertBool (T.unpack (oJson o)) (jsonHas (oJson o) "G07128" "warning")
      assertBool (T.unpack (oJson o)) (not ("\"G07127\"" `T.isInfixOf` oJson o))
      prod <- buildChapters Prod True (narrowSidenote <> narrowCaption) [("a.gm", tableAndSidenote)]
      assertBool (T.unpack (oJson prod)) (jsonHas (oJson prod) "G07128" "error"),
    testCase "ADR 0389 I11: inv11_file_caption: the captions of a file take the indents of caption of its style" $ do
      let chapter title = "@figure images/wide.svg alt=\"t\"\n  " <> title <> "図\n\n@caption " <> title <> "表\n| a | b |\n|---|---|\n| 1 | 2 |\n\n@caption " <> title <> "例\n```\na\n```\n"
      pl <- layoutChapters (withCaption numbered 10 "") [("a.gm", "@style-def paragraph caption indent=1zw\n\n" <> chapter "甲"), ("b.gm", chapter "乙")]
      let titles = ["甲図", "甲表", "甲例", "乙図", "乙表", "乙例"]
          indents = sort [(t, unSp (ptIndent l)) | l <- figureLines pl <> tableLines pl <> nub (concat [ciCaption ci | ci <- Map.elems (plCodes pl)]), t <- titles, t `T.isInfixOf` partText l]
      indents @?= sort (zip titles (replicate 3 (unSp (10 * pt)) <> replicate 3 0))
  ]
