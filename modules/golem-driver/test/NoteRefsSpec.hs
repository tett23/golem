{- | References to notes: a label on a note, its number with [ref-number]
and the page of its mark with [ref-page] (root ADR 0422).
-}
module NoteRefsSpec (noteRefTests) where

import Control.Monad (forM, forM_, replicateM)
import Data.ByteString qualified as BS
import Data.Char (isDigit)
import Data.List (nub, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import EndnotesSpec (baseStyle, buildIn, epubPage, fileText, pdfLinesIn, twoChapters)
import Golem.Driver
import Golem.Layout.Japanese (BoxKind (..), boxKind)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Paginate (PageOutAt (..), Slotted (..))
import Golem.Project.Style (Sp (..))
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..), isError)
import Golem.Typeset (PdfLayout (..), SetLine (..))
import Support hiding (codesOf)
import System.Environment (lookupEnv)
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | The kinds of notes a paragraph of a test source calls.
data Kind = KNote | KSidenote | KEndnote
  deriving stock (Eq, Show, Enum, Bounded)

-- | The command of a kind.
command :: Kind -> Text
command = \case
  KNote -> "note"
  KSidenote -> "sidenote"
  KEndnote -> "endnote"

-- | A paragraph that calls a note of a kind; the labelled one starts with 印, the others with 他.
paragraphOf :: Bool -> Int -> Kind -> Text
paragraphOf labelled k kind =
  (if labelled then "印[" <> command kind <> " label=x: " else "他[" <> command kind <> ": ")
    <> T.singleton (toEnum (fromEnum 'ア' + k))
    <> "]\n\n"

{- | The two chapters of an input: a.gm a note of each kind, so that the
numbers of the book and of the chapter differ; b.gm the notes of the
input, the one at the index labelled, then the reference.
-}
sourcesOf :: [Kind] -> Int -> [(FilePath, Text)]
sourcesOf ks j =
  [ ("a.gm", T.concat (zipWith (paragraphOf False) [0 ..] [KNote, KSidenote, KEndnote])),
    ("b.gm", T.concat [paragraphOf (i == j) (3 + i) k | (i, k) <- zip [0 ..] ks] <> "参[ref-number x]\n")
  ]

styleOf :: Text -> Text -> BS.ByteString
styleOf notes endnotes = baseStyle <> "\n[notes]\nnumbering = \"" <> TE.encodeUtf8 notes <> "\"\n\n[endnotes]\nnumbering = \"" <> TE.encodeUtf8 endnotes <> "\"\n"

-- | The digits of a text, which no other digit is next to in the test sources.
digitsOf :: Text -> Text
digitsOf = T.filter isDigit

-- | The text after a prefix up to the end of its line, in the lines given.
lineAfter :: Text -> [Text] -> Maybe Text
lineAfter p ls = listToMaybe [rest | l <- ls, Just rest <- [T.stripPrefix p l]]

-- | Text without its tags.
withoutTags :: Text -> Text
withoutTags t = case T.breakOn "<" t of
  (before, rest)
    | T.null rest -> before
    | otherwise -> before <> withoutTags (T.drop 1 (T.dropWhile (/= '>') rest))

{- | In a page of HTML or EPUB: the mark of the labelled note (after the
empty span of its label, up to the end of the element of the mark) and
the reference (after 参, up to the end of its paragraph).
-}
htmlValues :: Text -> (Text, Text)
htmlValues page =
  let (_, atLabel) = T.breakOn "<span id=\"x\"></span>" page
      mark = withoutTags (fst (T.breakOn "</a>" (fst (T.breakOn "</sup>" (T.drop (T.length "<span id=\"x\"></span>") atLabel)))))
      (_, atRef) = T.breakOn "参" page
      ref = withoutTags (fst (T.breakOn "</p>" (T.drop 1 atRef)))
   in (digitsOf mark, digitsOf ref)

-- | Inputs of up to @depth@ notes of the three kinds, each with the index of the labelled one.
inputs :: Int -> [([Kind], Int)]
inputs depth = [(ks, j) | n <- [1 .. depth], ks <- replicateM n [minBound .. maxBound], j <- [0 .. n - 1]]

