{- | What the tests of golem-eval share: a context to update with record
syntax, and parsing a source as file 1 and evaluating it, with
projections of the result.
-}
module Support
  ( baseCtx,
    evalSource,
    evalResult,
    resultBlocks,
    resultBodies,
    diagCodeText,
    diagSite,
  )
where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Golem.Doc.IR (Block, BlockBody, blockBody, docBlocks)
import Golem.Eval.File
import Golem.Parser (parseAst)
import Golem.Parser.SourceSettings (defaultSourceSettings)
import Golem.Project.Style (defaultStyle)
import Golem.Syntax

-- | File 1 at ch/01.gm in dev, with nothing declared, no assets and no plugins.
baseCtx :: EvalContext
baseCtx =
  EvalContext
    { ctxFile = FileId 1,
      ctxPath = "ch/01.gm",
      ctxProfile = Dev,
      ctxMeta = Map.empty,
      ctxImports = Map.empty,
      ctxSwatches = Set.empty,
      ctxCharStyles = Set.empty,
      ctxParaStyles = Map.empty,
      ctxDefaultKenten = "sesame",
      ctxCiteKeys = Set.empty,
      ctxAssets = Map.empty,
      ctxPlugins = noPlugins,
      ctxSource = defaultSourceSettings,
      ctxStyle = defaultStyle
    }

{- | Parses the source as file 1 and evaluates it in the context: the
diagnostics of the parser followed by those of the evaluator, and the
result.
-}
evalSource :: EvalContext -> Text -> ([Diagnostic], EvalResult)
evalSource c src =
  let (file, _, pds) = parseAst (FileId 1) src
      r = evalFile c file
   in (pds <> erDiagnostics r, r)

-- | The result of 'evalSource' alone.
evalResult :: EvalContext -> Text -> EvalResult
evalResult c = snd . evalSource c

resultBlocks :: EvalResult -> [Block]
resultBlocks = docBlocks . erDocument

resultBodies :: EvalResult -> [BlockBody]
resultBodies = map blockBody . resultBlocks

diagCodeText :: Diagnostic -> Text
diagCodeText d = let DiagnosticCode x = diagCode d in x

-- | The code, message, start and end of a diagnostic (golem-eval ADR 0003).
diagSite :: Diagnostic -> (Text, Text, Int, Int)
diagSite d = (diagCodeText d, diagMessage d, spanStart (diagSpan d), spanEnd (diagSpan d))
