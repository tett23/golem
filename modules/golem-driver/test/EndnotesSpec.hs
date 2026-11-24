{- | The endnotes: a channel apart from the notes and the sidenotes,
always at the end of the chapter (root ADR 0412).
-}
module EndnotesSpec (endnoteTests, baseStyle, buildIn, epubPage, fileText, pdfLinesIn, twoChapters) where

import Codec.Archive.Zip (findEntryByPath, fromEntry, toArchive)
import Control.Monad (forM_, replicateM, when)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Char (isDigit)
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Project (Manifest (..), Project (..), ProjectFailure (..))
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Golem.Typeset (PdfInput (..), layoutPages)
import Support hiding (codesOf)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | The kinds of notes a paragraph of a test source calls.
data Kind = KNote | KSidenote | KEndnote
  deriving stock (Eq, Show, Enum, Bounded)

-- | The values of [notes] numbering, [endnotes] numbering and [notes] placement.
data Config = Config
  { cNotes :: !Text,
    cEndnotes :: !Text,
    cPlacement :: !Text
  }
  deriving stock (Eq, Show)

-- | Two chapters, a file each; with sidenotes, which need their column.
twoChapters :: BS.ByteString
twoChapters = replaceIn "chapters = [\"a.gm\"]" "chapters = [\"a.gm\", \"b.gm\"]" miniManifest

baseStyle :: BS.ByteString
baseStyle = sidenoteStyleWith ""

styleOf :: Config -> BS.ByteString
styleOf c =
  baseStyle
    <> "\n[notes]\nnumbering = \""
    <> TE.encodeUtf8 (cNotes c)
    <> "\"\nplacement = \""
    <> TE.encodeUtf8 (cPlacement c)
    <> "\"\n\n[endnotes]\nnumbering = \""
    <> TE.encodeUtf8 (cEndnotes c)
    <> "\"\n"

{- | The body of the k-th note of the book (from 0): a character of its
own, which no mark has.
-}
bodyOf :: Int -> Text
bodyOf k = T.singleton (toEnum (fromEnum 'ア' + 2 * k))

-- | A paragraph that calls a note of a kind: a character of the kind, then the note.
paragraphOf :: Int -> Kind -> Text
paragraphOf k = \case
  KNote -> "脚[note: " <> bodyOf k <> "]\n\n"
  KSidenote -> "傍[sidenote: " <> bodyOf k <> "]\n\n"
  KEndnote -> "後[endnote: " <> bodyOf k <> "]\n\n"

-- | The sources of the two chapters, each kind a paragraph, the bodies numbered through the book.
sourcesOf :: ([Kind], [Kind]) -> [(FilePath, Text)]
sourcesOf (xs, ys) =
  [ ("a.gm", T.concat (zipWith paragraphOf [0 ..] xs)),
    ("b.gm", T.concat (zipWith paragraphOf [length xs ..] ys))
  ]

-- | The endnotes of each chapter: the number each takes and its body.
expectedEndnotes :: Config -> ([Kind], [Kind]) -> [[(Int, Text)]]
expectedEndnotes c (xs, ys) =
  let bodies ks from = [bodyOf k | (k, KEndnote) <- zip [from ..] ks]
      first = bodies xs 0
      second = bodies ys (length xs)
   in case cEndnotes c of
        "book" -> [zip [1 ..] first, zip [length first + 1 ..] second]
        _ -> [zip [1 ..] first, zip [1 ..] second]

-- | What a line of the PDF is: the paragraph of a kind, the title of a list, or an entry of one.
data Line
  = LPara Kind Text
  | LTitle Text
  | LEntry Text Text
  deriving stock (Eq, Show)