-- | How many notes the inputs have at most: 4 (root ADR 0422), or GOLEM_ENUM_NOTE_REFS_DEPTH.
enumDepth :: IO Int
enumDepth = maybe 4 read <$> lookupEnv "GOLEM_ENUM_NOTE_REFS_DEPTH"

-- | Checks one input in one configuration on the four outputs: the reference is the number of the mark.
checkInput :: FilePath -> Text -> Text -> ([Kind], Int) -> Assertion
checkInput dir notes endnotes (ks, j) = do
  let style = styleOf notes endnotes
      sources = sourcesOf ks j
      what = T.unpack notes <> "/" <> T.unpack endnotes <> " " <> show ks <> " " <> show j
  pdf <- pdfLinesIn dir twoChapters style sources
  case pdf of
    Left ds -> assertFailure (what <> ": " <> show ds)
    Right pages -> do
      let ls = concat pages
          mark = digitsOf <$> lineAfter "印" ls
          ref = digitsOf <$> lineAfter "参" ls
      assertBool (what <> " PDF has the mark: " <> show ls) (maybe False (not . T.null) mark)
      assertEqual (what <> " PDF") mark ref
  (ds, files) <- buildIn dir [TargetHtml, TargetEpub, TargetText] twoChapters style sources
  assertEqual (what <> " errors") [] [diagCode d | d <- ds, isError d]
  let html = htmlValues (fileText files "build/html/b.html")
      epub = htmlValues (epubPage files "OEBPS/b.xhtml")
      text = T.lines (fileText files "build/text/horizontal/b.txt")
  assertBool (what <> " HTML has the mark") (not (T.null (fst html)))
  uncurry (assertEqual (what <> " HTML")) html
  assertEqual (what <> " EPUB") html epub
  let textMark = digitsOf <$> lineAfter "印" text
  assertBool (what <> " text has the mark") (maybe False (not . T.null) textMark)
  assertEqual (what <> " text") textMark (digitsOf <$> lineAfter "参" text)

-- | The marks of notes in a line: its boxes of the kind of a mark, with their widths and texts.
marksIn :: Line -> [(Integer, Text)]
marksIn l = [(unSp w, bcText c) | Box w c <- lineItems l, boxKind c == KindNoteMark]

-- | The text of a line.
textOf :: Line -> Text
textOf l = T.concat [bcText c | Box _ c <- lineItems l]

-- | Each line of the text of the pages with its page, in the order of the slots.
linesByPage :: PdfLayout -> [(Int, Line)]
linesByPage pl =
  [ (poNumber p, slLine sl)
  | p <- gridPages pl,
    (_, SLine lid) <- sortOn fst (poSlots p),
    Just sl <- [Map.lookup lid (plLines pl)]
  ]

-- | The page and the line that start with a text.
lineStarting :: Text -> PdfLayout -> Maybe (Int, Line)
lineStarting p pl = listToMaybe [(n, l) | (n, l) <- linesByPage pl, p `T.isPrefixOf` textOf l]

layoutOf :: BS.ByteString -> Text -> IO PdfLayout
layoutOf style src = layoutMini style src [] >>= either (assertFailure . show) (pure . snd)

-- | sidenoteStyle (12 characters a line, 30 lines a page) with the notes numbered per page.
pageStyle :: BS.ByteString
pageStyle = baseStyle <> "\n[notes]\nnumbering = \"page\"\n"

-- | Notes in paragraphs apart, @gap@ fillers before each, the one at @k@ (from 1) labelled, then the reference.
pagedSource :: Int -> Int -> Int -> Text
pagedSource count gap k =
  T.concat [fillers gap <> (if i == k then "印[note label=x: 注。]\n\n" else "他[note: 注。]\n\n") | i <- [1 .. count]] <> "参[ref-number x]\n"

codes :: [Diagnostic] -> [Text]
codes ds = [c | d <- ds, let DiagnosticCode c = diagCode d]

