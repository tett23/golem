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
    CffResult (..),
    SeacError (..),
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
  | -- | the references of a glyph cannot all be checked (G08108, Golem ADR 0390)
    Unverifiable
  | -- | the seac of a glyph is wrong (G08114 to G08117, root ADR 0420)
    Seac !SeacError
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
checkCffReferences :: ByteString -> [Int] -> CffResult
checkCffReferences file gids = maybe (CffResult CffInTable [] [] []) (`checkCffTable` gids) (sfntCffTable file)

{- | The answer of the check of a CFF table for the glyphs used (Golem ADR
0390): whether a reference leaves the table (G08107, one for the font), the
glyphs whose references cannot all be checked (G08108), and the glyphs that
run random, in the order of their numbers.
-}
data CffResult = CffResult
  { cffCheck :: !CffCheck,
    cffUnverifiable :: ![Int],
    cffRandom :: ![Int],
    -- | the glyphs whose seac is wrong, and how (G08114 to G08117, root ADR 0420)
    cffSeac :: ![(Int, SeacError)]
  }
  deriving stock (Eq, Show)

-- | How the seac of a used glyph is wrong (root ADR 0420).
data SeacError
  = -- | G08114: other than 0 or 4 arguments besides the width, or a character code not an integer of 0 to 255
    SeacArguments
  | -- | G08115: no character of StandardEncoding at a code, or the charset has not its name
    SeacMissingComponent
  | -- | G08116: a component is a seac itself
    SeacNested
  | -- | G08117: a seac in a CID-keyed font
    SeacCidKeyed
  deriving stock (Eq, Show)

-- | Checks the references of a bare CFF table for the glyphs.
checkCffTable :: ByteString -> [Int] -> CffResult
checkCffTable t gids = case structure t of
  Left OutOfTable -> CffResult CffOutOfTable [] [] []
  Left _ -> CffResult CffInTable [] [] []
  Right font ->
    let checked = [(g, glyph t font g) | g <- Set.toList (Set.fromList gids)]
     in CffResult
          (if any ((== Just OutOfTable) . fst . snd) checked then CffOutOfTable else CffInTable)
          [g | (g, (Just Unverifiable, _)) <- checked]
          [g | (g, (_, True)) <- checked]
          [(g, e) | (g, (Just (Seac e), _)) <- checked]

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
    -- | whether the font is CID-keyed
    fCid :: !Bool,
    -- | the glyph of a SID by the charset (root ADR 0420)
    fGlyphOfSid :: Int -> Maybe Int,
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
      charsetOff = fromMaybe 0 (ints top 15 >>= single)
  charset t nGlyphs charsetOff
  let glyphOfSid = sidGlyph t nGlyphs charsetOff
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
      pure (Font charStrings globals cid glyphOfSid locals)
    else do
      locals <- private t top
      pure (Font charStrings globals cid glyphOfSid (const (pure locals)))
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

{- | The glyph of a SID by the charset at an offset, the first that has it
(root ADR 0420); the charset was checked by 'charset' first. The predefined
charsets are those of the CFF specification (Technical Note 5176,
Appendix C): ISOAdobe gives the glyph i the SID i up to 228, and of the
Expert and ExpertSubset charsets only the SIDs StandardEncoding has (below
150) are listed.
-}
sidGlyph :: ByteString -> Int -> Int -> Int -> Maybe Int
sidGlyph t nGlyphs off = \sid -> if sid <= 0 then Nothing else Map.lookup sid table >>= inFont
  where
    inFont g = if g > 0 && g < nGlyphs then Just g else Nothing
    table = Map.fromListWith (\_ first -> first) (zip sids [1 ..])
    -- the SIDs of the glyphs 1, 2, ... in order
    sids = case off of
      0 -> [1 .. 228]
      1 -> expanded [(1, 1), (12, 13), (13, 14), (14, 15), (15, 99), (26, 27), (27, 28), (46, 109), (47, 110)]
      2 -> expanded [(1, 1), (8, 13), (9, 14), (10, 15), (11, 99), (22, 27), (23, 28), (41, 109), (42, 110)]
      _ -> case uN 1 t off of
        Just 0 -> [sid | g <- [1 .. nGlyphs - 1], Just sid <- [u16 t (off + 1 + 2 * (g - 1))]]
        Just 1 -> ranges 1
        Just 2 -> ranges 2
        _ -> []
    -- glyph and SID pairs as SIDs in glyph order, 0 (no name of StandardEncoding) between them
    expanded :: [(Int, Int)] -> [Int]
    expanded pairs = [fromMaybe 0 (lookup g pairs) | g <- [1 .. maximum (map fst pairs)]]
    ranges n = take (nGlyphs - 1) (go (off + 1))
      where
        go p = case (u16 t p, uN n t (p + 2)) of
          (Just first, Just left) -> [first .. first + left] <> go (p + 2 + n)
          _ -> []

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

