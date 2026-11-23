{- | Patterns painted as colours in imported PDF figures (root ADR 0425):
coloured and uncoloured tiling patterns and shading patterns, with the
checks of the graphics state of a shading pattern.
-}
module PdfColorPatternSpec (pdfColorPatternTests) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Pdf qualified as P
import PdfColorShadingSpec (converted, dictOf, fn2, numbers, nums, page, recolor, rejected, tone)
import Test.Tasty
import Test.Tasty.HUnit

pdfColorPatternTests :: [TestTree]
pdfColorPatternTests =
  [ testGroup "root ADR 0425 I1: patterns that cannot be judged" rejectTests,
    testGroup "root ADR 0425 I5: patterns in the class of the figure" classTests,
    testGroup "root ADR 0425 I6: the mapped shadings of shading patterns" shadingTests,
    testGroup "root ADR 0425 I11: the contents of coloured tiling patterns" tilingTests
  ]

rejectTests :: [TestTree]
rejectTests =
  [ testCase "root ADR 0425 I1: a shading pattern whose ExtGState has BM Multiply is G08113" $
      rejected (patterned fill [("P", shadingPattern [("ExtGState", P.ODict [("BM", P.OName "Multiply")])] (gray 0 1))] []),
    testCase "root ADR 0425 I1: a shading pattern whose ExtGState has TR2 a function is G08113" $
      rejected (patterned fill [("P", shadingPattern [("ExtGState", P.ODict [("TR2", fn2 [0] [1])])] (gray 0 1))] []),
    testCase "root ADR 0425 I1: a shading pattern whose ExtGState has OPM 1 and op true is G08113" $
      rejected (patterned fill [("P", shadingPattern [("ExtGState", P.ODict [("OPM", P.OInt 1), ("op", P.OBool True)])] (gray 0 1))] []),
    testCase "root ADR 0425 I1: OPM 1 from gs and OP true in the pattern's ExtGState is G08113" $
      rejected (patterned ("/S gs " <> fill) [("P", shadingPattern [("ExtGState", P.ODict [("OP", P.OBool True)])] (gray 0 1))] [] `withStates` [("S", P.ODict [("OPM", P.OInt 1)])]),
    testCase "root ADR 0425 I1: a pattern that is not in the resources is G08113" $
      rejected (patterned "/Pattern cs /Q scn 0 0 1 1 re f" [("P", shadingPattern [] (gray 0 1))] []),
    testCase "root ADR 0425 I1: a coloured tiling pattern painting a Multiply gray is G08113" $
      rejected (patterned fill [("P", tiling 1 [("ExtGState", P.ODict [("M", P.ODict [("BM", P.OName "Multiply")])])] "/M gs .5 g 0 0 1 1 re f")] [])
  ]

classTests :: [TestTree]
classTests =
  [ testCase "root ADR 0425 I5: an uncoloured tiling pattern with a gray scn paints CMYK components" $ do
      p <- converted (patterned "/C cs .25 /P scn 0 0 1 1 re f" [("P", tiling 2 [] "0 0 1 1 re f")] [("C", P.OArr [P.OName "Pattern", P.OName "DeviceGray"])])
      case selected p of
        Just (space, components, _) -> do
          space @?= P.OArr [P.OName "Pattern", P.OName "DeviceCMYK"]
          components @?= tone 0.25
        Nothing -> assertFailure (show (P.ipContent p)),
    testCase "root ADR 0425 I5: an uncoloured tiling pattern with red scn and a gray rectangle keeps the original colours" $
      recolor (patterned "/C cs 1 0 0 /P scn 0 0 1 1 re f .5 g 0 0 1 1 re f" [("P", tiling 2 [] "0 0 1 1 re f")] [("C", P.OArr [P.OName "Pattern", P.OName "DeviceRGB"])]) @?= Right Nothing,
    testCase "root ADR 0425 I5: a red tiling pattern and a red rectangle are all the swatch" $ do
      p <- converted (patterned ("1 0 0 rg 0 0 1 1 re f " <> fill) [("P", tiling 1 [] "1 0 0 rg 0 0 1 1 re f")] [])
      assertBool "rectangle" ("0 1 1 0 k" `BS.isInfixOf` P.ipContent p)
      case selected p of
        Just (_, _, Just (_, body)) -> assertBool "pattern content" ("0 1 1 0 k" `BS.isInfixOf` body)
        other -> assertFailure (show other),
    testCase "root ADR 0425 I5: a red-to-blue shading pattern keeps the original colours" $
      recolor (patterned fill [("P", shadingPattern [] (axial "DeviceRGB" (fn2 [1, 0, 0] [0, 0, 1])))] []) @?= Right Nothing,
    testCase "root ADR 0425 I5: a gray shading pattern used for stroking is recoloured" $ do
      p <- converted (patterned "/Pattern CS /P SCN 0 0 m 1 1 l S" [("P", shadingPattern [] (gray 0 1))] [])
      case selected p of
        Just (_, _, Just (fields, _)) -> assertBool "shading" (any ((== "Shading") . fst) fields)
        other -> assertFailure (show other),
    testCase "root ADR 0425 I5: a pattern selected outside a Form with its own resources paints inside it" $ do
      let form = P.OStream [("Type", P.OName "XObject"), ("Subtype", P.OName "Form"), ("BBox", nums [0, 0, 1, 1]), ("Resources", P.ODict [("Pattern", P.ODict [("P", P.ORef 21)])])] "0 0 1 1 re f"
          base = patterned "/Pattern cs /P scn /F Do" [("P", shadingPattern [] (gray 0 1))] []
          withForm = case P.ipResources base of
            P.ODict entries -> base {P.ipResources = P.ODict (entries <> [("XObject", P.ODict [("F", P.ORef 20)])])}
            _ -> base
      p <- converted (withForm `withObjects` [(20, form), (21, shadingPattern [] (axial "DeviceRGB" (fn2 [1, 0, 0] [0, 0, 1])))])
      assertBool "form content selects the converted pattern" (any (\(_, o) -> case o of P.OStream _ body -> " scn\nf" `BS.isInfixOf` body; _ -> False) (P.ipObjects p)),
    testCase "root ADR 0425 I5: a pattern selected but never painted adds no colour" $ do
      _ <- converted (patterned "/Pattern cs /P scn .5 g 0 0 1 1 re f" [("P", shadingPattern [] (axial "DeviceRGB" (fn2 [1, 0, 0] [0, 0, 1])))] [])
      pure ()
  ]

