{- | The hyphenation exceptions of the book and of the files in the PDF
(docs/adr ADR 0272): I12, the file's list first, then the book's; I13, a
file's list changes none of the lines of the other files and of the table
of contents.
-}
module ExceptionsSpec (exceptionsTests) where

import Data.ByteString qualified as BS
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.LayoutSpec (pageGeometry)
import Golem.Project (Manifest (..), Project (..), ProjectFailure (..))
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Golem.Typeset (PdfInput (..), PdfLayout (..), SetLine (..), layoutPdf)
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | A word of 32 letters: wider than a line of 12 characters, and no patterns break it.
word :: Text
word = T.replicate 32 "x"

-- | The word with a hyphen after the 16th letter.
half :: Text
half = T.replicate 16 "x" <> "-" <> T.replicate 16 "x"

-- | The word with a hyphen after the 8th letter.
quarter :: Text
quarter = T.replicate 8 "x" <> "-" <> T.replicate 24 "x"

-- | The lines of the chapters laid out in the style given, each as the file of its line and its items.
linesOf :: BS.ByteString -> [(FilePath, Text)] -> IO [(FileId, [Item])]
linesOf style chapters = withChapters (withBodyFont style) chapters [] $ \tmp -> do
  writeFiles tmp fakeFontFiles
  ev <- evaluateProject Dev tmp
  e <- either (assertFailure . show . pfDiagnostics) pure ev
  book <- case (evBook e, filter isError (evDiagnostics e)) of
    (Just b, []) -> pure b
    (_, errs) -> assertFailure (show [(diagCode d, diagMessage d) | d <- errs])
  geom <- either (assertFailure . show) pure (pageGeometry (FileId 0) False (evStyle e))
  r <- layoutPdf (PdfInput (diskFiles tmp) (evProject e) (evStyle e) book False [] Map.empty Nothing (localStylesOf e) (chapterMasters (evProject e)) (evStyleFile e) Map.empty (projectVarTexts (manifestVars (projectManifest (evProject e)))) (evStyleText e)) geom fakeFonts
  pl <- either (assertFailure . show) pure r
  pure [(maybe (FileId (-1)) snd (Map.lookupLE lid (plLineFiles pl)), lineItems (slLine sl)) | (lid, sl) <- Map.toList (plLines pl)]

-- | The text of the lines of a file, by its place among the chapters.
textsIn :: Int -> [(FileId, [Item])] -> [Text]
textsIn k ls = [T.concat [bcText c | Box _ c <- its] | (fid, its) <- ls, fid == fileOf k ls]

-- | The items of the lines of a file, by its place among the chapters.
itemsIn :: Int -> [(FileId, [Item])] -> [[Item]]
itemsIn k ls = [its | (fid, its) <- ls, fid == fileOf k ls]

-- | The file of the k-th chapter: the k-th file of the lines, in order.
fileOf :: Int -> [(FileId, [Item])] -> FileId
fileOf k ls = case drop k (nub (map fst ls)) of
  f : _ -> f
  [] -> FileId (-1)

-- | An item without where its characters are in the source.
placeless :: Item -> Item
placeless = \case
  Box w c -> Box w c {bcSource = (fst (bcSource c), mkSpan (FileId 0) 0 0), bcAt = 0}
  x -> x

-- | A list in style.toml.
bookList :: Text -> BS.ByteString
bookList w = horizontalStyle <> "\n[composition.hyphenation-exceptions]\nen = [\"" <> encode w <> "\"]\n"
  where
    encode = BS.pack . map (fromIntegral . fromEnum) . T.unpack

-- | A paragraph of the word, with a file's list or none.
para :: Maybe Text -> Text
para list = maybe "" (\w -> "@hyphenation-exceptions en " <> w <> "\n\n") list <> word <> "\n"

exceptionsTests :: TestTree
exceptionsTests =
  testGroup
    "hyphenation exceptions in the PDF (docs/adr ADR 0272)"
    [ testCase "I12: without a list the word is one line; the book's list breaks it in every file" $ do
        none <- linesOf horizontalStyle [("a.gm", para Nothing), ("b.gm", para Nothing)]
        textsIn 0 none @?= [word]
        book <- linesOf (bookList half) [("a.gm", para Nothing), ("b.gm", para Nothing)]
        textsIn 0 book @?= [T.replicate 16 "x", T.replicate 16 "x"]
        textsIn 1 book @?= [T.replicate 16 "x", T.replicate 16 "x"],
      testCase "I12: a file's list breaks the word of its file only, and wins over the book's" $ do
        ls <- linesOf (bookList half) [("a.gm", para (Just quarter)), ("b.gm", para Nothing)]
        textsIn 0 ls @?= [T.replicate 8 "x", T.replicate 24 "x"]
        textsIn 1 ls @?= [T.replicate 16 "x", T.replicate 16 "x"],
      testCase "I13: a file's list changes no item of the lines of another file, nor of the table of contents" $ do
        let chapters list = [("a.gm", maybe "" (\w -> "@hyphenation-exceptions en " <> w <> "\n\n") list <> "# " <> word <> "\n\n" <> word <> "\n"), ("b.gm", "@toc\n\n" <> para Nothing)]
        without <- linesOf horizontalStyle (chapters Nothing)
        with <- linesOf horizontalStyle (chapters (Just half))
        assertBool "the file's own lines change" (itemsIn 0 with /= itemsIn 0 without)
        -- the lines of b.gm hold the table of contents; where its boxes are in the source moves with the list written in a.gm
        map (map placeless) (itemsIn 1 with) @?= map (map placeless) (itemsIn 1 without)
    ]
