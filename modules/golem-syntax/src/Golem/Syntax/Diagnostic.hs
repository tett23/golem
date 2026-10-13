module Golem.Syntax.Diagnostic
  ( Severity (..),
    DiagnosticCode (..),
    Diagnostic (..),
    Fix (..),
    Profile (..),
    diagnostic,
    isError,
    hasErrors,
    adjustForProfile,
    sortDiagnostics,
    profileDependentCodes,
  )
where

import Data.List (sortOn)
import Data.Text (Text)
import Golem.Syntax.Span

data Severity = Error | Warning
  deriving stock (Eq, Ord, Show)

{- | @G@ followed by four digits. The upper two digits name the source
(01 syntax, 02 eval, 03 project, 04 document, 05 lint, 06 plugin,
07 layout, 08 output). A code is never reused for another meaning.
-}
newtype DiagnosticCode = DiagnosticCode Text
  deriving stock (Eq, Ord, Show)

data Fix = Fix
  { fixTitle :: !Text,
    fixEdits :: ![(SrcSpan, Text)]
  }
  deriving stock (Eq, Ord, Show)

data Diagnostic = Diagnostic
  { diagCode :: !DiagnosticCode,
    diagSeverity :: !Severity,
    diagSpan :: !SrcSpan,
    diagMessage :: !Text,
    diagRelated :: ![(SrcSpan, Text)],
    diagFixes :: ![Fix]
  }
  deriving stock (Eq, Ord, Show)

data Profile = Dev | Prod
  deriving stock (Eq, Ord, Show)

diagnostic :: Text -> Severity -> SrcSpan -> Text -> Diagnostic
diagnostic code sev sp msg = Diagnostic (DiagnosticCode code) sev sp msg [] []

isError :: Diagnostic -> Bool
isError = (== Error) . diagSeverity

hasErrors :: [Diagnostic] -> Bool
hasErrors = any isError

{- | Codes whose severity depends on the profile: a warning in dev and an
error in prod.
-}
profileDependentCodes :: [DiagnosticCode]
profileDependentCodes =
  [ DiagnosticCode "G0504", -- unreferenced label
    DiagnosticCode "G0310" -- a font missing from HTML and EPUB (golem-project ADR 0004)
  ]

-- | The single place where the build profile changes severities.
adjustForProfile :: Profile -> Diagnostic -> Diagnostic
adjustForProfile prof d
  | diagCode d `elem` profileDependentCodes =
      d {diagSeverity = if prof == Prod then Error else Warning}
  | otherwise = d

-- | Deterministic order: file, position, code, then the rest.
sortDiagnostics :: [Diagnostic] -> [Diagnostic]
sortDiagnostics =
  sortOn
    ( \d ->
        ( spanFile (diagSpan d),
          spanStart (diagSpan d),
          spanEnd (diagSpan d),
          diagCode d,
          diagMessage d,
          -- the rest only breaks ties, so the order is total
          show (diagSeverity d, diagRelated d, diagFixes d)
        )
    )
