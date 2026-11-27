-- | Bundled declarations use the same reader as a writer's copy (root ADR 0470).
module Golem.Project.Bibliography.Builtin (bundledBibliographySource, bundledBibliographyDeclaration) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble.BibliographyStyle
import Golem.Project.Bibliography.Builtin.IEEE qualified as IEEE
import Golem.Project.Bibliography.Builtin.Sist02 qualified as Sist02
import Golem.Project.Bibliography.Builtin.UnifiedLinguistics qualified as UnifiedLinguistics
import Golem.Project.Bibliography.Builtin.Vancouver qualified as Vancouver
import Golem.Project.Style (Dim, parseStyle, stBibliography)
import Golem.Syntax.Diagnostic (Diagnostic, Severity (Error), diagnostic)
import Golem.Syntax.Span (FileId, mkSpan)

bundledBibliographySource :: Text -> Maybe Text
bundledBibliographySource "ieee" = Just IEEE.sourceText
bundledBibliographySource "vancouver" = Just Vancouver.sourceText
bundledBibliographySource "sist02" = Just Sist02.sourceText
bundledBibliographySource "unified-linguistics" = Just UnifiedLinguistics.sourceText
bundledBibliographySource _ = Nothing

{- | The reserved name is renamed only inside trusted embedded data. The
normal reader still rejects a writer's declaration under a reserved name.
-}
bundledBibliographyDeclaration :: FileId -> Text -> Either [Diagnostic] (Maybe (BibliographyStyle Dim))
bundledBibliographyDeclaration fid name = traverse readSource (bundledBibliographySource name)
  where
    readSource source = do
      let copied = T.replace ("[bibliography.styles." <> name) "[bibliography.styles.bundled-copy" (T.replace ("style = '" <> name <> "'") "style = 'bundled-copy'" source)
      style <- parseStyle fid copied
      case Map.lookup "bundled-copy" (bibStyles (stBibliography style)) of
        Just declaration -> pure declaration
        Nothing -> Left [diagnostic "G03006" Error (mkSpan fid 0 0) ("同梱の参考文献スタイルに名前の表がありません: " <> name)]