-- | A line of the PDF read: a paragraph starts with the character of its kind; an entry ends with its body.
readLine :: Text -> Line
readLine t = case T.uncons t of
  Just ('脚', rest) -> LPara KNote rest
  Just ('傍', rest) -> LPara KSidenote rest
  Just ('後', rest) | T.all isDigit rest, not (T.null rest) -> LPara KEndnote rest
  _
    | t `elem` ["注", "後注", "Notes", "Endnotes"] -> LTitle t
    | otherwise -> LEntry (T.dropEnd 1 t) (T.takeEnd 1 t)

{- | The lines the PDF has: the paragraphs of each chapter, then the list
of its footnotes when they are at the end of the chapter (their marks
are left out, which numbering = "page" decides on the pages), then the
list of its endnotes, numbered (root ADR 0412 I1, I2, I4).
-}
expectedPdf :: Config -> ([Kind], [Kind]) -> [Line] -> Bool
expectedPdf c input@(xs, ys) = go (zip3 [xs, ys] [0, length xs] (expectedEndnotes c input))
  where
    go [] rest = null rest
    go ((ks, from, ens) : more) rest =
      let paras = length ks
          (ps, rest1) = splitAt paras rest
          paraOk = and (zipWith paraLine ks ps) && length ps == paras && endnoteMarks ps == map fst ens
          notes = [bodyOf k | (k, KNote) <- zip [from ..] ks]
          (rest2, notesOk)
            | cPlacement c == "chapter-end" && not (null notes) = case rest1 of
                LTitle "注" : r -> let (es, r') = splitAt (length notes) r in (r', [b | LEntry m b <- es, "*" `T.isPrefixOf` m] == notes)
                _ -> (rest1, False)
            | otherwise = (rest1, True)
          (rest3, endOk)
            | null ens = (rest2, True)
            | otherwise = case rest2 of
                LTitle "後注" : r -> let (es, r') = splitAt (length ens) r in (r', es == [LEntry (tshow n) b | (n, b) <- ens])
                _ -> (rest2, False)
       in paraOk && notesOk && endOk && go more rest3
    paraLine k = \case
      LPara k' _ -> k == k'
      _ -> False
    endnoteMarks ps = [read (T.unpack n) | LPara KEndnote n <- ps]

tshow :: Int -> Text
tshow = T.pack . show

-- | The lines of each page of the PDF, as text.
pdfLines :: BS.ByteString -> BS.ByteString -> [(FilePath, Text)] -> IO (Either [Diagnostic] [[Text]])
pdfLines manifest style sources = withSystemTempDirectory "golem-endnotes" $ \tmp -> pdfLinesIn tmp manifest style sources

-- | 'pdfLines' in a directory, whose files it writes over.
pdfLinesIn :: FilePath -> BS.ByteString -> BS.ByteString -> [(FilePath, Text)] -> IO (Either [Diagnostic] [[Text]])
pdfLinesIn tmp manifest style sources = do
  BS.writeFile (tmp </> "manifest.toml") manifest
  BS.writeFile (tmp </> "style.toml") style
  writeTexts tmp sources
  ev <- evaluateProject Dev tmp
  case ev of
    Left f -> pure (Left (pfDiagnostics f))
    Right e -> case (evBook e, filter isError (evDiagnostics e)) of
      (Just book, []) -> layoutPages fakeProvider (PdfInput (diskFiles tmp) (evProject e) (evStyle e) book False [] Map.empty Nothing (localStylesOf e) (chapterMasters (evProject e)) (evStyleFile e) Map.empty (projectVarTexts (manifestVars (projectManifest (evProject e)))) (evStyleText e))
      (_, ds) -> pure (Left ds)

{- | Builds the project for the targets: its diagnostics and the contents
of the files it wrote, by their names under the output folder.
-}
buildFor :: [Target] -> BS.ByteString -> BS.ByteString -> [(FilePath, Text)] -> IO ([Diagnostic], [(FilePath, BS.ByteString)])
buildFor targets manifest style sources = withSystemTempDirectory "golem-endnotes" $ \tmp -> buildIn tmp targets manifest style sources