-- | The diagnostics of a one-chapter build to HTML and plain text.
buildCodes :: BS.ByteString -> Text -> IO [Text]
buildCodes style src = withSystemTempDirectory "golem-note-refs" $ \dir -> do
  (ds, _) <- buildIn dir [TargetHtml, TargetText] miniManifest style [("a.gm", src)]
  pure (codes ds)

noteRefTests :: [TestTree]
noteRefTests =
  [ testGroup
      "root ADR 0422 I1: every input of up to four notes of the three kinds, one labelled, in the four outputs"
      [ testCase ("[notes] numbering = " <> T.unpack n <> ", [endnotes] numbering = " <> T.unpack e) $ do
          depth <- enumDepth
          withSystemTempDirectory "golem-note-refs" $ \dir -> forM_ (inputs depth) (checkInput dir n e)
      | n <- ["chapter", "file", "book", "page"],
        e <- ["chapter", "file", "book"]
      ],
    testCase "root ADR 0422 I1: one labelled footnote is 1" $ do
      pages <- withSystemTempDirectory "golem-note-refs" $ \dir -> pdfLinesIn dir miniManifest baseStyle [("a.gm", "本[note label=x: 注。]\n\n参[ref-number x]\n")]
      ls <- either (assertFailure . show) (pure . concat) pages
      lineAfter "参" ls @?= Just "1",
    testCase "root ADR 0422 I1: the third sidenote labelled is 3, the number of the channel of the sidenotes" $ do
      let src = "他[note: 注。]\n\n他[sidenote: 傍。]\n\n他[sidenote: 傍。]\n\n印[sidenote label=x: 傍。]\n\n参[ref-number x]\n"
      pages <- withSystemTempDirectory "golem-note-refs" $ \dir -> pdfLinesIn dir miniManifest baseStyle [("a.gm", src)]
      ls <- either (assertFailure . show) (pure . concat) pages
      lineAfter "参" ls @?= Just "3",
    testCase "root ADR 0422 I1: an endnote labelled with numbering = \"chapter\" takes the number of its chapter" $ do
      let src = [("a.gm", "他[endnote: 一。]\n"), ("b.gm", "他[endnote: 二。]\n\n印[endnote label=x: 三。]\n\n参[ref-number x]\n")]
      pages <- withSystemTempDirectory "golem-note-refs" $ \dir -> pdfLinesIn dir twoChapters baseStyle src
      ls <- either (assertFailure . show) (pure . concat) pages
      lineAfter "参" ls @?= Just "2",
    testCase "root ADR 0422 I1, I2: numbered per page, a note on the next page takes the number of that page, the reference keeps its width" $ do
      lastOfBook <- layoutOf pageStyle (pagedSource 12 5 12)
      let refOf = maybe [] (marksIn . snd) (lineStarting "参" lastOfBook)
          markOf = maybe [] (marksIn . snd) (lineStarting "印" lastOfBook)
      assertBool "the labelled note is not on the first page" (maybe False ((> 1) . fst) (lineStarting "印" lastOfBook))
      -- the mark takes the number of its page, not 12; the reference is that number
      assertBool (show markOf) (map snd markOf /= ["*12"])
      map (T.dropWhile (== '*') . snd) markOf @?= map snd refOf
      -- numbered through the book, the reference is the text of its number: no box of a mark
      unnumbered <- layoutOf (baseStyle <> "\n[notes]\nnumbering = \"book\"\n") (pagedSource 12 5 12)
      map snd (maybe [] (marksIn . snd) (lineStarting "参" unnumbered)) @?= []
      length refOf @?= 1,
    testCase "root ADR 0422 I2: numbered per page, the reference reserves the width of the widest number, one digit or two" $ do
      -- 12 notes: the number of the book of the labelled note is 1 or 12; the reserve is that of 12
      widths <- forM [1, 2, 11, 12] $ \k -> do
        pl <- layoutOf pageStyle (pagedSource 12 5 k)
        pure (map fst (maybe [] (marksIn . snd) (lineStarting "参" pl)))
      assertEqual "one box each" [1, 1, 1, 1] (map length widths)
      assertEqual "one width" 1 (length (nub (concat widths)))
      -- the same book of nine notes reserves less: the width is that of the widest number of the channel
      nine <- layoutOf pageStyle (pagedSource 9 5 9)
      let w9 = map fst (maybe [] (marksIn . snd) (lineStarting "参" nine))
      assertBool (show (w9, widths)) (w9 < take 1 (concat widths)),
    testCase "root ADR 0422 I1: the HTML of a book numbered per page numbers the reference through the book" $ do
      withSystemTempDirectory "golem-note-refs" $ \dir -> do
        (_, files) <- buildIn dir [TargetHtml] miniManifest pageStyle [("a.gm", pagedSource 12 5 12)]
        htmlValues (fileText files "build/html/a.html") @?= ("12", "12"),
    testCase "root ADR 0422 I3: [ref-page] is the page of the mark, before and after a page break" $ do
      results <- forM [(kind, gap) | kind <- [KNote, KEndnote], gap <- [24 .. 31]] $ \(kind, gap) -> do
        let src = fillers gap <> "印[" <> command kind <> " label=x: 注。]\n\n" <> fillers 40 <> "参[ref-page x]\n"
        pl <- layoutOf baseStyle src
        let markPage = fst <$> lineStarting "印" pl
            refText = textOf . snd <$> lineStarting "参" pl
        assertEqual (show (kind, gap)) (fmap (("参" <>) . T.pack . show) markPage) refText
        pure markPage
      assertBool ("both pages: " <> show results) (Just 1 `elem` results && Just 2 `elem` results),
    testCase "root ADR 0422: [ref-page] to a note in the outputs without pages writes its number" $ do
      withSystemTempDirectory "golem-note-refs" $ \dir -> do
        (_, files) <- buildIn dir [TargetHtml, TargetText] miniManifest baseStyle [("a.gm", "他[note: 一。]\n\n印[note label=x: 二。]\n\n参[ref-page x]\n")]
        htmlValues (fileText files "build/html/a.html") @?= ("2", "2")
        lineAfter "参" (T.lines (fileText files "build/text/horizontal/a.txt")) @?= Just "2",
    testCase "root ADR 0422 I5: [ref-title] to a note is one G04006" $ do
      cs <- buildCodes baseStyle "本[note label=x: 注。]\n\n参[ref-title x]\n"
      filter (`elem` ["G04006", "G04001", "G04003"]) cs @?= ["G04006"],
    testCase "root ADR 0422 I5: a label of a note equal to that of a heading is one G04001" $ do
      cs <- buildCodes baseStyle "@label x\n# 見出し\n\n本[note label=x: 注。]\n\n参[ref-number x]\n"
      filter (`elem` ["G04006", "G04001", "G04003", "G04005"]) cs @?= ["G04001"]
      cs' <- buildCodes baseStyle "本[note label=x: 注。]\n\n本[endnote label=x: 注。]\n"
      filter (== "G04001") cs' @?= ["G04001"],
    testCase "root ADR 0422: the label of a note follows the rule of the characters of @label: G02026" $ do
      cs <- buildCodes baseStyle "本[note label=X: 注。]\n"
      filter (== "G02026") cs @?= ["G02026"],
    testCase "root ADR 0422: a note written by name takes a label too" $ do
      pages <- withSystemTempDirectory "golem-note-refs" $ \dir -> pdfLinesIn dir miniManifest baseStyle [("a.gm", "他[note: 一。]\n\n印[note k label=x]\n\n参[ref-number x]\n\n@note k\n:::\n二つめ。\n\n三つめ。\n:::\n")]
      ls <- either (assertFailure . show) (pure . concat) pages
      lineAfter "参" ls @?= Just "2",
    testCase "root ADR 0422 I4: a note without a label: the name of @note is no label (G04003)" $ do
      cs <- buildCodes baseStyle "本[note k]\n\n参[ref-number k]\n\n@note k\n  注。\n"
      filter (== "G04003") cs @?= ["G04003"]
  ]
