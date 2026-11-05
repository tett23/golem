{- | A reader of TOML being written, for completion (docs/adr ADR 0169).
It reads the text before the cursor from the start of the file and finds
where the cursor stands: in a header, at a key, at a value, or nowhere
(in a comment, in a multi-line string, after a value). It is not a parser
of TOML: it follows the headers, the strings, the comments, the nesting of
arrays and inline tables and the dotted keys, and nothing else. It never
fails; what it cannot read is 'Nowhere'.
-}
module Golem.Lsp.Toml
  ( Context (..),
    Quote (..),
    contextAt,
    definedPaths,
  )
where

import Data.ByteString qualified as BS
import Data.List (inits, nub)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE

-- | Where the cursor is in a string.
data Quote = Bare | Basic | Literal
  deriving stock (Eq, Show)

data Context
  = -- | in a header: the steps written, and the step being written
    AtHeader [Text] Text
  | {- | at a key: the path of the table, the keys written in it before
    the cursor, and the key being written
    -}
    AtKey [Text] [Text] Text
  | {- | at a value: the path of the key, whether it is an element of an
    array, whether the cursor is in a string, and the value being written
    -}
    AtValue [Text] Bool Quote Text
  | Nowhere
  deriving stock (Eq, Show)

-- | The context of a byte offset of a text in UTF-8.
contextAt :: Text -> Int -> Context
contextAt text off =
  let before = TE.decodeUtf8Lenient (BS.take off (TE.encodeUtf8 text))
      (toks, end) = lexToml before
      st = foldl step start toks
   in case end of
        EndNowhere -> Nowhere
        EndString q p -> case mode st of
          MValue path -> AtValue path (inArray st) q p
          _ -> Nowhere
        EndWord p -> case mode st of
          MHeader segs -> AtHeader segs p
          MKey [] -> AtKey (base st) (written st) p
          MKey ks -> AtKey (base st <> ks) [] p
          MValue path -> AtValue path (inArray st) Bare p
          MAfter -> Nowhere

{- | The paths of the tables and keys a text defines, in the order of the
text without repeats: every header, every key (dotted or in an inline
table) and the tables on the way to them.
-}
definedPaths :: Text -> [[Text]]
definedPaths text = nub (reverse (defs (foldl step start (fst (lexToml text)))))

-- ------------------------------------------------------------------ tokens

data Tok = TLBracket | TRBracket | TLBrace | TRBrace | TEq | TComma | TDot | TNewline | TWord Text | TStr Text
  deriving stock (Eq, Show)

-- | How the text ends: in a word (perhaps empty), in an open string, or where nothing is completed.
data End = EndWord Text | EndString Quote Text | EndNowhere

lexToml :: Text -> ([Tok], End)
lexToml = go [] . T.unpack
  where
    go acc = \case
      [] -> (reverse acc, EndWord "")
      '#' : r -> case break (== '\n') r of
        (_, []) -> (reverse acc, EndNowhere)
        (_, rest) -> go acc rest
      '\n' : r -> go (TNewline : acc) r
      c : r | c `elem` [' ', '\t', '\r'] -> go acc r
      '"' : '"' : '"' : r -> multi acc "\"\"\"" r
      '\'' : '\'' : '\'' : r -> multi acc "'''" r
      '"' : r -> basic acc "" r
      '\'' : r -> literal acc "" r
      '[' : r -> go (TLBracket : acc) r
      ']' : r -> go (TRBracket : acc) r
      '{' : r -> go (TLBrace : acc) r
      '}' : r -> go (TRBrace : acc) r
      '=' : r -> go (TEq : acc) r
      ',' : r -> go (TComma : acc) r
      '.' : r -> go (TDot : acc) r
      s -> case break special s of
        (w, []) -> (reverse acc, EndWord (T.pack w))
        (w, rest) -> go (TWord (T.pack w) : acc) rest
    special c = c `elem` (" \t\r\n#\"'[]{}=,." :: String)
    -- a string is read to its end; one left open at a line end is closed there
    basic acc s = \case
      [] -> (reverse acc, EndString Basic (T.pack (reverse s)))
      '\\' : c : r -> basic acc (c : '\\' : s) r
      '"' : r -> go (TStr (T.pack (reverse s)) : acc) r
      r@('\n' : _) -> go (TStr (T.pack (reverse s)) : acc) r
      c : r -> basic acc (c : s) r
    literal acc s = \case
      [] -> (reverse acc, EndString Literal (T.pack (reverse s)))
      '\'' : r -> go (TStr (T.pack (reverse s)) : acc) r
      r@('\n' : _) -> go (TStr (T.pack (reverse s)) : acc) r
      c : r -> literal acc (c : s) r
    multi acc close s = case T.breakOn (T.pack close) (T.pack s) of
      (_, rest)
        | T.null rest -> (reverse acc, EndNowhere)
        | otherwise -> go (TStr "" : acc) (T.unpack (T.drop (length close) rest))

