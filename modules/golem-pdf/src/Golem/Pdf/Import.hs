{-# LANGUAGE MultiWayIf #-}

{- | Reading a page of a PDF so that it can be written as a Form XObject
(golem-pdf ADR 0008). Only what that needs is read: the cross-reference
(tables, streams, object streams, @/Prev@ and @/XRefStm@), objects, three
decoders (Flate with predictors, ASCIIHex, ASCII85) and the page tree.
A broken cross-reference is not repaired. DeviceRGB becomes the sRGB
ICCBased colour space; spot colours, layers, fonts not embedded and RGB
inline images are refused.

Reading is total and bounded (docs/adr ADR 0035, 0040): nesting,
references and the revisions are followed to fixed depths, every node of
the page tree and every revision at most once, every stream is decoded at
most once, and all that one import decodes is counted against
'maxDecodedBytes'.
-}
module Golem.Pdf.Import
  ( ImportedPage (..),
    ImportError (..),
    ColorUse (..),
    FigureContent (..),
    FormContent (..),
    importPage,
    importErrorText,
  )
where

import Codec.Compression.Zlib qualified as Z
import Control.Applicative ((<|>))
import Control.Monad (ap, foldM, guard, unless, when)
import Data.Bifunctor (first)
import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.ByteString.Builder.Extra qualified as BE
import Data.ByteString.Lazy qualified as BL
import Data.ByteString.Unsafe qualified as BU
import Data.Either (fromRight)
import Data.Foldable (asum)
import Data.List (find, nub)
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
import Golem.Pdf.Drawing (Drawing)
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

-- | What a figure placed in a PDF is (golem-pdf ADR 0008, 0009).
data FigureContent
  = RasterFigure !ImageData
  | VectorFigure !ImportedPage
  | SvgFigure !Drawing
  deriving stock (Eq, Show)

-- | What a Form XObject is: a page of a PDF figure, or the drawing of an SVG figure (ADR 0009).
data FormContent
  = ImportedForm !ImportedPage
  | DrawnForm !Drawing
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

{- | The most bytes one import may decode in all: 256 MiB (docs/adr ADR
0040). Every stage of every stream counts (Flate, the predictor after it,
ASCIIHex, ASCII85); a stream decoded again is not counted again.
-}
maxDecodedBytes :: Int
maxDecodedBytes = 256 * 1024 * 1024

{- | The most entries the cross-reference may have, all its revisions
together: the largest object number of ISO 32000-1 Annex C (docs/adr ADR
0040).
-}
maxXrefEntries :: Int
maxXrefEntries = 8388607

-- | The reason when decoding passes 'maxStreamBytes' or 'maxDecodedBytes' (docs/adr ADR 0040).
tooLarge :: Text
tooLarge = "展開した大きさが上限を超えました"

-- ------------------------------------------------------------------ reading with a budget

{- | What reading one file keeps (docs/adr ADR 0040): the bytes it may
still decode, the streams decoded, by object number, and the object
streams read, by object number, so that each is decoded once.
-}
data St = St
  { stLeft :: !Int,
    stDecoded :: !(Map Int ByteString),
    stObjStreams :: !(Map Int (Map Int V))
  }

-- | Reading that may fail, with 'St'.
newtype M a = M {runM :: St -> Either ImportError (a, St)}

instance Functor M where
  fmap f (M g) = M (fmap (first f) . g)

instance Applicative M where
  pure a = M (\s -> Right (a, s))
  (<*>) = ap

instance Monad M where
  M g >>= k = M (\s -> g s >>= \(a, s') -> runM (k a) s')

liftR :: R a -> M a
liftR r = M (\s -> (,s) <$> r)

badM :: Text -> M a
badM = liftR . bad

getsM :: (St -> a) -> M a
getsM f = M (\s -> Right (f s, s))

modifyM :: (St -> St) -> M ()
modifyM f = M (\s -> Right ((), f s))

-- | The most bytes the next stage of decoding may give.
budget :: M Int
budget = getsM (min maxStreamBytes . stLeft)

-- | Counts bytes decoded; the import ends when they pass the budget.
spend :: Int -> M ()
spend n = M (\s -> if n > stLeft s then Left (Malformed tooLarge) else Right ((), s {stLeft = stLeft s - n}))

{- | An action whose failure is given as a value, with the state as it was
before it; passing the budget is not given but ends the import.
-}
attempt :: M a -> M (Either ImportError a)
attempt (M g) = M $ \s -> case g s of
  Left e | e == Malformed tooLarge -> Left e
  Left e -> Right (Left e, s)
  Right (a, s') -> Right (Right a, s')

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
isDelim w = w == 40 || w == 41 || w == 60 || w == 62 || w == 91 || w == 93 || w == 123 || w == 125 || w == 47 || w == 37

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
                    -- the rest is dropped, not joined again, so that many escapes take linear time
                    let oct = BS.takeWhile (\x -> x >= 48 && x <= 55) (BS.take 3 r)
                        v = BS.foldl' (\a x -> a * 8 + fromIntegral (x - 48)) (0 :: Int) oct
                     in go depth (acc' <> B.word8 (fromIntegral (v `mod` 256))) (BS.drop (BS.length oct) r)
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

{- | One section of the cross-reference: a table, or a stream whose rows
are looked up where they are, so that a stream of many rows costs no more
than its bytes (docs/adr ADR 0040).
-}
data Section
  = TableSection !(Map Int Entry)
  | -- | the widths of the fields, the subsections by their first number (the number of entries and the row of the first), the rows
    StreamSection ![Int] !(Map Int (Int, Int)) !ByteString

-- | The entry of an object in one section.
sectionEntry :: Int -> Section -> Maybe Entry
sectionEntry n = \case
  TableSection m -> Map.lookup n m
  StreamSection ws subs rows -> do
    (start, (count, firstRow)) <- Map.lookupLE n subs
    let width = sum ws
        row = firstRow + n - start
    guard (n < start + count && width > 0 && (row + 1) * width <= BS.length rows)
    rowEntry ws (BS.take width (BS.drop (row * width) rows))

-- | The entry of a row of a cross-reference stream.
rowEntry :: [Int] -> ByteString -> Maybe Entry
rowEntry ws b =
  let field i =
        let w = ws !! i
            off = sum (take i ws)
         in BS.foldl' (\acc x -> acc `shiftL` 8 .|. fromIntegral x) (0 :: Int) (BS.take w (BS.drop off b))
      t = case ws of
        0 : _ -> 1
        _ -> field 0
   in case t of
        0 -> Just FreeEntry
        1 -> Just (InFile (field 1))
        2 -> Just (InStream (field 1))
        _ -> Nothing

-- | A PDF as read: its bytes and its cross-reference, the newest section first.
data Doc = Doc
  { docBytes :: !ByteString,
    docXref :: ![Section]
  }

-- | The object @n@, or null when the cross-reference does not have it.
fetch :: Doc -> Int -> M V
fetch d = fetchAt d 0

fetchAt :: Doc -> Int -> Int -> M V
fetchAt d depth n = case asum (map (sectionEntry n) (docXref d)) of
  Just (InFile off) -> objectAt d depth (Just n) off
  Just (InStream s) -> Map.findWithDefault VNull n <$> objectStream d depth s
  _ -> pure VNull

-- | A value with a reference followed.
resolve :: Doc -> V -> M V
resolve d = \case
  VRef n -> fetch d n
  v -> pure v

{- | The indirect object at an offset: @n g obj@, its value and, for a
stream, its data. With @Just n@ the number must be @n@.
-}
objectAt :: Doc -> Int -> Maybe Int -> Int -> M V
objectAt d depth want off = do
  let bytes = docBytes d
      where' = "オブジェクト " <> maybe (tshow off) tshow want
  when (off < 0 || off >= BS.length bytes) (badM where')
  r <- attempt $ do
    (num, v, s5) <- liftR $ do
      (num, s1) <- uint (BS.drop off bytes)
      (_, s2) <- uint s1
      s3 <- keyword "obj" s2
      when (maybe False (/= num) want) (bad where')
      (v, s4) <- parseObj 0 s3
      Right (num, v, skipWs s4)
    if "stream" `BS.isPrefixOf` s5
      then case v of
        VDict dict -> do
          when (isJust (lookup "F" dict)) (badM "外部のファイルのストリーム")
          let s6 = dropEol (BS.drop 6 s5)
          len <- streamLength d depth num dict
          when (len > BS.length s6) (badM "ストリームの長さ")
          let (body, after) = BS.splitAt len s6
          unless ("endstream" `BS.isPrefixOf` skipWs after) (badM "ストリームの長さ")
          pure (VStream dict body)
        _ -> badM where'
      else pure v
  either (const (badM where')) pure r
  where
    dropEol t
      | "\r\n" `BS.isPrefixOf` t = BS.drop 2 t
      | "\n" `BS.isPrefixOf` t || "\r" `BS.isPrefixOf` t = BS.drop 1 t
      | otherwise = t

-- | The Length of a stream, which may be an indirect object.
streamLength :: Doc -> Int -> Int -> Dict -> M Int
streamLength d depth self dict = case lookup "Length" dict of
  Just (VInt l) | l >= 0 && l <= fromIntegral maxStreamBytes * 4 -> pure (fromInteger l)
  Just (VRef m)
    | depth < 4 && m /= self ->
        fetchAt d (depth + 1) m >>= \case
          VInt l | l >= 0 && l <= fromIntegral maxStreamBytes * 4 -> pure (fromInteger l)
          _ -> badM "ストリームの長さ"
  _ -> badM "ストリームの長さ"

-- | The objects of an object stream, by number, read once (docs/adr ADR 0040).
objectStream :: Doc -> Int -> Int -> M (Map Int V)
objectStream d depth s =
  getsM (Map.lookup s . stObjStreams) >>= \case
    Just objs -> pure objs
    Nothing -> do
      objs <- readStream
      modifyM (\st -> st {stObjStreams = Map.insert s objs (stObjStreams st)})
      pure objs
  where
    readStream = case asum (map (sectionEntry s) (docXref d)) of
      Just (InFile off) ->
        objectAt d depth (Just s) off >>= \case
          VStream dict body -> do
            decoded <- decodeStream d dict body
            let int k = case lookup k dict of
                  Just (VInt x) | x >= 0 && x <= 10000000 -> Right (fromInteger x)
                  _ -> bad "オブジェクトのストリーム"
            liftR $ do
              n <- int "N"
              firstOff <- int "First"
              let header = BS.take firstOff decoded
              pairs <- readPairs n header
              Map.fromList <$> traverse (\(num, o) -> (num,) . fst <$> parseObj 0 (BS.drop (firstOff + o) decoded)) pairs
          _ -> badM "オブジェクトのストリーム"
      _ -> badM "オブジェクトのストリーム"
    readPairs :: Int -> ByteString -> R [(Int, Int)]
    readPairs 0 _ = Right []
    readPairs k t = do
      (a, t1) <- uint t
      (b, t2) <- uint t1
      ((a, b) :) <$> readPairs (k - 1) t2

-- ------------------------------------------------------------------ the cross-reference

{- | The cross-reference, the newest section first, and the trailer, from
the last @startxref@. A revision or an @/XRefStm@ already read is not read
again (docs/adr ADR 0040).
-}
readXref :: ByteString -> M ([Section], Dict)
readXref bytes = do
  let tailBytes = BS.drop (BS.length bytes - 2048) bytes
      (_, at) = lastOccurrence "startxref" tailBytes
  when (BS.null at) (badM "startxref")
  (off, _) <- liftR (either (const (bad "startxref")) Right (uint (BS.drop 9 at)))
  when (off >= BS.length bytes) (badM "startxref")
  chain Set.empty 0 0 off
  where
    len = BS.length bytes
    offset o = if o >= 0 && o < toInteger len then pure (fromInteger o) else badM "相互参照"
    counted t = if t > maxXrefEntries then badM "相互参照" else pure t
    chain seen depth total off
      | depth > maxRevisions || off < 0 || off >= len = badM "相互参照"
      | Set.member off seen = pure ([], [])
      | otherwise = do
          (sec, trailer, n) <- section total off
          total1 <- counted (total + n)
          let seen1 = Set.insert off seen
          (stm, seen2, total2) <- case lookup "XRefStm" trailer of
            Just (VInt o) -> do
              o' <- offset o
              if Set.member o' seen1
                then pure ([], seen1, total1)
                else do
                  (s, _, m) <- streamSection o'
                  t <- counted (total1 + m)
                  pure ([s], Set.insert o' seen1, t)
            _ -> pure ([], seen1, total1)
          (older, olderTrailer) <- case lookup "Prev" trailer of
            Just (VInt p) -> offset p >>= chain seen2 (depth + 1) total2
            _ -> pure ([], [])
          pure (sec : stm <> older, trailer <> [kv | kv@(k, _) <- olderTrailer, k `notElem` map fst trailer, k `notElem` ["Prev", "XRefStm"]])
    section total off =
      let s = skipWs (BS.drop off bytes)
       in if "xref" `BS.isPrefixOf` s then liftR (table total (BS.drop 4 s)) else streamSection off
    table total0 = go total0 0 Map.empty
      where
        go total n acc t0 =
          let t = skipWs t0
           in if "trailer" `BS.isPrefixOf` t
                then
                  parseObj 0 (BS.drop 7 t) >>= \case
                    (VDict dict, _) -> Right (TableSection acc, dict, n)
                    _ -> bad "トレーラー"
                else do
                  (start, t1) <- uint t
                  (count, t2) <- uint t1
                  when (count > BS.length t2 `div` 18 + 1 || total + count > maxXrefEntries) (bad "相互参照")
                  (acc', t3) <- entries start count acc t2
                  go (total + count) (n + count) acc' t3
        entries _ 0 acc t = Right (acc, t)
        entries n k acc t = do
          (o, t1) <- uint t
          (_, t2) <- uint t1
          case BS.uncons (skipWs t2) of
            Just (110, r) -> entries (n + 1) (k - 1 :: Int) (Map.insertWith (\_ old -> old) n (InFile o) acc) r
            Just (102, r) -> entries (n + 1) (k - 1) (Map.insertWith (\_ old -> old) n FreeEntry acc) r
            _ -> bad "相互参照"
    streamSection off = do
      let probe = Doc bytes []
      v <- objectAt probe 0 Nothing off
      case v of
        VStream dict body | lookup "Type" dict == Just (VName "XRef") -> do
          decoded <- decodeWith (filtersDirect dict) body
          liftR $ do
            ws <- case lookup "W" dict of
              Just (VArr xs) | length xs == 3, all smallInt xs -> Right [fromInteger i | VInt i <- xs]
              _ -> bad "相互参照"
            size <- case lookup "Size" dict of
              Just (VInt sz) | sz >= 0 && sz <= toInteger maxXrefEntries + 1 -> Right (fromInteger sz)
              _ -> bad "相互参照"
            index <- case lookup "Index" dict of
              Nothing -> Right [(0, size)]
              Just (VArr xs) | all isInt xs, even (length xs) -> Right (pairsOf [fromInteger i | VInt i <- xs])
              _ -> bad "相互参照"
            subs <- subsections index
            let width = sum ws
                rows = if width <= 0 then 0 else BS.length decoded `div` width
            Right (StreamSection ws subs decoded, dict, min rows (sum (map snd index)))
        _ -> badM "相互参照"
    smallInt = \case
      VInt i -> i >= 0 && i <= 8
      _ -> False
    isInt = \case
      VInt i -> i >= 0 && i <= 100000000
      _ -> False
    pairsOf = \case
      a : b : r -> (a, b) : pairsOf r
      _ -> []

{- | The subsections of a cross-reference stream by their first number,
each with the number of its entries and the row of its first. ISO
32000-1 7.5.8.2 has them sorted and not overlapping; others are refused.
-}
subsections :: [(Int, Int)] -> R (Map Int (Int, Int))
subsections = go 0 0 Map.empty
  where
    go _ _ acc [] = Right acc
    go row end acc ((start, count) : rest)
      | start < end = bad "相互参照"
      | count == 0 = go row end acc rest
      | otherwise = go (row + count) (start + count) (Map.insert start (count, row) acc) rest

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
filtersOf :: Doc -> Dict -> M [(ByteString, Dict)]
filtersOf d dict = do
  f <- maybe (pure VNull) (resolve d) (lookup "Filter" dict)
  p <- maybe (pure VNull) (resolve d) (lookup "DecodeParms" dict)
  names <- case f of
    VNull -> pure []
    VName n -> pure [n]
    VArr xs -> traverse (\x -> resolve d x >>= liftR . nameOf) xs
    _ -> badM "フィルター"
  parms <- case p of
    VDict pd -> pure [pd]
    VArr xs -> map dictOf <$> traverse (resolve d) xs
    _ -> pure []
  pure (zip names (parms <> repeat []))
  where
    nameOf = \case
      VName n -> Right n
      _ -> bad "フィルター"

decodeStream :: Doc -> Dict -> ByteString -> M ByteString
decodeStream d dict body = filtersOf d dict >>= \fs -> decodeWith fs body

-- | The data of the stream that is the object @k@, decoded once (docs/adr ADR 0040).
decodedObject :: Doc -> Int -> Dict -> ByteString -> M ByteString
decodedObject d k dict body =
  getsM (Map.lookup k . stDecoded) >>= \case
    Just out -> pure out
    Nothing -> do
      out <- decodeStream d dict body
      modifyM (\st -> st {stDecoded = Map.insert k out (stDecoded st)})
      pure out

-- | The filters Golem decodes (ADR 0008).
decodable :: [ByteString]
decodable = ["FlateDecode", "ASCIIHexDecode", "ASCII85Decode"]

-- | The filters copied as they are, in image streams only.
imageOnly :: [ByteString]
imageOnly = ["DCTDecode", "CCITTFaxDecode", "RunLengthDecode"]

{- | The filters applied in turn. What each stage gives is counted against
the budget, and no stage gives more than the budget has left (docs/adr ADR
0040).
-}
decodeWith :: [(ByteString, Dict)] -> ByteString -> M ByteString
decodeWith fs b0 = foldM step b0 fs
  where
    step b (name, parms) = case name of
      "FlateDecode" -> do
        inflated <- stage (\limit -> either (const (bad "Flate のストリーム")) Right (inflateUpTo (limit + 1) b))
        liftR (predict parms inflated) >>= maybe (pure inflated) (stage . const . Right)
      "ASCIIHexDecode" -> stage (asciiHex b)
      "ASCII85Decode" -> stage (ascii85 b)
      other -> liftR (Left (UnsupportedFilter (TE.decodeLatin1 other)))
    stage f = do
      limit <- budget
      out <- liftR (f limit)
      when (BS.length out > limit) (badM tooLarge)
      spend (BS.length out)
      pure out

{- | The predictor of Flate: none (Nothing), TIFF 2 (8 bits) or the PNG
filters. Colors is 1 to 32, BitsPerComponent 1, 2, 4, 8 or 16 and Columns
1 or more (docs/adr ADR 0040).
-}
predict :: Dict -> ByteString -> R (Maybe ByteString)
predict parms b
  | predictor == 1 = Right Nothing
  | otherwise = do
      colors <- param "Colors" 1 (\x -> x >= 1 && x <= 32)
      bpc <- param "BitsPerComponent" 8 (`elem` [1, 2, 4, 8, 16])
      columns <- param "Columns" 1 (>= 1)
      -- in Integer, and no longer than the data, so that it cannot overflow
      let rowBytes = fromInteger (min (toInteger (BS.length b) + 1) ((columns * colors * bpc + 7) `div` 8))
          bpp = fromInteger (max 1 ((colors * bpc) `div` 8))
      if
        | predictor == 2 && bpc == 8 -> Right (Just (BS.concat (map (tiffRow bpp) (chunks rowBytes b))))
        | predictor >= 10 ->
            let h = BS.length b `div` (rowBytes + 1)
             in either (const (bad "予測子")) (Right . Just) (unfilterPng bpp rowBytes h (BS.take (h * (rowBytes + 1)) b))
        | otherwise -> Left (UnsupportedFilter "FlateDecode")
  where
    predictor = case lookup "Predictor" parms of
      Just (VInt x) | x >= 0 && x <= 65536 -> x
      _ -> 1
    param k def ok = case lookup k parms of
      Nothing -> Right def
      Just (VInt x) | ok x -> Right (x :: Integer)
      _ -> bad "予測子"
    chunks n s = if n <= 0 || BS.null s then [] else BS.take n s : chunks n (BS.drop n s)

{- | A row of the TIFF predictor: each byte plus the decoded one a pixel
before it. The bytes of the last pixel are kept in a queue, so that a row
takes time in proportion to its length (docs/adr ADR 0040).
-}
tiffRow :: Int -> ByteString -> ByteString
tiffRow bpp = snd . BS.mapAccumL step (replicate bpp 0, [])
  where
    step (front, back) w = case front of
      old : front' -> let v = w + old in ((front', v : back), v)
      [] -> case reverse back of
        old : front' -> let v = w + old in ((front', [v]), v)
        [] -> ((front, back), w)

{- | ASCIIHex, giving at most @limit@ bytes: the digits are counted first,
up to where they pass the limit, and only then decoded.
-}
asciiHex :: ByteString -> Int -> R ByteString
asciiHex b limit = do
  digits <- count 0 0
  let n = (digits + 1) `div` 2
  if n > limit
    then bad tooLarge
    else Right (built n (decode 0 Nothing))
  where
    len = BS.length b
    at = BU.unsafeIndex b
    count !i !k
      | i >= len || at i == 62 = Right k
      | isWs (at i) = count (i + 1) k
      | isJust (hexVal (at i)) = if (k + 2) `div` 2 > limit then Right (k + 1) else count (i + 1) (k + 1)
      | otherwise = bad "ASCIIHex のストリーム"
    decode !i high
      | i >= len || at i == 62 = maybe mempty (\h -> B.word8 (h * 16)) high
      | otherwise = case hexVal (at i) of
          Nothing -> decode (i + 1) high
          Just x -> case high of
            Nothing -> decode (i + 1) (Just x)
            Just h -> B.word8 (h * 16 + x) <> decode (i + 1) Nothing

{- | ASCII85, giving at most @limit@ bytes: the stream is checked and its
size counted first, up to where it passes the limit, and only then
decoded.
-}
ascii85 :: ByteString -> Int -> R ByteString
ascii85 b limit = do
  n <- check start 0 0 0
  if n > limit
    then bad tooLarge
    else Right (built n (decode start 0 0))
  where
    len = BS.length b
    at = BU.unsafeIndex b
    skip !i = if i < len && isWs (at i) then skip (i + 1) else i
    start =
      let i = skip 0
       in if i + 1 < len && at i == 60 && at (i + 1) == 126 then i + 2 else i
    -- the end: the input ends, or ~> (white space may come between)
    atEnd i = i >= len || at i == 126
    endOk i = i >= len || (let j = skip (i + 1) in j < len && at j == 62)
    -- i: where reading is (white space skipped), k: the characters of the group so far, v: its value, n: the bytes so far
    check !i0 !k !v !n
      | n > limit = Right n
      | atEnd i =
          if not (endOk i)
            then bad "ASCII85 のストリーム"
            else
              if
                | k == 0 -> Right n
                | k == 1 || padded k v > 0xFFFFFFFF -> bad "ASCII85 のストリーム"
                | otherwise -> Right (n + k - 1)
      | w == 122 && k == 0 = check (i + 1) 0 0 (n + 4)
      | w >= 33 && w <= 117 =
          let v' = v * 85 + fromIntegral (w - 33)
           in if
                | k + 1 < 5 -> check (i + 1) (k + 1) v' n
                | v' > 0xFFFFFFFF -> bad "ASCII85 のストリーム"
                | otherwise -> check (i + 1) 0 0 (n + 4)
      | otherwise = bad "ASCII85 のストリーム"
      where
        i = skip i0
        w = at i
    padded :: Int -> Int -> Int
    padded k v = iterate (\x -> x * 85 + 84) v !! (5 - k)
    decode !i0 !k !v
      | atEnd i = if k == 0 then mempty else bytes (k - 1) (padded k v)
      | w == 122 = B.word32BE 0 <> decode (i + 1) 0 0
      | k + 1 < 5 = decode (i + 1) (k + 1) (v * 85 + fromIntegral (w - 33))
      | otherwise = bytes 4 (v * 85 + fromIntegral (w - 33)) <> decode (i + 1) 0 0
      where
        i = skip i0
        w = at i
    bytes m x = mconcat [B.word8 (fromIntegral ((x `shiftR` (8 * (3 - j))) .&. 0xFF)) | j <- [0 .. m - 1]]

-- | The bytes of a builder known to give @n@ bytes, written into one buffer of that size.
built :: Int -> B.Builder -> ByteString
built n bld
  | n <= 0 = BS.empty
  | otherwise = BL.toStrict (BE.toLazyByteStringWith (BE.untrimmedStrategy n BE.smallChunkSize) BL.empty bld)

-- ------------------------------------------------------------------ the page

-- | What a page inherits from the page tree.
data Inherited = Inherited
  { inResources :: !(Maybe V),
    inMediaBox :: !(Maybe V),
    inCropBox :: !(Maybe V),
    inRotate :: !(Maybe V)
  }

{- | The page @n@ (from 1) of the tree with what it inherits, or, when the
tree has fewer pages, their number. Every node is visited once: a node
named twice is refused, since a node has one Parent (ISO 32000-1 7.7.3).
The walk ends at the page (docs/adr ADR 0040).
-}
pageAt :: Doc -> Int -> V -> M (Either Int (Dict, Inherited))
pageAt d n root = either (Left . snd) Right <$> walk (Set.empty, 0) (0 :: Int) (Inherited Nothing Nothing Nothing Nothing) root
  where
    walk (seen, count) depth inh v
      | depth > 64 = badM "ページの木"
      | otherwise = do
          (key, node) <- case v of
            VRef k
              | Set.member k seen -> badM "ページの木"
              | otherwise -> (Just k,) <$> fetch d k
            _ -> pure (Nothing, v)
          dict <- case node of
            VDict x -> pure x
            _ -> badM "ページの木"
          let seen' = maybe seen (`Set.insert` seen) key
              pick k f = lookup k dict <|> f inh
              inh' = Inherited (pick "Resources" inResources) (pick "MediaBox" inMediaBox) (pick "CropBox" inCropBox) (pick "Rotate" inRotate)
              kids st = \case
                [] -> pure (Left st)
                k : ks -> walk st (depth + 1) inh' k >>= either (`kids` ks) (pure . Right)
          if lookup "Type" dict == Just (VName "Page")
            then pure (if count + 1 == n then Right (dict, inh') else Left (seen', count + 1))
            else case lookup "Kids" dict of
              Nothing -> pure (Left (seen', count))
              Just kv ->
                resolve d kv >>= \case
                  VArr xs -> kids (seen', count) xs
                  _ -> badM "ページの木"

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

boxOf :: Doc -> V -> M Box
boxOf d v =
  resolve d v >>= \case
    VArr xs | length xs == 4 -> do
      ns <- traverse (\x -> resolve d x >>= maybe (badM "ページの大きさ") pure . numberOf) xs
      case ns of
        [a, b, c, e] -> pure (min a c, min b e, max a c, max b e)
        _ -> badM "ページの大きさ"
    _ -> badM "ページの大きさ"

-- ------------------------------------------------------------------ importing

{- | The page @n@ (from 1) of a PDF, as a Form XObject can be written from
it (golem-pdf ADR 0008).
-}
importPage :: Int -> ByteString -> Either ImportError ImportedPage
importPage n bytes = fst <$> runM (importM n bytes) (St maxDecodedBytes Map.empty Map.empty)

importM :: Int -> ByteString -> M ImportedPage
importM n bytes = do
  liftR (checkHeader bytes)
  (xref, trailer) <- readXref bytes
  when (isJust (lookup "Encrypt" trailer)) (liftR (Left Encrypted))
  let doc = Doc bytes xref
  root <- maybe (badM "トレーラー") (resolve doc) (lookup "Root" trailer)
  pagesRoot <- maybe (badM "ページの木") pure (look "Pages" root)
  (page, inh) <- pageAt doc n pagesRoot >>= either (liftR . Left . NoSuchPage n) pure
  userUnit <- maybe (pure Nothing) (fmap numberOf . resolve doc) (lookup "UserUnit" page)
  when (maybe False (/= 1) userUnit) (liftR (Left UnsupportedUserUnit))
  media <- maybe (badM "ページの大きさ") (boxOf doc) (inMediaBox inh)
  crop <- maybe (pure media) (boxOf doc) (inCropBox inh)
  let (mx0, my0, mx1, my1) = media
      (cx0, cy0, cx1, cy1) = crop
      box@(x0, y0, x1, y1) = (max mx0 cx0, max my0 cy0, min mx1 cx1, min my1 cy1)
  when (x1 <= x0 || y1 <= y0) (badM "ページの大きさ")
  rotate <-
    maybe (pure (VInt 0)) (resolve doc) (inRotate inh) >>= \case
      VInt r | r `mod` 90 == 0 -> pure (fromInteger (r `mod` 360))
      _ -> badM "Rotate"
  resources <- maybe (pure (VDict [])) (resolve doc) (inResources inh)
  group <- traverse (resolve doc) (lookup "Group" page)
  content <- pageContent doc page
  -- the objects the resources and the group reach, each once
  objs <- collect doc (resources : maybe [] pure group)
  let roots = resources : maybe [] pure group
      values = roots <> [o | (_, o, _) <- objs]
  checkObjects doc objs values
  -- the content streams decoded, checked and with DeviceRGB replaced
  (pageBytes, pageChanged, pageUses) <- liftR (rewriteContent content)
  rewritten <-
    Map.fromList
      <$> traverse
        (\(k, o) -> case o of VStream dict body -> (k,) <$> (decodedObject doc k dict body >>= liftR . rewriteContent); _ -> badM "内容のストリーム")
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
  pure
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

{- | The content of a page: its streams decoded and joined by newlines. A
stream named more than once is decoded once, and the joined content may
be no larger than 'maxStreamBytes' (docs/adr ADR 0040).
-}
pageContent :: Doc -> Dict -> M ByteString
pageContent d page = case lookup "Contents" page of
  Nothing -> pure ""
  Just v ->
    resolve d v >>= \case
      VArr xs -> do
        parts <- traverse one xs
        when (sum (map BS.length parts) + length parts - 1 > maxStreamBytes) (badM tooLarge)
        pure (BS.intercalate "\n" parts)
      _ -> one v
  where
    one = \case
      VRef k ->
        fetch d k >>= \case
          VStream dict body -> decodedObject d k dict body
          VNull -> pure ""
          _ -> badM "内容のストリーム"
      VStream dict body -> decodeStream d dict body
      VNull -> pure ""
      _ -> badM "内容のストリーム"

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
collect :: Doc -> [V] -> M [(Int, V, Role)]
collect d roots = (\(_, acc) -> reverse acc) <$> foldM (go NoHint) (Set.empty, []) roots
  where
    go hint st@(seen, acc) = \case
      VRef k
        | k <= 0 || Set.member k seen -> pure st
        | otherwise -> do
            o <- fetch d k
            let seen' = Set.insert k seen
            if excluded o || o == VNull
              then pure (seen', acc)
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
      _ -> pure st
    entries hint st kv =
      foldM
        ( \s (k, v) ->
            if
              | k `elem` skipKeys -> pure s
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
checkObjects :: Doc -> [(Int, V, Role)] -> [V] -> M ()
checkObjects d objs values = do
  mapM_ filterOk objs
  mapM_ fontOk (concatMap dictsIn values)
  when (any (any isSpot . valuesIn) values) (liftR (Left SpotColor))
  when (any (any layer . dictsIn) values) (liftR (Left OptionalContent))
  where
    filterOk (_, o, role) = case o of
      VStream dict _ -> do
        names <- map fst <$> filtersOf d dict
        let image = lookup "Subtype" dict == Just (VName "Image")
            allowed = decodable <> (if role == Plain && image then imageOnly else [])
        maybe (pure ()) (liftR . Left . UnsupportedFilter . TE.decodeLatin1) (find (`notElem` allowed) names)
      _ -> pure ()
    fontOk kv
      | Just (VName st) <- lookup "Subtype" kv,
        st `elem` ["Type1", "MMType1", "TrueType", "CIDFontType0", "CIDFontType2"],
        maybe True (== VName "Font") (lookup "Type" kv) = do
          desc <- maybe (pure VNull) (resolve d) (lookup "FontDescriptor" kv)
          unless (any (\k -> isJust (look k desc)) ["FontFile", "FontFile2", "FontFile3"]) $
            liftR (Left (FontNotEmbedded (maybe "名前のないフォント" nameText' (lookup "BaseFont" kv))))
      | otherwise = pure ()
    nameText' = \case
      VName b -> TE.decodeLatin1 b
      _ -> "名前のないフォント"
    isSpot = \case
      VArr (VName s : _) -> s == "Separation" || s == "DeviceN"
      _ -> False
    layer kv = isJust (lookup "OC" kv) || lookup "Type" kv `elem` [Just (VName "OCG"), Just (VName "OCMD")]

hasDeviceRgb :: V -> Bool
hasDeviceRgb = elem (VName "DeviceRGB") . valuesIn

{- | The colour spaces of the objects (ADR 0008), in the order they are
found. A profile that cannot be decoded is taken as it is, but passing the
budget ends the import (docs/adr ADR 0040).
-}
objectUses :: Doc -> [V] -> M [ColorUse]
objectUses d values = concat <$> traverse use (concatMap valuesIn values)
  where
    use = \case
      VName "DeviceGray" -> pure [UseGray]
      VName "DeviceRGB" -> pure [UseRgb]
      VName "DeviceCMYK" -> pure [UseCmyk]
      VArr (VName "CalGray" : _) -> pure [UseGray]
      VArr (VName "CalRGB" : _) -> pure [UseRgb]
      VArr (VName "Lab" : _) -> pure [UseLab]
      VArr [VName "ICCBased", ref] ->
        resolve d ref >>= \case
          VStream dict body -> do
            let n = case lookup "N" dict of
                  Just (VInt i) -> fromInteger i
                  _ -> 0
            decoded <- attempt (case ref of VRef k -> decodedObject d k dict body; _ -> decodeStream d dict body)
            pure [UseIcc n (fromRight body decoded)]
          _ -> pure []
      _ -> pure []

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

{- | A content stream with DeviceRGB replaced (ADR 0008): @r g b rg@ as
@/GolemSRGB cs r g b sc@, @RG@ as @CS@ and @SC@, @/DeviceRGB cs@ as
@/GolemSRGB cs@. Also whether it changed and the colour spaces it uses;
an RGB inline image is refused.

The stream is read once, from the start, writing the output as it goes:
of the operands only the last three are kept, and what is not replaced is
copied as a slice of the input, so that a stream of many small tokens
takes memory in proportion to its length (docs/adr ADR 0040).
-}
rewriteContent :: ByteString -> R (ByteString, Bool, [ColorUse])
rewriteContent c = go 0 0 0 0 0 0 0 0 0 0 0 0 [] []
  where
    len = BS.length c
    at = BU.unsafeIndex c
    slice s e = BS.take (e - s) (BS.drop s c)
    -- the ends of a name or a keyword, a number and a comment
    regularEnd !i = if i < len && isRegular (at i) then regularEnd (i + 1) else i
    numberEnd !i = if i < len && isNumChar (at i) then numberEnd (i + 1) else i
    lineEnd !i = if i < len && at i /= 10 && at i /= 13 then lineEnd (i + 1) else i
    -- whether the bytes from s to e are the keyword
    is !s !e kw = e - s == BS.length kw && match 0
      where
        match !x = x >= BS.length kw || (at (s + x) == BU.unsafeIndex kw x && match (x + 1))
    addUse u us = if u `elem` us then us else us <> [u]
    {- i: where reading is; n: the operands since the last operator (4 for
    more than three); (k1, s1, e1): the kind (0 other, 1 number, 2 name),
    the start and the end of the last operand, (k2, s2, e2) of the one
    before, (k3, s3, e3) of the one before that; copied: how much of the
    input is in the output; out: the output so far, reversed; uses: the
    colour spaces, in the order they are first used. Every step is a call
    with these as arguments, so that a step allocates nothing.
    -}
    go :: Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> [ByteString] -> [ColorUse] -> R (ByteString, Bool, [ColorUse])
    go !i !n !k1 !s1 !e1 !k2 !s2 !e2 !k3 !s3 !e3 !copied !out !uses
      | i >= len =
          if null out
            then Right (c, False, uses)
            else Right (BS.concat (reverse (BS.drop copied c : out)), True, uses)
      | isWs (at i) = go (i + 1) n k1 s1 e1 k2 s2 e2 k3 s3 e3 copied out uses
      | at i == 37 = go (lineEnd i) n k1 s1 e1 k2 s2 e2 k3 s3 e3 copied out uses
      | at i == 47 = go (regularEnd (i + 1)) (min 4 (n + 1)) 2 i (regularEnd (i + 1)) k1 s1 e1 k2 s2 e2 copied out uses
      | at i == 40 || at i == 60 || at i == 91 = case parseObj 0 (BS.drop i c) of
          Left _ -> bad "内容のストリーム"
          Right (_, after) -> let j = len - BS.length after in go j (min 4 (n + 1)) 0 i j k1 s1 e1 k2 s2 e2 copied out uses
      | at i == 123 || at i == 125 = go (i + 1) (min 4 (n + 1)) 0 i (i + 1) k1 s1 e1 k2 s2 e2 copied out uses
      | isNumChar (at i) = go (numberEnd i) (min 4 (n + 1)) 1 i (numberEnd i) k1 s1 e1 k2 s2 e2 copied out uses
      | isRegular (at i) = keyword' i (regularEnd i) n k1 s1 e1 k2 s2 e2 k3 s3 e3 copied out uses
      | otherwise = bad "内容のストリーム"
    -- the keyword from i to j: an operator, or true, false and null as operands
    keyword' !i !j !n !k1 !s1 !e1 !k2 !s2 !e2 !k3 !s3 !e3 !copied !out !uses
      | is i j "BI" = do
          (dict, k) <- inlineImage j
          u <- inlineUses dict
          go k 0 0 0 0 0 0 0 0 0 0 copied out (foldl (flip addUse) uses (reverse u))
      | is i j "true" || is i j "false" || is i j "null" = go j (min 4 (n + 1)) 0 i j k1 s1 e1 k2 s2 e2 copied out uses
      | (is i j "rg" || is i j "RG") && n == 3 && k1 == 1 && k2 == 1 && k3 == 1 =
          let (space, set) = if is i j "rg" then ("cs", "sc") else ("CS", "SC")
              r = "/GolemSRGB " <> space <> " " <> slice s3 e3 <> " " <> slice s2 e2 <> " " <> slice s1 e1 <> " " <> set
           in next j (r : slice copied s3 : out) (addUse UseRgb uses)
      | (is i j "cs" || is i j "CS") && n == 1 && k1 == 2 = case unescapeName (slice (s1 + 1) e1) of
          "DeviceRGB" -> go j 0 0 0 0 0 0 0 0 0 0 e1 ("/GolemSRGB" : slice copied s1 : out) (addUse UseRgb uses)
          "DeviceGray" -> next copied out (addUse UseGray uses)
          "DeviceCMYK" -> next copied out (addUse UseCmyk uses)
          _ -> next copied out uses
      | is i j "g" || is i j "G" = next copied out (addUse UseGray uses)
      | is i j "k" || is i j "K" = next copied out (addUse UseCmyk uses)
      | otherwise = next copied out uses
      where
        next = go j 0 0 0 0 0 0 0 0 0 0
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
          let (_, found) = BS.breakSubstring "EI" (BS.drop from c)
              k = len - BS.length found
              before = if k > 0 then BS.index c (k - 1) else 32
              after = BS.drop (k + 2) c
           in if BS.null found
                then bad "内容のストリーム"
                else
                  if isWs before && maybe True (not . isRegular . fst) (BS.uncons after)
                    then Right (k + 2)
                    else findEi (k + 2)
    inlineUses dict = do
      let cs = fromMaybe VNull (lookup "CS" dict <|> lookup "ColorSpace" dict)
          names = [n | VName n <- valuesIn cs]
          filters = [n | VName n <- valuesIn (fromMaybe VNull (lookup "F" dict <|> lookup "Filter" dict))]
      when (any (`elem` ["RGB", "DeviceRGB"]) names) (Left RgbInlineImage)
      case find (`elem` ["LZW", "LZWDecode", "JBIG2Decode", "JPXDecode", "Crypt"]) filters of
        Just f -> Left (UnsupportedFilter (if f == "LZW" then "LZWDecode" else TE.decodeLatin1 f))
        Nothing -> Right ()
      Right (mapMaybe (\n -> lookup n [("G", UseGray), ("DeviceGray", UseGray), ("CMYK", UseCmyk), ("DeviceCMYK", UseCmyk)]) names)
