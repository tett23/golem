{-# LANGUAGE MultiWayIf #-}

{- | Reading a page of a PDF so that it can be written as a Form XObject
(golem-pdf ADR 0008). Only what that needs is read: the cross-reference
(tables, streams, object streams, @/Prev@ and @/XRefStm@), objects, three
decoders (Flate with predictors, ASCIIHex, ASCII85) and the page tree.
A broken cross-reference is not repaired. DeviceRGB becomes the sRGB
ICCBased colour space; spot colours, layers, fonts not embedded and RGB
inline images are refused.

Reading is total and bounded (docs/adr ADR 0035): nesting, references and
the revisions are followed to fixed depths, every object at most once,
and no stream is inflated beyond 'maxStreamBytes'.
-}
module Golem.Pdf.Import
  ( ImportedPage (..),
    ImportError (..),
    ColorUse (..),
    FigureContent (..),
    importPage,
    importErrorText,
  )
where

import Codec.Compression.Zlib qualified as Z
import Control.Applicative ((<|>))
import Control.Monad (foldM, unless, when)
import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.ByteString.Lazy qualified as BL
import Data.Either (fromRight)
import Data.List (find, nub)
import Data.Map.Lazy qualified as ML
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, mapMaybe)
import Data.Ratio ((%))
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import Golem.Pdf.Image (ImageData, inflateUpTo, unfilterPng)
import Golem.Pdf.Object
import Golem.Pdf.Sha256 (sha256)
import Golem.Pdf.Srgb (srgbProfile)
import Text.Printf (printf)

-- ------------------------------------------------------------------ the result

-- | A colour space a PDF figure uses, for golem preflight (G0908, G0909).
data ColorUse
  = UseGray
  | -- | DeviceRGB (replaced by sRGB) and CalRGB
    UseRgb
  | UseCmyk
  | -- | ICCBased: the number of components and the profile
    UseIcc !Int !ByteString
  | UseLab
  deriving stock (Eq, Ord, Show)

{- | A page of a PDF, read so that it can be written as a Form XObject.
The objects are keyed by their numbers in the file (0 is the sRGB
profile); the references in them, in the resources and in the group use
those keys, and 'Golem.Pdf.Writer' numbers them again.
-}
data ImportedPage = ImportedPage
  { -- | the SHA-256 of the file, so that pages of one file share their objects
    ipFile :: !ByteString,
    -- | the page, from 1
    ipPage :: !Int,
    -- | the crop box in pt: lower left x, y and upper right x, y
    ipBox :: !(Rational, Rational, Rational, Rational),
    -- | Rotate: 0, 90, 180 or 270
    ipRotate :: !Int,
    -- | the width and the height in pt after the rotation
    ipSize :: !(Rational, Rational),
    ipResources :: !Obj,
    -- | the transparency group of the page
    ipGroup :: !(Maybe Obj),
    -- | the content, decoded and with DeviceRGB replaced
    ipContent :: !ByteString,
    -- | the objects reached from the resources, in the order they are reached
    ipObjects :: ![(Int, Obj)],
    ipColors :: ![ColorUse]
  }
  deriving stock (Eq, Show)

-- | Why a PDF cannot be placed (golem-pdf ADR 0008).
data ImportError
  = -- | where it could not be read
    Malformed !Text
  | Encrypted
  | -- | the page asked for and the number of pages
    NoSuchPage !Int !Int
  | UnsupportedFilter !Text
  | FontNotEmbedded !Text
  | SpotColor
  | RgbInlineImage
  | OptionalContent
  | UnsupportedUserUnit
  deriving stock (Eq, Show)

-- | What a figure placed in a PDF is (golem-pdf ADR 0008).
data FigureContent
  = RasterFigure !ImageData
  | VectorFigure !ImportedPage
  deriving stock (Eq, Show)

-- | The wording shown to the user (golem-pdf ADR 0008).
importErrorText :: ImportError -> Text
importErrorText = \case
  Malformed w -> "PDF として読めません（" <> w <> "）"
  Encrypted -> "暗号化された PDF は使えません"
  NoSuchPage n m -> tshow n <> " ページ目がありません（全 " <> tshow m <> " ページ）"
  UnsupportedFilter f -> f <> " で圧縮された PDF は使えません"
  FontNotEmbedded f -> "埋め込んでいないフォントがあります: " <> f
  SpotColor -> "特色（Separation か DeviceN）があります"
  RgbInlineImage -> "RGB のインライン画像があります"
  OptionalContent -> "レイヤー（オプショナルコンテンツ）があります"
  UnsupportedUserUnit -> "UserUnit が 1 でないページは使えません"

tshow :: (Show a) => a -> Text
tshow = T.pack . show

-- ------------------------------------------------------------------ limits

-- | The most bytes a stream may decode to: 256 MiB (docs/adr ADR 0035).
maxStreamBytes :: Int
maxStreamBytes = 256 * 1024 * 1024

-- | How deep arrays and dictionaries may nest.
maxNesting :: Int
maxNesting = 256

-- | How many revisions (@/Prev@) are followed.
maxRevisions :: Int
maxRevisions = 256

-- ------------------------------------------------------------------ values

type Dict = [(ByteString, V)]

-- | A value as read; names are their bytes, references drop the generation.
data V
  = VNull
  | VBool !Bool
  | VInt !Integer
  | VReal !ByteString
  | VStr !ByteString
  | VName !ByteString
  | VArr ![V]
  | VDict !Dict
  | VRef !Int
  | VStream !Dict !ByteString
  deriving stock (Eq, Show)

type R = Either ImportError

bad :: Text -> R a
bad = Left . Malformed

dictOf :: V -> Dict
dictOf = \case
  VDict d -> d
  VStream d _ -> d
  _ -> []

look :: ByteString -> V -> Maybe V
look k v = lookup k (dictOf v)

nameIs :: ByteString -> ByteString -> V -> Bool
nameIs k n v = look k v == Just (VName n)

-- ------------------------------------------------------------------ lexing

isWs :: Word8 -> Bool
isWs w = w == 0 || w == 9 || w == 10 || w == 12 || w == 13 || w == 32

isDelim :: Word8 -> Bool
isDelim w = w `BS.elem` "()<>[]{}/%"

isRegular :: Word8 -> Bool
isRegular w = not (isWs w || isDelim w)

isDigitW :: Word8 -> Bool
isDigitW w = w >= 48 && w <= 57

isNumChar :: Word8 -> Bool
isNumChar w = isDigitW w || w == 43 || w == 45 || w == 46

