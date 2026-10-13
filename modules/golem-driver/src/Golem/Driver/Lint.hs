{- | @golem lint@ (golem-lint ADR 0001): parse, evaluate to S1, apply the
rules. Syntax and evaluation errors are reported as well.
-}
module Golem.Driver.Lint
  ( lintProject,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Golem.Doc.Assemble (Book (..), LabelTarget (..))
import Golem.Driver
import Golem.Eval.File (EvalResult (..))
import Golem.Lint
import Golem.Project
import Golem.Syntax

lintProject :: Profile -> FilePath -> IO (Map FileId SourceInfo, [Diagnostic])
lintProject profile root = do
  ev <- evaluateProject profile root
  pure $ case ev of
    Left ds -> (Map.empty, finish ds)
    Right e ->
      let project = evProject e
          sources = Map.toList (projectSources project)
          -- the paragraph styles that keep their lines (docs/adr ADR 0005)
          keep = keepStyles (evStyle e)
          files =
            [ FileLint fid (sfPath sf) (sfCst sf) (erSource r) (erUsage r)
            | (fid, sf) <- sources,
              Just r <- [Map.lookup fid (evResults e)]
            ]
          lintDiags = case evBook e of
            Just b -> lint (LintInput files (Map.map ltSpan (bookLabels b)) (bookReferenced b) keep)
            -- evaluation stopped: only the rules that need no evaluation
            Nothing
              | null files -> concat [latinJoinedByNewline (sourceSettingsOf project fid) keep fid (sfCst sf) | (fid, sf) <- sources]
              | otherwise -> lint (LintInput files Map.empty Set.empty keep)
       in (withLockSource e (sourceInfos project), finish (evDiagnostics e <> lintDiags))
  where
    finish = sortDiagnostics . map (adjustForProfile profile)