-- | 'buildFor' in a directory, whose files it writes over.
buildIn :: FilePath -> [Target] -> BS.ByteString -> BS.ByteString -> [(FilePath, Text)] -> IO ([Diagnostic], [(FilePath, BS.ByteString)])
buildIn tmp targets manifest style sources = do
  BS.writeFile (tmp </> "manifest.toml") (manifest <> "\n[targets.html]\n\n[targets.epub]\n\n[targets.text]\nvariants = [\"horizontal\"]\n")
  BS.writeFile (tmp </> "style.toml") (withBodyFont style)
  writeFiles tmp (bodyFontFiles style)
  writeTexts tmp sources
  r <- build (defaultOptions tmp) {optTargets = Just targets, optFonts = fakeProvider}
  files <- mapM (\p -> (drop (length tmp + 1) p,) <$> BS.readFile p) (brWritten r)
  pure (brDiagnostics r, files)

-- | The text of a written file.
fileText :: [(FilePath, BS.ByteString)] -> FilePath -> Text
fileText files p = maybe "" TE.decodeUtf8 (lookup p files)

-- | A page of the EPUB.
epubPage :: [(FilePath, BS.ByteString)] -> FilePath -> Text
epubPage files p = case lookup "build/epub/book.epub" files of
  Just bytes -> maybe "" (TE.decodeUtf8 . BL.toStrict . fromEntry) (findEntryByPath p (toArchive (BL.fromStrict bytes)))
  Nothing -> ""

-- | The texts after each occurrence of a text, up to a quote.
idsAfter :: Text -> Text -> [Text]
idsAfter needle page = [T.takeWhile (/= '"') (T.drop (T.length needle) rest) | (_, rest) <- T.breakOnAll needle page]

{- | The endnotes of an HTML or EPUB page: the ids of the references in the
text, and the ids and the bodies of the list after the list of notes.
-}
data PageNotes = PageNotes
  { pnRefs :: [Text],
    pnEntries :: [(Text, Text)],
    pnTitle :: Maybe Text,
    pnNotesFirst :: Bool
  }
  deriving stock (Eq, Show)

pageNotes :: Text -> PageNotes
pageNotes page =
  let (before, section) = T.breakOn "<section class=\"endnotes\">" page
      entries = [(T.takeWhile (/= '"') rest, T.takeWhile (/= '<') (T.drop 3 (snd (T.breakOn "a> " rest)))) | open <- ["<aside epub:type=\"endnote\" id=\"endnote-", "<aside role=\"doc-endnote\" id=\"endnote-"], (_, r) <- T.breakOnAll open section, let rest = T.drop (T.length open) r]
      title = if T.null section then Nothing else Just (T.takeWhile (/= '<') (T.drop 4 (snd (T.breakOn "<h2>" section))))
      (beforeNotes, notes) = T.breakOn "<section class=\"notes\">" page
   in PageNotes (idsAfter "id=\"endnoteref-" before) entries title (T.null section || T.null notes || T.length beforeNotes <= T.length before)

-- | What a page of a chapter must have: the refs of its endnotes, then a list of them after that of the notes.
expectedPage :: [(Int, Text)] -> PageNotes
expectedPage ens = PageNotes (map (tshow . fst) ens) [(tshow n, b) | (n, b) <- ens] (if null ens then Nothing else Just "後注") True

{- | The endnotes of the plain text of a chapter: the list after the
title 後注, each its number and its body.
-}
textEndnotes :: Text -> [(Text, Text)]
textEndnotes t = case T.breakOn "\n後注\n" t of
  (_, rest) | not (T.null rest) -> [(T.takeWhile (/= ' ') (T.drop 1 l), T.drop 1 (T.dropWhile (/= ' ') l)) | l <- takeWhile ("*" `T.isPrefixOf`) (T.lines (T.drop 4 rest))]
  _ -> []

