{- | The output of a derived 'Show' as an indented tree (golem-cli ADR
0007), for golem inspect --as ast and --as ir. It reads what derived
instances write: constructors applied to arguments, records, lists,
tuples, negative numbers in parentheses, string and character literals;
a value with an infix operator (@1 % 2@) is one leaf. A string it cannot
read is returned as it is.
-}
module Golem.Syntax.ShowTree
  ( showTree,
    treeWidth,
  )
where

import Data.Bifunctor (first)
import Data.Char (isAlpha, isAlphaNum, isAscii, isDigit, isPrint, isSpace, isUpper)
import Data.List (intercalate)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Syntax.Span (FileId (..))
import Text.Read (readMaybe)

-- | A node is written on one line when it fits in this many columns, indentation included.
treeWidth :: Int
treeWidth = 100

data Node
  = -- | a constructor (or a function such as fromList) and its arguments
    NCon String [Node]
  | NRec String [(String, Node)]
  | NList [Node]
  | NTuple [Node]
  | -- | a number, a literal, or a value with an infix operator, as it is written
    NLeaf String
  | -- | a SrcSpan: the file, the start and the end
    NSpan Int Int Int
  | NLocated (Int, Int, Int) Node

data Tok = Tok {tKind :: Kind, tText :: String, tStart :: Int, tEnd :: Int}

data Kind = KIdent | KNum | KStr | KChar | KOp | KPunct
  deriving stock (Eq)

{- | The tree of the 'show' of a value, the spans of the file with the
given FileId written as @s..e@ and those of other files as @f:s..e@.
-}
showTree :: FileId -> String -> Text
showTree (FileId cur) s = case tokens 0 s >>= parseAll s of
  Just n -> T.pack (intercalate "\n" (block cur 0 n))
  Nothing -> T.pack s

-- ------------------------------------------------------------------ tokens

tokens :: Int -> String -> Maybe [Tok]
tokens i = \case
  [] -> Just []
  cs@(c : rest)
    | isSpace c -> tokens (i + 1) rest
    | c `elem` ("()[]{}," :: String) -> (Tok KPunct [c] i (i + 1) :) <$> tokens (i + 1) rest
    | c == '"' -> literal KStr '"' cs
    | c == '\'' -> literal KChar '\'' cs
    | isDigit c ->
        let n = number cs
         in (Tok KNum n i (i + length n) :) <$> tokens (i + length n) (drop (length n) cs)
    | isAlpha c || c == '_' ->
        let n = takeWhile (\x -> isAlphaNum x || x `elem` ("_'." :: String)) cs
         in (Tok KIdent n i (i + length n) :) <$> tokens (i + length n) (drop (length n) cs)
    | isOp c ->
        let n = takeWhile isOp cs
         in (Tok KOp n i (i + length n) :) <$> tokens (i + length n) (drop (length n) cs)
    | otherwise -> Nothing
  where
    literal k q cs = do
      n <- closing q (drop 1 cs) 1
      (Tok k (take n cs) i (i + n) :) <$> tokens (i + n) (drop n cs)
    closing q xs n = case xs of
      [] -> Nothing
      '\\' : _ : r -> closing q r (n + 2)
      x : r
        | x == q -> Just (n + 1)
        | otherwise -> closing q r (n + 1)
    number xs = case xs of
      x : 'e' : '-' : r | isDigit x -> x : 'e' : '-' : number r
      x : r | isAlphaNum x || x == '.' -> x : number r
      _ -> []

isOp :: Char -> Bool
isOp c = c `elem` ("!#$%&*+./<=>?@\\^|-~:" :: String)

-- ------------------------------------------------------------------ parsing

parseAll :: String -> [Tok] -> Maybe Node
parseAll src ts = case expr src ts of
  Just (n, []) -> Just n
  _ -> Nothing

punct :: String -> Tok -> Bool
punct p t = tKind t == KPunct && tText t == p

