{- | Function-based shadings painted by @sh@ in imported PDF figures
(root ADR 0425): the colours they add to the figure, the shadings that
cannot be recoloured, and the exact mapping of their definitions.
-}
module PdfColorShadingSpec (pdfColorShadingTests) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Maybe (fromMaybe)
import Data.Ratio ((%))
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Pdf qualified as P
import Golem.Typeset.FigureColor (analyzeRaster)
import Golem.Typeset.PdfColor (recolorImportedPage)
import Test.Tasty
import Test.Tasty.HUnit

swatch :: (Int, Int, Int, Int)
swatch = (0, 100, 100, 0)

-- | The swatch components as fractions.
inks :: [Rational]
inks = [0, 1, 1, 0]

-- | The tone of gray value g in each ink.
tone :: Rational -> [Rational]
tone g = [s * (1 - g) | s <- inks]

recolor :: P.ImportedPage -> Either T.Text (Maybe P.ImportedPage)
recolor = recolorImportedPage swatch (analyzeRaster swatch)

pdfColorShadingTests :: [TestTree]
pdfColorShadingTests =
  [ testGroup "root ADR 0425 I1: shadings that cannot be judged" rejectTests,
    testGroup "root ADR 0425 I5: shadings in the class of the figure" classTests,
    testGroup "root ADR 0425 I6: the mapped definitions of gray shadings" mappingTests,
    testGroup "root ADR 0425 I7: gray shadings that cannot be recoloured" unreplaceableTests
  ]

rejectTests :: [TestTree]
rejectTests =
  [ testCase "root ADR 0425 I1: an axial shading of a FunctionType 4 function is G08113" $
      rejected (shaded "/Sh sh" (axial "DeviceGray" (P.ORef 8)) [(8, P.OStream [("FunctionType", P.OInt 4), ("Domain", nums [0, 1]), ("Range", nums [0, 1])] "{ }")]),
    testCase "root ADR 0425 I1: OPM 1 with op true when painting a shading is G08113" $
      rejected
        ( (shaded "/S gs /Sh sh" (axial "DeviceGray" (fn2 [0] [1])) [])
            { P.ipResources = P.ODict [("Shading", P.ODict [("Sh", P.ORef 9)]), ("ExtGState", P.ODict [("S", P.ODict [("OPM", P.OInt 1), ("op", P.OBool True)])])]
            }
        )
  ]

classTests :: [TestTree]
classTests =
  [ testCase "root ADR 0425 I5: a gray rectangle and a red one-colour shading keep the original colours" $
      recolor (shaded ".5 g 0 0 1 1 re f /Sh sh" (axial "DeviceRGB" (fn2 [1, 0, 0] [1, 0, 0])) []) @?= Right Nothing,
    testCase "root ADR 0425 I5: a red rectangle and the same red one-colour shading are all the swatch" $ do
      p <- converted (shaded "1 0 0 rg 0 0 1 1 re f /Sh sh" (axial "DeviceRGB" (fn2 [1, 0, 0] [1, 0, 0])) [])
      assertBool "rectangle" ("0 1 1 0 k" `BS.isInfixOf` P.ipContent p)
      let (fields, function) = shadingOf p
      lookup "ColorSpace" fields @?= Just (P.OName "DeviceCMYK")
      lookup "FunctionType" function @?= Just (P.OInt 2)
      (numbers =<< lookup "C0" function) @?= Just inks
      (numbers =<< lookup "C1" function) @?= Just inks,
    testCase "root ADR 0425 I5: a white-only shading and a white rectangle stay white" $ do
      p <- converted (shaded "1 g 0 0 1 1 re f /Sh sh" (axial "DeviceGray" (fn2 [1] [1])) [])
      let (_, function) = shadingOf p
      (numbers =<< lookup "C0" function) @?= Just (tone 1)
      (numbers =<< lookup "C1" function) @?= Just (tone 1),
    testCase "root ADR 0425 I5: a figure of only a gray shading is recoloured" $ do
      p <- converted (shaded "/Sh sh" (axial "DeviceGray" (fn2 [0.25] [0.75])) [])
      let (_, function) = shadingOf p
      (numbers =<< lookup "C0" function) @?= Just (tone (1 % 4)),
    testCase "root ADR 0425 I5: a figure of only a red one-colour shading is the swatch" $ do
      p <- converted (shaded "/Sh sh" (axial "DeviceRGB" (fn2 [1, 0, 0] [1, 0, 0])) [])
      let (_, function) = shadingOf p
      (numbers =<< lookup "C1" function) @?= Just inks,
    testCase "root ADR 0425 I5: a red-to-blue shading keeps the original colours" $
      recolor (shaded "/Sh sh" (axial "DeviceRGB" (fn2 [1, 0, 0] [0, 0, 1])) []) @?= Right Nothing,
    testCase "root ADR 0425 I5: DeviceRGB C0 (1.2, 1, 1) and C1 (0, 0, 0) is multicolour, not clipped" $
      recolor (shaded "/Sh sh" (axial "DeviceRGB" (fn2 [1.2, 1, 1] [0, 0, 0])) []) @?= Right Nothing,
    testCase "root ADR 0425 I5: a shading behind a zero fill alpha adds no colour" $ do
      _ <- converted ((shaded "/A gs /Sh sh /B gs .5 g 0 0 1 1 re f" (axial "DeviceRGB" (fn2 [1, 0, 0] [0, 0, 1])) []) {P.ipResources = P.ODict [("Shading", P.ODict [("Sh", P.ORef 9)]), ("ExtGState", P.ODict [("A", P.ODict [("ca", P.OInt 0)]), ("B", P.ODict [("ca", P.OInt 1)])])]})
      pure ()
  ]