-- | Drops white space and comments.
skipWs :: ByteString -> ByteString
skipWs s = case BS.uncons s of
  Just (w, r)
    | isWs w -> skipWs (BS.dropWhile isWs r)
    | w == 37 -> skipWs (BS.dropWhile (\x -> x /= 10 && x /= 13) r)
  _ -> s

-- | An unsigned integer of at most 18 digits.
uint :: ByteString -> R (Int, ByteString)
uint s0 =
  let s = skipWs s0
      (ds, rest) = BS.span isDigitW s
   in if BS.null ds || BS.length ds > 18 then bad "数" else Right (digitsValue ds, rest)

digitsValue :: (Num a) => ByteString -> a
digitsValue = BS.foldl' (\acc w -> acc * 10 + fromIntegral (w - 48)) 0

-- | A keyword followed by a delimiter, white space or the end.
keyword :: ByteString -> ByteString -> R ByteString
keyword kw s0 =
  let s = skipWs s0
      rest = BS.drop (BS.length kw) s
   in if kw `BS.isPrefixOf` s && maybe True (not . isRegular . fst) (BS.uncons rest) then Right rest else bad (TE.decodeLatin1 kw)

-- | Reads one value, with the nesting so far.
parseObj :: Int -> ByteString -> R (V, ByteString)
parseObj depth s0
  | depth > maxNesting = bad "入れ子が深すぎます"
  | otherwise = case BS.uncons s of
      Nothing -> bad "ファイルの終わり"
      Just (w, r)
        | w == 47 -> let (n, rest) = BS.span isRegular r in Right (VName (unescapeName n), rest)
        | w == 40 -> first' VStr <$> literal r
        | w == 60 && BS.take 1 r == "<" -> dict [] (BS.drop 1 r)
        | w == 60 -> first' VStr <$> hexString r
        | w == 91 -> array [] r
        | isNumChar w -> number
        | isRegular w ->
            let (kw, rest) = BS.span isRegular s
             in case kw of
                  "true" -> Right (VBool True, rest)
                  "false" -> Right (VBool False, rest)
                  "null" -> Right (VNull, rest)
                  _ -> bad "値"
        | otherwise -> bad "値"
  where
    s = skipWs s0
    first' f (a, b) = (f a, b)
    array acc t = case BS.uncons (skipWs t) of
      Just (93, rest) -> Right (VArr (reverse acc), rest)
      Nothing -> bad "配列"
      _ -> parseObj (depth + 1) t >>= \(v, rest) -> array (v : acc) rest
    dict acc t =
      let t' = skipWs t
       in if ">>" `BS.isPrefixOf` t'
            then Right (VDict (reverse acc), BS.drop 2 t')
            else case BS.uncons t' of
              Just (47, rest) -> do
                let (k, rest') = BS.span isRegular rest
                (v, rest'') <- parseObj (depth + 1) rest'
                dict ((unescapeName k, v) : acc) rest''
              _ -> bad "辞書"
    number =
      let (tok, rest) = BS.span isNumChar s
          (sign, digits) = case BS.uncons tok of
            Just (45, d) -> (-1, d)
            Just (43, d) -> (1, d)
            _ -> (1, tok)
       in if BS.elem 46 digits
            then if validReal digits then Right (VReal tok, rest) else bad "数"
            else
              if BS.null digits || not (BS.all isDigitW digits) || BS.length digits > 30
                then bad "数"
                else
                  let n = sign * digitsValue digits
                   in case refAfter rest of
                        Just rest' | sign == 1 && BS.length digits <= 18 -> Right (VRef (fromInteger n), rest')
                        _ -> Right (VInt n, rest)
    validReal d =
      let (a, b) = BS.break (== 46) d
          b' = BS.drop 1 b
       in BS.all isDigitW a && BS.all isDigitW b' && not (BS.null a && BS.null b') && BS.length d <= 40
    refAfter t = do
      let t1 = skipWs t
          (g, t2) = BS.span isDigitW t1
      if BS.null g || BS.length g > 10 then Nothing else Just ()
      let t3 = skipWs t2
      case BS.uncons t3 of
        Just (82, t4) | maybe True (not . isRegular . fst) (BS.uncons t4) -> Just t4
        _ -> Nothing

-- | A name with its #xx escapes undone.
unescapeName :: ByteString -> ByteString
unescapeName n
  | BS.notElem 35 n = n
  | otherwise = BS.pack (go (BS.unpack n))
  where
    go = \case
      35 : a : b : rest | Just x <- hexVal a, Just y <- hexVal b -> (x * 16 + y) : go rest
      w : rest -> w : go rest
      [] -> []

hexVal :: Word8 -> Maybe Word8
hexVal w
  | isDigitW w = Just (w - 48)
  | w >= 65 && w <= 70 = Just (w - 55)
  | w >= 97 && w <= 102 = Just (w - 87)
  | otherwise = Nothing

