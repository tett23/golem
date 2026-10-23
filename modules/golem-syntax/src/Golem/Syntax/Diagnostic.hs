module Golem.Syntax.Diagnostic
  ( Severity (..),
    DiagnosticCode (..),
    Diagnostic (..),
    Fix (..),
    Fact (..),
    Profile (..),
    diagnostic,
    notice,
    noticeCodes,
    silenceNotices,
    isError,
    hasErrors,
    adjustForProfile,
    sortDiagnostics,
    profileDependentCodes,
    preflightCodes,
  )
where

import Data.List (sortOn)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Syntax.Span

{- | A notice is below a warning (golem-syntax ADR 0002): something the
author may want to know, which needs no fixing. It does not change the exit
code, and only notices can be silenced.
-}
data Severity = Error | Warning | Notice
  deriving stock (Eq, Ord, Show)

{- | @G@ followed by five digits (docs/adr 0061). The upper two digits name
the source (01 syntax, 02 eval, 03 project, 04 document, 05 lint, 06 plugin,
07 layout, 08 output, 09 preflight); the lower three are the number in it.
Numbers 000 to 099 are the codes of four digits written with a 0 inserted;
new codes take 100 to 999. A code is never reused for another meaning.
-}
newtype DiagnosticCode = DiagnosticCode Text
  deriving stock (Eq, Ord, Show)

data Fix = Fix
  { fixTitle :: !Text,
    fixEdits :: ![(SrcSpan, Text)]
  }
  deriving stock (Eq, Ord, Show)

{- | A value a machine reads from a diagnostic (golem-cli ADR 0006): a page
number, a measured value, a path.
-}
data Fact = FactInt !Integer | FactText !Text | FactInts ![Integer] | FactTexts ![Text]
  deriving stock (Eq, Ord, Show)

data Diagnostic = Diagnostic
  { diagCode :: !DiagnosticCode,
    diagSeverity :: !Severity,
    diagSpan :: !SrcSpan,
    diagMessage :: !Text,
    diagRelated :: ![(SrcSpan, Text)],
    diagFixes :: ![Fix],
    -- | facts for machines (golem-cli ADR 0006); none is not written to JSON
    diagFacts :: ![(Text, Fact)]
  }
  deriving stock (Eq, Ord, Show)

data Profile = Dev | Prod
  deriving stock (Eq, Ord, Show)

diagnostic :: Text -> Severity -> SrcSpan -> Text -> Diagnostic
diagnostic code sev sp msg = Diagnostic (DiagnosticCode code) sev sp msg [] [] []

-- | A diagnostic of severity 'Notice'; its code must be in 'noticeCodes'.
notice :: Text -> SrcSpan -> Text -> Diagnostic
notice code = diagnostic code Notice

{- | The codes of the notices (golem-syntax ADR 0002), in one place as
'profileDependentCodes'. silence-notices of the manifest accepts these
only, and docs/diagnostics.md must agree with them (a golem-driver test).
-}
noticeCodes :: [DiagnosticCode]
noticeCodes =
  map
    DiagnosticCode
    [ "G02062", -- a @style-def overrides a style of style.toml or a built-in one
      "G02063", -- [tcy: ...] of ASCII digits only
      "G02064", -- an escaped space at the start of a line in a paragraph that keeps its lines
      "G02065", -- @listing src= (to be retired)
      "G02079", -- an escaped space at the end of a line in a paragraph that keeps its lines
      "G02094", -- @blank-line written in a row (docs/adr ADR 0046)
      "G03023", -- no style.toml
      "G03100", -- a zero indent of caption or sidenote (golem-driver ADR 0043)
      "G04007", -- @number equal to the automatic number
      "G04008", -- page breaks at the very end of the book
      "G04009", -- @blank-line at the very end of the book (docs/adr ADR 0046)
      "G04011", -- @blank-line of as many lines as a page or more (docs/adr ADR 0047)
      "G07030", -- a line of a code block wrapped (golem-driver ADR 0017)
      "G07039", -- a figure fitted to the column (golem-driver ADR 0034)
      "G07045", -- kenten with ruby, not drawn in the PDF (golem-driver ADR 0019)
      "G07046", -- a block with rules broken or a heading rule left out (golem-driver ADR 0027)
      "G07047", -- blank lines dropped at the top of a column (docs/adr ADR 0046)
      "G08008" -- code in the body role without [fonts.code] (golem-driver ADR 0017)
    ]

{- | The single place where notices are silenced: those whose codes are in
the set, or every notice with 'Nothing' (--no-notices). Errors and warnings
are always kept.
-}
silenceNotices :: Maybe (Set DiagnosticCode) -> [Diagnostic] -> [Diagnostic]
silenceNotices codes = filter keep
  where
    keep d = diagSeverity d /= Notice || maybe False (not . Set.member (diagCode d)) codes

isError :: Diagnostic -> Bool
isError = (== Error) . diagSeverity

hasErrors :: [Diagnostic] -> Bool
hasErrors = any isError

{- | Codes whose severity depends on the profile: a warning in dev and an
error in prod.
-}
profileDependentCodes :: [DiagnosticCode]
profileDependentCodes =
  [ DiagnosticCode "G05004", -- unreferenced label
    DiagnosticCode "G03010" -- a font missing from HTML and EPUB (golem-project ADR 0004)
  ]

{- | The codes of golem preflight whose severity the preflight rules decide,
but G09005, retired (golem-pdf ADR 0008)
(golem-cli ADR 0006). They are neither notices nor profile-dependent, and
docs/diagnostics.md must agree with them (a golem-driver test).
-}
preflightCodes :: [DiagnosticCode]
preflightCodes = [DiagnosticCode (T.pack ("G090" <> pad n)) | n <- [2 .. 18 :: Int], n /= 5]
  where
    pad n = (if n < 10 then "0" else "") <> show n

-- | The single place where the build profile changes severities.
adjustForProfile :: Profile -> Diagnostic -> Diagnostic
adjustForProfile prof d
  | diagCode d `elem` profileDependentCodes =
      d {diagSeverity = if prof == Prod then Error else Warning}
  | otherwise = d

{- | Deterministic order: errors and warnings first, notices after them
(golem-syntax ADR 0002); within each, the code, then the file, the start,
the end, the message and the rest (golem-syntax ADR 0003). Errors and
warnings are not told apart: they mix in the order of their codes.
-}
sortDiagnostics :: [Diagnostic] -> [Diagnostic]
sortDiagnostics =
  sortOn
    ( \d ->
        ( diagSeverity d == Notice,
          diagCode d,
          spanFile (diagSpan d),
          spanStart (diagSpan d),
          spanEnd (diagSpan d),
          diagMessage d,
          -- the rest only breaks ties, so the order is total
          show (diagSeverity d, diagRelated d, diagFixes d, diagFacts d)
        )
    )