mappingTests :: [TestTree]
mappingTests =
  [ testCase "root ADR 0425 I6: DeviceGray FunctionType 2 from black to white maps C0 and C1 and keeps N and Domain" $ do
      p <- converted (shaded "/Sh sh" (axial "DeviceGray" (P.ODict [("FunctionType", P.OInt 2), ("Domain", nums [0, 1]), ("C0", nums [0]), ("C1", nums [1]), ("N", P.OReal "1.5")])) [])
      let (fields, function) = shadingOf p
      lookup "ColorSpace" fields @?= Just (P.OName "DeviceCMYK")
      lookup "Coords" fields @?= Just (nums [0, 0, 1, 0])
      (numbers =<< lookup "C0" function) @?= Just (tone 0)
      (numbers =<< lookup "C1" function) @?= Just (tone 1)
      lookup "N" function @?= Just (P.OReal "1.5")
      lookup "Domain" function @?= Just (nums [0, 1]),
    testCase "root ADR 0425 I6: omitted C0 and C1 map the defaults 0 and 1" $ do
      p <- converted (shaded "/Sh sh" (axial "DeviceGray" (P.ODict [("FunctionType", P.OInt 2), ("Domain", nums [0, 1]), ("N", P.OInt 1)])) [])
      let (_, function) = shadingOf p
      (numbers =<< lookup "C0" function) @?= Just (tone 0)
      (numbers =<< lookup "C1" function) @?= Just (tone 1),
    testCase "root ADR 0425 I6: a FunctionType 0 of Order 3 and four samples without Decode maps Range as Decode" $ do
      let sampled = P.OStream [("FunctionType", P.OInt 0), ("Domain", nums [0, 1]), ("Range", nums [0, 1]), ("Size", nums [4]), ("BitsPerSample", P.OInt 8), ("Order", P.OInt 3)] (BS.pack [0, 85, 170, 255])
      p <- converted (shaded "/Sh sh" (axial "DeviceGray" (P.ORef 8)) [(8, sampled)])
      let (_, function) = shadingOf p
          (_, samples) = streamOf p "Function"
      samples @?= BS.concatMap (BS.replicate 4) (BS.pack [0, 85, 170, 255])
      (numbers =<< lookup "Decode" function) @?= Just (concat [[s, 0] | s <- inks])
      (numbers =<< lookup "Range" function) @?= Just (concat [[0, s] | s <- inks])
      lookup "Size" function @?= Just (nums [4])
      lookup "BitsPerSample" function @?= Just (P.OInt 8)
      lookup "Order" function @?= Just (P.OInt 3)
      lookup "Domain" function @?= Just (nums [0, 1]),
    testCase "root ADR 0425 I6: a Range [0.2, 0.8] maps to ordered pairs" $ do
      p <- converted (shaded "/Sh sh" (axial "DeviceGray" (P.ODict [("FunctionType", P.OInt 2), ("Domain", nums [0, 1]), ("Range", nums [0.2, 0.8]), ("C0", nums [0.2]), ("C1", nums [0.8]), ("N", P.OInt 1)])) [])
      let (_, function) = shadingOf p
      (numbers =<< lookup "Range" function) @?= Just (concat [let (a, b) = (s * (1 - 0.8), s * (1 - 0.2)) in [a, b] | s <- inks]),
    testCase "root ADR 0425 I6: an array of three equal DeviceRGB functions becomes an array of four" $ do
      let one = fn2 [0.25] [0.75]
      p <- converted (shaded "/Sh sh" (axial "DeviceRGB" (P.OArr [one, one, one])) [])
      case lookup "Function" (fst (shadingOf p)) of
        Just (P.OArr functions) -> do
          length functions @?= 4
          [numbers =<< lookup "C0" (dictOf p f) | f <- functions] @?= [Just [s * (1 - 0.25)] | s <- inks]
          [numbers =<< lookup "C1" (dictOf p f) | f <- functions] @?= [Just [s * (1 - 0.75)] | s <- inks]
        other -> assertFailure (show other),
    testCase "root ADR 0425 I6: a FunctionType 3 of gray functions maps each and keeps Bounds and Encode" $ do
      let stitched = P.ODict [("FunctionType", P.OInt 3), ("Domain", nums [0, 1]), ("Functions", P.OArr [fn2 [0] [0.5], fn2 [0.5] [1]]), ("Bounds", nums [0.5]), ("Encode", nums [0, 1, 0, 1])]
      p <- converted (shaded "/Sh sh" (axial "DeviceGray" stitched) [])
      let (_, function) = shadingOf p
      lookup "Bounds" function @?= Just (nums [0.5])
      lookup "Encode" function @?= Just (nums [0, 1, 0, 1])
      case lookup "Functions" function of
        Just (P.OArr [a, b]) -> do
          (numbers =<< lookup "C0" (dictOf p a)) @?= Just (tone 0)
          (numbers =<< lookup "C1" (dictOf p a)) @?= Just (tone 0.5)
          (numbers =<< lookup "C1" (dictOf p b)) @?= Just (tone 1)
        other -> assertFailure (show other),
    testCase "root ADR 0425 I6: a Lab FunctionType 2 with a* and b* zero maps L* over 100" $ do
      p <- converted (shaded "/Sh sh" (axial "Lab" (fn2 [25, 0, 0] [75, 0, 0])) [])
      let (_, function) = shadingOf p
      (numbers =<< lookup "C0" function) @?= Just (tone 0.25)
      (numbers =<< lookup "C1" function) @?= Just (tone 0.75),
    testCase "root ADR 0425 I6: a DeviceCMYK FunctionType 2 with C, M, Y zero maps K" $ do
      p <- converted (shaded "/Sh sh" (axial "DeviceCMYK" (fn2 [0, 0, 0, 0.2] [0, 0, 0, 1])) [])
      let (_, function) = shadingOf p
      (numbers =<< lookup "C0" function) @?= Just (tone 0.8)
      (numbers =<< lookup "C1" function) @?= Just (tone 0),
    testCase "root ADR 0425 I6: a function without Range gets the mapped range of the colour space" $ do
      p <- converted (shaded "/Sh sh" (axial "DeviceGray" (fn2 [0] [1])) [])
      let (_, function) = shadingOf p
      (numbers =<< lookup "Range" function) @?= Just (concat [[0, s] | s <- inks]),
    testCase "root ADR 0425 I5: a one-colour function shading (type 1) keeps a function of two inputs" $ do
      let sampled = P.OStream [("FunctionType", P.OInt 0), ("Domain", nums [0, 1, 0, 1]), ("Range", nums [0, 1, 0, 1, 0, 1]), ("Size", nums [1, 1]), ("BitsPerSample", P.OInt 8)] (BS.pack [255, 0, 0])
      p <- converted (shaded "/Sh sh" [("ShadingType", P.OInt 1), ("ColorSpace", P.OName "DeviceRGB"), ("Function", P.ORef 8)] [(8, sampled)])
      let (_, function) = shadingOf p
      lookup "Domain" function @?= Just (nums [0, 1, 0, 1])
      (numbers =<< lookup "Decode" function) @?= Just (concat [[s, s] | s <- inks]),
    testCase "root ADR 0425 I6: a gray Background maps with the function" $ do
      p <- converted (shaded "/Sh sh" ((axialFields "DeviceGray" (fn2 [0] [1])) <> [("Background", nums [0.5])]) [])
      (numbers =<< lookup "Background" (fst (shadingOf p))) @?= Just (tone 0.5)
  ]

