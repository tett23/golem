{- | Notes of more than one paragraph through the outputs (docs/adr/0263):
I1, I2, I4, I5 and I8.
-}
module NotesSpec (notesTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Paginate (PageOut (..))
import Golem.Syntax (diagCode, isError)
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Golem.Typeset (PdfLayout (..), SetLine (..))
import Support
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A note of three paragraphs, each short enough for one line.
three :: T.Text
three = "本文[note k]。\n\n@note k\n  一の段。\n\n  二の段。\n\n  三の段。\n"

lineText :: Line -> T.Text
lineText l = T.concat [bcText c | Box _ c <- lineItems l]

-- | The lines of the footnotes of a layout, each note with its lines.
footnotes :: PdfLayout -> [[T.Text]]
footnotes pl = [map lineText ls | sl <- Map.elems (plLines pl), (_, ls) <- slNotes sl]

layout :: BS.ByteString -> T.Text -> IO PdfLayout
layout style src = layoutMini style src [] >>= either (assertFailure . show . map diagCode) (pure . snd)

-- | Every file a build writes for the targets, by its path under build/, and the errors.
buildAll :: BS.ByteString -> T.Text -> IO [(FilePath, BS.ByteString)]
buildAll style src = withSystemTempDirectory "golem-notes" $ \tmp -> do
  writeProject tmp (TE.encodeUtf8 (manifestToml testManifest {tmTargets = ["pdf", "html", "epub", "text"]})) style src []
  r <- build (defaultOptions tmp) {optFonts = fakeProvider}
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  mapM (\p -> (drop (length tmp + 1) p,) <$> BS.readFile p) (brWritten r)

notesTests :: [TestTree]
notesTests =
  [ testCase "I4, I5: a footnote of three paragraphs takes their lines in order, the mark only on the first" $ do
      pl <- layout horizontalStyle three
      case footnotes pl of
        [ls@[a, b, c]] -> do
          assertBool (show ls) ("一の段。" `T.isSuffixOf` a && "二の段。" == b && "三の段。" == c)
          assertBool (show ls) (not ("一の段。" `T.isPrefixOf` a))
        other -> assertFailure (show other),
    testCase "I4: a paragraph of two lines in a footnote: the lines of each paragraph added up" $ do
      pl <- layout horizontalStyle "本文[note k]。\n\n@note k\n  一二三四五六七八九十一二三四五。\n\n  末。\n"
      map length (footnotes pl) @?= [3],
    testCase "I6: a footnote too long for a page goes on to the next, at a line between or inside its paragraphs" $ do
      let paras = T.concat ["  段" <> T.pack (show i) <> "。\n\n" | i <- [1 .. 6 :: Int]]
      pl <- layout fiveLines ("本文[note k]。\n\n@note k\n" <> paras)
      let pages = [(poNumber p, n) | p <- plPages pl, (_, _, n) <- poFootnotes p]
      assertBool (show pages) (length pages >= 2)
      sum (map snd pages) @?= 6,
    testCase "I5: the notes at the end of a chapter: the mark on the first paragraph, the others after it" $ do
      files <- buildAll (horizontalStyle <> "\n[notes]\nplacement = \"chapter-end\"\n") three
      case [TE.decodeUtf8 b | (p, b) <- files, "horizontal/a.txt" `isSuffixOf` p] of
        [t] -> assertBool (T.unpack t) ("*1 一の段。\n二の段。\n三の段。" `T.isInfixOf` t)
        other -> assertFailure (show other),
    testCase "HTML: a p for each paragraph, the link back at the start of the first; style.css takes their margins off" $ do
      (html, css) <- htmlMini horizontalStyle three
      assertBool (T.unpack html) ("<aside epub:type=\"footnote\" id=\"note-1\"><p><a href=\"#noteref-1\">1</a> 一の段。</p><p>二の段。</p><p>三の段。</p></aside>" `T.isInfixOf` html)
      assertBool (T.unpack css) ("section.notes aside p { margin-block: 0; padding-inline-start: 0; text-indent: 0; }" `T.isInfixOf` css),
    testCase "I1: a note of one paragraph is one p in HTML" $ do
      (html, _) <- htmlMini horizontalStyle "本文[note: 注。]。\n"
      assertBool (T.unpack html) ("<p><a href=\"#noteref-1\">1</a> 注。</p></aside>" `T.isInfixOf` html),
    testCase "I2: @note before the mark, after it and in a list item give the same HTML, EPUB and plain text, and the same drawing of the PDF" $ do
      let at pre post = pre <> "本文[note k]。\n\n- 項目\n" <> post
          body = "@note k\n  一の段。\n\n  二の段。\n\n"
      a <- buildAll horizontalStyle (at body "")
      b <- buildAll horizontalStyle (at "" ("\n" <> body))
      c <- buildAll horizontalStyle (at "" "\n  @note k\n    一の段。\n\n    二の段。\n")
      let outputs fs = [(p, bs) | (p, bs) <- fs, not (".json" `isSuffixOf` p)]
          -- the PDF follows the places of the text in the source (its structure), not only the text
          notPdf = filter (not . (".pdf" `isSuffixOf`) . fst) . outputs
      map fst (outputs a) @?= map fst (outputs b)
      forM_ [(n, notPdf x) | (n, x) <- [("after", b), ("in a list item", c)]] $ \(n, fs) ->
        forM_ (zip (notPdf a) fs) $ \((p, x), (_, y)) -> assertBool (n <> ": " <> p) (x == y)
      -- the PDF: the same drawing on every page
      let drawn fs = mapM (\(_, x) -> map drawnGlyphs <$> pageContents x) [f | f <- fs, ".pdf" `isSuffixOf` fst f]
      da <- drawn a
      db <- drawn b
      dc <- drawn c
      da @?= db
      da @?= dc,
    testCase "tagged PDF: a Note holds the Lbl of its mark and a P for each paragraph" $ do
      t <- withSystemTempDirectory "golem-structure" $ \tmp -> do
        writeProject tmp miniManifest horizontalStyle three []
        r <- pdfStructure (defaultOptions tmp) {optFonts = fakeProvider}
        either (assertFailure . show . map diagCode) (pure . map T.strip . T.lines) r
      let note = takeWhile (\l -> not ("H" `T.isPrefixOf` l)) (drop 1 (dropWhile (not . ("Note" `T.isPrefixOf`)) t))
      length (filter (== "P") note) @?= 3
      take 1 note @?= ["Lbl"],
    testCase "I8: the same source gives the same files twice" $ do
      a <- buildAll horizontalStyle three
      b <- buildAll horizontalStyle three
      a @?= b
  ]
