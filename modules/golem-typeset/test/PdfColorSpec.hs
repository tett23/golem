module PdfColorSpec (pdfColorTests) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Golem.Pdf qualified as P
import Golem.Typeset.FigureColor (RasterAnalysis (..), RasterKind (..))
import Golem.Typeset.PdfColor (recolorImportedPage)
import Test.Tasty
import Test.Tasty.HUnit

pdfColorTests :: [TestTree]
pdfColorTests =
  [ testCase "root ADR 0403 I1: PDF white black and gray become CMYK tints" $ do
      p <- converted "1 g 0 0 10 10 re f 0 g 10 0 10 10 re f .5 g 20 0 10 10 re f"
      assertBool "white" ("0 0 0 0 k" `BS.isInfixOf` P.ipContent p)
      assertBool "black" ("0 1 1 0 k" `BS.isInfixOf` P.ipContent p)
      assertBool "half" ("0 0.5 0.5 0 k" `BS.isInfixOf` P.ipContent p),
    testCase "root ADR 0403 I1: unused non-gray color does not make PDF multicolor" $ do
      _ <- converted "1 0 0 rg 0 g 0 0 10 10 re f"
      pure (),
    testCase "root ADR 0403 I1: the default PDF paint is black" $ do
      p <- converted "0 0 10 10 re f"
      assertBool "default black converted" ("0 1 1 0 k" `BS.isPrefixOf` P.ipContent p),
    testCase "root ADR 0403 I2: PDF geometry transparency and resource objects stay intact" $ do
      let original = (page "0 g /Alpha gs 0 0 10 10 re f") {P.ipBox = (2, 3, 12, 23), P.ipRotate = 90, P.ipSize = (20, 10)}
      p <- requireConverted original
      P.ipBox p @?= P.ipBox original
      P.ipRotate p @?= P.ipRotate original
      P.ipSize p @?= P.ipSize original
      P.ipResources p @?= P.ipResources original
      P.ipObjects p @?= P.ipObjects original
      assertBool "alpha operator retained" ("/Alpha gs" `BS.isInfixOf` P.ipContent p),
    testCase "root ADR 0403 I3: differently colored painted objects keep original PDF" $
      recolor (page "1 0 0 rg 0 0 10 10 re f 0 0 1 rg 10 0 10 10 re f") @?= Right Nothing,
    testCase "root ADR 0403 I3: multicolor inside a saved state preserves the entire PDF" $
      recolor (page "q 1 0 0 rg 0 0 10 10 re f 0 0 1 rg 10 0 10 10 re f Q") @?= Right Nothing,
    testCase "root ADR 0403 I3: graphics-state restore recovers the original paint" $
      recolor (page "1 0 0 rg q 0 g 0 0 10 10 re f Q 10 0 10 10 re f") @?= Right Nothing,
    testCase "root ADR 0403 I1: invisible PDF text adds no paint" $ do
      _ <- converted "1 0 0 rg 3 Tr (invisible) Tj 0 g 0 0 10 10 re f"
      pure (),
    testCase "root ADR 0403 I2: recoloring shares the remaining PDF decode budget" $ do
      let original = (page "0 0 10 10 re f") {P.ipDecodedBytes = 256 * 1024 * 1024 - 1}
      case recolor original of
        Left _ -> pure ()
        other -> assertFailure (show other),
    testCase "root ADR 0403 I2: changed PDF objects have swatch-specific identities" $ do
      red <- requireConverted (page "0 g 0 0 10 10 re f")
      let blue = recolorImportedPage (100, 100, 0, 0) noRaster (page "0 g 0 0 10 10 re f")
      case blue of
        Right (Just p) -> do
          assertBool "different swatches" (P.ipFile red /= P.ipFile p)
          assertBool "different from source" (P.ipFile p /= P.ipFile (page ""))
        other -> assertFailure (show other)
  ]
  where
    recolor = recolorImportedPage (0, 100, 100, 0) noRaster
    noRaster _ = Right (RasterAnalysis Multicolor Nothing)
    converted = requireConverted . page
    requireConverted p = case recolor p of
      Right (Just result) -> pure result
      other -> assertFailure (show other) >> pure p

page :: ByteString -> P.ImportedPage
page content = P.ImportedPage "source" 1 (0, 0, 30, 10) 0 (30, 10) (P.ODict []) Nothing content [] [P.UseGray] 0
