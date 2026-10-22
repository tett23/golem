{- | @golem lint@ (golem-lint ADR 0001): parse, evaluate to S1, apply the
rules. Syntax and evaluation errors are reported as well.
-}
module Golem.Driver.Lint
  ( lintProject,
    lintEvaluated,
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

{- | The diagnostics of golem lint; with @noNotices@ (--no-notices) no
notice, and otherwise none of the codes of silence-notices (golem-syntax
ADR 0002).
-}
lintProject :: Profile -> Bool -> FilePath -> IO (Map FileId SourceInfo, [Diagnostic])
lintProject profile noNotices root = do
  ev <- evaluateProject profile root
  pure $ case ev of
    Left f -> (pfSources f, finish Set.empty (pfDiagnostics f))
    Right e -> (withEvaluatedSources e (sourceInfos (evProject e)), finish (manifestSilencedNotices (projectManifest (evProject e))) (evDiagnostics e <> lintEvaluated e))
  where
    finish silenced = sortDiagnostics . silenceNotices (if noNotices then Nothing else Just silenced) . map (adjustForProfile profile)

{- | The rules on an evaluated project. G05001 of a file that defines styles
uses the paragraph styles that keep their lines in that file (docs/adr
ADR 0005, 0014).
-}
lintEvaluated :: Evaluated -> [Diagnostic]
lintEvaluated e =
  let project = evProject e
      sources = Map.toList (projectSources project)
      keep = keepStyles (evStyle e)
      locals = localStylesOf e
      -- how each file was read, @manifest included (docs/adr ADR 0013, 0014)
      sourceOf fid = maybe (sourceSettingsOf project fid) erSource (Map.lookup fid (evResults e))
      files =
        [ FileLint fid (sfPath sf) (sfCst sf) (erSource r) (erUsage r)
        | (fid, sf) <- sources,
          Just r <- [Map.lookup fid (evResults e)]
        ]
      -- G05001 again for the files with styles of their own
      perFile ds =
        [d | d <- ds, not (diagCode d == DiagnosticCode "G05001" && Map.member (spanFile (diagSpan d)) locals)]
          <> concat [latinJoinedByNewline (sourceOf fid) (keepStyles (docStyles e fid)) fid (sfCst sf) | (fid, sf) <- sources, Map.member fid locals]
   in case evBook e of
        Just b -> perFile (lint (LintInput files (Map.map ltSpan (bookLabels b)) (bookReferenced b) keep))
        -- evaluation stopped: only the rules that need no evaluation
        Nothing
          | null files -> concat [latinJoinedByNewline (sourceOf fid) keep fid (sfCst sf) | (fid, sf) <- sources]
          | otherwise -> perFile (lint (LintInput files Map.empty Set.empty keep))
