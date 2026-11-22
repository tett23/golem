module PdfColorSpec (pdfColorTests) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Pdf qualified as P
import Golem.Pdf.Image (flate)
import Golem.Typeset.FigureColor (RasterAnalysis (..), RasterKind (..))
import Golem.Typeset.PdfColor (recolorImportedPage)
import Test.Tasty
import Test.Tasty.HUnit

pdfColorTests :: [TestTree]
pdfColorTests =
  [ testCase "root ADR 0403 I1: a nested PDF Form is recolored" $ do
      result <- requireConverted (formPage ".5 g 0 0 10 10 re f" "/F Do")
      let content = newFormContent result
      assertBool "nested gray" ("0 0.5 0.5 0 k" `BS.isInfixOf` content),
    testCase "root ADR 0403 I1: a PDF Form inherits the caller paint" $ do
      result <- requireConverted (formPage "0 0 10 10 re f" ".5 g /F Do")
      assertBool "inherited paint is not reset to black" (not ("0 1 1 0 k" `BS.isInfixOf` newFormContent result)),
    testCase "root ADR 0403 I3: a reused Form in two colors keeps the original PDF" $
      recolor (formPage "0 0 10 10 re f" "1 0 0 rg /F Do 0 0 1 rg /F Do") @?= Right Nothing,
    testCase "root ADR 0403 I2: converted Forms are cloned without changing soft-mask resources" $ do
      let base = formPage "0 g 0 0 10 10 re f" "/Alpha gs /F Do"
          original = base {P.ipResources = P.ODict [("XObject", P.ODict [("F", P.ORef 1)]), ("ExtGState", P.ODict [("Alpha", P.ODict [("SMask", P.ODict [("S", P.OName "Luminosity"), ("G", P.ORef 1)])])])]}
      result <- requireConverted original
      lookup 1 (P.ipObjects result) @?= lookup 1 (P.ipObjects original)
      assertBool "original object not reused for paint" (P.ipResources result /= P.ipResources original),
    testCase "root ADR 0403 I2: a nested soft mask keeps the source XObject binding" $ do
      let base = formPage ".5 g 0 0 10 10 re f" "/Alpha gs /F Do"
          original = base {P.ipResources = P.ODict [("XObject", P.ODict [("F", P.ORef 1)]), ("ExtGState", P.ODict [("Alpha", P.ODict [("SMask", P.ODict [("S", P.OName "Luminosity"), ("G", P.ORef 3)])])])], P.ipObjects = P.ipObjects base <> [(3, P.OStream [("Subtype", P.OName "Form")] "/F Do")]}
      result <- requireConverted original
      case P.ipResources result of
        P.ODict fields | Just (P.ODict objects) <- lookup "XObject" fields -> lookup "F" objects @?= Just (P.ORef 1)
        other -> assertFailure (show other),
    testCase "root ADR 0403 I2: a cyclic PDF Form graph is rejected" $ do
      let cyclic = formPage "/F Do" "/F Do"
      case recolor cyclic of
        Left _ -> pure ()
        other -> assertFailure (show other),
    testCase "root ADR 0403 I2: a shared PDF Form graph is summarized without expansion" $ do
      result <- requireConverted sharedForms
      length (P.ipObjects result) @?= 80,
    testCase "root ADR 0403 I1: a compressed PDF Form uses its indirect filter" $ do
      let original = (formPage "unused" "/F Do") {P.ipObjects = [(1, P.OStream [("Subtype", P.OName "Form"), ("Filter", P.ORef 2)] (flate ".5 g 0 0 10 10 re f")), (2, P.OName "FlateDecode")]}
      result <- requireConverted original
      assertBool "decoded and recolored" ("0 0.5 0.5 0 k" `BS.isInfixOf` newFormContent result),
    testCase "root ADR 0403 I1: fully transparent PDF paint does not make a gray figure multicolor" $ do
      let original = (page "/Hide gs 1 0 0 rg 0 0 10 10 re f /Show gs .5 g 10 0 10 10 re f") {P.ipResources = P.ODict [("ExtGState", P.ODict [("Hide", P.ODict [("ca", P.OInt 0)]), ("Show", P.ODict [("ca", P.OInt 1)])])]}
      _ <- requireConverted original
      pure (),
    testCase "root ADR 0403 I1: PDF white black and gray become CMYK tints" $ do
      p <- converted "1 g 0 0 10 10 re f 0 g 10 0 10 10 re f .5 g 20 0 10 10 re f"
      assertBool "white" ("0 0 0 0 k" `BS.isInfixOf` P.ipContent p)
      assertBool "black" ("0 1 1 0 k" `BS.isInfixOf` P.ipContent p)
      assertBool "half" ("0 0.5 0.5 0 k" `BS.isInfixOf` P.ipContent p),
    testCase "root ADR 0403 I1: neutral CMYK and its RGB approximation use the same tint" $ do
      cmyk <- converted ".5 .5 .5 .5 k 0 0 10 10 re f"
      rgb <- converted ".25 .25 .25 rg 0 0 10 10 re f"
      P.ipContent cmyk @?= P.ipContent rgb,
    testCase "root ADR 0403 I1: unused non-gray color does not make PDF multicolor" $ do
      _ <- converted "1 0 0 rg 0 g 0 0 10 10 re f"
      pure (),
    testCase "root ADR 0403 I1: the default PDF paint is black" $ do
      p <- converted "0 0 10 10 re f"
      assertBool "default black converted" ("0 1 1 0 k" `BS.isPrefixOf` P.ipContent p),
    testCase "root ADR 0403 I2: PDF geometry transparency and resource objects stay intact" $ do
      let original = (page "0 g /Alpha gs 0 0 10 10 re f") {P.ipBox = (2, 3, 12, 23), P.ipRotate = 90, P.ipSize = (20, 10), P.ipResources = P.ODict [("ExtGState", P.ODict [("Alpha", P.ODict [("ca", P.OReal "0.5"), ("CA", P.OReal "0.5")])])]}
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

formPage :: ByteString -> ByteString -> P.ImportedPage
formPage form content =
  (page content)
    { P.ipResources = P.ODict [("XObject", P.ODict [("F", P.ORef 1)])],
      P.ipObjects = [(1, P.OStream [("Type", P.OName "XObject"), ("Subtype", P.OName "Form"), ("BBox", P.OArr (map P.OInt [0, 0, 10, 10]))] form)]
    }

newFormContent :: P.ImportedPage -> ByteString
newFormContent p = case (P.ipResources p, P.contentOperations (P.ipContent p)) of
  (P.ODict fields, Just operations)
    | Just (P.ODict objects) <- lookup "XObject" fields,
      name : _ <- [TE.decodeLatin1 (BS.drop 1 name) | ("Do", [name]) <- operations],
      Just (P.ORef key) <- lookup name objects,
      Just (P.OStream _ content) <- lookup key (P.ipObjects p) ->
        content
  _ -> "missing converted Form"

sharedForms :: P.ImportedPage
sharedForms =
  (page "/F1 Do")
    { P.ipResources = P.ODict [("XObject", P.ODict [(name n, P.ORef n) | n <- [1 .. 40]])],
      P.ipObjects = [(n, P.OStream [("Subtype", P.OName "Form")] (if n == 40 then "0 g 0 0 10 10 re f" else TE.encodeUtf8 ("/" <> name (n + 1) <> " Do /" <> name (n + 1) <> " Do"))) | n <- [1 .. 40]]
    }
  where
    name n = "F" <> T.pack (show n)