-- | The inputs: two chapters of up to @depth@ notes in all, of the three kinds.
inputs :: Int -> [([Kind], [Kind])]
inputs depth = [(xs, ys) | n <- [0 .. depth], a <- [0 .. n], xs <- seqs a, ys <- seqs (n - a)]
  where
    seqs k = replicateM k [minBound .. maxBound]

configs :: [Config]
configs = [Config n e p | n <- ["chapter", "file", "book", "page"], e <- ["chapter", "file", "book"], p <- ["page-foot", "chapter-end"]]

{- | How many notes the inputs have at most: 4 (root ADR 0412), or
GOLEM_ENUM_ENDNOTES_DEPTH.
-}
enumDepth :: IO Int
enumDepth = maybe 4 read <$> lookupEnv "GOLEM_ENUM_ENDNOTES_DEPTH"

-- | Checks one input in one configuration on the four outputs.
checkInput :: FilePath -> Config -> ([Kind], [Kind]) -> Assertion
checkInput dir c input = do
  let style = styleOf c
      sources = sourcesOf input
      ens = expectedEndnotes c input
      what = show c <> " " <> show input
  pdf <- pdfLinesIn dir twoChapters style sources
  case pdf of
    Left ds -> assertFailure (what <> ": " <> show ds)
    Right pages -> do
      let ls = map readLine (concat pages)
      assertBool (what <> " PDF: " <> show ls) (expectedPdf c input ls)
  (ds, files) <- buildIn dir [TargetHtml, TargetEpub, TargetText] twoChapters style sources
  assertEqual (what <> " errors") [] [diagCode d | d <- ds, isError d]
  forM_ (zip ["a", "b"] ens) $ \(name, chapterNotes) -> do
    assertEqual (what <> " HTML " <> name) (expectedPage chapterNotes) (pageNotes (fileText files ("build/html/" <> name <> ".html")))
    assertEqual (what <> " EPUB " <> name) (expectedPage chapterNotes) (pageNotes (epubPage files ("OEBPS/" <> name <> ".xhtml")))
    let text = fileText files ("build/text/horizontal/" <> name <> ".txt")
    assertEqual (what <> " text " <> name) [(tshow n, b) | (n, b) <- chapterNotes] (textEndnotes text)
    -- the list of the notes before that of the endnotes (root ADR 0412 I4)
    assertBool (what <> " text order " <> name) (let (n, rest) = T.breakOn "\n注\n" text in T.null rest || T.length n <= T.length (fst (T.breakOn "\n後注\n" text)))