unreplaceableTests :: [TestTree]
unreplaceableTests =
  [ testCase "root ADR 0425 I7: an array of DeviceRGB functions with different numbers of values is G08113, even beside red" $ do
      let sampled = P.OStream [("FunctionType", P.OInt 0), ("Domain", nums [0, 1]), ("Range", nums [0, 1]), ("Size", nums [3]), ("BitsPerSample", P.OInt 8)] (BS.pack [0, 128, 255])
      rejected (shaded "/Sh sh" (axial "DeviceRGB" (P.OArr [fn2 [0] [1], P.ORef 8, fn2 [0] [1]])) [(8, sampled)])
      rejected (shaded "1 0 0 rg 0 0 1 1 re f /Sh sh" (axial "DeviceRGB" (P.OArr [fn2 [0] [1], P.ORef 8, fn2 [0] [1]])) [(8, sampled)]),
    testCase "root ADR 0425 I7: a DeviceCMYK array whose functions differ in N is G08113" $
      rejected (shaded "/Sh sh" (axial "DeviceCMYK" (P.OArr [fn2 [0] [0], fn2 [0] [0], fn2 [0] [0], P.ODict [("FunctionType", P.OInt 2), ("Domain", nums [0, 1]), ("C0", nums [0]), ("C1", nums [1]), ("N", P.OInt 2)]])) []),
    testCase "root ADR 0425 I7: DeviceRGB with a different N for one output and gray ends is G08113" $
      rejected (shaded "/Sh sh" (axial "DeviceRGB" (P.OArr [fn2 [0] [1], P.ODict [("FunctionType", P.OInt 2), ("Domain", nums [0, 1]), ("C0", nums [0]), ("C1", nums [1]), ("N", P.OInt 2)], fn2 [0] [1]])) []),
    testCase "root ADR 0425 I7: DeviceCMYK values with C = M = Y = 0.2 are G08113" $
      rejected (shaded "/Sh sh" (axial "DeviceCMYK" (fn2 [0.2, 0.2, 0.2, 0] [0.2, 0.2, 0.2, 1])) []),
    testCase "root ADR 0425 I7: a red rectangle and that DeviceCMYK shading keep the original colours" $
      recolor (shaded "1 0 0 rg 0 0 1 1 re f /Sh sh" (axial "DeviceCMYK" (fn2 [0.2, 0.2, 0.2, 0] [0.2, 0.2, 0.2, 1])) []) @?= Right Nothing,
    testCase "root ADR 0425 I7: a DeviceGray FunctionType 2 without Range on Domain [0, 2] is G08113" $
      rejected (shaded "/Sh sh" ((axialFields "DeviceGray" (P.ODict [("FunctionType", P.OInt 2), ("Domain", nums [0, 2]), ("C0", nums [0]), ("C1", nums [1]), ("N", P.OInt 1)])) <> [("Domain", nums [0, 2])]) []),
    testCase "root ADR 0425 I7: a DeviceGray function of Range [-1, 1] is G08113" $
      rejected (shaded "/Sh sh" (axial "DeviceGray" (P.ODict [("FunctionType", P.OInt 2), ("Domain", nums [0, 1]), ("Range", nums [-1, 1]), ("C0", nums [-0.5]), ("C1", nums [1]), ("N", P.OInt 1)])) []),
    testCase "root ADR 0425 I7: Lab a* outputs all 0 with an a* Range of [1, 5] are G08113" $
      rejected (shaded "/Sh sh" (axialIn (P.OArr [P.OName "Lab", P.ODict [("WhitePoint", nums [0.9505, 1, 1.089]), ("Range", nums [1, 5, -100, 100])]]) (fn2 [25, 0, 0] [75, 0, 0])) []),
    testCase "root ADR 0425 I7: an array of three unequal DeviceRGB functions is G08113" $
      rejected (shaded "/Sh sh" (axial "DeviceRGB" (P.OArr [fn2 [0] [1], P.ODict [("FunctionType", P.OInt 2), ("Domain", nums [0, 2]), ("C0", nums [0]), ("C1", nums [1]), ("N", P.OInt 1)], fn2 [0] [1]])) [])
  ]

