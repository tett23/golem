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
    infoDiagnostic,
    infoCodes,
    dropInfo,
    silenceInfo,
    isError,
    hasErrors,
    adjustForProfile,
    sortDiagnostics,
    finishDiagnostics,
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
author may want to know, which needs no fixing. An info is below a notice
(docs/adr 0104): a record of what the processor did by the rules, which the
author need not know, given with --verbose only. Neither changes the exit
code, and only notices and infos can be silenced.
-}
data Severity = Error | Warning | Notice | Info
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
      "G07100", -- a heading taller than the rest of its column (golem-layout ADR 0020)
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

-- | A diagnostic of severity 'Info'; its code must be in 'infoCodes'.
infoDiagnostic :: Text -> SrcSpan -> Text -> Diagnostic
infoDiagnostic code = diagnostic code Info

{- | The codes of the infos (docs/adr 0104), in one place as 'noticeCodes'.
silence-info of the manifest accepts these only, and docs/diagnostics.md
must agree with them (a golem-driver test).
-}
infoCodes :: [DiagnosticCode]
infoCodes =
  [ DiagnosticCode "G07047" -- blank lines dropped at the top of a column (docs/adr ADR 0046)
  ]

-- | Drops every info: a run without --verbose (docs/adr 0104).
dropInfo :: [Diagnostic] -> [Diagnostic]
dropInfo = filter ((/= Info) . diagSeverity)

{- | Drops the infos whose codes are in the set (silence-info, docs/adr
0104). Diagnostics of the other severities are always kept.
-}
silenceInfo :: Set DiagnosticCode -> [Diagnostic] -> [Diagnostic]
silenceInfo codes = filter (\d -> diagSeverity d /= Info || not (Set.member (diagCode d) codes))

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
    DiagnosticCode "G03010", -- a font missing from HTML and EPUB (golem-project ADR 0004)
    DiagnosticCode "G08100" -- a character the font of the PDF has not (docs/adr 0081)
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

{- | The single place where a command finishes its list of diagnostics
(docs/adr 0104): the profile, then the notices silenced by silence-notices
or by --no-notices ('Nothing'), then the infos of silence-info, then every
info unless @verbose@ (--verbose), sorted. golem build, check, lint and
inspect all finish with it, so that each applies the same silencing at the
same point.
-}
finishDiagnostics :: Profile -> Maybe (Set DiagnosticCode) -> Set DiagnosticCode -> Bool -> [Diagnostic] -> [Diagnostic]
finishDiagnostics prof silenced silencedInfo verbose =
  sortDiagnostics
    . (if verbose then id else dropInfo)
    . silenceInfo silencedInfo
    . silenceNotices silenced
    . map (adjustForProfile prof)

{- | Deterministic order: errors and warnings first, notices after them
(golem-syntax ADR 0002), infos last (docs/adr 0104); within each, the code,
then the file, the start, the end, the message and the rest (golem-syntax
ADR 0003). Errors and warnings are not told apart: they mix in the order of
their codes.
-}
sortDiagnostics :: [Diagnostic] -> [Diagnostic]
sortDiagnostics =
  sortOn
    ( \d ->
        ( tier (diagSeverity d),
          diagCode d,
          spanFile (diagSpan d),
          spanStart (diagSpan d),
          spanEnd (diagSpan d),
          diagMessage d,
          -- the rest only breaks ties, so the order is total
          show (diagSeverity d, diagRelated d, diagFixes d, diagFacts d)
        )
    )
  where
    tier :: Severity -> Int
    tier = \case
      Notice -> 1
      Info -> 2
      _ -> 0