-- | Atoms up to a comma or a closing bracket; with an operator among them, one leaf.
expr :: String -> [Tok] -> Maybe (Node, [Tok])
expr src ts = case splitAt (extent (0 :: Int) 0 ts) ts of
  ([], _) -> Nothing
  (mine@(start : _), rest)
    | hasOp (0 :: Int) mine -> Just (NLeaf (slice src start (last mine)), rest)
    | otherwise -> (,rest) <$> apply src mine
  where
    opener t = tKind t == KPunct && tText t `elem` ["(", "[", "{"]
    closer t = tKind t == KPunct && tText t `elem` [")", "]", "}"]
    -- the number of tokens up to a comma or a closing bracket outside the brackets of the expression
    extent d i = \case
      [] -> i
      t : r
        | opener t -> extent (d + 1) (i + 1) r
        | closer t -> if d == 0 then i else extent (d - 1) (i + 1) r
        | punct "," t && d == 0 -> i
        | otherwise -> extent d (i + 1) r
    -- an infix operator outside brackets
    hasOp d = \case
      [] -> False
      t : r
        | opener t -> hasOp (d + 1) r
        | closer t -> hasOp (d - 1) r
        | tKind t == KOp && d == 0 -> True
        | otherwise -> hasOp d r

-- | The text of the source from one token to another.
slice :: String -> Tok -> Tok -> String
slice src a b = take (tEnd b - tStart a) (drop (tStart a) src)

-- | A head and its arguments.
apply :: String -> [Tok] -> Maybe Node
apply src ts = do
  (h, rest) <- atom src ts
  args <- atoms rest
  case (h, args) of
    (_, []) -> Just h
    (NCon c [], _) -> Just (NCon c args)
    _ -> Nothing
  where
    atoms [] = Just []
    atoms xs = do
      (a, r) <- atom src xs
      (a :) <$> atoms r

