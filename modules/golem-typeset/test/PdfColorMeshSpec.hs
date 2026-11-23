{- | Mesh shadings (ShadingType 4 to 7) painted by @sh@ in imported PDF
figures (root ADR 0425): the colours of their vertices and corners, and the
exact mapping of their colour Decode with the samples left unchanged.
-}
module PdfColorMeshSpec (pdfColorMeshTests) where

import Data.Bits (shiftR, (.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Pdf qualified as P
import PdfColorShadingSpec (converted, dictOf, fn2, inks, numbers, nums, page, recolor, rejected, shadingOf, tone)
import Test.Tasty
import Test.Tasty.HUnit

pdfColorMeshTests :: [TestTree]
pdfColorMeshTests =
  [ testGroup "root ADR 0425 I1: mesh shadings that cannot be judged" rejectTests,
    testGroup "root ADR 0425 I5: mesh shadings in the class of the figure" classTests,
    testGroup "root ADR 0425 I6: the mapped definitions of gray mesh shadings" mappingTests,
    testGroup "root ADR 0425 I7: gray mesh shadings that cannot be recoloured" unreplaceableTests
  ]

rejectTests :: [TestTree]
rejectTests =
  [ testCase "root ADR 0425 I1: a mesh whose data ends inside a vertex is G08113" $
      rejected (meshed (free 4 "DeviceGray" 8 8 8 [0, 1, 0, 1, 0, 1]) (BS.take 6 (bits [(8, 0), (8, 0), (8, 0), (8, 0), (8, 0), (8, 9), (8, 9)]))),
    testCase "root ADR 0425 I1: a mesh whose Decode lacks the colour pairs is G08113" $
      rejected (meshed (free 4 "DeviceGray" 8 8 8 [0, 1, 0, 1]) (triangle [[0], [128], [255]])),
    testCase "root ADR 0425 I1: a patch flag outside 0 to 3 is G08113" $
      rejected (meshed (free 6 "DeviceGray" 8 8 8 [0, 1, 0, 1, 0, 1]) (bits ((8, 4) : replicate 24 (8, 0) <> replicate 4 (8, 0))))
  ]

classTests :: [TestTree]
classTests =
  [ testCase "root ADR 0425 I5: a one-colour mesh without a function paints the swatch at every vertex" $ do
      p <- converted (meshed (free 4 "DeviceRGB" 8 8 8 [0, 1, 0, 1, 0, 1, 0, 1, 0, 1]) (triangle [[255, 0, 0], [255, 0, 0], [255, 0, 0]]))
      let (fields, body) = meshOf p
      lookup "ColorSpace" fields @?= Just (P.OName "DeviceCMYK")
      (numbers =<< lookup "Decode" fields) @?= Just ([0, 1, 0, 1] <> concat [[s, s] | s <- inks])
      body @?= triangle [replicate 4 255, replicate 4 255, replicate 4 255],
    testCase "root ADR 0425 I5: a red-to-blue Coons patch mesh keeps the original colours" $
      recolor (meshed (free 6 "DeviceRGB" 8 8 8 [0, 1, 0, 1, 0, 1, 0, 1, 0, 1]) (patch 12 [[255, 0, 0], [0, 0, 255], [255, 0, 0], [0, 0, 255]])) @?= Right Nothing,
    testCase "root ADR 0425 I5: a gray rectangle and a red tensor-product mesh keep the original colours" $
      recolor ((meshed (free 7 "DeviceRGB" 8 8 8 [0, 1, 0, 1, 0, 1, 0, 1, 0, 1]) (patch 16 (replicate 4 [255, 0, 0]))) {P.ipContent = ".5 g 0 0 1 1 re f /Sh sh"}) @?= Right Nothing,
    testCase "root ADR 0425 I5: a one-colour mesh with a function paints the swatch" $ do
      p <- converted (meshed (withFunction (fn2 [1, 0, 0] [1, 0, 0]) (lattice "DeviceRGB" [0, 1, 0, 1, 0, 1])) (bits [(8, 0), (8, 0), (8, 0), (8, 1), (8, 0), (8, 255), (8, 0), (8, 1), (8, 0), (8, 1), (8, 1), (8, 255)]))
      let (_, function) = shadingOf p
      (numbers =<< lookup "C0" function) @?= Just inks
      (numbers =<< lookup "C1" function) @?= Just inks
  ]

mappingTests :: [TestTree]
mappingTests =
  [ testCase "root ADR 0425 I6: gray vertices of a ShadingType 4 map their Decode and repeat each sample" $ do
      p <- converted (meshed (free 4 "DeviceGray" 8 8 8 [0, 2, 0, 2, 0, 1]) (triangle [[0], [128], [255]]))
      let (fields, body) = meshOf p
      lookup "ColorSpace" fields @?= Just (P.OName "DeviceCMYK")
      (numbers =<< lookup "Decode" fields) @?= Just ([0, 2, 0, 2] <> concat [tone 0 !! i : [tone 1 !! i] | i <- [0 .. 3]])
      [lookup name fields | name <- ["BitsPerCoordinate", "BitsPerComponent", "BitsPerFlag"]] @?= map (Just . P.OInt) [8, 8, 8]
      body @?= triangle [replicate 4 0, replicate 4 128, replicate 4 255],
    testCase "root ADR 0425 I6: vertices that do not fill a byte stay aligned to bytes" $ do
      p <- converted (meshed (free 4 "DeviceGray" 8 2 4 [0, 1, 0, 1, 0, 1]) (BS.concat [bits [(2, 0), (8, 1), (8, 2), (4, v)] | v <- [0, 7, 15]]))
      let (fields, body) = meshOf p
      (numbers =<< lookup "Decode" fields) @?= Just ([0, 1, 0, 1] <> concat [[s, 0] | s <- inks])
      body @?= BS.concat [bits ([(2, 0), (8, 1), (8, 2)] <> replicate 4 (4, v)) | v <- [0, 7, 15]],
    testCase "root ADR 0425 I6: a DeviceRGB lattice of equal components maps R" $ do
      p <- converted (meshed (lattice "DeviceRGB" [0, 1, 0, 1, 0, 1, 0, 1, 0, 1]) (BS.concat [bits [(8, x), (8, y), (8, v), (8, v), (8, v)] | (x, y, v) <- [(0, 0, 0), (255, 0, 51), (0, 255, 102), (255, 255, 255)]]))
      let (fields, body) = meshOf p
      (numbers =<< lookup "Decode" fields) @?= Just ([0, 1, 0, 1] <> concat [[s, 0] | s <- inks])
      lookup "VerticesPerRow" fields @?= Just (P.OInt 2)
      body @?= BS.concat [bits ([(8, x), (8, y)] <> replicate 4 (8, v)) | (x, y, v) <- [(0, 0, 0), (255, 0, 51), (0, 255, 102), (255, 255, 255)]],
    testCase "root ADR 0425 I6: gray corners of a ShadingType 6 map and keep the coordinates" $ do
      p <- converted (meshed (free 6 "DeviceGray" 8 8 8 [0, 1, 0, 1, 0, 1]) (patch 12 [[0], [64], [128], [255]] <> continued 8 [[32], [96]]))
      let (fields, body) = meshOf p
      (numbers =<< lookup "Decode" fields) @?= Just ([0, 1, 0, 1] <> concat [[s, 0] | s <- inks])
      body @?= patch 12 (map (replicate 4) [0, 64, 128, 255]) <> continued 8 (map (replicate 4) [32, 96]),
    testCase "root ADR 0425 I6: gray corners of a ShadingType 7 map" $ do
      p <- converted (meshed (free 7 "DeviceCMYK" 8 8 8 [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1]) (patch 16 [[0, 0, 0, v] | v <- [0, 85, 170, 255]]))
      let (fields, body) = meshOf p
      (numbers =<< lookup "Decode" fields) @?= Just ([0, 1, 0, 1] <> concat [[0, s] | s <- inks])
      body @?= patch 16 (map (replicate 4) [0, 85, 170, 255]),
    testCase "root ADR 0425 I6: a ShadingType 5 with a function maps the function and keeps the data" $ do
      let body = bits [(8, 0), (8, 0), (8, 0), (8, 255), (8, 0), (8, 128), (8, 0), (8, 255), (8, 64), (8, 255), (8, 255), (8, 255)]
      p <- converted (meshed (withFunction (fn2 [0] [1]) (lattice "DeviceGray" [0, 1, 0, 1, 0, 1])) body)
      let (fields, kept) = meshOf p
          (_, function) = shadingOf p
      kept @?= body
      (numbers =<< lookup "Decode" fields) @?= Just [0, 1, 0, 1, 0, 1]
      (numbers =<< lookup "C0" function) @?= Just (tone 0)
      (numbers =<< lookup "C1" function) @?= Just (tone 1),
    testCase "root ADR 0425 I6: a gray Background of a mesh maps with the vertices" $ do
      p <- converted (meshed (free 4 "DeviceGray" 8 8 8 [0, 1, 0, 1, 0, 1] <> [("Background", nums [0.5])]) (triangle [[0], [128], [255]]))
      (numbers =<< lookup "Background" (fst (meshOf p))) @?= Just (tone 0.5)
  ]

unreplaceableTests :: [TestTree]
unreplaceableTests =
  [ testCase "root ADR 0425 I7: DeviceCMYK vertices with C = M = Y = 0.2 are G08113" $
      rejected (meshed (free 4 "DeviceCMYK" 8 8 8 [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1]) (triangle [[51, 51, 51, 0], [51, 51, 51, 128], [51, 51, 51, 255]])),
    testCase "root ADR 0425 I7: gray vertex values outside the space are G08113" $
      rejected (meshed (free 4 "DeviceGray" 8 8 8 [0, 1, 0, 1, -1, 1]) (triangle [[0], [128], [255]])),
    testCase "root ADR 0425 I7: a red rectangle and those DeviceCMYK vertices keep the original colours" $
      recolor ((meshed (free 4 "DeviceCMYK" 8 8 8 [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1]) (triangle [[51, 51, 51, 0], [51, 51, 51, 128], [51, 51, 51, 255]])) {P.ipContent = "1 0 0 rg 0 0 1 1 re f /Sh sh"}) @?= Right Nothing
  ]

-- | A page painting the mesh shading Sh (object 9) with the given data.
meshed :: [(T.Text, P.ObjOf P.ObjNum)] -> ByteString -> P.ImportedPage
meshed fields body = (page "/Sh sh") {P.ipResources = P.ODict [("Shading", P.ODict [("Sh", P.ORef 9)])], P.ipObjects = [(9, P.OStream fields body)]}

-- | A free-form or patch mesh: type, space, coordinate, flag and component bits, Decode.
free :: Integer -> T.Text -> Integer -> Integer -> Integer -> [Rational] -> [(T.Text, P.ObjOf P.ObjNum)]
free kind space coordinate flag component decode = [("ShadingType", P.OInt kind), ("ColorSpace", P.OName space), ("BitsPerCoordinate", P.OInt coordinate), ("BitsPerFlag", P.OInt flag), ("BitsPerComponent", P.OInt component), ("Decode", nums decode)]

-- | A lattice of two vertices per row with 8-bit coordinates and components.
lattice :: T.Text -> [Rational] -> [(T.Text, P.ObjOf P.ObjNum)]
lattice space decode = [("ShadingType", P.OInt 5), ("ColorSpace", P.OName space), ("BitsPerCoordinate", P.OInt 8), ("BitsPerComponent", P.OInt 8), ("VerticesPerRow", P.OInt 2), ("Decode", nums decode)]

withFunction :: P.ObjOf P.ObjNum -> [(T.Text, P.ObjOf P.ObjNum)] -> [(T.Text, P.ObjOf P.ObjNum)]
withFunction function fields = fields <> [("Function", function)]

-- | One triangle of 8-bit flags, coordinates and components.
triangle :: [[Integer]] -> ByteString
triangle colours = BS.concat [bits ((8, 0) : (8, x) : (8, 0) : [(8, c) | c <- colour]) | (x, colour) <- zip [0, 128, 255] colours]

-- | A patch of flag 0 with the given number of points and four corner colours.
patch :: Int -> [[Integer]] -> ByteString
patch points colours = bits ((8, 0) : [(8, fromIntegral i) | i <- [1 .. 2 * points]] <> [(8, c) | colour <- colours, c <- colour])

-- | A patch of flag 1 that continues the previous one with two colours.
continued :: Int -> [[Integer]] -> ByteString
continued points colours = bits ((8, 1) : [(8, fromIntegral i) | i <- [1 .. 2 * points]] <> [(8, c) | colour <- colours, c <- colour])

-- | Big-endian fields of the given widths, padded with zeros to a byte.
bits :: [(Int, Integer)] -> ByteString
bits fields =
  let stream = concat [[(value `shiftR` (width - 1 - i)) .&. 1 | i <- [0 .. width - 1]] | (width, value) <- fields]
      bytesOf [] = []
      bytesOf xs = let (byte, rest) = splitAt 8 xs in fromInteger (foldl (\acc b -> acc * 2 + b) 0 (take 8 (byte <> repeat 0))) : bytesOf rest
   in BS.pack (bytesOf stream)

-- | The converted mesh painted by the content: its dictionary and data.
meshOf :: P.ImportedPage -> ([(T.Text, P.ObjOf P.ObjNum)], ByteString)
meshOf p = case P.contentOperations (P.ipContent p) of
  Just operations
    | name : _ <- [TE.decodeLatin1 (BS.drop 1 n) | ("sh", [n]) <- operations],
      P.ODict resources <- P.ipResources p,
      Just (P.ODict table) <- lookup "Shading" resources,
      Just (P.ORef key) <- lookup name table,
      Just (P.OStream fields body) <- lookup key (P.ipObjects p) ->
        (fields, body)
  _ -> (dictOf p P.ONull, BS.empty)