-- ------------------------------------------------------------------ values

{- | A value of a CharString run: one number, or the interval of the numbers
a value made from random may take (Golem ADR 0390).
-}
data Val
  = -- | one number: a value not made from random, or an interval of width 0
    Pt !Double
  | {- | an interval of width: the lower end and whether it belongs to the
    interval (whether it is closed), then the upper end and the same; an end
    may be infinite
    -}
    Wide !Double !Bool !Double !Bool
  deriving stock (Eq)

-- | The ends of a value, each with whether it belongs to the interval.
data Iv = Iv !Double !Bool !Double !Bool

-- | A value as an interval; NaN, which may come of an overflow, takes every number.
toIv :: Val -> Iv
toIv = \case
  Pt v
    | isNaN v -> Iv (negate infinity) False infinity False
    | otherwise -> Iv v True v True
  Wide a ai b bi -> Iv a ai b bi

-- | An interval as a value: one of width 0 is one number.
fromIv :: Iv -> Val
fromIv (Iv a ai b bi)
  | a == b = Pt a
  | otherwise = Wide a ai b bi

infinity :: Double
infinity = 1 / 0

-- | Whether an end of the interval is infinite.
infiniteEnd :: Val -> Bool
infiniteEnd v = let Iv a _ b _ = toIv v in isInfinite a || isInfinite b

-- | Whether 0 belongs to the interval.
holdsZero :: Iv -> Bool
holdsZero (Iv a ai b bi) = (a < 0 || (a == 0 && ai)) && (b > 0 || (b == 0 && bi))

-- | Whether a number other than 0 belongs to the interval.
holdsNonZero :: Iv -> Bool
holdsNonZero (Iv a _ b _) = a /= 0 || b /= 0

addI, mulI, divI :: Iv -> Iv -> Iv
addI (Iv a ai b bi) (Iv c ci d di) = Iv (a + c) (ai && ci) (b + d) (bi && di)
-- the products of the ends; 0 is reached when it belongs to either interval
mulI x@(Iv a ai b bi) y@(Iv c ci d di) = extremes (holdsZero x || holdsZero y) [(p * q, pin && qin) | (p, pin) <- [(a, ai), (b, bi)], (q, qin) <- [(c, ci), (d, di)]]
{- the quotients of the ends by a divisor that does not hold 0: an end of the
divisor open at 0 gives an infinite end; 0 is reached when it belongs to the
dividend -}
divI x@(Iv a ai b bi) (Iv c ci d di) = extremes (holdsZero x) [(quotient p q, pin && qin && q /= 0) | (p, pin) <- [(a, ai), (b, bi)], (q, qin) <- [(c, ci), (d, di)]]
  where
    positive = d > 0
    quotient p q
      | q /= 0 = p / q
      | p == 0 = 0
      | (p > 0) == positive = infinity
      | otherwise = negate infinity

negI, absI, sqrtI :: Iv -> Iv
negI (Iv a ai b bi) = Iv (negate b) bi (negate a) ai
absI i@(Iv a ai b bi)
  | a >= 0 = i
  | b <= 0 = negI i
  | otherwise = let m = max (negate a) b in Iv 0 True m ((b == m && bi) || (negate a == m && ai))
-- an interval of 0 or more
sqrtI (Iv a ai b bi) = Iv (sqrt a) ai (sqrt b) bi

{- | The interval from the smallest to the largest of the values at the ends,
each end closed when a pair of closed ends reaches it; a product or a
quotient of nonzero ends is reached only at the ends, and 0 is reached as
the first argument says.
-}
extremes :: Bool -> [(Double, Bool)] -> Iv
extremes zero cs =
  let lo = minimum (map fst cs)
      hi = maximum (map fst cs)
      reached v = if v == 0 then zero else or [c | (x, c) <- cs, x == v]
   in Iv lo (reached lo) hi (reached hi)