atom :: String -> [Tok] -> Maybe (Node, [Tok])
atom src = \case
  t : r | tKind t == KIdent -> case r of
    b : r' | punct "{" b, all isUpper (take 1 (tText t)) -> record (tText t) r'
    _ -> Just (NCon (tText t) [], r)
  t : r | tKind t == KNum -> Just (NLeaf (tText t), r)
  t : r | tKind t == KStr -> (\v -> (NLeaf (renderString v), r)) <$> (readMaybe (tText t) :: Maybe String)
  t : r | tKind t == KChar -> (\v -> (NLeaf (renderChar v), r)) <$> (readMaybe (tText t) :: Maybe Char)
  t : r | punct "(" t -> case r of
    c : r' | punct ")" c -> Just (NLeaf "()", r')
    _ -> do
      (items, r') <- sepBy ")" r
      case items of
        [x] -> Just (x, r')
        _ -> Just (NTuple items, r')
  t : r | punct "[" t -> case r of
    c : r' | punct "]" c -> Just (NList [], r')
    _ -> do
      (items, r') <- sepBy "]" r
      Just (NList items, r')
  _ -> Nothing
  where
    sepBy close xs = do
      (x, r) <- expr src xs
      case r of
        c : r'
          | punct "," c -> first (x :) <$> sepBy close r'
          | punct close c -> Just ([x], r')
        _ -> Nothing
    record name xs = do
      (fs, r) <- fields xs
      Just (special name fs, r)
    fields xs = case xs of
      c : r | punct "}" c -> Just ([], r)
      f : e : r
        | tKind f == KIdent,
          tKind e == KOp,
          tText e == "=" -> do
            (v, r') <- expr src r
            case r' of
              c : r''
                | punct "," c -> first ((tText f, v) :) <$> fields r''
                | punct "}" c -> Just ([(tText f, v)], r'')
              _ -> Nothing
      _ -> Nothing

-- | SrcSpan and Located, written in the short forms.
special :: String -> [(String, Node)] -> Node
special name fs = case (name, fs) of
  ("SrcSpan", [("spanFile", NCon "FileId" [NLeaf f]), ("spanStart", NLeaf s), ("spanEnd", NLeaf e)])
    | Just f' <- readMaybe f, Just s' <- readMaybe s, Just e' <- readMaybe e -> NSpan f' s' e'
  ("Located", [("locSpan", NSpan f s e), ("locValue", v)]) -> NLocated (f, s, e) v
  _ -> NRec name fs

-- ------------------------------------------------------------------ literals

-- | A string literal with the characters outside printable ASCII as they are.
renderString :: String -> String
renderString s = "\"" <> go s <> "\""
  where
    go = \case
      [] -> []
      c : r -> escape '"' c r <> go r

renderChar :: Char -> String
renderChar c = "'" <> escape '\'' c [] <> "'"

escape :: Char -> Char -> String -> String
escape q c next
  | c == q || c == '\\' = ['\\', c]
  | isPrint c && (not (isAscii c) || c >= ' ') = [c]
  | otherwise =
      let e = init (drop 1 (show [c]))
       in e <> (if needsEmpty e next then "\\&" else "")
  where
    needsEmpty e = \case
      n : _ -> (isDigit (last e) && isDigit n) || (e == "\\SO" && n == 'H')
      [] -> False

-- ------------------------------------------------------------------ layout

spanText :: Int -> (Int, Int, Int) -> String
spanText cur (f, s, e)
  | f == cur = "@" <> show s <> ".." <> show e
  | otherwise = "@" <> show f <> ":" <> show s <> ".." <> show e

-- | A node on one line.
oneLine :: Int -> Node -> String
oneLine cur = \case
  NCon c [] -> c
  NCon c as -> unwords (c : map (arg cur) as)
  NRec c fs -> c <> " {" <> intercalate ", " [f <> " = " <> oneLine cur v | (f, v) <- fs] <> "}"
  NList xs -> "[" <> intercalate ", " (map (oneLine cur) xs) <> "]"
  NTuple xs -> "(" <> intercalate ", " (map (oneLine cur) xs) <> ")"
  NLeaf s -> s
  NSpan f s e -> spanText cur (f, s, e)
  NLocated sp v -> oneLine cur v <> " " <> spanText cur sp

{- | A node as the argument of a constructor, in parentheses when it has
spaces; a string or a character literal is one token, whatever it holds.
-}
arg :: Int -> Node -> String
arg cur n = case n of
  NCon _ (_ : _) -> paren
  NLocated _ _ -> paren
  NLeaf s | take 1 s `notElem` ["\"", "'"] && (any isSpace s || take 1 s == "-") -> paren
  _ -> oneLine cur n
  where
    paren = "(" <> oneLine cur n <> ")"

-- | The lines of a node at an indentation.
block :: Int -> Int -> Node -> [String]
block cur ind n
  | fits ind (oneLine cur n) = [pad ind <> oneLine cur n]
  | otherwise = case n of
      NCon c as -> (pad ind <> c) : concatMap (block cur (ind + 2)) as
      NRec c fs -> (pad ind <> c) : concatMap field fs
      NList xs -> concatMap (item "- ") xs
      NTuple xs -> (pad ind <> "(,)") : concatMap (block cur (ind + 2)) xs
      NLocated sp v -> case block cur ind v of
        l : ls -> (l <> " " <> spanText cur sp) : ls
        [] -> []
      _ -> [pad ind <> oneLine cur n]
  where
    field (f, v)
      | fits (ind + 2) (f <> " = " <> oneLine cur v) = [pad (ind + 2) <> f <> " = " <> oneLine cur v]
      | otherwise = (pad (ind + 2) <> f <> " =") : block cur (ind + 4) v
    item mark x = case block cur (ind + 2) x of
      l : ls -> (pad ind <> mark <> drop (ind + 2) l) : ls
      [] -> []

fits :: Int -> String -> Bool
fits ind s = ind + length s <= treeWidth

pad :: Int -> String
pad k = replicate k ' '
