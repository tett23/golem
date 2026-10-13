{- | The font provider backed by golem-font (HarfBuzz and FreeType): the
font roles of style.toml that the PDF uses, their Japanese and Latin
faces, shaping, subsetting and the PDF font descriptions (golem-driver
ADR 0002 and 0003, golem-font ADR 0001 and 0002).
-}
module Golem.Driver.Fonts
  ( golemFontProvider,
  )
where

import Control.Applicative ((<|>))
import Data.ByteString qualified as BS
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver.Pdf (FontProvider (..), LoadedFonts (..), bodyRole, usedRoles)
import Golem.Font
import Golem.Layout.Japanese (CharClass (..), charClass, isVariationSelector)
import Golem.Pdf qualified as P
import Golem.Project.Paths (resolveInRoot)
import Golem.Project.Style
import Golem.Syntax
import System.FilePath ((</>))
import System.IO.Unsafe (unsafePerformIO)

golemFontProvider :: FontProvider
golemFontProvider = FontProvider $ \root style ->
  let body = bodyRole style
   in case Map.lookup body (stFonts style) of
        Nothing -> pure (Left [err "G0802" "style.toml に本文のフォント（[fonts.body]）がありません"])
        Just role | null (catMaybes [frJa role, frLatin role]) -> pure (Left [err "G0802" "[fonts.body] にフォントのファイルがありません"])
        Just _ -> do
          let roles = [(r, fr) | r <- usedRoles style, Just fr <- [Map.lookup r (stFonts style)]]
          loaded <- mapM (\(r, fr) -> (r,fr,,) <$> traverse (load root) (frJa fr) <*> traverse (load root) (frLatin fr)) roles
          pure $ case [d | (_, _, ja, la) <- loaded, Left d <- catMaybes [ja, la]] of
            (d : _) -> Left [d]
            [] ->
              let files = [(r, fr, right ja, right la) | (r, fr, ja, la) <- loaded]
                  -- faces in order: body Japanese, body Latin, then the other roles by name; the same bytes are one face
                  ordered = concat [catMaybes [ja, la] | (_, _, ja, la) <- files]
                  faces = nubOn (\(b, _, _) -> b) ordered
                  faceOf (b, _, _) = length (takeWhile (\(b', _, _) -> b' /= b) faces)
                  roleFaces = Map.fromList [(r, (faceOf <$> ja, faceOf <$> la, frFeatures fr)) | (r, fr, ja, la) <- files]
                  clashes =
                    [ (n, p1, p2)
                    | ((_, f1, p1), i) <- zip faces [0 :: Int ..],
                      ((_, f2, p2), j) <- zip faces [0 ..],
                      i < j,
                      let n = fontPostScriptName f1,
                      not (T.null n),
                      n == fontPostScriptName f2
                    ]
               in case clashes of
                    ((n, p1, p2) : _) -> Left [err "G0805" ("PostScript 名が同じ異なるフォントがあります: " <> n <> "（" <> T.pack p1 <> "、" <> T.pack p2 <> "）")]
                    [] -> Right (provide [f | (_, f, _) <- faces] body roleFaces)
  where
    err code = diagnostic code Error (mkSpan (FileId 0) 0 0)
    right = \case
      Just (Right x) -> Just x
      _ -> Nothing
    load root path = do
      r <- resolveInRoot root path
      case r of
        Left _ -> pure (Left (err "G0802" ("フォントのファイルがありません: " <> T.pack path)))
        Right rel -> do
          bytes <- BS.readFile (root </> rel)
          pure $ case loadFont bytes of
            Right f -> Right (bytes, f, path)
            Left Unreadable -> Left (err "G0803" ("フォントを読み込めません: " <> T.pack path))
            Left (EmbeddingRestricted t) -> Left (err "G0804" ("ライセンスが埋め込みを禁じているフォントです（fsType " <> T.pack (show t) <> "）: " <> T.pack path))
    nubOn key = reverse . fst . foldl' (\(acc, seen) x -> if key x `elem` seen then (acc, seen) else (x : acc, key x : seen)) ([], [])

{- | Fonts by face number; each role maps to its Japanese and Latin faces
and its OpenType features. A role that is not loaded is the body role.
-}
provide :: [Font] -> Text -> Map.Map Text (Maybe Int, Maybe Int, [Text]) -> LoadedFonts
provide fonts body roles =
  LoadedFonts
    { lfAdvance = curry (memo (\(role, c) -> sum [a | (_, _, a, _) <- shapeText role False (T.singleton c)])),
      lfWordAdvance = \role t -> sum [a | (_, _, a, _) <- shapeText role False t],
      lfShape = shapeText,
      lfCode = glyphCid . fontAt,
      lfEmbed = embed
    }
  where
    fontAt i = fonts !! max 0 (min (length fonts - 1) i)
    roleOf role = case Map.lookup role roles of
      Just (Nothing, Nothing, _) -> roleOf body
      Just r -> r
      Nothing -> fromMaybe (Just 0, Nothing, []) (Map.lookup body roles)
    fontFor role c =
      let (ja, la, _) = roleOf role
       in fromMaybe 0 (if charClass c == Western then la <|> ja else ja <|> la)
    -- a variation selector stays with the character before it (golem-pdf ADR 0006)
    runs role t = [(fontFor role (T.head r), r) | r <- T.groupBy (\a b -> isVariationSelector b || fontFor role a == fontFor role b) t, not (T.null r)]
    shapeText role vertical t =
      let (_, _, features) = roleOf role
       in concat
            [ [ (ix, g, toInteger adv % toInteger upem, clusterText r c)
              | (g, c, (xa, ya, _, _)) <- shapeUnits f req,
                let adv = if vertical then negate ya else xa
              ]
            | (ix, r) <- runs role t,
              let f = fontAt ix
                  upem = fontUnitsPerEm f
                  req = (shapeRequest 1000 r) {srDirection = if vertical then Vertical else Horizontal, srFeatures = features}
            ]
    -- the text of a glyph for ToUnicode: without variation selectors, so
    -- that a variant is found by its base character (golem-pdf ADR 0006)
    clusterText r c =
      let bytes = TE.encodeUtf8 r
       in T.filter (not . isVariationSelector) (maybe "" (T.singleton . fst) (T.uncons (TE.decodeUtf8Lenient (BS.drop c bytes))))
    embed ix vertical used =
      let f = fontAt ix
          upem = toInteger (fontUnitsPerEm f)
          per1000 v = fromInteger (round (toInteger v * 1000 % upem))
          gids = Map.keys (Map.fromList [(g, ()) | (g, _) <- used])
          cid = glyphCid f
          metrics = [(g, m) | g <- gids, Just m <- [glyphMetrics f g]]
          (asc, desc, cap) = fontExtents f
          program = fromMaybe (fontBytes f) (subsetFont f gids)
          name = subsetTag gids <> "+" <> (if T.null (fontPostScriptName f) then "GolemFont" else fontPostScriptName f)
          (bx0, by0, bx1, by1) = foldr (\(_, m) (a, b, c, d) -> let (x0, y0, x1, y1) = gmBBox m in (min a x0, min b y0, max c x1, max d y1)) (0, 0, 0, 0) metrics
       in P.Font
            { P.fontName = name,
              P.fontProgram = if fontIsCff f then maybe (P.OpenTypeProgram program) P.CffProgram (sfntTable "CFF " program) else P.TrueTypeProgram program,
              P.fontVertical = vertical,
              P.fontWidths = [(cid g, per1000 (gmAdvance m)) | (g, m) <- metrics],
              P.fontVerticalAdvances = [(cid g, per1000 (gmVerticalAdvance m)) | vertical, (g, m) <- metrics],
              P.fontAscent = per1000 asc,
              P.fontDescent = per1000 desc,
              P.fontCapHeight = per1000 cap,
              P.fontStemV = 80,
              P.fontBBox = (per1000 bx0, per1000 by0, per1000 bx1, per1000 by1),
              P.fontItalicAngle = 0,
              P.fontToUnicode = Map.toList (Map.fromListWith (\_ old -> old) [(cid g, t) | (g, t) <- used, g /= 0, not (T.null t)]),
              P.fontCidSystemInfo = maybe ("Adobe", "Identity", 0) (\c -> (csiRegistry c, csiOrdering c, csiSupplement c)) (fontCidSystemInfo f)
            }

-- | Advances are asked for again and again while composing; cache them.
memo :: ((Text, Char) -> Rational) -> (Text, Char) -> Rational
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

{- | The bytes of one table of an sfnt (OpenType) font. A CFF font is embedded
as its bare CFF table (FontFile3 with the subtype CIDFontType0C): PDFium
takes the codes of a CID-keyed CFF wrapped in OpenType as glyph IDs, and
drew no Japanese (golem-font ADR 0002 leaves the form of FontFile3 open).
-}
sfntTable :: BS.ByteString -> BS.ByteString -> Maybe BS.ByteString
sfntTable tag font = go 0
  where
    numTables = u16 4
    u16 o = fromIntegral (BS.index font o) * 256 + fromIntegral (BS.index font (o + 1)) :: Int
    u32 o = u16 o * 65536 + u16 (o + 2)
    go i
      | BS.length font < rec + 16 || i >= numTables = Nothing
      | BS.take 4 (BS.drop rec font) == tag = Just (BS.take (u32 (rec + 12)) (BS.drop (u32 (rec + 8)) font))
      | otherwise = go (i + 1)
      where
        rec = 12 + 16 * i