endnoteTests :: [TestTree]
endnoteTests =
  [ testGroup
      "root ADR 0412 I1, I2, I4: every input of up to four notes of the three kinds in two chapters, in the four outputs"
      [ testCase ("[notes] numbering = " <> T.unpack (cNotes c) <> ", [endnotes] numbering = " <> T.unpack (cEndnotes c) <> ", placement = " <> T.unpack (cPlacement c)) $ do
          depth <- enumDepth
          let is = inputs depth
          -- the inputs have endnotes in both chapters
          when (depth >= 2) $ assertBool "both chapters" (([KEndnote], [KEndnote]) `elem` is)
          -- one directory for the inputs of a configuration, each written over the one before
          withSystemTempDirectory "golem-endnotes" $ \dir -> forM_ is (checkInput dir c)
      | c <- configs
      ],
    testCase "root ADR 0412 I2: one endnote is 1 in the list at the end of its chapter" $ do
      pages <- pdfLines miniManifest baseStyle [("a.gm", "本文[endnote: 後の注。]\n")] >>= either (assertFailure . show) pure
      concat pages @?= ["本文1", "後注", "1後の注。"],
    testCase "root ADR 0412 I1: two notes and an endnote between them on the foot of the page: the notes 1 and 2, the endnote 1" $ do
      pages <- pdfLines miniManifest baseStyle [("a.gm", "甲[note: 一。]乙[endnote: 後。]丙[note: 二。]\n")] >>= either (assertFailure . show) pure
      concat pages @?= ["甲*1乙1丙*2", "後注", "1後。"],
    testCase "root ADR 0412 I4: the same with placement = \"chapter-end\": the list of the notes, then that of the endnotes" $ do
      let style = baseStyle <> "\n[notes]\nplacement = \"chapter-end\"\n"
      pages <- pdfLines miniManifest style [("a.gm", "甲[note: 一。]乙[endnote: 後。]丙[note: 二。]\n")] >>= either (assertFailure . show) pure
      concat pages @?= ["甲*1乙1丙*2", "注", "*1一。", "*2二。", "後注", "1後。"]
      (_, files) <- buildFor [TargetHtml] miniManifest style [("a.gm", "甲[note: 一。]乙[endnote: 後。]丙[note: 二。]\n")]
      let page = fileText files "build/html/a.html"
      assertBool "notes first" (T.length (fst (T.breakOn "<section class=\"notes\">" page)) < T.length (fst (T.breakOn "<section class=\"endnotes\">" page)))
      pageNotes page @?= PageNotes ["1"] [("1", "後。")] (Just "後注") True
      assertBool "the title of the notes" ("<section class=\"notes\">\n<h2>注</h2>" `T.isInfixOf` page)
      assertBool "the mark of the endnote" ("<a role=\"doc-noteref\" class=\"endnoteref\" href=\"#endnote-1\" id=\"endnoteref-1\">1</a>" `T.isInfixOf` page)
      assertBool "the link back" ("<aside role=\"doc-endnote\" id=\"endnote-1\"><p><a href=\"#endnoteref-1\">1</a> 後。</p></aside>" `T.isInfixOf` page),
    testCase "root ADR 0412 I4: the title is Endnotes in an English book" $ do
      let manifest = replaceIn "language = \"ja\"" "language = \"en\"" miniManifest
      pages <- pdfLines manifest baseStyle [("a.gm", "Text[endnote: An endnote.]\n")] >>= either (assertFailure . show) pure
      assertBool (show pages) ("Endnotes" `elem` concat pages)
      (_, files) <- buildFor [TargetHtml, TargetText] manifest baseStyle [("a.gm", "Text[endnote: An endnote.]\n")]
      pnTitle (pageNotes (fileText files "build/html/a.html")) @?= Just "Endnotes"
      assertBool "text" ("\nEndnotes\n*1 An endnote." `T.isInfixOf` fileText files "build/text/horizontal/a.txt"),
    testCase "root ADR 0412 I1, I2: endnotes in two chapters count from 1 in each" $ do
      pages <- pdfLines twoChapters baseStyle [("a.gm", "甲[endnote: 一。]\n"), ("b.gm", "乙[endnote: 二。]丙[endnote: 三。]\n")] >>= either (assertFailure . show) pure
      concat pages @?= ["甲1", "後注", "1一。", "乙1丙2", "後注", "1二。", "2三。"],
    testCase "root ADR 0412 I2: a file that ends with a page break: the list before the break" $ do
      pages <- pdfLines twoChapters baseStyle [("a.gm", "甲[endnote: 一。]\n\n@page-break\n"), ("b.gm", "乙\n")] >>= either (assertFailure . show) pure
      take 1 pages @?= [["甲1", "後注", "1一。"]]
      assertBool (show pages) ("乙" `elem` concat (drop 1 pages)),
    testCase "root ADR 0412 I2: an endnote of two paragraphs written with @endnote is one endnote" $ do
      let src = [("a.gm", "本文[endnote k]。\n\n@endnote k\n  一つめ。\n\n  二つめ。\n")]
      pages <- pdfLines miniManifest baseStyle src >>= either (assertFailure . show) pure
      concat pages @?= ["本文1。", "後注", "1一つめ。", "二つめ。"]
      (_, files) <- buildFor [TargetHtml, TargetText] miniManifest baseStyle src
      assertBool "html" ("<aside role=\"doc-endnote\" id=\"endnote-1\"><p><a href=\"#endnoteref-1\">1</a> 一つめ。</p><p>二つめ。</p></aside>" `T.isInfixOf` fileText files "build/html/a.html")
      assertBool "text" ("\n後注\n*1 一つめ。\n二つめ。\n" `T.isInfixOf` fileText files "build/text/horizontal/a.txt"),
    testCase "root ADR 0412 I5: [endnotes] numbering = \"page\" is G03278 and stops the build" $ do
      (ds, files) <- buildFor [TargetPdf, TargetHtml] miniManifest (baseStyle <> "\n[endnotes]\nnumbering = \"page\"\n") [("a.gm", "本文[endnote: 注。]\n")]
      [diagCode d | d <- ds, isError d] @?= [DiagnosticCode "G03278"]
      assertBool "nothing written" (not (any ((".pdf" `isSuffixOf`) . fst) files)),
    testCase "root ADR 0412: [endnotes] mark-format writes the marks of the PDF and the links of HTML" $ do
      let style = baseStyle <> TE.encodeUtf8 "\n[endnotes]\nmark-format = \"［{n:kanji}］\"\n"
      pages <- pdfLines miniManifest style [("a.gm", "甲[endnote: 一。]乙[endnote: 二。]\n")] >>= either (assertFailure . show) pure
      concat pages @?= ["甲［一］乙［二］", "後注", "［一］一。", "［二］二。"]
      (_, files) <- buildFor [TargetHtml] miniManifest style [("a.gm", "甲[endnote: 一。]\n")]
      assertBool "html" ("id=\"endnoteref-1\">一</a>" `T.isInfixOf` fileText files "build/html/a.html"),
    testCase "root ADR 0412: numbering = \"file\" in a chapter of two files: endnote-k-N and G03027 in every target" $ do
      let manifest = replaceIn "chapters = [\"a.gm\"]" "chapters = [[\"a.gm\", \"b.gm\"]]" miniManifest
          style = baseStyle <> "\n[endnotes]\nnumbering = \"file\"\n"
          src = [("a.gm", "甲[endnote: 一。]\n"), ("b.gm", "乙[endnote: 二。]\n")]
      (ds, files) <- buildFor [TargetHtml] manifest style src
      [diagSeverity d | d <- ds, diagCode d == DiagnosticCode "G03027"] @?= [Warning]
      idsAfter "id=\"endnoteref-" (fileText files "build/html/a.html") @?= ["1-1"]
      idsAfter "id=\"endnote-" (fileText files "build/html/b.html") @?= ["1-1", "2-1"]
      (pdfDs, _) <- buildFor [TargetPdf] manifest style src
      [diagSeverity d | d <- pdfDs, diagCode d == DiagnosticCode "G03027"] @?= [Warning]
      -- the notes numbered per file meet in no list of endnotes: none
      (noneDs, _) <- buildFor [TargetHtml] manifest (baseStyle <> "\n[notes]\nnumbering = \"file\"\n") src
      [d | d <- noneDs, diagCode d == DiagnosticCode "G03027"] @?= [],
    testCase "root ADR 0412 I3: a book without endnotes has no list of endnotes and the CSS of before" $ do
      (_, files) <- buildFor [TargetHtml] miniManifest baseStyle [("a.gm", "本文[note: 注。]\n")]
      assertBool "no endnotes" (not ("endnote" `T.isInfixOf` T.concat (map (TE.decodeUtf8 . snd) files)))
      (_, withEndnote) <- buildFor [TargetHtml] miniManifest baseStyle [("a.gm", "本文[endnote: 注。]\n")]
      assertBool "the CSS of the endnotes" ("section.endnotes aside p" `T.isInfixOf` fileText withEndnote "build/html/style.css")
  ]
