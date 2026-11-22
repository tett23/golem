module ExtendedJapaneseOutputsSpec (extendedJapaneseOutputTests) where

import Codec.Archive.Zip (eRelativePath, fromEntry, toArchive, zEntries)
import Control.Monad (forM_)
import Data.ByteString.Lazy qualified as BL
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Layout.Japanese (BoxKind (..), boxKind)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (Look (..))
import Golem.Length (Sp (..))
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), SetLine (..))
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

extendedJapaneseOutputTests :: [TestTree]
extendedJapaneseOutputTests =
  [ testCase "root ADR 0380 I1: evaluated upright AB occupies two unrotated boxes" $ do
      (_, layout) <- layoutMini pdfStyle "[upright: AB]\n" [] >>= either (assertFailure . show) pure
      [(boxKind c, bcText c) | sl <- Map.elems (plLines layout), Box _ c <- lineItems (slLine sl)] @?= [(KindUpright, "A"), (KindUpright, "B")],
    testCase "root ADR 0380 I1: one-character warichu keeps an empty first line in normal evaluation" $ do
      (_, layout) <- layoutMini horizontalStyle "[warichu: 字]\n" [] >>= either (assertFailure . show) pure
      [bcWarichu c | sl <- Map.elems (plLines layout), Box _ c <- lineItems (slLine sl)] @?= [Just ("", "字")],
    testCase "root ADR 0380 I1: both wider and narrower cells fit the requested number of Japanese characters" $
      forM_ [("8pt", 524288), ("12pt", 786432)] $ \(advance, step) -> do
        let style = replaceIn "font-size = \"10pt\"" ("font-size = \"10pt\"\ncharacter-advance = \"" <> advance <> "\"") horizontalStyle
        (_, layout) <- layoutMini style (T.replicate 12 "漢" <> "\n") [] >>= either (assertFailure . show) pure
        Map.size (plLines layout) @?= 1
        let boxes = [(w, lkSize (bcLook c)) | sl <- Map.elems (plLines layout), Box w c <- lineItems (slLine sl)]
        boxes @?= replicate 12 (Sp step, 655360),
    testCase "root ADR 0380 I1: HTML EPUB and both text variants preserve cutting-note and upright content" $
      withSystemTempDirectory "golem-0380-outputs" $ \tmp -> do
        let source = "前[warichu: 漢字仮名][upright: AB]後\n"
            manifest = miniManifest <> "\n[targets.html]\n\n[targets.epub]\n\n[targets.text]\n"
        writeProject tmp manifest horizontalStyle source []
        result <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub, TargetText]}
        assertEqual "no output errors" [] [diagCode d | d <- brDiagnostics result, isError d]
        html <- TIO.readFile (tmp </> "build/html/a.xhtml")
        assertBool "cutting note has two lines" (T.count "class=\"warichu-line\"" html == 2)
        assertBool "upright content" ("class=\"upright\">AB</span>" `T.isInfixOf` html)
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool "upright orientation" ("text-orientation: upright" `T.isInfixOf` css)
        assertBool "cutting-note two-line layout" ("display: inline-flex; flex-direction: column" `T.isInfixOf` css)
        assertBool "cutting-note fixed grapheme cells" (".warichu-cell { display: inline-block; inline-size: 1em" `T.isInfixOf` css)
        archive <- toArchive <$> BL.readFile (tmp </> "build/epub/book.epub")
        let epub = T.concat [TE.decodeUtf8 (BL.toStrict (fromEntry entry)) | entry <- zEntries archive, ".xhtml" `isSuffixOf` eRelativePath entry]
        T.count "class=\"warichu-line\"" epub @?= 2
        forM_ ["horizontal", "vertical"] $ \variant -> do
          text <- TIO.readFile (tmp </> "build/text" </> variant </> "a.txt")
          assertBool "original text order" ("前漢字仮名AB後" `T.isInfixOf` text)
  ]
