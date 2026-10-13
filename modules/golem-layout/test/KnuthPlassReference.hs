{- | The reference test of golem-layout ADR 0007: the example paragraph of
Knuth and Plass set by plain TeX with cmr10. TeX measured the words
(@frog-king.words@) and logged its breaks (@frog-king.log@); this module
reads both and compares them with 'breakParagraph'.
-}
module KnuthPlassReference
  ( Words (..),
    WordRec (..),
    TexRun (..),
    TexBreak (..),
    readWords,
    parseWords,
    paragraphItems,
    referenceLook,
    finish,
    parseTrace,
    parseScaled,
    wordsOf,
    compareRun,
  )
where

import Data.Char (isDigit)
import Data.Either (rights)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Text.Read qualified as TR
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look, plainLook)

-- | What TeX measured, in sp.
data Words = Words
  { -- | the interword glue: \fontdimen2, 3 and 4 of cmr10
    wSpace :: !(Sp, Sp, Sp),
    wParindent :: !Sp,
    -- | the whole paragraph in one \hbox
    wWhole :: !Sp,
    {- | the words in order, punctuation attached to the word before; a
    word with a hyphen in parts, an explicit hyphen between them
    -} wBoxes :: ![WordRec]
  }
  deriving stock (Eq, Show)

-- | A measured word (or part of one), or an explicit hyphen after it (ADR 0008).
data WordRec = WordBox !Text !Sp | WordExHyphen
  deriving stock (Eq, Show)

data TexRun = TexRun
  { trHsize :: !Sp,
    -- | 1 for @firstpass, 2 for @secondpass
    trPass :: !Int,
    -- | the breaks of the chosen path, from the start of the paragraph
    trBreaks :: ![TexBreak],
    -- | the t of the last break
    trTotalDemerits :: !Integer,
    {- | the glue set of each line from \showbox (the scaled integer TeX
    printed, over 65536); negative when shrinking
    -} trGlueSet :: ![Rational]
  }
  deriving stock (Eq, Show)

data TexBreak = TexBreak
  { -- | the number of the word before the break (from 0)
    tbWordIndex :: !Int,
    -- | the f of @line n.f@
    tbFitness :: !Int,
    -- | the demerits of the line that ends here
    tbDemerits :: !Integer
  }
  deriving stock (Eq, Show)

-- ------------------------------------------------------------------ the words

readWords :: FilePath -> IO Words
readWords path = do
  t <- TIO.readFile path
  either (\e -> fail (path <> ": " <> e)) pure (parseWords t)

parseWords :: Text -> Either String Words
parseWords t = do
  recs <- traverse record (filter (not . T.null . T.strip) (T.lines t))
  space <- case [vals | Left ("space", vals) <- recs] of
    [[w, y, z]] -> Right (w, y, z)
    _ -> Left "expected one space record with three values"
  parindent <- single "parindent" recs
  whole <- single "whole" recs
  pure (Words space parindent whole (rights recs))
  where
    record line = case T.words line of
      ["box", w, word] -> Right . WordBox word <$> int w
      ["exhyphen"] -> Right (Right WordExHyphen)
      (key : vals) | key `elem` ["space", "parindent", "whole"] -> (\ns -> Left (key, ns)) <$> traverse int vals
      _ -> Left ("unexpected record: " <> T.unpack line)
    single key recs = case [x | Left (k, [x]) <- recs, k == key] of
      [x] -> Right x
      _ -> Left ("expected one " <> T.unpack key <> " record")
    int w = case TR.signed TR.decimal w of
      Right (n, rest) | T.null rest -> Right n
      _ -> Left ("not an integer: " <> T.unpack w)

-- | The end of a paragraph, as in TeX: no break, \parfillskip, the forced break.
finish :: [Item]
finish = [Penalty 0 infPenalty NoHyphen, Glue 0 filStretch 0, Penalty 0 (negate infPenalty) NoHyphen]

-- | The look of the boxes: the algorithm does not read it.
referenceLook :: Look
referenceLook = plainLook "body" 0

