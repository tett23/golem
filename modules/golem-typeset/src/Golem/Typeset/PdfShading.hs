{- | The colours of the functions of PDF shadings, and their recolouring
(root ADR 0425). Functions arrive resolved: every reference replaced and a
sampled function's table decoded.
-}
module Golem.Typeset.PdfShading
  ( Fn (..),
    Gray (..),
    readFunction,
    fnOutputs,
    fnValues,
    fnPositions,
    fnDefinition,
    fnShape,
    fnWithin,
    mapFunction,
    solidFunction,
    numberObject,
  )
where

import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (transpose)
import Data.Ratio (denominator, numerator, (%))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Pdf qualified as P

type Obj = P.ObjOf P.ObjNum

-- | A function of ISO 32000-2 7.10, with the values Golem reads.
data Fn
  = -- | Sampled: its fields, the decoded table, the samples of each output.
    Fn0 ![(Text, Obj)] !ByteString !Int ![(Rational, Rational)] ![(Rational, Rational)] ![[Integer]]
  | -- | Exponential: fields, C0, C1, Domain, N, Range.
    Fn2 ![(Text, Obj)] ![Rational] ![Rational] !(Rational, Rational) !Rational !(Maybe [(Rational, Rational)])
  | -- | Stitching: fields, the functions, Range.
    Fn3 ![(Text, Obj)] ![Fn] !(Maybe [(Rational, Rational)])
  | -- | PostScript calculator.
    Fn4
  deriving stock (Eq, Show)

-- | How a value v of one output gives the gray value: g = alpha v + beta.
data Gray = Gray {grayOutput :: !Int, grayAlpha :: !Rational, grayBeta :: !Rational}
  deriving stock (Eq, Show)

-- | Read a resolved function; a sampled one needs its decoded table.
readFunction :: (Obj -> Either Text ByteString) -> Obj -> Either Text Fn
readFunction table value = do
  fields <- case value of
    P.ODict entries -> Right entries
    P.OStream entries _ -> Right entries
    _ -> Left invalid
  kind <- maybe (Left invalid) Right (lookup "FunctionType" fields)
  domain <- pairs =<< maybe (Left invalid) Right (lookup "Domain" fields)
  range <- traverse pairs (lookup "Range" fields)
  case kind of
    P.OInt 0 -> do
      ranges <- maybe (Left invalid) Right range
      sizes <- traverse integer =<< array =<< maybe (Left invalid) Right (lookup "Size" fields)
      bits <- integer =<< maybe (Left invalid) Right (lookup "BitsPerSample" fields)
      decode <- maybe (Right ranges) pairs (lookup "Decode" fields)
      if bits `elem` [1, 2, 4, 8, 12, 16, 24, 32] && all (> 0) sizes && length sizes == length domain && length decode == length ranges && product sizes <= 1048576 then Right () else Left invalid
      bytes <- table value
      let outputs = length ranges
          count = fromInteger (product sizes) * outputs
      -- The table must hold every sample before any is read.
      if toInteger count * bits > 8 * toInteger (BS.length bytes) then Left "PDF 図版のシェーディングの関数の標本が足りません" else Right ()
      let samples = unpackBits (fromInteger bits) count bytes
      if length samples < count then Left "PDF 図版のシェーディングの関数の標本が足りません" else Right ()
      Right (Fn0 fields bytes (fromInteger bits) decode ranges (transpose (chunks outputs (take count samples))))
    P.OInt 2 -> do
      c0 <- maybe (Right [0]) (traverse number <=< array) (lookup "C0" fields)
      c1 <- maybe (Right [1]) (traverse number <=< array) (lookup "C1" fields)
      n <- number =<< maybe (Left invalid) Right (lookup "N" fields)
      d <- case domain of [one] -> Right one; _ -> Left invalid
      if length c0 == length c1 && maybe True ((== length c0) . length) range then Right () else Left invalid
      Right (Fn2 fields c0 c1 d n range)
    P.OInt 3 -> do
      functions <- traverse (readFunction table) =<< array =<< maybe (Left invalid) Right (lookup "Functions" fields)
      case map fnOutputs functions of
        first : rest | all (== first) rest, maybe True ((== first) . length) range -> Right (Fn3 fields functions range)
        _ -> Left invalid
    P.OInt 4 -> Right Fn4
    _ -> Left invalid
  where
    invalid = "PDF 図版のシェーディングの関数を読めません"
    f <=< g = \x -> g x >>= f
    array = \case
      P.OArr values -> Right values
      _ -> Left invalid
    integer = \case
      P.OInt n -> Right n
      _ -> Left invalid
    number = \case
      P.OInt n -> Right (fromInteger n)
      P.OReal text -> maybe (Left invalid) Right (decimal (TE.encodeUtf8 text))
      _ -> Left invalid
    pairs v = do
      values <- traverse number =<< array v
      let go (a : b : rest) = (a, b) : go rest
          go _ = []
      if even (length values) then Right (go values) else Left invalid

