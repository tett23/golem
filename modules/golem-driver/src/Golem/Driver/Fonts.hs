{- | The font provider backed by golem-font (HarfBuzz and FreeType): the
font roles of style.toml that the PDF uses, their Japanese and Latin
faces, shaping, subsetting and the PDF font descriptions (golem-driver
ADR 0002 and 0003, golem-font ADR 0001 and 0002).
-}
module Golem.Driver.Fonts
  ( golemFontProvider,
    cffFontProgram,
    cff2FontDiagnostics,
    toUnicodeOf,
    actualTextOf,
  )
where

import Control.Applicative ((<|>))
import Data.ByteString qualified as BS
import Data.Containers.ListUtils (nubOrd)
import Data.Functor ((<&>))
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, isJust)
import Data.Ratio ((%))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver.Memo (fromShapingTextKey, memoWith, shapingTextKey)
import Golem.Driver.Pdf (FontProvider (..), LoadedFonts (..), Shaped (..), Shaping (..), bodyFontDiagnostics, bodyRole, usedRoles)
import Golem.Driver.TextLayer (ClusterPart (..), actualTextOf, toUnicodeOf)
import Golem.Font
import Golem.Layout.Japanese (CharClass (..), charClass, isExtending, isVariationSelector)
import Golem.Layout.Orientation (turnsInVertical)
import Golem.Pdf qualified as P
import Golem.Project.Paths (PathError (..), pathErrorMessage, resolveInRoot)
import Golem.Project.Style
import Golem.Syntax
import System.FilePath ((</>))
import Text.Printf (printf)

{- | Every file that cannot be loaded is reported, once per path (G08002,
G08003, G08004); G08005 is checked only when all are loaded. The
diagnostics are at the top of @fid@ (golem-driver ADR 0016).
-}
golemFontProvider :: FontProvider
golemFontProvider = FontProvider $ \root fid style locals ->
  let body = bodyRole style
      err code = diagnostic code Error (mkSpan fid 0 0)
      load path = do
        r <- resolveInRoot root path
        case r of
          -- reported by the driver before the fonts are loaded; kept for a provider used alone
          Left e -> pure (Left (err "G08002" (T.pack ((if e == Missing then "フォントのファイルがありません" else pathErrorMessage e) <> ": " <> path))))
          Right rel -> do
            bytes <- BS.readFile (root </> rel)
            loaded <- loadFont bytes
            pure $ case loaded of
              Right f
                | fontIsCff2 f -> Left (cff2Diagnostic fid path)
                | otherwise -> Right (bytes, f, path)
              Left Unreadable -> Left (err "G08003" ("フォントを読み込めません: " <> T.pack path))
              Left (EmbeddingRestricted t) -> Left (err "G08004" ("ライセンスが埋め込みを禁じているフォントです（fsType " <> T.pack (printf "0x%04X" t) <> "）: " <> T.pack path))
   in case bodyFontDiagnostics fid style of
        -- reported by the driver before the fonts are loaded; kept for a provider used alone
        ds@(_ : _) -> pure (Left ds)
        [] -> do
          let roles = [(r, fr) | r <- usedRoles style locals, Just fr <- [Map.lookup r (stFonts style)]]
              paths = nubOrd (concat [catMaybes [frJa fr, frLatin fr] | (_, fr) <- roles])
          loadedPaths <- Map.fromList <$> mapM (\p -> (p,) <$> load p) paths
          let side f fr = f fr >>= \p -> either (const Nothing) Just =<< Map.lookup p loadedPaths
              files = [(r, fr, side frJa fr, side frLatin fr) | (r, fr) <- roles]
          pure $ case [d | p <- paths, Just (Left d) <- [Map.lookup p loadedPaths]] of
            ds@(_ : _) -> Left ds
            [] ->
              let -- faces in order: body Japanese, body Latin, then the other roles by name; the same bytes are one face
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
                    ((n, p1, p2) : _) -> Left [err "G08005" ("PostScript 名が同じ異なるフォントがあります: " <> n <> "（" <> T.pack p1 <> "、" <> T.pack p2 <> "）")]
                    [] -> Right (provide fid [(f, p) | (_, f, p) <- faces] body roleFaces)
  where
    nubOn key = reverse . fst . foldl' (\(acc, seen) x -> if key x `elem` seen then (acc, seen) else (x : acc, key x : seen)) ([], [])

{- | G08019 (golem-font ADR 0003): a font with CFF2 outlines cannot be
embedded in the PDF. At the top of @fid@, as the other font diagnostics.
-}
cff2Diagnostic :: FileId -> FilePath -> Diagnostic
cff2Diagnostic fid path =
  diagnostic "G08019" Error (mkSpan fid 0 0) ("CFF2 の輪郭のフォントは PDF に埋め込めません: " <> T.pack path <> "。CFF か TrueType の輪郭のフォントを使ってください")