{- | The integers from the floor of the lower end to the ceiling of the upper
end, of an interval whose ends are finite, within ±2^29 as 'toInt'.
-}
integers :: Val -> (Int, Int)
integers v =
  let Iv a _ b _ = toIv v
      bound f x = f (max (negate limit) (min limit x))
      limit = 2 ^ (29 :: Int) :: Double
   in (bound floor a, bound ceiling b)

-- ------------------------------------------------------------------ CharStrings

-- | The state of a branch of a Type 2 CharString run.
data Run = Run
  { rStack :: ![Val],
    rStems :: !Int,
    rTransient :: !(Map.Map Int Val)
  }

{- | What the branches of a glyph share: the operators they ran (numbers and
operators, all the branches added up) and whether one ran random.
-}
data Count = Count
  { cSteps :: !Int,
    cRandom :: !Bool
  }

{- | How a branch ended: it went to its end or stopped as malformed (and the
next branch is followed), or it stopped the check of the glyph with
'OutOfTable' (G08107) or 'Unverifiable' (G08108).
-}
data Out
  = Went !Count
  | Halted !Stop !Count

-- | The rest of a run after a CharString or a subroutine returns or falls off its end.
type Back = Run -> Count -> Out

{- | The check of the CharString of a glyph and of the subroutines it calls:
how it stopped, if it stopped the glyph, and whether it ran random.
-}
glyph :: ByteString -> Font -> Int -> (Maybe Stop, Bool)
glyph t font g = case (,) <$> entry t (fCharStrings font) g <*> fLocals font g of
  Left OutOfTable -> (Just OutOfTable, False)
  Left _ -> (Nothing, False)
  Right (cs, locals) -> case run t font False locals 0 cs (Run [] 0 Map.empty) (Count 0 False) (\_ c -> Went c) of
    Went c -> (Nothing, cRandom c)
    Halted s c -> (Just s, cRandom c)

{- | The branches one after another, adding up their operators; the first that
stops the glyph stops it.
-}
branches :: [Count -> Out] -> Count -> Out
branches [] c = Went c
branches (b : bs) c = case b c of
  Went c' -> branches bs c'
  halted -> halted

{- | Branches that differ only in the values they hold: one that runs no
operator ran to the end of every CharString it was in, so every other
branch runs none either and ends the same way, and they are not run.
-}
valueBranches :: [Count -> Out] -> Count -> Out
valueBranches [] c = Went c
valueBranches (b : bs) c = case b c of
  Went c'
    | cSteps c' == cSteps c -> Went c'
    | otherwise -> valueBranches bs c'
  halted -> halted

-- | A read of the table in a run: a malformed one stops the branch alone.
reading :: Check a -> Count -> (a -> Out) -> Out
reading r c k = case r of
  Right a -> k a
  Left Malformed -> Went c
  Left s -> Halted s c

