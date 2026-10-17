{-# LANGUAGE CApiFFI #-}

{- | Fonts through HarfBuzz 14.6.0 and FreeType 2.14.3 (golem-font ADR 0001
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
-}
module Golem.Font
  ( Font,
    FontError (..),
    loadFont,
    fontUnitsPerEm,
    fontIsCff,
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
    ShapedGlyph (..),
    shape,
    shapeUnits,
    glyphVerticalOrigin,
    unitsToSp,
    GlyphMetrics (..),
    glyphMetrics,
    glyphCid,
    subsetFont,
    subsetTag,
    toUnicode,
  )
where

import Control.Exception (bracket)
import Data.Array.Unboxed (UArray, bounds, inRange, listArray, (!))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Unsafe qualified as BU
import Data.Either (fromRight)
import Data.Map.Strict qualified as Map
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Foreign
import Foreign.C.ConstPtr (ConstPtr (..))
import Foreign.C.String (CString, peekCString, withCString)
import Foreign.C.Types
import System.IO.Unsafe (unsafePerformIO)

data CFont

foreign import capi unsafe "golem_font.h golem_font_open" c_open :: Ptr Word8 -> CSize -> IO (Ptr CFont)

foreign import capi unsafe "golem_font.h &golem_font_close" c_close :: FunPtr (Ptr CFont -> IO ())

foreign import capi unsafe "golem_font.h golem_font_upem" c_upem :: Ptr CFont -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_fstype" c_fstype :: Ptr CFont -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_is_cff" c_isCff :: Ptr CFont -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_num_glyphs" c_numGlyphs :: Ptr CFont -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_extents" c_extents :: Ptr CFont -> Ptr Int32 -> Ptr Int32 -> Ptr Int32 -> IO ()

foreign import capi unsafe "golem_font.h golem_font_embox_central" c_emboxCentral :: Ptr CFont -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_glyph_metrics" c_metrics :: Ptr CFont -> Word32 -> Ptr Int32 -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_v_origin" c_vOrigin :: Ptr CFont -> Word32 -> Ptr Int32 -> Ptr Int32 -> IO ()

foreign import capi unsafe "golem_font.h golem_font_shape"
  c_shape :: Ptr CFont -> CString -> CInt -> CString -> CString -> CInt -> CString -> Ptr Word32 -> Ptr Word32 -> Ptr Int32 -> CInt -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_subset" c_subset :: Ptr CFont -> Ptr Word32 -> CInt -> Ptr CSize -> IO (Ptr Word8)

foreign import capi unsafe "golem_font.h golem_font_postscript_name" c_psName :: Ptr CFont -> IO CString

foreign import capi unsafe "golem_font.h golem_font_cid" c_cid :: Ptr CFont -> Word32 -> IO Word32

foreign import capi unsafe "golem_font.h golem_font_is_cid_keyed" c_isCidKeyed :: Ptr CFont -> IO CInt

foreign import capi unsafe "golem_font.h golem_font_ros" c_ros :: Ptr CFont -> Ptr (ConstPtr CChar) -> Ptr (ConstPtr CChar) -> Ptr CInt -> IO CInt

foreign import capi unsafe "golem_font.h golem_free" c_free :: Ptr Word8 -> IO ()

data Font = Font
  { fontPtr :: !(ForeignPtr CFont),
    fontBytes :: !ByteString,
    fontUnitsPerEm :: !Int,
    fontIsCff :: !Bool,
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
    fontCids :: !(Maybe (UArray Int Int))
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
  deriving stock (Eq, Show)

{- | Reads a font from its bytes (never from a path, ADR 0001). IO, called
where the bytes are read (docs/adr ADR 0034).
-}
loadFont :: ByteString -> IO (Either FontError Font)
loadFont bytes = do
  p <- BU.unsafeUseAsCStringLen bytes $ \(ptr, len) -> c_open (castPtr ptr) (fromIntegral len)
  if p == nullPtr
    then pure (Left Unreadable)
    else do
      fp <- newForeignPtr c_close p
      fsType <- fromIntegral <$> c_fstype p
      upem <- fromIntegral <$> c_upem p
      cff <- (/= 0) <$> c_isCff p
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
      touchForeignPtr fp
      pure $
        if embeddingRestricted fsType
          then Left (EmbeddingRestricted fsType)
          else Right (Font fp bytes upem cff n ext ps ros central cids)

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
    srFeatures :: ![Text],
    -- | the font size in sp
    srSize :: !Integer
  }
  deriving stock (Eq, Show)

shapeRequest :: Integer -> Text -> ShapeRequest
shapeRequest size t = ShapeRequest t "" "" Horizontal [] size

data ShapedGlyph = ShapedGlyph
  { sgGlyphId :: !Int,
    -- | byte offset in the UTF-8 text (for ToUnicode)
    sgCluster :: !Int,
    sgAdvance :: !Integer,
    sgOffset :: !(Integer, Integer)
  }
  deriving stock (Eq, Show)

-- | Font units to sp at a size: exact rational, rounded once, half to even.
unitsToSp :: Int -> Integer -> Int -> Integer
unitsToSp upem size units = round (toInteger units * size % toInteger upem)

{- | Glyph ids, clusters and (x advance, y advance, x offset, y offset) in
font units. The vertical direction enables @vert@ (HarfBuzz does so for
top-to-bottom text).
-}
shapeUnits :: Font -> ShapeRequest -> [(Int, Int, (Int, Int, Int, Int))]
shapeUnits f req = unsafePerformIO $ withForeignPtr (fontPtr f) $ \p ->
  BU.unsafeUseAsCStringLen (TE.encodeUtf8 (srText req)) $ \(txt, len) ->
    withCString (T.unpack (srScript req)) $ \script ->
      withCString (T.unpack (srLanguage req)) $ \lang ->
        withCString (T.unpack (T.intercalate "," (srFeatures req))) $ \feats -> do
          let attempt cap =
                allocaArray cap $ \gids -> allocaArray cap $ \clusters -> allocaArray (4 * cap) $ \pos -> do
                  n <- c_shape p txt (fromIntegral len) script lang (if srDirection req == Vertical then 1 else 0) feats gids clusters pos (fromIntegral cap)
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

{- | Shaping with positions in sp. In vertical text the advance is the
downward advance.
-}
shape :: Font -> ShapeRequest -> [ShapedGlyph]
shape f req =
  [ ShapedGlyph g c (sp (if srDirection req == Vertical then negate ya else xa)) (sp xo, sp yo)
  | (g, c, (xa, ya, xo, yo)) <- shapeUnits f req
  ]
  where
    sp = unitsToSp (fontUnitsPerEm f) (srSize req)

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

{- | Glyph id → text from shaping results: a glyph gets the text of its
cluster (a ligature the whole cluster); the first mapping in the
document wins (ADR 0002).
-}
toUnicode :: [(Text, [ShapedGlyph])] -> [(Int, Text)]
toUnicode runs = Map.toList (foldl' add Map.empty runs)
  where
    add m (txt, gs) =
      let bytes = TE.encodeUtf8 txt
          starts = Map.keys (Map.fromList [(sgCluster g, ()) | g <- gs])
          ends = drop 1 starts <> [BS.length bytes]
          clusterText = Map.fromList [(s, TE.decodeUtf8Lenient (BS.take (e - s) (BS.drop s bytes))) | (s, e) <- zip starts ends]
          firstOfCluster = Map.fromListWith (\_ old -> old) [(sgCluster g, sgGlyphId g) | g <- gs]
       in foldl'
            (\acc (c, gid) -> Map.insertWith (\_ old -> old) gid (Map.findWithDefault "" c clusterText) acc)
            m
            (Map.toList firstOfCluster)
