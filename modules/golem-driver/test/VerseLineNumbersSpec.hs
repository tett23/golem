module VerseLineNumbersSpec (verseLineNumberTests) where

import Codec.Archive.Zip (eRelativePath, fromEntry, toArchive, zEntries)
import Control.Monad (forM_)
import Data.ByteString.Lazy qualified as BL
import Data.List
  ( intercalate,
    isSuffixOf,
  )
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Doc.IR
import Golem.Driver
import Golem.Driver.Verse
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Project.Style
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), SetLine (..))
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

sp :: SrcSpan
sp = mkSpan (FileId 0) 0 0

sourceLines :: Int -> [Inline]
sourceLines n = intercalate [LineBreak sp] (replicate n [Text sp "word"])

prefixes :: [Inline] -> [T.Text]
prefixes xs = [t | Text _ t <- xs, T.isSuffixOf " " t, not (T.null (T.strip t))]

verseLineNumberTests :: [TestTree]
verseLineNumberTests =
  [ testCase "root ADR 0384 I1: every small line count and interval has floor(m/n) numbers" $
      forM_ [0 .. 32] $ \m -> forM_ [1 .. 12] $ \n ->
        length (prefixes (numberVerseLines sp n (sourceLines m))) @?= m `div` n,
    testCase "root ADR 0384 I1: four source lines at interval five have no number" $
      prefixes (numberVerseLines sp 5 (sourceLines 4)) @?= [],
    testCase "root ADR 0384 I1: five source lines at interval five have one number" $
      prefixes (numberVerseLines sp 5 (sourceLines 5)) @?= ["5 "],
    testCase "root ADR 0384 I1: empty source lines do not advance the counter" $
      prefixes (numberVerseLines sp 2 [LineBreak sp, Text sp "one", LineBreak sp, Text sp " ", LineBreak sp, Text sp "two"]) @?= ["2 "],
    testCase "root ADR 0384 I1: reference-only and note-mark-only lines count as nonempty" $ do
      prefixes (numberVerseLines sp 1 [Resolved sp RefNumber "target" [Text sp "7"]]) @?= ["1 "]
      prefixes (numberVerseLines sp 1 [CharStyle sp "em" [Note sp 1 Nothing (noteBody sp [])]]) @?= ["1 "],
    testCase "root ADR 0384 I1: the counter restarts at each paragraph" $ do
      style <- either (assertFailure . show) pure (parseStyle (FileId 0) "[paragraph-styles.verse]\nline-number-interval = 2\n")
      let paragraph = Block sp Nothing Nothing (Paragraph (Just "verse") (sourceLines 3))
          Document _ numbered = numberVerseDocument style (Document (FileId 0) [paragraph, paragraph])
      [prefixes is | Block _ _ _ (Paragraph _ is) <- numbered] @?= [["2 "], ["2 "]],
    testCase "root ADR 0384 I1: a long fifth source line is numbered once after PDF wrapping" $ do
      let style = horizontal30 "\n[paragraph-styles.verse]\nline-number-interval = 5\n"
          source = "@style verse\n" <> T.replicate 4 "  短い行\n" <> "  " <> T.replicate 80 "漢" <> "\n"
      (_, layout) <- layoutMini style source [] >>= either (assertFailure . show) pure
      let boxes = [bcText c | sl <- Map.elems (plLines layout), Box _ c <- lineItems (slLine sl)]
      length (filter (== "5") boxes) @?= 1
      assertBool "fifth line wraps" (Map.size (plLines layout) > 5),
    testCase "root ADR 0384 I1: HTML EPUB and both text variants number the same source lines" $
      withSystemTempDirectory "golem-0384-outputs" $ \tmp -> do
        let style = horizontal30 "\n[paragraph-styles.verse]\nline-number-interval = 2\n"
            source = "@style verse\n  一つ\n  二つ\n  三つ\n\n@style verse\n  次の一つ\n  次の二つ\n"
            manifest = miniManifest <> "\n[targets.html]\n\n[targets.epub]\n\n[targets.text]\n"
        writeProject tmp manifest style source []
        result <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub, TargetText]}
        assertEqual "no output errors" [] [diagCode d | d <- brDiagnostics result, isError d]
        html <- TIO.readFile (tmp </> "build/html/a.xhtml")
        T.count ">2 " html @?= 2
        archive <- toArchive <$> BL.readFile (tmp </> "build/epub/book.epub")
        let epub = T.concat [TE.decodeUtf8 (BL.toStrict (fromEntry entry)) | entry <- zEntries archive, ".xhtml" `isSuffixOf` eRelativePath entry]
        T.count ">2 " epub @?= 2
        forM_ ["horizontal", "vertical"] $ \variant -> do
          text <- TIO.readFile (tmp </> "build/text" </> variant </> "a.txt")
          T.count "2 " text @?= 2,
    testCase "root ADR 0384 I1: zero interval is rejected and one is accepted" $ do
      let parsed n = parseStyle (FileId 0) ("[paragraph-styles.verse]\nline-number-interval = " <> n <> "\n")
      case parsed "0" of
        Left ds -> map diagCode ds @?= [DiagnosticCode "G03006"]
        Right _ -> assertFailure "zero interval accepted"
      case parsed "1" of
        Right style -> (paraStyle style (Just "verse") >>= psLineNumberInterval) @?= Just 1
        Left ds -> assertFailure (show ds)
  ]
