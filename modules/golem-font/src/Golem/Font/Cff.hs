{- | The references of a CFF table, checked against the declared length of
the table before the font is embedded in a PDF (Golem ADR 0357).

The check reads the table as the CFF specification (Adobe Technical Note
5176) and the Type 2 CharString format (Technical Note 5177) lay it out:
the INDEXes of the header (Name, Top DICT, String, Global Subrs), the data
the Top DICT points at (CharStrings, charset, Encoding, Private DICT and its
Subrs, FDArray, FDSelect and the Private DICT of every Font DICT), and, for
the glyphs used, the CharString and every subroutine it calls. It runs the
CharStrings far enough to know the subroutine numbers: the operand stack,
the arithmetic operators, the stem hints that set the length of hintmask.

A reference that ends past the table, or a subroutine, glyph or Font DICT
number past its INDEX, makes the table 'CffOutOfTable'. A table malformed in
another way (an unknown operator, a stack underflow, an offSize of 5) stops
the check of that part without that verdict: such a table reads nothing
outside itself through what was checked, and G08107 reports only a reference
out of the table (Golem ADR 0357). The check is pure, so the same table and
glyphs give the same answer on every build.
-}
module Golem.Font.Cff
  ( CffCheck (..),
    sfntCffTable,
    checkCffTable,
    checkCffReferences,
  )
where

