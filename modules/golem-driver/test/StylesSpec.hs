module StylesSpec (inFileTests, regexStyleTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Doc.Assemble (Book)
import Golem.Driver
import Golem.Driver.Lint (lintProject)
import Golem.Driver.Pdf (PdfInput (..), PdfLayout (..), PlacedFigure (..), SetLine (..), flowLines, layoutPdf, usedRoles)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (Look (..), Synthetic (..))
import Golem.LayoutSpec (pageGeometry)
import Golem.Project (ProjectFailure (..))
import Golem.Project.Style (LocalStyles (..), ParaStyleDef (..), noLocalStyles, noParaDef, parseStyle)
import Golem.Syntax
import Support
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import Test.Tasty
import Test.Tasty.HUnit

-- | The evaluated project of 'withChapters'; no errors allowed.
evaluatedOk :: FilePath -> IO (Evaluated, Book)
evaluatedOk tmp = do
  ev <- evaluateProject Dev tmp
  case ev of
    Left f -> assertFailure (show (pfDiagnostics f))
    Right e -> case (evBook e, filter isError (evDiagnostics e)) of
      (Just book, []) -> pure (e, book)
      (_, errs) -> assertFailure (show [(diagCode d, diagMessage d) | d <- errs])

-- | The PDF lines of the chapters as (line length, indent).
chapterLines :: BS.ByteString -> [(FilePath, T.Text)] -> IO [(Integer, Integer)]
chapterLines style chapters = withChapters style chapters [] $ \tmp -> do
  (e, book) <- evaluatedOk tmp
  r <- flowLines fakeProvider (PdfInput tmp (evProject e) (evStyle e) book False [] Map.empty Nothing (localStylesOf e) (chapterMasters (evProject e)) (evStyleFile e) Map.empty)
  either (assertFailure . show) (pure . snd) r

-- | The PDF layout of the chapters.
chapterLayout :: BS.ByteString -> [(FilePath, T.Text)] -> [(FilePath, BS.ByteString)] -> IO PdfLayout
chapterLayout style chapters files = withChapters style chapters [] $ \tmp -> do
  forM_ files $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes
  (e, book) <- evaluatedOk tmp
  geom <- either (assertFailure . show) pure (pageGeometry (FileId 0) False (evStyle e))
  r <- layoutPdf (PdfInput tmp (evProject e) (evStyle e) book False [] Map.empty Nothing (localStylesOf e) (chapterMasters (evProject e)) (evStyleFile e) Map.empty) geom fakeFonts
  either (assertFailure . show) pure r

-- | Regex styles (docs/adr ADR 0015).
regexStyleTests :: [TestTree]
regexStyleTests =
  [ testCase "HTML: a match is a span of its character style" $ do
      (page, _) <- htmlMini regexStyle "第12章\n"
      assertBool (T.unpack page) ("第<span class=\"cs-n\">12</span>章" `T.isInfixOf` page),
    testCase "plain text: the text is unchanged" $
      withChapters regexStyle [("c1.gm", "第12章\n")] [] $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        TIO.readFile (tmp </> "build/text/horizontal/c1.txt") >>= (@?= "第12章\n"),
    testCase "PDF: the match is drawn in synthetic bold, the rest is not" $ do
      content <- miniPdf fakeProvider True (horizontalStyle <> "\n" <> regexStyle) "第12章\n" [] >>= fmap BS.concat . inflateAll
      let runs = strokeRuns content
      assertBool (show runs) (all isJust (widthsOf '1' runs) && not (null (widthsOf '1' runs)))
      assertBool (show runs) (all isJust (widthsOf '2' runs))
      widthsOf '第' runs @?= [Nothing]
      widthsOf '章' runs @?= [Nothing],
    testCase "HTML: the regex styles of a file hold in that file only" $
      withChapters "" [("c1.gm", "@style-def character n synthetic-bold=true\n@style-def regex body pattern=\"[0-9]+\" style=n\n\n第12章\n"), ("c2.gm", "第12章\n")] [] $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        p1 <- TIO.readFile (tmp </> "build/html/c1.xhtml")
        p2 <- TIO.readFile (tmp </> "build/html/c2.xhtml")
        assertBool (T.unpack p1) ("第<span class=\"cs-n\">12</span>章" `T.isInfixOf` p1)
        assertBool (T.unpack p2) ("第12章" `T.isInfixOf` p2),
    testCase "PDF: vertical, a match inside a ruby base is set and the reading drawn" $ do
      content <- miniPdf fakeProvider True (pdfStyle <> "\n" <> regexStyle) "[ruby: 東京12|とうきょう]へ\n" [] >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
          sizesOf c = nub [dSize d | d <- ds, dGlyph d == fromEnum c]
      assertBool "the reading" (not (null (sizesOf 'と')))
      assertBool "the reading is smaller than the base" (sizesOf 'と' /= sizesOf '東')
      -- a ruby whose whole base matches is wrapped as a whole and takes the look
      whole <- miniPdf fakeProvider True (pdfStyle <> "\n" <> regexStyle) "[ruby: 12|じゅうに]へ\n" [] >>= fmap BS.concat . inflateAll
      let runs = strokeRuns whole
      assertBool (show runs) (not (null (widthsOf (toEnum 0x32) runs)) && all isJust (widthsOf (toEnum 0x32) runs))
  ]
  where
    regexStyle = "[character-styles.n]\nsynthetic-bold = true\n\n[paragraph-styles.body]\nregex-styles = [{ pattern = '[0-9]+', style = \"n\" }]\n"

inFileTests :: [TestTree]
inFileTests =
  [ testCase "HTML: a page with styles of its own has a class; its rules are under it" $
      withChapters "" (letters <> [("c3.gm", "本文。\n")]) [] $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        p1 <- TIO.readFile (tmp </> "build/html/c1.xhtml")
        p2 <- TIO.readFile (tmp </> "build/html/c2.xhtml")
        p3 <- TIO.readFile (tmp </> "build/html/c3.xhtml")
        assertBool "c1" ("<body class=\"file-1\">" `T.isInfixOf` p1)
        assertBool "c2" ("<body class=\"file-2\">" `T.isInfixOf` p2)
        assertBool "c3" ("<body>" `T.isInfixOf` p3)
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "file-1" (any ("padding-inline-start: 2em;" `T.isInfixOf`) (rulesOf "body.file-1 p.ps-letter" css))
        assertBool "file-2" (any ("padding-inline-start: 4em;" `T.isInfixOf`) (rulesOf "body.file-2 p.ps-letter" css))
        assertBool "space-between" (any ("margin-block-start: 1em;" `T.isInfixOf`) (rulesOf "body.file-1 p.ps-letter + p.ps-letter" css))
        rulesOf "p.ps-letter" css @?= [],
    testCase "HTML: the class of a vertical page" $
      withChapters pdfStyle (take 1 letters) [] $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        p1 <- TIO.readFile (tmp </> "build/html/c1.xhtml")
        assertBool "c1" ("<body class=\"vertical file-1\">" `T.isInfixOf` p1),
    testCase "PDF: the same name indents by the definition of each file" $ do
      let fs = 655360
      ls <- chapterLines (horizontal30 "") letters
      map snd ls @?= [2 * fs, 4 * fs],
    testCase "HTML: an override writes every property under the class of its page" $ do
      let style = "[character-styles.term]\nsynthetic-bold = true\n\n[paragraph-styles.quote]\nindent = \"1zw\"\n"
          plain = [("c" <> show i <> ".gm", "[style term: 語]\n\n@style quote\n引用。\n") | i <- [1 .. 3 :: Int]]
          fourth = "@style-def character term synthetic-bold=false\n@style-def paragraph body indent=2zw\n\n[style term: 語]\n\n- 項目\n"
          cssOf c4 = withChapters style (plain <> [("c4.gm", c4)]) [] $ \tmp -> do
            r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
            assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
            TIO.readFile (tmp </> "build/html/style.css")
      css <- cssOf fourth
      assertBool "term" (any ("font-weight: normal;" `T.isInfixOf`) (rulesOf "body.file-4 .cs-term" css))
      assertBool "body" (any ("padding-inline-start: 2em;" `T.isInfixOf`) (rulesOf "body.file-4 p:not([class])" css))
      rulesOf "body.file-4 p.ps-quote" css @?= []
      let ls = T.lines css
          index p = length (takeWhile (not . p) ls)
          liRule = index ("body.file-4 li p:not([class]), body.file-4 li p[class] {" `T.isPrefixOf`)
      assertBool "the list rule" (liRule < length ls)
      assertBool "after the rules of the page" (all (\l -> not ("body.file-4" `T.isPrefixOf` l) || l == ls !! liRule) (drop (liRule + 1) ls))
      assertBool "after" (index ("body.file-4 p:not([class])" `T.isPrefixOf`) < liRule)
      without <- cssOf "[style term: 語]\n"
      filter (not . ("body.file-" `T.isPrefixOf`)) ls @?= T.lines without,
    testCase "PDF: an override of a character style and of body holds in its file only" $ do
      let style = horizontal30 "\n[character-styles.term]\nsynthetic-bold = true\n"
      pl <- chapterLayout style [("c1.gm", "[style term: 甲]\n"), ("c2.gm", "@style-def character term synthetic-bold=false\n@style-def paragraph body indent=2zw\n\n[style term: 乙]\n")] []
      [bcText c | sl <- Map.elems (plLines pl), Box _ c <- lineItems (slLine sl), synBold (lkSynthetic (bcLook c))] @?= ["甲"]
      map slIndent (Map.elems (plLines pl)) @?= [0, 2 * 655360],
    testCase "PDF: an override of caption sets the captions of its file" $ do
      img <- tinyImage
      let fig = "@figure images/tiny.jpg alt=\"t\"\n  キャプション。\n"
      pl <- chapterLayout (figStyle (horizontal30 "")) [("c1.gm", "@style-def paragraph caption size=0.8zw\n\n" <> fig), ("c2.gm", fig)] img
      map pfCaptionSize (Map.elems (plFigures pl)) @?= [524288, 655360],
    testCase "PDF: a role only a style of a file uses is loaded and drawn" $ do
      s <- either (assertFailure . show) pure (parseStyle (FileId 0) "[fonts.body]\nja = \"b.otf\"\n\n[fonts.heading]\nja = \"h.otf\"\n")
      usedRoles s [] @?= ["body"]
      usedRoles s [noLocalStyles {lsParaStyles = Map.fromList [("letter", noParaDef {psFont = Just "heading"})]}] @?= ["body", "heading"]
      content <- miniPdf fakeProvider True (horizontal30 "" <> fakeBody <> "\n[fonts.heading]\nja = \"fonts/h.otf\"\n") "@style-def paragraph letter font=heading\n\n@style letter\n手。\n\n本。\n" fakeFontFiles >>= fmap BS.concat . inflateAll
      let ds = drawnGlyphs content
          fontsOf c = nub [dFont d | d <- ds, dGlyph d == fromEnum c]
      assertBool "drawn" (not (null (fontsOf '手')))
      assertBool "the role of letter" (fontsOf '手' /= fontsOf '本'),
    testCase "the styles of a file imported are not the importer's" $
      withChapters "" [("c1.gm", "@import common.gm as c\n\n@style letter\n手紙。\n")] [("common.gm", "@style-def paragraph letter\n\n@set v = 1\n")] $ \tmp -> do
        ev <- evaluateProject Dev tmp
        case ev of
          Left f -> assertFailure (show (pfDiagnostics f))
          Right e -> assertBool "G02047" (DiagnosticCode "G02047" `elem` map diagCode (evDiagnostics e)),
    testCase "plain text: the first line of a style of the file" $
      withChapters "" [("c1.gm", "@style-def paragraph letter first-line-indent=1zw\n\n@style letter\n手紙。\n")] [] $ \tmp -> do
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        TIO.readFile (tmp </> "build/text/horizontal/c1.txt") >>= (@?= "　手紙。\n"),
    testCase "HTML: @manifest reads its file in the line style" $
      withChapters "" [("c1.gm", "@manifest paragraph-separator=line\n\n一。\n二。\n三。\n"), ("c2.gm", "一。\n二。\n")] [] $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        p1 <- TIO.readFile (tmp </> "build/html/c1.xhtml")
        p2 <- TIO.readFile (tmp </> "build/html/c2.xhtml")
        T.count "<p>" p1 @?= 3
        T.count "<p>" p2 @?= 1,
    testCase "HTML: @manifest wins over the entry of the chapter" $
      withEntries "" ["{ file = \"c1.gm\", paragraph-separator = \"line\" }"] [("c1.gm", "@manifest paragraph-separator=blank-line\n\n一。\n二。\n")] [] $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        p1 <- TIO.readFile (tmp </> "build/html/c1.xhtml")
        T.count "<p>" p1 @?= 1,
    testCase "HTML: @manifest of a file imported does not reach the importer" $
      withChapters "" [("c1.gm", "@import common.gm as c\n\n[= c.v]。\n二。\n")] [("common.gm", "@manifest paragraph-separator=line\n\n@set v = 1\n")] $ \tmp -> do
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        p1 <- TIO.readFile (tmp </> "build/html/c1.xhtml")
        T.count "<p>" p1 @?= 1,
    testCase "lint: two Latin lines of a file in the line style are not G05001" $
      withChapters "" [("c1.gm", "@manifest paragraph-separator=line\n\nFull fathom five\nOf his bones\n"), ("c2.gm", "Full fathom five\nOf his bones\n")] [] $ \tmp -> do
        (infos, ds) <- lintProject Dev False tmp
        [p | d <- ds, diagCode d == DiagnosticCode "G05001", Just (SourceInfo p _) <- [Map.lookup (spanFile (diagSpan d)) infos]] @?= ["c2.gm"],
    testCase "lint: a style of the file that keeps its lines is not G05001" $
      withChapters "" [("c1.gm", "@style-def paragraph letter line-breaks=keep\n\n@style letter\n  Full fathom five\n  Of his bones\n"), ("c2.gm", "Full fathom five\nOf his bones\n")] [] $ \tmp -> do
        (infos, ds) <- lintProject Dev False tmp
        [p | d <- ds, diagCode d == DiagnosticCode "G05001", Just (SourceInfo p _) <- [Map.lookup (spanFile (diagSpan d)) infos]] @?= ["c2.gm"]
  ]
  where
    letters =
      [ ("c1.gm", "@style-def paragraph letter indent=2zw\n\n@style letter\n手紙。\n"),
        ("c2.gm", "@style-def paragraph letter indent=4zw\n\n@style letter\n手紙。\n")
      ]