{- | G08019 for the given font files of the PDF, before it is laid out, so
that golem check reports it too (golem-font ADR 0003). A file that cannot
be read or loaded is left to the font provider (G08002, G08003, G08004).
-}
cff2FontDiagnostics :: FilePath -> FileId -> [FilePath] -> IO [Diagnostic]
cff2FontDiagnostics root fid paths = concat <$> mapM one (nubOrd paths)
  where
    one path = do
      r <- resolveInRoot root path
      case r of
        Left _ -> pure []
        Right rel -> do
          loaded <- BS.readFile (root </> rel) >>= loadFont
          pure [cff2Diagnostic fid path | Right f <- [loaded], fontIsCff2 f]

-- | The form of a face for golem preflight (golem-cli ADR 0006, golem-font ADR 0003).
faceForm :: Font -> Text
faceForm f
  | fontIsCff2 f = "cff2"
  | fontIsCff f = "cff"
  | otherwise = "truetype"

{- | Fonts by face number; each role maps to its Japanese and Latin faces
and its OpenType features. A role that is not loaded is the body role.
The measures are kept by the shaping too: its features change them
(docs/adr/0020).
-}
provide :: FileId -> [(Font, FilePath)] -> Text -> Map.Map Text (Maybe Int, Maybe Int, [Text]) -> LoadedFonts
provide fid faces body roles =
  LoadedFonts
    { lfAdvance = advance,
      lfWordAdvance = \s t -> sum (map shAdvance (shapeText s t)),
      -- the pair shaped together less the two shaped apart (docs/adr/0020)
      lfPairKern = \s a b -> pairKern (s, T.pack [a, b]),
      lfShape = shapeText,
      lfCode = glyphCid . fontAt,
      lfEmbed = embed,
      lfEmBoxCentral = \ix -> let f = fontAt ix in toInteger (fontEmBoxCentral f) % toInteger (fontUnitsPerEm f),
      -- the path in style.toml and the form of a face (golem-cli ADR 0006)
      lfFaceFile = \ix -> let (f, p) = faceAt ix in (p, faceForm f),
      -- the ink box of a glyph from FreeType, in em (golem-driver ADR 0019)
      lfInkBox = \ix g ->
        let f = fontAt ix
            em v = toInteger v % toInteger (fontUnitsPerEm f)
         in (\m -> let (x0, y0, x1, y1) = gmBBox m in (em x0, em y0, em x1, em y1)) <$> glyphMetrics f g
    }
  where
    {- advances are asked for again and again while composing; they are
    remembered in a lazy trie, without state (docs/adr ADR 0034) -}
    advanceOf = memoWith shapingTextKey fromShapingTextKey (\(s, t) -> sum (map shAdvance (shapeText s t)))
    advance s c = advanceOf (s, T.singleton c)
    pairKern = memoWith shapingTextKey fromShapingTextKey (\(s, t) -> sum (map shAdvance (shapeText s t)) - sum [advance s c | c <- T.unpack t])
    faceAt i = faces !! max 0 (min (length faces - 1) i)
    fontAt = fst . faceAt
    roleOf role = case Map.lookup role roles of
      Just (Nothing, Nothing, _) -> roleOf body
      Just r -> r
      Nothing -> fromMaybe (Just 0, Nothing, []) (Map.lookup body roles)
    fontFor role c =
      let (ja, la, _) = roleOf role
       in fromMaybe 0 (if charClass c == Western then la <|> ja else ja <|> la)
    -- a combining character stays with the character before it, variation selectors among them (golem-pdf ADR 0006, golem-driver ADR 0036)
    runs role t = [(fontFor role (T.head r), r) | r <- T.groupBy (\a b -> isExtending b || fontFor role a == fontFor role b) t, not (T.null r)]
    {- shaping a text in a role, with the features added after the role's
    (docs/adr/0020). In vertical text a cluster of a Japanese run whose
    glyphs vert leaves as they are, and whose first character is R or Tr in
    UAX #50, is turned: its horizontal glyphs and advances (golem-driver ADR
    0015). The clusters are numbered by character in the whole text. -}
    shapeText (Shaping role vertical extra) t =
      let (_, la, roleFeatures) = roleOf role
          features = roleFeatures <> extra
          shapeIn f r dir = shapeUnits f ((shapeRequest 1000 r) {srDirection = dir, srFeatures = features})
          em f u = toInteger u % toInteger (fontUnitsPerEm f)
          {- the offsets as HarfBuzz gives them in horizontal shaping; vertical
          shaping subtracts the vertical origin, added back here (golem-driver
          ADR 0020) -}
          glyph ix f r starts turned dir (g, c, (xa, ya, xo, yo)) =
            let (ox, oy) = if dir == Vertical then glyphVerticalOrigin f g else (0, 0)
             in Shaped ix g (em f (if dir == Vertical then negate ya else xa)) (clusterText r starts c) turned c (em f (xo + ox), em f (yo + oy)) ClusterWhole
          clusters gs = [(c, [x | x@(_, c', _) <- gs, c' == c]) | c <- nubOrd [c | (_, c, _) <- gs]]
          gids = map (\(g, _, _) -> g)
          run (ix, r) = withParts $ case () of
            _
              | not vertical -> let gs = shapeIn f r Horizontal in map (glyph ix f r (startsOf gs) False Horizontal) gs
              | latinRun -> let gs = shapeIn f r Vertical in map (glyph ix f r (startsOf gs) False Vertical) gs
              | otherwise ->
                  let across = Map.fromList (clusters (shapeIn f r Horizontal))
                      vgs = shapeIn f r Vertical
                      starts = startsOf vgs
                   in concat
                        [ case Map.lookup c across of
                            Just hs
                              | gids hs == gids vs,
                                maybe False (turnsInVertical . fst) (T.uncons (clusterText r starts c)) ->
                                  map (glyph ix f r starts True Horizontal) hs
                            _ -> map (glyph ix f r starts False Vertical) vs
                        | (c, vs) <- clusters vgs
                        ]
            where
              f = fontAt ix
              -- a run for which fontFor chose the Latin face
              latinRun = isJust la && maybe False ((== Western) . charClass . fst) (T.uncons r)
          -- the byte offsets of a run's clusters as character indices in t
          offsets = scanl (+) 0 [T.length r | (_, r) <- runs role t]
          inText r start sh = sh {shCluster = start + T.length (TE.decodeUtf8Lenient (BS.take (shCluster sh) (TE.encodeUtf8 r)))}
       in concat [map (inText r start) (run (ix, r)) | ((ix, r), start) <- zip (runs role t) offsets]
    {- the text of a glyph for ToUnicode: its whole cluster, from its byte
    offset to the start of the next cluster of the run (golem-driver ADR
    0030), without variation selectors, so that a variant is found by its
    base character (golem-pdf ADR 0006) -}
    clusterText r starts c =
      let bytes = TE.encodeUtf8 r
          end = fromMaybe (BS.length bytes) (Set.lookupGT c starts)
       in T.filter (not . isVariationSelector) (TE.decodeUtf8Lenient (BS.take (end - c) (BS.drop c bytes)))
    -- the byte offsets of the clusters of a run
    startsOf gs = Set.fromList [c | (_, c, _) <- gs]
    {- the part of each glyph in its cluster: the only glyph, or the first or
    a later one of several, in glyph order (golem-driver ADR 0030) -}
    withParts gs = concat [parts grp | grp <- groupOn shCluster gs]
      where
        parts = \case
          [g] -> [g {shPart = ClusterWhole}]
          g : rest -> g {shPart = ClusterLead} : [x {shPart = ClusterRest} | x <- rest]
          [] -> []
        groupOn k = \case
          [] -> []
          x : xs -> let (same, rest) = span ((== k x) . k) xs in (x : same) : groupOn k rest
    {- IO: the subset is made as the PDF is written (docs/adr ADR 0034); a CFF
    font without a CFF table is G08018 (golem-pdf ADR 0011) -}
    embed ix vertical used = do
      let (f, path) = faceAt ix
          upem = toInteger (fontUnitsPerEm f)
          per1000 v = fromInteger (round (toInteger v * 1000 % upem))
          gids = Map.keys (Map.fromList [(g, ()) | (g, _) <- used])
          cid = glyphCid f
          metrics = [(g, m) | g <- gids, Just m <- [glyphMetrics f g]]
          (asc, desc, cap) = fontExtents f
          name = subsetTag gids <> "+" <> (if T.null (fontPostScriptName f) then "GolemFont" else fontPostScriptName f)
          (bx0, by0, bx1, by1) = foldr (\(_, m) (a, b, c, d) -> let (x0, y0, x1, y1) = gmBBox m in (min a x0, min b y0, max c x1, max d y1)) (0, 0, 0, 0) metrics
      program <- fromMaybe (fontBytes f) <$> subsetFont f gids
      pure $
        (if fontIsCff f then cffFontProgram fid path program else Right (P.TrueTypeProgram program)) <&> \fontProgram ->
          P.Font
            { P.fontName = name,
              P.fontProgram = fontProgram,
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

{- | The program of a CFF font: its bare CFF table, embedded in FontFile3 with
the subtype CIDFontType0C (golem-pdf ADR 0011). PDFium takes the codes of a
CID-keyed CFF wrapped in OpenType as glyph IDs and draws no Japanese, so a
font whose CFF table cannot be taken out is G08018, at the top of @fid@, and
is not embedded as OpenType.
-}
cffFontProgram :: FileId -> FilePath -> BS.ByteString -> Either Diagnostic P.FontProgram
cffFontProgram fid path program = case sfntTable "CFF " program of
  Just cff | not (BS.null cff) -> Right (P.CffProgram cff)
  _ -> Left (diagnostic "G08018" Error (mkSpan fid 0 0) ("フォントから CFF の表を取り出せません: " <> T.pack path))

-- | The bytes of one table of an sfnt (OpenType) font.
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
