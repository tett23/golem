-- stack: edges taken from the ancestors of f, root first

{- | The import graph (golem-project ADR 0001): cycle detection and a
deterministic evaluation order.
-}
module Golem.Project.Imports
  ( ImportSite (..),
    ImportGraph (..),
    importsOf,
    findCycles,
    topoOrder,
  )
where

import Data.List (sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Golem.Parser.AST
import Golem.Syntax

-- | One @\@import path as ns@ line.
data ImportSite = ImportSite
  { isPath :: !Text,
    isNamespace :: !Text,
    isSpan :: !SrcSpan
  }
  deriving stock (Eq, Show)

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
      BlockCommand (Located _ "import") args _ -> [site sp (map locValue args)]
      Attributed cmds _ -> concatMap fromBlock cmds
      _ -> []
    site sp = \case
      [Positional (Word p), Positional (Word "as"), Positional (Word ns)] -> Right (ImportSite p ns sp)
      [Positional (StringLit p), Positional (Word "as"), Positional (Word ns)] -> Right (ImportSite p ns sp)
      _ -> Left (diagnostic "G0309" Error sp "@import は「@import パス as 名前空間」の形で書きます")

{- | Cycles found by a depth-first search over files and edges in order,
each as the import sites along it. A self-import is a cycle of length 1.
-}
findCycles :: ImportGraph -> [[(FileId, ImportSite)]]
findCycles (ImportGraph g) = snd (foldl visitRoot (Map.empty, []) (Map.keys g))
  where
    visitRoot (colors, acc) f
      | Map.member f colors = (colors, acc)
      | otherwise = let (c', cs) = visit colors [] f in (c', acc <> cs)

    visit colors stack f =
      let colors0 = Map.insert f Gray colors
          step (cs, acc) (t, site) = case Map.lookup t cs of
            Just Gray -> (cs, acc <> [dropWhile ((/= t) . fst) stack <> [(f, site)]])
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
