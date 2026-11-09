{- | The line adjustment and the stretch limit of paragraph styles through
the build (docs/adr/0274): the default pulls in, a paragraph style of
"balanced" sets its lines as before, and neither key changes HTML and
EPUB (R9).
-}
module LineAdjustmentSpec (lineAdjustmentTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Syntax
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

{- | Eleven characters and two commas, 13 em at their natural widths in
lines of 12: 12 em with the half em after each comma taken.
-}
squeezable :: Text
squeezable = "あいうえお、かきくけこ、さ\n"

-- | The lines of the first page of a one-chapter book.
firstPage :: BS.ByteString -> Text -> IO [Text]
firstPage style source = do
  r <- pagesMini "" style source [] Map.empty
  case r of
    Right (p : _) -> pure p
    Right [] -> assertFailure "no page"
    Left ds -> assertFailure (show ds)

lineAdjustmentTests :: TestTree
lineAdjustmentTests =
  testGroup
    "the line adjustment of paragraph styles through the build (docs/adr/0274)"
    [ testCase "R3: by default a paragraph that fits a line by the shrink of its glue is one line" $
        firstPage horizontalStyle squeezable >>= (@?= ["あいうえお、かきくけこ、さ"]),
      testCase "R1: body balanced sets it as before the ADR, in two lines" $
        firstPage (horizontalStyle <> "\n[paragraph-styles.body]\nline-adjustment = \"balanced\"\n") squeezable >>= (@?= ["あいうえお、かきくけこ、", "さ"]),
      testCase "R1: a paragraph of a style based on body with balanced, by @style" $
        firstPage (horizontalStyle <> "\n[paragraph-styles.even]\nline-adjustment = \"balanced\"\n") ("@style even\n" <> squeezable) >>= (@?= ["あいうえお、かきくけこ、", "さ"]),
      testCase "R9: HTML and EPUB are the same bytes with the keys written and without them" $ do
        let out style = withSystemTempDirectory "golem-adjust" $ \tmp -> do
              BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n\n[targets.epub]\n")
              BS.writeFile (tmp </> "style.toml") style
              BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 ("# 一\n\n" <> squeezable))
              r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
              assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
              buildFiles (tmp </> "build")
        plain <- out horizontalStyle
        written <- out (horizontalStyle <> "\n[paragraph-styles.body]\nline-adjustment = \"balanced\"\nstretch-limit = 1000\n\n[paragraph-styles.caption]\nstretch-limit = 0\n")
        assertBool "files" (not (Map.null plain))
        written @?= plain
    ]