rejected :: P.ImportedPage -> Assertion
rejected p = case recolor p of
  Left _ -> pure ()
  other -> assertFailure ("expected G08113, got " <> show other)

converted :: P.ImportedPage -> IO P.ImportedPage
converted p = case recolor p of
  Right (Just result) -> pure result
  other -> assertFailure (show other) >> pure p

page :: ByteString -> P.ImportedPage
page content = P.ImportedPage "source" 1 (0, 0, 30, 10) 0 (30, 10) (P.ODict []) Nothing content [] [P.UseGray] 0

-- | A page painting the shading named Sh (object 9) with further objects.
shaded :: ByteString -> [(T.Text, P.ObjOf P.ObjNum)] -> [(P.ObjNum, P.ObjOf P.ObjNum)] -> P.ImportedPage
shaded content fields objects = (page content) {P.ipResources = P.ODict [("Shading", P.ODict [("Sh", P.ORef 9)])], P.ipObjects = (9, P.ODict fields) : objects}

axial :: T.Text -> P.ObjOf P.ObjNum -> [(T.Text, P.ObjOf P.ObjNum)]
axial space = axialFields space

axialFields :: T.Text -> P.ObjOf P.ObjNum -> [(T.Text, P.ObjOf P.ObjNum)]
axialFields space = axialIn (if space == "Lab" then P.OArr [P.OName "Lab", P.ODict [("WhitePoint", nums [0.9505, 1, 1.089])]] else P.OName space)