import Control.Monad (foldM, unless, when)
import Data.Bits (shiftL, testBit, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set

-- | Whether the used references of a CFF table stay inside it.
data CffCheck
  = -- | every reference that was checked ends within the table
    CffInTable
  | -- | a used reference ends past the table, or names an entry past its INDEX
    CffOutOfTable
  deriving stock (Eq, Show)

-- | Why a part of the check stopped.
data Stop
  = -- | a reference out of the table: the verdict of the whole check
    OutOfTable
  | -- | malformed in another way: the part is not followed further
    Malformed
  deriving stock (Eq, Show)

type Check = Either Stop

{- | The CFF table of an OpenType font, or of the first font of a collection
(the face golem-font opens), as long as its table record declares; Nothing
when there is none.
-}
sfntCffTable :: ByteString -> Maybe ByteString
sfntCffTable file = do
  start <- if BS.take 4 file == "ttcf" then u32 file 12 else Just 0
  numTables <- u16 file (start + 4)
  let records = [start + 12 + 16 * k | k <- [0 .. numTables - 1]]
  r <- case [r | r <- records, BS.take 4 (BS.drop r file) == "CFF "] of
    r : _ -> Just r
    [] -> Nothing
  off <- u32 file (r + 8)
  len <- u32 file (r + 12)
  Just (BS.take len (BS.drop off file))

{- | 'checkCffTable' on the CFF table of the font file; a font without one
is left to the checks that report it (G08003, G08018).
-}
checkCffReferences :: ByteString -> [Int] -> CffCheck
checkCffReferences file gids = maybe CffInTable (`checkCffTable` gids) (sfntCffTable file)

-- | Checks the references of a bare CFF table for the glyphs.
checkCffTable :: ByteString -> [Int] -> CffCheck
checkCffTable t gids = case structure t >>= \font -> mapM_ (glyph t font) (Set.toList (Set.fromList gids)) of
  Left OutOfTable -> CffOutOfTable
  _ -> CffInTable

-- ------------------------------------------------------------------ reading

-- | Unsigned big-endian integers of n bytes at an offset, Nothing past the bytes.
uI :: Int -> ByteString -> Int -> Maybe Integer
uI n b o
  | o < 0 || o + n > BS.length b = Nothing
  | otherwise = Just (BS.foldl' (\a w -> a `shiftL` 8 .|. fromIntegral w) 0 (BS.take n (BS.drop o b)))

-- | 'uI' as an Int, clamped by 'clamp'.
uN :: Int -> ByteString -> Int -> Maybe Int
uN n b o = clamp <$> uI n b o

-- | A signed 32-bit integer of four bytes.
signed32 :: Integer -> Integer
signed32 v = if v >= 0x80000000 then v - 0x100000000 else v

{- | A number of the table as an Int within ±2^29. A larger offset or length
lies past any table Golem reads either way, and the sums of a few such
numbers stay within the 32-bit Int of wasm32, so the check gives the same
answer there as on 64-bit processors.
-}
clamp :: Integer -> Int
clamp = fromInteger . max (negate limit) . min limit
  where
    limit = 2 ^ (29 :: Int)

-- | A number of a CharString run as an Int, within the same bounds; NaN is the lower bound.
toInt :: Double -> Int
toInt v = truncate (max (negate limit) (min limit v))
  where
    limit = 2 ^ (29 :: Int)

u16, u32 :: ByteString -> Int -> Maybe Int
u16 = uN 2
u32 = uN 4

-- | A read inside the table: past it is out of the table.
inTable :: Maybe a -> Check a
inTable = maybe (Left OutOfTable) Right

-- | A read inside a DICT or a CharString, which lie inside the table: past it is malformed.
inPart :: Maybe a -> Check a
inPart = maybe (Left Malformed) Right

-- | That the range [from, to) lies inside the table.
within :: ByteString -> Int -> Int -> Check ()
within t from to
  | from < 0 || to < from = Left Malformed
  | to > BS.length t = Left OutOfTable
  | otherwise = Right ()

-- ------------------------------------------------------------------ INDEX

-- | An INDEX: its count, the offset size, where its offsets start, and the byte before its data.
data Index = Index
  { ixCount :: !Int,
    ixOffSize :: !Int,
    ixOffsets :: !Int,
    ixBase :: !Int,
    ixEnd :: !Int
  }

-- | The INDEX at an offset; its offsets and its last offset must lie inside the table.
indexAt :: ByteString -> Int -> Check Index
indexAt t p = do
  count <- inTable (u16 t p)
  if count == 0
    then pure (Index 0 1 (p + 2) (p + 1) (p + 2))
    else do
      offSize <- inTable (uN 1 t (p + 2))
      unless (offSize >= 1 && offSize <= 4) (Left Malformed)
      let offsets = p + 3
          base = offsets + (count + 1) * offSize - 1
      lastOff <- inTable (uN offSize t (offsets + count * offSize))
      when (lastOff < 1) (Left Malformed)
      within t (base + 1) (base + lastOff)
      pure (Index count offSize offsets base (base + lastOff))

-- | Entry i of an INDEX: both of its ends inside the table; an entry past the count is out of the table.
entry :: ByteString -> Index -> Int -> Check ByteString
entry t ix i = do
  unless (i >= 0 && i < ixCount ix) (Left OutOfTable)
  let off k = inTable (uN (ixOffSize ix) t (ixOffsets ix + k * ixOffSize ix))
  s <- off i
  e <- off (i + 1)
  when (s < 1 || e < 1) (Left Malformed)
  when (ixBase ix + max s e > BS.length t) (Left OutOfTable)
  when (e < s) (Left Malformed)
  pure (BS.take (e - s) (BS.drop (ixBase ix + s) t))

-- ------------------------------------------------------------------ DICT

-- | A DICT as its operators (12 x as 1200 + x) and their integer operands; a real is Nothing.
dict :: ByteString -> Check (Map.Map Int [Maybe Int])
dict = go [] Map.empty
  where
    go acc m b = case BS.uncons b of
      Nothing -> pure m
      Just (b0, rest)
        | b0 == 12 -> do
            (b1, rest') <- inPart (BS.uncons rest)
            go [] (Map.insert (1200 + fromIntegral b1) (reverse acc) m) rest'
        | b0 <= 21 -> go [] (Map.insert (fromIntegral b0) (reverse acc) m) rest
        | b0 == 28 -> num 2 rest (\v -> if v >= 0x8000 then v - 0x10000 else v)
        | b0 == 29 -> do
            v <- inPart (uI 4 rest 0)
            go (Just (clamp (signed32 v)) : acc) m (BS.drop 4 rest)
        | b0 == 30 -> go (Nothing : acc) m (BS.drop 1 (BS.dropWhile (not . realEnd) rest))
        | b0 >= 32 && b0 <= 246 -> go (Just (fromIntegral b0 - 139) : acc) m rest
        | b0 >= 247 && b0 <= 254 -> do
            b1 <- inPart (fromIntegral <$> BS.indexMaybe rest 0)
            let v = if b0 <= 250 then (fromIntegral b0 - 247) * 256 + b1 + 108 else negate ((fromIntegral b0 - 251) * 256 + b1 + 108)
            go (Just v : acc) m (BS.drop 1 rest)
        | otherwise -> Left Malformed
      where
        num n rest f = do
          v <- inPart (uN n rest 0)
          go (Just (f v) : acc) m (BS.drop n rest)
    -- the byte whose nibbles hold the end (0xf) of a real
    realEnd w = w .&. 0x0f == 0x0f || w .&. 0xf0 == 0xf0

-- | The integer operands of an operator of a DICT, if it has them all.
ints :: Map.Map Int [Maybe Int] -> Int -> Maybe [Int]
ints d op = Map.lookup op d >>= sequence

-- ------------------------------------------------------------------ the font

-- | What the CharStrings of the used glyphs need: the INDEXes and the local subroutines of each glyph.
data Font = Font
  { fCharStrings :: !Index,
    fGlobals :: !Index,
    -- | the local subroutines of a glyph (Nothing: the Private DICT has no Subrs)
    fLocals :: Int -> Check (Maybe Index)
  }

-- | The header, the INDEXes after it and every DICT and the data they point at.
structure :: ByteString -> Check Font
structure t = do
  hdrSize <- inTable (uN 1 t 2)
  _ <- inTable (uN 1 t 3)
  when (hdrSize < 4) (Left Malformed)
  names <- indexAt t hdrSize
  tops <- indexAt t (ixEnd names)
  strings <- indexAt t (ixEnd tops)
  globals <- indexAt t (ixEnd strings)
  top <- entry t tops 0 >>= dict
  csOff <- inPart (ints top 17 >>= single)
  charStrings <- indexAt t csOff
  let nGlyphs = ixCount charStrings
      cid = Map.member 1230 top
  charset t nGlyphs (fromMaybe 0 (ints top 15 >>= single))
  unless cid (encoding t (fromMaybe 0 (ints top 16 >>= single)))
  if cid
    then do
      fdArrayOff <- inPart (ints top 1236 >>= single)
      fdSelectOff <- inPart (ints top 1237 >>= single)
      fdArray <- indexAt t fdArrayOff
      fdLocals <- mapM (\i -> entry t fdArray i >>= dict >>= private t) [0 .. ixCount fdArray - 1]
      select <- fdSelect t nGlyphs fdSelectOff
      let locals g = do
            fd <- select g
            unless (fd >= 0 && fd < length fdLocals) (Left OutOfTable)
            pure (fdLocals !! fd)
      pure (Font charStrings globals locals)
    else do
      locals <- private t top
      pure (Font charStrings globals (const (pure locals)))
  where
    single = \case
      [v] -> Just v
      _ -> Nothing

-- | The Private DICT a Top DICT or a Font DICT points at, and the INDEX of its Subrs.
private :: ByteString -> Map.Map Int [Maybe Int] -> Check (Maybe Index)
private t d = case ints d 18 of
  Nothing -> pure Nothing
  Just [size, off] -> do
    within t off (off + size)
    p <- dict (BS.take size (BS.drop off t))
    case ints p 19 of
      Just [subrs] -> Just <$> indexAt t (off + subrs)
      _ -> pure Nothing
  Just _ -> Left Malformed

-- | The charset of the font (0, 1 and 2 are the predefined ones).
charset :: ByteString -> Int -> Int -> Check ()
charset t nGlyphs off
  | off <= 2 = pure ()
  | otherwise =
      inTable (uN 1 t off) >>= \case
        0 -> within t (off + 1) (off + 1 + 2 * max 0 (nGlyphs - 1))
        1 -> ranges 1
        2 -> ranges 2
        _ -> Left Malformed
  where
    -- ranges of a first SID and a count of 1 or 2 bytes, until every glyph after .notdef is covered
    ranges n = go 1 (off + 1)
      where
        go covered p
          | covered >= nGlyphs = pure ()
          | otherwise = do
              left <- inTable (uN n t (p + 2))
              go (covered + left + 1) (p + 2 + n)

-- | The Encoding of a name-keyed font (0 and 1 are the predefined ones).
encoding :: ByteString -> Int -> Check ()
encoding t off
  | off <= 1 = pure ()
  | otherwise = do
      format <- inTable (uN 1 t off)
      n <- inTable (uN 1 t (off + 1))
      end <- case format .&. 0x7f of
        0 -> pure (off + 2 + n)
        1 -> pure (off + 2 + 2 * n)
        _ -> Left Malformed
      within t off end
      when (testBit format 7) $ do
        sups <- inTable (uN 1 t end)
        within t end (end + 1 + 3 * sups)

-- | The FDSelect: the Font DICT of a glyph, its data checked first.
fdSelect :: ByteString -> Int -> Int -> Check (Int -> Check Int)
fdSelect t nGlyphs off =
  inTable (uN 1 t off) >>= \case
    0 -> do
      within t (off + 1) (off + 1 + nGlyphs)
      pure (\g -> inTable (uN 1 t (off + 1 + g)))
    3 -> do
      n <- inTable (u16 t (off + 1))
      within t (off + 3) (off + 3 + 3 * n + 2)
      let firsts = [(f, fd) | k <- [0 .. n - 1], let r = off + 3 + 3 * k, Just f <- [u16 t r], Just fd <- [uN 1 t (r + 2)]]
      pure (\g -> inPart (lookupRange g firsts))
    _ -> Left Malformed
  where
    lookupRange g rs = case [fd | (f, fd) <- rs, f <= g] of
      [] -> Nothing
      fds -> Just (last fds)

-- ------------------------------------------------------------------ CharStrings

-- | The state of a Type 2 CharString run.
data Run = Run
  { rStack :: ![Double],
    rStems :: !Int,
    rTransient :: !(Map.Map Int Double),
    rSteps :: !Int
  }

-- | How a CharString or a subroutine ended.
data End = EndChar | Return | Fell

-- | The CharString of a glyph and the subroutines it calls.
glyph :: ByteString -> Font -> Int -> Check ()
glyph t font g = do
  cs <- entry t (fCharStrings font) g
  locals <- fLocals font g
  -- a malformed CharString is not followed further: only an out-of-table reference counts
  case run t font locals 0 cs (Run [] 0 Map.empty 0) of
    Left OutOfTable -> Left OutOfTable
    _ -> pure ()

-- | Runs a CharString, at a call depth (the limit of Type 2 is 10).
run :: ByteString -> Font -> Maybe Index -> Int -> ByteString -> Run -> Check (End, Run)
run t font locals depth = go
  where
    go b st
      | rSteps st > stepLimit = Left Malformed
      | otherwise = case BS.uncons b of
          Nothing -> pure (Fell, st)
          Just (b0, rest) -> step b0 rest st {rSteps = rSteps st + 1}
    push v rest st
      | length (rStack st) >= 48 = Left Malformed
      | otherwise = go rest st {rStack = v : rStack st}
    clear rest st = go rest st {rStack = []}
    step b0 rest st
      | b0 == 28 = do
          v <- inPart (u16 rest 0)
          push (fromIntegral (if v >= 0x8000 then v - 0x10000 else v)) (BS.drop 2 rest) st
      | b0 >= 32 && b0 <= 246 = push (fromIntegral b0 - 139) rest st
      | b0 >= 247 && b0 <= 254 = do
          b1 <- inPart (BS.indexMaybe rest 0)
          let v = if b0 <= 250 then (fromIntegral b0 - 247) * 256 + fromIntegral b1 + 108 else negate ((fromIntegral b0 - 251) * 256 + fromIntegral b1 + 108)
          push v (BS.drop 1 rest) st
      | b0 == 255 = do
          v <- inPart (uI 4 rest 0)
          push (fromInteger (signed32 v) / 65536) (BS.drop 4 rest) st
      | b0 `elem` [1, 3, 18, 23] = clear rest (stems st)
      | b0 == 19 || b0 == 20 = do
          let st' = stems st
              n = (rStems st' + 7) `div` 8
          when (BS.length rest < n) (Left Malformed)
          clear (BS.drop n rest) st'
      | b0 == 10 = call locals rest st
      | b0 == 29 = call (Just (fGlobals font)) rest st
      | b0 == 11 = pure (Return, st)
      | b0 == 14 = pure (EndChar, st)
      | b0 == 12 = do
          (b1, rest') <- inPart (BS.uncons rest)
          escape b1 rest' st
      | otherwise = clear rest st
    -- the stem hints, two operands each; an odd one is the width
    stems st = st {rStems = rStems st + length (rStack st) `div` 2, rStack = []}
    call subrs rest st = do
      (v, st') <- pop st
      ix <- maybe (Left OutOfTable) pure subrs
      let n = ixCount ix
          bias
            | n < 1240 = 107
            | n < 33900 = 1131
            | otherwise = 32768
      sub <- entry t ix (toInt v + bias)
      when (depth >= 10) (Left Malformed)
      (end, st'') <- run t font locals (depth + 1) sub st'
      case end of
        EndChar -> pure (EndChar, st'')
        _ -> go rest st''
    pop st = case rStack st of
      v : vs -> pure (v, st {rStack = vs})
      [] -> Left Malformed
    pops k st = foldM (\(vs, s) _ -> pop s >>= \(v, s') -> pure (v : vs, s')) ([], st) [1 .. k :: Int]
    -- the operands of an arithmetic operator, the first pushed first
    with k rest st f = do
      (vs, st') <- pops k st
      r <- f vs st'
      go rest r
    pushed vs st = if length vs + length (rStack st) > 48 then Left Malformed else pure st {rStack = reverse vs ++ rStack st}
    bool c = if c then 1 else 0
    un f rest st = with 1 rest st $ \case
      [a] -> f a
      _ -> const (Left Malformed)
    bin f rest st = with 2 rest st $ \case
      [a, b] -> f a b
      _ -> const (Left Malformed)
    escape b1 rest st = case b1 of
      3 -> bin (\a b -> pushed [bool (a /= 0 && b /= 0)]) rest st
      4 -> bin (\a b -> pushed [bool (a /= 0 || b /= 0)]) rest st
      5 -> un (\a -> pushed [bool (a == 0)]) rest st
      9 -> un (\a -> pushed [abs a]) rest st
      10 -> bin (\a b -> pushed [a + b]) rest st
      11 -> bin (\a b -> pushed [a - b]) rest st
      12 -> bin (\a b s -> if b == 0 then Left Malformed else pushed [a / b] s) rest st
      14 -> un (\a -> pushed [negate a]) rest st
      15 -> bin (\a b -> pushed [bool (a == b)]) rest st
      18 -> un (const pure) rest st
      20 -> bin (\v i s -> pure s {rTransient = Map.insert (toInt i) v (rTransient s)}) rest st
      21 -> un (\i s -> pushed [Map.findWithDefault 0 (toInt i) (rTransient s)] s) rest st
      22 -> with 4 rest st $ \case
        [s1, s2, v1, v2] -> pushed [if v1 <= v2 then s1 else s2]
        _ -> const (Left Malformed)
      24 -> bin (\a b -> pushed [a * b]) rest st
      26 -> un (\a s -> if a < 0 then Left Malformed else pushed [sqrt a] s) rest st
      27 -> un (\a -> pushed [a, a]) rest st
      28 -> bin (\a b -> pushed [b, a]) rest st
      29 -> do
        (i, st') <- pop st
        let k = toInt i
            vs = rStack st'
        v <- if k < 0 then inPart (safeHead vs) else inPart (safeAt k vs)
        go rest =<< pushed [v] st'
      30 -> do
        (j, st1) <- pop st
        (n, st2) <- pop st1
        let k = toInt n
        when (k < 0 || k > length (rStack st2)) (Left Malformed)
        let (top, below) = splitAt k (rStack st2)
            -- the stack holds the top first; roll moves values toward the top by j
            rolled = if k == 0 then top else let s = toInt j `mod` k in drop s top ++ take s top
        go rest st2 {rStack = rolled ++ below}
      -- random: a value the check cannot know, so the CharString is not followed
      23 -> Left Malformed
      _ -> clear rest st
    safeHead = \case
      v : _ -> Just v
      [] -> Nothing
    safeAt k vs = case drop k vs of
      v : _ -> Just v
      [] -> Nothing

-- | The operators a glyph may run, its subroutines included, before the check stops following it.
stepLimit :: Int
stepLimit = 100000
