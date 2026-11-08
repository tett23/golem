{-# LANGUAGE MultiWayIf #-}

{- | The spaces before and after of paragraph styles that a file redefines
with @style-def, in HTML and EPUB against PDF (docs/adr/0217).

Each case builds a book to PDF, HTML and EPUB. In PDF, the lines that the
spaces put between the first block A and the next block B of a chapter
(g) are the distance of their first lines less that of the same book
without the keys of the spaces. In HTML and EPUB, the declaration of
margin-block-start that wins on B is that of the evaluator of the
cascade (CssCascade, in the tests of golem-html).
-}
module FileSpacesSpec (fileSpacesTests) where

import Codec.Archive.Zip (findEntryByPath, fromEntry, toArchive)
import Control.Monad (forM, forM_, unless)
import CssCascade (Elem (..), Page (..), Winner (..), pageOf, winningMarginStarts)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Assemble (Book)
import Golem.Driver
import Golem.Layout.Paginate (PageOut (..))
import Golem.LayoutSpec (pageGeometry)
import Golem.Project (Manifest (..), Project (..), ProjectFailure (..))
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Golem.Typeset (PdfInput (..), PdfLayout (..), layoutPdf)
import Support
import System.FilePath ((</>))
import Test.Tasty
import Test.Tasty.HUnit

-- | The keys of a paragraph style, by name.
type Keys = [(Text, Text)]

-- | A case: the styles of style.toml, the chapters (definitions of the file, source), the chapters to check.
data Case = Case
  { caseName :: String,
    caseStyles :: [(Text, Keys)],
    caseChapters :: [([(Text, Keys)], Text)],
    caseChecked :: [Int]
  }

spaceKeys :: [Text]
spaceKeys = ["space-before", "space-after", "space-between"]

{- | The same book without spaces: every key of the spaces 0, in style.toml
and in the files, for the styles of the case and the built-in verse, whose
spaces are not 0 by default.
-}
withoutSpaces :: Case -> Case
withoutSpaces c =
  c
    { caseStyles = [(n, zero (concat [ks | (m, ks) <- caseStyles c, m == n])) | n <- names],
      caseChapters = [([(n, zero ks) | (n, ks) <- defs], src) | (defs, src) <- caseChapters c]
    }
  where
    names = foldr (\n acc -> if n `elem` acc then acc else n : acc) [] (map fst (caseStyles c) <> [n | (defs, _) <- caseChapters c, (n, _) <- defs] <> ["verse"])
    zero ks = filter ((`notElem` spaceKeys) . fst) ks <> [(k, "0") | k <- spaceKeys]

styleOf :: Case -> BS.ByteString
styleOf c =
  figStyle horizontalStyle
    <> TE.encodeUtf8 (T.concat ["\n[paragraph-styles." <> n <> "]\n" <> T.concat [k <> " = " <> v <> "\n" | (k, v) <- ks] | (n, ks) <- caseStyles c])

chaptersOf :: Case -> [(FilePath, Text)]
chaptersOf c =
  [ ("c" <> show i <> ".gm", T.concat ["@style-def paragraph " <> n <> T.concat [" " <> k <> "=" <> v | (k, v) <- ks] <> "\n" | (n, ks) <- defs] <> (if null defs then "" else "\n") <> src <> (if i < length (caseChapters c) then "@page-break\n" else ""))
  | (i, (defs, src)) <- zip [1 :: Int ..] (caseChapters c)
  ]

evaluatedOk :: FilePath -> IO (Evaluated, Book)
evaluatedOk tmp = do
  ev <- evaluateProject Dev tmp
  case ev of
    Left f -> assertFailure (show (pfDiagnostics f))
    Right e -> case (evBook e, filter isError (evDiagnostics e)) of
      (Just book, []) -> pure (e, book)
      (_, errs) -> assertFailure (show [(diagCode d, diagMessage d) | d <- errs])

-- | What a build of a case gives: the grid lines of each chapter's page, and the CSS and pages of HTML and EPUB.
data Outputs = Outputs
  { bSlots :: [[Int]],
    bHtml :: (Text, [Page]),
    bEpub :: (Text, [Page])
  }

buildCase :: Case -> IO Outputs
buildCase c = do
  img <- tinyImage
  withChapters (styleOf c) (chaptersOf c) [] $ \tmp -> do
    writeFiles tmp img
    (e, book) <- evaluatedOk tmp
    geom <- either (assertFailure . show) pure (pageGeometry (FileId 0) False (evStyle e))
    r <- layoutPdf (PdfInput (diskFiles tmp) (evProject e) (evStyle e) book False [] Map.empty Nothing (localStylesOf e) (chapterMasters (evProject e)) (evStyleFile e) Map.empty (projectVarTexts (manifestVars (projectManifest (evProject e))))) geom fakeFonts
    pl <- either (assertFailure . show) pure r
    let slots = map (map fst . poSlots) (plPages pl)
    unless (length slots == length (caseChapters c)) (assertFailure ("a page a chapter: " <> show slots))
    res <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
    assertEqual "no errors" [] [(diagCode d, diagMessage d) | d <- filter isError (brDiagnostics res)]
    css <- TIO.readFile (tmp </> "build/html/style.css")
    pages <- forM (zip [1 :: Int ..] (caseChapters c)) $ \(i, _) -> pageOf <$> TIO.readFile (tmp </> "build/html/c" <> show i <> ".xhtml")
    archive <- toArchive <$> BL.readFile (tmp </> "build/epub/book.epub")
    let entry p = maybe (error ("no " <> p <> " in the EPUB")) (TE.decodeUtf8 . BL.toStrict . fromEntry) (findEntryByPath ("OEBPS/" <> p) archive)
        ecss = entry "style.css"
        epages = [pageOf (entry ("c" <> show i <> ".xhtml")) | (i, _) <- zip [1 :: Int ..] (caseChapters c)]
    pure (Outputs slots (css, pages) (ecss, epages))

-- | The value that wins on each element of the page.
winners :: (Text, Page) -> [Maybe Text]
winners (css, page) = either (\e -> error ("the evaluator: " <> e)) (map (fmap wValue)) (winningMarginStarts css page)

{- | H1 to H3 on the checked chapters of a case, in HTML and EPUB: the
first block of the chapter is A, the next B, or a blank line and then B.
-}
checkCase :: Case -> IO ()
checkCase c = do
  keyed <- buildCase c
  plain <- buildCase (withoutSpaces c)
  forM_ (caseChecked c) $ \i -> do
    let gapOf b = case bSlots b !! i of
          (s0 : s1 : _) -> s1 - s0
          other -> error ("two lines on the page of chapter " <> show (i + 1) <> ": " <> show other)
        g = gapOf keyed - gapOf plain
    forM_ [("HTML", bHtml), ("EPUB", bEpub)] $ \(target, part) -> do
      let (css, pages) = part keyed
          page = pages !! i
          blank = case pgBlocks page of
            (_ : Elem "div" ["blank-line"] : _) -> True
            _ -> False
          bAt = if blank then 2 else 1
          ws = winners (css, page)
          (pcss, ppages) = part plain
          ws0 = winners (pcss, ppages !! i)
          same = case pgBlocks page of
            (a : b : _) -> elName a == "p" && a == b
            _ -> False
          what = target <> " chapter " <> show (i + 1) <> " " <> show (pgBody page, take (bAt + 1) (pgBlocks page)) <> ", g = " <> show g
      if
        | blank -> assertEqual ("H3: " <> what) (Just "0") (ws !! bAt)
        | g > 0 -> assertEqual ("H1: " <> what) (Just (T.pack (show g) <> "em")) (ws !! bAt)
        | not same -> assertEqual ("H2: " <> what) (ws0 !! bAt) (ws !! bAt)
        | otherwise -> pure ()

para :: Text -> Text -> Text
para style t = (if style == "body" then "" else "@style " <> style <> "\n") <> t <> "\n\n"

-- | The cases: each value of each axis of the table of docs/adr/0217 appears in one at least.
cases :: [Case]
cases =
  [ -- the reproduction of the ADR: the space after put back to 0
    Case "a space after put back to 0, then body" [("a", [("space-after", "2")])] [([("a", [("space-after", "0"), ("indent", "1zw")])], para "a" "あ。" <> para "body" "い。")] [0],
    -- the pair: style.toml 1 after, 3 before; the file puts the space before back to 0
    Case "a pair whose space before is put back to 0" [("a", [("space-after", "1")]), ("b", [("space-before", "3")])] [([("b", [("space-before", "0"), ("indent", "1zw")])], para "a" "あ。" <> para "b" "い。")] [0],
    Case "a smaller space after, a pair" [("a", [("space-after", "2")]), ("b", [("space-before", "1")])] [([("a", [("space-after", "1"), ("indent", "1zw")])], para "a" "あ。" <> para "b" "い。")] [0],
    Case "the same space after, then body" [("a", [("space-after", "1")])] [([("a", [("space-after", "1"), ("indent", "1zw")])], para "a" "あ。" <> para "body" "い。")] [0],
    Case "a greater space after, then a heading" [("a", [("space-after", "1")])] [([("a", [("space-after", "2"), ("indent", "1zw")])], para "a" "あ。" <> "## 見出し\n\n")] [0],
    Case "both put back to 0" [("a", [("space-after", "2")]), ("b", [("space-before", "3")])] [([("a", [("space-after", "0"), ("indent", "1zw")]), ("b", [("space-before", "0"), ("indent", "1zw")])], para "a" "あ。" <> para "b" "い。")] [0],
    Case "a definition without the keys of the spaces, then a list" [("a", [("space-after", "2")])] [([("a", [("indent", "1zw")])], para "a" "あ。" <> "- 項目\n\n")] [0],
    Case "A not defined, B defined greater" [("a", [("space-after", "2")]), ("b", [("space-before", "1")])] [([("b", [("space-before", "3"), ("indent", "1zw")])], para "a" "あ。" <> para "b" "い。")] [0],
    Case "B not defined, A defined, then a code block" [("a", [("space-after", "2")])] [([("a", [("space-after", "1"), ("indent", "1zw")])], para "a" "あ。" <> "```\ncode\n```\n\n")] [0],
    Case "A is body put back to 0" [("body", [("space-after", "1")]), ("b", [])] [([("body", [("space-after", "0"), ("indent", "1zw")])], para "body" "あ。" <> para "b" "い。")] [0],
    Case "B is body, its space before put back to 0" [("a", [("space-after", "0")]), ("body", [("space-before", "1")])] [([("body", [("space-before", "0"), ("indent", "1zw")])], para "a" "あ。" <> para "body" "い。")] [0],
    Case "a style that keeps its lines put back to 0" [] [([("verse", [("space-after", "0"), ("indent", "3zw")])], "@style verse\nあ\n\n" <> para "body" "い。")] [0],
    Case "the same style, space-between of the file" [("a", [("space-before", "1"), ("space-after", "2"), ("space-between", "1")])] [([("a", [("space-between", "2"), ("indent", "1zw")])], para "a" "あ。" <> para "a" "い。")] [0],
    Case "a blank line before a space before of the file" [("a", [("space-after", "2")]), ("b", [("space-before", "3")])] [([("b", [("space-before", "2"), ("indent", "1zw")])], para "a" "あ。" <> "@blank-line\n\n" <> para "b" "い。")] [0],
    Case "a space before from 0, then a table" [("a", [("space-after", "1")])] [([("a", [("space-after", "2"), ("indent", "1zw")])], para "a" "あ。" <> "| a | b |\n|---|---|\n| c | d |\n\n")] [0],
    Case "a space after put back to 0, then a figure" [("a", [("space-after", "2")])] [([("a", [("space-after", "0"), ("indent", "1zw")])], para "a" "あ。" <> "@figure images/tiny.jpg alt=\"t\"\n  キャプション。\n\n")] [0],
    Case
      "two files define the style with different values; the pages of a file that does not"
      [("a", [("space-after", "1")])]
      [ ([("a", [("space-after", "0"), ("indent", "1zw")])], para "a" "あ。" <> para "body" "い。"),
        ([], para "a" "あ。" <> para "body" "い。"),
        ([("a", [("space-after", "3"), ("indent", "1zw")])], para "a" "あ。" <> para "body" "い。")
      ]
      [0, 1, 2]
  ]

fileSpacesTests :: [TestTree]
fileSpacesTests =
  [testCase ("H1 to H3: " <> caseName c) (checkCase c) | c <- cases]
    <> [ testCase "H6: the same input writes the same style.css" $ do
           let c = last cases
           a <- buildCase c
           b <- buildCase c
           fst (bHtml a) @?= fst (bHtml b)
       ]