fnOutputs :: Fn -> Int
fnOutputs = \case
  Fn0 _ _ _ _ ranges _ -> length ranges
  Fn2 _ c0 _ _ _ _ -> length c0
  Fn3 _ (f : _) _ -> fnOutputs f
  _ -> 0

{- | The values of one output: decoded samples, C0 and C1, or those of the
stitched functions.
-}
fnValues :: Fn -> Int -> [Rational]
fnValues fn output = map (!! output) (fnPositions fn)

-- | The colours of the definition: the values of all outputs at each position.
fnPositions :: Fn -> [[Rational]]
fnPositions = \case
  Fn0 _ _ bits decode _ samples ->
    let top = 2 ^ bits - 1
     in transpose [[d0 + fromInteger s * (d1 - d0) / top | s <- column] | ((d0, d1), column) <- zip decode samples]
  Fn2 _ c0 c1 _ _ _ -> [c0, c1]
  Fn3 _ functions _ -> concatMap fnPositions functions
  Fn4 -> []

{- | The definition of one output, comparable between outputs and between
the functions of an array: the kind, Domain, Range, N, Size, Order, Encode,
Decode, Bounds and values.
-}
fnDefinition :: Fn -> Int -> Text
fnDefinition fn output = case fn of
  Fn0 fields _ bits decode ranges samples -> T.pack (show ("0" :: Text, common fields, bits, decode !! output, ranges !! output, samples !! output))
  Fn2 fields c0 c1 domain n range -> T.pack (show ("2" :: Text, common fields, c0 !! output, c1 !! output, domain, n, fmap (!! output) range))
  Fn3 fields functions range -> T.pack (show ("3" :: Text, common fields, map (`fnDefinition` output) functions, fmap (!! output) range))
  Fn4 -> "4"
  where
    common fields = [(k, v) | (k, v) <- fields, k `elem` ["Domain", "Size", "Order", "Encode", "Bounds"]]

{- | The definition of one output without its values: whether the functions
of an array line up position by position.
-}
fnShape :: Fn -> Int -> Text
fnShape fn output = case fn of
  Fn0 fields _ bits decode ranges samples -> T.pack (show ("0" :: Text, common fields, bits, decode !! output, ranges !! output, length (samples !! output)))
  Fn2 fields _ _ domain n range -> T.pack (show ("2" :: Text, common fields, domain, n, fmap (!! output) range))
  Fn3 fields functions range -> T.pack (show ("3" :: Text, common fields, map (`fnShape` output) functions, fmap (!! output) range))
  Fn4 -> "4"
  where
    common fields = [(k, v) | (k, v) <- fields, k `elem` ["Domain", "Size", "Order", "Encode", "Bounds"]]

{- | Whether every value and Range of the outputs lie within the colour
space's ranges, and an exponential function without Range cannot
extrapolate.
-}
fnWithin :: [(Rational, Rational)] -> Fn -> Bool
fnWithin spaceRanges fn =
  all (\position -> and (zipWith inside spaceRanges position)) (fnPositions fn) && rangesWithin fn
  where
    inside (low, high) value = low <= value && value <= high
    contained ranges = and (zipWith (\(low, high) (a, b) -> low <= a && b <= high) spaceRanges ranges)
    rangesWithin = \case
      Fn0 _ _ _ _ ranges _ -> contained ranges
      Fn2 _ _ _ (d0, d1) n range -> maybe (0 <= d0 && d1 <= 1 && n > 0) contained range
      Fn3 _ functions range -> maybe True contained range && all rangesWithin functions
      Fn4 -> False

