{- | The explanations of the diagnostic codes (golem-cli ADR 0005), shown by
golem explain and linked from the LSP. scripts/gen-embedded.sh writes
docs/diagnostics.md into "Golem.Driver.Explain.Embedded" (docs/adr/0203);
the tests of golem-driver check that the module is the document and that
the document has the form of "Golem.Driver.Explain.Catalog".
-}
module Golem.Driver.Explain
  ( catalog,
    lookupExplanation,
    explainHint,
    codeDescriptionUrl,
    module Golem.Driver.Explain.Catalog,
  )
where

import Data.Either (fromRight)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Driver.Explain.Catalog
import Golem.Driver.Explain.Embedded (documentText)
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..))

-- | The content of docs/diagnostics.md.
document :: Text
document = documentText

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
