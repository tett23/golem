-- stack: edges taken from the ancestors of f, root first

{- | The import graph (golem-project ADR 0001): cycle detection and a
deterministic evaluation order.
-}
module Golem.Project.Imports
  ( ImportSite (..),
    ImportForm (..),
    importNamespace,
    importNames,
    ImportGraph (..),
    importsOf,
    importSite,
    findCycles,
    topoOrder,
  )
where

import Data.ByteString qualified as BS
import Data.List (sort)
import Data.List.NonEmpty (NonEmpty, prependList)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Parser.AST
import Golem.Syntax

-- | One @\@import@ line: its path, its form and the span of the line.
data ImportSite = ImportSite
  { isPath :: !Text,
    isForm :: !ImportForm,
    isSpan :: !SrcSpan
  }
  deriving stock (Eq, Show)

{- | The two forms of @\@import@ (root ADR 0451): @path * as ns@, with the
namespace and its span, and @path { a, b }@, with each name and its span.
-}
data ImportForm
  = ImportAll !Text !SrcSpan
  | ImportNames ![(Text, SrcSpan)]
  deriving stock (Eq, Show)

-- | The namespace of an import of the form @* as ns@.
importNamespace :: ImportSite -> Maybe Text
importNamespace s = case isForm s of
  ImportAll ns _ -> Just ns
  ImportNames _ -> Nothing

-- | The names an import of the form @{ … }@ lists, with their spans.
importNames :: ImportSite -> [(Text, SrcSpan)]
importNames s = case isForm s of
  ImportAll _ _ -> []
  ImportNames ns -> ns

-- | Edges from each file to the files it imports, in source order.
newtype ImportGraph = ImportGraph (Map FileId [(FileId, ImportSite)])
  deriving stock (Eq, Show)

{- | The import commands of a file, including those inside a group of
consecutive block commands.
-}
importsOf :: File -> [Either Diagnostic ImportSite]
importsOf (File _ bs) = concatMap fromBlock bs
  where
    fromBlock (Located sp b) = case b of
      BlockCommand (Located _ "import") args _ -> [importSite sp args]
      Attributed cmds _ -> concatMap fromBlock cmds
      _ -> []

{- | The arguments of one \@import (root ADR 0451): a word or a string for
the path, then @* as ns@ or names in braces separated by commas. The form
without @*@ is G03295, any other G03009. Shared by the project and the
evaluation of a file outside it (golem-project ADR 0006).
-}
importSite :: SrcSpan -> [Located Argument] -> Either Diagnostic ImportSite
importSite sp args = case args of
  (Located _ pathArg : rest) | Just p <- pathOf pathArg -> case rest of
    [Located _ (Positional (Word "*")), Located _ (Positional (Word "as")), Located nssp (Positional (Word ns))] -> Right (ImportSite p (ImportAll ns nssp) sp)
    [Located _ (Positional (Word "as")), Located _ (Positional (Word ns))] ->
      Left (diagnostic "G03295" Error sp ("「@import パス as 名前空間」の形は使えません。「@import " <> written pathArg <> " * as " <> ns <> "」と書きます"))
    _ | Just names <- listedNames rest -> Right (ImportSite p (ImportNames names) sp)
    _ -> malformed
  _ -> malformed
  where
    malformed = Left (diagnostic "G03009" Error sp "@import は「@import パス * as 名前空間」か「@import パス { 名前, … }」の形で書きます")
    pathOf = \case
      Positional (Word p) -> Just p
      Positional (StringLit p) -> Just p
      _ -> Nothing
    written = \case
      Positional (StringLit p) -> "\"" <> p <> "\""
      Positional (Word p) -> p
      _ -> ""

{- | The names of a list in braces (root ADR 0451): the words split at
@{@, @}@ and @,@ must be @{@, a name, then @,@ and a name any times, and
@}@. A name's span is its place in its word.
-}
listedNames :: [Located Argument] -> Maybe [(Text, SrcSpan)]
listedNames args = traverse word args >>= open . concatMap pieces
  where
    word = \case
      Located wsp (Positional (Word w)) -> Just (w, wsp)
      _ -> Nothing
    pieces (w, wsp) = go (spanStart wsp) w
      where
        go off t = case T.uncons t of
          Nothing -> []
          Just (c, rest)
            | isMark c -> Left c : go (off + 1) rest
            | otherwise ->
                let (n, rest') = T.break isMark t
                    len = BS.length (TE.encodeUtf8 n)
                 in Right (n, mkSpan (spanFile wsp) off (off + len)) : go (off + len) rest'
    isMark c = c == '{' || c == '}' || c == ','
    open = \case
      Left '{' : Right n : rest -> (n :) <$> more rest
      _ -> Nothing
    more = \case
      [Left '}'] -> Just []
      Left ',' : Right n : rest -> (n :) <$> more rest
      _ -> Nothing

{- | Cycles found by a depth-first search over files and edges in order,
each as the import sites along it. A self-import is a cycle of length 1.
A path ends with the edge that closes it, so it is never empty (docs/adr
ADR 0027).
-}
findCycles :: ImportGraph -> [NonEmpty (FileId, ImportSite)]
findCycles (ImportGraph g) = snd (foldl visitRoot (Map.empty, []) (Map.keys g))
  where
    visitRoot (colors, acc) f
      | Map.member f colors = (colors, acc)
      | otherwise = let (c', cs) = visit colors [] f in (c', acc <> cs)

    visit colors stack f =
      let colors0 = Map.insert f Gray colors
          step (cs, acc) (t, site) = case Map.lookup t cs of
            Just Gray -> (cs, acc <> [prependList (dropWhile ((/= t) . fst) stack) (pure (f, site))])
            Just Black -> (cs, acc)
            Nothing ->
              let (cs', found) = visit cs (stack <> [(f, site)]) t
               in (cs', acc <> found)
          (colors1, cycles) = foldl step (colors0, []) (Map.findWithDefault [] f g)
       in (Map.insert f Black colors1, cycles)

data Color = Gray | Black
  deriving stock (Eq)

{- | Kahn's algorithm; ties are broken by file id, which follows manifest
order and then first reference.
-}
topoOrder :: ImportGraph -> [FileId]
topoOrder (ImportGraph g) = loop initial (Map.keysSet g)
  where
    deps = Map.map (Set.fromList . map fst) g
    initial = deps
    loop remaining pending
      | Set.null pending = []
      | otherwise = case sort [f | f <- Set.toList pending, Set.null (Map.findWithDefault Set.empty f remaining `Set.intersection` pending)] of
          (f : _) -> f : loop remaining (Set.delete f pending)
          [] -> Set.toList pending -- cycles are reported elsewhere
