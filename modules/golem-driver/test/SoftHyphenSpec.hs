{- | Soft hyphens and the ranges that do not break in the PDF (docs/adr ADR
0272): the hyphen at a line broken at a soft hyphen, no glyph and no
ToUnicode entry of U+00AD, the starts of the pages in the source with its
soft hyphens, G07122 for a line past the measure at a range, and G07123
and G07124 for the soft hyphens that are not breaks.
-}
module SoftHyphenSpec (softHyphenTests) where

import Data.ByteString qualified as BS
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Syntax
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | Builds the one-chapter project to PDF with the fake fonts.
built :: BS.ByteString -> T.Text -> IO BuildResult
built style source = withSystemTempDirectory "golem-shy" $ \tmp -> do
  writeProject tmp miniManifest style source fakeFontFiles
  build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}

-- | The diagnostics of codes as code, file, start and length.
sitesOf :: [T.Text] -> BuildResult -> [(T.Text, FilePath, Int, Int)]
sitesOf cs r =
  [ (c, maybe "" siPath (Map.lookup (spanFile sp) (brSources r)), spanStart sp, spanLength sp)
  | d <- brDiagnostics r,
    let DiagnosticCode c = diagCode d
        sp = diagSpan d,
    c `elem` cs
  ]

byteLength :: T.Text -> Int
byteLength = BS.length . TE.encodeUtf8

-- | A word of 40 letters, a soft hyphen, and another of 40: wider than a line of 30 characters, which breaks at the soft hyphen.
longWord :: T.Text -> T.Text
longWord shy = T.replicate 4 "abcdefghij" <> shy <> T.replicate 4 "klmnopqrst"

