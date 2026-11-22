-- | Process-colour conversion of imported figures (root ADR 0403).
module Golem.Typeset.PdfColor (recolorImportedPage) where

import Control.Monad (foldM)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Char (isDigit)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Golem.Pdf qualified as P
import Golem.Typeset.FigureColor (Cmyk, RasterAnalysis, RasterKind (..))

-- A colour is kept in the source space until an operator actually paints it.
data Color = Gray !Rational | Rgb !Rational !Rational !Rational | CmykColor !Rational !Rational !Rational !Rational
  deriving stock (Eq, Show)

data Space = GraySpace | RgbSpace | CmykSpace

data Graphics = Graphics
  { fillColor :: !Color,
    strokeColor :: !Color,
    fillSpace :: !Space,
    strokeSpace :: !Space,
    textMode :: !Int
  }

data Scan = Scan !Graphics ![Graphics] !RasterKind ![ByteString]

{- | Nothing means that actual painting uses multiple colours, or paints nothing.
Form XObjects and raster resources are added to this traversal separately.
-}
recolorImportedPage :: Cmyk -> (P.ImageData -> Either Text RasterAnalysis) -> P.ImportedPage -> Either Text (Maybe P.ImportedPage)
recolorImportedPage swatch _ page = do
  operations <- maybe (Left "PDF 図版の描画命令を読めません") Right (P.contentOperations (P.ipContent page))
  Scan _ stack kind reversed <- foldM (step swatch) (Scan initial [] Unpainted []) operations
  if not (null stack)
    then Left "PDF 図版の描画状態が閉じていません"
    else case kind of
      Multicolor -> Right Nothing
      Unpainted -> Right Nothing
      _ ->
        let content = BC.unlines (paint swatch (Gray 0) False : paint swatch (Gray 0) True : reverse reversed)
            identity = P.sha256 (P.ipFile page <> BC.pack (show (P.ipPage page, swatch)) <> P.sha256 content)
         in Right (Just page {P.ipContent = content, P.ipFile = identity, P.ipColors = [P.UseCmyk]})
  where
    initial = Graphics (Gray 0) (Gray 0) GraySpace GraySpace 0

step :: Cmyk -> Scan -> (ByteString, [ByteString]) -> Either Text Scan
step swatch (Scan graphics stack kind output) (operator, args) = do
  let keep state saved seen bytes = Right (Scan state saved seen (bytes : output))
      original = BC.unwords (args <> [operator])
      same = keep graphics stack kind original
      painted colors = keep graphics stack (foldl mergeKind kind (map colorKind colors)) original
      colorOp isStroke space = do
        color <- parseColor space args
        let state = if isStroke then graphics {strokeColor = color, strokeSpace = space} else graphics {fillColor = color, fillSpace = space}
        keep state stack kind (paint swatch color isStroke)
      spaceOp isStroke = do
        space <- case args of
          ["/DeviceGray"] -> Right GraySpace
          ["/DeviceRGB"] -> Right RgbSpace
          ["/GolemSRGB"] -> Right RgbSpace
          ["/DeviceCMYK"] -> Right CmykSpace
          _ -> Left "PDF 図版の色空間の変換は未完了です"
        let zero = case space of
              GraySpace -> Gray 0
              RgbSpace -> Rgb 0 0 0
              CmykSpace -> CmykColor 0 0 0 1
            state = if isStroke then graphics {strokeSpace = space, strokeColor = zero} else graphics {fillSpace = space, fillColor = zero}
        keep state stack kind (paint swatch zero isStroke)
  case operator of
    "q" -> keep graphics (graphics : stack) kind original
    "Q" -> case stack of
      saved : rest -> keep saved rest kind original
      [] -> Left "PDF 図版の描画状態の復元先がありません"
    "g" -> colorOp False GraySpace
    "G" -> colorOp True GraySpace
    "rg" -> colorOp False RgbSpace
    "RG" -> colorOp True RgbSpace
    "k" -> colorOp False CmykSpace
    "K" -> colorOp True CmykSpace
    "cs" -> spaceOp False
    "CS" -> spaceOp True
    "sc" -> colorOp False (fillSpace graphics)
    "scn" -> colorOp False (fillSpace graphics)
    "SC" -> colorOp True (strokeSpace graphics)
    "SCN" -> colorOp True (strokeSpace graphics)
    "Tr" -> case args of
      [value] | Just n <- int value, n >= 0 && n <= 7 -> keep graphics {textMode = fromInteger n} stack kind original
      _ -> Left "PDF 図版のテキスト描画モードが不正です"
    _
      | operator `elem` ["f", "F", "f*"] -> painted [fillColor graphics]
      | operator `elem` ["S", "s"] -> painted [strokeColor graphics]
      | operator `elem` ["B", "B*", "b", "b*"] -> painted [fillColor graphics, strokeColor graphics]
      | operator `elem` ["Tj", "TJ", "'", "\""] -> painted ([fillColor graphics | textMode graphics `elem` [0, 2, 4, 6]] <> [strokeColor graphics | textMode graphics `elem` [1, 2, 5, 6]])
      | operator `elem` ["Do", "sh", "BI"] -> Left "PDF 図版の画像・Form・シェーディングの色変換は未完了です"
      | otherwise -> same

