{-# LANGUAGE CApiFFI #-}

{- | Fonts through HarfBuzz 15.1.0 and FreeType 2.15.0 (golem-font ADR 0001
and 0002): loading from bytes, the embedding licence check, shaping,
metrics, subsetting with retained glyph ids, subset name tags and
ToUnicode mappings. The FFI is confined here. Loading and subsetting are
IO, called at the edges; what is fixed once a font is open is read while
loading. Only the queries that the pure layout makes as it goes
('shapeUnits', 'glyphVerticalOrigin', 'glyphMetrics') are wrapped as pure
functions with unsafePerformIO (docs/adr ADR 0034). Pure functions may be
evaluated on any capability at once, so the C layer holds a lock per font
around FreeType, whose face one thread may use at a time; HarfBuzz's
objects are only read and need none.

Positions and dimensions are returned in font units, the dimensionless
numbers of an em divided into upem; this package holds no length. The
caller multiplies them by the size of type (docs/adr ADR 0114).
-}
module Golem.Font
  ( Font,
    FontError (..),
    loadFont,
    loadFontAt,
    FontInstance (..),
    defaultInstance,
    InstanceError (..),
    Axis (..),
    fontAxes,
    fontCoordinates,
    CoordinatesUse (..),
    fontCoordinatesFor,
    fontInstanceErrors,
    fontUnitsPerEm,
    fontIsCff,
    fontIsCff2,
    fontNumGlyphs,
    fontExtents,
    fontEmBoxCentral,
    fontBytes,
    fontPostScriptName,
    CidSystemInfo (..),
    fontCidSystemInfo,
    Direction (..),
    ShapeRequest (..),
    shapeRequest,
    shapeUnits,
    fontHasFeature,
    glyphVerticalOrigin,
    GlyphMetrics (..),
    glyphMetrics,
    glyphCid,
    subsetFont,
    subsetTag,
  )
where

import Control.Exception (bracket)
import Data.Array.Unboxed (UArray, bounds, inRange, listArray, (!))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Unsafe qualified as BU
import Data.Either (fromLeft, fromRight)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Foreign
import Foreign.C.ConstPtr (ConstPtr (..))
import Foreign.C.String (CString, peekCString, withCString)
import Foreign.C.Types
import System.IO.Unsafe (unsafePerformIO)

data CFont

foreign import capi safe "golem_font.h golem_font_open" c_open :: Ptr Word8 -> CSize -> IO (Ptr CFont)

foreign import capi unsafe "golem_font.h &golem_font_close" c_close :: FunPtr (Ptr CFont -> IO ())

foreign import capi unsafe "golem_font.h golem_font_upem" c_upem :: Ptr CFont -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_fstype" c_fstype :: Ptr CFont -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_is_cff" c_isCff :: Ptr CFont -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_is_cff2" c_isCff2 :: Ptr CFont -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_num_glyphs" c_numGlyphs :: Ptr CFont -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_extents" c_extents :: Ptr CFont -> Ptr Int32 -> Ptr Int32 -> Ptr Int32 -> IO ()

foreign import capi unsafe "golem_font.h golem_font_embox_central" c_emboxCentral :: Ptr CFont -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_glyph_metrics" c_metrics :: Ptr CFont -> Word32 -> Ptr Int32 -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_v_origin" c_vOrigin :: Ptr CFont -> Word32 -> Ptr Int32 -> Ptr Int32 -> IO ()

foreign import capi unsafe "golem_font.h golem_font_shape"
  c_shape :: Ptr CFont -> CString -> CInt -> CString -> CString -> CInt -> CString -> CInt -> Ptr Word32 -> Ptr Word32 -> Ptr Int32 -> CInt -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_feature_tags" c_featureTags :: Ptr CFont -> Ptr Word32 -> CInt -> IO CInt

foreign import capi safe "golem_font.h golem_font_subset" c_subset :: Ptr CFont -> Ptr Word32 -> CInt -> Ptr CSize -> IO (Ptr Word8)

foreign import capi unsafe "golem_font.h golem_font_postscript_name" c_psName :: Ptr CFont -> IO CString

foreign import capi unsafe "golem_font.h golem_font_cid" c_cid :: Ptr CFont -> Word32 -> IO Word32

foreign import capi unsafe "golem_font.h golem_font_is_cid_keyed" c_isCidKeyed :: Ptr CFont -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_ros" c_ros :: Ptr CFont -> Ptr (ConstPtr CChar) -> Ptr (ConstPtr CChar) -> Ptr CInt -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_free" c_free :: Ptr Word8 -> IO ()

foreign import capi unsafe "golem_font.h golem_font_axes" c_axes :: Ptr CFont -> Ptr Int32 -> CInt -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_instances" c_instances :: Ptr CFont -> Ptr Int32 -> CInt -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_name" c_name :: Ptr CFont -> CUInt -> CString -> CInt -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_set_coords" c_setCoords :: Ptr CFont -> Ptr Int32 -> CInt -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_coords_for" c_coordsFor :: Ptr CFont -> CInt -> Ptr CFloat -> CInt -> IO CInt

data Font = Font
  { fontPtr :: !(ForeignPtr CFont),
    fontBytes :: !ByteString,
    fontUnitsPerEm :: !Int,
    fontIsCff :: !Bool,
    -- | whether the font has CFF2 outlines, which the PDF does not take (golem-font ADR 0003)
    fontIsCff2 :: !Bool,
    fontNumGlyphs :: !Int,
    -- | ascender, descender, cap height in font units
    fontExtents :: !(Int, Int, Int),
    fontPostScriptName :: !Text,
    -- | the ROS of a CID-keyed CFF font; Nothing for any other font (golem-pdf ADR 0006)
    fontCidSystemInfo :: !(Maybe CidSystemInfo),
    {- | The height of the centre of the ideographic em box above the
    baseline, in font units (golem-driver ADR 0015): the ideoEmboxCentral
    baseline of HarfBuzz for horizontal Han text, from the BASE table or
    HarfBuzz's fallback when the font has none.
    -} fontEmBoxCentral :: !Int,
    -- | the CID of every glyph of a CID-keyed font, read while loading (docs/adr ADR 0034)
    fontCids :: !(Maybe (UArray Int Int)),
    -- | the tags of the FeatureList of GSUB and GPOS, read while loading (docs/adr/0268)
    fontFeatureTags :: !(Set.Set Text),
    -- | the axes of fvar: tag, minimum, default, maximum in 16.16 (Golem ADR 0358)
    fontAxisRecords :: ![(Text, Int32, Int32, Int32)],
    -- | the named instances of fvar by their English names, with their coordinates (Golem ADR 0358)
    fontNamedInstances :: ![(Text, [Int32])],
    -- | the coordinates the font is set at, in 16.16 in the order of fvar (Golem ADR 0358)
    fontCoordinateValues :: ![Int32]
  }

-- | The Registry, Ordering and Supplement of a CID-keyed font.
data CidSystemInfo = CidSystemInfo
  { csiRegistry :: !Text,
    csiOrdering :: !Text,
    csiSupplement :: !Int
  }
  deriving stock (Eq, Show)

data FontError
  = Unreadable
  | -- | the OS/2 fsType forbids embedding (restricted licence or bitmap only)
    EmbeddingRestricted !Int
  | InstanceErrors ![InstanceError]
  deriving stock (Eq, Show)

{- | Reads a font from its bytes (never from a path, ADR 0001). IO, called
where the bytes are read (docs/adr ADR 0034).
-}
loadFont :: ByteString -> IO (Either FontError Font)
loadFont = loadFontAt defaultInstance

{- | Reads a font from its bytes and sets it at the instance (Golem ADR
0358): shaping, the metrics and the subset all take the same coordinates.
A font that is not variable takes the default instance alone.
-}
loadFontAt :: FontInstance -> ByteString -> IO (Either FontError Font)
loadFontAt inst bytes = do
  p <- BU.unsafeUseAsCStringLen bytes $ \(ptr, len) -> c_open (castPtr ptr) (fromIntegral len)
  if p == nullPtr
    then pure (Left Unreadable)
    else do
      fp <- newForeignPtr c_close p
      fsType <- fromIntegral <$> c_fstype p
      (axes, named) <- readVariations p
      case resolveInstance axes named inst of
        _ | embeddingRestricted fsType -> pure (Left (EmbeddingRestricted fsType))
        Left errs -> pure (Left (InstanceErrors errs))
        Right coords -> do
          set <- if null coords then pure 0 else withArrayLen coords (\n arr -> c_setCoords p arr (fromIntegral n))
          if set /= 0 then pure (Left Unreadable) else loadRest fp p bytes fsType axes named coords

loadRest :: ForeignPtr CFont -> Ptr CFont -> ByteString -> Int -> [(Text, Int32, Int32, Int32)] -> [(Text, [Int32])] -> [Int32] -> IO (Either FontError Font)
loadRest fp p bytes fsType axes named coords = do
  upem <- fromIntegral <$> c_upem p
  cff <- (/= 0) <$> c_isCff p
  cff2 <- (/= 0) <$> c_isCff2 p
  n <- fromIntegral <$> c_numGlyphs p
  ext <- allocaArray 3 $ \arr -> do
    c_extents p arr (arr `plusPtr` 4) (arr `plusPtr` 8)
    [a, d, c] <- peekArray 3 arr
    pure (fromIntegral a, fromIntegral d, fromIntegral c)
  ps <- T.pack <$> (c_psName p >>= peekCString)
  ros <- alloca $ \rp -> alloca $ \op -> alloca $ \sp -> do
    r <- c_ros p rp op sp
    if r /= 0
      then pure Nothing
      else do
        registry <- peek rp >>= peekCString . unConstPtr
        ordering <- peek op >>= peekCString . unConstPtr
        supplement <- fromIntegral <$> peek sp
        pure (cidSystemInfo registry ordering supplement)
  central <- fromIntegral <$> c_emboxCentral p
  cidKeyed <- (/= 0) <$> c_isCidKeyed p
  cids <-
    if cidKeyed && n > 0
      then Just . listArray (0, n - 1) <$> mapM (fmap fromIntegral . c_cid p . fromIntegral) [0 .. n - 1]
      else pure Nothing
  -- the feature list, of any script and language system (docs/adr/0268)
  count <- fromIntegral <$> c_featureTags p nullPtr 0
  tags <- allocaArray (max 1 count) $ \arr -> do
    _ <- c_featureTags p arr (fromIntegral count)
    Set.fromList . map tagText <$> peekArray count arr
  touchForeignPtr fp
  pure $
    if embeddingRestricted fsType
      then Left (EmbeddingRestricted fsType)
      else Right (Font fp bytes upem cff cff2 n ext ps ros central cids tags axes named coords)

{- | Whether fsType forbids Golem to embed the font (golem-driver ADR 0016),
as the OpenType specification reads it: bits 0 to 3 are usage permissions
and the least restrictive one set applies, so bit 1 (restricted licence
embedding) forbids only without bit 2 (preview and print) or bit 3
(editable); bit 8 forbids subsetting, and Golem embeds only subsets; bit 9
allows bitmap embedding only.
-}
embeddingRestricted :: Int -> Bool
embeddingRestricted fsType =
  (set 1 && not (set 2) && not (set 3)) || set 8 || set 9
  where
    set = testBit fsType

{- | A ROS that a PDF string can hold as it is: printable ASCII and a
supplement that is not negative (golem-pdf ADR 0006).
-}
cidSystemInfo :: String -> String -> Int -> Maybe CidSystemInfo
cidSystemInfo registry ordering supplement
  | all printable registry && all printable ordering && supplement >= 0 = Just (CidSystemInfo (T.pack registry) (T.pack ordering) supplement)
  | otherwise = Nothing
  where
    printable c = c >= ' ' && c <= '~'

data Direction = Horizontal | Vertical
  deriving stock (Eq, Show)

data ShapeRequest = ShapeRequest
  { srText :: !Text,
    srScript :: !Text,
    srLanguage :: !Text,
    srDirection :: !Direction,
    -- | HarfBuzz feature strings such as @"palt"@ or @"-liga"@
    srFeatures :: ![Text]
  }
  deriving stock (Eq, Show)

shapeRequest :: Text -> ShapeRequest
shapeRequest t = ShapeRequest t "" "" Horizontal []

{- | Glyph ids, clusters (byte offsets in the UTF-8 text) and (x advance,
y advance, x offset, y offset) in font units. Shaping needs no size: the
caller multiplies the units by the size of type (docs/adr ADR 0114). The
vertical direction enables @vert@ (HarfBuzz does so for top-to-bottom
text).
-}
shapeUnits :: Font -> ShapeRequest -> [(Int, Int, (Int, Int, Int, Int))]
shapeUnits f req = unsafePerformIO $ withForeignPtr (fontPtr f) $ \p ->
  BU.unsafeUseAsCStringLen (TE.encodeUtf8 (srText req)) $ \(txt, len) ->
    withCString (T.unpack (srScript req)) $ \script ->
      withCString (T.unpack (srLanguage req)) $ \lang ->
        withCString (T.unpack (T.intercalate "," (srFeatures req))) $ \feats -> do
          let attempt cap =
                allocaArray cap $ \gids -> allocaArray cap $ \clusters -> allocaArray (4 * cap) $ \pos -> do
                  n <- c_shape p txt (fromIntegral len) script lang (if srDirection req == Vertical then 1 else 0) feats (fromIntegral (length (srFeatures req))) gids clusters pos (fromIntegral cap)
                  if n < 0
                    then pure (Left (fromIntegral (negate n - 1) :: Int))
                    else do
                      gs <- peekArray (fromIntegral n) gids
                      cs <- peekArray (fromIntegral n) clusters
                      ps <- peekArray (4 * fromIntegral n) pos
                      pure (Right [(fromIntegral g, fromIntegral c, quad (drop (4 * i) ps)) | (i, g, c) <- zip3 [0 ..] gs cs])
              quad (a : b : c : d : _) = (fromIntegral a, fromIntegral b, fromIntegral c, fromIntegral d)
              quad _ = (0, 0, 0, 0)
          r <- attempt (max 16 (2 * len + 8))
          case r of
            Right xs -> pure xs
            Left needed -> fromRight [] <$> attempt needed

{- | Whether the FeatureList of the GSUB or the GPOS table of the font has
an OpenType feature tag, of any script and language system (docs/adr/0268).
-}
fontHasFeature :: Font -> Text -> Bool
fontHasFeature f tag = Set.member tag (fontFeatureTags f)

{- | The vertical origin (x, y) of a glyph in font units, as
@hb_font_get_glyph_v_origin@ gives it (golem-driver ADR 0020): vertical
shaping subtracts it from the offsets of each glyph, so adding it back
gives the GPOS placement alone.
-}
glyphVerticalOrigin :: Font -> Int -> (Int, Int)
glyphVerticalOrigin f gid = unsafePerformIO $ withForeignPtr (fontPtr f) $ \p ->
  alloca $ \px -> alloca $ \py -> do
    c_vOrigin p (fromIntegral gid) px py
    x <- peek px
    y <- peek py
    pure (fromIntegral x, fromIntegral y)

data GlyphMetrics = GlyphMetrics
  { gmAdvance :: !Int,
    gmVerticalAdvance :: !Int,
    -- | xMin, yMin, xMax, yMax
    gmBBox :: !(Int, Int, Int, Int)
  }
  deriving stock (Eq, Show)

-- | Metrics from FreeType, in font units.
glyphMetrics :: Font -> Int -> Maybe GlyphMetrics
glyphMetrics f gid = unsafePerformIO $ withForeignPtr (fontPtr f) $ \p ->
  allocaArray 6 $ \arr -> do
    r <- c_metrics p (fromIntegral gid) arr
    if r /= 0
      then pure Nothing
      else do
        [h, v, x0, y0, x1, y1] <- map fromIntegral <$> peekArray 6 arr
        pure (Just (GlyphMetrics h v (x0, y0, x1, y1)))

{- | The CID of a glyph in a CID-keyed CFF font (the character code in the
PDF with Identity encodings); the glyph id in any other font, and for a
glyph id outside the font, as a 32-bit glyph id (FreeType's answer).
-}
glyphCid :: Font -> Int -> Int
glyphCid f gid = case fontCids f of
  Just cids | inRange (bounds cids) gid -> cids ! gid
  _ -> fromIntegral (fromIntegral gid :: Word32)

{- | A subset with only the glyphs (and .notdef), glyph ids kept (ADR 0002).
IO, called when the PDF is written (docs/adr ADR 0034).
-}
subsetFont :: Font -> [Int] -> IO (Maybe ByteString)
subsetFont f gids = withForeignPtr (fontPtr f) $ \p ->
  withArrayLen (map fromIntegral (Map.keys (Map.fromList [(g, ()) | g <- 0 : gids]))) $ \n arr ->
    alloca $ \lenPtr -> do
      out <- c_subset p arr (fromIntegral n) lenPtr
      if out == nullPtr
        then pure Nothing
        else bracket (pure out) c_free $ \o -> do
          len <- peek lenPtr
          Just <$> BS.packCStringLen (castPtr o, fromIntegral len)

-- | The six-letter subset prefix, from a hash of the glyph set (ADR 0002).
subsetTag :: [Int] -> Text
subsetTag gids =
  let set = Map.keys (Map.fromList [(g, ()) | g <- gids])
      h = foldl' (\acc g -> (acc `xor` fromIntegral g) * 1099511628211) (14695981039346656037 :: Word64) set
   in T.pack (take 6 (letters h))
  where
    letters x = toEnum (fromEnum 'A' + fromIntegral (x `mod` 26)) : letters (x `div` 26)

{- | The instance of a variable font that a role asks for (Golem ADR 0358):
a named instance of fvar, by its English subfamily name as it is written,
and the coordinates of axes by their tags, which override those of the
instance. The axes written neither by the instance nor by a coordinate are
at their defaults.
-}
data FontInstance = FontInstance
  { fiName :: !(Maybe Text),
    fiAxes :: ![(Text, Double)]
  }
  deriving stock (Eq, Ord, Show)

-- | No instance and no coordinate: the default of every axis.
defaultInstance :: FontInstance
defaultInstance = FontInstance Nothing []

-- | Why a font cannot be set at an instance (Golem ADR 0358).
data InstanceError
  = -- | the font has no named instance of the name (a font that is not variable has none)
    UnknownInstance !Text
  | -- | the font has no axis of the tag
    UnknownAxis !Text
  | -- | the value lies outside the minimum and the maximum of the axis
    AxisOutOfRange !Text !Double !(Double, Double)
  deriving stock (Eq, Show)

-- | An axis of fvar; the values are its 16.16 numbers.
data Axis = Axis
  { axisTag :: !Text,
    axisMinimum :: !Double,
    axisDefault :: !Double,
    axisMaximum :: !Double
  }
  deriving stock (Eq, Show)

-- | The holders of the coordinates (Golem ADR 0358, I1).
data CoordinatesUse
  = -- | the font of HarfBuzz that shapes
    CoordinatesShaping
  | -- | the face of FreeType that gives the metrics
    CoordinatesMetrics
  | -- | the input of the subset that the PDF embeds
    CoordinatesSubset
  deriving stock (Eq, Show)

{- | The coordinates of every axis, in the order of fvar, as 16.16 numbers;
or every reason the instance is not in the font, the name first and then
the axes in the order they are written.
-}
resolveInstance :: [(Text, Int32, Int32, Int32)] -> [(Text, [Int32])] -> FontInstance -> Either [InstanceError] [Int32]
resolveInstance axes named (FontInstance name written) =
  case nameErrors <> concatMap axisErrors written of
    [] -> Right [maybe base fixedOf (lookup tag written) | ((tag, _, _, _), base) <- zip axes start]
    errs -> Left errs
  where
    defaults = [d | (_, _, d, _) <- axes]
    start = maybe defaults (\n -> fromMaybe defaults (lookup n named)) name
    nameErrors = [UnknownInstance n | Just n <- [name], Nothing <- [lookup n named]]
    axisErrors (tag, v) = case [(lo, hi) | (t, lo, _, hi) <- axes, t == tag] of
      [] -> [UnknownAxis tag]
      (lo, hi) : _
        | v < fromFixed lo || v > fromFixed hi -> [AxisOutOfRange tag v (fromFixed lo, fromFixed hi)]
        | otherwise -> []
    -- in the precision of fvar; within the axis, so within Int32
    fixedOf v = fromInteger (round (toRational v * 65536))

fromFixed :: Int32 -> Double
fromFixed c = fromIntegral c / 65536

tagText :: Word32 -> Text
tagText w = T.pack [toEnum (fromIntegral ((w `shiftR` s) .&. 0xFF)) | s <- [24, 16, 8, 0]]

-- | The axes of fvar and the named instances with their English names.
readVariations :: Ptr CFont -> IO ([(Text, Int32, Int32, Int32)], [(Text, [Int32])])
readVariations p = do
  count <- fromIntegral <$> c_axes p nullPtr 0
  axes <- allocaArray (max 1 (4 * count)) $ \arr -> do
    _ <- c_axes p arr (fromIntegral count)
    vs <- peekArray (4 * count) arr
    pure [(tagText (fromIntegral t), lo, d, hi) | [t, lo, d, hi] <- chunks 4 vs]
  n <- fromIntegral <$> c_instances p nullPtr 0
  let per = 1 + count
  insts <- allocaArray (max 1 (per * n)) $ \arr -> do
    _ <- c_instances p arr (fromIntegral (per * n))
    vs <- peekArray (per * n) arr
    sequence [(,cs) <$> nameOf (fromIntegral i) | i : cs <- chunks per vs]
  pure (axes, insts)
  where
    chunks k xs = case splitAt k xs of
      (a, rest) | length a == k -> a : chunks k rest
      _ -> []
    nameOf i = do
      len <- c_name p i nullPtr 0
      allocaBytes (fromIntegral len + 1) $ \buf -> do
        _ <- c_name p i buf (len + 1)
        TE.decodeUtf8Lenient <$> BS.packCStringLen (buf, fromIntegral len)

{- | The coordinates as one of shaping, the metrics and the subset holds
them, as floats (Golem ADR 0358, I1): HarfBuzz reads the 16.16 values of
fvar so. IO: the subset's are read from an input made for it.
-}
fontCoordinatesFor :: CoordinatesUse -> Font -> IO [(Text, Float)]
fontCoordinatesFor use f = withForeignPtr (fontPtr f) $ \p -> do
  let n = length (fontAxes f)
      which = case use of CoordinatesShaping -> 0; CoordinatesMetrics -> 1; CoordinatesSubset -> 2
  allocaArray (max 1 n) $ \arr -> do
    got <- fromIntegral <$> c_coordsFor p which arr (fromIntegral n)
    vs <- peekArray (max 0 (min n got)) arr
    pure (zip (map axisTag (fontAxes f)) [realToFrac v | v <- vs])

-- | The axes of fvar, in its order; none for a font that is not variable (Golem ADR 0358).
fontAxes :: Font -> [Axis]
fontAxes f = [Axis t (fromFixed lo) (fromFixed d) (fromFixed hi) | (t, lo, d, hi) <- fontAxisRecords f]

{- | The coordinates the font is set at, every axis in the order of fvar, in
the precision of fvar (16.16) (Golem ADR 0358).
-}
fontCoordinates :: Font -> [(Text, Double)]
fontCoordinates f = zip [t | (t, _, _, _) <- fontAxisRecords f] (map fromFixed (fontCoordinateValues f))

-- | Why the font cannot be set at the instance; none when it can (Golem ADR 0358).
fontInstanceErrors :: Font -> FontInstance -> [InstanceError]
fontInstanceErrors f inst = fromLeft [] (resolveInstance (fontAxisRecords f) (fontNamedInstances f) inst)