{- | The indent, the words with interword glue between them, the paragraph
end. An explicit hyphen takes the place of the glue after its part, with
the penalty of \exhyphenpenalty (ADR 0008).
-}
paragraphItems :: Words -> [Item]
paragraphItems ws =
  let (w, y, z) = wSpace ws
      between = \case
        (WordBox {} : _) -> [Glue w y z]
        _ -> []
      items = \case
        (WordBox word n : rest) -> Box n (BoxContent word False 0 0 0 referenceLook 0 0) : between rest <> items rest
        (WordExHyphen : rest) -> Penalty 0 50 ExplicitHyphen : items rest
        [] -> []
   in Box (wParindent ws) (BoxContent "" False 0 0 0 referenceLook 0 0) : items (wBoxes ws) <> finish

-- ------------------------------------------------------------------ the log

{- | Splits the log at the @GOLEM-HSIZE=@ marks and reads each part: the
trace of \tracingparagraphs up to @> \box1=@, then the \showbox.
-}
parseTrace :: Text -> [TexRun]
parseTrace t = mapMaybe run (drop 1 (T.splitOn "GOLEM-HSIZE=" t))
  where
    run part =
      let (digits, rest) = T.span isDigit part
          ls = T.lines rest
          (trace, shown) = break (T.isPrefixOf "> \\box") ls
       in case reads (T.unpack digits) of
            [(h, "")] -> fmap (\(pass, brks, total) -> TexRun h pass brks total (glueSets shown)) (lastPass trace)
            _ -> Nothing

-- | The state while reading a trace.
data Trace = Trace
  { stPass :: !Int,
    stWords :: !Int, -- words printed so far in this pass
    stBreakWord :: !Int, -- the word before the latest feasible break
    stBreakPar :: !Bool, -- the latest feasible break is \par
    stNodes :: !(Map.Map Int (Int, Int, Integer, Int)), -- n -> (word, fitness, t, predecessor)
    stLast :: ![Int] -- the nodes at \par, in order
  }

lastPass :: [Text] -> Maybe (Int, [TexBreak], Integer)
lastPass ls =
  let st = foldl' step (Trace 0 0 (-1) False Map.empty []) ls
      nodes = stNodes st
      finals = [(n, tot) | n <- stLast st, Just (_, _, tot, _) <- [Map.lookup n nodes]]
      best = case finals of
        [] -> Nothing
        _ -> Just (fst (foldr1 (\a b -> if snd b < snd a then b else a) finals))
      path n = case Map.lookup n nodes of
        Just (w, f, tot, m) ->
          let prevT = maybe 0 (\(_, _, pt, _) -> pt) (Map.lookup m nodes)
           in TexBreak w f (tot - prevT) : path m
        Nothing -> []
   in fmap (\n -> (stPass st, reverse (path n), maybe 0 (\(_, _, tot, _) -> tot) (Map.lookup n nodes))) best
  where
    step st line
      | line == "@firstpass" = fresh 1
      | line == "@secondpass" = fresh 2
      | line == "@emergencypass" = fresh 3
      | Just node <- T.stripPrefix "@@" line = addNode st node
      | "@" `T.isPrefixOf` line =
          st {stBreakWord = stWords st - 1, stBreakPar = "@\\par" `T.isPrefixOf` line}
      | stPass st > 0 = st {stWords = stWords st + length (wordsOf line)}
      | otherwise = st
      where
        fresh p = Trace p 0 (-1) False Map.empty []
    -- @@n: line l.f[-] t=T -> @@m
    addNode st node =
      case T.words node of
        [nColon, "line", lf, tEq, "->", m]
          | Just n <- num (T.dropEnd 1 nColon),
            (_, f) <- T.breakOnEnd "." (T.dropWhileEnd (== '-') lf),
            Just fit <- num f,
            Just tot <- T.stripPrefix "t=" tEq >>= num,
            Just prev <- T.stripPrefix "@@" m >>= num ->
              st
                { stNodes = Map.insert n (stBreakWord st, fit, toInteger tot, prev) (stNodes st),
                  stLast = if stBreakPar st then stLast st <> [n] else stLast st
                }
        _ -> st
    num x = case TR.decimal x of
      Right (n, r) | T.null r -> Just (n :: Int)
      _ -> Nothing

{- | The words of a printed piece of the paragraph, without the indent and
font. A word is split after a hyphen followed by more: TeX prints lime-
and tree apart when the break after lime- is feasible, and lime-tree
together when it is not (ADR 0008).
-}
wordsOf :: Text -> [Text]
wordsOf = concatMap splitHyphen . T.words . T.replace "\\tenrm" " " . T.replace "[]" " "
  where
    splitHyphen w = case T.breakOn "-" w of
      (a, rest) | Just more <- T.stripPrefix "-" rest, not (T.null more) -> (a <> "-") : splitHyphen more
      _ -> [w]