-- ------------------------------------------------------------------ reading

-- | A value being read: an array of the values of a key, or an inline table and the keys written in it.
data Frame = FArray [Text] | FInline [Text] [Text]

data Mode
  = -- | at a key: the steps of a dotted key read so far
    MKey [Text]
  | MHeader [Text]
  | -- | at a value of the key
    MValue [Text]
  | -- | after a value or a header
    MAfter

data St = St
  { header :: [Text],
    -- | the keys written in the table of the header
    headerKeys :: [Text],
    frames :: [Frame],
    mode :: Mode,
    -- | the paths defined, last first
    defs :: [[Text]]
  }

start :: St
start = St [] [] [] (MKey []) []

-- | The path of the table the keys go into.
base :: St -> [Text]
base st = case frames st of
  FInline p _ : _ -> p
  _ -> header st

written :: St -> [Text]
written st = case frames st of
  FInline _ ks : _ -> ks
  _ -> headerKeys st

inArray :: St -> Bool
inArray st = case frames st of
  FArray _ : _ -> True
  _ -> False

step :: St -> Tok -> St
step st tok = case (mode st, tok) of
  -- a header, at the start of a line outside any value
  (MKey [], TLBracket) | null (frames st) -> st {mode = MHeader []}
  (MKey [], TRBrace) | FInline _ _ : rest <- frames st -> st {frames = rest, mode = MAfter}
  (MKey ks, TWord w) -> st {mode = MKey (ks <> [w])}
  (MKey ks, TStr w) -> st {mode = MKey (ks <> [w])}
  (MKey ks, TDot) -> st {mode = MKey ks}
  (MKey ks@(k : _), TEq) ->
    let path = base st <> ks
        st' = case frames st of
          FInline p wks : rest -> st {frames = FInline p (wks <> [k]) : rest}
          _ -> st {headerKeys = headerKeys st <> [k]}
     in st' {mode = MValue path, defs = addPaths (base st) ks (defs st)}
  (MKey _, _) -> st {mode = MKey []}
  (MHeader segs, TWord w) -> st {mode = MHeader (segs <> [w])}
  (MHeader segs, TStr w) -> st {mode = MHeader (segs <> [w])}
  (MHeader segs, TDot) -> st {mode = MHeader segs}
  -- the second bracket of an array of tables
  (MHeader [], TLBracket) -> st
  (MHeader segs, TRBracket) -> st {header = segs, headerKeys = [], mode = MAfter, defs = addPaths [] segs (defs st)}
  (MHeader _, _) -> st {mode = MKey []}
  (MValue path, TLBracket) -> st {frames = FArray path : frames st}
  (MValue path, TLBrace) -> st {frames = FInline path [] : frames st, mode = MKey []}
  (MValue _, TRBracket) | FArray _ : rest <- frames st -> st {frames = rest, mode = MAfter}
  -- a value left out at the end of a line: the next line starts again
  (MValue _, TNewline) | null (frames st) -> st {mode = MKey []}
  (MValue _, TNewline) -> st
  (MValue _, _) -> st {mode = MAfter}
  (MAfter, TComma) -> case frames st of
    FArray p : _ -> st {mode = MValue p}
    FInline _ _ : _ -> st {mode = MKey []}
    [] -> st
  (MAfter, TRBracket) | FArray _ : rest <- frames st -> st {frames = rest}
  (MAfter, TRBrace) | FInline _ _ : rest <- frames st -> st {frames = rest}
  (MAfter, TNewline) | null (frames st) -> st {mode = MKey []}
  (MAfter, _) -> st

-- | The paths of a key of steps under a table, and of the tables on the way, last first.
addPaths :: [Text] -> [Text] -> [[Text]] -> [[Text]]
addPaths table ks acc = reverse [table <> p | p <- drop 1 (inits ks), not (null (table <> p))] <> acc
