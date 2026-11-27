{- | The paragraphs of fit-characters in the PDF (root ADR 0466): which
paragraphs are fitted, where their lines are put by align, G07144, and
the CSS of HTML.
-}
module FitCharactersSpec (fitCharactersTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Paginate (HeadingBlock (..))
import Golem.Length (Sp (..))
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), SetLine (..), layoutPdf)
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

fs :: Sp
fs = 655360

-- | horizontalStyle (12 characters of 10pt a line) with the paragraph style title of fit-characters = n and more keys.
fitStyle :: Int -> BS.ByteString -> BS.ByteString
fitStyle n extra = horizontalStyle <> "\n[paragraph-styles.title]\nfirst-line-indent = \"0zw\"\nfit-characters = " <> TE.encodeUtf8 (T.pack (show n)) <> "\n" <> extra

-- | The style of 'fitStyle' without fit-characters.
plainStyle :: BS.ByteString -> BS.ByteString
plainStyle extra = horizontalStyle <> "\n[paragraph-styles.title]\nfirst-line-indent = \"0zw\"\n" <> extra

-- | The lines of a layout, in order.
linesOf :: PdfLayout -> [SetLine]
linesOf = Map.elems . plLines

-- | The length of a set line: its boxes and its glue at their widths.
lengthOf :: SetLine -> Sp
lengthOf sl = sum [w | Box w _ <- lineItems (slLine sl)] + sum [w | Glue {itemWidth = w} <- lineItems (slLine sl)]

-- | The texts of the boxes of a line that show characters.
textsOf :: SetLine -> [T.Text]
textsOf sl = [bcText c | Box _ c <- lineItems (slLine sl), not (T.null (bcText c))]

-- | The spaces between the boxes of characters of a line.
gapsOf :: SetLine -> [Sp]
gapsOf sl = go (dropWhile (not . isText) (lineItems (slLine sl)))
  where
    isText = \case
      Box _ c -> not (T.null (bcText c))
      _ -> False
    go = \case
      _ : rest ->
        let (between, more) = break isText rest
         in if null more then [] else sum [w | Box w _ <- between] + sum [w | Glue {itemWidth = w} <- between] : go more
      [] -> []

-- | The byte offset of the first @needle@ in @src@.
offsetIn :: T.Text -> T.Text -> Int
offsetIn src needle = BS.length (TE.encodeUtf8 (fst (T.breakOn needle src)))

-- | Each line as it is set: where it starts, its items.
setLines :: PdfLayout -> [(Sp, [Item])]
setLines pl = [(slIndent sl, lineItems (slLine sl)) | sl <- linesOf pl]

-- | The diagnostics of a laid out source, the warnings with them.
layoutDiagnostics :: BS.ByteString -> T.Text -> IO [Diagnostic]
layoutDiagnostics style source = do
  r <- withMiniInput fakeProvider miniManifest style source [] layoutPdf
  case r of
    Left ds -> assertFailure ("not laid out: " <> show (map diagCode ds))
    Right (Left ds) -> pure ds
    Right (Right pl) -> pure (plNotices pl)

-- | The diagnostics of a build of a one-chapter project to PDF, or of golem check.
buildDiagnostics :: Bool -> BS.ByteString -> T.Text -> IO [Diagnostic]
buildDiagnostics check style source = withSystemTempDirectory "golem-fit" $ \tmp -> do
  writeProject tmp miniManifest style source []
  brDiagnostics <$> build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optCheckOnly = check}

-- | The rules of fit-characters in the style.css of a book of title paragraphs in a style.
fitRules :: BS.ByteString -> IO [T.Text]
fitRules toml = withSystemTempDirectory "golem-fit-css" $ \tmp -> do
  writeProject tmp (miniManifest <> "\n[targets.html]\n") (horizontalStyle <> "\n" <> toml) "@style title\n目次\n" []
  r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml], optFonts = fakeProvider}
  filter isError (brDiagnostics r) @?= []
  css <- TIO.readFile (tmp </> "build/html/style.css")
  pure (filter (T.isInfixOf "text-justify") (T.lines css))

-- | The codes of G07144 and where each is, from the start of the source.
fitWarnings :: [Diagnostic] -> [(Severity, Int)]
fitWarnings ds = [(diagSeverity d, spanStart (diagSpan d)) | d <- diagnosticsOf "G07144" ds]

