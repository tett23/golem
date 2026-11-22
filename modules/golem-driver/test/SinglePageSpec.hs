-- | Pagination and preflight through ordinary PDF input (root ADR 0400).
module SinglePageSpec (tests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Layout.PageLabel (pageLabelText)
import Golem.Layout.Paginate (ColumnSet (..), PageOut (..))
import Golem.LayoutSpec (PageGeometry (..), Rect (..), typeAreaFor)
import Golem.Pdf qualified as P
import Golem.Preflight qualified as V
import Golem.Preflight.Rules (printRules)
import Golem.Preflight.View qualified as V
import Golem.Project.Style (SizeSource (..))
import Golem.Syntax
import Golem.Typeset (PdfInput (..), PdfLayout (..), layoutLabels, layoutPdf, renderPdfView)
import Support
import Test.Tasty
import Test.Tasty.HUnit

singleStyle :: BS.ByteString
singleStyle = replaceIn "binding = \"left\"" "layout = \"single\"" (replaceIn "gutter =" "left =" horizontalStyle)

sectionBook :: Integer -> Text -> Text -> IO (Either [Diagnostic] (PageGeometry, PdfLayout))
sectionBook start first second = sectionBookFiles start first second []

sectionBookFiles :: Integer -> Text -> Text -> [(FilePath, BS.ByteString)] -> IO (Either [Diagnostic] (PageGeometry, PdfLayout))
sectionBookFiles start first second files = layoutMiniWith manifest singleStyle first (("b.gm", TE.encodeUtf8 second) : files)
  where
    manifest = replaceIn "chapters = [\"a.gm\"]" ("chapters = [\"a.gm\", { file = \"b.gm\", page-numbering = { start = " <> T.pack (show start) <> " } }]") miniManifest

sectionPages :: PdfLayout -> [(Int, Int)]
sectionPages pl = [(k, poNumber p) | p <- plPages pl, k <- poSections p]

expectLayout :: Either [Diagnostic] (PageGeometry, PdfLayout) -> (PdfLayout -> Assertion) -> Assertion
expectLayout result use = case result of
  Left ds -> assertFailure (show ds)
  Right (_, pl) -> use pl

tests :: TestTree
tests =
  testGroup
    "root ADR 0400"
    [ testCase "A1/A2: physical right folios and multiline heads keep their anchors on three pages" $
        forM_ ["horizontal", "vertical"] $ \mode -> do
          let style = replaceIn "writing-mode = \"horizontal\"" ("writing-mode = \"" <> mode <> "\"") (if mode == "vertical" then replaceIn "lines = 30" "lines = 20" singleStyle else singleStyle) <> "\n[masters.body]\nrunning-head = { position = \"top-left\", content = [\"Heading\", \"Second\"] }\nfolio = { position = \"bottom-right\", format = \"{n}\" }\n"
          result <- withMiniInput fakeProvider miniManifest (withBodyFont style) "甲。\n@page-break\n乙。\n@page-break\n丙。\n" fakeFontFiles $ \inp _ _ -> renderPdfView "test" fakeProvider inp
          case result of
            Right (Right (_, _, view, _)) -> do
              let pages = V.vwPages view
                  folios = [[V.lvRect line | line <- V.pvLines page, V.lvKind line == "ノンブル"] | page <- pages]
                  heads = [[V.lvRect line | line <- V.pvLines page, V.lvKind line == "柱"] | page <- pages]
              length pages @?= 3
              map length folios @?= [1, 1, 1]
              length (nub [[(rectX r + rectW r, rectY r) | r <- fs] | fs <- folios]) @?= 1
              assertBool (show heads) (any ((== 2) . length) heads)
              length (nub [hs | hs <- heads, length hs == 2]) @?= 1
            other -> assertFailure (either show (either show (const "unexpected PDF result")) other),
      testCase "I2: index columns stay inside the same asymmetric type area across page parities" $ do
        let wide = replaceIn "characters = 12" "characters = 30" singleStyle <> "\n[index]\ncolumns = 2\ncolumn-gap = \"10pt\"\n"
            source = T.unlines ["[index reading=あ: 項目" <> T.pack (show n) <> "]本文。" | n <- [1 .. 120 :: Int]] <> "@index\n"
        result <- withMiniInput fakeProvider miniManifest (withBodyFont wide) source fakeFontFiles $ \inp geom fonts -> do
          pl <- layoutPdf inp geom fonts
          pdf <- renderPdfView "test" fakeProvider inp
          pure ((\layout drawn -> (geom, layout, drawn)) <$> pl <*> pdf)
        case result of
          Right (Right (geom, pl, (_, _, view, _))) -> do
            let indexPages = nub [poNumber p | p <- plPages pl, csColumns (poColumnSet p) == 2]
                area = typeAreaFor geom 1
            assertBool (show indexPages) (length indexPages >= 2)
            forM_ [p | p <- V.vwPages view, V.pvIndex p `elem` indexPages] $ \page ->
              forM_ (V.pvLines page) $ \line -> do
                let r = V.lvRect line
                assertBool (show r) (rectX r >= rectX area && rectX r + rectW r <= rectX area + rectW area)
          other -> assertFailure (either show (either show (const "unexpected index output")) other),
      testCase "A6: the fixed excerpt reproduces a 9 to 11 page PDF without blanks" $ do
        original <- TIO.readFile "test/fixtures/kanikosen/kanikosen.gm"
        source <- TIO.readFile "test/fixtures/single-page/kanikosen.gm"
        source @?= T.unlines (take 164 (T.lines original))
        manifest <- replaceIn "kanikosen.gm" "a.gm" <$> BS.readFile "test/fixtures/single-page/manifest.toml"
        style <- BS.readFile "test/fixtures/single-page/style.toml"
        noto <- notoBytes
        result <- withMiniInput realProvider manifest style source [("fonts/NotoSerifJP-Regular.otf", noto)] $ \inp geom _ -> do
          typeAreaFor geom 1 @?= typeAreaFor geom 2
          renderPdfView "test" realProvider inp
        case result of
          Right (Right (_, _, view, _)) -> do
            let pages = V.vwPages view
            assertBool (show (length pages)) (length pages >= 9 && length pages <= 11)
            assertBool "no blank pages" (all (not . V.pvBlank) pages)
          other -> assertFailure (either show (either show (const "unexpected PDF result")) other),
      testCase "A3: labels and page references restart without a parity blank" $ do
        let manifest = replaceIn "chapters = [\"a.gm\"]" "chapters = [\"a.gm\", { file = \"b.gm\", page-numbering = { start = 1 } }]" miniManifest
        result <- withMiniInput fakeProvider manifest (withBodyFont singleStyle) "甲。\n" (("b.gm", TE.encodeUtf8 "@label here\n参照[ref-page here]。\n") : fakeFontFiles) $ \inp geom fonts -> do
          pl <- layoutPdf inp geom fonts
          pure ((\layout -> (layout, Map.map pageLabelText (layoutLabels inp layout))) <$> pl)
        case result of
          Right (Right (pl, labels)) -> do
            Map.lookup 2 labels @?= Just "1"
            assertBool (show (lineTexts pl)) ("参照1。" `elem` lineTexts pl)
            assertBool "no blank pages" (all (not . poBlank) (plPages pl))
          other -> assertFailure (either show (either show (const "unexpected layout")) other),
      testCase "I5: section start parity adds no blank page after body contents" $ do
        one <- sectionBook 1 "前の章。\n" "次の章。\n"
        two <- sectionBook 2 "前の章。\n" "次の章。\n"
        forM_ [one, two] $ \r -> expectLayout r $ \pl -> do
          sectionPages pl @?= [(1, 2)]
          assertBool "no blank pages" (all (not . poBlank) (plPages pl)),
      testCase "I5: section start parity is irrelevant on an empty page" $ do
        one <- sectionBook 1 "" "次の章。\n"
        two <- sectionBook 2 "" "次の章。\n"
        forM_ [one, two] $ \r -> expectLayout r $ \pl -> sectionPages pl @?= [(1, 1)],
      testCase "I5/I6: continued notes and deferred figures finish before a later heading regardless of label parity" $ do
        image <- tinyImage
        let figure = T.replicate 29 "本文。\n" <> "@nonumber\n@figure images/tiny.jpg width=30pt alt=図\n  図の説明。\n"
            note = "本文[note: " <> T.replicate 1000 "注" <> "]。\n"
        forM_ [(figure, image), (note, [])] $ \(first, files) -> do
          one <- sectionBookFiles 1 first "# 次の章\n本文。\n" files
          two <- sectionBookFiles 2 first "# 次の章\n本文。\n" files
          case (one, two) of
            (Right (_, a), Right (_, b)) -> do
              sectionPages a @?= sectionPages b
              map poBlank (plPages a) @?= map poBlank (plPages b)
              maximum (map poNumber (plPages a)) @?= maximum (map poNumber (plPages b))
            other -> assertFailure (either show (const "layout one succeeded") (fst other) <> "; " <> either show (const "layout two succeeded") (snd other)),
      testCase "I6: subsequent explicit recto and verso refer to physical page parity" $
        forM_ [("recto", 3), ("verso", 2)] $ \(kind, page) -> do
          result <- layoutMini singleStyle ("甲。\n@page-break " <> kind <> "\n乙。\n") []
          expectLayout result $ \pl -> maximum (map poNumber (plPages pl)) @?= page,
      testCase "I6: a labelled section does not change the parity of later breaks" $ do
        result <- sectionBook 2 "" "甲。\n@page-break recto\n乙。\n"
        expectLayout result $ \pl -> maximum (map poNumber (plPages pl)) @?= 3,
      testCase "I4: an unused manuscript style definition cannot introduce a spine alignment" $ do
        result <- layoutMini singleStyle "@style-def paragraph unused align=towards-spine\n本文。\n" []
        case result of
          Left ds -> codesOf ds @?= ["G03006"]
          Right _ -> assertFailure "accepted a spine alignment in an unused definition",
      testCase "I4: local inheritance reports the defining forbidden alignment once" $ do
        let prefix = "@style-def paragraph valid align=left\n"
            source = prefix <> "@style-def paragraph parent align=towards-spine\n@style-def paragraph child based-on=parent\n@style-def paragraph grandchild based-on=child\n本文。\n"
        result <- layoutMini singleStyle source []
        case result of
          Left ds -> do
            codesOf ds @?= ["G03006"]
            map (spanStart . diagSpan) ds @?= [BS.length (TE.encodeUtf8 prefix)]
          Right _ -> assertFailure "accepted a locally inherited spine alignment",
      testCase "I7: all crop mark styles and ordinary folio choices leave hidden folios absent" $
        forM_ [Nothing, Just P.Western, Just P.Japanese] $ \marks -> forM_ [False, True] $ \folio -> do
          let page = replaceIn "layout = \"single\"" "layout = \"single\"\nbleed = \"3mm\"" singleStyle
              style = page <> if folio then "\n[masters.body]\nfolio = { position = \"bottom-right\", format = \"{n}\" }\n" else ""
          result <- withMiniInput fakeProvider miniManifest (withBodyFont style) "本文。\n" fakeFontFiles $ \inp _ _ -> renderPdfView "test" fakeProvider inp {piMarks = marks}
          case result of
            Right (Right (_, _, view, _)) -> assertBool "hidden folios were drawn" (all ((/= SourceHiddenFolio) . V.gvSizeSource) (concatMap V.pvGlyphs (V.vwPages view)))
            other -> assertFailure (either show (either show (const "unexpected PDF result")) other),
      testCase "I8: rendered single-page views report the physical left edge on both parities" $ do
        result <- withMiniInput fakeProvider miniManifest (withBodyFont singleStyle) "甲。\n@page-break\n乙。\n" fakeFontFiles $ \inp _ _ -> renderPdfView "test" fakeProvider inp
        case result of
          Right (Right (_, _, view, _)) -> do
            let rectangle = Rect 65536 6553600 655360 655360
                source = mkSpan (FileId 0) 0 1
                image = P.RasterFigure (P.ImageData 100 100 8 P.CsCmyk Nothing "" False False Nothing)
                hazard p = p {V.pvLines = [V.LineView rectangle "本文の行" source Nothing], V.pvImages = [V.ImageView rectangle image source "image.jpg" False]}
                ds = filter ((`elem` [DiagnosticCode "G09011", DiagnosticCode "G09012"]) . diagCode) (V.check printRules view {V.vwPages = map hazard (V.vwPages view)})
            length ds @?= 2
            assertBool (show ds) (all (("左" `T.isInfixOf`) . diagMessage) ds)
            length (nub (map V.pvIndex (V.vwPages view))) @?= 2
            let onePage p =
                  [ (diagCode d, diagSeverity d, T.replace (V.pagesPhrase [V.pvIndex p]) "" (diagMessage d))
                  | d <- V.check printRules view {V.vwPages = [hazard p]},
                    diagCode d `elem` [DiagnosticCode "G09011", DiagnosticCode "G09012"]
                  ]
            map (length . onePage) (V.vwPages view) @?= [2, 2]
            length (nub (map onePage (V.vwPages view))) @?= 1
          other -> assertFailure (either show (either show (const "unexpected PDF result")) other)
    ]
