-- | Headings of six levels in PDF, HTML and EPUB (docs/adr/0188).
module HeadingLevelsSpec (headingLevelsTests) where

import Codec.Archive.Zip (findEntryByPath, fromEntry, toArchive)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Layout.Paginate (PageOut (..), Slotted (..))
import Golem.Length (Sp (..))
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), SetLine (..))
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A heading of each level, 一 to 六.
sixLevels :: T.Text
sixLevels = "# 一\n\n## 二\n\n### 三\n\n#### 四\n\n##### 五\n\n###### 六\n\n本文。\n"

-- | The body size of horizontalStyle, 10pt (1.5 times is 983040, 1.25 times 819200).
fs :: Sp
fs = 655360

headingLevelsTests :: [TestTree]
headingLevelsTests =
  [ testCase "PDF: the levels 4 to 6 take the default 1zw and one line" $ do
      (_, pl) <- layoutOk horizontalStyle sixLevels []
      -- the size of each heading, and the grid lines from it to the next slot of its page
      [ (next - h, slSize <$> Map.lookup lid (plLines pl))
        | p <- plPages pl,
          let slots = sortOn fst (poSlots p),
          ((h, SHeading lid _), next) <- zip slots (map fst (drop 1 slots))
        ]
        @?= [(5, Just 983040), (3, Just 819200), (2, Just fs), (1, Just fs), (1, Just fs), (1, Just fs)],
    testCase "PDF: the entries of the levels 4 to 6 in the table of contents are indented 3 to 5 characters" $ do
      -- 30 characters a line: each entry takes one line
      (_, pl) <- layoutOk (replaceIn "characters = 12" "characters = 30" horizontalStyle) ("@toc depth=6\n\n" <> sixLevels) []
      take 6 [slIndent sl | p <- plPages pl, (_, SLine lid) <- poSlots p, Just sl <- [Map.lookup lid (plLines pl)]]
        @?= [0, fs, 2 * fs, 3 * fs, 4 * fs, 5 * fs],
    testCase "PDF: heading.5.short shows the heading of level 5 of the page" $ do
      let style =
            BS.concat
              [ replaceIn "lines = 30\n" "lines = 8\n" horizontalStyle,
                BS.concat ["\n[headings." <> TE.encodeUtf8 (T.pack (show l)) <> "]\nsize = \"1zw\"\nlines = 1\n" | l <- [1 :: Int .. 6]],
                "\n[masters.body]\nrunning-head = { position = \"top-outside\", content = \"heading.5.short\" }\n"
              ]
          source = "# 一\n\n## 二\n\n### 三\n\n#### 四\n\n##### 五の題\n\n" <> T.intercalate "\n\n" (replicate 6 (T.replicate 12 "あ")) <> "\n"
      (heads, _) <- layoutHeads miniManifest style [("a.gm", source)]
      Map.lookup 1 heads @?= Just ["五の題"]
      Map.lookup 2 heads @?= Just ["五の題"],
    testCase "HTML and EPUB: <h4> to <h6> in the body, and the navigation nested six deep" $
      withSystemTempDirectory "golem-six" $ \tmp -> do
        TIO.writeFile (tmp </> "manifest.toml") (TE.decodeUtf8 miniManifest <> "[targets.html]\n[targets.epub]\n")
        BS.writeFile (tmp </> "style.toml") (horizontalStyle <> "\n[headings.6]\nrule-before = { weight = \"1pt\" }\n")
        TIO.writeFile (tmp </> "a.gm") ("@toc depth=6\n\n" <> sixLevels)
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        html <- TIO.readFile (tmp </> "build/html/a.xhtml")
        mapM_ (\h -> assertBool (T.unpack h) (h `T.isInfixOf` html)) ["<h4", "<h5", "<h6", "toc-4", "toc-5", "toc-6"]
        -- the rule of [headings.6] is a rule of h6 in the CSS
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool (T.unpack css) ("h6::before" `T.isInfixOf` css)
        archive <- toArchive <$> BL.readFile (tmp </> "build/epub/book.epub")
        let entry p = maybe "" (TE.decodeUtf8 . BL.toStrict . fromEntry) (findEntryByPath p archive)
            nav = entry "OEBPS/nav.xhtml"
        mapM_ (\h -> assertBool (T.unpack h) (h `T.isInfixOf` entry "OEBPS/a.xhtml")) ["<h4", "<h5", "<h6"]
        -- the lists open before 六 in the navigation of the table of contents
        let before = fst (T.breakOn "六" (snd (T.breakOn "epub:type=\"toc\"" nav)))
        (T.count "<ol" before - T.count "</ol>" before) @?= 6
  ]