axialIn :: P.ObjOf P.ObjNum -> P.ObjOf P.ObjNum -> [(T.Text, P.ObjOf P.ObjNum)]
axialIn space function = [("ShadingType", P.OInt 2), ("ColorSpace", space), ("Coords", nums [0, 0, 1, 0]), ("Function", function)]

fn2 :: [Rational] -> [Rational] -> P.ObjOf P.ObjNum
fn2 c0 c1 = P.ODict [("FunctionType", P.OInt 2), ("Domain", nums [0, 1]), ("C0", nums c0), ("C1", nums c1), ("N", P.OInt 1)]

nums :: [Rational] -> P.ObjOf P.ObjNum
nums = P.OArr . map number
  where
    number r
      | r == fromInteger (round r) = P.OInt (round r)
      | otherwise = P.OReal (T.pack (decimalText r))
    decimalText r = let sign = if r < 0 then "-" else ""; a = abs r; whole = floor a :: Integer; frac = a - fromInteger whole in sign <> show whole <> "." <> digits frac
    digits f | f == 0 = "" | otherwise = let d = floor (f * 10) :: Integer in show d <> digits (f * 10 - fromInteger d)

-- | The numbers of an array, exactly.
numbers :: P.ObjOf P.ObjNum -> Maybe [Rational]
numbers (P.OArr values) = traverse number values
  where
    number (P.OInt n) = Just (fromInteger n)
    number (P.OReal text) = exact (TE.encodeUtf8 text)
    number _ = Nothing
    exact bytes =
      let (sign, body) = maybe (1, bytes) (\(c, rest) -> if c == '-' then (-1, rest) else (1, bytes)) (BC.uncons bytes)
          (whole, fraction) = BC.break (== '.') body
          digits = BS.drop 1 fraction
       in do
            a <- if BS.null whole then Just 0 else fst <$> BC.readInteger whole
            b <- if BS.null digits then Just 0 else fst <$> BC.readInteger digits
            Just (sign * (fromInteger a + b % (10 ^ BS.length digits)))
numbers _ = Nothing

-- | The converted shading painted by the content, and its function's dictionary.
shadingOf :: P.ImportedPage -> ([(T.Text, P.ObjOf P.ObjNum)], [(T.Text, P.ObjOf P.ObjNum)])
shadingOf p =
  let fields = fromMaybe [] (paintedShading p)
   in (fields, maybe [] (dictOf p) (lookup "Function" fields))

paintedShading :: P.ImportedPage -> Maybe [(T.Text, P.ObjOf P.ObjNum)]
paintedShading p = do
  operations <- P.contentOperations (P.ipContent p)
  name : _ <- Just [TE.decodeLatin1 (BS.drop 1 n) | ("sh", [n]) <- operations]
  P.ODict resources <- Just (P.ipResources p)
  P.ODict table <- lookup "Shading" resources
  value <- lookup name table
  Just (dictOf p value)

dictOf :: P.ImportedPage -> P.ObjOf P.ObjNum -> [(T.Text, P.ObjOf P.ObjNum)]
dictOf p = \case
  P.ODict fields -> fields
  P.OStream fields _ -> fields
  P.ORef key -> maybe [] (dictOf p) (lookup key (P.ipObjects p))
  _ -> []

streamOf :: P.ImportedPage -> T.Text -> ([(T.Text, P.ObjOf P.ObjNum)], ByteString)
streamOf p name = case lookup name (fst (shadingOf p)) of
  Just (P.ORef key) | Just (P.OStream fields bytes) <- lookup key (P.ipObjects p) -> (fields, bytes)
  _ -> ([], BS.empty)