shadingTests :: [TestTree]
shadingTests =
  [ testCase "root ADR 0425 I6: a gray shading pattern maps its function and keeps its Matrix" $ do
      p <- converted (patterned fill [("P", shadingPattern [("Matrix", nums [1, 0, 0, 1, 5, 5])] (gray 0 1))] [])
      case selected p of
        Just (_, _, Just (fields, _)) -> do
          lookup "Matrix" fields @?= Just (nums [1, 0, 0, 1, 5, 5])
          let shading = maybe [] (dictOf p) (lookup "Shading" fields)
              function = maybe [] (dictOf p) (lookup "Function" shading)
          lookup "ColorSpace" shading @?= Just (P.OName "DeviceCMYK")
          (numbers =<< lookup "C0" function) @?= Just (tone 0)
          (numbers =<< lookup "C1" function) @?= Just (tone 1)
        other -> assertFailure (show other),
    testCase "root ADR 0425 I6: a gray Background of a shading pattern maps" $ do
      p <- converted (patterned fill [("P", shadingPattern [] (axial "DeviceGray" (fn2 [0] [1]) <> [("Background", nums [0.5])]))] [])
      case selected p of
        Just (_, _, Just (fields, _)) -> do
          let shading = maybe [] (dictOf p) (lookup "Shading" fields)
          (numbers =<< lookup "Background" shading) @?= Just (tone 0.5)
        other -> assertFailure (show other),
    testCase "root ADR 0425 I6: a shading pattern whose ExtGState is Normal is recoloured" $ do
      _ <- converted (patterned fill [("P", shadingPattern [("ExtGState", P.ODict [("BM", P.OName "Normal"), ("OPM", P.OInt 0), ("op", P.OBool True)])] (gray 0 1))] [])
      pure ()
  ]

tilingTests :: [TestTree]
tilingTests =
  [ testCase "root ADR 0425 I11: a coloured tiling pattern of gray content maps its content" $ do
      p <- converted (patterned fill [("P", tiling 1 [] ".5 g 0 0 1 1 re f")] [])
      case selected p of
        Just (_, _, Just (fields, body)) -> do
          assertBool "content" ("0 0.5 0.5 0 k" `BS.isInfixOf` body)
          lookup "PaintType" fields @?= Just (P.OInt 1)
          lookup "XStep" fields @?= Just (P.OInt 2)
        other -> assertFailure (show other),
    testCase "root ADR 0425 I11: a coloured tiling pattern of red content beside a gray rectangle keeps the original colours" $
      recolor (patterned (".5 g 0 0 1 1 re f " <> fill) [("P", tiling 1 [] "1 0 0 rg 0 0 1 1 re f")] []) @?= Right Nothing,
    testCase "root ADR 0425 I11: a coloured tiling pattern painting a gray shading maps the shading" $ do
      p <- converted (patterned fill [("P", tiling 1 [("Shading", P.ODict [("Sh", P.ODict (gray 0 1))])] "/Sh sh")] [])
      case selected p of
        Just (_, _, Just (_, body)) -> assertBool "sh" ("sh" `BS.isInfixOf` body)
        other -> assertFailure (show other),
    testCase "root ADR 0425 I11: a coloured tiling pattern inside a pattern maps both contents" $ do
      p <- converted (patterned fill [("P", tiling 1 [("Pattern", P.ODict [("Q", P.ORef 20)])] "/Pattern cs /Q scn 0 0 1 1 re f")] [] `withObjects` [(20, tiling 1 [] "0 g 0 0 1 1 re f")])
      assertBool "inner" (any (\(_, o) -> case o of P.OStream _ body -> "0 1 1 0 k" `BS.isInfixOf` body; _ -> False) (P.ipObjects p))
  ]

