{- | The checks of golem preflight (golem-cli ADR 0006): pure functions from
the rules and a view of the PDF to diagnostics G0902 to G0918. A check
reports a cause once, at its first place, with every page in the fact
@pdf-pages@ and the first ten pages in the message.
-}
module Golem.Preflight
  ( check,
    pagesPhrase,
    mmText,
  )
where

import Data.ByteString (ByteString)
import Data.Char (GeneralCategory (..), generalCategory, isControl, ord)
import Data.List (nub, sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.LayoutSpec (Rect (..))
import Golem.Pdf (ColorSpace (..), ColorUse (..), FigureContent (..), ImageData (..), ImportedPage (..), X4Problem (..))
import Golem.Preflight.Rules
import Golem.Preflight.View
import Golem.Project.Style (Sp)
import Golem.Syntax
import Numeric (showHex)

check :: Rules -> View -> [Diagnostic]
check r v =
  concat
    [ glyphMissing r v,
      fontFormats r v,
      typeSize r v,
      imageResolution r v,
      imageResolutionMax r v,
      imageColorSpace r v,
      imageIcc r v,
      bleedSize r v,
      trimHazard r v,
      liveArea r v,
      overfullLines r v,
      pdfX r v,
      inkCoverage r v,
      pageCount r v,
      blankPages r v,
      strokeWeight r v
    ]

-- ------------------------------------------------------------------ helpers

severityOf :: Level -> Maybe Severity
severityOf = \case
  LevelError -> Just Error
  LevelWarning -> Just Warning
  LevelOff -> Nothing

-- | A diagnostic at a level; nothing when the check is off.
at :: Level -> Text -> SrcSpan -> Text -> [(Text, Fact)] -> [Diagnostic]
at level code sp msg facts = [(diagnostic code sev sp msg) {diagFacts = facts} | Just sev <- [severityOf level]]

{- | Groups by a key in the order of the first occurrence, with the pages of
each group in order.
-}
groups :: (Ord k) => [(k, Int, a)] -> [(k, [Int], [a])]
groups xs =
  let keys = nub [k | (k, _, _) <- xs]
      byKey = Map.fromListWith (flip (<>)) [(k, [(p, a)]) | (k, p, a) <- xs]
   in [(k, nub (sort (map fst pas)), map snd pas) | k <- keys, Just pas <- [Map.lookup k byKey]]

{- | @PDF の 1、2 ページ目@: at most ten pages, then @ほか <n> ページ@
(golem-cli ADR 0006).
-}
pagesPhrase :: [Int] -> Text
pagesPhrase ps =
  let shown = take 10 ps
      rest = length ps - length shown
   in "PDF の " <> T.intercalate "、" (map tshow shown) <> " ページ目" <> (if rest > 0 then "ほか " <> tshow rest <> " ページ" else "")

pagesFact :: [Int] -> (Text, Fact)
pagesFact ps = ("pdf-pages", FactInts (map toInteger ps))

tshow :: (Show a) => a -> Text
tshow = T.pack . show

-- | A length in mm to one decimal (golem-cli ADR 0006).
mmText :: Sp -> Text
mmText s =
  let tenths = round (toRational s * 254 / (72 * 65536)) :: Integer
      (i, f) = abs tenths `divMod` 10
   in (if tenths < 0 then "-" else "") <> tshow i <> "." <> tshow f <> "mm"

-- | The effective resolution: the pixels over the inches placed, the smaller of the two, cut down.
ppiOf :: ImageView -> ImageData -> Integer
ppiOf iv img =
  let Rect _ _ w h = ivRect iv
      per px sz = if sz <= 0 then 0 else toInteger px * 72 * 65536 `div` sz
   in min (per (imgWidth img) w) (per (imgHeight img) h)

data Kind = KColor | KGray | KBitmap
  deriving stock (Eq)

kindOf :: ImageData -> Kind
kindOf img = case imgColor img of
  CsGray | imgBits img == 1 -> KBitmap
  CsGray -> KGray
  _ -> KColor

-- | The image of a PNG or JPEG figure; a PDF figure has none (golem-pdf ADR 0008).
raster :: ImageView -> Maybe ImageData
raster iv = case ivContent iv of
  RasterFigure img -> Just img
  VectorFigure _ -> Nothing

images :: View -> [(Int, ImageView)]
images v = [(pvIndex p, iv) | p <- vwPages v, iv <- pvImages p]

-- | One diagnostic per @figure: its first placement, with the pages it is on.
perFigure :: View -> (ImageView -> Maybe a) -> [(ImageView, [Int], a)]
perFigure v f =
  [ (iv, ps, a)
  | (_, ps, (iv, a) : _) <- groups [(ivSpan iv, n, (iv, a)) | (n, iv) <- images v, Just a <- [f iv]]
  ]

-- ------------------------------------------------------------------ the checks

-- | G0902: glyph 0 (.notdef), per character and font.
glyphMissing :: Rules -> View -> [Diagnostic]
glyphMissing r v =
  concat
    [ at (ruGlyphMissing r) "G0902" (gvSpan g) msg [("code-point", FactText cp), ("font", FactText (gvFont g)), pagesFact ps, ("count", FactInt (toInteger (length gs)))]
    | ((t, font), ps, gs@(g : _)) <- groups [((gvText gl, gvFont gl), pvIndex p, gl) | p <- vwPages v, gl <- pvGlyphs p, gvGlyph gl == 0],
      let c = maybe ' ' fst (T.uncons t)
          cp = "U+" <> T.justifyRight 4 '0' (T.toUpper (T.pack (showHex (ord c) "")))
          shown = if isControl c || isMark c then "" else "「" <> T.singleton c <> "」"
          msg = "フォントにグリフのない文字です: " <> cp <> shown <> "（" <> font <> "、" <> pagesPhrase ps <> "）"
    ]
  where
    isMark c = generalCategory c `elem` [NonSpacingMark, SpacingCombiningMark, EnclosingMark]

-- | G0903: an embedded font of a form the rules do not allow.
fontFormats :: Rules -> View -> [Diagnostic]
fontFormats r v =
  concat
    [ at (ruFontFormats r) "G0903" (vwStyleSpan v) ("この設定では使えない形式のフォントです: " <> fvPath f <> "（" <> fvFormat f <> "）") [("font", FactText (fvPath f))]
    | f <- nubOnPath (vwFonts v),
      fvFormat f `notElem` ruFontFormatsAllowed r
    ]
  where
    nubOnPath = foldr (\f acc -> f : filter ((/= fvPath f) . fvPath) acc) []

-- | The number of inks of a colour: the default black is one.
inks :: Maybe (Text, Cmyk) -> Int
inks = \case
  Nothing -> 1
  Just (_, (c, m, y, k)) -> length (filter (/= 0) [c, m, y, k])

-- | G0904: text smaller than min-size, only in two inks or more with multi-ink-only.
typeSize :: Rules -> View -> [Diagnostic]
typeSize r v =
  concat
    [ at (ruTypeSize r) "G0904" (gvSpan g) msg [("size", FactText (mmText (gvSize g))), pagesFact ps]
    | (_, ps, g : _) <-
        groups
          [ ((gvStyle gl, fmap fst (gvColor gl)), pvIndex p, gl)
          | p <- vwPages v,
            gl <- pvGlyphs p,
            gvSize gl < ruTypeSizeMin r,
            not (ruTypeSizeMultiInkOnly r) || inks (gvColor gl) >= 2
          ],
      let msg = "文字が小さすぎます: " <> mmText (gvSize g) <> "（" <> mmText (ruTypeSizeMin r) <> " 未満、色 " <> maybe "なし" fst (gvColor g) <> "、" <> pagesPhrase ps <> "）"
    ]

-- | G0906: the effective resolution below a threshold of the kind of the image.
imageResolution :: Rules -> View -> [Diagnostic]
imageResolution r v =
  [ (diagnostic "G0906" sev (ivSpan iv) msg) {diagFacts = [("ppi", FactInt ppi), ("limit", FactInt (toInteger limit)), ("pixels", FactInts [toInteger (imgWidth img), toInteger (imgHeight img)]), pagesFact ps]}
  | (iv, ps, (img, ppi, sev, limit)) <- perFigure v below,
    let msg = "図版の実効の解像度が足りません: " <> ivPath iv <> "（" <> tshow ppi <> "ppi、" <> tshow limit <> "ppi 未満、" <> pagesPhrase ps <> "）"
  ]
  where
    -- PNG and JPEG only: the images inside a PDF figure are not checked
    below iv = do
      img <- raster iv
      let ppi = ppiOf iv img
          Tier e w = case kindOf img of
            KColor -> ruResolutionColor r
            KGray -> ruResolutionGray r
            KBitmap -> ruResolutionBitmap r
      if e > 0 && ppi < toInteger e
        then Just (img, ppi, Error, e)
        else if w > 0 && ppi < toInteger w then Just (img, ppi, Warning, w) else Nothing

-- | G0907: the effective resolution above the maximum of the kind of the image.
imageResolutionMax :: Rules -> View -> [Diagnostic]
imageResolutionMax r v =
  concat
    [ at (ruImageResolutionMax r) "G0907" (ivSpan iv) msg [("ppi", FactInt ppi), ("limit", FactInt (toInteger limit)), ("pixels", FactInts [toInteger (imgWidth img), toInteger (imgHeight img)]), pagesFact ps]
    | (iv, ps, (img, ppi, limit)) <- perFigure v above,
      let msg = "図版の実効の解像度が高すぎます: " <> ivPath iv <> "（" <> tshow ppi <> "ppi、" <> tshow limit <> "ppi 超）"
    ]
  where
    above iv = do
      img <- raster iv
      let ppi = ppiOf iv img
          limit = case kindOf img of
            KColor -> ruColorMax r
            KGray -> ruGrayMax r
            KBitmap -> ruBitmapMax r
      if limit > 0 && ppi > toInteger limit then Just (img, ppi, limit) else Nothing

colorSpaceName :: ColorSpace -> Text
colorSpaceName = \case
  CsGray -> "gray"
  CsRgb -> "rgb"
  CsIndexed _ -> "rgb"
  CsCmyk -> "cmyk"

{- | The name of a colour space of a PDF figure (golem-pdf ADR 0008): an
ICC profile by its number of components, DeviceRGB replaced by sRGB is rgb.
-}
colorUseName :: ColorUse -> Text
colorUseName = \case
  UseGray -> "gray"
  UseRgb -> "rgb"
  UseCmyk -> "cmyk"
  UseIcc 1 _ -> "gray"
  UseIcc 3 _ -> "rgb"
  UseIcc 4 _ -> "cmyk"
  UseIcc _ _ -> "icc"
  UseLab -> "lab"

-- | G0908: an image in a colour space the rules do not allow; for a PDF figure, all of them in one.
imageColorSpace :: Rules -> View -> [Diagnostic]
imageColorSpace r v =
  concat
    [ at (ruImageColorSpace r) "G0908" (ivSpan iv) ("この設定では使えない色空間の図版です: " <> ivPath iv <> "（" <> cs <> "）。Golem は画像の色を変換しないので、CMYK に変換した画像に替えます") [("color-space", FactText cs), pagesFact ps]
    | (iv, ps, cs) <- perFigure v disallowed
    ]
  where
    disallowed iv = case filter (`notElem` ruColorSpacesAllowed r) (spacesOf iv) of
      [] -> Nothing
      cs -> Just (T.intercalate "、" cs)
    spacesOf iv = case ivContent iv of
      RasterFigure img -> [colorSpaceName (imgColor img)]
      VectorFigure page -> nub (map colorUseName (ipColors page))

-- | G0909: a CMYK image with a profile other than the output intent's.
imageIcc :: Rules -> View -> [Diagnostic]
imageIcc r v = case vwIntentProfile v of
  Nothing -> []
  Just intent ->
    concat
      [ at (ruImageIcc r) "G0909" (ivSpan iv) ("出力インテントと違う ICC プロファイルを持つ CMYK の図版です: " <> ivPath iv <> "。印刷の工程で色が変換されることがあります") [pagesFact ps]
      | (iv, ps, ()) <- perFigure v (differs intent)
      ]
  where
    differs :: ByteString -> ImageView -> Maybe ()
    differs intent iv = case ivContent iv of
      RasterFigure img -> case (imgColor img, imgIcc img) of
        (CsCmyk, Just p) | p /= intent -> Just ()
        _ -> Nothing
      VectorFigure page
        | any (\case UseIcc 4 p -> p /= intent; _ -> False) (ipColors page) -> Just ()
        | otherwise -> Nothing

-- | G0910: [page] bleed below min.
bleedSize :: Rules -> View -> [Diagnostic]
bleedSize r v =
  [ d
  | vwBleed v < ruBleedMin r,
    d <- at (ruBleedSize r) "G0910" (vwStyleSpan v) ("塗り足しの幅が足りません: " <> mmText (vwBleed v) <> "（" <> mmText (ruBleedMin r) <> " 以上にします）") []
  ]

{- | The distance of each edge of a rectangle from the same edge of the
trimmed page, inside positive: 天, 地, 小口, のど.
-}
edges :: PageView -> Rect -> [(Text, Sp)]
edges p (Rect x y w h) =
  let Rect tx ty tw th = pvTrim p
      left = x - tx
      right = (tx + tw) - (x + w)
      (gutter, outer) = if pvGutterLeft p then (left, right) else (right, left)
   in [("天", (ty + th) - (y + h)), ("地", y - ty), ("小口", outer), ("のど", gutter)]

-- | G0911: an edge of an image near the trim line that does not reach the bleed line.
trimHazard :: Rules -> View -> [Diagnostic]
trimHazard r v =
  concat
    [ at (ruBleedTrimHazard r) "G0911" (ivSpan iv) ("図版が仕上がりの線の近くにあり、塗り足しまで届いていません: " <> ivPath iv <> "（" <> edge <> "、仕上がりの線から " <> mmText e <> "、" <> pagesPhrase ps <> "）") [pagesFact ps]
    | (iv, ps, (edge, e)) <- perFigure' hazard
    ]
  where
    d = ruTrimHazardDistance r
    b = vwBleed v
    -- -B < e < d; an edge on the trim line (e = 0) also without bleed, as the tests of the ADR ask
    hazard p iv = case [(edge, e) | (edge, e) <- edges p (ivRect iv), e < d, negate b < e || e >= 0] of
      (x : _) -> Just x
      [] -> Nothing
    perFigure' f =
      [ (iv, ps, a)
      | (_, ps, (iv, a) : _) <- groups [(ivSpan iv, pvIndex p, (iv, a)) | p <- vwPages v, iv <- pvImages p, Just a <- [f p iv]]
      ]

-- | G0912: lines of text and rules outside the safe area.
liveArea :: Rules -> View -> [Diagnostic]
liveArea r v =
  concat
    [ at (ruLiveArea r) "G0912" sp ("文字が仕上がりの線に近すぎます: " <> kind <> "（" <> edge <> "、仕上がりの線から " <> mmText e <> "、" <> pagesPhrase ps <> "）") [pagesFact ps]
    | ((kind, edge), ps, (sp, e) : _) <-
        groups
          ( [((lvKind l, edge), pvIndex p, (lvSpan l, e)) | p <- vwPages v, l <- pvLines p, (edge, e) <- take 1 (outside p (lvRect l))]
              <> [((rvKind ru, edge), pvIndex p, (vwStyleSpan v, e)) | p <- vwPages v, ru <- pvRules p, (edge, e) <- take 1 (outside p (rvRect ru))]
          )
    ]
  where
    outside p rect = [(edge, e) | (edge, e) <- edges p rect, e < ruLiveAreaDistance r]

-- | G0913: a line overfull after line breaking.
overfullLines :: Rules -> View -> [Diagnostic]
overfullLines r v =
  concat
    [ at (ruOverfullLines r) "G0913" (lvSpan l) ("行が行長から " <> mmText amount <> " はみ出しています（" <> pagesPhrase [pvIndex p] <> "）") [("overfull", FactText (mmText amount)), pagesFact [pvIndex p]]
    | p <- vwPages v,
      l <- pvLines p,
      Just amount <- [lvOverfull l]
    ]

-- | G0914: the PDF/X-4 requirements; one diagnostic when the output intent is missing.
pdfX :: Rules -> View -> [Diagnostic]
pdfX r v
  | null (vwX4 v) = []
  | otherwise = case vwIntentProfile v of
      Nothing -> at (ruPdfX r) "G0914" (vwStyleSpan v) "PDF/X-4 の要件を満たしていません: 出力インテントがありません（style.toml の [color] に intent を書きます）" [("requirement", FactText "出力インテント")]
      Just _ ->
        concat
          [ at (ruPdfX r) "G0914" (vwStyleSpan v) ("PDF/X-4 の要件を満たしていません: " <> x4Requirement p <> "（" <> x4Detail p <> "）") [("requirement", FactText (x4Requirement p))]
          | p <- nub (vwX4 v)
          ]

-- | G0915: the total ink of a swatch used.
inkCoverage :: Rules -> View -> [Diagnostic]
inkCoverage r v =
  concat
    [ at (ruInkCoverage r) "G0915" (vwStyleSpan v) ("色の総インキ量が多すぎます: " <> name <> "（" <> tshow total <> "%、" <> tshow (ruInkMax r) <> "% 超）") [("total", FactInt (toInteger total))]
    | (name, (c, m, y, k)) <- Map.toList (vwSwatchesUsed v),
      let total = c + m + y + k,
      total > ruInkMax r
    ]

-- | G0916: the pages are not a multiple of multiple-of.
pageCount :: Rules -> View -> [Diagnostic]
pageCount r v =
  let n = length (vwPages v)
      m = max 1 (ruPageMultiple r)
      short = (m - n `mod` m) `mod` m
   in [ d
      | short /= 0,
        d <- at (ruPageCount r) "G0916" (vwManifestSpan v) ("ページ数が " <> tshow m <> " の倍数ではありません: " <> tshow n <> "（あと " <> tshow short <> " ページ）") [("pages", FactInt (toInteger n))]
      ]

-- | G0917: the blank pages, together.
blankPages :: Rules -> View -> [Diagnostic]
blankPages r v = case [pvIndex p | p <- vwPages v, pvBlank p] of
  [] -> []
  ps -> at (ruBlankPages r) "G0917" (vwManifestSpan v) ("空白のページです（" <> pagesPhrase ps <> "）") [pagesFact ps]

-- | G0918: rules thinner than min, per kind.
strokeWeight :: Rules -> View -> [Diagnostic]
strokeWeight r v =
  concat
    [ at (ruStrokeWeight r) "G0918" (vwStyleSpan v) ("線が細すぎます: " <> kind <> "（" <> mmText w <> "、" <> mmText (ruStrokeMin r) <> " 未満、" <> pagesPhrase ps <> "）") [pagesFact ps]
    | (kind, ps, w : _) <- groups [(rvKind ru, pvIndex p, rvWeight ru) | p <- vwPages v, ru <- pvRules p, rvWeight ru < ruStrokeMin r]
    ]
