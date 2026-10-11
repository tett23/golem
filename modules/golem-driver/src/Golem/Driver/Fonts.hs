{- | The font provider backed by golem-font (HarfBuzz and FreeType): the
body font of style.toml, Japanese and Latin faces, shaping, subsetting
and the PDF font descriptions (golem-driver ADR 0002, golem-font ADR
0001 and 0002).
-}
module Golem.Driver.Fonts
  ( golemFontProvider,
  )
where

import Control.Applicative ((<|>))
import Data.ByteString qualified as BS
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, listToMaybe)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver.Pdf (FontProvider (..), LoadedFonts (..))
import Golem.Font
import Golem.Layout.Japanese (CharClass (..), charClass)
import Golem.Pdf qualified as P
import Golem.Project.Paths (resolveInRoot)
import Golem.Project.Style
import Golem.Syntax
import System.FilePath ((</>))
import System.IO.Unsafe (unsafePerformIO)

golemFontProvider :: FontProvider
golemFontProvider = FontProvider $ \root style ->
  case Map.lookup "body" (stFonts style) <|> listToMaybe (Map.elems (stFonts style)) of
    Nothing -> pure (Left [err "G0802" "style.toml に本文のフォント（[fonts.body]）がありません"])
    Just role -> do
      let paths = catMaybes [frJa role, frLatin role]
      loaded <- mapM (load root) paths
      case sequence loaded of
        Left d -> pure (Left [d])
        Right [] -> pure (Left [err "G0802" "[fonts.body] にフォントのファイルがありません"])
        Right fonts -> pure (Right (provide fonts (maybe 0 (const (length fonts - 1)) (frLatin role)) (frFeatures role)))
  where
    err code = diagnostic code Error (mkSpan (FileId 0) 0 0)
    load root path = do
      r <- resolveInRoot root path
      case r of
        Left _ -> pure (Left (err "G0802" ("フォントのファイルがありません: " <> T.pack path)))
        Right rel -> do
          bytes <- BS.readFile (root </> rel)
          pure $ case loadFont bytes of
            Right f -> Right f
            Left Unreadable -> Left (err "G0803" ("フォントを読み込めません: " <> T.pack path))
            Left (EmbeddingRestricted t) -> Left (err "G0804" ("ライセンスが埋め込みを禁じているフォントです（fsType " <> T.pack (show t) <> "）: " <> T.pack path))

provide :: [Font] -> Int -> [Text] -> LoadedFonts
provide fonts latinIx features =
  LoadedFonts
    { lfAdvance = memo (\c -> sum [a | (_, _, a, _) <- shapeText False (T.singleton c)]),
      lfWordAdvance = \t -> sum [a | (_, _, a, _) <- shapeText False t],
      lfShape = shapeText,
      lfCode = glyphCid . fontAt,
      lfEmbed = embed
    }
  where
    fontAt i = fonts !! max 0 (min (length fonts - 1) i)
    fontFor c = if charClass c == Western then latinIx else 0
    runs t = [(fontFor (T.head r), r) | r <- T.groupBy (\a b -> fontFor a == fontFor b) t, not (T.null r)]
    shapeText vertical t =
      concat
        [ [ (ix, g, toInteger adv % toInteger upem, clusterText r c)
          | (g, c, (xa, ya, _, _)) <- shapeUnits f req,
            let adv = if vertical then negate ya else xa
          ]
        | (ix, r) <- runs t,
          let f = fontAt ix
              upem = fontUnitsPerEm f
              req = (shapeRequest 1000 r) {srDirection = if vertical then Vertical else Horizontal, srFeatures = features}
        ]
    clusterText r c =
      let bytes = TE.encodeUtf8 r
       in maybe "" (T.singleton . fst) (T.uncons (TE.decodeUtf8Lenient (BS.drop c bytes)))
    embed ix vertical used =
      let f = fontAt ix
          upem = toInteger (fontUnitsPerEm f)
          per1000 v = fromInteger (round (toInteger v * 1000 % upem))
          gids = nub (map fst used)
          cid = glyphCid f
          metrics = [(g, m) | g <- gids, Just m <- [glyphMetrics f g]]
          (asc, desc, cap) = fontExtents f
          program = fromMaybe (fontBytes f) (subsetFont f gids)
          name = subsetTag gids <> "+" <> (if T.null (fontPostScriptName f) then "GolemFont" else fontPostScriptName f)
          (bx0, by0, bx1, by1) = foldr (\(_, m) (a, b, c, d) -> let (x0, y0, x1, y1) = gmBBox m in (min a x0, min b y0, max c x1, max d y1)) (0, 0, 0, 0) metrics
       in P.Font
            { P.fontName = name,
              P.fontProgram = if fontIsCff f then P.OpenTypeProgram program else P.TrueTypeProgram program,
              P.fontVertical = vertical,
              P.fontWidths = [(cid g, per1000 (gmAdvance m)) | (g, m) <- metrics],
              P.fontVerticalAdvances = [(cid g, per1000 (gmVerticalAdvance m)) | vertical, (g, m) <- metrics],
              P.fontAscent = per1000 asc,
              P.fontDescent = per1000 desc,
              P.fontCapHeight = per1000 cap,
              P.fontStemV = 80,
              P.fontBBox = (per1000 bx0, per1000 by0, per1000 bx1, per1000 by1),
              P.fontItalicAngle = 0,
              P.fontToUnicode = Map.toList (Map.fromListWith (\_ old -> old) [(cid g, t) | (g, t) <- used, g /= 0])
            }

-- | Advances are asked for again and again while composing; cache them.
memo :: (Char -> Rational) -> Char -> Rational
memo f = unsafePerformIO $ do
  ref <- newIORef Map.empty
  pure $ \c -> unsafePerformIO $ do
    m <- readIORef ref
    case Map.lookup c m of
      Just v -> pure v
      Nothing -> do
        let v = f c
        atomicModifyIORef' ref (\m' -> (Map.insert c v m', v))
{-# NOINLINE memo #-}
