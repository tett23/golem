{- | Numbers kept with their units through the build (docs/adr/0275): the
overfull line a number and its unit make is G07105, or G07122 in a range
not broken (W6), and number-unit-penalty changes neither HTML nor EPUB
(W8).
-}
module NumberUnitBuildSpec (numberUnitBuildTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A number of 24 digits, as wide as the lines of twelve characters of 'horizontalStyle'.
digits :: Text
digits = T.replicate 4 "123456"

-- | The codes of the overfull lines of a one-chapter book built to PDF.
overfullCodes :: BS.ByteString -> Text -> IO [Text]
overfullCodes style source = withSystemTempDirectory "golem-number-unit" $ \tmp -> do
  writeProject tmp miniManifest style source []
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFiles = diskFiles tmp, optFonts = fakeProvider}
  pure [c | d <- brDiagnostics r, let DiagnosticCode c = diagCode d, c `elem` ["G07105", "G07122"]]

numberUnitBuildTests :: TestTree
numberUnitBuildTests =
  testGroup
    "numbers kept with their units through the build (docs/adr/0275)"
    [ testCase "W6: a number as wide as the line, and 円, is one overfull line, G07105 only" $ do
        -- the number alone fits the line: the rule of the ADR makes the line overfull
        overfullCodes horizontalStyle ("あ" <> digits <> "\n") >>= (@?= [])
        overfullCodes horizontalStyle ("あ" <> digits <> "円\n") >>= (@?= ["G07105"]),
      testCase "W6: the number and 円 in [style no-break] is one overfull line, G07122 only" $
        overfullCodes horizontalStyle ("あ[style no-break: " <> digits <> "円]\n") >>= (@?= ["G07122"]),
      testCase "W8: HTML and EPUB are the same bytes whatever number-unit-penalty is" $ do
        let out style = withSystemTempDirectory "golem-number-unit" $ \tmp -> do
              BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n\n[targets.epub]\n")
              BS.writeFile (tmp </> "style.toml") style
              BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 "# 一\n\nあ100円と１０冊。\n")
              r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
              assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
              buildFiles (tmp </> "build")
        plain <- out horizontalStyle
        assertBool "files" (not (Map.null plain))
        mapM_ (\v -> out (horizontalStyle <> "\n[composition]\nnumber-unit-penalty = " <> v <> "\n") >>= (@?= plain)) ["0", "50", "10000"]
    ]
