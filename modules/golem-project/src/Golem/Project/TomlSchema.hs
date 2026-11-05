{- | The keys and the values of a file of settings as data (docs/adr ADR
0169): the schema decides which keys of a TOML file are unknown, and the
language server completes the keys and the values from it. The decoder of
the file reads the same keys; a test of each package checks that every
key of its schema is one its decoder reads.
-}
module Golem.Project.TomlSchema
  ( Node (..),
    Leaf (..),
    Namespace (..),
    unknownKeys,
    nodeAt,
    scalarKeys,
  )
where

import Data.List (find)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe, mapMaybe)
import Data.Text (Text)
import Toml.Pretty (prettySimpleKey)
import Toml.Schema (MatchMessage (..), Scope (..))
import Toml.Semantics (Table' (..), Value' (..))
import Toml.Syntax (Position)

-- | The shape of one value.
data Node
  = -- | a table of known keys, in the order the decoder reads them
    NTable [(Text, Node)]
  | {- | a table whose keys the writer names ([fonts], [character-styles]
    and so on), each with the shape of the node; the namespace is the kind
    of name each key defines, if other values refer to it
    -}
    NNamed (Maybe Namespace) Node
  | -- | an array, with the shape of its elements
    NArray Node
  | -- | one of several shapes (a rule table or false, and so on)
    NEither [Node]
  | NValue Leaf
  | {- | a key the decoder knows only to reject it with its own message (a
    retired key, or one that does not belong in the table): not unknown,
    never completed, and nothing under it is looked at
    -}
    NRejected
  deriving stock (Eq, Show)

data Leaf
  = LString
  | LDimension
  | LInteger
  | LBoolean
  | -- | false alone: no rule, no background (true is an error)
    LFalse
  | -- | one of the values
    LEnum [Text]
  | -- | a name defined in a table of the namespace
    LRef Namespace
  deriving stock (Eq, Show)

-- | The kinds of names a file defines and refers to.
data Namespace = FontRoles | Swatches | CharStyles | ParaStyles | AkiSets | Masters
  deriving stock (Eq, Ord, Show)

{- | The keys of a TOML document that its schema does not know, as the
messages toml-parser writes for the keys left in a table: @unexpected key:@
and the key, at the position of the key, with the path of the table. The
keys of a table come in the order of their names, the tables in the
order of the paths.
-}
unknownKeys :: Node -> Table' Position -> [MatchMessage Position]
unknownKeys = table []
  where
    table path node (MkTable m) = case node of
      NTable kvs ->
        concat
          [ case lookup k kvs of
              Nothing -> [MatchMessage (Just kpos) path ("unexpected key: " <> show (prettySimpleKey k))]
              Just n -> value (path <> [ScopeKey k]) n v
          | (k, (kpos, v)) <- Map.toAscList m
          ]
      NNamed _ n -> concat [value (path <> [ScopeKey k]) n v | (k, (_, v)) <- Map.toAscList m]
      _ -> []
    value path node v = case (node, v) of
      (NTable _, Table' _ t) -> table path node t
      (NNamed _ _, Table' _ t) -> table path node t
      (NArray n, List' _ xs) -> concat (zipWith (\i x -> value (path <> [ScopeIndex i]) n x) [0 ..] xs)
      -- the first shape the value has; a value of no shape is the decoder's error
      (NEither ns, _) -> maybe [] (\n -> value path n v) (find (fits v) ns)
      _ -> []
    fits v = \case
      NTable _ -> isTable v
      NNamed _ _ -> isTable v
      NArray _ -> case v of
        List' _ _ -> True
        _ -> False
      _ -> False
    isTable = \case
      Table' _ _ -> True
      _ -> False

{- | The node at a path of keys. A name of a named table is any key, an
array stands for its elements, and of several shapes the first that has
the path is taken.
-}
nodeAt :: Node -> [Text] -> Maybe Node
nodeAt node = \case
  [] -> Just node
  path@(k : rest) -> case node of
    NTable kvs -> lookup k kvs >>= (`nodeAt` rest)
    NNamed _ n -> nodeAt n rest
    NArray n -> nodeAt n path
    NEither ns -> listToMaybe (mapMaybe (`nodeAt` path) ns)
    _ -> Nothing

{- | The keys of a table whose values are not tables or arrays, in the order
of the schema: the keys of a style that @style-def takes.
-}
scalarKeys :: Node -> [Text]
scalarKeys = \case
  NTable kvs -> [k | (k, n) <- kvs, scalar n]
  _ -> []
  where
    scalar = \case
      NValue _ -> True
      NEither ns -> all scalar ns
      _ -> False
