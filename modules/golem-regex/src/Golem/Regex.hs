{-# LANGUAGE MultiWayIf #-}

{- | The regular expressions of regex styles (docs/adr ADR 0015): a subset
of the dialect of InDesign (Boost's Perl-compatible one), matched by a
backtracking matcher that records the states it failed from, so that one
search takes O(P × N) steps for P instructions and N characters.

The syntax outside the subset is an error, not read as something else.
Only the range of a match is found: there are no captures and no back
references, so whether a state (instruction, position) leads to success
does not depend on the path that reached it.
-}
module Golem.Regex
  ( Regex,
    RegexError (..),
    compile,
    matches,
    matchesCounting,
    programSize,
  )
where

import Control.Monad (when)
import Data.Array (Array, listArray, (!))
import Data.Array.Unboxed (UArray)
import Data.Array.Unboxed qualified as U
import Data.Char (GeneralCategory (..), chr, digitToInt, generalCategory, isAsciiLower, isAsciiUpper, isDigit, isHexDigit, ord, toLower, toUpper)
import Data.IntMap.Strict qualified as IntMap
import Data.IntSet (IntSet)
import Data.IntSet qualified as IntSet
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T

-- | A compiled regular expression. Eq and Show compare the source.
data Regex = Regex
  { rxSource :: !Text,
    rxProgram :: !(Array Int Instr),
    rxSize :: !Int
  }

instance Eq Regex where
  a == b = rxSource a == rxSource b

instance Show Regex where
  showsPrec d r = showParen (d > 10) (showString "Regex " . showsPrec 11 (rxSource r))

data RegexError = RegexError
  { -- | the position in the pattern, in characters
    reOffset :: !Int,
    reMessage :: !Text
  }
  deriving stock (Eq, Show)

-- | The largest program, in instructions, a pattern may compile to.
maxProgramSize :: Int
maxProgramSize = 10000

-- | The number of instructions of the program (for the bound of the steps).
programSize :: Regex -> Int
programSize = rxSize

-- ------------------------------------------------------------------ syntax

data Node
  = -- | one character satisfying the predicate
    NChar (Char -> Bool)
  | NSeq [Node]
  | NAlt [Node]
  | -- | minimum, maximum (Nothing: no limit), greedy
    NRep !Int !(Maybe Int) !Bool Node
  | NBol
  | NEol
  | -- | \b (True) or \B (False)
    NWord !Bool
  | -- | ahead (True) or behind, positive, the fixed width of a lookbehind
    NLook !Bool !Bool !Int Node
  | NKeep

-- | The number of instructions a node compiles to.
nodeSize :: Node -> Integer
nodeSize = \case
  NSeq ns -> sum (map nodeSize ns)
  NAlt ns -> sum (map nodeSize ns) + 2 * fromIntegral (max 0 (length ns - 1))
  NRep lo hi _ n -> repSize (toInteger lo) (toInteger <$> hi) (nodeSize n)
  NLook _ _ _ n -> nodeSize n + 2
  _ -> 1

repSize :: Integer -> Maybe Integer -> Integer -> Integer
repSize lo hi s = lo * s + maybe (s + 2) (\h -> (h - lo) * (s + 1)) hi

-- | The number of characters every path of a node consumes, if it is one number.
width :: Node -> Maybe Int
width = \case
  NChar _ -> Just 1
  NSeq ns -> sum <$> traverse width ns
  NAlt [] -> Just 0
  NAlt (n : ns) -> do
    w <- width n
    ws <- traverse width ns
    if all (== w) ws then Just w else Nothing
  NRep lo hi _ n -> case width n of
    Just 0 -> Just 0
    Just w | hi == Just lo -> Just (lo * w)
    _ -> Nothing
  _ -> Just 0

-- ------------------------------------------------------------------ parsing

type Input = [(Int, Char)]

-- | The state of the parser: the case-insensitive flag, the end of the pattern and whether inside a lookaround.
data Env = Env
  { envFold :: !Bool,
    envEnd :: !Int,
    envInLook :: !Bool
  }

failAt :: Int -> Text -> Either RegexError a
failAt o m = Left (RegexError o m)

-- | Compiles a pattern, or the first error in it.
compile :: Text -> Either RegexError Regex
compile src = do
  let input0 = zip [0 ..] (T.unpack src)
      (fold, input) = case input0 of
        (_, '(') : (_, '?') : (_, 'i') : (_, ')') : rest -> (True, rest)
        _ -> (False, input0)
      env = Env fold (T.length src) False
  when (null input) $ failAt 0 "空の正規表現です"
  (node, rest) <- parseAlt env input
  case rest of
    [] -> pure ()
    (o, _) : _ -> failAt o "対応する ( がありません"
  let total = nodeSize node + 1
  when (total > toInteger maxProgramSize) $ failAt 0 tooLarge
  let code = emit 0 node <> [IMatch]
      n = length code
  pure (Regex src (listArray (0, n - 1) code) n)

tooLarge :: Text
tooLarge = "照合のプログラムが大きすぎます。量指定子の展開を含めて " <> T.pack (show maxProgramSize) <> " 命令までです"

-- | The largest count a quantifier may write.
maxRepetition :: Integer
maxRepetition = 65535

tooManyRepetitions :: Text
tooManyRepetitions = "繰り返しの回数が上限の " <> T.pack (show maxRepetition) <> " 回を超えています"

parseAlt :: Env -> Input -> Either RegexError (Node, Input)
parseAlt env input = do
  (first, rest) <- parseSeq env input
  go [first] rest
  where
    go acc = \case
      (_, '|') : rest -> do
        (n, rest') <- parseSeq env rest
        go (n : acc) rest'
      rest -> pure (case acc of [n] -> n; _ -> NAlt (reverse acc), rest)

parseSeq :: Env -> Input -> Either RegexError (Node, Input)
parseSeq env = go []
  where
    go acc = \case
      [] -> pure (NSeq (reverse acc), [])
      input@((_, c) : _) | c == '|' || c == ')' -> pure (NSeq (reverse acc), input)
      input@((o, _) : _)
        | isQuantifierStart input -> failAt o "量指定子の前に何もありません"
      input -> do
        (atom, rest) <- parseAtom env input
        (node, rest') <- parseQuantifier atom rest
        go (node : acc) rest'

-- | Whether the input starts with a quantifier: *, +, ? or a well-formed {n}, {n,}, {n,m}.
isQuantifierStart :: Input -> Bool
isQuantifierStart = \case
  (_, c) : _ | c `elem` ("*+?" :: String) -> True
  input@((_, '{') : _) -> case braces input of
    Just _ -> True
    Nothing -> False
  _ -> False

-- | {n}, {n,} or {n,m}: the bounds and the rest, or Nothing when it is not one (then { is a character).
braces :: Input -> Maybe ((Integer, Maybe Integer, Bool), Input)
braces = \case
  (_, '{') : rest -> do
    let (lo, r1) = span (isDigit . snd) rest
    if null lo
      then Nothing
      else case r1 of
        (_, '}') : r2 -> Just ((num lo, Just (num lo), True), r2)
        (_, ',') : r2 ->
          let (hi, r3) = span (isDigit . snd) r2
           in case r3 of
                (_, '}') : r4 -> Just ((num lo, if null hi then Nothing else Just (num hi), False), r4)
                _ -> Nothing
        _ -> Nothing
  _ -> Nothing
  where
    num = read . map snd

parseQuantifier :: Node -> Input -> Either RegexError (Node, Input)
parseQuantifier atom input = case input of
  (o, c) : rest
    | c == '*' -> lazy o 0 Nothing rest
    | c == '+' -> lazy o 1 Nothing rest
    | c == '?' -> lazy o 0 (Just 1) rest
    | c == '{',
      Just ((lo, hi, _), rest') <- braces input -> do
        when (maybe False (< lo) hi) $ failAt o "量指定子の {n,m} は n ≦ m です"
        when (lo > maxRepetition || maybe False (> maxRepetition) hi) $ failAt o tooManyRepetitions
        lazy o (fromInteger lo) (fromInteger <$> hi) rest'
  _ -> pure (atom, input)
  where
    lazy o lo hi rest = do
      (greedy, rest') <- case rest of
        (_, '?') : r -> pure (False, r)
        (p, '+') : _ -> failAt p "所有的な量指定子（*+、++、?+）は使えません"
        r -> pure (True, r)
      case rest' of
        (p, _) : _ | isQuantifierStart rest' -> failAt p "量指定子が続いています"
        _ -> pure ()
      let node = NRep lo hi greedy atom
      when (nodeSize node > toInteger maxProgramSize) $ failAt o tooLarge
      pure (node, rest')

parseAtom :: Env -> Input -> Either RegexError (Node, Input)
parseAtom env = \case
  [] -> failAt (envEnd env) "正規表現が途中で終わっています"
  (o, c) : rest -> case c of
    '(' -> parseGroup env o rest
    '[' -> do
      (p, rest') <- parseClass env o rest
      pure (NChar p, rest')
    '.' -> pure (NChar (/= '\n'), rest)
    '^' -> pure (NBol, rest)
    '$' -> pure (NEol, rest)
    '~' -> failAt o tildeMessage
    '\\' -> parseEscape env o rest
    _ -> pure (NChar (literal env c), rest)

tildeMessage :: Text
tildeMessage = "InDesign の ~ のメタ文字は使えません。文字の ~ は \\~ と書きます"

-- | A character, folded when the pattern starts with (?i).
literal :: Env -> Char -> Char -> Bool
literal env c = folded (envFold env) (== c)

-- | A predicate that also accepts the lower and the upper case of a character.
folded :: Bool -> (Char -> Bool) -> Char -> Bool
folded False p = p
folded True p = \x -> p x || p (toLower x) || p (toUpper x)

parseGroup :: Env -> Int -> Input -> Either RegexError (Node, Input)
parseGroup env o input = case input of
  (_, '?') : rest -> case rest of
    (_, ':') : r -> body id r
    (_, '=') : r -> look True True r
    (_, '!') : r -> look True False r
    (_, '<') : (_, '=') : r -> look False True r
    (_, '<') : (_, '!') : r -> look False False r
    (_, '<') : _ -> failAt o "名前付きの群は使えません"
    (_, 'P') : _ -> failAt o "名前付きの群は使えません"
    (_, '>') : _ -> failAt o "アトミックな群は使えません"
    (_, '(') : _ -> failAt o "条件の群は使えません"
    (_, '#') : _ -> failAt o "コメントの群は使えません"
    (_, 'i') : (_, ')') : _ -> failAt o "(?i) は正規表現の先頭にだけ書けます"
    _ -> failAt o "使えないフラグか群です。使えるのは正規表現の先頭の (?i) と、(?:...)、(?=...)、(?!...)、(?<=...)、(?<!...) です"
  _ -> body id input
  where
    body wrap r = do
      (n, rest) <- parseAlt env r
      case rest of
        (_, ')') : rest' -> pure (wrap n, rest')
        _ -> failAt o "括弧が閉じていません"
    look ahead positive r = do
      (n, rest) <- parseAlt env {envInLook = True} r
      case rest of
        (_, ')') : rest' ->
          if ahead
            then pure (NLook True positive 0 n, rest')
            else case width n of
              Just w -> pure (NLook False positive w n, rest')
              Nothing -> failAt o "後読みの長さが一つに決まりません"
        _ -> failAt o "括弧が閉じていません"

parseEscape :: Env -> Int -> Input -> Either RegexError (Node, Input)
parseEscape env o = \case
  [] -> failAt o "\\ の後に文字がありません"
  (_, c) : rest -> case c of
    'b' -> pure (NWord True, rest)
    'B' -> pure (NWord False, rest)
    'K'
      | envInLook env -> failAt o "\\K は先読みと後読みの中に書けません"
      | otherwise -> pure (NKeep, rest)
    _ -> do
      (item, rest') <- classEscape env o c rest
      pure (NChar (itemPred env item), rest')

-- | An item of a class: a character, or a set of characters (folded under (?i) or not).
data Item = IChar !Char | ISet !Bool (Char -> Bool)

itemPred :: Env -> Item -> Char -> Bool
itemPred env = \case
  IChar c -> literal env c
  ISet f p -> folded (envFold env && f) p

-- | An escape usable both outside and inside a class (the character after the backslash is given).
classEscape :: Env -> Int -> Char -> Input -> Either RegexError (Item, Input)
classEscape _ o c rest = case c of
  't' -> pure (IChar '\t', rest)
  'n' -> pure (IChar '\n', rest)
  'x' -> hexEscape o rest
  'd' -> set False isNd
  'D' -> set False (not . isNd)
  'w' -> set False isWord
  'W' -> set False (not . isWord)
  's' -> set False isWhiteSpace
  'S' -> set False (not . isWhiteSpace)
  'l' -> set True isLl
  'u' -> set True isLu
  'p' -> property True
  'P' -> property False
  'k' -> failAt o "後方参照は使えません"
  _
    | c >= '1' && c <= '9' -> failAt o "後方参照は使えません"
    | isAsciiLower c || isAsciiUpper c || isDigit c -> failAt o ("使えないエスケープです: \\" <> T.singleton c)
    | otherwise -> pure (IChar c, rest)
  where
    set f p = pure (ISet f p, rest)
    property positive = case rest of
      (_, '{') : r -> case break ((== '}') . snd) r of
        (name, _ : r') -> case categoryNamed (T.pack (map snd name)) of
          Just cats -> pure (ISet False (\x -> (generalCategory x `elem` cats) == positive), r')
          Nothing
            | T.pack (map snd name) `elem` scripts -> failAt o ("文字体系の \\p{" <> T.pack (map snd name) <> "} は使えません。\\x{4E00}-\\x{9FFF} のように範囲で書きます")
            | otherwise -> failAt o ("未知の一般カテゴリーです: \\p{" <> T.pack (map snd name) <> "}")
        (_, []) -> failAt o "\\p{ が閉じていません"
      _ -> failAt o "一般カテゴリーは \\p{L} のように {} で囲んで書きます"

hexEscape :: Int -> Input -> Either RegexError (Item, Input)
hexEscape o = \case
  (_, '{') : r -> case break ((== '}') . snd) r of
    (ds, _ : r')
      | not (null ds), all (isHexDigit . snd) ds, length ds <= 8 -> codePoint (hexValue (map snd ds)) r'
    _ -> failAt o "\\x{...} の中は 16 進数で書きます"
  (_, a) : (_, b) : r | isHexDigit a && isHexDigit b -> codePoint (hexValue [a, b]) r
  _ -> failAt o "\\x の後は 16 進数の 2 桁か {...} で書きます"
  where
    codePoint :: Integer -> Input -> Either RegexError (Item, Input)
    codePoint v r
      | v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF) = failAt o "符号位置が文字ではありません"
      | otherwise = pure (IChar (chr (fromInteger v)), r)

parseClass :: Env -> Int -> Input -> Either RegexError (Char -> Bool, Input)
parseClass env o input = do
  let (negated, r0) = case input of
        (_, '^') : r -> (True, r)
        r -> (False, r)
  (items, rest) <- case r0 of
    (_, ']') : r -> items1 [IChar ']'] r
    r -> items1 [] r
  let p x = any (\i -> itemPred env i x) items
  pure (if negated then not . p else p, rest)
  where
    items1 acc = \case
      [] -> failAt o "文字クラスの [ が閉じていません"
      (_, ']') : rest -> pure (reverse acc, rest)
      input'@((io, _) : _) -> do
        (item, rest) <- classItem input'
        case (item, rest) of
          (IChar lo, (_, '-') : rest'@((_, c2) : _)) | c2 /= ']' -> do
            (hiItem, rest'') <- classItem rest'
            case hiItem of
              IChar hi
                | hi < lo -> failAt io "文字クラスの範囲の両端が逆です"
                | otherwise -> items1 (ISet True (\x -> x >= lo && x <= hi) : acc) rest''
              ISet {} -> failAt io "文字クラスの範囲の端に文字クラスは書けません"
          (ISet {}, (_, '-') : (_, c2) : _) | c2 /= ']' -> failAt io "文字クラスの範囲の端に文字クラスは書けません"
          _ -> items1 (item : acc) rest
    classItem = \case
      (io, '[') : (_, ':') : r
        | (name, (_, ':') : (_, ']') : r') <- break ((== ':') . snd) r,
          all (\(_, c) -> isAsciiLower c || c == '^') name ->
            case posixClass (T.pack (map snd name)) of
              Just p -> pure (ISet True p, r')
              Nothing -> failAt io ("使えない POSIX の文字クラスです: [:" <> T.pack (map snd name) <> ":]")
      (io, '\\') : (_, 'b') : _ -> failAt io "文字クラスの中に \\b は書けません"
      (io, '\\') : (_, c) : r -> classEscape env io c r
      [(io, '\\')] -> failAt io "\\ の後に文字がありません"
      (io, '~') : _ -> failAt io tildeMessage
      (_, c) : r -> pure (IChar c, r)
      [] -> failAt o "文字クラスの [ が閉じていません"

-- ------------------------------------------------------------------ characters

isNd, isWord, isLl, isLu :: Char -> Bool
isNd c = generalCategory c == DecimalNumber
isWord c = generalCategory c `elem` (letters <> marks <> [DecimalNumber, ConnectorPunctuation])
isLl c = generalCategory c == LowercaseLetter
isLu c = generalCategory c == UppercaseLetter

{- | Unicode's White_Space: 25 characters, fixed here rather than taken
from isSpace (docs/adr ADR 0015).
-}
isWhiteSpace :: Char -> Bool
isWhiteSpace c = IntSet.member (ord c) whiteSpace

whiteSpace :: IntSet
whiteSpace =
  IntSet.fromList
    ([0x09 .. 0x0D] <> [0x20, 0x85, 0xA0, 0x1680] <> [0x2000 .. 0x200A] <> [0x2028, 0x2029, 0x202F, 0x205F, 0x3000])

letters, marks, numbers, punctuation, symbols, separators, others :: [GeneralCategory]
letters = [UppercaseLetter, LowercaseLetter, TitlecaseLetter, ModifierLetter, OtherLetter]
marks = [NonSpacingMark, SpacingCombiningMark, EnclosingMark]
numbers = [DecimalNumber, LetterNumber, OtherNumber]
punctuation = [ConnectorPunctuation, DashPunctuation, OpenPunctuation, ClosePunctuation, InitialQuote, FinalQuote, OtherPunctuation]
symbols = [MathSymbol, CurrencySymbol, ModifierSymbol, OtherSymbol]
separators = [Space, LineSeparator, ParagraphSeparator]
others = [Control, Format, Surrogate, PrivateUse, NotAssigned]

-- | The general categories a name of \p{...} stands for.
categoryNamed :: Text -> Maybe [GeneralCategory]
categoryNamed n = lookup n table
  where
    table =
      [ ("L", letters),
        ("M", marks),
        ("N", numbers),
        ("P", punctuation),
        ("S", symbols),
        ("Z", separators),
        ("C", others),
        ("Letter", letters),
        ("Mark", marks),
        ("Number", numbers),
        ("Punctuation", punctuation),
        ("Symbol", symbols),
        ("Separator", separators),
        ("Other", others)
      ]
        <> zip
          ["Lu", "Ll", "Lt", "Lm", "Lo", "Mn", "Mc", "Me", "Nd", "Nl", "No", "Pc", "Pd", "Ps", "Pe", "Pi", "Pf", "Po", "Sm", "Sc", "Sk", "So", "Zs", "Zl", "Zp", "Cc", "Cf", "Cs", "Co", "Cn"]
          (map pure (letters <> marks <> numbers <> punctuation <> symbols <> separators <> others))

-- | Names of scripts, which \p{...} does not take (for the message).
scripts :: [Text]
scripts =
  ["Han", "Hiragana", "Katakana", "Latin", "Greek", "Cyrillic", "Hangul", "Arabic", "Hebrew", "Thai", "Common", "Inherited", "Bopomofo", "Devanagari"]

posixClass :: Text -> Maybe (Char -> Bool)
posixClass = \case
  "alpha" -> Just (\c -> generalCategory c `elem` letters)
  "digit" -> Just isNd
  "alnum" -> Just (\c -> generalCategory c `elem` letters || isNd c)
  "upper" -> Just isLu
  "lower" -> Just isLl
  "space" -> Just isWhiteSpace
  "punct" -> Just (\c -> generalCategory c `elem` punctuation)
  _ -> Nothing

-- ------------------------------------------------------------------ program

data Instr
  = -- | consume one character satisfying the predicate
    IPred (Char -> Bool)
  | -- | try the first, then the second
    ISplit !Int !Int
  | IJmp !Int
  | IBol
  | IEol
  | IWord !Bool
  | -- | ahead, positive, width of a lookbehind, the start of the subprogram, the next instruction
    ILook !Bool !Bool !Int !Int !Int
  | IKeep
  | IMatch

size :: Node -> Int
size = fromInteger . nodeSize

-- | The instructions of a node placed at a program counter.
emit :: Int -> Node -> [Instr]
emit pc = \case
  NChar p -> [IPred p]
  NBol -> [IBol]
  NEol -> [IEol]
  NWord b -> [IWord b]
  NKeep -> [IKeep]
  NSeq ns -> seqAt pc ns
  NAlt [] -> []
  NAlt [n] -> emit pc n
  NAlt (n : ns) ->
    let a = emit (pc + 1) n
        restPc = pc + 1 + size n + 1
        b = emit restPc (NAlt ns)
        end = restPc + size (NAlt ns)
     in [ISplit (pc + 1) restPc] <> a <> [IJmp end] <> b
  NRep lo hi greedy n ->
    let s = size n
        fixed = seqAt pc (replicate lo n)
        q0 = pc + lo * s
        split a b = if greedy then ISplit a b else ISplit b a
        tailCode = case hi of
          Nothing -> [split (q0 + 1) (q0 + s + 2)] <> emit (q0 + 1) n <> [IJmp q0]
          Just h ->
            let k = h - lo
                end = q0 + k * (s + 1)
             in concat [split (q + 1) end : emit (q + 1) n | i <- [0 .. k - 1], let q = q0 + i * (s + 1)]
     in fixed <> tailCode
  NLook ahead positive w n ->
    let sub = emit (pc + 1) n <> [IMatch]
     in ILook ahead positive w (pc + 1) (pc + 1 + size n + 1) : sub
  where
    seqAt _ [] = []
    seqAt q (x : xs) = emit q x <> seqAt (q + size x) xs

-- ------------------------------------------------------------------ matching

-- | The result of a state: success (end, the last \K), or failure with the shallowest state on the stack it ran into.
data Res = Ok !Int !(Maybe Int) | No !Int

noDepth :: Int
noDepth = maxBound

data S = S
  { sFailed :: !IntSet,
    sPending :: ![Int],
    -- | the states of lookaround subprograms known to reach their end
    sSucceeded :: !IntSet,
    sLook :: !(IntMap.IntMap Bool),
    sSteps :: !Int
  }

-- | A minimal strict state monad, to keep the dependencies to base, text, containers and array.
newtype M a = M {runM :: S -> (a, S)}

instance Functor M where
  fmap f (M g) = M (\s -> let (a, s') = g s in s' `seq` (f a, s'))

instance Applicative M where
  pure a = M (a,)
  M f <*> M g = M (\s -> let (h, s1) = f s; (a, s2) = g s1 in s1 `seq` s2 `seq` (h a, s2))

instance Monad M where
  M g >>= k = M (\s -> let (a, s1) = g s in s1 `seq` runM (k a) s1)

gets :: (S -> a) -> M a
gets f = M (\s -> (f s, s))

modify' :: (S -> S) -> M ()
modify' f = M (\s -> let s' = f s in s' `seq` ((), s'))

{- | The non-overlapping matches [start, end), leftmost first, in
characters; an empty match is left out and the next search starts one
character later.
-}
matches :: Regex -> Text -> [(Int, Int)]
matches r = fst . matchesCounting r

-- | 'matches' and the number of steps it took (for the tests).
matchesCounting :: Regex -> Text -> ([(Int, Int)], Int)
matchesCounting r txt =
  let n = T.length txt
      subject = U.listArray (0, n - 1) (T.unpack txt) :: UArray Int Char
      prog = rxProgram r
      (ms, s) = runM (loop prog subject n 0 []) (S IntSet.empty [] IntSet.empty IntMap.empty 0)
   in (ms, sSteps s)
  where
    loop prog subject n start acc
      | start > n = pure (reverse acc)
      | otherwise = do
          res <- search prog subject n 0 start
          case res of
            Ok e k ->
              let b = fromMaybe start k
                  acc' = if e > b then (b, e) : acc else acc
               in loop prog subject n (if e > start then e else start + 1) acc'
            No _ -> loop prog subject n (start + 1) acc

{- | One search from a state with a fresh stack. The failures it records
are kept for later searches, except those that depended on a state of
the stack when the search succeeds (they failed only because that state
was still being searched). A search of a lookaround subprogram also
records the states it succeeded from: only whether it succeeds matters
there, not where it ends.
-}
search :: Array Int Instr -> UArray Int Char -> Int -> Int -> Int -> M Res
search prog subject n pc0 pos0 = do
  saved <- gets sPending
  modify' (\s -> s {sPending = []})
  res <- visit IntMap.empty 0 pc0 pos0
  case res of
    Ok {} -> modify' (\s -> s {sFailed = foldl' (flip IntSet.delete) (sFailed s) (sPending s), sPending = saved})
    No _ -> modify' (\s -> s {sPending = saved})
  pure res
  where
    isSub = pc0 /= 0
    key pc pos = pc * (n + 1) + pos
    visit stack depth pc pos = do
      modify' (\s -> s {sSteps = sSteps s + 1})
      let k = key pc pos
      case IntMap.lookup k stack of
        Just d -> pure (No d)
        Nothing -> do
          failed <- gets (IntSet.member k . sFailed)
          succeeded <- if isSub then gets (IntSet.member k . sSucceeded) else pure False
          if
            | failed -> pure (No noDepth)
            | succeeded -> pure (Ok pos Nothing)
            | otherwise -> do
                res <- step (IntMap.insert k depth stack) (depth + 1) pc pos
                case res of
                  Ok {} -> do
                    when isSub $ modify' (\s -> s {sSucceeded = IntSet.insert k (sSucceeded s)})
                    pure res
                  No low -> do
                    let conditional = low < depth
                    modify' (\s -> s {sFailed = IntSet.insert k (sFailed s), sPending = if conditional then k : sPending s else sPending s})
                    pure (No (if conditional then low else noDepth))
    step stack depth pc pos = case prog ! pc of
      IPred p
        | pos < n && p (subject U.! pos) -> visit stack depth (pc + 1) (pos + 1)
        | otherwise -> pure (No noDepth)
      ISplit a b -> do
        r1 <- visit stack depth a pos
        case r1 of
          Ok {} -> pure r1
          No l1 -> do
            r2 <- visit stack depth b pos
            pure $ case r2 of
              Ok {} -> r2
              No l2 -> No (min l1 l2)
      IJmp t -> visit stack depth t pos
      IBol -> continueIf (pos == 0)
      IEol -> continueIf (pos == n)
      IWord b -> continueIf ((wordAt (pos - 1) /= wordAt pos) == b)
      ILook ahead positive w sub next -> do
        ok <- lookaround ahead w sub pos
        if ok == positive then visit stack depth next pos else pure (No noDepth)
      IKeep -> do
        res <- visit stack depth (pc + 1) pos
        pure $ case res of
          Ok e Nothing -> Ok e (Just pos)
          _ -> res
      IMatch -> pure (Ok pos Nothing)
      where
        continueIf c = if c then visit stack depth (pc + 1) pos else pure (No noDepth)
    wordAt i = i >= 0 && i < n && isWord (subject U.! i)
    lookaround ahead w sub pos = do
      let start = if ahead then pos else pos - w
      if start < 0
        then pure False
        else do
          let k = key sub start
          cached <- gets (IntMap.lookup k . sLook)
          case cached of
            Just b -> pure b
            Nothing -> do
              res <- search prog subject n sub start
              let b = case res of
                    Ok {} -> True
                    No _ -> False
              modify' (\s -> s {sLook = IntMap.insert k b (sLook s)})
              pure b

hexValue :: String -> Integer
hexValue = foldl' (\a d -> a * 16 + toInteger (digitToInt d)) 0