-- | The glue set of each line (the depth-one \hbox) of a \showbox.
glueSets :: [Text] -> [Rational]
glueSets ls =
  [ if T.null g then 0 else fromInteger (parseScaled (T.drop (T.length marker) g)) / 65536
  | l <- ls,
    ".\\hbox(" `T.isPrefixOf` l,
    let g = snd (T.breakOn marker l)
  ]
  where
    marker = ", glue set "

{- | A number printed by TeX's print_scaled, read back to the scaled
integer (round_decimals of tex.web). A leading @- @ makes it negative and a
trailing unit such as @fil@ is ignored.
-}
parseScaled :: Text -> Integer
parseScaled t0 =
  let t = T.strip t0
      (neg, t') = case T.stripPrefix "-" t of
        Just r -> (True, T.stripStart r)
        Nothing -> (False, t)
      (ip, rest) = T.span isDigit t'
      frac = case T.stripPrefix "." rest of
        Just r -> T.takeWhile isDigit r
        Nothing -> ""
      intPart = if T.null ip then 0 else read (T.unpack ip) :: Integer
      digits = [toInteger (fromEnum c - fromEnum '0') | c <- T.unpack frac]
      fracPart = (foldr (\d a -> (a + d * 131072) `div` 10) 0 digits + 1) `div` 2
      v = intPart * 65536 + fracPart
   in if neg then negate v else v

-- ------------------------------------------------------------------ comparing

{- | The differences between Golem's breaks and TeX's for one \hsize; empty
when they agree.
-}
compareRun :: Words -> TexRun -> [String]
compareRun ws run =
  let items = paragraphItems ws
      r = breakParagraph defaultParams (const (trHsize run)) items
      at = Map.fromList (zip [0 ..] items)
      wordBefore p = length [() | i <- [0 .. p - 1], Just (Box {}) <- [Map.lookup i at]] - 2
      golemWords = map wordBefore (brPositions r)
      texWords = map tbWordIndex (trBreaks run)
      golemFits = map lineFitness (brLines r)
      texFits = map tbFitness (trBreaks run)
      ratios = zip3 [1 :: Int ..] (map lineRatio (init' (brLines r))) (trGlueSet run)
      label = "\\hsize=" <> show (trHsize run) <> "sp: "
   in map (label <>) $
        [ "pass " <> show (brPass r) <> ", TeX " <> show (trPass run)
        | brPass r /= trPass run
        ]
          <> [ "break " <> show i <> " after word " <> show g <> ", TeX after word " <> show x
             | (i, g, x) <- zip3 [1 :: Int ..] golemWords texWords,
               g /= x
             ]
          <> [ show (length golemWords) <> " lines, TeX " <> show (length texWords)
             | length golemWords /= length texWords
             ]
          <> [ "demerits " <> show (brDemerits r) <> ", TeX " <> show (trTotalDemerits run)
             | brDemerits r /= trTotalDemerits run
             ]
          <> [ "line " <> show i <> " fitness " <> show g <> ", TeX " <> show x
             | (i, g, x) <- zip3 [1 :: Int ..] golemFits texFits,
               g /= x
             ]
          <> [ "line " <> show i <> " glue set " <> show (round (g * 65536) :: Integer) <> "sp, TeX " <> show (round (x * 65536) :: Integer)
             | (i, g, x) <- ratios,
               abs (round (g * 65536) - round (x * 65536) :: Integer) > 1
             ]
          <> [ "line " <> show i <> " is overfull"
             | (i, l) <- zip [1 :: Int ..] (brLines r),
               lineOverfull l
             ]
  where
    init' xs = if null xs then [] else init xs

-- | The fitness class of a set line, from its stretch or shrink and 'badness'.
lineFitness :: Line -> Fitness
lineFitness l =
  let its = lineItems l
      natural = sum [itemWidth it | it <- its, not (isPenalty it)]
      stretch = sum [y | Glue _ y _ <- its]
      shrink = sum [z | Glue _ _ z <- its]
      shortfall = lineTarget l - natural
   in if shortfall >= 0
        then fitnessOf False (badness shortfall stretch)
        else fitnessOf True (if negate shortfall > shrink then 10000 else badness (negate shortfall) shrink)
  where
    isPenalty = \case
      Penalty {} -> True
      _ -> False