fill :: ByteString
fill = "/Pattern cs /P scn 0 0 1 1 re f"

-- | A page with patterns and colour spaces named in its resources.
patterned :: ByteString -> [(T.Text, P.ObjOf P.ObjNum)] -> [(T.Text, P.ObjOf P.ObjNum)] -> P.ImportedPage
patterned content patterns spaces =
  let numbered = zip [9 ..] patterns
   in (page content)
        { P.ipResources = P.ODict ([("Pattern", P.ODict [(name, P.ORef key) | (key, (name, _)) <- numbered])] <> [("ColorSpace", P.ODict spaces) | not (null spaces)]),
          P.ipObjects = [(key, object) | (key, (_, object)) <- numbered]
        }

withStates :: P.ImportedPage -> [(T.Text, P.ObjOf P.ObjNum)] -> P.ImportedPage
withStates p states = case P.ipResources p of
  P.ODict entries -> p {P.ipResources = P.ODict (entries <> [("ExtGState", P.ODict states)])}
  _ -> p

withObjects :: P.ImportedPage -> [(P.ObjNum, P.ObjOf P.ObjNum)] -> P.ImportedPage
withObjects p objects = p {P.ipObjects = P.ipObjects p <> objects}

-- | A tiling pattern of the given paint type, resources and content.
tiling :: Integer -> [(T.Text, P.ObjOf P.ObjNum)] -> ByteString -> P.ObjOf P.ObjNum
tiling paintType resources = P.OStream [("Type", P.OName "Pattern"), ("PatternType", P.OInt 1), ("PaintType", P.OInt paintType), ("TilingType", P.OInt 1), ("BBox", nums [0, 0, 2, 2]), ("XStep", P.OInt 2), ("YStep", P.OInt 2), ("Resources", P.ODict resources)]

shadingPattern :: [(T.Text, P.ObjOf P.ObjNum)] -> [(T.Text, P.ObjOf P.ObjNum)] -> P.ObjOf P.ObjNum
shadingPattern extra shading = P.ODict ([("Type", P.OName "Pattern"), ("PatternType", P.OInt 2), ("Shading", P.ODict shading)] <> extra)

axial :: T.Text -> P.ObjOf P.ObjNum -> [(T.Text, P.ObjOf P.ObjNum)]
axial space function = [("ShadingType", P.OInt 2), ("ColorSpace", P.OName space), ("Coords", nums [0, 0, 1, 0]), ("Function", function)]

gray :: Rational -> Rational -> [(T.Text, P.ObjOf P.ObjNum)]
gray c0 c1 = axial "DeviceGray" (fn2 [c0] [c1])

{- | The colour space, the components, and the pattern (its dictionary and
content) that the last @scn@ or @SCN@ of the content selects.
-}
selected :: P.ImportedPage -> Maybe (P.ObjOf P.ObjNum, [Rational], Maybe ([(T.Text, P.ObjOf P.ObjNum)], ByteString))
selected p = do
  operations <- P.contentOperations (P.ipContent p)
  P.ODict resources <- Just (P.ipResources p)
  let table category = case lookup category resources of
        Just value -> dictOf p value
        Nothing -> []
      named n = TE.decodeLatin1 (BS.drop 1 n)
      spaceOf n = if named n == "Pattern" then Just (P.OName "Pattern") else lookup (named n) (table "ColorSpace")
  (space : _) <- Just (reverse [s | (op, [n]) <- operations, op `elem` ["cs", "CS"], Just s <- [spaceOf n]])
  (args : _) <- Just (reverse [a | (op, a) <- operations, op `elem` ["scn", "SCN"]])
  let components = traverse (\a -> numbers (P.OArr [P.OReal (TE.decodeLatin1 a)])) (init args)
      object = lookup (named (last args)) (table "Pattern")
      resolve = \case
        P.ORef key -> lookup key (P.ipObjects p) >>= resolve
        P.OStream fields body -> Just (fields, body)
        P.ODict fields -> Just (fields, BS.empty)
        _ -> Nothing
      dereferenced = \case
        P.ORef key -> maybe (P.ORef key) dereferenced (lookup key (P.ipObjects p))
        other -> other
  Just (dereferenced space, maybe [] concat components, object >>= resolve)