{- | Runs a CharString, of a glyph used or of a component of its seac (root
ADR 0420), at a call depth (the limit of Type 2 is 10), then the rest of
the run.
-}
run :: ByteString -> Font -> Bool -> Maybe Index -> Int -> ByteString -> Run -> Count -> Back -> Out
run t font component locals depth code st0 c0 back = go code st0 c0
  where
    go b st c = case BS.uncons b of
      Nothing -> back st c
      Just (b0, rest)
        | cSteps c >= stepLimit -> Halted Unverifiable c {cSteps = cSteps c + 1}
        | otherwise -> step b0 rest st c {cSteps = cSteps c + 1}
    push v rest st c
      | length (rStack st) >= 48 = Went c
      | otherwise = go rest st {rStack = v : rStack st} c
    clear rest st = go rest st {rStack = []}
    step b0 rest st c
      | b0 == 28 = reading (inPart (u16 rest 0)) c $ \v -> push (Pt (fromIntegral (if v >= 0x8000 then v - 0x10000 else v))) (BS.drop 2 rest) st c
      | b0 >= 32 && b0 <= 246 = push (Pt (fromIntegral b0 - 139)) rest st c
      | b0 >= 247 && b0 <= 254 = reading (inPart (BS.indexMaybe rest 0)) c $ \b1 ->
          let v = if b0 <= 250 then (fromIntegral b0 - 247) * 256 + fromIntegral b1 + 108 else negate ((fromIntegral b0 - 251) * 256 + fromIntegral b1 + 108)
           in push (Pt v) (BS.drop 1 rest) st c
      | b0 == 255 = reading (inPart (uI 4 rest 0)) c $ \v -> push (Pt (fromInteger (signed32 v) / 65536)) (BS.drop 4 rest) st c
      | b0 `elem` [1, 3, 18, 23] = clear rest (stems st) c
      | b0 == 19 || b0 == 20 =
          let st' = stems st
              n = (rStems st' + 7) `div` 8
           in if BS.length rest < n then Went c else clear (BS.drop n rest) st' c
      | b0 == 10 = call locals rest st c
      | b0 == 29 = call (Just (fGlobals font)) rest st c
      | b0 == 11 = back st c
      | b0 == 14 = endchar st c
      | b0 == 12 = reading (inPart (BS.uncons rest)) c $ \(b1, rest') -> escape b1 rest' st c
      | otherwise = clear rest st c
    {- endchar: the arguments besides the width (an odd one, the first
    pushed) are none, or the four of a seac, adx ady bchar achar, as FreeType
    reads them (root ADR 0420) -}
    endchar st c =
      let vs = rStack st
          args = if odd (length vs) then take (length vs - 1) vs else vs
       in case args of
            [] -> Went c
            [achar, bchar, _, _]
              | component -> Halted (Seac SeacNested) c
              | fCid font -> Halted (Seac SeacCidKeyed) c
              | otherwise -> seac bchar achar c
            _ -> Halted (Seac SeacArguments) c
    {- the components of a seac, the base then the accent, each over every
    code its value may take, checked as the glyphs used -}
    seac bchar achar c = case (,) <$> codes bchar <*> codes achar of
      Left s -> Halted s c
      Right (bases, accents) -> case mapM glyphOf (bases <> accents) of
        Nothing -> Halted (Seac SeacMissingComponent) c
        Just gs -> branches (map follow (unique gs)) c
    codes v = case v of
      Pt x
        | x >= 0 && x <= 255 && x == fromIntegral (toInt x) -> Right [toInt x]
        | otherwise -> Left (Seac SeacArguments)
      _
        | infiniteEnd v -> Left Unverifiable
        | otherwise ->
            let (lo, hi) = integers v
             in if lo < 0 || hi > 255 then Left (Seac SeacArguments) else Right [lo .. hi]
    glyphOf k = case standardEncoding k of
      0 -> Nothing
      sid -> fGlyphOfSid font sid
    unique = foldr (\g gs -> g : filter (/= g) gs) []
    follow g cc = reading ((,) <$> entry t (fCharStrings font) g <*> fLocals font g) cc $ \(cs, locals') ->
      run t font True locals' 0 cs (Run [] 0 Map.empty) cc (\_ c' -> Went c')
    -- the stem hints, two operands each; an odd one is the width
    stems st = st {rStems = rStems st + length (rStack st) `div` 2, rStack = []}
    {- a subroutine: a number of width 0 rounded toward 0; an interval of
    width, every integer from the floor of its lower end to the ceiling of its
    upper end, each a branch once all are in the INDEX (Golem ADR 0390) -}
    call subrs rest st c = case pop st of
      Nothing -> Went c
      Just (v, st') -> case subrs of
        Nothing -> Halted OutOfTable c
        Just ix ->
          let count = ixCount ix
              bias
                | count < 1240 = 107
                | count < 33900 = 1131
                | otherwise = 32768
              enter k cc = reading (entry t ix (k + bias)) cc $ \sub ->
                if depth >= 10 then Went cc else run t font component locals (depth + 1) sub st' cc (go rest)
           in case v of
                Pt x -> enter (toInt x) c
                _
                  | infiniteEnd v -> Halted OutOfTable c
                  | otherwise ->
                      let (lo, hi) = integers v
                       in if lo + bias < 0 || hi + bias >= count
                            then Halted OutOfTable c
                            else branches (map enter [lo .. hi]) c
    pop st = case rStack st of
      v : vs -> Just (v, st {rStack = vs})
      [] -> Nothing
    pops k st = foldM (\(vs, s) _ -> pop s >>= \(v, s') -> pure (v : vs, s')) ([], st) [1 .. k :: Int]
    pushed vs st = if length vs + length (rStack st) > 48 then Nothing else Just st {rStack = reverse vs ++ rStack st}
    {- an operator of k operands, the first pushed first, and what it pushes:
    one list of values, or several, each a branch, or how it stops -}
    oper k rest st c f = case pops k st of
      Nothing -> Went c
      Just (vs, st') -> case f vs of
        Left Malformed -> Went c
        Left s -> Halted s c
        Right alternatives -> valueBranches [\cc -> maybe (Went cc) (\st'' -> go rest st'' cc) (pushed out st') | out <- alternatives] c
    one v = Right [[v]]
    bool b = Pt (if b then 1 else 0)
    -- the results 0 and 1 that may come, 0 first
    outcomes canFalse canTrue = Right ([[Pt 0] | canFalse] <> [[Pt 1] | canTrue])
    arith2 pointwise interval = \case
      [Pt a, Pt b] -> one (Pt (pointwise a b))
      [a, b] -> one (fromIv (interval (toIv a) (toIv b)))
      _ -> Left Malformed
    arith1 pointwise interval = \case
      [Pt a] -> one (Pt (pointwise a))
      [a] -> one (fromIv (interval (toIv a)))
      _ -> Left Malformed
    escape b1 rest st c = case b1 of
      3 -> oper 2 rest st c $ \case
        [Pt a, Pt b] -> one (bool (a /= 0 && b /= 0))
        [a, b] -> outcomes (holdsZero (toIv a) || holdsZero (toIv b)) (holdsNonZero (toIv a) && holdsNonZero (toIv b))
        _ -> Left Malformed
      4 -> oper 2 rest st c $ \case
        [Pt a, Pt b] -> one (bool (a /= 0 || b /= 0))
        [a, b] -> outcomes (holdsZero (toIv a) && holdsZero (toIv b)) (holdsNonZero (toIv a) || holdsNonZero (toIv b))
        _ -> Left Malformed
      5 -> oper 1 rest st c $ \case
        [Pt a] -> one (bool (a == 0))
        [a] -> outcomes (holdsNonZero (toIv a)) (holdsZero (toIv a))
        _ -> Left Malformed
      9 -> oper 1 rest st c (arith1 abs absI)
      10 -> oper 2 rest st c (arith2 (+) addI)
      11 -> oper 2 rest st c (arith2 (-) (\a b -> addI a (negI b)))
      12 -> oper 2 rest st c $ \case
        [Pt a, Pt b] -> if b == 0 then Left Malformed else one (Pt (a / b))
        [a, b]
          | infiniteEnd a || infiniteEnd b -> Left Unverifiable
          | b == Pt 0 -> Left Malformed
          | holdsZero (toIv b) -> Left Unverifiable
          | otherwise -> one (fromIv (divI (toIv a) (toIv b)))
        _ -> Left Malformed
      14 -> oper 1 rest st c (arith1 negate negI)
      15 -> oper 2 rest st c $ \case
        [Pt a, Pt b] -> one (bool (a == b))
        [a, b] -> outcomes True (meets (toIv a) (toIv b))
        _ -> Left Malformed
      18 -> oper 1 rest st c (const (Right [[]]))
      20 -> case pops 2 st of
        Just ([v, i], st') -> place i c $ \k -> go rest st' {rTransient = Map.insert k v (rTransient st')}
        _ -> Went c
      21 -> case pops 1 st of
        Just ([i], st') -> place i c $ \k cc -> maybe (Went cc) (\st'' -> go rest st'' cc) (pushed [Map.findWithDefault (Pt 0) k (rTransient st')] st')
        _ -> Went c
      22 -> oper 4 rest st c $ \case
        [s1, s2, Pt v1, Pt v2] -> one (if v1 <= v2 then s1 else s2)
        [s1, s2, v1, v2] ->
          let Iv lo1 lo1in hi1 _ = toIv v1
              Iv lo2 _ hi2 hi2in = toIv v2
              -- v1 <= v2 for some pair, and v1 > v2 for some pair
              first = lo1 < hi2 || (lo1 == hi2 && lo1in && hi2in)
              second = hi1 > lo2
           in Right ([[s1] | first] <> [[s2] | second, not (first && s1 == s2)])
        _ -> Left Malformed
      -- random: every number of (0, 1] (Golem ADR 0390)
      23 -> push (Wide 0 False 1 True) rest st c {cRandom = True}
      24 -> oper 2 rest st c $ \case
        [Pt a, Pt b] -> one (Pt (a * b))
        [a, b]
          | infiniteEnd a || infiniteEnd b -> Left Unverifiable
          | otherwise -> one (fromIv (mulI (toIv a) (toIv b)))
        _ -> Left Malformed
      26 -> oper 1 rest st c $ \case
        [Pt a] -> if a < 0 then Left Malformed else one (Pt (sqrt a))
        [a] -> let i@(Iv lo _ _ _) = toIv a in if lo < 0 then Left Unverifiable else one (fromIv (sqrtI i))
        _ -> Left Malformed
      27 -> oper 1 rest st c (\vs -> Right [vs <> vs])
      28 -> oper 2 rest st c (\vs -> Right [reverse vs])
      29 -> case pop st of
        Nothing -> Went c
        Just (Pt i, st') ->
          let k = toInt i
              vs = rStack st'
           in case if k < 0 then safeHead vs else safeAt k vs of
                Nothing -> Went c
                Just v -> maybe (Went c) (\st'' -> go rest st'' c) (pushed [v] st')
        Just (i, st')
          | infiniteEnd i -> Halted Unverifiable c
          | max 0 hi >= length vs -> Halted Unverifiable c
          | otherwise -> valueBranches [\cc -> maybe (Went cc) (\st'' -> go rest st'' cc) (safeAt (max 0 k) vs >>= \v -> pushed [v] st') | k <- [lo .. hi]] c
          where
            (lo, hi) = integers i
            vs = rStack st'
      30 -> case pops 2 st of
        Just ([n, j], st2)
          | infiniteEnd n || infiniteEnd j -> Halted Unverifiable c
          | otherwise ->
              let depthNow = length (rStack st2)
                  counts = case n of
                    Pt x -> Right [toInt x]
                    _ -> let (lo, hi) = integers n in if lo < 0 || hi > depthNow then Left Unverifiable else Right [lo .. hi]
                  amounts = case j of
                    Pt x -> [toInt x]
                    _ -> let (lo, hi) = integers j in [lo .. hi]
               in case counts of
                    Left s -> Halted s c
                    Right [k] | k < 0 || k > depthNow -> Went c
                    Right ks -> valueBranches [go rest st2 {rStack = roll k a (rStack st2)} | k <- ks, a <- amounts] c
        _ -> Went c
      _ -> clear rest st c
    -- the position of get and put: a number of width 0 rounded toward 0, or every integer of an interval of width
    place i c k = case i of
      Pt x -> k (toInt x) c
      _
        | infiniteEnd i -> Halted Unverifiable c
        | otherwise -> let (lo, hi) = integers i in valueBranches (map k [lo .. hi]) c
    -- the stack holds the top first; roll moves the top k values toward the top by a
    roll k a vs =
      let (top, below) = splitAt k vs
          rolled = if k == 0 then top else let s = a `mod` k in drop s top ++ take s top
       in rolled ++ below
    -- whether two intervals have a number in common
    meets (Iv a ai b bi) (Iv c ci d di) =
      let (lo, loIn)
            | a > c = (a, ai)
            | c > a = (c, ci)
            | otherwise = (a, ai && ci)
          (hi, hiIn)
            | b < d = (b, bi)
            | d < b = (d, di)
            | otherwise = (b, bi && di)
       in lo < hi || (lo == hi && loIn && hiIn)
    safeHead = \case
      v : _ -> Just v
      [] -> Nothing
    safeAt k vs = case drop k vs of
      v : _ -> Just v
      [] -> Nothing

{- | The SID of the character of a code of StandardEncoding (Technical Note
5176, Appendix B), 0 where it has none.
-}
standardEncoding :: Int -> Int
standardEncoding code
  | code >= 32 && code <= 126 = code - 31
  | code >= 161 && code <= 255 = fromMaybe 0 (lookup code high)
  | otherwise = 0
  where
    high =
      zip [161 .. 175] [96 .. 110]
        <> zip [177 .. 180] [111 .. 114]
        <> zip [182 .. 189] [115 .. 122]
        <> [(191, 123)]
        <> zip [193 .. 200] [124 .. 131]
        <> [(202, 132), (203, 133), (205, 134), (206, 135), (207, 136), (208, 137)]
        <> [(225, 138), (227, 139), (232, 140), (233, 141), (234, 142), (235, 143)]
        <> [(241, 144), (245, 145), (248, 146), (249, 147), (250, 148), (251, 149)]

-- | The operators a glyph may run, its subroutines included, before the check stops following it.
stepLimit :: Int
stepLimit = 100000