parseColor :: Space -> [ByteString] -> Either Text Color
parseColor space args = do
  values <- maybe (Left "PDF 図版の色の成分を読めません") Right (traverse decimal args)
  let clipped = map (max 0 . min 1) values
  case (space, clipped) of
    (GraySpace, [g]) -> Right (Gray g)
    (RgbSpace, [r, g, b]) -> Right (Rgb r g b)
    (CmykSpace, [c, m, y, k]) -> Right (CmykColor c m y k)
    _ -> Left "PDF 図版の色の成分数が不正です"

-- PDF decimal syntax, without floating-point equality in grey detection.
decimal :: ByteString -> Maybe Rational
decimal bytes =
  let (sign, body) = case BC.uncons bytes of
        Just ('-', rest) -> (-1, rest)
        Just ('+', rest) -> (1, rest)
        _ -> (1, bytes)
      (whole, fraction) = BC.break (== '.') body
   in if BS.null fraction
        then (fromInteger . (sign *)) <$> int whole
        else do
          let tailDigits = BS.drop 1 fraction
          if BS.null whole && BS.null tailDigits || not (BC.all isDigit whole && BC.all isDigit tailDigits)
            then Nothing
            else do
              a <- if BS.null whole then Just 0 else int whole
              b <- if BS.null tailDigits then Just 0 else int tailDigits
              let scale = 10 ^ BS.length tailDigits
              pure (sign * (a * scale + b) % scale)

int :: ByteString -> Maybe Integer
int bytes = case BC.readInteger bytes of
  Just (n, rest) | BS.null rest -> Just n
  _ -> Nothing

colorKind :: Color -> RasterKind
colorKind = \case
  Gray _ -> Grayscale
  Rgb r g b | r == g && g == b -> Grayscale
  Rgb r g b -> SolidRgb (r, g, b)
  CmykColor c m y _ | c == m && m == y -> Grayscale
  CmykColor c m y k -> SolidCmyk (c, m, y, k)

mergeKind :: RasterKind -> RasterKind -> RasterKind
mergeKind Unpainted next = next
mergeKind previous Unpainted = previous
mergeKind previous next | previous == next = previous
mergeKind _ _ = Multicolor

paint :: Cmyk -> Color -> Bool -> ByteString
paint (c, m, y, k) source isStroke =
  let amount = case source of
        Gray g -> 1 - g
        Rgb r g b | r == g && g == b -> 1 - g
        CmykColor a b d e | a == b && b == d -> min 1 (a + e)
        _ -> 1
      values = [fromIntegral component / 100 * amount | component <- [c, m, y, k]]
   in BC.unwords (map (TE.encodeUtf8 . P.showRationalDigits 8) values <> [if isStroke then "K" else "k"])
