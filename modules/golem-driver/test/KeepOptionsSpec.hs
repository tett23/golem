{- | The keep options of paragraph styles through the build (docs/adr/0261):
G07111, G07112 and G07113 from the last round of the layout, at the
paragraphs, in the same order on every build, and the CSS of HTML.
-}
module KeepOptionsSpec (keepOptionsTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Support
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | Builds the one-chapter project to PDF with the fake fonts: the code, the file and the offset of each diagnostic.
keepDiagnostics :: BS.ByteString -> Text -> IO [(Text, Maybe FilePath, Int)]
keepDiagnostics style source = withSystemTempDirectory "golem-keep" $ \tmp -> do
  writeProject tmp miniManifest style source []
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFiles = diskFiles tmp, optFonts = fakeProvider}
  pure [(c, siPath <$> Map.lookup (spanFile (diagSpan d)) (brSources r), spanStart (diagSpan d)) | d <- brDiagnostics r, let DiagnosticCode c = diagCode d, c `elem` ["G07111", "G07112", "G07113"]]

-- | A paragraph of so many lines of twelve characters, after an @style line of the style given.
styled :: Text -> Int -> Text
styled name n = "@style " <> name <> "\n" <> T.replicate (12 * n - 1) "あ" <> "。\n"

-- | The byte offset of the first occurrence of a text in another.
offsetOf :: Text -> Text -> Int
offsetOf needle hay = BS.length (TE.encodeUtf8 (fst (T.breakOn needle hay)))

keepOptionsTests :: TestTree
keepOptionsTests =
  testGroup
    "the keep options of paragraph styles through the build (docs/adr/0261)"
    [ testCase "G07112: a paragraph of keep-all-lines longer than a column, at the paragraph" $ do
        let style = fiveLines <> "\n[paragraph-styles.long]\nkeep-all-lines = true\n"
            source = "一。\n\n" <> styled "long" 7
        ds <- keepDiagnostics style source
        -- at the paragraph after its @style line
        ds @?= [("G07112", Just "a.gm", offsetOf "あああ" source)],
      testCase "G07111: a paragraph of keep-with-next at the end of the book, at the paragraph" $ do
        let style = fiveLines <> "\n[paragraph-styles.lead]\nkeep-with-next = 2\n"
            source = "一。\n\n" <> styled "lead" 1
        ds <- keepDiagnostics style source
        ds @?= [("G07111", Just "a.gm", offsetOf "あああ" source)],
      testCase "G07113: the first part of one line in a column of one line, by the default keep too" $ do
        let source = "@page-lines -4\n\n" <> T.replicate 35 "あ" <> "。\n"
        ds <- keepDiagnostics fiveLines source
        [c | (c, _, _) <- ds] @?= ["G07113"],
      testCase "the diagnostics are in the same order on every build" $ do
        let style = fiveLines <> "\n[paragraph-styles.long]\nkeep-all-lines = true\n\n[paragraph-styles.lead]\nkeep-with-next = 2\n"
            source = "一。\n\n" <> styled "long" 7 <> "\n" <> styled "long" 8 <> "\n" <> styled "lead" 1
        a <- keepDiagnostics style source
        b <- keepDiagnostics style source
        a @?= b
        -- the warning first, then the notices, as the build orders them
        [c | (c, _, _) <- a] @?= ["G07111", "G07112", "G07112"],
      testCase "HTML: the keep options not of their defaults are CSS, and a book without them has none" $ do
        let style = horizontalStyle <> "\n[paragraph-styles.k]\nkeep-with-next = 1\nkeep-all-lines = true\nkeep-first-lines = 3\nkeep-last-lines = 4\npage-break = \"recto\"\n\n[paragraph-styles.d]\nkeep-first-lines = 2\npage-break = \"any\"\n"
        (_, css) <- htmlMini style "@style k\nあ。\n"
        assertBool (T.unpack css) ("p.ps-k { break-after: avoid; break-inside: avoid; orphans: 3; widows: 4; break-before: recto; }" `T.isInfixOf` css)
        assertBool "no rule of d" (not ("p.ps-d { break" `T.isInfixOf` css) && not ("p.ps-d { orphans" `T.isInfixOf` css))
        (_, plain) <- htmlMini horizontalStyle "あ。\n"
        assertBool "none of the keep options" (not (any (`T.isInfixOf` plain) ["orphans", "widows", "break-inside", "break-after"]))
    ]
