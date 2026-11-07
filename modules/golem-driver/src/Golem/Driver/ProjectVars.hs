{- | The variables of [vars] of manifest.toml in the running heads
(docs/adr/0185): their text, and the checks of @{vars.<name>}@ of the
formats of style.toml.
-}
module Golem.Driver.ProjectVars
  ( projectVarTexts,
    projectVarDiagnostics,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Eval.Expr (embedValue)
import Golem.Eval.Value (Value (..), projectVarValues, typeName)
import Golem.Project.Manifest (ProjectVar)
import Golem.Project.Style (RunningRef (..), runningFormatSites)
import Golem.Syntax

-- | The value at a path of the tables of [vars].
lookupVar :: Map Text Value -> [Text] -> Maybe Value
lookupVar vars = \case
  [] -> Nothing
  [k] -> Map.lookup k vars
  k : rest -> case Map.lookup k vars of
    Just (VHash t) -> lookupVar t rest
    _ -> Nothing

{- | The text of every value of [vars] a running head can show, by its
path: strings as they are, numbers as they are embedded in prose.
-}
projectVarTexts :: Map Text ProjectVar -> Map [Text] Text
projectVarTexts = Map.fromList . go [] . projectVarValues
  where
    go path vars =
      concat
        [ case v of
            VHash t -> go (path <> [k]) t
            _ -> [(path <> [k], t) | Right t <- [embedValue (mkSpan (FileId 0) 0 0) v]]
        | (k, v) <- Map.toList vars
        ]

{- | G03111 for @{vars.<name>}@ without @?@ whose name is not in [vars],
G03112 for one whose value is not a string or a number; at the line of
the format in style.toml, once for each line and name, whatever the
number of chapters.
-}
projectVarDiagnostics :: FileId -> Text -> Map Text ProjectVar -> [Diagnostic]
projectVarDiagnostics styleFid styleText pvars =
  concat
    [ check master sp n optional
    | (master, sp, refs) <- runningFormatSites styleFid styleText,
      (n, optional) <- Map.toList (Map.fromListWith (&&) [(n, q) | (RefProjectVar n, q) <- refs])
    ]
  where
    vars = projectVarValues pvars
    check master sp n optional = case lookupVar vars n of
      Nothing
        | optional -> []
        | otherwise -> [diagnostic "G03111" Error sp ("柱が参照する変数 vars." <> T.intercalate "." n <> " が、manifest.toml の [vars] にありません（マスターページ " <> master <> "）")]
      Just v -> case embedValue sp v of
        Right _ -> []
        Left _ -> [diagnostic "G03112" Error sp ("柱に出せるのは文字列と数です: vars." <> T.intercalate "." n <> " は " <> typeName v <> "（マスターページ " <> master <> "）")]
