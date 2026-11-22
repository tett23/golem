module ParagraphPitchSpec (paragraphPitchTests) where

import Data.ByteString qualified as BS
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver (BuildOptions (..))
import Golem.Layout.KnuthPlass (Line (..))
import Golem.Layout.Paginate (PageOutAt (..), Slotted (..))
import Golem.Length (Sp (..))
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..), FileId (..), isError, spanFile)
import Golem.Typeset (PdfLayout (..), SetLine (..))
import Support hiding (pt)
import Test.Tasty
import Test.Tasty.HUnit

freeStyle :: BS.ByteString
freeStyle = TE.encodeUtf8 (T.replace "[page.grid]" "[page.grid]\nalignment = \"free\"" (TE.decodeUtf8 horizontalStyle))

pt :: Integer -> Sp
pt n = Sp (65536 * n)

paragraphPitchTests :: TestTree
paragraphPitchTests =
  testGroup
    "physical paragraph layout"
    [ testCase "root ADR 0397 I3: same-style dialogue uses its own pitch and gap" $ do
        (_, layout) <- layoutOk (freeStyle <> "\n[paragraph-styles.dialogue]\nline-pitch = \"18pt\"\nspace-between = \"6pt\"\n") "@style dialogue\nあ\n\n@style dialogue\nい\n" []
        map (map fst . poSlots) (plPages layout) @?= [[0, pt 24]],
      testCase "root ADR 0397 I3: mixed styles compare resolved dimensional spacing" $ do
        (_, layout) <- layoutOk (freeStyle <> "\n[paragraph-styles.a]\nline-pitch = \"18pt\"\nspace-after = \"6pt\"\n[paragraph-styles.b]\nline-pitch = \"16pt\"\nspace-before = \"4pt\"\n") "@style a\nあ\n\n@style b\nい\n" []
        map (map fst . poSlots) (plPages layout) @?= [[0, pt 24]],
      testCase "root ADR 0397 I4: explicit verse lines do not acquire paragraph gaps" $ do
        (_, layout) <- layoutOk (freeStyle <> "\n[paragraph-styles.dialogue]\nline-pitch = \"18pt\"\nspace-between = \"6pt\"\nline-breaks = \"keep\"\n") "@style dialogue\nあ\nい\n" []
        map (map fst . poSlots) (plPages layout) @?= [[0, pt 18]],
      testCase "root ADR 0397 A2: file-local pitch resolves like project pitch" $ do
        (_, local) <- layoutOk freeStyle "@style-def paragraph dialogue line-pitch=18pt space-between=6pt\n\n@style dialogue\nあ\n\n@style dialogue\nい\n" []
        map (map fst . poSlots) (plPages local) @?= [[0, pt 24]],
      testCase "root ADR 0397 I7: Emet styled output has the same physical slots" $ do
        let style = freeStyle <> "\n[paragraph-styles.dialogue]\nline-pitch = \"18pt\"\nspace-between = \"6pt\"\n"
            library = "pub block dialogue :: Blocks -> Blocks\ndialogue body = List.map styled body\nstyled :: Block.Block -> Block.Block\nstyled (Block.Paragraph _ xs) = Block.Paragraph (Just \"dialogue\") xs\nstyled b = b\n"
        (_, direct) <- layoutOk style "@style dialogue\nあ\n\n@style dialogue\nい\n" []
        (_, emitted) <- layoutOk style "@import script.emet as script\n\n@script.dialogue\n  あ\n\n@script.dialogue\n  い\n" [("script.emet", library)]
        map poSlots (plPages emitted) @?= map poSlots (plPages direct),
      testCase "root ADR 0397 I13: oversized paragraph fails at its source span" $ do
        let style = freeStyle <> "\n[paragraph-styles.dialogue]\nline-pitch = \"1000pt\"\n"
        assertPdfFailure "G07129" style "@style dialogue\nあ\n" []
        result <- layoutMini style "@style dialogue\nあ\n" []
        case result of
          Left ds -> do
            map diagCode ds @?= [DiagnosticCode "G07129"]
            map (spanFile . diagSpan) ds @?= [FileId 1]
          Right _ -> assertFailure "oversized line unexpectedly fitted",
      testCase "root ADR 0397 I13: a footnote minimum fails at its reference" $ do
        let style = replaceIn "lines = 30" "lines = 1" freeStyle <> "\n[paragraph-styles.body]\nline-pitch = \"6pt\"\n"
        assertPdfFailure "G07130" style "本文[note k]。\n\n@note k\n  注。\n" []
        result <- layoutMini style "本文[note k]。\n\n@note k\n  注。\n" []
        case result of
          Left ds -> do
            map diagCode ds @?= [DiagnosticCode "G07130"]
            map (spanFile . diagSpan) ds @?= [FileId 1]
          Right _ -> assertFailure "impossible footnote unexpectedly fitted",
      testCase "root ADR 0397 I6: dimensional caption interior spacing is diagnosed at use" $ do
        let style = freeStyle <> "\n[paragraph-styles.caption]\nspace-between = \"2pt\"\n"
        result <- layoutMini style "# 章\n\n@caption 題\n```text\nx\n```\n" []
        case result of
          Left ds -> assertBool (show ds) (DiagnosticCode "G03006" `elem` map diagCode ds)
          Right _ -> assertFailure "dimensional caption spacing unexpectedly accepted",
      testCase "root ADR 0397 I10: a wrapping edge touched by a line box does not shorten it" $ do
        imageFiles <- tinyImage
        let style = replaceIn "line-pitch = \"15pt\"" "line-pitch = \"10pt\"" freeStyle <> "\n[paragraph-styles.body]\nline-pitch = \"15pt\"\n[figures]\nwrap-gap = \"0pt\"\n"
            source = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n\n" <> longPara 12
        (_, layout) <- layoutOk style source imageFiles
        length [sl | sl <- Map.elems (plLines layout), lineTarget (slLine sl) < pt 120] @?= 2,
      testCase "root ADR 0397 I10: a one-sp wrapping intersection shortens the next line" $ do
        imageFiles <- tinyImage
        let style = replaceIn "line-pitch = \"15pt\"" "line-pitch = \"10pt\"" freeStyle <> "\n[paragraph-styles.body]\nline-pitch = \"15pt\"\n[figures]\nwrap-gap = \"0.0000152587890625pt\"\n"
            source = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n\n" <> longPara 12
        (_, layout) <- layoutOk style source imageFiles
        length [sl | sl <- Map.elems (plLines layout), lineTarget (slLine sl) < pt 120] @?= 3,
      testCase "root ADR 0397 I13: a figure needs at least one page-pitch row" $ do
        imageFiles <- tinyImage
        let style = replaceIn "lines = 30" "lines = 1" freeStyle
            source = "@nonumber\n@figure images/tiny.jpg alt=\"t\" width=2zw\n"
        assertPdfFailure "G07131" style source imageFiles
        result <- layoutMini style source imageFiles
        case result of
          Left ds -> do
            map diagCode ds @?= [DiagnosticCode "G07131"]
            map (spanFile . diagSpan) ds @?= [FileId 1]
          Right _ -> assertFailure "figure unexpectedly fitted without a page-pitch row",
      testCase "root ADR 0397 I13: a five-row heading does not fit a 4.5-row type area" $ do
        let style = replaceIn "line-pitch = \"15pt\"" "line-pitch = \"20pt\"" (replaceIn "lines = 30" "lines = 5" freeStyle) <> "\n[headings.1]\nsize = \"1zw\"\nlines = 5\n"
        result <- layoutMini style "# 題\n" []
        case result of
          Left ds -> assertBool (show ds) (DiagnosticCode "G07024" `elem` map diagCode ds)
          Right _ -> assertFailure "heading span exceeded the physical type area",
      testGroup
        "screenplay directions"
        [ testCase ("root ADR 0397 A1, A4: " <> mode <> " screenplay keeps every line across pages") $ do
            let style =
                  replaceIn "writing-mode = \"horizontal\"" ("writing-mode = \"" <> T.pack mode <> "\"") (replaceIn "lines = 30" "lines = 5" freeStyle)
                    <> "\n[paragraph-styles.dialogue]\nline-pitch = \"18pt\"\nspace-between = \"6pt\"\nkeep-first-lines = 1\nkeep-last-lines = 1\n[paragraph-styles.stage]\nline-pitch = \"12pt\"\nindent = \"2zw\"\n"
                source = T.concat (replicate 6 ("@style dialogue\n" <> T.replicate 25 "あ" <> "\n\n@style stage\nい\n\n"))
            (_, layout) <- layoutOk style source []
            let pages = plPages layout
                ids = [ident | page <- pages, (_, SLine ident) <- poSlots page]
            assertBool "multiple pages" (length pages > 1)
            sort ids @?= Map.keys (plLines layout)
            assertBool
              "line boxes stay within the physical type area"
              (and [start >= 0 && start + Map.findWithDefault (pt 15) ident (plLinePitches layout) <= poLines page | page <- pages, (start, SLine ident) <- poSlots page])
            let changed = replaceIn "line-pitch = \"18pt\"" "line-pitch = \"14pt\"" style
            (_, other) <- layoutOk changed source []
            assertBool "project pitch changes placement" (map poSlots pages /= map poSlots (plPages other))
            map (lineTarget . slLine) (Map.elems (plLines layout)) @?= map (lineTarget . slLine) (Map.elems (plLines other))
        | mode <- ["horizontal", "vertical"]
        ],
      testGroup
        "physical PDF coordinates"
        [ testCase ("root ADR 0397 A5: " <> mode <> " PDF uses physical centres on odd and even pages") $ do
            let style =
                  replaceIn "writing-mode = \"horizontal\"" ("writing-mode = \"" <> T.pack mode <> "\"") (replaceIn "lines = 30" "lines = 10" freeStyle)
                    <> "\n[paragraph-styles.a]\nline-pitch = \"18pt\"\nspace-after = \"6pt\"\n[paragraph-styles.b]\nline-pitch = \"16pt\"\nspace-before = \"4pt\"\n"
                part = "@style a\nあ\n\n@style b\nい\n\n"
            pdf <- miniPdf fakeProvider False style (part <> "@page-break\n\n" <> part) []
            content <- BS.concat <$> inflateAll pdf
            let glyphs = drawnGlyphs content
                coordinate = ptToRational . if mode == "vertical" then dX else dY
                positions ch = [coordinate d | d <- glyphs, dGlyph d == fromEnum ch]
            length (positions 'あ') @?= 2
            length (positions 'い') @?= 2
            zipWith (-) (positions 'あ') (positions 'い') @?= [23, 23]
        | mode <- ["horizontal", "vertical"]
        ],
      testGroup
        "mixed physical layout"
        [ testCase ("root ADR 0397 A5, I14: " <> mode <> (if columns then " columns" else " wrapping") <> ", notes, rules and boxes are deterministic") $ do
            images <- tinyImage
            let style =
                  replaceIn "writing-mode = \"horizontal\"" ("writing-mode = \"" <> T.pack mode <> "\"") (replaceIn "lines = 30" "lines = 10" (if columns then replaceIn "columns = 1" "columns = 2\ncolumn-gap = \"2zw\"" freeStyle else freeStyle))
                    <> "\n[color.swatches]\npale = { cmyk = [0,0,0,6] }\n[paragraph-styles.body]\nline-pitch = \"18pt\"\nspace-between = \"3pt\"\n[paragraph-styles.ruled]\nline-pitch = \"14pt\"\nrule-before = { weight = \"1pt\", space-after = \"2pt\" }\n[paragraph-styles.boxed]\nline-pitch = \"16pt\"\nbackground = \"pale\"\npadding = \"4pt\"\n"
                source =
                  "@label scene\n@style ruled\n本文[note n]です。\n\n@nonumber\n@figure images/tiny.jpg alt=\"t\""
                    <> (if columns then "" else " wrap=start")
                    <> " width=2zw\n\n"
                    <> longPara 8
                    <> "\n\n@no-page-break\n\n@style boxed\n"
                    <> T.replicate 36 "あ"
                    <> "\n\n@page-break\n\n参照先は[ref-page scene]ページ。\n\n@note n\n  注の本文。\n"
                files = [("manifest.toml", miniManifest), ("style.toml", withBodyFont style), ("a.gm", TE.encodeUtf8 source)] <> fakeFontFiles <> images
            parallel <- buildNotified files (\o -> o {optParallel = True})
            sequential <- buildNotified files (\o -> o {optParallel = False})
            filter isError (nDiagnostics parallel) @?= []
            nDiagnostics parallel @?= nDiagnostics sequential
            nOutputs parallel @?= nOutputs sequential
            assertBool "PDF was written" (not (null (nOutputs parallel)))
        | mode <- ["horizontal", "vertical"],
          columns <- [False, True]
        ],
      testCase "root ADR 0397 I14: free PDF is identical in parallel and sequential builds" $ do
        let style = freeStyle <> "\n[paragraph-styles.body]\nline-pitch = \"18pt\"\nspace-between = \"6pt\"\n"
        parallel <- buildMini fakeProvider True style "あ\nい\nう\n" []
        sequential <- buildMini fakeProvider False style "あ\nい\nう\n" []
        parallel @?= sequential
        assertBool "PDF was not produced" (case parallel of ([], Just _) -> True; _ -> False)
    ]

-- | Layout failures must also stop the driver's output phase.
assertPdfFailure :: T.Text -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> Assertion
assertPdfFailure code style source files = do
  (errors, pdf) <- buildMini fakeProvider False style source files
  errors @?= [DiagnosticCode code]
  pdf @?= Nothing
