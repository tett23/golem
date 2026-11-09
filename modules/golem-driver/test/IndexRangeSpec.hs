{- | The pages, the references and the section headings of the index in
the PDF (docs/adr/0265): I4, I5 and I7 by the lines of 'indexLines', and
G07118 and G07119 through the layout.
-}
module IndexRangeSpec (indexRangeTests) where

import Control.Monad (forM_, replicateM)
import Data.ByteString qualified as BS
import Data.Either (fromLeft)
import Data.List (nub, sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Assemble (IndexGroup (..), IndexLocator (..), IndexSection (..))
import Golem.Assemble.Formats (notationNamed)
import Golem.Doc.IR (InlineF (..), SeeKind (..))
import Golem.Driver
import Golem.Layout.PageLabel (PageLabel (..), plainLabel)
import Golem.LayoutSpec (pageGeometry)
import Golem.Project
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Golem.TestSupport.Manifest
import Golem.Typeset (IndexLine (..), PdfInput (..), indexLineInlines, indexLines, layoutPdf)
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

sp :: Int -> SrcSpan
sp i = mkSpan (FileId 0) i (i + 1)

at :: Int -> (FileId, SrcSpan)
at i = (FileId 0, sp i)

-- | An element of the pages of an entry: a page, or the pages from one to another.
data Element = Point Int | Range Int Int
  deriving stock (Eq, Show)

{- | The labels of the pages 1 to 5 of a book whose sections start at the
pages given (1 among them): the number of a page its place, so that the
text tells the places.
-}
labelsOf :: [Int] -> Map.Map Int PageLabel
labelsOf firsts = Map.fromList [(p, PageLabel p (toInteger p) Nothing (maximum [f | f <- firsts, f <= p])) | p <- [1 .. 5]]

{- | The locators of the elements and the page of each mark: the marks of
the element i at 10 i and 10 i + 1.
-}
locatorsOf :: Map.Map Int PageLabel -> [Element] -> ([IndexLocator], Map.Map SrcSpan PageLabel)
locatorsOf labels es =
  ( [either (AtMark . at) (\(a, b) -> Between (at a) (at b)) m | (m, _) <- marks],
    Map.fromList (concat [either (\a -> [(sp a, page p)]) (\(a, b) -> [(sp a, page p), (sp b, page q)]) m | (m, (p, q)) <- marks])
  )
  where
    page p = labels Map.! p
    marks =
      [ case e of
          Point p -> (Left (10 * i), (p, p))
          Range a b -> (Right (10 * i, 10 * i + 1), (a, b))
      | (i, e) <- zip [0 ..] es
      ]

-- | The text of a line.
textOf :: IndexLine -> Text
textOf = rendered . indexLineInlines

-- | The pages of the line of one entry, read back: each element as its first and last page.
pagesOfLine :: Text -> [(Int, Int)]
pagesOfLine t = case T.splitOn "　" t of
  [_, ps] -> [element (T.splitOn "–" e) | e <- T.splitOn ", " ps]
  _ -> []
  where
    element = \case
      [a] -> (num a, num a)
      [a, b] -> (num a, num b)
      other -> error (show other)
    num = read . T.unpack

-- | The lines of one entry of the elements, without a heading.
entryLines :: Map.Map Int PageLabel -> [Element] -> [Text]
entryLines labels es =
  let (locs, pages) = locatorsOf labels es
   in map textOf (indexLines False False (`Map.lookup` pages) [IndexSection "か" [IndexGroup ["語"] ["ご"] locs []]])

-- | Every element of the pages 1 to 5: a page, or two pages in order.
elements :: [Element]
elements = map Point [1 .. 5] <> [Range a b | a <- [1 .. 5], b <- [a .. 5]]

covers :: Element -> [Int]
covers = \case
  Point p -> [p]
  Range a b -> [a .. b]

-- | One section, entries of the groups.
oneSection :: [IndexGroup] -> [IndexSection]
oneSection gs = [IndexSection "か" gs]

indexRangeTests :: TestTree
indexRangeTests =
  testGroup
    "the pages, the references and the headings of the index in the PDF (docs/adr/0265)"
    [ testCase "I4: up to three elements of the pages 1 to 5, in a book of one section and of sections at 1 and 3" $
        forM_ [[1], [1, 3]] $ \firsts -> do
          let labels = labelsOf firsts
              sectionOf p = maximum [f | f <- firsts, f <= p]
              -- a range across sections is G07119
              allowed = [e | e <- elements, case e of Range a b -> sectionOf a == sectionOf b; _ -> True]
          forM_ (concat [replicateM n allowed | n <- [1 .. 3]]) $ \es -> do
            let out = case entryLines labels es of
                  [l] -> pagesOfLine l
                  other -> error (show other)
                info = show (firsts, es, out)
            -- the pages covered are the same
            assertEqual info (nub (sort (concatMap covers es))) (concat [[a .. b] | (a, b) <- out])
            -- strictly increasing, apart, and split at the first page of a section
            forM_ (zip out (drop 1 out)) $ \((_, b), (c, _)) ->
              assertBool info (c - b >= 2 || (c == b + 1 && c `elem` firsts))
            -- a range covers two pages or more, within one section
            forM_ out $ \(a, b) -> assertBool info (a <= b && sectionOf a == sectionOf b),
      testCase "I4: two pages next to each other are a range; three too; one apart are not" $ do
        let labels = labelsOf [1]
        entryLines labels [Point 5, Point 4] @?= ["語　4–5"]
        entryLines labels [Point 1, Point 2, Point 3] @?= ["語　1–3"]
        entryLines labels [Point 1, Point 3] @?= ["語　1, 3"]
        entryLines labels [Point 2, Point 2] @?= ["語　2"]
        entryLines labels [Range 2 2] @?= ["語　2"]
        entryLines labels [Range 2 4, Point 3, Point 5] @?= ["語　2–5"]
        entryLines labels [Range 3 5, Point 1] @?= ["語　1, 3–5"],
      testCase "I4: pages next to each other across sections are not a range" $
        entryLines (labelsOf [1, 3]) [Point 2, Point 3] @?= ["語　2, 3"],
      testCase "I4: the ends are page labels; the front matter xii and the body 1 stay apart" $ do
        let front = PageLabel 12 12 (notationNamed "lower-roman") 1
            body = PageLabel 13 1 Nothing 13
            pages = Map.fromList [(sp 0, front), (sp 1, body)]
        map textOf (indexLines False False (`Map.lookup` pages) (oneSection [IndexGroup ["語"] ["ご"] [AtMark (at 0), AtMark (at 1)] []])) @?= ["語　xii, 1"],
      testCase "I4: a range is joined by an en dash across, a wave dash down" $ do
        let pages = Map.fromList [(sp 0, plainLabel 3), (sp 1, plainLabel 4), (sp 2, plainLabel 12)]
            groups = oneSection [IndexGroup ["組版"] ["くみはん"] [AtMark (at 0), AtMark (at 1), AtMark (at 2)] []]
        map textOf (indexLines False False (`Map.lookup` pages) groups) @?= ["組版　3–4, 12"]
        map textOf (indexLines True False (`Map.lookup` pages) groups) @?= ["組版　3〜4、12"],
      testCase "I5: an automatic reference of an entry without pages is を見よ, with pages をも見よ" $ do
        let pages = Map.fromList [(sp i, plainLabel p) | (i, p) <- [(0, 12), (1, 13), (2, 18), (3, 25)]]
            groups =
              oneSection
                [ IndexGroup ["タイプセッティング"] ["たいぷせってぃんぐ"] [] [(SeeAuto, ["組版"])],
                  IndexGroup ["組版"] ["くみはん"] [Between (at 0) (at 2), AtMark (at 1), AtMark (at 3)] [(SeeAuto, ["印刷"])],
                  IndexGroup ["和文"] ["わぶん"] [] [(SeeAuto, ["組版", "和文組版"]), (SeeAlso, ["組版"])]
                ]
        map textOf (indexLines False False (`Map.lookup` pages) groups)
          @?= ["タイプセッティング（組版を見よ）", "組版　12–18, 25（印刷をも見よ）", "和文（組版：和文組版を見よ）（組版をも見よ）"],
      testCase "I7: the inputs of the lines of before, without headings, are the lines of before" $ do
        let pages = Map.map plainLabel (Map.fromList [(sp 1, 3), (sp 2, 3), (sp 3, 10), (sp 4, 12)])
            groups =
              oneSection
                [ IndexGroup ["組版"] ["くみはん"] [AtMark (at 1), AtMark (at 2)] [],
                  IndexGroup ["組版", "和文組版"] ["くみはん", "わぶんくみはん"] [AtMark (at 3)] [],
                  IndexGroup ["和文"] ["わぶん"] [AtMark (at 4)] []
                ]
        map textOf (indexLines False False (`Map.lookup` pages) groups) @?= ["組版　3", "　和文組版　10", "和文　12"]
        map textOf (indexLines False False (const (Just (plainLabel 5))) (oneSection [IndexGroup ["組版", "和文組版"] ["くみはん", "わぶんくみはん"] [AtMark (at 1)] []])) @?= ["組版", "　和文組版　5"],
      testCase "I7: the pages next to each other of before become a range" $ do
        let pages = Map.map plainLabel (Map.fromList [(sp 1, 3), (sp 2, 4), (sp 3, 5), (sp 4, 12)])
            groups = oneSection [IndexGroup ["組版"] ["くみはん"] [AtMark (at 4), AtMark (at 2), AtMark (at 1), AtMark (at 3)] []]
        map textOf (indexLines False False (`Map.lookup` pages) groups) @?= ["組版　3–5, 12"]
        map textOf (indexLines True False (`Map.lookup` pages) groups) @?= ["組版　3〜5、12"],
      testCase "the headings: a paragraph of strong before the entries of each section" $ do
        let pages = Map.fromList [(sp 1, plainLabel 3), (sp 2, plainLabel 7)]
            sections = [IndexSection "か" [IndexGroup ["組版"] ["くみはん"] [AtMark (at 1)] []], IndexSection "わ" [IndexGroup ["和文"] ["わぶん"] [AtMark (at 2)] []]]
            ls = indexLines False True (`Map.lookup` pages) sections
        map textOf ls @?= ["か", "組版　3", "わ", "和文　7"]
        [[n | CharStyle _ n _ <- is] | IndexHeadingLine is <- ls] @?= [["strong"], ["strong"]]
        length [() | IndexEntryLine _ <- ls] @?= 2
        map textOf (indexLines False False (`Map.lookup` pages) sections) @?= ["組版　3", "和文　7"],
      testCase "the PDF of an index of a range, a reference and headings: the heading before its first entry" $ do
        let source =
              "# 一\n\n本文[index reading=くみはん range=begin: 組版]。\n\n"
                <> T.replicate 6 "い\n\n"
                <> "本文[index reading=くみはん range=end: 組版][index reading=はん see=組版: 版][index reading=あい: 藍]。\n\n@index\n"
        r <- pagesMini "" (fiveLines <> flatHeadings) source [] mempty
        pages <- either (assertFailure . show) pure r
        let entries = ["あ", "藍　2", "か", "組版　1–2", "は", "版（組版を見よ）"]
        take 6 (dropWhile (/= "あ") (concat pages)) @?= entries
        -- each heading on the page of its first entry (docs/adr/0261)
        forM_ [("あ", "藍　2"), ("か", "組版　1–2"), ("は", "版（組版を見よ）")] $ \(h, e) ->
          assertBool (show pages) (any (\ls -> h `elem` ls && e `elem` ls) pages),
      testCase "G07119: a range from the front matter into the body, at its begin" $ do
        let preface = "# はじめに\n\n前付け[index reading=ご range=begin: 語]。\n"
            sources =
              [ ("preface.gm", preface),
                ("one.gm", "# 第一章\n\n本文[index reading=ご range=end: 語]。\n\n@index\n")
              ]
            manifest = manifestOf [numbered "preface.gm" "{ style = \"lower-roman\" }", numbered "one.gm" "{ style = \"arabic\", start = 1 }"]
        ds <- bookLayoutErrors manifest fiveLines sources
        [(codeOf d, spanStart (diagSpan d)) | d <- ds] @?= [("G07119", offsetOf "[index reading=ご range=begin" preface)],
      testCase "G07118: a range whose end is on a page before its begin, at its begin" $ do
        -- the figure of the begin mark goes on to the next page; the end mark stays on the page before
        let source = "# 一\n\nあ\n\nあ\n\n@figure images/tall.svg alt=\"t\"\n  図[index reading=ご range=begin: 語]。\n\n本文[index reading=ご range=end: 語]。\n\n@index\n"
        r <- layoutMini fiveLines source [("images/tall.svg", tallSvg)]
        case r of
          Left ds -> map codeOf ds @?= ["G07118"]
          Right _ -> assertFailure "no G07118"
    ]

codeOf :: Diagnostic -> Text
codeOf d = let DiagnosticCode c = diagCode d in c

-- | A manifest of the chapter entries given, written as TOML, for the PDF.
manifestOf :: [Text] -> BS.ByteString
manifestOf entries =
  TE.encodeUtf8 ("chapters = [" <> T.intercalate ", " entries <> "]\n" <> T.dropWhile (/= '\n') (manifestToml testManifest {tmTargets = ["pdf"]}))

-- | An entry of a file with page-numbering.
numbered :: Text -> Text -> Text
numbered file pn = "{ file = \"" <> file <> "\", page-numbering = " <> pn <> " }"

-- | The byte offset of the first occurrence of a text in another.
offsetOf :: Text -> Text -> Int
offsetOf needle hay = BS.length (TE.encodeUtf8 (fst (T.breakOn needle hay)))

-- | A box of 100 by 300.
tallSvg :: BS.ByteString
tallSvg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"300\"><rect width=\"100\" height=\"300\" fill=\"none\"/></svg>"

-- | The errors of the layout of a project with the fake fonts.
bookLayoutErrors :: BS.ByteString -> BS.ByteString -> [(FilePath, Text)] -> IO [Diagnostic]
bookLayoutErrors manifest style sources = withSystemTempDirectory "golem-index" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") manifest
  BS.writeFile (tmp </> "style.toml") style
  writeTexts tmp sources
  ev <- evaluateProject Dev tmp
  case ev of
    Left f -> assertFailure (show (pfDiagnostics f))
    Right e -> case (evBook e, pageGeometry (FileId 0) False (evStyle e)) of
      _ | errs@(_ : _) <- filter isError (evDiagnostics e) -> assertFailure (show errs)
      (Just book, Right geom) -> do
        let inp = PdfInput (diskFiles tmp) (evProject e) (evStyle e) book False [] Map.empty Nothing (localStylesOf e) (chapterMasters (evProject e)) (evStyleFile e) Map.empty (projectVarTexts (manifestVars (projectManifest (evProject e)))) (evStyleText e)
        r <- layoutPdf inp geom fakeFonts
        pure (fromLeft [] r)
      (_, Left ds) -> assertFailure (show ds)
      (Nothing, _) -> assertFailure "no book"