softHyphenTests :: TestTree
softHyphenTests =
  testGroup
    "soft hyphens and the ranges that do not break in the PDF (docs/adr ADR 0272)"
    [ testCase "H1 to H3 of docs/adr ADR 0285: [italic: hyphenationhyphenation], U+00AD, hyphenationhyphenation in [lang en] in lines of 12 em breaks at the soft hyphen, a hyphen drawn, not where the patterns break, no notice" $ do
        let source = "[lang en: [italic: hyphenationhyphenation]\xAD\&hyphenationhyphenation]\n"
        (_, pl) <- layoutOk horizontalStyle source []
        lineTexts pl @?= ["hyphenationhyphenation", "hyphenationhyphenation"]
        pdf <- miniPdf fakeProvider False horizontalStyle source []
        contents <- pageContents pdf
        assertBool "a hyphen" (fromEnum '-' `elem` map dGlyph (drawnGlyphs (BS.concat contents)))
        r <- built horizontalStyle source
        sitesOf ["G07123", "G07124"] r @?= [],
      testCase "a line broken at a soft hyphen ends with a hyphen drawn; no glyph and no ToUnicode entry of U+00AD" $ do
        pdf <- miniPdf fakeProvider False (horizontal30 "") (longWord "\xAD" <> "\n") []
        contents <- pageContents pdf
        let glyphs = map dGlyph (drawnGlyphs (BS.concat contents))
        assertBool "a hyphen" (fromEnum '-' `elem` glyphs)
        assertBool "no soft hyphen" (0xAD `notElem` glyphs)
        streams <- inflateAll pdf
        assertBool "no ToUnicode entry of U+00AD" (not (any (\st -> "beginbfchar" `BS.isInfixOf` st && "<00ad>" `BS.isInfixOf` BS.map lower st) streams)),
      testCase "[shy] breaks as U+00AD does" $ do
        (_, a) <- layoutOk (horizontal30 "") (longWord "[shy]" <> "\n") []
        (_, b) <- layoutOk (horizontal30 "") (longWord "\xAD" <> "\n") []
        lineTexts a @?= lineTexts b
        lineTexts a @?= [T.replicate 4 "abcdefghij", T.replicate 4 "klmnopqrst"],
      testCase "a word not broken at its soft hyphen has none in its text" $ do
        (_, pl) <- layoutOk (horizontal30 "") "ta\xAD\&ble\n" []
        lineTexts pl @?= ["table"],
      testCase "the starts of the pages are where their first characters are in the source, its soft hyphens counted (docs/adr ADR 0195)" $
        withSystemTempDirectory "golem-shy-pages" $ \tmp -> do
          let style = replaceIn "lines = 30" "lines = 1" (horizontal30 "")
              source = longWord "\xAD" <> " " <> longWord "[shy]" <> "\n"
          writeProject tmp miniManifest style source fakeFontFiles
          r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
          assertEqual "no errors" [] [diagMessage d | d <- brDiagnostics r, isError d]
          json <- TE.decodeUtf8 <$> BS.readFile (tmp </> "build/pdf/pages.json")
          -- the four lines start at a, k, a and k: their characters in UTF-16 code units, one for U+00AD and five for [shy]
          [T.takeWhile (/= '}') (snd (T.breakOn "\"character\":" o)) | o <- T.splitOn "},{" json]
            @?= ["\"character\":0", "\"character\":41", "\"character\":82", "\"character\":127"],
      testCase "I9: a range past the measure is one G07122, code past it one G07105, a line each" $ do
        let source = "[code: " <> T.replicate 40 "a" <> "]\n\n[style no-break: " <> T.replicate 40 "漢" <> "]\n"
            rangeStart = byteLength ("[code: " <> T.replicate 40 "a" <> "]\n\n[style no-break: ")
        r <- built horizontalStyle source
        [c | (c, _, _, _) <- sitesOf ["G07105", "G07122"] r] @?= ["G07105", "G07122"]
        -- at the first character past the measure: one of the range
        [s >= rangeStart && s < rangeStart + byteLength (T.replicate 40 "漢") | (c, _, s, _) <- sitesOf ["G07122"] r, c == "G07122"] @?= [True]
        [diagSeverity d | d <- diagnosticsOf "G07122" (brDiagnostics r)] @?= [Warning]
        assertBool "the PDF is written" (any (".pdf" `isSuffixOf`) (brWritten r)),
      testCase "I9: a range that fits the line gives no diagnostic" $ do
        r <- built horizontalStyle "あいう[style no-break: 漢漢漢]えお\n"
        sitesOf ["G07105", "G07122"] r @?= [],
      testCase "G07123 and G07124: at each soft hyphen that is not a break, [shy] where it is written so; none at the head of a word" $ do
        let source = "a\xAD.と[shy]い[code: x[shy]y]\xADtable\n"
        r <- built horizontalStyle source
        sitesOf ["G07123", "G07124"] r
          @?= [ ("G07123", "a.gm", 1, 2),
                ("G07123", "a.gm", byteLength "a\xAD.と", 5),
                ("G07124", "a.gm", byteLength "a\xAD.と[shy]い[code: x", 5)
              ]
        [diagSeverity d | d <- brDiagnostics r, diagCode d `elem` map DiagnosticCode ["G07123", "G07124"]] @?= [Notice, Notice, Notice],
      testCase "C6 (docs/adr/0277): the label of a page and its value past the measure are G07105 alone; in a range, G07122 alone" $ do
        -- a value of 21 digits fits a line of 12 characters of the fake fonts, the label and the value together do not:
        -- the line was broken after p. before the ADR, without a line past the measure
        let mark = "[cite a page=\"" <> T.replicate 21 "1" <> "\"]"
            builtCiting source = withSystemTempDirectory "golem-cite-over" $ \tmp -> do
              writeProject tmp ("bibliography = [\"refs.json\"]\n" <> miniManifest) horizontalStyle source (("refs.json", "[{\"id\": \"a\", \"title\": \"A\"}]") : fakeFontFiles)
              build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
            -- the diagnostics of the codes in the mark, which starts at the byte given
            inMark start r = [c | (c, _, s, _) <- sitesOf ["G07105", "G07122"] r, s >= start, s < start + byteLength mark]
        plain' <- builtCiting ("あ" <> mark <> "\n\n@bibliography\n")
        inMark (byteLength "あ") plain' @?= ["G07105"]
        kept <- builtCiting ("あ[style no-break: " <> mark <> "]\n\n@bibliography\n")
        inMark (byteLength "あ[style no-break: ") kept @?= ["G07122"],
      testCase "no G07123 nor G07124 in an HTML build" $
        withSystemTempDirectory "golem-shy-html" $ \tmp -> do
          writeProject tmp (miniManifest <> "\n[targets.html]\n") horizontalStyle "a\xAD.\n" fakeFontFiles
          r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
          sitesOf ["G07123", "G07124"] r @?= []
    ]
  where
    lower w = if w >= 65 && w <= 90 then w + 32 else w
