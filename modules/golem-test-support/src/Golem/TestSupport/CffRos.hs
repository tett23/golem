{-# LANGUAGE MultiWayIf #-}

{- | A copy of a CID-keyed OpenType font with another ROS (docs/adr ADR
0232): the Registry and the Ordering are two strings added at the end of
the String INDEX of its CFF table, the Supplement a number, so that the
tests carry the ROS of a font through golem-font and golem-pdf without a
font of that ROS in the repository. Made in memory, never written to a
file.

The Top DICT is written again with every number as a 5-byte integer, and
the offsets in it and in the Private operators of the FDArray move by
what the Top DICT and the String INDEX grew. The tables of the font are
laid out again in their order, each on four bytes, with the length and
the checksum of the CFF table written again.
-}
module Golem.TestSupport.CffRos (withRos) where

import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.List (sortOn, uncons, unsnoc)
import Data.Maybe (fromMaybe)
import Data.Word (Word8)

-- | The font with the ROS; Nothing when it is not a CID-keyed CFF font this can read.
withRos :: ByteString -> ByteString -> Int -> ByteString -> Maybe ByteString
withRos registry ordering supplement font = do
  numTables <- be16 font 4
  records <- mapM (record font) [12 + 16 * k | k <- [0 .. numTables - 1]]
  (_, cffOff, cffLen) <- lookup3 "CFF " records
  cff' <- rewriteCff registry ordering supplement (slice cffOff cffLen font)
  let tables = [(tag, if tag == "CFF " then cff' else slice off len font) | (tag, off, len) <- records]
  pure (relayout (BS.take 12 font) tables)
  where
    lookup3 k xs = case [x | x@(t, _, _) <- xs, t == k] of
      x : _ -> Just x
      [] -> Nothing

slice :: Int -> Int -> ByteString -> ByteString
slice off len = BS.take len . BS.drop off

be16 :: ByteString -> Int -> Maybe Int
be16 b i
  | i + 2 <= BS.length b = Just (fromIntegral (BS.index b i) `shiftL` 8 .|. fromIntegral (BS.index b (i + 1)))
  | otherwise = Nothing

beN :: Int -> ByteString -> Int -> Maybe Int
beN n b i
  | i + n <= BS.length b = Just (BS.foldl' (\acc w -> acc `shiftL` 8 .|. fromIntegral w) 0 (slice i n b))
  | otherwise = Nothing

record :: ByteString -> Int -> Maybe (ByteString, Int, Int)
record font r = (,,) (slice r 4 font) <$> beN 4 font (r + 8) <*> beN 4 font (r + 12)

bytesBE :: Int -> Int -> ByteString
bytesBE n v = BS.pack [fromIntegral (v `shiftR` (8 * k)) | k <- [n - 1, n - 2 .. 0]]

-- | The sfnt with its tables in order, each padded to four bytes.
relayout :: ByteString -> [(ByteString, ByteString)] -> ByteString
relayout header tables =
  let n = length tables
      start = 12 + 16 * n
      padded t = t <> BS.replicate ((4 - BS.length t `mod` 4) `mod` 4) 0
      offsets = scanl (+) start (map (BS.length . padded . snd) tables)
      records = [tag <> bytesBE 4 (checksum t) <> bytesBE 4 off <> bytesBE 4 (BS.length t) | ((tag, t), off) <- sortOn (fst . fst) (zip tables offsets)]
   in BS.concat (header : records <> map (padded . snd) tables)

checksum :: ByteString -> Int
checksum t =
  let p = t <> BS.replicate ((4 - BS.length t `mod` 4) `mod` 4) 0
   in foldl' (\acc i -> (acc + fromMaybe 0 (beN 4 p i)) .&. 0xFFFFFFFF) 0 [0, 4 .. BS.length p - 4]

-- ------------------------------------------------------------------ CFF

-- | An INDEX at an offset: its items and where it ends.
index :: ByteString -> Int -> Maybe ([ByteString], Int)
index c p = do
  count <- be16 c p
  if count == 0
    then Just ([], p + 2)
    else do
      osz <- if p + 2 < BS.length c then Just (fromIntegral (BS.index c (p + 2))) else Nothing
      offs <- mapM (\k -> beN osz c (p + 3 + k * osz)) [0 .. count]
      let base = p + 3 + (count + 1) * osz - 1
      (_, lastOff) <- unsnoc offs
      Just ([slice (base + a) (b - a) c | (a, b) <- zip offs (drop 1 offs)], base + lastOff)

-- | An INDEX of items, with offsets of four bytes.
mkIndex :: [ByteString] -> ByteString
mkIndex items =
  let offs = scanl (+) 1 (map BS.length items)
   in bytesBE 2 (length items) <> BS.singleton 4 <> BS.concat (map (bytesBE 4) offs) <> BS.concat items

-- | An operand or an operator of a DICT: a number, or the bytes of an operator.
data Token = Num !Int | Real !ByteString | Op !ByteString

dictTokens :: ByteString -> Maybe [Token]
dictTokens b = case BS.uncons b of
  Nothing -> Just []
  Just (w, r)
    | w == 12 -> (\(o, rest) -> (Op (BS.pack [12, o]) :) <$> dictTokens rest) =<< BS.uncons r
    | w <= 21 -> (Op (BS.singleton w) :) <$> dictTokens r
    | w == 28 -> do v <- be16 r 0; (Num (signed 16 v) :) <$> dictTokens (BS.drop 2 r)
    | w == 29 -> do v <- beN 4 r 0; (Num (signed 32 v) :) <$> dictTokens (BS.drop 4 r)
    | w == 30 -> let (nibbles, rest) = realEnd r in (Real (BS.cons 30 nibbles) :) <$> dictTokens rest
    | w >= 32 && w <= 246 -> (Num (fromIntegral w - 139) :) <$> dictTokens r
    | w >= 247 && w <= 250 -> do (x, rest) <- BS.uncons r; (Num ((fromIntegral w - 247) * 256 + fromIntegral x + 108) :) <$> dictTokens rest
    | w >= 251 && w <= 254 -> do (x, rest) <- BS.uncons r; (Num (negate ((fromIntegral w - 251) * 256) - fromIntegral x - 108) :) <$> dictTokens rest
    | otherwise -> Nothing
  where
    signed bits v = if v >= 1 `shiftL` (bits - 1) then v - 1 `shiftL` bits else v
    -- a real number ends at the nibble f
    realEnd r = let k = maybe (BS.length r) (+ 1) (BS.findIndex (\x -> x .&. 0x0F == 0x0F || x .&. 0xF0 == 0xF0) r) in BS.splitAt k r

-- | A DICT, every integer in five bytes.
encode :: [Token] -> ByteString
encode = BS.concat . map one
  where
    one = \case
      Num v -> BS.cons 29 (bytesBE 4 (v .&. 0xFFFFFFFF))
      Real r -> r
      Op o -> o

-- | The operands and operator of each entry.
entries :: [Token] -> [([Token], ByteString)]
entries = go []
  where
    go acc = \case
      [] -> []
      Op o : rest -> (reverse acc, o) : go [] rest
      t : rest -> go (t : acc) rest

unentries :: [([Token], ByteString)] -> [Token]
unentries es = concat [ops <> [Op o] | (ops, o) <- es]

-- the operators whose last operand is an offset from the start of the CFF data
offsetOps :: [ByteString]
offsetOps = [BS.singleton 15, BS.singleton 16, BS.singleton 17, BS.singleton 18, BS.pack [12, 36], BS.pack [12, 37]]

rosOp, fdArrayOp :: ByteString
rosOp = BS.pack [12, 30]
fdArrayOp = BS.pack [12, 36]

rewriteCff :: ByteString -> ByteString -> Int -> ByteString -> Maybe ByteString
rewriteCff registry ordering supplement c = do
  hdrSize <- fromIntegral . fst <$> BS.uncons (BS.drop 2 c)
  (_, nameEnd) <- index c hdrSize
  (tops, topEnd) <- index c nameEnd
  top <- case tops of
    [t] -> Just t
    _ -> Nothing
  (strings, strEnd) <- index c topEnd
  topEntries <- entries <$> dictTokens top
  if rosOp `notElem` map snd topEntries then Nothing else Just ()
  let sid0 = 391 + length strings
      strings' = strings <> [registry, ordering]
      newStrIndex = mkIndex strings'
      -- the Top DICT with the new ROS and the offsets moved by d
      topWith d =
        encode
          ( unentries
              [ if
                  | o == rosOp -> ([Num sid0, Num (sid0 + 1), Num supplement], o)
                  | o `elem` offsetOps, Just (before, Num v) <- unsnoc ops -> (before <> [Num (v + d)], o)
                  | otherwise -> (ops, o)
              | (ops, o) <- topEntries
              ]
          )
      -- every integer is five bytes, so the size of the Top DICT does not depend on delta
      newTopIndexLen = BS.length (mkIndex [topWith 0])
      delta = (nameEnd + newTopIndexLen + BS.length newStrIndex) - strEnd
      rest = BS.drop strEnd c
  rest' <- case lookup fdArrayOp [(o, ops) | (ops, o) <- topEntries] of
    Just ops | Just (_, Num fdOff) <- unsnoc ops -> fixFdArray delta (fdOff - strEnd) rest
    _ -> Just rest
  Just (BS.take nameEnd c <> mkIndex [topWith delta] <> newStrIndex <> rest')

{- | The FDArray in the bytes after the String INDEX, at its offset in
them, with the offset of each Private moved; only when that offset is a
five-byte integer, so that nothing changes size.
-}
fixFdArray :: Int -> Int -> ByteString -> Maybe ByteString
fixFdArray delta at rest = do
  count <- be16 rest at
  (w, _) <- BS.uncons (BS.drop (at + 2) rest)
  let osz = fromIntegral w
  offs <- mapM (\k -> beN osz rest (at + 3 + k * osz)) [0 .. count]
  let base = at + 3 + (count + 1) * osz - 1
  dicts <- mapM (\(a, b) -> fixPrivate (slice (base + a) (b - a) rest)) (zip offs (drop 1 offs))
  (firstOff, _) <- uncons offs
  (_, lastOff) <- unsnoc offs
  let start = base + firstOff
      end = base + lastOff
  Just (BS.take start rest <> BS.concat dicts <> BS.drop end rest)
  where
    fixPrivate d = do
      i <- privateAt d
      v <- beN 4 d (i + 1)
      Just (BS.take (i + 1) d <> bytesBE 4 ((v + delta) .&. 0xFFFFFFFF) <> BS.drop (i + 5) d)
    -- the byte 29 of the five-byte integer just before the operator 18
    privateAt d = case [k - 5 | k <- [5 .. BS.length d - 1], BS.index d k == (18 :: Word8), BS.index d (k - 5) == 29] of
      k : _ -> Just k
      [] -> Nothing