{- | The function whose outputs are the maps of the output of the gray value:
output k gives @a_k v + b_k@ for each map (a_k, b_k).
-}
mapFunction :: Int -> [(Rational, Rational)] -> Fn -> Obj
mapFunction output maps fn = case fn of
  Fn0 fields _ bits decode ranges samples ->
    let column = samples !! output
        (d0, d1) = decode !! output
        bytes = packBits bits (concatMap (replicate (length maps)) column)
        rangeOut = concat [sorted (apply m a) (apply m b) | m <- maps, let (a, b) = ranges !! output]
        decodeOut = concat [[apply m d0, apply m d1] | m <- maps]
     in P.OStream (replaceAll fields [("Range", nums rangeOut), ("Decode", nums decodeOut)] ["Length", "Filter", "DecodeParms", "DL"]) bytes
  Fn2 fields c0 c1 _ _ range ->
    P.ODict (replaceAll fields ([("C0", nums [apply m (c0 !! output) | m <- maps]), ("C1", nums [apply m (c1 !! output) | m <- maps])] <> [("Range", nums (concat [sorted (apply m a) (apply m b) | m <- maps])) | Just ranges <- [range], let (a, b) = ranges !! output]) [])
  Fn3 fields functions range ->
    P.ODict (replaceAll fields ([("Functions", P.OArr (map (mapFunction output maps) functions))] <> [("Range", nums (concat [sorted (apply m a) (apply m b) | m <- maps])) | Just ranges <- [range], let (a, b) = ranges !! output]) [])
  Fn4 -> P.ONull
  where
    apply (a, b) v = a * v + b
    sorted x y = [min x y, max x y]

-- | An exponential function whose every output is the given colour.
solidFunction :: (Rational, Rational) -> [Rational] -> Obj
solidFunction (d0, d1) colour = P.ODict [("FunctionType", P.OInt 2), ("Domain", nums [d0, d1]), ("C0", nums colour), ("C1", nums colour), ("N", P.OInt 1)]

replaceAll :: [(Text, Obj)] -> [(Text, Obj)] -> [Text] -> [(Text, Obj)]
replaceAll fields replacements dropped =
  [(k, v) | (k, v) <- fields, k `notElem` map fst replacements, k `notElem` dropped] <> replacements

nums :: [Rational] -> Obj
nums = P.OArr . map numberObject

{- | A number written exactly when its decimal terminates; otherwise to
twelve fractional digits.
-}
numberObject :: Rational -> Obj
numberObject r
  | denominator r == 1 = P.OInt (numerator r)
  | terminates (denominator r) = P.OReal (T.pack (exact r))
  | otherwise = P.OReal (P.showRationalDigits 12 r)
  where
    terminates d
      | d `mod` 2 == 0 = terminates (d `div` 2)
      | d `mod` 5 == 0 = terminates (d `div` 5)
      | otherwise = d == 1
    exact value =
      let sign = if value < 0 then "-" else ""
          a = abs value
          whole = floor a :: Integer
       in sign <> show whole <> "." <> digits (a - fromInteger whole)
    digits f
      | f == 0 = ""
      | otherwise = let d = floor (f * 10) :: Integer in show d <> digits (f * 10 - fromInteger d)

chunks :: Int -> [a] -> [[a]]
chunks n xs
  | n <= 0 = []
  | null xs = []
  | otherwise = take n xs : chunks n (drop n xs)

-- | Big-endian samples of the given width, without padding between them.
unpackBits :: Int -> Int -> ByteString -> [Integer]
unpackBits bits count bytes = [sample i | i <- [0 .. count - 1], (i + 1) * bits <= BS.length bytes * 8]
  where
    sample i = foldl (\acc bit -> acc `shiftL` 1 .|. bitAt (i * bits + bit)) 0 [0 .. bits - 1]
    bitAt position = toInteger ((BS.index bytes (position `div` 8) `shiftR` (7 - position `mod` 8)) .&. 1)

packBits :: Int -> [Integer] -> ByteString
packBits bits samples =
  let stream = concatMap (\s -> [(s `shiftR` (bits - 1 - b)) .&. 1 | b <- [0 .. bits - 1]]) samples
      bytesOf [] = []
      bytesOf xs = let (byte, rest) = splitAt 8 xs in fromInteger (foldl (\acc b -> acc * 2 + b) 0 (take 8 (byte <> repeat 0))) : bytesOf rest
   in BS.pack (bytesOf stream)

decimal :: ByteString -> Maybe Rational
decimal bytes =
  let (sign, body) = case BC.uncons bytes of
        Just ('-', rest) -> (-1, rest)
        Just ('+', rest) -> (1, rest)
        _ -> (1, bytes)
      (whole, fraction) = BC.break (== '.') body
      tailDigits = BS.drop 1 fraction
   in if BS.length body > 40 || BS.null whole && BS.null tailDigits || not (BC.all (`elem` ['0' .. '9']) whole && BC.all (`elem` ['0' .. '9']) tailDigits)
        then Nothing
        else do
          a <- if BS.null whole then Just 0 else fst <$> BC.readInteger whole
          b <- if BS.null tailDigits then Just 0 else fst <$> BC.readInteger tailDigits
          Just (sign * (fromInteger a + b % (10 ^ BS.length tailDigits)))