fitCharactersTests :: [TestTree]
fitCharactersTests =
  [ testCase "root ADR 0468 I2: multi-line heading pitch uses its paragraph style" $ do
      let style = replaceIn "characters = 12" "alignment = \"free\"\ncharacters = 12" horizontalStyle <> "\n[paragraph-styles.h]\nline-pitch = \"20pt\"\n[headings.1]\nparagraph-style = \"h\"\nsize = \"10pt\"\nlines = 1\n"
      (_, pl) <- layoutOk style ("# " <> T.replicate 24 "あ" <> "\n") []
      map hbPitch (Map.elems (plHeadings pl)) @?= [20 * 65536]
      assertBool "multiple heading lines" (length (linesOf pl) > 1),
    testCase "root ADR 0468 I2, I3: heading fitting uses heading size and ignores paragraph indents" $ do
      let style = horizontalStyle <> "\n[paragraph-styles.h]\nfit-characters = 4\nsize = \"6pt\"\nindent = \"8zw\"\nspace-before = 2\n[headings.1]\nparagraph-style = \"h\"\nsize = \"10pt\"\n"
      (_, pl) <- layoutOk style "# 目次\n" []
      map slSize (linesOf pl) @?= [fs]
      map lengthOf (linesOf pl) @?= [4 * fs]
      map slIndent (linesOf pl) @?= [0],
    testCase "root ADR 0468 I1, I2: unselected heading styles leave the heading unchanged" $ do
      let para = "\n[color.swatches]\nblack = { cmyk = [0,0,0,100] }\n[paragraph-styles.h]\nindent = \"8zw\"\nspace-before = 2\nbackground = \"black\"\n[headings.1]\nsize = \"10pt\"\n"
      (_, selected) <- layoutOk (horizontalStyle <> para <> "paragraph-style = \"h\"\n") "# 題名\n\n本文\n" []
      (_, plain) <- layoutOk (horizontalStyle <> para) "# 題名\n\n本文\n" []
      setLines selected @?= setLines plain,
    testCase "root ADR 0468 I2: ignored tracking preserves the previous body tracking" $ do
      let style = horizontalStyle <> "\n[paragraph-styles.body]\ntracking = 200\n[paragraph-styles.h]\ntracking = 0\n[headings.1]\nsize = \"10pt\"\n"
      (_, selected) <- layoutOk (style <> "paragraph-style = \"h\"\n") "# 題名\n" []
      (_, plain) <- layoutOk style "# 題名\n" []
      setLines selected @?= setLines plain,
    testCase "root ADR 0468 I2: HTML headings carry their paragraph style and only allowed CSS" $
      withSystemTempDirectory "golem-heading-style" $ \tmp -> do
        let style = replaceIn "characters = 12" "alignment = \"free\"\ncharacters = 12" horizontalStyle <> "\n[paragraph-styles.h]\nline-pitch = \"20pt\"\nalign = \"center\"\nindent = \"8zw\"\n[headings.1]\nparagraph-style = \"h\"\n"
        writeProject tmp (miniManifest <> "\n[targets.html]\n") style "# 題名\n" []
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml], optFonts = fakeProvider}
        filter isError (brDiagnostics r) @?= []
        css <- TIO.readFile (tmp </> "build/html/style.css")
        html <- TIO.readFile (tmp </> "build/html/a.html")
        assertBool "style class" ("class=\"ps-h\"" `T.isInfixOf` html)
        let headingRules = filter (T.isPrefixOf "h1.ps-h ") (T.lines css)
        assertBool "line pitch" (any (T.isInfixOf "line-height: 20pt") headingRules)
        assertBool "alignment" (any (T.isInfixOf "text-align: center") headingRules)
        assertBool "no paragraph indent" (not (any (T.isInfixOf "padding-inline") headingRules)),
    testCase "root ADR 0466 I1: a paragraph whose style has no fit-characters is set as before" $ do
      (_, fitted) <- layoutOk (fitStyle 4 "[paragraph-styles.other]\nfirst-line-indent = \"0zw\"\n") "@style other\n目次\n\n本文の段落です。\n" []
      (_, plain) <- layoutOk (plainStyle "[paragraph-styles.other]\nfirst-line-indent = \"0zw\"\n") "@style other\n目次\n\n本文の段落です。\n" []
      setLines fitted @?= setLines plain,
    testCase "root ADR 0466 I2, I3: 2 characters of fit-characters = 4: 4 characters wide, the space of 2 between them" $ do
      (_, pl) <- layoutOk (fitStyle 4 "") "@style title\n目次\n" []
      case linesOf pl of
        [sl] -> do
          textsOf sl @?= ["目", "次"]
          lengthOf sl @?= 4 * fs
          gapsOf sl @?= [2 * fs]
          slIndent sl @?= 0
        ls -> assertFailure (show (length ls)),
    testCase "root ADR 0466 I2, I3: 4 characters of fit-characters = 4: no space between them" $ do
      (_, pl) <- layoutOk (fitStyle 4 "") "@style title\n前書き章\n" []
      map lengthOf (linesOf pl) @?= [4 * fs]
      map gapsOf (linesOf pl) @?= [[0, 0, 0]],
    testCase "root ADR 0466 I2: 1 character of fit-characters = 3 at the centre of the width" $ do
      (_, pl) <- layoutOk (fitStyle 3 "") "@style title\n序\n" []
      case linesOf pl of
        [sl] -> do
          lengthOf sl @?= 3 * fs
          textsOf sl @?= ["序"]
          [w | Box w c <- takeWhile (not . isText) (lineItems (slLine sl)), T.null (bcText c)] @?= [fs]
        ls -> assertFailure (show (length ls)),
    testCase "root ADR 0466 I2: the fitted line is put by align: center, right and towards the start" $ do
      let indentOf align = do
            (_, pl) <- layoutOk (fitStyle 4 ("align = \"" <> align <> "\"\n")) "@style title\n目次\n" []
            pure (map slIndent (linesOf pl), map lengthOf (linesOf pl))
      indentOf "center" >>= (@?= ([4 * fs], [4 * fs]))
      indentOf "right" >>= (@?= ([8 * fs], [4 * fs]))
      indentOf "left" >>= (@?= ([0], [4 * fs]))
      indentOf "fully-justified" >>= (@?= ([0], [4 * fs])),
    testCase "root ADR 0466 I2: a paragraph of the body of @style, put in place, is fitted" $ do
      (_, pl) <- layoutOk (fitStyle 4 "") "@style title\n:::\n目次\n\n索引\n:::\n" []
      map lengthOf (linesOf pl) @?= [4 * fs, 4 * fs]
      map gapsOf (linesOf pl) @?= [[2 * fs], [2 * fs]],
    testCase "root ADR 0466 I1: a list item of a style of fit-characters is not fitted, and has no diagnostic" $ do
      (_, fitted) <- layoutOk (fitStyle 4 "") "@style title\n  - 目次\n" []
      (_, plain) <- layoutOk (plainStyle "") "@style title\n  - 目次\n" []
      setLines fitted @?= setLines plain
      ds <- layoutDiagnostics (fitStyle 4 "") "@style title\n  - 目次\n"
      fitWarnings ds @?= [],
    testCase "root ADR 0466 I4: 5 characters of fit-characters = 4 are set as before, with one G07144 at the paragraph" $ do
      let src = "@style title\nあいうえお\n"
      (_, fitted) <- layoutOk (fitStyle 4 "") src []
      (_, plain) <- layoutOk (plainStyle "") src []
      setLines fitted @?= setLines plain
      ds <- layoutDiagnostics (fitStyle 4 "") src
      map fst (fitWarnings ds) @?= [Warning]
      map diagMessage (diagnosticsOf "G07144" ds) @?= ["段落の字が fit-characters の 4 字分の幅に収まらないので、字取りをしません"],
    testCase "root ADR 0466 I4: a paragraph with a line break is not fitted, with one G07144" $ do
      let src = "@style title\n目\\\n次\n"
      (_, fitted) <- layoutOk (fitStyle 4 "") src []
      (_, plain) <- layoutOk (plainStyle "") src []
      setLines fitted @?= setLines plain
      ds <- layoutDiagnostics (fitStyle 4 "") src
      map fst (fitWarnings ds) @?= [Warning],
    testCase "root ADR 0466 I4: a paragraph that keeps its lines and has two is one G07144" $ do
      ds <- layoutDiagnostics (fitStyle 4 "line-breaks = \"keep\"\n") "@style title\n  目\n  次\n"
      length (fitWarnings ds) @?= 1,
    testCase "root ADR 0466 I4: G07144 once for each paragraph that does not fit, none for those that do" $ do
      let src = "@style title\nあいうえお\n\n@style title\n目次\n\n@style title\n目\\\n次\n\nかきくけこさ\n"
      ds <- layoutDiagnostics (fitStyle 4 "") src
      -- the first paragraph and the third, each at its block
      case fitWarnings ds of
        [(Warning, a), (Warning, b)] -> do
          assertBool (show a) (a <= offsetIn src "あいうえお")
          assertBool (show b) (b >= offsetIn src "@style title\n目\\" && b <= offsetIn src "目\\")
        ws -> assertFailure (show ws),
    testCase "root ADR 0466 I4: golem build and golem check report G07144 alike" $ do
      let src = "@style title\nあいうえお\n\n@style title\n目次\n"
      built <- buildDiagnostics False (fitStyle 4 "") src
      checked <- buildDiagnostics True (fitStyle 4 "") src
      map fst (fitWarnings built) @?= [Warning]
      fitWarnings checked @?= fitWarnings built,
    testCase "root ADR 0466 I2: HTML writes the width and the spacing of a style of fit-characters, none without it" $ do
      fitted <- fitRules "[paragraph-styles.title]\nfit-characters = 4\n[paragraph-styles.other]\nalign = \"center\"\n"
      fitted @?= ["p.ps-title { width: 4em; text-align: justify; text-align-last: justify; text-justify: inter-character; }"]
      fitRules "[paragraph-styles.title]\nalign = \"center\"\n" >>= (@?= [])
  ]
  where
    isText = \case
      Box _ c -> not (T.null (bcText c))
      _ -> False
