{-# LANGUAGE TemplateHaskell #-}

{- | The explanations of the diagnostic codes (golem-cli ADR 0005), shown by
golem explain and linked from the LSP. docs/diagnostics.md is embedded when
compiling; a document that breaks the form of "Golem.Driver.Explain.Catalog"
fails the compilation, so no executable carries a malformed one.
-}
module Golem.Driver.Explain
  ( catalog,
    lookupExplanation,
    explainHint,
    codeDescriptionUrl,
    module Golem.Driver.Explain.Catalog,
  )
where

import Data.ByteString qualified as BS
import Data.Either (fromRight)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver.Explain.Catalog
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..))
import Language.Haskell.TH (litE, stringL)
import Language.Haskell.TH.Syntax (addDependentFile, runIO)

-- | The content of docs/diagnostics.md, checked by 'parseCatalog' when compiling.
document :: Text
document =
  T.pack
    $( do
         -- modules/golem-driver/diagnostics.md links to docs/diagnostics.md
         let path = "diagnostics.md"
         addDependentFile path
         text <- runIO (TE.decodeUtf8 <$> BS.readFile path)
         case parseCatalog text of
           Left e -> fail (T.unpack e)
           Right _ -> litE (stringL (T.unpack text))
     )

-- | Every section of docs/diagnostics.md by its code.
catalog :: Map Text Explanation
catalog = Map.fromList [(exCode e, e) | e <- fromRight [] (parseCatalog document)]

-- | The section of a code, which may be written in lower case.
lookupExplanation :: Text -> Maybe Explanation
lookupExplanation code = Map.lookup (T.toUpper code) catalog

{- | The one line written after the diagnostics in the human format, naming
the smallest documented code among them; empty when none is documented
(such as the codes of plugins).
-}
explainHint :: [Diagnostic] -> Text
explainHint ds =
  case [c | DiagnosticCode c <- map diagCode ds, Map.member c catalog] of
    [] -> ""
    cs -> "コードの説明は golem explain <コード> で表示できます（例: golem explain " <> minimum cs <> "）"

{- | The URL of the section of a documented code on main, for the
codeDescription of the LSP. Codes are never reused, so the explanation on
main also holds for the codes of older versions.
-}
codeDescriptionUrl :: DiagnosticCode -> Maybe Text
codeDescriptionUrl (DiagnosticCode c)
  | Map.member c catalog = Just ("https://github.com/tett23/golem/blob/main/docs/diagnostics.md#" <> T.toLower c)
  | otherwise = Nothing
