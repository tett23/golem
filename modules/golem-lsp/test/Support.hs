-- | The helpers that the tests of golem-lsp share (docs/adr/0173).
module Support (codesOf) where

import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Golem.Lsp.Workspace (Workspace, diagnosticsFor)
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..))

-- | The codes of the diagnostics of a file of the workspace.
codesOf :: Workspace -> FilePath -> [Text]
codesOf ws p = [c | d <- fromMaybe [] (Map.lookup p (diagnosticsFor ws)), let DiagnosticCode c = diagCode d]
