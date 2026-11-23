module KeepBookPartsSpec (tests) where

import Data.ByteString qualified as BS
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Layout.Paginate (PageOutAt (..), Slotted (..))
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), folioTexts, layoutPdf)
import Support (buildMini, fakeProvider, horizontalStyle, layoutOk, miniManifest, replaceIn, setLineText, tinyImage, withMiniInput)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "root ADR 0401 book-part integration"
    [ testCase "root ADR 0401 I2: free page retention keeps a whole item across columns" $ do
        let free = replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" (style "page" 2)
        (_, layout) <- layoutOk free (source 3 3) []
        positions layout @?= [(2, 0), (2, 0), (2, 1)],
      testCase "root ADR 0401 I2: free page moves a whole item with a wrapped figure to the next page" $ do
        files <- tinyImage
        let free unit = replaceIn "lines = 3" "lines = 6" (replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" (style unit 1))
            manuscript = T.intercalate "\\\n" (replicate 4 "f") <> "\n\n- x\\\n  x\n\n  @nonumber\n  @figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n\n  x\\\n  x\n"
            figures layout = [poNumber p | p <- plPages layout, (_, SWrapped _) <- poSlots p]
        (_, column) <- layoutOk (free "column") manuscript files
        (_, page) <- layoutOk (free "page") manuscript files
        assertBool ("column splits the item: " <> show (positions column)) (length (nub (map fst (positions column))) > 1)
        assertEqual (show (plPages page)) (replicate 4 (2, 0)) (positions page)
        figures page @?= [2]
        filter ((== DiagnosticCode "G07133") . diagCode) (plNotices page) @?= [],
      testCase "root ADR 0401 I3: free page item with a wrapped figure larger than a page falls back once" $ do
        files <- tinyImage
        let free = replaceIn "lines = 3" "lines = 6" (replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" (style "page" 1))
            manuscript = "f\n\n- x\\\n  x\n\n  @nonumber\n  @figure images/tiny.jpg alt=\"t\" wrap=start width=2zw\n\n  " <> T.intercalate "\\\n  " (replicate 6 "x") <> "\n"
        (_, layout) <- layoutOk free manuscript files
        assertEqual (show (plPages layout)) 8 (length (positions layout))
        length (filter ((== DiagnosticCode "G07133") . diagCode) (plNotices layout)) @?= 1,
      testCase "root ADR 0401 I2: single-page folio resets do not change physical spread boundaries" $ do
        let single = replaceIn "binding = \"left\"" "layout = \"single\"" (replaceIn "gutter = \"20mm\"" "left = \"20mm\"" (style "spread" 1)) <> "\n[masters.body]\nfolio = { position = \"bottom-right\", format = \"{n}\" }\n"
            manifest = TE.encodeUtf8 ("chapters = [{ file = \"a.gm\", page-numbering = { style = \"lower-roman\", start = 40 } }]\n" <> T.dropWhile (/= '\n') (TE.decodeUtf8 miniManifest))
        result <- withMiniInput fakeProvider manifest single ("@page-break\n\n" <> source 2 3) [] $ \inp geometry fonts -> do
          actual <- layoutPdf inp geometry fonts
          case actual of
            Left diagnostics -> assertFailure (show diagnostics)
            Right layout -> do
              positions layout @?= [(2, 0), (3, 0), (3, 0)]
              let labels = folioTexts inp geometry layout
              map (`Map.lookup` labels) [2, 3] @?= [Just "xli", Just "xlii"]
        either (assertFailure . show) pure result,
      testCase "root ADR 0401 I2: a list item keeps its deferred figure inside its page" $ do
        let files = [("images/tiny.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><rect width=\"10\" height=\"10\"/></svg>")]
            manuscript = T.intercalate "\\\n" (replicate 3 "f") <> "\n\n- a\\\n  a\n\n  @nonumber\n  @figure images/tiny.svg width=1zw alt=\"tiny\"\n    caption\n"
        (_, layout) <- layoutOk (style "page" 2) manuscript files
        let textPages = [poNumber p | p <- plPages layout, (_, SLine ident) <- poSlots p, Just line <- [Map.lookup ident (plLines layout)], "a" `T.isSuffixOf` setLineText line]
            figurePages = [poNumber p | p <- plPages layout, (_, SFigure _) <- poSlots p]
        assertEqual (show (plPages layout, plNotices layout)) ([2, 2], [2]) (textPages, figurePages)
        filter ((== DiagnosticCode "G07133") . diagCode) (plNotices layout) @?= [],
      testCase "root ADR 0401 I3: nested list source frames retain the inner item after outer fallback" $ do
        (_, layout) <- layoutOk (style "page" 2) "- f\\\n  f\\\n  f\\\n  f\n\n  - x\\\n    x\\\n    x\n" []
        positions layout @?= replicate 3 (2, 0)
        let notices = filter ((== DiagnosticCode "G07133") . diagCode) (plNotices layout)
        length notices @?= 1
        map (spanStart . diagSpan) notices @?= [0],
      testCase "root ADR 0401 I1: figures and captions retain their existing indivisible placement" $ do
        let files = [("images/tiny.svg", "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><rect width=\"10\" height=\"10\"/></svg>")]
            manuscript = T.intercalate "\\\n" (replicate 5 "f") <> "\n\n@nonumber\n@figure images/tiny.svg width=1zw alt=\"tiny\"\n  caption\n"
        (_, ordinary) <- layoutOk (style "column" 2) manuscript files
        (_, page) <- layoutOk (style "page" 2) manuscript files
        (_, spread) <- layoutOk (style "spread" 2) manuscript files
        plPages page @?= plPages ordinary
        plPages spread @?= plPages ordinary
        (codes, _) <- buildMini fakeProvider True (style "page" 2) "@nonumber\n@figure images/tiny.svg width=1zw alt=\"tiny\"\n  c\\\n  c\\\n  c\n" files
        assertBool "caption-only overflow keeps existing dimension error" (DiagnosticCode "G07038" `elem` codes),
      testCase "root ADR 0401 I3: a caption pair larger than a page falls back with one notice" $ do
        let manuscript = "@nonumber\n@caption " <> T.replicate 30 "題" <> "\n@column-widths 4zw\n| " <> T.replicate 8 "h " <> "|\n| --- |\n| " <> T.replicate 8 "x " <> "|\n"
        (_, layout) <- layoutOk (style "page" 2) manuscript []
        let notices = filter ((== DiagnosticCode "G07133") . diagCode) (plNotices layout)
            tablePages = [poNumber p | p <- plPages layout, (_, SLine ident) <- poSlots p, Map.member ident (plTableLines layout)]
        length notices @?= 1
        map (spanStart . diagSpan) notices @?= [BS.length (TE.encodeUtf8 (fst (T.breakOn "| " manuscript)))]
        tablePages @?= [1, 1, 2, 2, 2, 2],
      testCase "root ADR 0401 I2: a table caption and first row may fill a whole spread" $ do
        let manuscript = "@page-break\n\n@nonumber\n@caption " <> T.replicate 30 "題" <> "\n@column-widths 4zw\n| " <> T.replicate 8 "h " <> "|\n| --- |\n| " <> T.replicate 8 "x " <> "|\n"
        (_, layout) <- layoutOk (style "spread" 2) manuscript []
        let tablePages = [poNumber p | p <- plPages layout, (_, SLine ident) <- poSlots p, Map.member ident (plTableLines layout)]
        assertBool "table spans only physical pages two and three" (all (`elem` [2, 3]) tablePages && 2 `elem` tablePages && 3 `elem` tablePages),
      testCase "root ADR 0401 I2: a definition term follows its first description into a new page" $ do
        (_, layout) <- layoutOk (style "page" 2) (T.intercalate "\\\n" (replicate 5 "f") <> "\n\n= term\n  x\\\n  x\n") []
        positions layout @?= [(2, 0), (2, 0)]
        let terms = [(poNumber p, poColumn p) | p <- plPages layout, (_, SLine ident) <- poSlots p, Just line <- [Map.lookup ident (plLines layout)], setLineText line == "term"]
        terms @?= [(2, 0)],
      testCase "root ADR 0401 I2: a definition preserves nested table header and first row" $ do
        let sourceText = T.intercalate "\\\n" (replicate 3 "f") <> "\n\n= term\n  @column-widths 4zw\n  | h |\n  | --- |\n  | " <> T.replicate 8 "x " <> "|\n"
        (_, layout) <- layoutOk (style "page" 2) sourceText []
        let kept = [(poNumber p, poColumn p) | p <- plPages layout, (_, SLine ident) <- poSlots p, Just line <- [Map.lookup ident (plLines layout)], setLineText line == "term" || Map.member ident (plTableLines layout)]
        map fst kept @?= replicate 4 2,
      testCase "root ADR 0401 I2: table header and first row may occupy separate columns" $ do
        (_, layout) <- layoutOk (style "page" 2) ("@column-widths 4zw\n| " <> T.replicate 8 "h " <> "|\n| --- |\n| " <> T.replicate 8 "x " <> "|\n") []
        let tableSlots = [(poNumber page, poColumn page, ident) | page <- plPages layout, (_, SLine ident) <- poSlots page, Map.member ident (plTableLines layout)]
        map (\(page, column, _) -> (page, column)) tableSlots @?= [(1, 0), (1, 0), (1, 1), (1, 1)],
      testCase "root ADR 0401 I2: in one column a spread still needs the header and each row in one column" $ do
        let manuscript = "@page-break\n\n@column-widths 4zw\n| " <> T.replicate 8 "h " <> "|\n| --- |\n| " <> T.replicate 8 "x " <> "|\n| " <> T.replicate 8 "y " <> "|\n"
        (codes, _) <- buildMini fakeProvider True (style "spread" 1) manuscript []
        assertBool (show codes) (DiagnosticCode "G07042" `elem` codes)
        (twoColumns, _) <- buildMini fakeProvider True (style "spread" 2) manuscript []
        assertBool (show twoColumns) (DiagnosticCode "G07042" `notElem` twoColumns),
      testCase "root ADR 0401 I1: default and explicit column preserve item placement" $ do
        (_, omitted) <- layoutOk (style "" 2) (source 4 3) []
        (_, explicit) <- layoutOk (style "column" 2) (source 4 3) []
        positions omitted @?= positions explicit
        positions explicit @?= [(1, 1), (1, 1), (2, 0)],
      testCase "root ADR 0401 I2: page retains a whole list item across columns" $ do
        (_, layout) <- layoutOk (style "page" 2) (source 2 3) []
        positions layout @?= [(1, 0), (1, 1), (1, 1)],
      testCase "root ADR 0401 I2: page moves a list item that would cross a page" $ do
        (_, layout) <- layoutOk (style "page" 2) (source 4 3) []
        positions layout @?= replicate 3 (2, 0),
      testCase "root ADR 0401 I2: spread retains an item on physical pages two and three" $ do
        (_, layout) <- layoutOk (style "spread" 1) ("@page-break\n\n" <> source 2 3) []
        positions layout @?= [(2, 0), (3, 0), (3, 0)],
      testCase "root ADR 0401 I2: spread moves an item across physical pages three and four" $ do
        (_, layout) <- layoutOk (style "spread" 1) ("@page-break\n\n" <> source 5 2) []
        positions layout @?= replicate 2 (4, 0),
      testCase "root ADR 0401 I3: oversized item notice occurs once at its original source span" $ do
        (_, layout) <- layoutOk (style "page" 1) (source 2 7) []
        positions layout @?= [(2, 0), (2, 0), (2, 0), (3, 0), (3, 0), (3, 0), (4, 0)]
        let notices = filter ((== DiagnosticCode "G07133") . diagCode) (plNotices layout)
        length notices @?= 1
        case notices of
          [d] -> spanStart (diagSpan d) @?= BS.length (TE.encodeUtf8 (fst (T.breakOn "- " (source 2 7))))
          other -> assertFailure (show (length other))
    ]
  where
    style :: T.Text -> Int -> BS.ByteString
    style unit columns =
      replaceIn "lines = 30" "lines = 3" (replaceIn "columns = 1" ("columns = " <> T.pack (show columns) <> "\ncolumn-gap = \"1zw\"") horizontalStyle)
        <> (if T.null unit then BS.empty else TE.encodeUtf8 ("\n[composition]\nkeep-parts = \"" <> unit <> "\"\n"))
        <> "\n[paragraph-styles.body]\nkeep-first-lines = 1\nkeep-last-lines = 1\n"
    source filler count = T.intercalate "\\\n" (replicate filler "f") <> "\n\n- " <> T.intercalate "\\\n  " (replicate count "x") <> "\n"
    positions layout = [(poNumber p, poColumn p) | p <- plPages layout, (_, SLine ident) <- poSlots p, Just line <- [Map.lookup ident (plLines layout)], "x" `T.isSuffixOf` setLineText line]