-- | A literal string after its @(@.
literal :: ByteString -> R (ByteString, ByteString)
literal = go (0 :: Int) mempty
  where
    special w = w == 40 || w == 41 || w == 92 || w == 13
    go depth acc t =
      let (plain, rest) = BS.break special t
          acc' = acc <> B.byteString plain
       in case BS.uncons rest of
            Nothing -> bad "文字列"
            Just (41, r)
              | depth == 0 -> Right (BL.toStrict (B.toLazyByteString acc'), r)
              | otherwise -> go (depth - 1) (acc' <> B.word8 41) r
            Just (40, r) -> go (depth + 1) (acc' <> B.word8 40) r
            Just (13, r) -> go depth (acc' <> B.word8 10) (if BS.take 1 r == "\n" then BS.drop 1 r else r)
            Just (_, r) -> case BS.uncons r of
              Nothing -> bad "文字列"
              Just (e, r')
                | e == 110 -> go depth (acc' <> B.word8 10) r'
                | e == 114 -> go depth (acc' <> B.word8 13) r'
                | e == 116 -> go depth (acc' <> B.word8 9) r'
                | e == 98 -> go depth (acc' <> B.word8 8) r'
                | e == 102 -> go depth (acc' <> B.word8 12) r'
                | e == 13 -> go depth acc' (if BS.take 1 r' == "\n" then BS.drop 1 r' else r')
                | e == 10 -> go depth acc' r'
                | e >= 48 && e <= 55 ->
                    let (oct, r'') = BS.span (\x -> x >= 48 && x <= 55) (BS.take 3 r)
                        v = BS.foldl' (\a x -> a * 8 + fromIntegral (x - 48)) (0 :: Int) oct
                     in go depth (acc' <> B.word8 (fromIntegral (v `mod` 256))) (r'' <> BS.drop 3 r)
                | otherwise -> go depth (acc' <> B.word8 e) r'

-- | A hexadecimal string after its @<@.
hexString :: ByteString -> R (ByteString, ByteString)
hexString t =
  let (body, rest) = BS.break (== 62) t
      digits = BS.filter (not . isWs) body
   in case (BS.uncons rest, traverse hexVal (BS.unpack digits)) of
        (Just (_, rest'), Just vs) -> Right (BS.pack (pairs vs), rest')
        _ -> bad "文字列"
  where
    pairs = \case
      a : b : r -> a * 16 + b : pairs r
      [a] -> [a * 16]
      [] -> []

-- ------------------------------------------------------------------ the file

data Entry = InFile !Int | InStream !Int | FreeEntry

-- | A PDF as read: its bytes, its cross-reference and its object streams, decoded once.
data Doc = Doc
  { docBytes :: !ByteString,
    docXref :: !(Map Int Entry),
    docStreams :: ML.Map Int (R (Map Int V))
  }

-- | The object @n@, or null when the cross-reference does not have it.
fetch :: Doc -> Int -> R V
fetch d = fetchAt d 0

fetchAt :: Doc -> Int -> Int -> R V
fetchAt d depth n = case Map.lookup n (docXref d) of
  Just (InFile off) -> objectAt d depth (Just n) off
  Just (InStream s) -> case ML.lookup s (docStreams d) of
    Just r -> Map.findWithDefault VNull n <$> r
    Nothing -> Right VNull
  _ -> Right VNull

-- | A value with a reference followed.
resolve :: Doc -> V -> R V
resolve d = \case
  VRef n -> fetch d n
  v -> Right v

{- | The indirect object at an offset: @n g obj@, its value and, for a
stream, its data. With @Just n@ the number must be @n@.
-}
objectAt :: Doc -> Int -> Maybe Int -> Int -> R V
objectAt d depth want off = do
  let bytes = docBytes d
      where' = "オブジェクト " <> maybe (tshow off) tshow want
  when (off < 0 || off >= BS.length bytes) (bad where')
  either (const (bad where')) Right $ do
    (num, s1) <- uint (BS.drop off bytes)
    (_, s2) <- uint s1
    s3 <- keyword "obj" s2
    when (maybe False (/= num) want) (bad where')
    (v, s4) <- parseObj 0 s3
    let s5 = skipWs s4
    if "stream" `BS.isPrefixOf` s5
      then case v of
        VDict dict -> do
          when (isJust (lookup "F" dict)) (bad "外部のファイルのストリーム")
          let s6 = dropEol (BS.drop 6 s5)
          len <- streamLength d depth num dict
          when (len > BS.length s6) (bad "ストリームの長さ")
          let (body, after) = BS.splitAt len s6
          unless ("endstream" `BS.isPrefixOf` skipWs after) (bad "ストリームの長さ")
          Right (VStream dict body)
        _ -> bad where'
      else Right v
  where
    dropEol t
      | "\r\n" `BS.isPrefixOf` t = BS.drop 2 t
      | "\n" `BS.isPrefixOf` t || "\r" `BS.isPrefixOf` t = BS.drop 1 t
      | otherwise = t

-- | The Length of a stream, which may be an indirect object.
streamLength :: Doc -> Int -> Int -> Dict -> R Int
streamLength d depth self dict = case lookup "Length" dict of
  Just (VInt l) | l >= 0 && l <= fromIntegral maxStreamBytes * 4 -> Right (fromInteger l)
  Just (VRef m)
    | depth < 4 && m /= self ->
        fetchAt d (depth + 1) m >>= \case
          VInt l | l >= 0 && l <= fromIntegral maxStreamBytes * 4 -> Right (fromInteger l)
          _ -> bad "ストリームの長さ"
  _ -> bad "ストリームの長さ"

-- | The objects of an object stream, by number.
objectStream :: Doc -> Int -> R (Map Int V)
objectStream d s = case Map.lookup s (docXref d) of
  Just (InFile off) ->
    objectAt d 0 (Just s) off >>= \case
      VStream dict body -> do
        decoded <- decodeStream d dict body
        let int k = case lookup k dict of
              Just (VInt x) | x >= 0 && x <= 10000000 -> Right (fromInteger x)
              _ -> bad "オブジェクトのストリーム"
        n <- int "N"
        first <- int "First"
        let header = BS.take first decoded
        pairs <- readPairs n header
        Map.fromList <$> traverse (\(num, o) -> (num,) . fst <$> parseObj 0 (BS.drop (first + o) decoded)) pairs
      _ -> bad "オブジェクトのストリーム"
  _ -> bad "オブジェクトのストリーム"
  where
    readPairs :: Int -> ByteString -> R [(Int, Int)]
    readPairs 0 _ = Right []
    readPairs k t = do
      (a, t1) <- uint t
      (b, t2) <- uint t1
      ((a, b) :) <$> readPairs (k - 1) t2

-- ------------------------------------------------------------------ the cross-reference

-- | The cross-reference and the trailer, from the last @startxref@.
readXref :: ByteString -> R (Map Int Entry, Dict)
readXref bytes = do
  let tailBytes = BS.drop (BS.length bytes - 2048) bytes
      (_, at) = lastOccurrence "startxref" tailBytes
  when (BS.null at) (bad "startxref")
  (off, _) <- either (const (bad "startxref")) Right (uint (BS.drop 9 at))
  when (off >= BS.length bytes) (bad "startxref")
  chain Set.empty 0 off
  where
    chain seen depth off
      | depth > maxRevisions || Set.member off seen || off < 0 || off >= BS.length bytes = bad "相互参照"
      | otherwise = do
          (entries, trailer) <- section off
          let seen' = Set.insert off seen
          stm <- case lookup "XRefStm" trailer of
            Just (VInt o) | not (Set.member (fromInteger o) seen') -> fst <$> streamSection (fromInteger o)
            _ -> Right Map.empty
          (older, olderTrailer) <- case lookup "Prev" trailer of
            Just (VInt p) -> chain seen' (depth + 1) (fromInteger p)
            _ -> Right (Map.empty, [])
          Right (entries `Map.union` stm `Map.union` older, trailer <> [kv | kv@(k, _) <- olderTrailer, k `notElem` map fst trailer, k `notElem` ["Prev", "XRefStm"]])
    section off =
      let s = skipWs (BS.drop off bytes)
       in if "xref" `BS.isPrefixOf` s then table (BS.drop 4 s) else streamSection off
    table = go Map.empty
      where
        go acc t0 =
          let t = skipWs t0
           in if "trailer" `BS.isPrefixOf` t
                then
                  parseObj 0 (BS.drop 7 t) >>= \case
                    (VDict dict, _) -> Right (acc, dict)
                    _ -> bad "トレーラー"
                else do
                  (start, t1) <- uint t
                  (count, t2) <- uint t1
                  when (count > BS.length t2 `div` 18 + 1) (bad "相互参照")
                  (acc', t3) <- entries start count acc t2
                  go acc' t3
        entries _ 0 acc t = Right (acc, t)
        entries n k acc t = do
          (o, t1) <- uint t
          (_, t2) <- uint t1
          case BS.uncons (skipWs t2) of
            Just (110, r) -> entries (n + 1) (k - 1 :: Int) (Map.insertWith (\_ old -> old) n (InFile o) acc) r
            Just (102, r) -> entries (n + 1) (k - 1) (Map.insertWith (\_ old -> old) n FreeEntry acc) r
            _ -> bad "相互参照"
    streamSection off = do
      let probe = Doc bytes Map.empty ML.empty
      v <- objectAt probe 0 Nothing off
      case v of
        VStream dict body | lookup "Type" dict == Just (VName "XRef") -> do
          decoded <- decodeWith [(n, p) | (n, p) <- filtersDirect dict] body
          ws <- case lookup "W" dict of
            Just (VArr xs) | length xs == 3, all smallInt xs -> Right [fromInteger i | VInt i <- xs]
            _ -> bad "相互参照"
          size <- case lookup "Size" dict of
            Just (VInt sz) | sz >= 0 && sz <= 100000000 -> Right (fromInteger sz)
            _ -> bad "相互参照"
          index <- case lookup "Index" dict of
            Nothing -> Right [(0, size)]
            Just (VArr xs) | all isInt xs, even (length xs) -> Right (pairsOf [fromInteger i | VInt i <- xs])
            _ -> bad "相互参照"
          Right (xrefRows ws index decoded, dict)
        _ -> bad "相互参照"
    smallInt = \case
      VInt i -> i >= 0 && i <= 8
      _ -> False
    isInt = \case
      VInt i -> i >= 0 && i <= 100000000
      _ -> False
    pairsOf = \case
      a : b : r -> (a, b) : pairsOf r
      _ -> []

-- | The entries of a cross-reference stream.
xrefRows :: [Int] -> [(Int, Int)] -> ByteString -> Map Int Entry
xrefRows ws index decoded =
  let width = sum ws
      rowsOf = if width <= 0 then [] else takeRows decoded
      takeRows b = if BS.length b < width then [] else BS.take width b : takeRows (BS.drop width b)
      numbers = concat [[start .. start + count - 1] | (start, count) <- index]
      field b i =
        let w = ws !! i
            off = sum (take i ws)
         in BS.foldl' (\acc x -> acc `shiftL` 8 .|. fromIntegral x) (0 :: Int) (BS.take w (BS.drop off b))
      entry b =
        let t = if head' ws == 0 then 1 else field b 0
         in case t of
              0 -> Just FreeEntry
              1 -> Just (InFile (field b 1))
              2 -> Just (InStream (field b 1))
              _ -> Nothing
      head' = \case
        x : _ -> x
        [] -> 0
   in Map.fromListWith (\_ old -> old) [(n, e) | (n, b) <- zip numbers rowsOf, Just e <- [entry b]]

-- | The last occurrence of a needle: what is before it, and it with what follows.
lastOccurrence :: ByteString -> ByteString -> (ByteString, ByteString)
lastOccurrence needle hay = go 0 Nothing
  where
    go from found =
      let (_, at) = BS.breakSubstring needle (BS.drop from hay)
       in if BS.null at
            then maybe (hay, "") (`BS.splitAt` hay) found
            else let i = BS.length hay - BS.length at in go (i + 1) (Just i)

-- ------------------------------------------------------------------ decoding

-- | The filters of a stream whose Filter and DecodeParms are direct.
filtersDirect :: Dict -> [(ByteString, Dict)]
filtersDirect dict = zip names (parms <> repeat [])
  where
    names = case lookup "Filter" dict of
      Just (VName n) -> [n]
      Just (VArr xs) -> [n | VName n <- xs]
      _ -> []
    parms = case lookup "DecodeParms" dict of
      Just (VDict p) -> [p]
      Just (VArr xs) -> map dictOf xs
      _ -> []

-- | The filters of a stream, with references followed.
filtersOf :: Doc -> Dict -> R [(ByteString, Dict)]
filtersOf d dict = do
  f <- maybe (Right VNull) (resolve d) (lookup "Filter" dict)
  p <- maybe (Right VNull) (resolve d) (lookup "DecodeParms" dict)
  names <- case f of
    VNull -> Right []
    VName n -> Right [n]
    VArr xs -> traverse (resolve d >=> nameOf) xs
    _ -> bad "フィルター"
  parms <- case p of
    VDict pd -> Right [pd]
    VArr xs -> map dictOf <$> traverse (resolve d) xs
    _ -> Right []
  Right (zip names (parms <> repeat []))
  where
    nameOf = \case
      VName n -> Right n
      _ -> bad "フィルター"
    (>=>) f g x = f x >>= g

decodeStream :: Doc -> Dict -> ByteString -> R ByteString
decodeStream d dict body = filtersOf d dict >>= \fs -> decodeWith fs body

-- | The filters Golem decodes (ADR 0008).
decodable :: [ByteString]
decodable = ["FlateDecode", "ASCIIHexDecode", "ASCII85Decode"]

-- | The filters copied as they are, in image streams only.
imageOnly :: [ByteString]
imageOnly = ["DCTDecode", "CCITTFaxDecode", "RunLengthDecode"]

decodeWith :: [(ByteString, Dict)] -> ByteString -> R ByteString
decodeWith fs b0 = foldM step b0 fs
  where
    step b (name, parms) = case name of
      "FlateDecode" -> either (const (bad "Flate のストリーム")) Right (inflateUpTo maxStreamBytes b) >>= predict parms
      "ASCIIHexDecode" -> asciiHex b
      "ASCII85Decode" -> ascii85 b
      other -> Left (UnsupportedFilter (TE.decodeLatin1 other))

-- | The predictor of Flate: none, TIFF 2 (8 bits) or the PNG filters.
predict :: Dict -> ByteString -> R ByteString
predict parms b =
  let int k def = case lookup k parms of
        Just (VInt x) | x >= 0 && x <= 65536 -> fromInteger x
        _ -> def
      predictor = int "Predictor" 1 :: Int
      colors = int "Colors" 1 :: Int
      bpc = int "BitsPerComponent" 8 :: Int
      columns = int "Columns" 1 :: Int
      rowBytes = (columns * colors * bpc + 7) `div` 8
   in if
        | predictor == 1 -> Right b
        | predictor == 2 && bpc == 8 -> Right (BS.concat (map (tiffRow colors) (chunks rowBytes b)))
        | predictor >= 10 ->
            let h = BS.length b `div` (rowBytes + 1)
             in either (const (bad "予測子")) Right (unfilterPng (max 1 ((colors * bpc) `div` 8)) rowBytes h (BS.take (h * (rowBytes + 1)) b))
        | otherwise -> Left (UnsupportedFilter "FlateDecode")
  where
    chunks n s = if n <= 0 || BS.null s then [] else BS.take n s : chunks n (BS.drop n s)
    -- each byte plus the decoded one a pixel before it
    tiffRow bpp row = BS.pack (reverse (foldl (\done (i, w) -> (w + (if i >= bpp then done !! (bpp - 1) else 0)) : done) [] (zip [0 :: Int ..] (BS.unpack row))))

asciiHex :: ByteString -> R ByteString
asciiHex b =
  let body = BS.filter (not . isWs) (BS.takeWhile (/= 62) b)
   in case traverse hexVal (BS.unpack body) of
        Just vs -> Right (BS.pack (pairs vs))
        Nothing -> bad "ASCIIHex のストリーム"
  where
    pairs = \case
      a : c : r -> a * 16 + c : pairs r
      [a] -> [a * 16]
      [] -> []

ascii85 :: ByteString -> R ByteString
ascii85 b0 =
  let b1 = BS.filter (not . isWs) b0
      b2 = if "<~" `BS.isPrefixOf` b1 then BS.drop 2 b1 else b1
      body = fst (BS.breakSubstring "~>" b2)
   in BL.toStrict . B.toLazyByteString <$> go mempty (BS.unpack body)
  where
    go acc = \case
      [] -> Right acc
      122 : rest -> go (acc <> B.word32BE 0) rest
      ws
        | (grp, rest) <- splitAt 5 ws,
          all (\w -> w >= 33 && w <= 117) grp ->
            let n = length grp
                padded = grp <> replicate (5 - n) 117
                v = foldl (\a w -> a * 85 + toInteger (w - 33)) 0 padded
             in if n < 2 || v > 0xFFFFFFFF
                  then if n == 0 then Right acc else bad "ASCII85 のストリーム"
                  else
                    let bytes = [fromInteger ((v `div` (256 ^ i)) `mod` 256) | i <- [3, 2, 1, 0 :: Int]]
                     in go (acc <> B.byteString (BS.pack (take (n - 1) bytes))) rest
        | otherwise -> bad "ASCII85 のストリーム"

-- ------------------------------------------------------------------ the page

-- | What a page inherits from the page tree.
data Inherited = Inherited
  { inResources :: !(Maybe V),
    inMediaBox :: !(Maybe V),
    inCropBox :: !(Maybe V),
    inRotate :: !(Maybe V)
  }

-- | The pages of the tree in order, each with what it inherits.
pageLeaves :: Doc -> V -> R [(Dict, Inherited)]
pageLeaves d = walk Set.empty (0 :: Int) (Inherited Nothing Nothing Nothing Nothing)
  where
    walk seen depth inh v
      | depth > 64 = bad "ページの木"
      | otherwise = do
          (key, node) <- case v of
            VRef n
              | Set.member n seen -> bad "ページの木"
              | otherwise -> (Just n,) <$> fetch d n
            _ -> Right (Nothing, v)
          dict <- case node of
            VDict x -> Right x
            _ -> bad "ページの木"
          let seen' = maybe seen (`Set.insert` seen) key
              pick k f = lookup k dict <|> f inh
              inh' = Inherited (pick "Resources" inResources) (pick "MediaBox" inMediaBox) (pick "CropBox" inCropBox) (pick "Rotate" inRotate)
          if lookup "Type" dict == Just (VName "Page")
            then Right [(dict, inh')]
            else case lookup "Kids" dict of
              Nothing -> Right []
              Just kv ->
                resolve d kv >>= \case
                  VArr kids -> concat <$> traverse (walk seen' (depth + 1) inh') kids
                  _ -> bad "ページの木"

numberOf :: V -> Maybe Rational
numberOf = \case
  VInt i -> Just (fromInteger i)
  VReal t ->
    let (sign, digits) = case BS.uncons t of
          Just (45, r) -> (-1, r)
          Just (43, r) -> (1, r)
          _ -> (1, t)
        (a, b) = BS.break (== 46) digits
        f = BS.drop 1 b
     in Just (sign * (fromInteger (digitsValue a) + fromInteger (digitsValue f) % (10 ^ BS.length f)))
  _ -> Nothing

-- | A rectangle as lower left and upper right.
type Box = (Rational, Rational, Rational, Rational)

boxOf :: Doc -> V -> R Box
boxOf d v =
  resolve d v >>= \case
    VArr xs | length xs == 4 -> do
      ns <- traverse (\x -> resolve d x >>= maybe (bad "ページの大きさ") Right . numberOf) xs
      case ns of
        [a, b, c, e] -> Right (min a c, min b e, max a c, max b e)
        _ -> bad "ページの大きさ"
    _ -> bad "ページの大きさ"

-- ------------------------------------------------------------------ importing

{- | The page @n@ (from 1) of a PDF, as a Form XObject can be written from
it (golem-pdf ADR 0008).
-}
importPage :: Int -> ByteString -> Either ImportError ImportedPage
importPage n bytes = do
  checkHeader bytes
  (xref, trailer) <- readXref bytes
  when (isJust (lookup "Encrypt" trailer)) (Left Encrypted)
  let doc = Doc bytes xref (ML.fromList [(s, objectStream doc s) | s <- Set.toList (Set.fromList [s | InStream s <- Map.elems xref])])
  root <- maybe (bad "トレーラー") (resolve doc) (lookup "Root" trailer)
  pagesRoot <- maybe (bad "ページの木") Right (look "Pages" root)
  leaves <- pageLeaves doc pagesRoot
  (page, inh) <- if n >= 1 && n <= length leaves then Right (leaves !! (n - 1)) else Left (NoSuchPage n (length leaves))
  userUnit <- maybe (Right Nothing) (fmap numberOf . resolve doc) (lookup "UserUnit" page)
  when (maybe False (/= 1) userUnit) (Left UnsupportedUserUnit)
  media <- maybe (bad "ページの大きさ") (boxOf doc) (inMediaBox inh)
  crop <- maybe (Right media) (boxOf doc) (inCropBox inh)
  let (mx0, my0, mx1, my1) = media
      (cx0, cy0, cx1, cy1) = crop
      box@(x0, y0, x1, y1) = (max mx0 cx0, max my0 cy0, min mx1 cx1, min my1 cy1)
  when (x1 <= x0 || y1 <= y0) (bad "ページの大きさ")
  rotate <-
    maybe (Right (VInt 0)) (resolve doc) (inRotate inh) >>= \case
      VInt r | r `mod` 90 == 0 -> Right (fromInteger (r `mod` 360))
      _ -> bad "Rotate"
  resources <- maybe (Right (VDict [])) (resolve doc) (inResources inh)
  group <- traverse (resolve doc) (lookup "Group" page)
  content <- pageContent doc page
  -- the objects the resources and the group reach, each once
  objs <- collect doc (resources : maybe [] pure group)
  let roots = resources : maybe [] pure group
      values = roots <> [o | (_, o, _) <- objs]
  checkObjects doc objs values
  -- the content streams decoded, checked and with DeviceRGB replaced
  (pageBytes, pageChanged, pageUses) <- rewriteContent content
  rewritten <-
    Map.fromList
      <$> traverse
        (\(k, o) -> case o of VStream dict body -> (k,) <$> (decodeStream doc dict body >>= rewriteContent); _ -> bad "内容のストリーム")
        [(k, o) | (k, o, Content) <- objs]
  let contentNeeds = pageChanged || any (\(_, c, _) -> c) (Map.elems rewritten)
      objectNeeds = any hasDeviceRgb values
      withProfile = contentNeeds || objectNeeds
      keys = Set.fromList ([k | (k, _, _) <- objs] <> [0 | withProfile])
      marked = Set.fromList [r | v <- values, (k, VRef r) <- dictsEntries v, k == "Resources"]
      conv = convert keys contentNeeds
      raw = Map.fromList [(k, o) | (k, o, _) <- objs]
      addSrgb' = addSrgb (\c -> conv (Map.findWithDefault VNull c raw))
      object (k, o, role) = (k,) $ case (o, role) of
        (VStream dict _, Content) ->
          let (body, _, _) = Map.findWithDefault (pageBytes, False, []) k rewritten
           in OStream (convDict keys contentNeeds [kv | kv@(key, _) <- dict, key `notElem` ["Filter", "DecodeParms", "DL"]] <> [("Filter", OName "FlateDecode")]) (flate body)
        (VStream dict body, Plain) -> OStream (convDict keys contentNeeds dict) body
        _
          | contentNeeds && Set.member k marked -> addSrgb' (conv o)
          | otherwise -> conv o
      profile = OStream [("N", OInt 3), ("Filter", OName "FlateDecode")] (flate srgbProfile)
      size = if rotate == 90 || rotate == 270 then (y1 - y0, x1 - x0) else (x1 - x0, y1 - y0)
  uses <- objectUses doc values
  Right
    ImportedPage
      { ipFile = sha256 bytes,
        ipPage = n,
        ipBox = box,
        ipRotate = rotate,
        ipSize = size,
        ipResources = (if contentNeeds then addSrgb' else id) (conv resources),
        ipGroup = conv <$> group,
        ipContent = pageBytes,
        ipObjects = map object objs <> [(0, profile) | withProfile],
        ipColors = nub (pageUses <> concat [u | (_, _, u) <- Map.elems rewritten] <> uses)
      }

-- | @%PDF-1.0@ to @%PDF-1.7@ and @%PDF-2.0@.
checkHeader :: ByteString -> R ()
checkHeader b =
  let v = BS.take 3 (BS.drop 5 b)
   in if "%PDF-" `BS.isPrefixOf` b && (v `elem` ["1.0", "1.1", "1.2", "1.3", "1.4", "1.5", "1.6", "1.7", "2.0"])
        then Right ()
        else bad "ヘッダー"

-- | The content of a page: its streams decoded and joined by newlines.
pageContent :: Doc -> Dict -> R ByteString
pageContent d page = case lookup "Contents" page of
  Nothing -> Right ""
  Just v ->
    resolve d v >>= \case
      VArr xs -> BS.intercalate "\n" <$> traverse (resolve d >=> one) xs
      other -> one other
  where
    one = \case
      VStream dict body -> decodeStream d dict body
      VNull -> Right ""
      _ -> bad "内容のストリーム"
    (>=>) f g x = f x >>= g

-- | What a stream is to the copy: its data is decoded and rewritten, or copied as it is.
data Role = Plain | Content
  deriving stock (Eq)

data Hint = NoHint | ContentHint | CharProcsHint
  deriving stock (Eq)

-- | Keys not copied, nor followed.
skipKeys :: [ByteString]
skipKeys = ["Parent", "Metadata", "PieceInfo", "StructParent", "StructParents"]

{- | The objects reached from the roots, in the order of the keys and the
elements as they are in the file, each once. Pages, page trees and the
catalog are not reached: references to them become null.
-}
collect :: Doc -> [V] -> R [(Int, V, Role)]
collect d roots = (\(_, acc) -> reverse acc) <$> foldM (go NoHint) (Set.empty, []) roots
  where
    go hint st@(seen, acc) = \case
      VRef k
        | k <= 0 || Set.member k seen -> Right st
        | otherwise -> do
            o <- fetch d k
            let seen' = Set.insert k seen
            if excluded o || o == VNull
              then Right (seen', acc)
              else do
                let role = if hint == ContentHint || isContentStream o then Content else Plain
                    st' = (seen', (k, o, role) : acc)
                if hint == CharProcsHint then children ContentHint st' o else children NoHint st' o
      v -> if hint == CharProcsHint then children ContentHint st v else children NoHint st v
    -- the values inside a value; the values of CharProcs are content
    children hint st = \case
      VArr xs -> foldM (go hint) st xs
      VDict kv -> entries hint st kv
      VStream kv _ -> entries hint st kv
      _ -> Right st
    entries hint st kv =
      foldM
        ( \s (k, v) ->
            if
              | k `elem` skipKeys -> Right s
              | hint == ContentHint -> go ContentHint s v
              | k == "CharProcs" && lookup "Subtype" kv == Just (VName "Type3") -> go CharProcsHint s v
              | otherwise -> go NoHint s v
        )
        st
        kv
    excluded o = any (\t -> nameIs "Type" t o) ["Page", "Pages", "Catalog"]

isContentStream :: V -> Bool
isContentStream = \case
  VStream dict _ -> lookup "Subtype" dict == Just (VName "Form") || lookup "PatternType" dict == Just (VInt 1)
  _ -> False

-- | Every dictionary in a value, not following references.
dictsIn :: V -> [Dict]
dictsIn = \case
  VDict kv -> kv : concatMap (dictsIn . snd) kv
  VStream kv _ -> kv : concatMap (dictsIn . snd) kv
  VArr xs -> concatMap dictsIn xs
  _ -> []

-- | Every entry of every dictionary in a value.
dictsEntries :: V -> [(ByteString, V)]
dictsEntries = concat . dictsIn

-- | Every value in a value, itself first.
valuesIn :: V -> [V]
valuesIn v =
  v : case v of
    VDict kv -> concatMap (valuesIn . snd) kv
    VStream kv _ -> concatMap (valuesIn . snd) kv
    VArr xs -> concatMap valuesIn xs
    _ -> []

{- | The refusals of ADR 0008 on the objects copied: filters, fonts not
embedded, spot colours and layers, in that order.
-}
checkObjects :: Doc -> [(Int, V, Role)] -> [V] -> R ()
checkObjects d objs values = do
  mapM_ filterOk objs
  mapM_ fontOk (concatMap dictsIn values)
  when (any (any isSpot . valuesIn) values) (Left SpotColor)
  when (any (any layer . dictsIn) values) (Left OptionalContent)
  where
    filterOk (_, o, role) = case o of
      VStream dict _ -> do
        names <- map fst <$> filtersOf d dict
        let image = lookup "Subtype" dict == Just (VName "Image")
            allowed = decodable <> (if role == Plain && image then imageOnly else [])
        maybe (Right ()) (Left . UnsupportedFilter . TE.decodeLatin1) (find (`notElem` allowed) names)
      _ -> Right ()
    fontOk kv
      | Just (VName st) <- lookup "Subtype" kv,
        st `elem` ["Type1", "MMType1", "TrueType", "CIDFontType0", "CIDFontType2"],
        maybe True (== VName "Font") (lookup "Type" kv) = do
          desc <- maybe (Right VNull) (resolve d) (lookup "FontDescriptor" kv)
          unless (any (\k -> isJust (look k desc)) ["FontFile", "FontFile2", "FontFile3"]) $
            Left (FontNotEmbedded (maybe "名前のないフォント" nameText' (lookup "BaseFont" kv)))
      | otherwise = Right ()
    nameText' = \case
      VName b -> TE.decodeLatin1 b
      _ -> "名前のないフォント"
    isSpot = \case
      VArr (VName s : _) -> s == "Separation" || s == "DeviceN"
      _ -> False
    layer kv = isJust (lookup "OC" kv) || lookup "Type" kv `elem` [Just (VName "OCG"), Just (VName "OCMD")]

hasDeviceRgb :: V -> Bool
hasDeviceRgb = elem (VName "DeviceRGB") . valuesIn

-- | The colour spaces of the objects (ADR 0008), in the order they are found.
objectUses :: Doc -> [V] -> R [ColorUse]
objectUses d values = concat <$> traverse use (concatMap valuesIn values)
  where
    use = \case
      VName "DeviceGray" -> Right [UseGray]
      VName "DeviceRGB" -> Right [UseRgb]
      VName "DeviceCMYK" -> Right [UseCmyk]
      VArr (VName "CalGray" : _) -> Right [UseGray]
      VArr (VName "CalRGB" : _) -> Right [UseRgb]
      VArr (VName "Lab" : _) -> Right [UseLab]
      VArr [VName "ICCBased", ref] ->
        resolve d ref >>= \case
          VStream dict body -> do
            let n = case lookup "N" dict of
                  Just (VInt i) -> fromInteger i
                  _ -> 0
                profile = fromRight body (decodeStream d dict body)
            Right [UseIcc n profile]
          _ -> Right []
      _ -> Right []

-- ------------------------------------------------------------------ writing the copy

-- | The sRGB ICCBased colour space; key 0 is its profile.
srgbSpace :: Obj
srgbSpace = OArr [OName "ICCBased", ORef 0]

-- | A name in PDF syntax, with #xx for what a name cannot hold as it is.
nameText :: ByteString -> Text
nameText = T.pack . concatMap one . BS.unpack
  where
    one w
      | w >= 0x21 && w <= 0x7E && not (isDelim w) && w /= 35 = [toEnum (fromIntegral w)]
      | otherwise = printf "#%02X" w

{- | A value as an object of the writer: DeviceRGB as the sRGB colour
space, references to objects not copied as null, and, when the content
was rewritten, GolemSRGB in every direct Resources.
-}
convert :: Set Int -> Bool -> V -> Obj
convert keys needs = \case
  VNull -> ONull
  VBool b -> OBool b
  VInt i -> OInt i
  VReal t -> OReal (TE.decodeLatin1 t)
  VStr s -> OHex s
  VName "DeviceRGB" -> srgbSpace
  VName n -> OName (nameText n)
  VArr xs -> OArr (map (convert keys needs) xs)
  VDict kv -> ODict (convDict keys needs kv)
  VRef k -> if Set.member k keys then ORef k else ONull
  VStream kv body -> OStream (convDict keys needs kv) body

convDict :: Set Int -> Bool -> Dict -> [(Text, Obj)]
convDict keys needs kv =
  [ (nameText k, v')
  | (k, v) <- kv,
    k `notElem` ("Length" : skipKeys),
    let v0 = convert keys needs v
        v' = if needs && k == "Resources" then addSrgb (const ONull) v0 else v0,
    v' /= ONull
  ]

{- | GolemSRGB in the ColorSpace of resources; a ColorSpace that is a
reference is written there with the entries of the object it refers to.
-}
addSrgb :: (Int -> Obj) -> Obj -> Obj
addSrgb deref = \case
  ODict kv ->
    let spaces = case lookup "ColorSpace" kv of
          Just (ODict cs) -> cs
          Just (ORef c) | ODict cs <- deref c -> cs
          _ -> []
     in ODict (filter ((/= "ColorSpace") . fst) kv <> [("ColorSpace", ODict (filter ((/= "GolemSRGB") . fst) spaces <> [("GolemSRGB", srgbSpace)]))])
  other -> other

flate :: ByteString -> ByteString
flate = BL.toStrict . Z.compressWith Z.defaultCompressParams {Z.compressLevel = Z.compressionLevel 9} . BL.fromStrict

-- ------------------------------------------------------------------ content streams

-- | A token of a content stream.
data CTok
  = CNum !ByteString
  | CName !ByteString
  | COther
  | COp !ByteString
  | CInline !Dict
  deriving stock (Eq, Show)

-- | The tokens of a content stream with their start and end.
scanContent :: ByteString -> R [(Int, Int, CTok)]
scanContent c = go 0 []
  where
    len = BS.length c
    go i acc
      | i >= len = Right (reverse acc)
      | otherwise =
          let w = BS.index c i
              rest = BS.drop i c
           in if
                | isWs w -> go (i + 1) acc
                | w == 37 -> go (i + BS.length (BS.takeWhile (\x -> x /= 10 && x /= 13) rest)) acc
                | w == 47 ->
                    let n = BS.takeWhile isRegular (BS.drop 1 rest)
                        j = i + 1 + BS.length n
                     in go j ((i, j, CName (unescapeName n)) : acc)
                | w == 40 || w == 60 || w == 91 -> do
                    (_, after) <- either (const (bad "内容のストリーム")) Right (parseObj 0 rest)
                    let j = len - BS.length after
                    go j ((i, j, COther) : acc)
                | w == 123 || w == 125 -> go (i + 1) ((i, i + 1, COther) : acc)
                | isNumChar w ->
                    let t = BS.takeWhile isNumChar rest
                        j = i + BS.length t
                     in go j ((i, j, CNum t) : acc)
                | isRegular w ->
                    let kw = BS.takeWhile isRegular rest
                        j = i + BS.length kw
                     in case kw of
                          "BI" -> do
                            (dict, k) <- inlineImage j
                            go k ((i, k, CInline dict) : acc)
                          _ | kw `elem` ["true", "false", "null"] -> go j ((i, j, COther) : acc)
                          _ -> go j ((i, j, COp kw) : acc)
                | otherwise -> bad "内容のストリーム"
    -- the dictionary of an inline image after BI, and the end of its EI
    inlineImage j = entries [] (BS.drop j c)
      where
        entries acc t0 =
          let t = skipWs t0
           in if "ID" `BS.isPrefixOf` t && maybe True (isWs . fst) (BS.uncons (BS.drop 2 t))
                then
                  let dataStart = len - BS.length t + 3
                   in (reverse acc,) <$> findEi dataStart
                else case BS.uncons t of
                  Just (47, r) -> do
                    let (k, r') = BS.span isRegular r
                    (v, r'') <- either (const (bad "内容のストリーム")) Right (parseObj 0 r')
                    entries ((unescapeName k, v) : acc) r''
                  _ -> bad "内容のストリーム"
        findEi from =
          let (_, at) = BS.breakSubstring "EI" (BS.drop from c)
              k = len - BS.length at
              before = if k > 0 then BS.index c (k - 1) else 32
              after = BS.drop (k + 2) c
           in if BS.null at
                then bad "内容のストリーム"
                else
                  if isWs before && maybe True (not . isRegular . fst) (BS.uncons after)
                    then Right (k + 2)
                    else findEi (k + 2)

{- | A content stream with DeviceRGB replaced (ADR 0008): @r g b rg@ as
@/GolemSRGB cs r g b sc@, @RG@ as @CS@ and @SC@, @/DeviceRGB cs@ as
@/GolemSRGB cs@. Also whether it changed and the colour spaces it uses;
an RGB inline image is refused.
-}
rewriteContent :: ByteString -> R (ByteString, Bool, [ColorUse])
rewriteContent c = do
  toks <- scanContent c
  (edits, uses) <- walk [] [] [] toks
  let out = splice 0 (reverse edits)
  Right (out, not (null edits), nub (reverse uses))
  where
    walk operands edits uses = \case
      [] -> Right (edits, uses)
      (s, e, tok) : rest -> case tok of
        COp op -> do
          (edits', uses') <- operator op (reverse operands) e edits uses
          walk [] edits' uses' rest
        CInline dict -> do
          u <- inlineUses dict
          walk [] edits (u <> uses) rest
        _ -> walk ((s, e, tok) : operands) edits uses rest
    operator op args e edits uses = case (op, args) of
      (_, [(s, _, CNum a), (_, _, CNum b), (_, _, CNum cc)])
        | op == "rg" || op == "RG" ->
            let (space, set) = if op == "rg" then ("cs", "sc") else ("CS", "SC")
             in Right ((s, e, "/GolemSRGB " <> space <> " " <> a <> " " <> b <> " " <> cc <> " " <> set) : edits, UseRgb : uses)
      (_, [(s, ne, CName n)])
        | op == "cs" || op == "CS" -> case n of
            "DeviceRGB" -> Right ((s, ne, "/GolemSRGB") : edits, UseRgb : uses)
            "DeviceGray" -> Right (edits, UseGray : uses)
            "DeviceCMYK" -> Right (edits, UseCmyk : uses)
            _ -> Right (edits, uses)
      _
        | op == "g" || op == "G" -> Right (edits, UseGray : uses)
        | op == "k" || op == "K" -> Right (edits, UseCmyk : uses)
        | otherwise -> Right (edits, uses)
    inlineUses dict = do
      let cs = fromMaybe VNull (lookup "CS" dict <|> lookup "ColorSpace" dict)
          names = [n | VName n <- valuesIn cs]
          filters = [n | VName n <- valuesIn (fromMaybe VNull (lookup "F" dict <|> lookup "Filter" dict))]
      when (any (`elem` ["RGB", "DeviceRGB"]) names) (Left RgbInlineImage)
      case find (`elem` ["LZW", "LZWDecode", "JBIG2Decode", "JPXDecode", "Crypt"]) filters of
        Just f -> Left (UnsupportedFilter (if f == "LZW" then "LZWDecode" else TE.decodeLatin1 f))
        Nothing -> Right ()
      Right (mapMaybe (\n -> lookup n [("G", UseGray), ("DeviceGray", UseGray), ("CMYK", UseCmyk), ("DeviceCMYK", UseCmyk)]) names)
    splice at = \case
      [] -> BS.drop at c
      (s, e, r) : rest -> BS.take (s - at) (BS.drop at c) <> r <> splice e rest
