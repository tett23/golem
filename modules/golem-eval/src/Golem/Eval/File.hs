{- | File evaluation, S0 (golem-eval ADR 0002): one source file and its
imports become semantic IR. Values that need the whole document (S1) or
the layout (S2) are left as 'Ref' and 'Deferred' inlines.
-}
module Golem.Eval.File
  ( EvalContext (..),
    VarImports (..),
    Asset (..),
    PluginHook (..),
    PluginCommand (..),
    PluginBlockCommand (..),
    noPlugins,
    figureChecks,
    Usage (..),
    EvalResult (..),
    evalFile,
    paragraphBlocks,
    builtinInlineCommands,
    Space (..),
    Overrides (..),
    noOverrides,
    fileOverrides,
    callsBuiltin,
    kentenShapes,
    TableFormat (..),
    CellReading (..),
    AlignError (..),
    parseCsv,
    parseTsv,
    TableError (..),
    TableLimit (..),
    tableDiagnostic,
    tableMaxBytes,
    tableMaxRows,
    tableMaxCells,
  )
where

import Control.Applicative ((<|>))
import Control.Monad (forM, forM_, unless, when)
import Control.Monad.State.Strict
import Data.Bifunctor qualified as Bi
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isAscii, isAsciiLower, isAsciiUpper, isDigit)
import Data.Either (fromLeft, fromRight, isLeft, lefts, rights)
import Data.List (mapAccumL, partition)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing, listToMaybe, mapMaybe)
import Data.Ratio (denominator, numerator)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Array qualified as TA
import Data.Text.Encoding qualified as TE
import Data.Text.Internal qualified as TI
import Data.Text.Unsafe (lengthWord8)
import Golem.Doc.FigureWidth (FigureWidth (..), parseFigureWidth)
import Golem.Doc.IR
import Golem.Doc.Url (UrlProblem (..), checkUrl, linkElements, urlProblemMessage)
import Golem.Doc.Validate (langTagMessage)
import Golem.Eval.Analysis (analyse)
import Golem.Eval.Builtin
import Golem.Eval.Expr
import Golem.Eval.Functions
import Golem.Eval.Number (exactText)
import Golem.Eval.RegexStyle (applyInitialStyles, applyRegexStyles, regexRules)
import Golem.Eval.Settings
import Golem.Eval.Value
import Golem.Parser.AST qualified as A
import Golem.Parser.Lower qualified as A (numberWord)
import Golem.Parser.Read (checkTableText)
import Golem.Parser.SourceSettings
import Golem.Project.Imports (ImportForm (..), ImportSite (..), ListedName (..), importNames, importSite, importsOf)
import Golem.Project.Paths (PathError (..), normalizeRelative, pathErrorMessage)
import Golem.Project.Style (Dim (..), LineBreaks (..), LocalStyles (..), LocalValue (..), ParaStyleDef (..), Sp (..), Style (stOutlines, stPrintingsFormat), StyleKind (..), checkLocalStyles, headingParaStyle, kentenShapeNames, localStyleDefWithValues, noLocalStyles, paraLineBreaks, paraStyleKeys, paraStyleWith, parseAki, parseDim, renderPrintingTemplate, withLocalStyles)
import Golem.Syntax
import Golem.Syntax.LanguageTag (isLanguageTag)
import Golem.Syntax.Sha256 (sha256)
import Golem.Syntax.Text (isSpaceTab, tshow)
import Numeric.Natural (Natural)

-- | The call of one plugin command.
newtype PluginCommand = PluginCommand
  { -- | the output and the plugin's own diagnostics, or errors
    pcCall :: [PluginArg] -> [[Inline]] -> SrcSpan -> Either [Diagnostic] ([Inline], [Diagnostic])
  }

{- | The call of one block command of a plugin (docs/adr/0122): the
arguments, the body evaluated, and where it is called.
-}
newtype PluginBlockCommand = PluginBlockCommand
  { -- | the blocks and the plugin's own diagnostics, or errors
    pbCall :: [PluginArg] -> [Block] -> SrcSpan -> Either [Diagnostic] ([Block], Map Text ByteString, [Diagnostic])
  }

{- | Plugin commands and filters, provided by golem-plugin. The keys tell an
override of a built-in command from a command of its own (docs/adr ADR 0027).
-}
data PluginHook = PluginHook
  { phOverrides :: !(Map BuiltinInline PluginCommand),
    phCommands :: !(Map PluginCommandName PluginCommand),
    -- | the block commands of the plugins, by name (docs/adr/0122)
    phBlocks :: !(Map Text PluginBlockCommand),
    -- | the overrides of built-in block commands that block-overrides declares (root ADR 0453)
    phBlockOverrides :: !(Map OverridableBlock PluginBlockCommand),
    -- | the channels the plugins declare (golem-doc ADR 0007)
    phChannels :: !(Map Text ChannelDecl),
    phApplyFilters :: FilePath -> Document -> Either [Diagnostic] (Document, [Diagnostic]),
    -- | the names of the context of the book the plugins ask for, in order (docs/adr/0121)
    phContextNames :: ![Text],
    -- | the plugins failed to load or to pass the checks: a name one might have given is G02282 (root ADR 0461)
    phFailed :: !Bool
  }

noPlugins :: PluginHook
noPlugins = PluginHook Map.empty Map.empty Map.empty Map.empty Map.empty (\_ d -> Right (d, [])) [] False

data EvalContext = EvalContext
  { ctxFile :: !FileId,
    ctxPath :: !FilePath,
    ctxProfile :: !Profile,
    ctxMeta :: !(Map Text Value),
    -- | the namespace vars, the values of [vars] of manifest.toml (docs/adr/0185)
    ctxVars :: !(Map Text Value),
    -- | the variables the @import lines of variable files give (root ADR 0455)
    ctxImports :: !VarImports,
    ctxSwatches :: !(Set Text),
    -- | the character styles, built-in ones included (docs/adr ADR 0005)
    ctxCharStyles :: !(Set Text),
    -- | the paragraph styles and whether they keep their lines (docs/adr ADR 0005)
    ctxParaStyles :: !(Map Text LineBreaks),
    ctxDefaultKenten :: !Text,
    ctxCiteKeys :: !(Set Text),
    -- | the files @figure, @table and @listing refer to; a path not in it is missing
    ctxAssets :: !(Map FilePath Asset),
    ctxPlugins :: !PluginHook,
    -- | how the file is read (docs/adr ADR 0013)
    ctxSource :: !SourceSettings,
    -- | style.toml as read, which the @style-def of a file is laid over (docs/adr ADR 0014)
    ctxStyle :: !Style,
    -- | the styles of the @style-def of the file, for the keys of @style (root ADR 0467)
    ctxLocalStyles :: !LocalStyles,
    -- | the functions of the .emet of the project (docs/adr/0162)
    ctxFunctions :: !FunctionTable
  }

{- | The variables the @import lines of variable files give (root ADR
0455). The evaluation of a project resolves each line through the import
graph and gives the variables the file it points at exports, by the path
as the line writes it; the evaluation of a file outside a project does not
resolve them, and an @import of a variable file is then as one of a .emet
that could not be loaded.
-}
data VarImports = ResolvedImports !(Map Text (Map Text Value)) | UnresolvedImports

-- | The variables an @import of a path gives; Nothing when the evaluation does not resolve the imports.
importedVars :: EvalContext -> Text -> Maybe (Map Text Value)
importedVars ctx path = case ctxImports ctx of
  ResolvedImports m -> Just (Map.findWithDefault Map.empty path m)
  UnresolvedImports -> Nothing

-- | A file referenced by @figure, @table or @listing (golem-eval ADR 0003).
data Asset
  = -- | read as text, for a table or a listing, with the file it was read from (golem-eval ADR 0004)
    AssetText !FileId !Text
  | {- | a table file that failed the reading stage, whose diagnostics were
    reported when it was read: no table is made of it, and a listing reads
    the text as before (golem-eval ADR 0004)
    -}
    AssetTableUnreadable !FileId !Text
  | {- | a table file larger than 'tableMaxBytes', by its size in bytes, not
    read for the table (G02088, docs/adr ADR 0043); the text when a listing
    also reads it
    -}
    AssetTableTooLarge !Integer !(Maybe Text)
  | -- | present, and not read
    AssetPresent
  | -- | a path that cannot be used: absolute, a URL, outside the root, or missing
    AssetInvalid !PathError
  deriving stock (Eq, Show)

data Usage = Usage
  { usageDefined :: ![(Text, SrcSpan)],
    usageReferenced :: !(Set Text),
    usageNamespaceRefs :: !(Map Text (Set Text)),
    usageImports :: ![(Text, FilePath, SrcSpan)],
    -- | each item an @import lists: its alias, its original name, its path and the span of its alias (root ADR 0451, root ADR 0458)
    usageListed :: ![(Text, Text, FilePath, SrcSpan)],
    -- | the listed names the file uses without a namespace (root ADR 0451)
    usageListedRefs :: !(Set Text),
    -- | where the file overrides the built-in commands, for the tools (root ADR 0471)
    usageOverrides :: !Overrides
  }
  deriving stock (Eq, Show)

data EvalResult = EvalResult
  { erDocument :: !Document,
    erExports :: !(Map Text Value),
    erUsage :: !Usage,
    erDiagnostics :: ![Diagnostic],
    -- | the settings that applied to the file (docs/adr ADR 0013)
    erSource :: !SourceSettings,
    -- | the styles the file defines (docs/adr ADR 0014)
    erStyles :: !LocalStyles,
    -- | the line of each @number by the span of the block it numbers (G04007, golem-syntax ADR 0002)
    erNumberSites :: !(Map SrcSpan SrcSpan),
    -- | the images plugins made for the figures of the file, by their source (docs/adr/0123)
    erImages :: !(Map Text ByteString)
  }

{- | Where a file overrides the built-in commands (root ADR 0471), for the
stages before the evaluation and the tools: the names the plugins
override, in every file of the book, and the names the @import lines of
names list, each from the end of its line on, in the spaces of use the
source gives the name in.
-}
data Overrides = Overrides
  { ovPlugins :: !(Set (Space, Text)),
    ovListed :: ![(Space, Text, Int)]
  }
  deriving stock (Eq, Show)

noOverrides :: Overrides
noOverrides = Overrides Set.empty []

{- | The overrides of a file (root ADR 0471), told from its @import lines
of names and the plugins as the evaluation tells them ('listedImport'):
an alias of a built-in name that is not reserved, of a space of use the
.emet gives the name in (every space for a .emet that could not be
loaded), with the shape of the names of each of those spaces. A variable
file overrides nothing.
-}
fileOverrides :: FunctionTable -> PluginHook -> A.File -> Overrides
fileOverrides table hook file =
  Overrides
    (Set.fromList ([(InlineSpace, builtinName b) | b <- Map.keys (phOverrides hook)] <> [(BlockSpace, overridableBlockName b) | b <- Map.keys (phBlockOverrides hook)]))
    [ (s, a, spanEnd sp)
    | ImportSite path (ImportNames items) sp <- rights (importsOf file),
      ListedName n _ a _ <- items,
      a `notElem` reservedNames,
      Just spaces <- [sourceSpaces path n a],
      s <- spaces,
      overridable s a
    ]
  where
    sourceSpaces path n a
      | ".emet" `T.isSuffixOf` path = case normalizeRelative (T.unpack path) >>= \p -> maybe (Left Missing) Right (Map.lookup p (ftFiles table)) of
          Right fns
            | not (ftUnloaded table) ->
                let spaces = [InlineSpace | Map.member n (fnInline fns)] <> [BlockSpace | Map.member n (fnBlock fns)] <> [ExprSpace | Map.member n (fnExpr fns)]
                 in -- an alias not of the shape of the names of every one of them is G02278 and left out
                    Just (if all (`aliasShape` a) spaces then spaces else [])
          _ -> Just [InlineSpace, BlockSpace, ExprSpace]
      | otherwise = Nothing
    overridable s a = case s of
      InlineSpace -> isJust (parseBuiltin a)
      BlockSpace -> isJust (parseOverridableBlock a)
      ExprSpace -> False

{- | Whether a command of a name at a position (an offset of the file)
calls the built-in command (root ADR 0471).
-}
callsBuiltin :: Overrides -> Space -> Text -> Int -> Bool
callsBuiltin (Overrides plugins listed) s n pos = not (Set.member (s, n) plugins || or [True | (s', n', from) <- listed, s' == s, n' == n, from <= pos])

data St = St
  { stVars :: !(Map Text Value),
    stNamespaces :: !(Map Text (Map Text Value)),
    -- | the namespaces of the .emet the file imports (docs/adr/0162)
    stFunctions :: !(Map Text FunctionRef),
    stDefined :: ![(Text, SrcSpan)],
    stRefs :: !(Set Text),
    stNsRefs :: !(Map Text (Set Text)),
    stImports :: ![(Text, FilePath, SrcSpan)],
    stNote :: !Int,
    stSidenote :: !Int,
    -- | the number of the last endnote of the file (root ADR 0412)
    stEndnote :: !Int,
    stDiags :: ![Diagnostic],
    -- | the line of each @number by the span of its block (G04007)
    stNumberSites :: !(Map SrcSpan SrcSpan),
    -- | the images of the figures of plugins that passed the checks (docs/adr/0123)
    stImages :: !(Map Text ByteString),
    -- | each [note name] in order: its span and its name (docs/adr/0263)
    stNoteRefs :: ![(SrcSpan, Text)],
    -- | each @note in order: its name, its span and its body, Nothing for one of a name already defined (docs/adr/0263)
    stNoteDefs :: ![(Text, SrcSpan, [Block])],
    -- | each [endnote name] and each @endnote, as those of the notes (root ADR 0412)
    stEndnoteRefs :: ![(SrcSpan, Text)],
    stEndnoteDefs :: ![(Text, SrcSpan, [Block])],
    -- | the argument span and exact count of each @blank-line (Golem ADR 0345)
    stBlankCounts :: !(Map SrcSpan (SrcSpan, Integer)),
    -- | the @import lines of the file and the names it @set, for the clashes of listed names (root ADR 0451)
    stFileImports :: ![ImportSite],
    stSetNames :: !(Set Text),
    -- | the functions listed by @import, by their space of use and name; Unloaded with why for one the evaluation cannot call (root ADR 0461)
    stListedFns :: !(Map (Space, Text) FunctionRef),
    -- | the variables listed by @import
    stListedVars :: !(Map Text Value),
    stListedSites :: ![(Text, Text, FilePath, SrcSpan)],
    stListedRefs :: !(Set Text),
    -- | the names listed by, and the namespaces of, the @import lines of variable files the evaluation does not resolve (root ADR 0455)
    stUnresolvedVars :: !(Set Text),
    stUnresolvedNamespaces :: !(Set Text),
    stBodyScopes :: ![BodyScope]
  }

-- | A body accepted by one command, before its callback is entered (root ADR 0473).
data BodyScope = BodyScope
  { scopeCommand :: !SrcSpan,
    scopeFence :: !(Maybe SrcSpan),
    scopeInput :: ![A.Located A.Block],
    scopeResult :: !(Maybe (Maybe [Block]))
  }

withBodyScope :: SrcSpan -> Maybe SrcSpan -> Bool -> [A.Located A.Block] -> M [Block] -> M [Block]
withBodyScope site fence canOmit input action = do
  errors <- gets (length . filter ((== Error) . diagSeverity) . stDiags)
  modify' (\st -> st {stBodyScopes = BodyScope site fence input Nothing : stBodyScopes st})
  out <- action
  current <- gets (listToMaybe . stBodyScopes)
  ds <- gets stDiags
  case (fence, current) of
    (Just fsp, Just scope)
      | canOmit,
        length input == 1,
        Just (Just [_]) <- scopeResult scope,
        length (filter ((== Error) . diagSeverity) ds) == errors -> do
          let opening = mkSpan (spanFile fsp) (spanStart fsp) (spanStart fsp + 3)
          unless (any (\d -> diagCode d == DiagnosticCode "G01031" && diagSpan d == opening) ds) $
            report (diagnostic "G01031" Info opening "::: で囲まなくても、直後の一つのブロックは本体になります")
    _ -> pure ()
  modify' (\st -> st {stBodyScopes = drop 1 (stBodyScopes st)})
  pure out

-- | Evaluate a bound body once, check its cardinality, then call its consumer.
bodyValues :: [A.Located A.Block] -> M [Block] -> ([Block] -> M [Block]) -> M [Block]
bodyValues input evaluate consume =
  gets (listToMaybe . stBodyScopes) >>= \case
    Just scope | scopeInput scope == input -> do
      result <- case scopeResult scope of
        Just cached -> pure cached
        Nothing -> do
          bs <- evaluate
          let tooMany = isNothing (scopeFence scope) && (length input > 1 || length bs > 1)
              site = case input of
                [] -> scopeCommand scope
                first : rest -> foldl (\a b -> mkSpan (spanFile a) (min (spanStart a) (spanStart b)) (max (spanEnd a) (spanEnd b))) (A.locSpan first) (map A.locSpan rest)
          when tooMany $ err "G02290" site "複数のブロックを本体にするには ::: で囲みます"
          let cached = if tooMany then Nothing else Just bs
          modify' (\st -> st {stBodyScopes = case stBodyScopes st of current : rest -> current {scopeResult = Just cached} : rest; [] -> []})
          pure cached
      maybe (pure []) consume result
    _ -> evaluate >>= consume

-- | Where .gm uses a name: an inline command, a block command, or an expression (root ADR 0451).
data Space = InlineSpace | BlockSpace | ExprSpace
  deriving stock (Eq, Ord, Show)

type M = State St

-- | A diagnostic of the file.
report :: Diagnostic -> M ()
report d = modify' (\s -> s {stDiags = stDiags s <> [d]})

err :: Text -> SrcSpan -> Text -> M ()
err code sp msg = report (diagnostic code Error sp msg)

{- | Why the evaluation cannot call a name of a .emet it has not loaded
(root ADR 0461): the evaluation of a file without manifest resolves no
@import; otherwise the .emet could not be loaded or checked.
-}
loadFailure :: EvalContext -> Unloaded
loadFailure ctx = case ctxImports ctx of
  UnresolvedImports -> NoManifest
  ResolvedImports _ -> EmetErrors

{- | A call of a name the evaluation cannot call, by the name it is written
with: G02279, G02280 or G02281 (root ADR 0461); it puts out nothing.
-}
unloadedCall :: Unloaded -> SrcSpan -> Text -> M [a]
unloadedCall why sp shown = report (unloadedDiagnostic why sp shown) >> pure []

{- | A name no command has where a plugin might have given one: G02282 at
its span after the plugins failed to load or to pass the checks, the
diagnostic otherwise (root ADR 0461).
-}
unknownName :: EvalContext -> Text -> Diagnostic -> M ()
unknownName ctx shown d
  | phFailed (ctxPlugins ctx) = err "G02282" (diagSpan d) ("プラグインの誤りのため、この名前のコマンドがあるかを決められません: " <> shown)
  | otherwise = report d

builtinInlineCommands :: [Text]
builtinInlineCommands = map builtinName allBuiltins

attributeCommands :: [Text]
attributeCommands = ["label", "toc-title", "number", "nonumber", "notoc", "style", "caption", "lang", "column-widths"]

-- | The shapes of kenten (golem-driver ADR 0019); an unknown one is G02039.
kentenShapes :: [Text]
kentenShapes = kentenShapeNames

reservedNames :: [Text]
reservedNames = ["doc", "meta", "vars", "true", "false", "nil"]

evalFile :: EvalContext -> A.File -> EvalResult
evalFile ctx0 (A.File fid blocks0) =
  let -- the file settings (docs/adr ADR 0014): @manifest over the [source] of the context, and @style-def
      (header, rest) = fileHeader blocks0
      (source, settingDiags) = fileSettings sourceKeys (ctxSource ctx0) header
      (local0, styleDiags) = fileStyles (ctxStyle ctx0) header
      -- @hyphenation-exceptions (docs/adr ADR 0272)
      (exceptions, exceptionDiags) = fileHyphenationExceptions header
      local = local0 {lsHyphenationExceptions = exceptions}
      ctx = (withFileStyles local ctx0) {ctxSource = source}
      blocks = paragraphBlocks source rest
      -- the styles of style.toml with those of the file over them
      fileStyle = withLocalStyles (ctxStyle ctx0) local
      -- meta and vars, which every file reads without @import (docs/adr/0185)
      st0 =
        (St Map.empty (Map.fromList [("meta", ctxMeta ctx), ("vars", ctxVars ctx)]) Map.empty [] Set.empty Map.empty [] 0 0 0 (settingDiags <> styleDiags <> exceptionDiags) Map.empty Map.empty [] [] [] [] Map.empty [] Set.empty Map.empty Map.empty [] Set.empty Set.empty Set.empty [])
          { stFileImports = rights (importsOf (A.File fid blocks0)),
            stSetNames = Set.fromList (concatMap setNames blocks0)
          }
      (bsEval, st) = runState (nextStyled ctx fileStyle blocks) st0
      (bsCollapsed, blankDiags) = collapseBlankLines (stBlankCounts st) bsEval
      -- the notes written by name take their bodies (docs/adr/0263)
      (bsNotes, footDiags) = namedNotes FootKind (stNoteRefs st) (stNoteDefs st) bsCollapsed
      -- the endnotes written by name, apart from the notes (root ADR 0412)
      (bs0, endDiags) = namedNotes EndKind (stEndnoteRefs st) (stEndnoteDefs st) bsNotes
      noteDiags = footDiags <> endDiags
      (bs, nestedDiags) = nestedBreaks bs0
      breakDiags = blankDiags <> nestedDiags <> conflictingBreaks bs
      doc0 = Document fid bs
      (doc, filterDiags) = case phApplyFilters (ctxPlugins ctx) (ctxPath ctx) doc0 of
        Left ds -> (doc0, ds)
        Right (d, ws) -> (fillFilterKenten ctx d, ws <> unknownParaStyles ctx d <> functionFilterNames ctx d)
      -- the regex styles last, so that the text of filters is matched too (docs/adr ADR 0015)
      rules = regexRules fileStyle
      -- the first characters after them, so that the regex styles match the text as written (docs/adr/0374)
      styled = applyInitialStyles fileStyle (applyRegexStyles rules doc)
   in EvalResult
        { erDocument = styled,
          erExports = stVars st,
          erUsage = Usage (stDefined st) (stRefs st) (stNsRefs st) (stImports st) (stListedSites st) (stListedRefs st) (fileOverrides (ctxFunctions ctx) (ctxPlugins ctx) (A.File fid blocks0)),
          erDiagnostics = stDiags st <> noteDiags <> breakDiags <> filterDiags <> unwritableText styled,
          erSource = ctxSource ctx,
          erStyles = local,
          erNumberSites = stNumberSites st,
          erImages = stImages st
        }

{- | The blocks at the top of a file evaluated in order (docs/adr/0374):
a paragraph without a paragraph style written takes the next-style of the
paragraph style of the block right before it in the result, when that
block is a paragraph. A block that puts out nothing (a variable) is not
counted; any other block between them, a break of the attributes of the
paragraph included, leaves the paragraph in body. The paragraph is
evaluated as the body form of @style, so that a style that keeps its
lines keeps those of the paragraph.

Paragraph boundaries have already been fixed by 'paragraphBlocks'
(root ADR 0473). Each block is normalized right before evaluation, so
that the names earlier @import lines override are known (root ADR 0471).
-}
nextStyled :: EvalContext -> Style -> [A.Located A.Block] -> M [Block]
nextStyled ctx style = nextStyledFrom ctx style Nothing

nextStyledFrom :: EvalContext -> Style -> Maybe Text -> [A.Located A.Block] -> M [Block]
nextStyledFrom ctx style = go
  where
    go _ [] = pure []
    go next (b : bs) = do
      isBuiltin <- builtinBlockAt ctx
      (out, next') <- lines' isBuiltin next [b]
      (out <>) <$> go next' bs
    lines' _ next [] = pure ([], next)
    lines' isBuiltin next (b : bs) = do
      let b' = case next of
            Just n | implicit isBuiltin b -> withStyle n b
            _ -> b
      out <- evalBlock ctx (normalizeBlock isBuiltin b')
      let next' = followingStyle style next out
      Bi.first (out <>) <$> lines' isBuiltin next' bs
    implicit isBuiltin = \case
      A.Located _ (A.Paragraph _) -> True
      A.Located _ (A.Attributed cmds (Just (A.Located _ (A.Paragraph _)))) -> not (any (\c -> isStyleCommand isBuiltin c || isBreakCommand isBuiltin c || isSettingCommand c) cmds)
      _ -> False

-- | The last emitted paragraph or heading supplies the next paragraph style; empty output leaves it alone.
followingStyle :: Style -> Maybe Text -> [Block] -> Maybe Text
followingStyle style previous out = case reverse out of
  [] -> previous
  Block {blockBody = Paragraph st _} : _ -> paraStyleWith style (styleRefNameOf st) (maybe [] refValues st) >>= psNextStyle
  Block {blockBody = Heading level _ _} : _ -> headingParaStyle style level >>= psNextStyle
  _ -> Nothing

-- | The synthetic built-in @style cannot be overridden by a source command.
styleCommand :: SrcSpan -> Text -> [A.Located A.Block] -> A.Block
styleCommand sp n = A.BlockCommand (A.Located sp nextStyleName) [A.Located sp (A.Positional (A.Word n))]

withStyle :: Text -> A.Located A.Block -> A.Located A.Block
withStyle n (A.Located sp b) = A.Located sp $ case b of
  A.Paragraph is -> styleCommand sp n [A.Located sp (A.Paragraph is)]
  A.Attributed cmds t -> A.Attributed (cmds <> [A.Located sp (styleCommand sp n [])]) t
  other -> other

{- | The context with the styles of the file over those of style.toml
(docs/adr ADR 0014): its character styles added, and whether each
paragraph style keeps its lines resolved again, as an override may change
the styles based on it.
-}
withFileStyles :: LocalStyles -> EvalContext -> EvalContext
withFileStyles local ctx
  | local == noLocalStyles = ctx {ctxLocalStyles = local}
  | otherwise =
      ctx
        { ctxLocalStyles = local,
          ctxCharStyles = Set.union (Map.keysSet (lsCharStyles local)) (ctxCharStyles ctx),
          ctxParaStyles = Map.union (paraLineBreaks (withLocalStyles (ctxStyle ctx) local)) (ctxParaStyles ctx)
        }

-- ------------------------------------------------------------------ characters for the output

{- | G02089 at each string of the IR with a character that cannot be
written to the output (docs/adr ADR 0042): the text of paragraphs,
headings, lists, table cells, code, figures and notes, whatever the
target. One for each string, naming its first such character; the lines
of a code block are one string at the block.
-}
unwritableText :: Document -> [Diagnostic]
unwritableText = concatMap blockDiags . docBlocks
  where
    at sp t = case firstUnwritable t of
      Just c -> [diagnostic "G02089" Error sp ("出力に書けない文字（" <> codePointText c <> "）があります")]
      Nothing -> []
    blockDiags (Block sp _ _ b) = case b of
      Paragraph _ is -> inlines is
      Heading _ attrs is -> maybe [] inlines (haTocTitle attrs) <> inlines is
      BulletList items -> concatMap (concatMap blockDiags . itemBlocks) items
      OrderedList items -> concatMap (concatMap blockDiags . itemBlocks) items
      DefList groups -> concat [concatMap inlines (dgTerms g) <> concatMap (concatMap blockDiags) (dgDefs g) | g <- groups]
      TableBlock t -> maybe [] inlines (tableCaption t) <> concatMap inlines (tableHeader t) <> concatMap (concatMap inlines) (tableRows t)
      CodeBlock c -> maybe [] (at sp) (codeFile c) <> maybe [] inlines (codeCaption c) <> at sp (codeText c)
      FigureBlock f -> at sp (figAlt f) <> concatMap blockDiags (figCaption f)
      ChannelOutput _ -> []
      ForcedBreak _ -> []
      PageControl _ -> []
      BlankLines _ -> []
      Separator _ -> []
      FrameBlock _ bs -> concatMap blockDiags bs
    inlines :: [InlineF r] -> [Diagnostic]
    inlines = concatMap inline
    inline :: InlineF r -> [Diagnostic]
    inline = \case
      Text sp t -> at sp t
      Ruby sp _ segs -> concat [inlines (rsBase g) <> maybe [] (at sp) (rsReading g) <> maybe [] (at sp) (rsOtherReading g) | g <- segs]
      Kenten _ _ xs -> inlines xs
      Color _ _ xs -> inlines xs
      CharStyle _ _ xs -> inlines xs
      Tcy sp t -> at sp t
      Warichu sp t -> at sp t
      Upright sp t -> at sp t
      Note _ _ _ bs -> concatMap inlines (noteParagraphs bs)
      Sidenote _ _ _ bs -> concatMap inlines (noteParagraphs bs)
      Endnote _ _ _ bs -> concatMap inlines (noteParagraphs bs)
      IndexMark sp e -> concatMap (at sp) (ieTerms e <> ieReadings e <> case ieKind e of IndexSee _ ts -> ts; _ -> [])
      ProofComment sp t -> at sp t
      Number {} -> []
      Ref {} -> []
      Deferred {} -> []
      -- the text of a page is written (docs/adr/0266)
      Cite sp items -> concat [at sp t | Just (Locator _ (LocText t)) <- map citLocator items] <> inlines (citeInlines items)
      LineBreak {} -> []
      Aki {} -> []
      ChannelItem sp c -> concatMap (at sp) (ciChannel c : maybe [] pure (ciKey c) <> maybe [] pure (ciReading c)) <> inlines (ciBody c)
      Link _ _ xs -> inlines xs
      Lang _ _ xs -> inlines xs
      Resolved _ _ _ xs -> inlines xs

-- ------------------------------------------------------------------ newlines

{- | 'A.SoftBreak' removed and the neighbouring 'A.Text' joined into one,
whose span covers both (docs/adr ADR 0003). Inlines nested in commands
are joined too.
-}
joinSoftBreaks :: [A.Located A.Inline] -> [A.Located A.Inline]
joinSoftBreaks = mergeLocated . dropSoft False . map nestedInline
  where
    -- 'A.HardBreak' stays (docs/adr ADR 0016), and so does a newline right
    -- after it: the line after the hard break is empty, which the
    -- evaluation reports
    dropSoft afterHard = \case
      [] -> []
      (x : rest)
        | isSoftBreak x && not afterHard -> dropSoft False rest
        | otherwise -> x : dropSoft (isHardBreak x) rest

isSoftBreak :: A.Located A.Inline -> Bool
isSoftBreak (A.Located _ A.SoftBreak) = True
isSoftBreak _ = False

isHardBreak :: A.Located A.Inline -> Bool
isHardBreak (A.Located _ A.HardBreak) = True
isHardBreak _ = False

mergeLocated :: [A.Located A.Inline] -> [A.Located A.Inline]
mergeLocated (A.Located a (A.Text x) : A.Located b (A.Text y) : rest) =
  mergeLocated (A.Located (mkSpan (spanFile a) (spanStart a) (spanEnd b)) (A.Text (x <> y)) : rest)
mergeLocated (x : rest) = x : mergeLocated rest
mergeLocated [] = []

-- | The newlines inside an inline (its slots and arguments) are dropped.
nestedInline :: A.Located A.Inline -> A.Located A.Inline
nestedInline (A.Located sp i) = A.Located sp $ case i of
  A.Command n args slots -> A.Command n (map normalizeArg args) (map joinSoftBreaks slots)
  other -> other

normalizeArg :: A.Located A.Argument -> A.Located A.Argument
normalizeArg (A.Located sp a) = A.Located sp $ case a of
  A.Positional v -> A.Positional (argV v)
  A.Keyword k v -> A.Keyword k (argV v)
  other -> other
  where
    argV = \case
      A.CommandArg x -> A.CommandArg (nestedInline x)
      v -> v

{- | Every inline sequence of a block with its newlines dropped, except the
paragraphs a paragraph style is given to, which keep them at the top
level (docs/adr ADR 0005): the paragraphs of the body of @style, of its
lists and of the @lang and groups in it (root ADR 0460), and the next
paragraph of a group, which the line style splits when the group is
evaluated (root ADR 0459). The bodies of @style and @figure are told by
the built-in command they call (root ADR 0471).
-}
normalizeBlock :: (Text -> Bool) -> A.Located A.Block -> A.Located A.Block
normalizeBlock isBuiltin lb@(A.Located sp b) = A.Located sp $ case b of
  A.Paragraph is -> A.Paragraph (joinSoftBreaks is)
  A.Heading l is -> A.Heading l (joinSoftBreaks is)
  A.BulletList items -> A.BulletList (map (map normalize) items)
  A.OrderedList items -> A.OrderedList (map (map normalize) items)
  A.DefList gs -> A.DefList [A.DefGroup (map joinSoftBreaks ts) (map (map normalize) ds) | A.DefGroup ts ds <- gs]
  A.Table al h rows -> A.Table al (map joinSoftBreaks h) (map (map joinSoftBreaks) rows)
  A.BlockCommand n args body
    | builtinCommand isBuiltin lb == Just "style" -> A.BlockCommand n (map normalizeArg args) (map (styledBlock isBuiltin) body)
    -- the newlines of a caption are left to the paragraph style caption (docs/adr/0367)
    | builtinCommand isBuiltin lb == Just "figure" -> A.BlockCommand n (map normalizeArg args) (map captionBody body)
    | otherwise -> A.BlockCommand n (map normalizeArg args) (map normalize body)
  A.Attributed cs t
    | any (isStyleCommand isBuiltin) cs -> A.Attributed (map (styledBlock isBuiltin) cs) (styledBlock isBuiltin <$> t)
    | otherwise -> A.Attributed (map normalize cs) (nextBody <$> t)
  -- Boundaries are fixed already; the receiver still decides how internal newlines are drawn.
  A.Fenced closed bs -> A.Fenced closed (map (styledBlock isBuiltin) bs)
  other -> other
  where
    normalize = normalizeBlock isBuiltin
    captionBody = \case
      A.Located psp (A.Paragraph is) -> A.Located psp (A.Paragraph (map nestedInline is))
      other -> normalize other
    nextBody = \case
      A.Located psp (A.Paragraph is) -> A.Located psp (A.Paragraph (map nestedInline is))
      other -> normalize other

{- | A block of the body of @style, its paragraphs with their newlines
(root ADR 0460): those of lists, definitions, @lang, groups and the
blocks between ::: lines too. The built-in @lang alone (root ADR 0471).
-}
styledBlock :: (Text -> Bool) -> A.Located A.Block -> A.Located A.Block
styledBlock isBuiltin lb@(A.Located sp b) = case b of
  A.Paragraph is -> A.Located sp (A.Paragraph (map nestedInline is))
  A.BulletList items -> A.Located sp (A.BulletList (map (map styled) items))
  A.OrderedList items -> A.Located sp (A.OrderedList (map (map styled) items))
  A.DefList gs -> A.Located sp (A.DefList [A.DefGroup (map joinSoftBreaks ts) (map (map styled) ds) | A.DefGroup ts ds <- gs])
  A.BlockCommand n args body | isLangCommand isBuiltin lb -> A.Located sp (A.BlockCommand n (map normalizeArg args) (map styled body))
  A.Attributed cs t -> A.Located sp (A.Attributed (map styled cs) (styled <$> t))
  A.Fenced closed bs -> A.Located sp (A.Fenced closed (map styled bs))
  _ -> normalizeBlock isBuiltin lb
  where
    styled = styledBlock isBuiltin

-- | A block that calls the built-in @style (root ADR 0471).
isStyleCommand :: (Text -> Bool) -> A.Located A.Block -> Bool
isStyleCommand isBuiltin c = builtinCommand isBuiltin c == Just "style"

-- ------------------------------------------------------------------ the line style

{- | Normalize paragraph boundaries before binding bodies (root ADR 0473).
Only the source paragraph separator and hard breaks determine the boundary;
command names, paragraph styles and the next style are not inputs.
-}
paragraphBlocks :: SourceSettings -> [A.Located A.Block] -> [A.Located A.Block]
paragraphBlocks source = concatMap normalize
  where
    normalize lb@(A.Located sp value) = case value of
      A.Paragraph is | ssParagraphSeparator source == LineSeparated -> splitParagraph is
      A.BulletList items -> [A.Located sp (A.BulletList (map (paragraphBlocks source) items))]
      A.OrderedList items -> [A.Located sp (A.OrderedList (map (paragraphBlocks source) items))]
      A.DefList groups -> [A.Located sp (A.DefList [A.DefGroup terms (map (paragraphBlocks source) definitions) | A.DefGroup terms definitions <- groups])]
      A.BlockCommand name args body -> [A.Located sp (A.BlockCommand name args (paragraphBlocks source body))]
      A.Fenced closed body -> [A.Located sp (A.Fenced closed (paragraphBlocks source body))]
      A.Attributed commands target ->
        let commands' = paragraphBlocks source commands
         in case maybe [] normalize target of
              [] -> [A.Located sp (A.Attributed commands' Nothing)]
              first : rest -> A.Located (mkSpan (spanFile sp) (spanStart sp) (spanEnd (A.locSpan first))) (A.Attributed commands' (Just first)) : rest
      _ -> [lb]

{- | The lines of a paragraph as paragraphs: spaces and tabs at the start of
each line are not text (the ideographic space is), and a line left empty
is dropped.
-}
splitParagraph :: [A.Located A.Inline] -> [A.Located A.Block]
splitParagraph = concatMap paragraph . chunks
  where
    chunks xs = case break isSoftBreak xs of
      (l, []) -> [l]
      (l, _ : rest) -> l : chunks rest
    -- the escapes are text before the spaces are dropped (golem-parser ADR 0010)
    paragraph l = case trimStart (A.plainEscapes l) of
      [] -> []
      is@(A.Located first _ : _) ->
        let A.Located lastSp _ = last is
         in [A.Located (mkSpan (spanFile first) (spanStart first) (spanEnd lastSp)) (A.Paragraph is)]
    trimStart = \case
      (A.Located tsp (A.Text t) : rest) ->
        let t' = T.dropWhile (\c -> c == ' ' || c == '\t') t
            -- the characters dropped are one byte each
            tsp' = mkSpan (spanFile tsp) (spanStart tsp + T.length t - T.length t') (spanEnd tsp)
         in [A.Located tsp' (A.Text t') | not (T.null t')] <> rest
      is -> is

-- ------------------------------------------------------------------ blocks

env :: M Env
env = gets (\s -> Env (Map.union (stVars s) (stListedVars s)) (stNamespaces s) (stFunctions s) (Map.fromList [(n, r) | ((ExprSpace, n), r) <- Map.toList (stListedFns s)]) (stUnresolvedVars s) (stUnresolvedNamespaces s))

block :: SrcSpan -> BlockBody -> Block
block sp = Block sp Nothing Nothing

evalBlock :: EvalContext -> A.Located A.Block -> M [Block]
evalBlock ctx lb@(A.Located sp (A.BlockCommand _ _ body)) | not (null body) = do
  existing <- gets (listToMaybe . stBodyScopes)
  if maybe False (\scope -> scopeCommand scope == sp && scopeInput scope == body) existing
    then evalBlockRaw ctx lb
    else withBodyScope sp Nothing False body (evalBlockRaw ctx lb)
evalBlock ctx lb = evalBlockRaw ctx lb

evalBlockRaw :: EvalContext -> A.Located A.Block -> M [Block]
evalBlockRaw ctx (A.Located sp b) = case b of
  A.Separator name -> pure [block sp (Separator name)]
  -- items, definitions and captions break their lines by the same rule (docs/adr ADR 0016)
  A.Paragraph is -> styledParagraph ctx sp Nothing is
  A.Heading l is -> one . Heading l noHeadingAttrs <$> evalInlines ctx True is
  A.BulletList items -> one . BulletList <$> mapM (fmap (ListItem Nothing) . evalBlocks ctx) items
  A.OrderedList items -> one . OrderedList <$> mapM (fmap (ListItem Nothing) . evalBlocks ctx) items
  A.DefList gs -> one . DefList <$> mapM (\(A.DefGroup ts ds) -> DefGroup <$> mapM (evalInlines ctx False) ts <*> mapM (evalBlocks ctx) ds) gs
  A.Table al h rows -> do
    h' <- mapM (evalInlines ctx False) h
    rows' <- mapM (mapM (evalInlines ctx False)) rows
    pure [block sp (TableBlock (plainTable (map alignment al) h' rows'))]
  A.CodeBlock lang args0 ls ->
    prepareArgs args0 >>= \case
      Nothing -> pure []
      Just args -> do
        ca <- codeArgs ctx sp [] args
        c <- codeOf sp ca Nothing lang True [(lsp, t) | A.Located lsp t <- ls]
        pure [block sp (CodeBlock c)]
  A.SetVar (A.Located nsp n) e -> do
    defined <- gets (Map.member n . stVars)
    if n `elem` reservedNames
      then err "G02023" nsp ("予約語は変数の名前に使えません: " <> n)
      else
        if defined
          then err "G02024" nsp ("変数を二度定義しています: " <> n)
          else do
            noteRefs e
            en <- env
            case evalAnalysed en e of
              Left d -> report d
              Right v -> modify' (\s -> s {stVars = Map.insert n v (stVars s), stDefined = stDefined s <> [(n, nsp)]})
    pure []
  A.BlockCommand name@(A.Located _ n) args body
    -- @manifest and @style-def read their own arguments (docs/adr ADR 0132)
    | n `elem` settingCommands -> standalone ctx sp name args body
    -- @import is read as written, as the project reads it: a spread is G03009 (docs/adr ADR 0142)
    | n == "import" -> standalone ctx sp name args body
    | otherwise -> do
        -- the checks of the arguments of @style and @listing, when the built-in command is called (root ADR 0471)
        called' <- (\isBuiltin -> builtinCommand isBuiltin (A.Located sp b)) <$> builtinBlockAt ctx
        case called' of
          -- @style is read before the evaluation for the lines of its body: G02114 at each spread (docs/adr ADR 0112, ADR 0143)
          -- the body is put out without the style, as the next block of the attribute form was (root ADR 0459)
          Just "style" | ssps@(_ : _) <- spreadsOf args -> mapM_ (report . styleSpread) ssps >> evalBlocks ctx body
          Just "listing"
            | srcDuplicates@(_ : _) <- [(asp, k) | (asp, k) <- repeatedKeys args, k == "src"] -> do
                mapM_ (\(asp, k) -> err "G02077" asp ("同じキーを二度書いています: " <> k)) srcDuplicates
                pure []
          _ -> prepareArgs args >>= maybe (pure []) (\args' -> standalone ctx sp name args' body)
  A.Attributed cmds target -> attributed ctx Nothing sp cmds target
  A.Fenced _ bs -> evalBlocks ctx bs
  A.ErrorBlock -> pure []
  where
    one x = [block sp x]

evalBlocks :: EvalContext -> [A.Located A.Block] -> M [Block]
evalBlocks ctx bs = concat <$> mapM (evalBlock ctx) bs

alignment :: A.Alignment -> Alignment
alignment = \case
  A.AlignDefault -> AlignDefault
  A.AlignLeft -> AlignLeft
  A.AlignCenter -> AlignCenter
  A.AlignRight -> AlignRight

{- | A block command that is not an attribute of another block. An
overridable built-in one is looked up first in the overrides of the
plugins, then among the names the file lists by @import (root ADR 0453,
root ADR 0471): a listed name that puts out nothing does not fall back to
the built-in one. The @style the evaluation makes for a next-style calls
the built-in one whatever the file overrides (root ADR 0471).
-}
standalone :: EvalContext -> SrcSpan -> A.Located A.Name -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
standalone ctx sp lname@(A.Located nsp name) args body
  | name == nextStyleName = builtinBlock ctx sp (A.Located nsp "style") args body
  | Just o <- parseOverridableBlock name, Just pb <- Map.lookup o (phBlockOverrides (ctxPlugins ctx)) = pluginBlock ctx sp pb args body
  | Just _ <- parseOverridableBlock name =
      listedFunction BlockSpace name >>= \case
        Nothing -> builtinBlock ctx sp lname args body
        Just (Loaded fns) | Just f <- Map.lookup name (fnBlock fns) -> callBlock ctx sp ("@" <> name) f args body
        Just (Unloaded why) -> unloadedCall why nsp ("@" <> name)
        Just (Loaded _) -> pure []
  | otherwise = builtinBlock ctx sp lname args body

{- | The name of the @style the evaluation makes for a next-style
(docs/adr/0374), which no name written can be: it calls the built-in
@style whatever the file overrides (root ADR 0471 I8).
-}
nextStyleName :: Text
nextStyleName = "@style"

{- | Whether a block command of a name calls the built-in command where it
is evaluated (root ADR 0471): neither a plugin's block-overrides nor a
name listed by @import before it overrides the name. The handling of the
built-in commands by their names is applied only then. The @style of a
next-style is the built-in one.
-}
builtinBlockAt :: EvalContext -> M (Text -> Bool)
builtinBlockAt ctx = do
  listedFns <- gets stListedFns
  let overridden n = isJust (parseOverridableBlock n >>= (`Map.lookup` phBlockOverrides (ctxPlugins ctx))) || Map.member (BlockSpace, n) listedFns
  pure (\n -> n == nextStyleName || not (overridden n))

{- | The built-in block command a block calls: its name, and style for the
@style of a next-style; Nothing for a block that is no block command, or
one whose name is overridden where it is (root ADR 0471).
-}
builtinCommand :: (Text -> Bool) -> A.Located A.Block -> Maybe Text
builtinCommand isBuiltin = \case
  A.Located _ (A.BlockCommand (A.Located _ n) _ _)
    | not (isBuiltin n) -> Nothing
    | n == nextStyleName -> Just "style"
    | otherwise -> Just n
  _ -> Nothing

-- | A block command of the language, a plugin or a function, after the overrides.
builtinBlock :: EvalContext -> SrcSpan -> A.Located A.Name -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
builtinBlock ctx sp (A.Located nsp name) args body = case name of
  "import" -> do
    -- the same check as the project's (golem-project ADR 0006); G02023 points at the namespace
    case importSite sp args of
      Right (ImportSite path (ImportNames names) _) -> listedImport ctx sp path names
      Right (ImportSite path (ImportAll ns nssp) _) -> do
        if ns `elem` reservedNames
          then err "G02023" nssp ("予約語は名前空間に使えません: " <> ns)
          else
            if ".emet" `T.isSuffixOf` path
              then -- the functions of a .emet (docs/adr/0162)
                let table = ctxFunctions ctx
                    ref = case normalizeRelative (T.unpack path) >>= \p -> maybe (Left Missing) Right (Map.lookup p (ftFiles table)) of
                      Right fns | not (ftUnloaded table) -> Loaded fns
                      _ -> Unloaded (loadFailure ctx)
                 in modify' (\s -> s {stFunctions = Map.insert ns ref (stFunctions s), stImports = stImports s <> [(ns, T.unpack path, sp)]})
              else do
                -- a namespace of an @import the evaluation does not resolve: each reference is G02281 (root ADR 0455, root ADR 0461)
                let vals = importedVars ctx path
                    unresolvedNs = if isNothing vals then Set.insert ns else Set.delete ns
                modify' (\s -> s {stNamespaces = Map.insert ns (fromMaybe Map.empty vals) (stNamespaces s), stImports = stImports s <> [(ns, T.unpack path, sp)], stUnresolvedNamespaces = unresolvedNs (stUnresolvedNamespaces s)})
      Left d -> report d
    pure []
  "toc" -> do
    depth <- maybe (pure (Right 2)) (naturalArg ctx "@toc の depth" sp) (keywordAt "depth" args)
    case depth of
      Right d | d >= 1 && d <= 6 -> pure [block sp (ChannelOutput (TocOutput (fromIntegral d)))]
      Left NaturalReported -> pure []
      _ -> err "G02025" sp "@toc の depth は 1 から 6 の整数です" >> pure []
  -- the body of a note of more than one paragraph (docs/adr/0263)
  "note" -> noteDefinition ctx FootKind sp args body
  -- the body of an endnote of more than one paragraph (root ADR 0412)
  "endnote" -> noteDefinition ctx EndKind sp args body
  "index" -> pure [block sp (ChannelOutput IndexOutput)]
  "bibliography" -> pure [block sp (ChannelOutput BibliographyOutput)]
  "channel" -> channelBlock ctx sp args
  "printings" -> printingsBlock ctx sp args body
  "separator" -> case (map A.locValue args, body) of
    ([A.Positional v], []) | Just name' <- nameArg v, not (T.null name') -> pure [block sp (Separator name')]
    _ -> err "G02158" sp "@separator には名前を一つ書き、本体は付けません" >> pure []
  -- a text frame named in style.toml, holding paragraphs (root ADR 0438)
  "frame" -> frameBlock ctx sp args body
  "page-break" -> forcedBreak sp name args body
  "column-break" -> forcedBreak sp name args body
  "no-page-break" -> noPageBreak ctx sp args body
  "need-lines" -> needLines ctx sp name args body
  "page-lines" -> pageControl sp name args body
  "blank-line" -> blankLine ctx sp args body
  "figure" -> figure ctx sp args body
  "table" -> csvTable ctx sp args
  "listing" -> listing ctx sp args
  "style" -> styleBody ctx sp (maximum (spanEnd nsp : map (spanEnd . A.locSpan) args)) args body
  "lang" | not (null body) -> langBody ctx sp args body
  -- the file settings are read before the blocks; elsewhere they are errors (docs/adr ADR 0014)
  _ | name `elem` settingCommands -> misplacedSetting sp >> pure []
  _
    | name `elem` attributeCommands -> err "G02010" sp ("@" <> name <> " の後にブロックがありません") >> pure []
    | Just pb <- Map.lookup name (phBlocks (ctxPlugins ctx)) -> pluginBlock ctx sp pb args body
    | Just (ns, n) <- splitNamespace name -> functionBlock ctx sp nsp ns n args body
    | otherwise ->
        -- a block command listed by @import (root ADR 0451)
        listedFunction BlockSpace name >>= \case
          Nothing -> unknownName ctx ("@" <> name) (diagnostic "G02009" Error nsp ("未知のブロックコマンドです: @" <> name)) >> pure []
          Just (Loaded fns) | Just f <- Map.lookup name (fnBlock fns) -> callBlock ctx sp ("@" <> name) f args body
          Just (Unloaded why) -> unloadedCall why nsp ("@" <> name)
          Just (Loaded _) -> pure []

{- | The names of the variables a file sets, wherever they are, for G02274
(root ADR 0451): an @import clashes with a @set before it or after it.
-}
setNames :: A.Located A.Block -> [Text]
setNames (A.Located _ b) = case b of
  A.SetVar (A.Located _ n) _ -> [n]
  A.BulletList items -> concatMap (concatMap setNames) items
  A.OrderedList items -> concatMap (concatMap setNames) items
  A.DefList gs -> concatMap (concatMap (concatMap setNames) . A.dgDefs) gs
  A.BlockCommand _ _ body -> concatMap setNames body
  A.Attributed cmds t -> concatMap setNames cmds <> maybe [] setNames t
  A.Fenced _ bs -> concatMap setNames bs
  _ -> []

-- | A function listed by @import in a space of use, its use noted for the lint (G05003, root ADR 0451).
listedFunction :: Space -> Text -> M (Maybe FunctionRef)
listedFunction space name = do
  r <- gets (Map.lookup (space, name) . stListedFns)
  when (isJust r) (modify' (\s -> s {stListedRefs = Set.insert name (stListedRefs s)}))
  pure r

{- | What a path an @import lists names of gives (root ADR 0451): the
functions of a .emet, the variables of a .gm, or nothing to check for a
.emet that could not be loaded, with why its names cannot be called, and
for a variable file whose @import the evaluation does not resolve, whose
references in the expressions are G02281 (root ADR 0455, root ADR 0461).
-}
data ListedSource = FromEmet !FunctionNamespace | FromVars !(Map Text Value) | Unchecked !Unloaded | UnresolvedVars

listedSource :: EvalContext -> Text -> ListedSource
listedSource ctx path
  | ".emet" `T.isSuffixOf` path =
      let table = ctxFunctions ctx
       in case normalizeRelative (T.unpack path) >>= \p -> maybe (Left Missing) Right (Map.lookup p (ftFiles table)) of
            Right fns | not (ftUnloaded table) -> FromEmet fns
            _ -> Unchecked (loadFailure ctx)
  | otherwise = maybe UnresolvedVars FromVars (importedVars ctx path)

-- | The spaces of use a source gives a name in; Nothing for one that is not checked.
listedSpaces :: ListedSource -> Text -> Maybe [Space]
listedSpaces src n = case src of
  FromEmet fns -> Just ([InlineSpace | Map.member n (fnInline fns)] <> [BlockSpace | Map.member n (fnBlock fns)] <> [ExprSpace | Map.member n (fnExpr fns)])
  FromVars vals -> Just [ExprSpace | Map.member n vals]
  Unchecked _ -> Nothing
  UnresolvedVars -> Nothing

{- | The names of the built-in commands a listed name may not override, by
space of use (G02270, root ADR 0453).
-}
builtinNamesIn :: Space -> [Text]
builtinNamesIn = \case
  InlineSpace -> []
  BlockSpace -> fixedBlockCommands
  ExprSpace -> []

{- | An @import of names (root ADR 0451, root ADR 0458): each item is
checked, then its alias is put in the spaces of use its source gives the
original name, bound to the definition of the original name. The checks
of an item stop at the first that falls: a reserved alias is G02275, an
original name the source does not give G02276, an alias that breaks the
rules of the names of a space of use of the original name G02278 (none
for a source that is not checked). Otherwise each kind of clash of the
alias gives its code once: a built-in command (G02270), a command of a
plugin (G02271), an alias another @import lists (G02272, at both), an
alias before it in the list (G02273), a variable the file sets (G02274),
a built-in name of the expressions (G02277). An alias that clashes with
another @import is put in as one whose calls are G02280, so that the
order of the @import lines changes nothing; one that clashes with a name
of the language or a variable is left out of that space.
-}
listedImport :: EvalContext -> SrcSpan -> Text -> [ListedName] -> M ()
listedImport ctx sp path items = do
  others <- gets (filter ((/= sp) . isSpan) . stFileImports)
  set <- gets stSetNames
  let src = listedSource ctx path
      -- the overrides the plugins declare count as their commands (root ADR 0453)
      pluginNames = \case
        InlineSpace -> map unPluginCommandName (Map.keys (phCommands (ctxPlugins ctx))) <> map builtinName (Map.keys (phOverrides (ctxPlugins ctx)))
        BlockSpace -> Map.keys (phBlocks (ctxPlugins ctx)) <> map overridableBlockName (Map.keys (phBlockOverrides (ctxPlugins ctx)))
        ExprSpace -> []
      -- the spaces of use of the items of the other @import lines under an alias, of those that pass their own checks
      otherSpaces a = concat [spaces | o <- others, l <- importNames o, lnAlias l == a, Just spaces <- [admitted (listedSource ctx (isPath o)) l]]
      one (i, l@(ListedName n nsp a asp))
        | a `elem` reservedNames = err "G02275" asp ("予約語は取り込む名前に使えません: " <> a)
        | otherwise = case listedSpaces src n of
            -- a variable of an @import not resolved: only its references in the expressions are G02281 (root ADR 0455, root ADR 0461)
            Nothing | UnresolvedVars <- src -> do
              note l
              modify' (\st -> st {stUnresolvedVars = Set.insert a (stUnresolvedVars st)})
            Nothing -> do
              note l
              mapM_ (\s -> put' s a (Unloaded (uncheckedWhy src))) [InlineSpace, BlockSpace, ExprSpace]
            Just [] -> err "G02276" nsp (path <> " が公開していない名前です: " <> n)
            Just spaces
              | not (all (`aliasShape` a) spaces) -> err "G02278" asp ("別名の形が不正です: " <> a)
              | otherwise -> do
                  note l
                  let earlier = or [True | e <- take i items, lnAlias e == a, isJust (admitted src e)]
                      clashes s =
                        [("G02270", "上書きできない組み込みのコマンドと同じ名前は取り込めません: " <> a) | a `elem` builtinNamesIn s]
                          <> [("G02271", "プラグインのコマンドと同じ名前は取り込めません: " <> a) | a `elem` pluginNames s]
                          <> [("G02272", "ほかの @import が並べた名前と同じです: " <> a) | s `elem` otherSpaces a]
                          <> [("G02273", "同じ並びに二度書いた名前です: " <> a) | earlier]
                          <> [("G02274", "@set の変数と同じ名前は取り込めません: " <> a) | s == ExprSpace, a `Set.member` set]
                          <> [("G02277", "組み込みの式の名前と同じ名前は取り込めません: " <> a) | s == ExprSpace, a `elem` builtinExpressionNames]
                      codes = concatMap clashes spaces
                  mapM_ (\(c, m) -> err c asp m) (Map.toList (Map.fromList codes))
                  forM_ spaces $ \s -> do
                    let cs = map fst (clashes s) :: [Text]
                        kept
                          | any (`elem` cs) ["G02270", "G02271", "G02274", "G02277"] = pure ()
                          | "G02272" `elem` cs = put' s a (Unloaded ImportClash)
                          | otherwise = case src of
                              FromEmet fns -> put' s a (Loaded (renamed n a fns))
                              FromVars vals -> mapM_ (\v -> modify' (\st -> st {stListedVars = Map.insert a v (stListedVars st)})) (Map.lookup n vals)
                              Unchecked _ -> pure ()
                              UnresolvedVars -> pure ()
                    kept
  mapM_ one (zip [0 :: Int ..] items)
  where
    note (ListedName n _ a asp) = modify' (\s -> s {stListedSites = stListedSites s <> [(a, n, T.unpack path, asp)]})
    uncheckedWhy = \case
      Unchecked why -> why
      _ -> EmetErrors
    put' s a ref = modify' (\st -> st {stListedFns = Map.insert (s, a) ref (stListedFns st)})

{- | The spaces of use an item of a source is put in under its alias, when
it passes the checks of its own (G02275, G02276, G02278); an empty list
for a source that is not checked (root ADR 0458).
-}
admitted :: ListedSource -> ListedName -> Maybe [Space]
admitted src (ListedName n _ a _)
  | a `elem` reservedNames = Nothing
  | otherwise = case listedSpaces src n of
      Nothing -> Just []
      Just [] -> Nothing
      Just spaces
        | all (`aliasShape` a) spaces -> Just spaces
        | otherwise -> Nothing

{- | Whether an alias keeps the rules of the names of a space of use (root
ADR 0458, G02278): those of the commands of .gm in the inline and the
block spaces (a lowercase letter, then lowercase letters, digits and -),
those of the expressions in theirs (a letter or _, then letters, digits
and _).
-}
aliasShape :: Space -> Text -> Bool
aliasShape s a = case (s, T.uncons a) of
  (ExprSpace, Just (c, rest)) -> (letter c || c == '_') && T.all (\x -> letter x || isDigit x || x == '_') rest
  (_, Just (c, rest)) -> isAsciiLower c && T.all (\x -> isAsciiLower x || isDigit x || x == '-') rest
  (_, Nothing) -> False
  where
    letter x = isAsciiLower x || isAsciiUpper x

{- | The definitions of the original name of a .emet under an alias (root
ADR 0458): a call under the alias finds the function of the original
name, and no other.
-}
renamed :: Text -> Text -> FunctionNamespace -> FunctionNamespace
renamed n a fns = FunctionNamespace (pick (fnInline fns)) (pick (fnBlock fns)) (pick (fnExpr fns)) (pick (fnOthers fns))
  where
    pick :: Map Text v -> Map Text v
    pick m = maybe Map.empty (Map.singleton a) (Map.lookup n m)

{- | A block command of a plugin (docs/adr/0122): its arguments as a plugin
command's, its body evaluated as blocks. An argument beyond int64 is
G02091 and the plugin is not called.
-}
pluginBlock :: EvalContext -> SrcSpan -> PluginBlockCommand -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
pluginBlock ctx sp pb args body = do
  vals <- pluginArgs ctx sp args
  bodyValues body (evalBlocks ctx body) $ \body' -> case sequence vals of
    Left d -> report d >> pure []
    Right vs | not (all (all inInt64 . valueInts . pluginArgValue) vs) -> outOfInt64 sp >> pure []
    Right vs -> case pbCall pb vs body' sp of
      Left ds -> mapM_ report ds >> pure []
      Right (out, imgs, ds) -> do
        mapM_ report ds
        concat <$> mapM (memoryFigure sp body' imgs) out

{- | A figure a block command made, whose image is in memory (docs/adr/0123,
root ADR 0439), goes through the checks of @figure (checkFigure), its
image found among the images of the command; one that fails gives no
block, as @figure, and its image is not kept. A paragraph style in its
caption is G02013, and is dropped, as @figure does. A block of the body,
and a block that is no figure, passes as it is.
-}
memoryFigure :: SrcSpan -> [Block] -> Map Text ByteString -> Block -> M [Block]
memoryFigure sp body imgs b = case b of
  Block bsp lbl lang (FigureBlock f) | b `notElem` body -> do
    mapM_ (\_ -> err "G02013" sp "@style は図版のキャプションには付けられません") [() | Block _ _ _ (Paragraph (Just _) _) <- figCaption f]
    let unstyle = \case
          Block csp clbl clang (Paragraph (Just _) is) -> Block csp clbl clang (Paragraph Nothing is)
          c -> c
        f' = f {figCaption = map unstyle (figCaption f)}
    ok <- checkFigure sp (pure . (`Map.member` imgs)) f'
    if ok
      then do
        modify' (\s -> s {stImages = Map.union (stImages s) (Map.restrictKeys imgs (Set.fromList (figSource f' : maybe [] pure (figWeb f'))))})
        pure [Block bsp lbl lang (FigureBlock f')]
      else pure []
  _ -> pure [b]

{- | The images of the figures a block command of a .emet made (root ADR
0439): the SVG after 'svgDataPrefix' in the source of each, as UTF-8,
named as the image of a plugin is, by the SHA-256 of its bytes, with the
sources of the figures set to the names. golem-emet has refused any other
figure the command made (E06104); a block of the body passes as it is.
-}
dataImages :: [Block] -> [Block] -> ([Block], Map Text ByteString)
dataImages body = foldr place ([], Map.empty)
  where
    place b@(Block bsp lbl lang (FigureBlock f)) (bs, imgs)
      | b `notElem` body,
        Just svg <- T.stripPrefix svgDataPrefix (figSource f) =
          let bytes = TE.encodeUtf8 svg
              name = pluginImagePrefix <> hexOf (sha256 bytes) <> ".svg"
           in (Block bsp lbl lang (FigureBlock f {figSource = name}) : bs, Map.insert name bytes imgs)
    place b (bs, imgs) = (b : bs, imgs)
    hexOf = T.pack . concatMap (\w -> [hexDigit (w `div` 16), hexDigit (w `mod` 16)]) . BS.unpack
    hexDigit w = "0123456789abcdef" !! fromIntegral w

{- | The arguments of a call of a plugin: a keyword with its name
(docs/adr/0110). A spread is already expanded by 'prepareArgs'
(docs/adr/0112), so a plugin never gets one.
-}
pluginArgs :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> M [Either Diagnostic PluginArg]
pluginArgs ctx sp args = forM (firstKeywords args) $ \(A.Located _ a) -> case a of
  A.Positional v -> fmap PluginPositional <$> argValue ctx sp v
  A.Keyword (A.Located _ k) v -> fmap (PluginKeyword k) <$> argValue ctx sp v
  _ -> pure (Right (PluginPositional VNil))

{- | A plugin receives the first value of a repeated key, as before ADR 0351;
diagnostics are collected from the complete list before this call.
-}
firstKeywords :: [A.Located A.Argument] -> [A.Located A.Argument]
firstKeywords args =
  [ a
  | (i, a) <- zip [0 :: Int ..] args,
    let previous = take i args,
    case a of
      A.Located _ (A.Keyword (A.Located _ k) _) -> k `notElem` [p | A.Located _ (A.Keyword (A.Located _ p) _) <- previous]
      _ -> True
  ]

-- ------------------------------------------------------------------ functions of .emet

{- | The namespace of a command of a .emet (docs/adr/0162): Left with the
diagnostic of a namespace the file has not imported, or what the namespace
gives: its functions, or why the evaluation cannot call them (root ADR
0461).
-}
functionNamespace :: Text -> SrcSpan -> Text -> Text -> M (Either Diagnostic FunctionRef)
functionNamespace code nsp ns shown = do
  -- the namespace is used, for the lint of unused imports (G05003)
  modify' (\s -> s {stNsRefs = Map.insertWith Set.union ns (Set.singleton shown) (stNsRefs s)})
  refs <- gets stFunctions
  isVars <- gets (Map.member ns . stNamespaces)
  pure $ case Map.lookup ns refs of
    Just ref -> Right ref
    Nothing
      | isVars -> Left (diagnostic code Error nsp ("名前空間 " <> ns <> " は .gm の変数の取り込みで、コマンドを持ちません: " <> shown))
      | otherwise -> Left (diagnostic code Error nsp ("未定義の名前空間 " <> ns <> " のコマンドです: " <> shown))

{- | The values of the arguments of a command of a .emet (docs/adr/0162),
fitted to what it takes: the positional ones, the variable ones as an
array, and the keyword ones in the order of the signature, a left out one
with its default. G02119 for a keyword argument the signature has not,
G02120 for the number of the positional ones, G02121 for a value of
another type. Nothing after an error, which is reported.
-}
functionArgs :: EvalContext -> SrcSpan -> Text -> Params -> [A.Located A.Argument] -> M (Maybe [Value])
functionArgs ctx sp name ps args = do
  vals <- forM args $ \la@(A.Located _ a) -> case a of
    A.Positional _ -> fmap (Nothing,) <$> plainArgValue ctx sp (argOf la)
    A.Keyword (A.Located _ k) _ -> fmap (Just k,) <$> plainArgValue ctx sp (argOf la)
    _ -> pure (Right (Nothing, VNil))
  let known = map kpName (prKeywords ps)
      unknown = [(ksp, k) | A.Located _ (A.Keyword (A.Located ksp k) _) <- args, k `notElem` known]
      unknownDiagnostic (ksp, k) = diagnostic "G02119" Error ksp ("シグネチャにないキーワード引数です: " <> k <> "（" <> name <> (if null known then " はキーワード引数を取りません）" else " のキーワード引数: " <> T.intercalate "、" known <> "）"))
      positionalArguments = [(asp, result) | (A.Located asp (A.Positional _), result) <- zip args vals]
      positional = [(i, asp, v) | (i, (asp, Right (_, v))) <- zip [1 ..] positionalArguments]
      positionalCount = length positionalArguments
      requiredCount = length (prPositional ps)
      missingSite = mkSpan (spanFile sp) (spanEnd sp) (spanEnd sp)
      countError = argErrorDiagnostic missingSite name (WrongCount positionalCount requiredCount (isJust (prVarargs ps)))
      countErrors
        | positionalCount < requiredCount =
            [ countError {diagMessage = diagMessage countError <> "。" <> tshow index <> " 番目の位置引数がありません"}
            | index <- [positionalCount + 1 .. requiredCount]
            ]
        | positionalCount > requiredCount && isNothing (prVarargs ps) = [countError]
        | otherwise = []
      positionalTypeErrors =
        [ argErrorDiagnostic asp name (WrongType i expected v)
        | (i, asp, v) <- positional,
          Just expected <- [if i <= requiredCount then Just (prPositional ps !! (i - 1)) else prVarargs ps],
          isNothing (fitValue expected v)
        ]
      keywordValues =
        [ (valueSpan asp ksp, k, v)
        | (A.Located asp (A.Keyword (A.Located ksp k) _), Right (_, v)) <- zip args vals
        ]
      keywordTypeErrors =
        [ diagnostic "G02121" Error vsp ("引数の型が合いません: " <> name <> " のキーワード引数 " <> k <> " は " <> argTypeText (kpType kp) <> " を求めますが、" <> typeName v <> "です")
        | (vsp, k, v) <- keywordValues,
          Just kp <- [lookupKeyword k],
          isNothing (fitValue (kpType kp) v)
        ]
      errors = lefts vals <> map unknownDiagnostic unknown <> countErrors <> positionalTypeErrors <> keywordTypeErrors
  mapM_ report errors
  if not (null errors) || not (null (repeatedKeys args))
    then pure Nothing
    else case sequence vals of
      Left _ -> pure Nothing
      Right vs -> do
        let given = [(k, v) | (Just k, v) <- vs]
            keyword kp = maybe (kpDefault kp) (fromMaybe (kpDefault kp) . fitValue (kpType kp)) (lookup (kpName kp) given)
        case positionalValues ps [v | (Nothing, v) <- vs] of
          Left _ -> pure Nothing
          Right pos -> pure (Just (pos <> map keyword (prKeywords ps)))
  where
    lookupKeyword k = listToMaybe [kp | kp <- prKeywords ps, kpName kp == k]
    valueSpan asp ksp = mkSpan (spanFile asp) (spanEnd ksp + 1) (spanEnd asp)
    argOf (A.Located asp a) = case a of
      A.Positional v -> A.Located asp v
      A.Keyword _ v -> A.Located asp v
      _ -> A.Located asp (A.Word "")

-- | An inline command of a .emet (docs/adr/0162); after any error, the function is not called.
functionInline :: EvalContext -> Bool -> SrcSpan -> SrcSpan -> Text -> Text -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
functionInline ctx inHeading sp nsp ns n args slots =
  functionNamespace "G02022" nsp ns qualified >>= \case
    Left d -> unknownName ctx qualified d >> pure []
    Right (Unloaded why) -> unloadedCall why nsp qualified
    Right (Loaded fns) -> case Map.lookup n (fnInline fns) of
      Nothing -> unknownName ctx qualified (diagnostic "G02022" Error nsp ("名前空間 " <> ns <> " にないインラインのコマンドです: " <> qualified <> blockHint)) >> pure []
        where
          blockHint = if Map.member n (fnBlock fns) then "（ブロックコマンドの @" <> qualified <> " はあります）" else ""
      Just f -> callInline ctx inHeading sp qualified f args slots
  where
    qualified = ns <> "." <> n

-- | The call of an inline command of a .emet, by the name it is written with; after any error, the function is not called.
callInline :: EvalContext -> Bool -> SrcSpan -> Text -> InlineFunction -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
callInline ctx inHeading sp qualified f args slots = do
  vals <- functionArgs ctx sp qualified (ifParams f) args
  case vals of
    Nothing -> pure []
    Just vs
      | length slots /= ifSlots f -> err "G02122" sp ("散文スロットの数が合いません: " <> qualified <> " は " <> tshow (ifSlots f) <> " 個の散文スロットを取りますが、" <> tshow (length slots) <> " 個あります") >> pure []
      | otherwise -> do
          slots' <- mapM (evalInlines ctx inHeading) slots
          case ifCall f vs slots' sp of
            Left ds -> mapM_ report ds >> pure []
            Right out -> do
              let out' = map (fillKenten ctx) out
              ok <- outputChecked ctx sp out' []
              pure (if ok then out' else [])

-- | A block command of a .emet (docs/adr/0162); after any error, the function is not called.
functionBlock :: EvalContext -> SrcSpan -> SrcSpan -> Text -> Text -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
functionBlock ctx sp nsp ns n args body =
  functionNamespace "G02009" nsp ns ("@" <> qualified) >>= \case
    Left d -> unknownName ctx ("@" <> qualified) d >> pure []
    Right (Unloaded why) -> unloadedCall why nsp ("@" <> qualified)
    Right (Loaded fns) -> case Map.lookup n (fnBlock fns) of
      Nothing -> unknownName ctx ("@" <> qualified) (diagnostic "G02009" Error nsp ("名前空間 " <> ns <> " にないブロックコマンドです: @" <> qualified <> inlineHint)) >> pure []
        where
          inlineHint = if Map.member n (fnInline fns) then "（インラインのコマンドの [" <> qualified <> "] はあります）" else ""
      Just f -> callBlock ctx sp ("@" <> qualified) f args body
  where
    qualified = ns <> "." <> n

-- | The call of a block command of a .emet, by the name it is written with (@ included); after any error, the function is not called.
callBlock :: EvalContext -> SrcSpan -> Text -> BlockFunction -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
callBlock ctx sp shown f args body = do
  vals <- functionArgs ctx sp (T.drop 1 shown) (bfParams f) args
  case vals of
    Nothing -> pure []
    Just vs
      | not (bfBody f) && not (null body) -> err "G02123" sp ("本体を受け取らない関数のブロックコマンドに本体があります: " <> shown) >> pure []
      | otherwise -> do
          bodyValues body (evalBlocks ctx body) $ \body' -> case bfCall f vs body' sp of
            Left ds -> mapM_ report ds >> pure []
            Right out -> do
              let out' = map (fillKentenBlock ctx) out
              ok <- outputChecked ctx sp [] out'
              if ok
                then let (placed, imgs) = dataImages body' out' in concat <$> mapM (memoryFigure sp body' imgs) placed
                else pure []

{- | The names a function put in its output, checked as the built-in
commands check them (docs/adr/0162): a character style (G02018), a
swatch (G02017), a paragraph style (G02047), a shape of kenten (G02039)
and a key of the bibliography (G02021), at the call. False after an
error: the caller drops the output.
-}
outputChecked :: EvalContext -> SrcSpan -> [Inline] -> [Block] -> M Bool
outputChecked ctx sp is bs = do
  let errors = nameErrors ctx is bs
  mapM_ (\(c, m) -> err c sp m) errors
  pure (null errors)

-- | The errors of the names of inlines and blocks, each name once.
nameErrors :: EvalContext -> [Inline] -> [Block] -> [(Text, Text)]
nameErrors ctx is bs =
  let inl = universeInlines (is <> concatMap blockInlines (universeBlocks bs))
      once xs = Set.toList (Set.fromList xs)
   in [("G02018", "定義されていない文字スタイルです: " <> x) | x <- once [x | CharStyle _ x _ <- inl], not (Set.member x (ctxCharStyles ctx))]
        <> [("G02017", "style.toml にないスウォッチです: " <> x) | x <- once [x | Color _ x _ <- inl], not (Set.member x (ctxSwatches ctx))]
        <> [("G02047", "定義されていない段落スタイルです: " <> x) | x <- once (concatMap paraStyleOf (universeBlocks bs)), not (Map.member x (ctxParaStyles ctx))]
        <> [("G02039", "未知の圏点の形です: " <> x) | x <- once [x | Kenten _ (Just x) _ <- inl], x `notElem` kentenShapes]
        <> [("G02021", "書誌データにないキーです: " <> x) | x <- once [citKey i | Cite _ items <- inl, i <- items], not (Set.member x (ctxCiteKeys ctx))]
  where
    -- the paragraph style of a paragraph and of the cells of a table (docs/adr/0262)
    paraStyleOf (Block _ _ _ body) = case body of
      Paragraph (Just x) _ -> [styleRefName x]
      TableBlock Table {tableStyle = Just x} -> [styleRefName x]
      _ -> []
    universeBlocks = concatMap (\b -> b : universeBlocks (innerBlocks b))
    innerBlocks (Block _ _ _ body) = case body of
      BulletList items -> concatMap itemBlocks items
      OrderedList items -> concatMap itemBlocks items
      DefList gs -> concat (concatMap dgDefs gs)
      FigureBlock f -> figCaption f
      FrameBlock _ inner -> inner
      _ -> []
    blockInlines (Block _ _ _ body) = case body of
      Paragraph _ xs -> xs
      Heading _ a xs -> fromMaybe [] (haTocTitle a) <> xs
      TableBlock t -> fromMaybe [] (tableCaption t) <> concat (tableHeader t) <> concat (concat (tableRows t))
      DefList gs -> concat (concatMap dgTerms gs)
      CodeBlock c -> fromMaybe [] (codeCaption c)
      _ -> []
    universeInlines = concatMap (\i -> i : universeInlines (children i))
    children = \case
      Kenten _ _ xs -> xs
      Color _ _ xs -> xs
      CharStyle _ _ xs -> xs
      Note _ _ _ nb -> concat (noteParagraphs nb)
      Sidenote _ _ _ nb -> concat (noteParagraphs nb)
      Endnote _ _ _ nb -> concat (noteParagraphs nb)
      Cite _ items -> citeInlines items
      ChannelItem _ c -> ciBody c
      Link _ _ xs -> xs
      Lang _ _ xs -> xs
      Resolved _ _ _ xs -> xs
      Ruby _ _ segs -> concat [mapMaybe withRubyInline (rsBase g) | g <- segs]
      _ -> []
    withRubyInline :: InlineNoRuby -> Maybe Inline
    withRubyInline = \case
      Text a t -> Just (Text a t)
      _ -> Nothing

{- | The errors of the names of a document after the filters of .emet
(docs/adr/0162), at the top of the file: the filters of a plugin check
the paragraph styles alone ('unknownParaStyles').
-}
functionFilterNames :: EvalContext -> Document -> [Diagnostic]
functionFilterNames ctx d
  | Set.member (ctxPath ctx) (ftFilterFiles (ctxFunctions ctx)) =
      [diagnostic c Error (mkSpan (ctxFile ctx) 0 0) m | (c, m) <- nameErrors ctx [] (docBlocks d), c /= "G02047"]
  | otherwise = []

-- | 'fillKenten' over a document a filter of a .emet applies to (docs/adr/0162).
fillFilterKenten :: EvalContext -> Document -> Document
fillFilterKenten ctx d
  | Set.member (ctxPath ctx) (ftFilterFiles (ctxFunctions ctx)) = d {docBlocks = map (fillKentenBlock ctx) (docBlocks d)}
  | otherwise = d

-- | A kenten a function made without a shape takes the default of style.toml (docs/adr/0162).
fillKenten :: EvalContext -> Inline -> Inline
fillKenten ctx = \case
  Kenten s Nothing xs -> Kenten s (Just (ctxDefaultKenten ctx)) (map (fillKenten ctx) xs)
  Kenten s sh xs -> Kenten s sh (map (fillKenten ctx) xs)
  Color s c xs -> Color s c (map (fillKenten ctx) xs)
  CharStyle s c xs -> CharStyle s c (map (fillKenten ctx) xs)
  Note s n lbl bs -> Note s n lbl (mapNoteBody (map (fillKenten ctx)) bs)
  Sidenote s n lbl bs -> Sidenote s n lbl (mapNoteBody (map (fillKenten ctx)) bs)
  Endnote s n lbl bs -> Endnote s n lbl (mapNoteBody (map (fillKenten ctx)) bs)
  Link s u xs -> Link s u (map (fillKenten ctx) xs)
  Lang s l xs -> Lang s l (map (fillKenten ctx) xs)
  Resolved s k l xs -> Resolved s k l (map (fillKenten ctx) xs)
  i -> i

-- | 'fillKenten' in the inlines of blocks.
fillKentenBlock :: EvalContext -> Block -> Block
fillKentenBlock ctx (Block sp l lang body) = Block sp l lang $ case body of
  Paragraph st xs -> Paragraph st (map f xs)
  Heading lv a xs -> Heading lv a (map f xs)
  BulletList items -> BulletList [ListItem n (map (fillKentenBlock ctx) bs) | ListItem n bs <- items]
  OrderedList items -> OrderedList [ListItem n (map (fillKentenBlock ctx) bs) | ListItem n bs <- items]
  DefList gs -> DefList [DefGroup (map (map f) ts) (map (map (fillKentenBlock ctx)) ds) | DefGroup ts ds <- gs]
  TableBlock t -> TableBlock t {tableCaption = map f <$> tableCaption t, tableHeader = map (map f) (tableHeader t), tableRows = map (map (map f)) (tableRows t)}
  FrameBlock name bs -> FrameBlock name (map (fillKentenBlock ctx) bs)
  other -> other
  where
    f = fillKenten ctx

-- ------------------------------------------------------------------ the commands written in a row

{- | What a command written in a row with others does with what follows it
(root ADR 0459), by what its name resolves to where it is written.
-}
data CommandKind
  = -- | takes the result of the commands after it, or the body, as its body
    TakesBody
  | -- | an attribute of the first block of that result
    Attribute
  | -- | accepts only an explicit fenced body (the existing figure caption)
    ExplicitBody
  | -- | puts out blocks of its own and takes no body
    PutsOut
  | {- | a name the evaluation cannot call (a .emet not loaded, a name of G02272): it puts out nothing, and
    counts as a command that puts out blocks for G02011 and G02123 (root ADR 0461)
    -}
    Unresolved
  deriving stock (Eq)

{- | The paragraph style a @style passes to the blocks of its body (root
ADR 0460): the line of the @style, the name and the keys of its named
arguments (root ADR 0467; Nothing after G02047, as body).
-}
data Passed = Passed
  { psCommand :: !SrcSpan,
    psRef :: !(Maybe StyleRef)
  }

-- | The kind of a command of a group, looked up as 'standalone' and 'builtinBlock' look it up, without noting any use.
commandKind :: EvalContext -> A.Located A.Block -> M CommandKind
commandKind ctx (A.Located _ b) =
  gets stListedFns >>= \listedFns -> case b of
    A.BlockCommand (A.Located _ name) _ _
      -- the @style of a next-style is the built-in one (root ADR 0471)
      | name == nextStyleName -> pure TakesBody
      | Just o <- parseOverridableBlock name, Map.member o (phBlockOverrides (ctxPlugins ctx)) -> pure TakesBody
      -- an overridden built-in command is the function listed (root ADR 0471)
      | isJust (parseOverridableBlock name), Just ref <- Map.lookup (BlockSpace, name) listedFns -> pure (listedKind name ref)
      | name `elem` ["note", "endnote", "frame", "style", "lang"] -> pure TakesBody
      | name == "figure" -> pure ExplicitBody
      | name `elem` attributeCommands -> pure Attribute
      | name `elem` builtinBlockCommands || name `elem` settingCommands -> pure PutsOut
      | Map.member name (phBlocks (ctxPlugins ctx)) -> pure TakesBody
      | Just (ns, n) <- splitNamespace name ->
          gets (Map.lookup ns . stFunctions) >>= \case
            Just (Loaded fns) -> pure (maybe PutsOut functionKind (Map.lookup n (fnBlock fns)))
            Just (Unloaded _) -> pure Unresolved
            Nothing -> pure PutsOut
      | otherwise -> case Map.lookup (BlockSpace, name) listedFns of
          Nothing -> pure PutsOut
          Just ref -> pure (listedKind name ref)
    _ -> pure PutsOut
  where
    functionKind f = if bfBody f then TakesBody else PutsOut
    listedKind name = \case
      Loaded fns | Just f <- Map.lookup name (fnBlock fns) -> functionKind f
      _ -> Unresolved

{- | The commands written in a row and their body (root ADR 0459): the
file settings out of place first (G02049), then the breaks, which go
before the rest (docs/adr ADR 0017); the rest is one command, the later
ones inside the earlier ones ('commandRow'). The body is the next block,
or the blocks between ::: lines.
-}
attributed :: EvalContext -> Maybe Passed -> SrcSpan -> [A.Located A.Block] -> Maybe (A.Located A.Block) -> M [Block]
attributed ctx passed sp cmds0 target
  -- a file setting inside a group is out of place (docs/adr ADR 0014)
  | any isSettingCommand cmds0 = do
      mapM_ (misplacedSetting . A.locSpan) (filter isSettingCommand cmds0)
      attributed ctx passed sp (filter (not . isSettingCommand) cmds0) target
  | otherwise = do
      isBuiltin <- builtinBlockAt ctx
      attributedWith isBuiltin ctx passed sp cmds0 target

-- | 'attributed' after the file settings, the built-in commands told where the group is (root ADR 0471).
attributedWith :: (Text -> Bool) -> EvalContext -> Maybe Passed -> SrcSpan -> [A.Located A.Block] -> Maybe (A.Located A.Block) -> M [Block]
attributedWith isBuiltin ctx passed sp cmds0 target
  -- the breaks that call the built-in commands (root ADR 0471)
  | (breaks@(_ : _), rest) <- partition (isBreakCommand isBuiltin) cmds0 = do
      bs <- concat <$> mapM (evalBlock ctx) breaks
      (bs <>) <$> attributed ctx passed sp rest target
  | null cmds0 = case target of
      Nothing -> pure []
      Just (A.Located _ (A.Fenced _ inner)) -> do
        err "G02123" sp "本体を受け取らないコマンドに ::: で囲んだ本体があります"
        concat <$> mapM (evalWith ctx passed) inner
      Just t -> evalWith ctx passed t
  | otherwise = commandRow ctx passed sp cmds0 target

-- | A block evaluated with the paragraph style of a @style around it, or as it is.
evalWith :: EvalContext -> Maybe Passed -> A.Located A.Block -> M [Block]
evalWith ctx = maybe (evalBlock ctx) (evalStyled ctx)

{- | The commands of a group, without its settings and breaks, as one
command (root ADR 0459): a command that takes a body takes the commands
after it with the body; an attribute goes to the first block of what
follows; a command that puts out blocks is evaluated where it is written,
its blocks before the rest. G02013 for an attribute, @style or @lang
outside @note and @endnote, which are left out; G02012 for each one
written again, all but the last left out (root ADR 0462); G02011 once for the group when a command
that puts out blocks has an attribute outside it, or the next block after
it; G02123 for the blocks between ::: lines after it. A name the
evaluation cannot call counts as a command that puts out blocks for them,
in the nested groups too (root ADR 0461).
-}
commandRow :: EvalContext -> Maybe Passed -> SrcSpan -> [A.Located A.Block] -> Maybe (A.Located A.Block) -> M [Block]
commandRow ctx passed sp cmds0 target = do
  isBuiltin <- builtinBlockAt ctx
  let isNote c = builtinCommand isBuiltin c `elem` [Just "note", Just "endnote"]
      isStyleCommand' = isStyleCommand isBuiltin
      isLangCommand' = isLangCommand isBuiltin
      -- the already normalized body blocks, independent of its style (root ADR 0473)
      bodyBlocks = case target of
        Nothing -> []
        Just (A.Located _ (A.Fenced _ bs)) -> bs
        Just t -> [t]
      evalBody = concat <$> mapM (evalWith ctx passed) bodyBlocks
      -- the commands after one that takes a body, with the body
      inner = \case
        [] -> bodyBlocks
        [(_, c)] | isNothing target -> [c]
        rest@((_, A.Located csp _) : _) -> [A.Located (mkSpan (spanFile sp) (spanStart csp) (spanEnd sp)) (A.Attributed (map snd rest) target)]
      go = \case
        [] -> ([],) <$> evalBody
        xs@((Attribute, _) : _) -> do
          let (attrs, rest) = span ((== Attribute) . fst) xs
          (pre, r) <- go rest
          when (null r && null pre && isNothing target && Unresolved `notElem` map fst rest) $
            err "G02010" sp "属性の後にブロックがありません"
          (pre,) <$> attach ctx (map snd attrs) r
        ((TakesBody, c) : rest) -> ([],) <$> applyBody True c (inner rest)
        ((ExplicitBody, c) : rest)
          | null rest, Just (A.Located _ (A.Fenced _ _)) <- target -> ([],) <$> applyBody False c bodyBlocks
        ((_, c) : rest)
          | null rest -> do
              out <- evalWith ctx passed c
              after <- case passed of
                Just _ -> evalBody
                Nothing -> nextStyledFrom ctx (withLocalStyles (ctxStyle ctx) (ctxLocalStyles ctx)) (followingStyle (withLocalStyles (ctxStyle ctx) (ctxLocalStyles ctx)) Nothing out) bodyBlocks
              pure ([], out <> after)
          | otherwise -> do
              out <- evalWith ctx passed c
              let style = withLocalStyles (ctxStyle ctx) (ctxLocalStyles ctx)
                  refresh entry@(_, A.Located csp (A.BlockCommand (A.Located _ n) _ _))
                    | n == nextStyleName, not (null out) = fmap (\st -> (TakesBody, A.Located csp (styleCommand csp st []))) (followingStyle style Nothing out)
                    | otherwise = Just entry
                  refresh entry = Just entry
              (pre, r) <- go (mapMaybe refresh rest)
              pure (out <> pre, r)
  kinds0 <- mapM (commandKind ctx) cmds0
  let tagged0 = zip kinds0 cmds0
      (outside, fromNote) = break (isNote . snd) tagged0
      noteName = case fromNote of
        ((_, A.Located _ (A.BlockCommand (A.Located _ n) _ _)) : _) -> n
        _ -> "note"
      wrapper (k, c) = k == Attribute || isStyleCommand' c || isLangCommand' c
      misplaced = if null fromNote then [] else filter wrapper outside
  forM_ misplaced $ \case
    (_, A.Located asp (A.BlockCommand (A.Located _ n) _ _)) -> err "G02013" asp ("@" <> n <> " は @" <> noteName <> " には付けられません")
    _ -> pure ()
  let tagged1 = (if null fromNote then outside else filter (not . wrapper) outside) <> fromNote
      once = [(n, i) | (i, (k, c@(A.Located _ (A.BlockCommand (A.Located _ n) _ _)))) <- zip [0 :: Int ..] tagged1, k == Attribute || isStyleCommand' c || isLangCommand' c]
      repeated = [i | (j, (n, i)) <- zip [0 :: Int ..] once, n `elem` map fst (take j once)]
      -- of a command written twice, the one written last is kept (root ADR 0462)
      dropped = [i | (j, (n, i)) <- zip [0 :: Int ..] once, n `elem` map fst (drop (j + 1) once)]
  mapM_ (\(_, (_, A.Located asp _)) -> err "G02012" asp "同じ属性を二度書いています") [x | x@(i, _) <- zip [0 :: Int ..] tagged1, i `elem` repeated]
  let tagged = [x | (i, x) <- zip [0 :: Int ..] tagged1, i `notElem` dropped]
      -- a name the evaluation cannot call is one that puts out blocks (root ADR 0461)
      kinds = [if k == Unresolved then PutsOut else k | (k, _) <- tagged]
      nextBlock = case target of
        Just (A.Located _ (A.Fenced _ _)) -> False
        Just _ -> True
        Nothing -> False
      fenced = isJust target && not nextBlock
      -- G02011 for the commands of a list: an attribute before a command
      -- that puts out blocks and is not the last, or the next block after
      -- the last that puts out blocks
      g02011 ks = case reverse ks of
        [] -> False
        (lastK : before) ->
          let earlier = reverse before
           in or [Attribute `elem` take i earlier | (i, k) <- zip [0 ..] earlier, k `elem` [PutsOut, ExplicitBody]]
                || (lastK `elem` [PutsOut, ExplicitBody] && nextBlock)
      -- the commands inside the first that takes a body report for themselves
      suffix = case break (== TakesBody) kinds of
        (_, _ : rest@(_ : _)) -> Just rest
        _ -> Nothing
  when (g02011 kinds && not (maybe False g02011 suffix)) $
    err "G02011" sp "属性のまとまりに属性でないコマンドがあります"
  when (TakesBody `notElem` kinds && fenced && lastOf kinds == Just PutsOut) $
    err "G02123" sp "本体を受け取らないコマンドに ::: で囲んだ本体があります"
  (pre, r) <- go tagged
  pure (pre <> r)
  where
    lastOf ks = case reverse ks of
      (k : _) -> Just k
      [] -> Nothing
    applyBody canOmit c body = case c of
      A.Located csp (A.BlockCommand n args own) ->
        let input = own <> body
            fence = case target of Just (A.Located fsp (A.Fenced _ _)) -> Just fsp; _ -> Nothing
            closed = case target of Just (A.Located _ (A.Fenced isClosed _)) -> isClosed; _ -> False
         in withBodyScope csp fence (canOmit && closed) input (evalWith ctx passed (A.Located csp (A.BlockCommand n args input)))
      other -> evalWith ctx passed other

-- | A block that calls the built-in @lang (root ADR 0471).
isLangCommand :: (Text -> Bool) -> A.Located A.Block -> Bool
isLangCommand isBuiltin c = builtinCommand isBuiltin c == Just "lang"

{- | The attributes on the first of the blocks (docs/adr ADR 0005, golem-eval
ADR 0003): its label, the attributes of its kind (G02013 for the others),
G02134 for @nonumber on a code block or a table without a caption.
-}
attach :: EvalContext -> [A.Located A.Block] -> [Block] -> M [Block]
attach ctx attrs0 bs = do
  attrs <- catMaybes <$> mapM uniqueAttrKeys attrs0
  let named = [(n, asp) | A.Located asp (A.BlockCommand (A.Located _ n) _ _) <- attrs]
  case bs of
    (Block bsp label0 lang0 body : rest) -> do
      -- where G04007 points: the @number line (golem-syntax ADR 0002)
      case [asp | ("number", asp) <- named] of
        (asp : _) -> modify' (\s -> s {stNumberSites = Map.insert bsp asp (stNumberSites s)})
        [] -> pure ()
      (label, body') <- foldl (\acc x -> acc >>= \a -> applyAttr ctx a x) (pure (label0, body)) attrs
      -- G02134: @nonumber on a code block without a caption, whichever line comes first (docs/adr/0200)
      body'' <- case body' of
        CodeBlock c
          | codeNoNumber c,
            Nothing <- codeCaption c -> do
              mapM_ (\asp -> err "G02134" asp "キャプションのないコードブロックは番号を持たないので、@nonumber は要りません") (take 1 [asp | ("nonumber", asp) <- named])
              pure (CodeBlock c {codeNoNumber = False})
        -- likewise a table (docs/adr/0262)
        TableBlock tb
          | tableNoNumber tb,
            Nothing <- tableCaption tb -> do
              mapM_ (\asp -> err "G02134" asp "キャプションのない表は番号を持たないので、@nonumber は要りません") (take 1 [asp | ("nonumber", asp) <- named])
              pure (TableBlock tb {tableNoNumber = False})
        _ -> pure body'
      pure (Block bsp label lang0 body'' : rest)
    [] -> pure []

{- | A block of the body of @style (root ADR 0460): the paragraphs, those
of lists and those inside @lang and attributes evaluated in the style;
a table with the style for its cells; the paragraphs and tables of what
other block commands put out in the style afterwards. A heading, a block
without paragraphs or tables, @frame, @note, @endnote and an inner @style
are as they are.
-}
evalStyled :: EvalContext -> Passed -> A.Located A.Block -> M [Block]
evalStyled ctx ps lb@(A.Located sp b) =
  builtinBlockAt ctx >>= \isBuiltin -> case b of
    A.Paragraph is -> styledParagraph ctx sp (psRef ps) is
    A.BulletList items -> one . BulletList <$> mapM (fmap (ListItem Nothing) . inner) items
    A.OrderedList items -> one . OrderedList <$> mapM (fmap (ListItem Nothing) . inner) items
    A.DefList gs -> one . DefList <$> mapM (\(A.DefGroup ts ds) -> DefGroup <$> mapM (evalInlines ctx False) ts <*> mapM inner ds) gs
    A.Table {} -> evalBlock ctx lb >>= mapM (styledOutput ctx ps)
    A.Attributed cmds t -> attributed ctx (Just ps) sp cmds t
    A.Fenced _ bs -> inner bs
    -- the built-in commands alone (root ADR 0471): an overridden name puts out blocks in the style
    A.BlockCommand _ args body
      | builtinCommand isBuiltin lb `elem` map Just ["style", "frame", "note", "endnote"] -> evalBlock ctx lb
      | isLangCommand isBuiltin lb, not (null body) -> prepareArgs args >>= maybe (pure []) (\args' -> langBodyWith inner sp args' body)
      | otherwise -> evalBlock ctx lb >>= mapM (styledOutput ctx ps)
    _ -> evalBlock ctx lb
  where
    inner = fmap concat . mapM (evalStyled ctx ps)
    one x = [block sp x]

{- | The paragraph style of a @style on a block a command put out (root ADR
0460): its paragraphs without a style, those of its lists too, and the
cells of its tables (docs/adr/0262). An unknown style is G02047.
-}
styledOutput :: EvalContext -> Passed -> Block -> M Block
styledOutput ctx ps b = case blockBody b of
  Paragraph Nothing is -> case psRef ps of
    Just r
      | Map.notMember (styleRefName r) (ctxParaStyles ctx) -> err "G02047" (blockSpan b) ("定義されていない段落スタイルです: " <> styleRefName r) >> pure b
      | otherwise -> pure b {blockBody = Paragraph (paragraphRef r) is}
    Nothing -> pure b
  BulletList items -> (\xs -> b {blockBody = BulletList xs}) <$> mapM item items
  OrderedList items -> (\xs -> b {blockBody = OrderedList xs}) <$> mapM item items
  DefList gs -> (\xs -> b {blockBody = DefList xs}) <$> mapM (\(DefGroup ts ds) -> DefGroup ts <$> mapM (mapM (styledOutput ctx ps)) ds) gs
  TableBlock t
    | Nothing <- tableStyle t,
      Just r <- psRef ps,
      Map.notMember (styleRefName r) (ctxParaStyles ctx) ->
        err "G02047" (psCommand ps) ("定義されていない段落スタイルです: " <> styleRefName r) >> pure b
    | Nothing <- tableStyle t,
      Just r <- psRef ps,
      r /= "table" ->
        pure b {blockBody = TableBlock t {tableStyle = Just r}}
  _ -> pure b
  where
    item (ListItem n bs) = ListItem n <$> mapM (styledOutput ctx ps) bs

-- | Whether some block has a paragraph or a table, in its lists too (G02046, root ADR 0460).
hasParagraphOrTable :: [Block] -> Bool
hasParagraphOrTable = any $ \b -> case blockBody b of
  Paragraph {} -> True
  TableBlock _ -> True
  BulletList items -> any (hasParagraphOrTable . itemBlocks) items
  OrderedList items -> any (hasParagraphOrTable . itemBlocks) items
  DefList gs -> any (any hasParagraphOrTable . dgDefs) gs
  _ -> False

{- | @channel, the list of a channel a plugin declares (golem-doc ADR
0007): one name, G02090 otherwise; style= the paragraph style of its
entries, body by default, G02047 when it is not defined.
-}
channelBlock :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> M [Block]
channelBlock ctx sp args = do
  kw <- keywords ctx args
  case [v | A.Located _ (A.Positional v) <- args] of
    [v]
      | Just n <- nameArg v,
        Map.member n (phChannels (ctxPlugins ctx)) -> case argText <$> lookup "style" kw of
          Nothing -> pure [block sp (ChannelOutput (CustomOutput n Nothing))]
          Just "body" -> pure [block sp (ChannelOutput (CustomOutput n Nothing))]
          Just st
            | Map.member st (ctxParaStyles ctx) -> pure [block sp (ChannelOutput (CustomOutput n (Just st)))]
            | otherwise -> err "G02047" sp ("定義されていない段落スタイルです: " <> st) >> pure []
      | otherwise -> unknownName ctx (argText v) (diagnostic "G02090" Error sp ("宣言されていないチャネルです: " <> argText v)) >> pure []
    _ -> err "G02090" sp "@channel にはチャネルの名前を一つ書きます" >> pure []

-- | G02049: @manifest or @style-def after the file settings (docs/adr ADR 0014).
misplacedSetting :: SrcSpan -> M ()
misplacedSetting sp = err "G02049" sp "@manifest、@style-def、@hyphenation-exceptions はファイルの最初に置きます"

-- | A block that calls a built-in break, page control, blank line or separator (root ADR 0471).
isBreakCommand :: (Text -> Bool) -> A.Located A.Block -> Bool
isBreakCommand isBuiltin c = maybe False (`elem` ["page-break", "column-break", "no-page-break", "need-lines", "page-lines", "blank-line", "separator"]) (builtinCommand isBuiltin c)

{- | @printings: one paragraph for each printing of meta.printings, as
@2026年10月16日　初版第1刷発行@; the year in kanji-digits, the other
numbers by the default of [numbers] (docs/adr ADR 0033). Each cause
has its own code and every cause found is reported, in this order:
G02096 for arguments, G02097 for a body, G02076 for a book not in Japanese,
G02098 without printings (docs/adr ADR 0056).
-}
printingsBlock :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
printingsBlock ctx sp args body = case (errors, Map.lookup "printings" (ctxMeta ctx)) of
  ([], Just (VArray ps)) -> pure (mapMaybe line ps)
  _ -> mapM_ (\(c, s, m) -> err c s m) errors >> pure []
  where
    printings = case Map.lookup "printings" (ctxMeta ctx) of
      Just (VArray (_ : _)) -> True
      _ -> False
    japaneseBook = case Map.lookup "language" (ctxMeta ctx) of
      Just (VString lang) -> T.toLower (T.takeWhile (/= '-') lang) == "ja"
      _ -> False
    errors =
      [("G02096", sp, takesNoArguments "printings") | not (null args)]
        <> [("G02097", bsp, takesNoBody "printings") | A.Located bsp _ : _ <- [body]]
        <> [("G02076", sp, "@printings は日本語の本（language の主の副タグが ja）でだけ使えます") | not japaneseBook, isNothing format]
        <> [("G02098", sp, "マニフェストに [[metadata.printings]] がありません") | not printings]
    format = stPrintingsFormat (ctxStyle ctx)
    field h name = case Map.lookup name h of
      Just (VString t) -> t
      Just (VInt n) -> T.pack (show n)
      _ -> ""
    line = \case
      VHash h
        | Just pieces <- format -> Just (block sp (Paragraph Nothing [txt (renderPrintingTemplate (field h) pieces)]))
        | Just [e, n, y, m, d] <- traverse (\k -> Map.lookup k h >>= intOf) ["edition", "number", "year", "month", "day"] ->
            Just . block sp . Paragraph Nothing $
              [num y (Just StyleKanjiDigits), txt "年", num m Nothing, txt "月", num d Nothing, txt "日\x3000"]
                <> (if e == 1 then [txt "初版"] else [txt "第", num e Nothing, txt "版"])
                <> [txt "第", num n Nothing, txt "刷発行"]
      _ -> Nothing
    num = Number sp
    txt = Text sp

{- | The message of G02096, an argument to a command that takes none, and of
G02097, a body under a command that cannot have one (docs/adr ADR 0056).
-}
takesNoArguments, takesNoBody :: Text -> Text
takesNoArguments name = "@" <> name <> " は引数を取りません"
takesNoBody name = "@" <> name <> " は本体を持てません"

{- | A page-break command: the error of its arguments, if any, then G02097
at the first block of its body, if any; the block only if neither
(docs/adr ADR 0060).
-}
breakCommand :: SrcSpan -> Text -> [A.Located A.Block] -> Either (Text, Text) BlockBody -> M [Block]
breakCommand sp name body parsed = do
  either (\(c, m) -> err c sp m) (const (pure ())) parsed
  mapM_ (\(A.Located bsp _) -> err "G02097" bsp (takesNoBody name)) (take 1 body)
  pure [block sp b | null body, Right b <- [parsed]]

{- | @page-break and @column-break (docs/adr ADR 0017): G02058 for an
argument of @page-break other than one recto or verso, G02096 for an
argument of @column-break (docs/adr ADR 0060).
-}
forcedBreak :: SrcSpan -> Text -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
forcedBreak sp name args body = breakCommand sp name body $ case (name, map A.locValue args) of
  ("page-break", []) -> Right (ForcedBreak BreakPage)
  ("page-break", [A.Positional v]) | nameArg v == Just "recto" -> Right (ForcedBreak BreakRecto)
  ("page-break", [A.Positional v]) | nameArg v == Just "verso" -> Right (ForcedBreak BreakVerso)
  ("column-break", []) -> Right (ForcedBreak BreakColumn)
  ("column-break", _) -> Left ("G02096", takesNoArguments name)
  _ -> Left ("G02058", "@page-break の引数は recto か verso です")

-- | @page-lines takes a signed, nonzero integer (docs/adr ADR 0060).
pageControl :: SrcSpan -> Text -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
pageControl sp name args body = breakCommand sp name body . fmap PageControl $ case (name, map A.locValue args) of
  ("page-lines", [A.Positional v])
    | Just w <- nameArg v,
      Just (s, digits) <- T.uncons w,
      s `elem` ['+', '-'],
      Just n <- count digits,
      n /= 0 ->
        Right (AdjustLines (if s == '-' then negate n else n))
  _ -> Left ("G02099", "@page-lines の引数は +1 や -1 のように符号を付けた 0 でない整数です")
  where
    -- ASCII digits that fit in an Int
    count w
      | not (T.null w) && T.all isDigit w && T.length w <= 9 = Just (read (T.unpack w))
      | otherwise = Nothing

noPageBreak :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
noPageBreak ctx sp args body = case args of
  [] -> finish (Right (PageControl NoBreak))
  [A.Located asp (A.Positional v)] ->
    naturalArg ctx "@no-page-break の引数" sp (A.Located asp v) >>= \case
      Right n | inInt64 (toInteger n) -> finish (Right (PageControl (NoBreakLines n)))
      Right _ -> finish (Left ("G02091", outOfInt64Message))
      Left NotANumber -> finish (Left ("G02156", "@no-page-break の行数には 0 以上の整数を書きます"))
      Left NaturalReported -> mapM_ (\(A.Located bsp _) -> err "G02097" bsp (takesNoBody "no-page-break")) (take 1 body) >> pure []
  _ -> finish (Left ("G02096", "@no-page-break の引数には行数を一つだけ指定できます"))
  where
    finish = breakCommand sp "no-page-break" body

{- | @need-lines N (docs/adr ADR 0030): a natural number of 1 or more and
of at most 9 digits, G02070 otherwise; a negative number or one that is
not an integer is G02103 or G02104 (docs/adr ADR 0102).
-}
needLines :: EvalContext -> SrcSpan -> Text -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
needLines ctx sp name args body = case args of
  [A.Located asp (A.Positional v)] ->
    naturalArg ctx "@need-lines の引数" sp (A.Located asp v) >>= \case
      Right n | n >= 1 && n < 10 ^ (9 :: Int) -> breakCommand sp name body (Right (PageControl (NeedLines (fromIntegral n))))
      Left NaturalReported -> mapM_ (\(A.Located bsp _) -> err "G02097" bsp (takesNoBody name)) (take 1 body) >> pure []
      _ -> usage
  _ -> usage
  where
    usage = breakCommand sp name body (Left ("G02070", "@need-lines の引数は 1 以上の整数です"))

{- | @blank-line and @blank-line N (docs/adr ADR 0046, ADR 0345): one positional
natural number; zero is kept until adjacent commands are combined. G02091 out of int64; a
negative number or one that is not an integer is G02103 or G02104
(docs/adr ADR 0102).
-}
blankLine :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
blankLine ctx sp args body
  | not (null body) = bad "@blank-line は本体を持てません"
  | otherwise = case args of
      [] -> ok sp 1
      [A.Located asp (A.Positional v)] ->
        naturalArg ctx "@blank-line の引数" sp (A.Located asp v) >>= \case
          Right n -> ok asp (toInteger n)
          Left NaturalReported -> pure []
          Left NotANumber -> bad usage
      _ -> bad usage
  where
    usage = "@blank-line の引数は 0 以上の整数を一つだけ書きます"
    ok asp n = do
      modify' (\s -> s {stBlankCounts = Map.insert sp (asp, n) (stBlankCounts s)})
      pure [block sp (BlankLines (if n < 2 ^ (63 :: Int) then fromInteger n else 0))]
    bad m = err "G02092" sp m >> pure []

{- | A run of @blank-line commands becomes one IR block (Golem ADR 0345).
Page controls keep their order without dividing the run.
-}
collapseBlankLines :: Map.Map SrcSpan (SrcSpan, Integer) -> [Block] -> ([Block], [Diagnostic])
collapseBlankLines counts = go
  where
    go [] = ([], [])
    go bs = case span inRun bs of
      ([], b : rest) -> let (out, ds) = go rest in (b : out, ds)
      (run, rest) ->
        let (out, ds) = collapseRun run
            (following, later) = go rest
         in (out <> following, ds <> later)

    inRun b = case blockBody b of
      BlankLines _ -> True
      PageControl _ -> True
      _ -> False

    collapseRun run =
      let blanks = [(b, n) | b <- run, BlankLines n <- [blockBody b]]
          values = [(b, maybe (toInteger n) snd (Map.lookup (blockSpan b) counts)) | (b, n) <- blanks]
          positives = [b | (b, n) <- values, n > 0]
          total = sum [n | (_, n) <- values]
          over = firstOverflow 0 values
          notices =
            [ notice "G02094" (blockSpan b) "続けて書いた @blank-line は @blank-line <N> にまとめて書けます"
            | b <- drop 1 positives
            ]
          infoDiags = case (blanks, positives) of
            ((b, _) : _, []) -> [infoDiagnostic "G02254" (blockSpan b) "行アキは 0 行です"]
            _ -> []
          errorDiags = case over of
            Just b -> [diagnostic "G02091" Error (maybe (blockSpan b) fst (Map.lookup (blockSpan b) counts)) outOfInt64Message]
            Nothing -> []
          output = case (over, positives) of
            (Just _, _) -> filter (not . isBlank) run
            (Nothing, []) -> filter (not . isBlank) run
            (Nothing, first : _) -> mapMaybe (combine first (fromInteger total)) run
       in (output, infoDiags <> notices <> errorDiags)

    isBlank b = case blockBody b of
      BlankLines _ -> True
      _ -> False
    combine first total b = case blockBody b of
      BlankLines _
        | blockSpan b == blockSpan first -> Just b {blockBody = BlankLines total}
        | otherwise -> Nothing
      _ -> Just b
    firstOverflow _ [] = Nothing
    firstOverflow n ((b, count) : rest)
      | n + toInteger count >= 2 ^ (63 :: Int) = Just b
      | otherwise = firstOverflow (n + toInteger count) rest

{- | G02072: a no-break next to a page or column break, with only need-lines
and page-lines between them (docs/adr ADR 0030).
-}
conflictingBreaks :: [Block] -> [Diagnostic]
conflictingBreaks bs =
  [ diagnostic "G02072" Error sp ("@no-page-break と " <> breakName k <> " が同じ位置にあります")
  | (i, Block sp _ _ (PageControl control)) <- zip [0 :: Int ..] bs,
    keepsPageBreak control,
    side <- [reverse (take i bs), drop (i + 1) bs],
    Block _ _ _ (ForcedBreak k) : _ <- [dropWhile soft side]
  ]
  where
    soft b = case blockBody b of
      PageControl (NoBreakLines 0) -> True
      PageControl (NeedLines _) -> True
      PageControl (AdjustLines _) -> True
      _ -> False
    breakName = \case
      BreakColumn -> "@column-break"
      _ -> "@page-break"

-- ------------------------------------------------------------------ languages

{- | The tag of [lang] and @lang (docs/adr ADR 0187): one positional
argument, a word or a string, and no keyword argument, else G02131; a
tag of the form of BCP 47, else G02132. Nothing after an error.
-}
langTag :: SrcSpan -> [A.Located A.Argument] -> M (Maybe Text)
langTag sp args = case args of
  [A.Located _ (A.Positional v)]
    | Just t <- nameArg v ->
        if isLanguageTag t
          then pure (Just t)
          else err "G02132" sp (langTagMessage t) >> pure Nothing
  _ -> err "G02131" sp "lang には言語のタグを一つ書きます" >> pure Nothing

{- | @[lang タグ: 散文]@ (docs/adr ADR 0187): the prose in a language span;
a slot that is not one is G02038. With a wrong tag the prose stays,
without a span.
-}
langSpan :: EvalContext -> Bool -> SrcSpan -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
langSpan ctx inHeading sp args slots = do
  tag <- langTag sp args
  case slots of
    [s] -> do
      is <- evalInlines ctx inHeading s
      pure (maybe is (\t -> [Lang sp t is]) tag)
    _ -> err "G02038" sp "lang には散文スロットが一つ必要です" >> pure []

{- | The body form of @lang (docs/adr ADR 0187): each block at the top of
the body takes the language, unless it has one of its own; no block wraps
them. A forced break, a page control, blank lines and a separator of the
body stay where they are, without a language; 'nestedBreaks' reports them
if that is not the top of the document (root ADR 0462).
-}
langBody :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
langBody ctx = langBodyWith (evalBlocks ctx)

-- | The body form of @lang, its blocks evaluated by the function given (the body of @style passes its paragraph style, root ADR 0460).
langBodyWith :: ([A.Located A.Block] -> M [Block]) -> SrcSpan -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
langBodyWith evalBody sp args body = do
  tag <- langTag sp args
  bodyValues body (evalBody body) $ \bs ->
    pure [if isBreakBlock (blockBody b) then b else withLang tag b | b <- bs]

-- | A forced break, a page control, blank lines or a separator: a point between the blocks, not a block of text.
isBreakBlock :: BlockBody -> Bool
isBreakBlock = \case
  ForcedBreak _ -> True
  PageControl _ -> True
  BlankLines _ -> True
  Separator _ -> True
  _ -> False

-- | A block with a language, unless it has one of its own (docs/adr ADR 0187).
withLang :: Maybe Text -> Block -> Block
withLang l b = b {blockLang = blockLang b <|> l}

{- | Forced breaks below the top of the document are dropped with G02059
(docs/adr ADR 0017), the controls of page breaks with G02071 (docs/adr ADR
0030), and blank lines with G02093 (docs/adr ADR 0046).
-}
nestedBreaks :: [Block] -> ([Block], [Diagnostic])
nestedBreaks bs = let (ds, bs') = concat <$> traverse top bs in (bs', ds)
  where
    top b = if isBreakBlock (blockBody b) then ([], [b]) else belowTop b

-- | The diagnostics and what is left of a block below the top of the document ('nestedBreaks').
belowTop :: Block -> ([Diagnostic], [Block])
belowTop = inner
  where
    inner :: Block -> ([Diagnostic], [Block])
    inner b@(Block sp lbl lang body) = case body of
      ForcedBreak _ -> ([diagnostic "G02059" Error sp "@page-break と @column-break は文書の最上位にだけ置けます"], [])
      PageControl _ -> ([diagnostic "G02071" Error sp "@no-page-break、@need-lines、@page-lines は文書の最上位にだけ置けます"], [])
      BlankLines _ -> ([diagnostic "G02093" Error sp "@blank-line は文書の最上位にだけ置けます"], [])
      Separator _ -> ([diagnostic "G02159" Error sp "区切りは文書の最上位にだけ置けます"], [])
      BulletList items -> rebuild BulletList <$> traverse item items
      OrderedList items -> rebuild OrderedList <$> traverse item items
      DefList gs -> rebuild DefList <$> traverse (\(DefGroup ts ds) -> DefGroup ts <$> traverse nested ds) gs
      FigureBlock f -> rebuild (\c -> FigureBlock f {figCaption = c}) <$> nested (figCaption f)
      FrameBlock name bs' -> rebuild (FrameBlock name) <$> nested bs'
      _ -> ([], [b])
      where
        rebuild f x = [Block sp lbl lang (f x)]
    item (ListItem n bs') = ListItem n <$> nested bs'
    nested bs' = concat <$> traverse inner bs'

applyAttr :: EvalContext -> (Maybe Text, BlockBody) -> A.Located A.Block -> M (Maybe Text, BlockBody)
applyAttr ctx (label, body) (A.Located sp cmd) = case cmd of
  A.BlockCommand (A.Located _ name) args _ -> case (name, body) of
    ("label", _) -> case map A.locValue args of
      [A.Positional v] | Just l <- nameArg v, validLabel l -> pure (Just l, body)
      _ -> err "G02026" sp "@label にはラベルの名前を一つ書きます。名前は英小文字、数字、-、_ で書きます" >> pure (label, body)
    ("toc-title", Heading l a is) -> do
      t <- evalInlines ctx True [A.Located sp (A.Text (T.unwords (map (argText . positional) args)))]
      pure (label, Heading l a {haTocTitle = Just t} is)
    ("number", Heading l a is) -> withNumber $ \n -> Heading l a {haNumber = Just n} is
    ("number", OrderedList (ListItem _ bs : rest)) -> withNumber $ \n -> OrderedList (ListItem (Just n) bs : rest)
    ("nonumber", Heading l a is) -> pure (label, Heading l a {haNoNumber = True} is)
    -- a figure and a code block without a number (docs/adr/0200); G02134 is decided after every attribute
    ("nonumber", FigureBlock f) -> pure (label, FigureBlock f {figNoNumber = True})
    ("nonumber", CodeBlock c) -> pure (label, CodeBlock c {codeNoNumber = True})
    ("nonumber", TableBlock t) -> pure (label, TableBlock t {tableNoNumber = True})
    ("notoc", Heading l a is) -> pure (label, Heading l a {haNoToc = True} is)
    -- the style of a paragraph is applied when the paragraph is evaluated
    ("style", Paragraph {}) -> pure (label, body)
    -- the paragraph style of the cells of a table (docs/adr/0262)
    ("style", TableBlock t) ->
      styleName ctx sp args >>= \case
        Just r
          | Map.notMember (styleRefName r) (ctxParaStyles ctx) -> err "G02047" sp ("定義されていない段落スタイルです: " <> styleRefName r) >> pure (label, body)
          | r == "table" -> pure (label, body)
          | otherwise -> pure (label, TableBlock t {tableStyle = Just r})
        Nothing -> pure (label, body)
    ("column-widths", TableBlock t) -> (\ws -> (label, TableBlock t {tableWidths = ws})) <$> columnWidths sp (length (tableHeader t)) args
    -- the language goes to any block, after the other attributes (docs/adr ADR 0187)
    ("lang", _) -> pure (label, body)
    -- the caption of a code block: the rest of the line, inlines included (golem-driver ADR 0023)
    ("caption", CodeBlock c)
      | null args -> err "G02069" sp "@caption には本文を書きます" >> pure (label, body)
      | otherwise -> do
          is <- evalInlines ctx False (captionInlines args)
          pure (label, CodeBlock c {codeCaption = Just is})
    -- the caption of a table, as that of a code block (docs/adr/0262)
    ("caption", TableBlock t)
      | null args -> err "G02069" sp "@caption には本文を書きます" >> pure (label, body)
      | otherwise -> do
          is <- evalInlines ctx False (captionInlines args)
          pure (label, TableBlock t {tableCaption = Just is})
    _ -> err "G02013" sp ("@" <> name <> " はこのブロックには付けられません") >> pure (label, body)
    where
      withNumber f = case args of
        [A.Located asp (A.Positional v)] ->
          naturalArg ctx "@number の引数" sp (A.Located asp v) >>= \case
            Right n
              | inInt64 (toInteger n) -> pure (label, f n)
              -- G02091: as if there were no @number (golem-doc ADR 0006)
              | otherwise -> outOfInt64 sp >> pure (label, body)
            Left NaturalReported -> pure (label, body)
            Left NotANumber -> wrongNumber
        _ -> wrongNumber
      wrongNumber = err "G02027" sp "@number には整数を一つ書きます" >> pure (label, body)
  _ -> pure (label, body)
  where
    positional = \case
      A.Located _ (A.Positional v) -> v
      A.Located _ (A.Keyword _ v) -> v
      A.Located _ _ -> A.Word ""

{- | The widths of @column-widths for a table of @n@ columns (docs/adr/0262):
auto, a length or a percentage each; G02135 at each value that is none of
them, G02136 when there are neither one nor @n@ values, and no widths
(every column auto) after either.
-}
columnWidths :: SrcSpan -> Int -> [A.Located A.Argument] -> M [ColumnWidth]
columnWidths sp n args = do
  read' <- mapM one args
  case sequence read' of
    Nothing -> pure []
    Just ws
      | [w] <- ws -> pure (replicate n w)
      | length ws == n, n > 0 -> pure ws
      | otherwise -> err "G02136" sp ("@column-widths の値の数が表の列の数と違います。値を一つか列の数（" <> tshow n <> "）だけ書きます") >> pure []
  where
    one (A.Located asp a) = case a of
      A.Positional (A.Word t) | Just w <- columnWidthOf t -> pure (Just w)
      A.Positional (A.StringLit t) | Just w <- columnWidthOf t -> pure (Just w)
      _ -> err "G02135" asp ("@column-widths の値が読めません。auto、寸法（10zw、30mm など）、割合（50% など）で書きます: " <> argSource a) >> pure Nothing
    argSource = \case
      A.Positional (A.Word t) -> t
      A.Positional (A.StringLit t) -> t
      _ -> "[= ...]"

-- | A width of a column as written: auto, or a width as that of a figure (docs/adr/0190, docs/adr/0262).
columnWidthOf :: Text -> Maybe ColumnWidth
columnWidthOf t
  | T.strip t == "auto" = Just ColumnAuto
  | otherwise =
      flip fmap (parseFigureWidth t) $ \case
        WidthLength x -> ColumnAbs x
        WidthZw q -> ColumnZw q
        WidthPercent q -> ColumnPercent q

-- | The message of G02142 (docs/adr/0263).
noteNameMessage :: Text
noteNameMessage = "注の名前を一つの語で書きます。名前は英小文字、数字、-、_ で書きます"

{- | The two kinds of notes written by name: the notes (docs/adr/0263) and
the endnotes (root ADR 0412), each with names of its own.
-}
data NoteKind = FootKind | EndKind
  deriving stock (Eq)

-- | The name of the command of a kind of notes.
kindCommand :: NoteKind -> Text
kindCommand = \case
  FootKind -> "note"
  EndKind -> "endnote"

-- | The definitions of a kind of notes so far.
kindDefs :: NoteKind -> St -> [(Text, SrcSpan, [Block])]
kindDefs = \case
  FootKind -> stNoteDefs
  EndKind -> stEndnoteDefs

{- | @note name with its body (docs/adr/0263): the body evaluated here,
its paragraphs the body of the note; G02142 for a name not of one word,
G02140 for a name already defined (the first wins), G02141 at each block
of the body that is not a paragraph, which is dropped, G02143 for no body,
G02013 for @style on a paragraph of the body, whose style is dropped.
It puts out nothing where it is.
-}
noteDefinition :: EvalContext -> NoteKind -> SrcSpan -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
noteDefinition ctx kind sp args body = case args of
  [A.Located _ (A.Positional v)]
    | Just name <- nameArg v,
      validLabel name -> do
        defined <- gets (any (\(n, _, _) -> n == name) . kindDefs kind)
        when defined $ err "G02140" sp ("同じ名前の注の本文を二度書いています: " <> name)
        when (null body) $ err "G02143" sp ("@" <> kindCommand kind <> " に本文がありません: " <> name)
        bodyValues body (concat <$> mapM (paragraphsOnly ctx ("G02141", "注の本文には段落だけを書けます") "@style は注の本文には付けられません") body) $ \bs -> do
          unless defined $ modify' $ \s -> case kind of
            FootKind -> s {stNoteDefs = stNoteDefs s <> [(name, sp, bs)]}
            EndKind -> s {stEndnoteDefs = stEndnoteDefs s <> [(name, sp, bs)]}
          pure []
  _ -> err "G02142" sp noteNameMessage >> pure []

{- | The body of a block that holds paragraphs only (@note, @endnote,
@frame): the code given at each block of the body that is not a
paragraph, and at each break, page control, blank line and separator of a
group, which are dropped (root ADR 0462); G02013 for @style on a
paragraph of the body, whose style is dropped.
-}
paragraphsOnly :: EvalContext -> (Text, Text) -> Text -> A.Located A.Block -> M [Block]
paragraphsOnly ctx (code, message) styleMessage lb0 = builtinBlockAt ctx >>= \isBuiltin -> inBody isBuiltin lb0
  where
    inBody isBuiltin lb@(A.Located bsp b) =
      let isStyleCommand' = isStyleCommand isBuiltin
       in case b of
            A.Attributed cmds t | (breaks@(_ : _), rest) <- partition (isBreakCommand isBuiltin) cmds -> do
              mapM_ (\(A.Located csp _) -> err code csp message) breaks
              if null rest then maybe (pure []) (inBody isBuiltin) t else inBody isBuiltin (A.Located bsp (A.Attributed rest t))
            A.Paragraph _ -> unstyled <$> evalBlock ctx lb
            A.Attributed cmds t@(Just (A.Located _ (A.Paragraph _))) | any isStyleCommand' cmds -> do
              mapM_ (\(A.Located csp _) -> err "G02013" csp styleMessage) (filter isStyleCommand' cmds)
              unstyled <$> evalBlock ctx (A.Located bsp (A.Attributed (filter (not . isStyleCommand') cmds) t))
            A.Attributed _ (Just (A.Located _ (A.Paragraph _))) -> unstyled <$> evalBlock ctx lb
            -- the body form of the built-in @style: G02013, its paragraphs without the style, its other blocks the code given
            A.BlockCommand _ _ inner | isStyleCommand' lb -> do
              err "G02013" bsp styleMessage
              concat <$> mapM (inBody isBuiltin . joined) inner
            A.ErrorBlock -> pure []
            _ -> err code bsp message >> pure []
    joined = \case
      A.Located psp (A.Paragraph is) -> A.Located psp (A.Paragraph (joinSoftBreaks is))
      other -> other
    -- a paragraph with a style (a body form of @style) loses it
    unstyled = concatMap $ \case
      Block bsp l lang (Paragraph _ is) -> [Block bsp l lang (Paragraph Nothing is)]
      _ -> []

{- | @frame NAME and its paragraphs (root ADR 0438): a text frame of
style.toml that takes no room in the flow. The name is one word of the
letters of a style name (G02255); the body holds paragraphs only
(G02256), without @style (G02013), as the body of a @note. Whether
[frames] has the name is checked once the style is known (G03289).
-}
frameBlock :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
frameBlock ctx sp args body = case args of
  [A.Located _ (A.Positional v)]
    | Just name <- nameArg v,
      frameName name -> do
        bodyValues body (concat <$> mapM (paragraphsOnly ctx ("G02256", "フレームの中身には段落だけを書けます") "@style はフレームの中の段落には付けられません") body) $ \bs ->
          pure [block sp (FrameBlock name bs)]
  _ -> err "G02255" sp "@frame にはフレームの名前を一つ書きます" >> pure []
  where
    frameName name = case T.uncons name of
      Just (c, rest) -> isAsciiLower c && T.all (\x -> isAsciiLower x || isDigit x || x == '-') rest
      Nothing -> False

{- | The notes written by name take the bodies of their @note
(docs/adr/0263): G02137 for a name no @note of the file defines, G02139
for a second [note] of the same name, which puts out nothing, as one of
a body left without a paragraph does; G02138 for a @note no [note]
names.
-}
namedNotes :: NoteKind -> [(SrcSpan, Text)] -> [(Text, SrcSpan, [Block])] -> [Block] -> ([Block], [Diagnostic])
namedNotes kind refs defs bs
  | null refs && null defs = (bs, [])
  | otherwise = (mapBlockInlines fill bs, refDiags <> unused)
  where
    bodies = Map.fromList [(n, body) | (n, _, body) <- defs]
    firsts = Map.fromListWith (\_ a -> a) [(n, sp) | (sp, n) <- refs]
    refDiags =
      concat
        [ case Map.lookup n bodies of
            Nothing -> [diagnostic "G02137" Error sp ("定義されていない注の名前です: " <> n)]
            Just _
              | Map.lookup n firsts /= Just sp -> [diagnostic "G02139" Error sp ("一つの注の本文を二つ以上の [" <> kindCommand kind <> "] が指しています: " <> n)]
              | otherwise -> []
        | (sp, n) <- refs
        ]
    unused = [diagnostic "G02138" Error sp ("使われない注の本文です: " <> n) | (n, sp, _) <- defs, Map.notMember n firsts]
    names = Map.fromList refs
    fill = \case
      Note sp k lbl []
        | kind == FootKind,
          Just n <- Map.lookup sp names ->
            case Map.lookup n bodies of
              Just body@(_ : _) | Map.lookup n firsts == Just sp -> [Note sp k lbl body]
              _ -> []
      -- an endnote written by name (root ADR 0412)
      Endnote sp k lbl []
        | kind == EndKind,
          Just n <- Map.lookup sp names ->
            case Map.lookup n bodies of
              Just body@(_ : _) | Map.lookup n firsts == Just sp -> [Endnote sp k lbl body]
              _ -> []
      other -> [other]

{- | Blocks with each inline at any depth replaced by what a function
gives for it, inside lists, definition lists, tables, captions and the
containers of inlines (docs/adr/0263).
-}
mapBlockInlines :: (Inline -> [Inline]) -> [Block] -> [Block]
mapBlockInlines f = map blk
  where
    blk b = b {blockBody = body (blockBody b)}
    body = \case
      Paragraph st is -> Paragraph st (inls is)
      Heading l a is -> Heading l a {haTocTitle = inls <$> haTocTitle a} (inls is)
      BulletList items -> BulletList [i {itemBlocks = map blk (itemBlocks i)} | i <- items]
      OrderedList items -> OrderedList [i {itemBlocks = map blk (itemBlocks i)} | i <- items]
      DefList gs -> DefList [DefGroup (map inls ts) (map (map blk) ds) | DefGroup ts ds <- gs]
      TableBlock t -> TableBlock t {tableCaption = inls <$> tableCaption t, tableHeader = map inls (tableHeader t), tableRows = map (map inls) (tableRows t)}
      CodeBlock c -> CodeBlock c {codeCaption = inls <$> codeCaption c}
      FigureBlock fig -> FigureBlock fig {figCaption = map blk (figCaption fig)}
      FrameBlock name bs -> FrameBlock name (map blk bs)
      other -> other
    inls = concatMap (f . inner)
    inner = \case
      Kenten sp sh xs -> Kenten sp sh (inls xs)
      Color sp c xs -> Color sp c (inls xs)
      CharStyle sp c xs -> CharStyle sp c (inls xs)
      Link sp u xs -> Link sp u (inls xs)
      Lang sp l xs -> Lang sp l (inls xs)
      Resolved sp k l xs -> Resolved sp k l (inls xs)
      other -> other

{- | The arguments of @caption as inlines (golem-driver ADR 0023): words
and strings are text, commands and expressions are themselves, a space
between two arguments.
-}
captionInlines :: [A.Located A.Argument] -> [A.Located A.Inline]
captionInlines args = concat (zipWith (\i a -> [space a | i > (0 :: Int)] <> one a) [0 ..] args)
  where
    space (A.Located asp _) = A.Located (mkSpan (spanFile asp) (spanStart asp) (spanStart asp)) (A.Text " ")
    one (A.Located asp a) = case a of
      A.Positional v -> value asp v
      A.Keyword (A.Located _ k) v -> A.Located asp (A.Text (k <> "=")) : value asp v
      _ -> []
    value asp = \case
      A.Word t -> [A.Located asp (A.Text t)]
      A.StringLit t -> [A.Located asp (A.Text t)]
      A.CommandArg i -> [i]
      A.ExprArg e -> [A.Located asp (A.Expr e)]

validLabel :: Text -> Bool
validLabel l = not (T.null l) && T.all (\c -> c `elem` ("-_" :: String) || isAsciiLower c || isDigit c) l

-- ------------------------------------------------------------------ paragraph styles

{- | The paragraph style of @style: the name, and the keys of its named
arguments over it (root ADR 0467, 'styleKeys'); G02047 and body when it
has not one name. code is the style of code blocks: G02066 and body
(golem-driver ADR 0017).
-}
styleName :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> M (Maybe StyleRef)
styleName ctx sp args = case [a | a@(A.Located _ arg) <- args, not (isKeywordArg arg)] of
  [A.Located _ (A.Positional v)] | nameArg v == Just "code" -> err "G02066" sp "code はコードブロックの段落スタイルです。コードは ``` か @listing で書きます" >> pure Nothing
  [A.Located _ (A.Positional v)] | Just n <- nameArg v -> Just . StyleRef n <$> styleKeys ctx sp n args
  _ -> err "G02047" sp "@style には段落スタイルの名前を一つ書きます" >> pure Nothing
  where
    isKeywordArg = \case
      A.Keyword {} -> True
      _ -> False

{- | The keys of the named arguments of @style (root ADR 0467): the keys
of a paragraph style that @style-def takes but based-on, each value
checked as @style-def checks it, with its codes. based-on and any other
name is G02288 at its argument; a value that is no word nor string is
G02116; a key written twice, which the reading of the arguments has
reported (G02077), is left out as @style-def leaves it out. A wrong key is
left out and the others take effect. The keys are then checked together
as a definition of the style with them over it; an error there is at the
@style, and leaves every key out.
-}
styleKeys :: EvalContext -> SrcSpan -> Text -> [A.Located A.Argument] -> M (Map Text StyleValue)
styleKeys ctx sp name args = do
  let kws = [(k, ksp, v) | A.Located ksp (A.Keyword (A.Located _ k) v) <- args]
      keys = [k | (k, _, _) <- kws]
      twice k = length (filter (== k) keys) > 1
  read' <- fmap catMaybes . forM kws $ \(k, ksp, v) ->
    if k == "based-on" || k `notElem` paraStyleKeys
      then err "G02288" ksp ("@style の名前付き引数に書けない名前です: " <> k) >> pure Nothing
      else case localValue v of
        Nothing -> report (notWordDiagnostic ksp) >> pure Nothing
        Just lv
          | twice k -> pure Nothing
          | otherwise -> case localStyleDefWithValues (ctxStyle ctx) ParagraphKind [(k, lv)] of
              Left ms -> mapM_ (\(code, m) -> report (styleDefValueDiagnostic "@style" code ksp m)) ms >> pure Nothing
              Right _ -> pure (Just (k, lv, ()))
  let local = ctxLocalStyles ctx
      before = checkLocalStyles (ctxStyle ctx) local
      -- the style as @style-def paragraph KEY based-on=NAME with the keys defines it, KEY a name no style has
      taken = Map.keysSet (ctxParaStyles ctx)
      key = fromMaybe name (listToMaybe [k | i <- [1 :: Int ..], let k = name <> "-" <> tshow i, Set.notMember k taken])
      wrong = case localStyleDefWithValues (ctxStyle ctx) ParagraphKind [(k, lv) | (k, lv, _) <- read'] of
        Right (Right overrides) ->
          let over = local {lsParaStyles = Map.insert key overrides {psBasedOn = Just name} (lsParaStyles local)}
           in [(code, T.replace key name m) | c@(code, _, m) <- checkLocalStyles (ctxStyle ctx) over, c `notElem` before, code /= "G03100"]
        Right (Left _) -> []
        Left ms -> ms
      keysOf = Map.fromList [(k, styleValue lv) | (k, lv, _) <- read']
  if null read' || Map.notMember name (ctxParaStyles ctx) || null wrong
    then pure keysOf
    else mapM_ (\(code, m) -> err code sp m) wrong >> pure Map.empty
  where
    styleValue = \case
      LocalWord w -> StyleWord w
      LocalString t -> StyleString t

{- | The style of a paragraph of @style (root ADR 0467): body without keys
is Nothing, as before the ADR.
-}
paragraphRef :: StyleRef -> Maybe StyleRef
paragraphRef r = if r == "body" then Nothing else Just r

-- | The keys of a paragraph style as the values @style-def reads (root ADR 0467).
refValues :: StyleRef -> [(Text, LocalValue)]
refValues r = [(k, case v of StyleWord w -> LocalWord w; StyleString t -> LocalString t) | (k, v) <- Map.toAscList (styleRefKeys r)]

{- | The body form of @style (docs/adr ADR 0005): the blocks of the body in
order, with the paragraph style passed to them (root ADR 0460,
'evalStyled'). G02046 when the result has neither a paragraph nor a
table; the blocks are put out all the same.
-}
styleBody :: EvalContext -> SrcSpan -> Int -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
styleBody ctx sp headerEnd args body
  -- no body at all, or a body of comments only (the command spans more than its line)
  | null body && spanEnd sp <= headerEnd + 1 = err "G02010" sp "@style の後にブロックがありません" >> pure []
  | null body = err "G02046" sp "@style の本体に段落がありません" >> pure []
  | otherwise = do
      ref <- styleName ctx sp args
      -- The body is validated before styling can become a successful result.
      bodyValues body (concat <$> mapM (evalStyled ctx (Passed sp ref)) body) $ \bs -> do
        unless (hasParagraphOrTable bs) $ err "G02046" sp "@style の本体に段落がありません"
        pure bs

{- | A paragraph in a paragraph style (docs/adr ADR 0005). An unknown style
is G02047 and the paragraph is body. With line-breaks = "keep" each line
of the source is a line, joined by 'LineBreak'; a paragraph with no line
left is dropped.
-}
styledParagraph :: EvalContext -> SrcSpan -> Maybe StyleRef -> [A.Located A.Inline] -> M [Block]
styledParagraph ctx sp mref is = case mref of
  Nothing -> joined Nothing
  Just ref -> case keysLineBreaks ref <$> Map.lookup (styleRefName ref) (ctxParaStyles ctx) of
    Nothing -> err "G02047" sp ("定義されていない段落スタイルです: " <> styleRefName ref) >> joined Nothing
    Just JoinLines -> joined (paragraphRef ref)
    Just KeepLines -> do
      mapM_ escapedIndent (linesOf Nothing is)
      mapM_ (escapedTrailing . snd) (linesOf Nothing is)
      ls <- filter (not . null . snd) <$> mapM (\(bsp, l) -> (bsp,) <$> evalInlines ctx False (A.plainEscapes (trimLine l))) (linesOf Nothing is)
      pure $ case ls of
        [] -> []
        ((_, first) : rest) -> [block sp (Paragraph (paragraphRef ref) (first <> concat [LineBreak bsp : l | (bsp, l) <- rest]))]
  where
    -- the line-breaks of the keys over those of the style (root ADR 0467)
    keysLineBreaks r own = case Map.lookup "line-breaks" (styleRefKeys r) of
      Just (StyleWord "keep") -> KeepLines
      Just (StyleString "keep") -> KeepLines
      Just (StyleWord "join") -> JoinLines
      Just (StyleString "join") -> JoinLines
      _ -> own
    {- G02064: an escaped space or tab at the start of a line is dropped
    as the plain ones are (golem-syntax ADR 0002). The line starts with
    the escape (golem-parser ADR 0010). -}
    escapedIndent = \case
      (_, A.Located tsp (A.Escaped c) : _)
        | c == ' ' || c == '\t' ->
            report (notice "G02064" (mkSpan (spanFile tsp) (spanStart tsp) (spanStart tsp + 1)) "行頭のエスケープした空白は無視されます。字下げには全角の空白を使います")
      _ -> pure ()
    {- G02079: an escaped space or tab among the spaces and tabs at the end
    of a line is dropped as well (golem-parser ADR 0012); one notice at
    the first such escape. A line of blanks only is the indent of G02064. -}
    escapedTrailing l = case [tsp | A.Located tsp (A.Escaped _) <- reverse (takeWhile blankEnd (reverse l))] of
      (tsp : _) | not (all blankEnd l) -> report (notice "G02079" (mkSpan (spanFile tsp) (spanStart tsp) (spanStart tsp + 1)) "行末のエスケープした空白は無視されます")
      _ -> pure ()
    joined st = (\x -> [block sp (Paragraph st x)]) <$> hardLines ctx sp is
    -- lines with the span of the newline before each (the first has none);
    -- a hard break is a newline here (docs/adr ADR 0016)
    linesOf before xs = case break (\x -> isSoftBreak x || isHardBreak x) xs of
      (l, []) -> [(fromMaybe sp before, l)]
      (l, A.Located bsp _ : rest) -> (fromMaybe sp before, l) : linesOf (Just bsp) rest

{- | The inlines of a paragraph that joins its lines, broken at its hard
breaks (docs/adr ADR 0016): the lines joined by 'LineBreak'. A line left
empty, or whose first source line has nothing in it, is G02057; an empty
line goes with the break before it.
-}
hardLines :: EvalContext -> SrcSpan -> [A.Located A.Inline] -> M [Inline]
hardLines ctx sp is = do
  let ls = splitHard Nothing is
  evaluated <- mapM (\(bsp, l) -> (bsp,l,) <$> evalInlines ctx False (joinSoftBreaks l)) ls
  let breaks = [bsp | (Just bsp, _, _) <- evaluated]
      -- where an empty line is reported: the break before it, or after it for the first line
      at = \case
        Just bsp -> bsp
        Nothing -> case breaks of
          (b : _) -> b
          [] -> sp
      emptyStart = \case
        (A.Located _ A.SoftBreak : _) -> True
        _ -> False
      bad (_, l, x) = null x || emptyStart l
  unless (null breaks) $
    mapM_ (\(bsp, _, _) -> err "G02057" (at bsp) "強制改行の前後に文字がありません") (filter bad evaluated)
  pure $ case [(bsp, x) | (bsp, _, x) <- evaluated, not (null x)] of
    [] -> []
    ((_, first) : rest) -> first <> concat [maybe [] (pure . LineBreak) bsp <> x | (bsp, x) <- rest]
  where
    splitHard before xs = case break isHardBreak xs of
      (l, []) -> [(before, l)]
      (l, A.Located bsp _ : rest) -> (before, l) : splitHard (Just bsp) rest

{- | Paragraph styles a filter made up (docs/adr ADR 0005), and the keys of
a style that @style could not take (G02288, root ADR 0467).
-}
unknownParaStyles :: EvalContext -> Document -> [Diagnostic]
unknownParaStyles ctx (Document _ bs) = concatMap go bs
  where
    ref sp r =
      [diagnostic "G02047" Error sp ("定義されていない段落スタイルです: " <> styleRefName r) | Map.notMember (styleRefName r) (ctxParaStyles ctx)]
        <> [diagnostic "G02288" Error sp ("@style の名前付き引数に書けない名前です: " <> k) | k <- Map.keys (styleRefKeys r), k == "based-on" || k `notElem` paraStyleKeys]
    go (Block sp _ _ body) = case body of
      Paragraph (Just r) _ -> ref sp r
      TableBlock Table {tableStyle = Just r} -> ref sp r
      BulletList items -> concatMap (concatMap go . itemBlocks) items
      OrderedList items -> concatMap (concatMap go . itemBlocks) items
      DefList gs -> concatMap (concatMap (concatMap go) . dgDefs) gs
      FigureBlock f -> concatMap go (figCaption f)
      FrameBlock _ inner -> concatMap go inner
      _ -> []

{- | Spaces and tabs at the start and the end of a line are not text,
escaped ones included (golem-parser ADR 0012). It runs before
'A.plainEscapes', so that the 'A.Text' it cuts has no escape in it and its
span shrinks by the characters cut.
-}
trimLine :: [A.Located A.Inline] -> [A.Located A.Inline]
trimLine = trimEnd . trimStart
  where
    trimStart = \case
      (x : rest) | blankEnd x -> trimStart rest
      (A.Located tsp (A.Text t) : rest) ->
        let t' = T.dropWhile isSpaceTab t
            tsp' = mkSpan (spanFile tsp) (spanStart tsp + T.length t - T.length t') (spanEnd tsp)
         in [A.Located tsp' (A.Text t') | not (T.null t')] <> rest
      is -> is
    trimEnd is = case reverse is of
      (x : rest) | blankEnd x -> trimEnd (reverse rest)
      (A.Located tsp (A.Text t) : rest) ->
        let t' = T.dropWhileEnd isSpaceTab t
            tsp' = mkSpan (spanFile tsp) (spanStart tsp) (spanEnd tsp - (T.length t - T.length t'))
         in reverse rest <> [A.Located tsp' (A.Text t') | not (T.null t')]
      _ -> is

-- | A text of spaces and tabs only, or an escaped space or tab.
blankEnd :: A.Located A.Inline -> Bool
blankEnd = \case
  A.Located _ (A.Text t) -> T.all isSpaceTab t
  A.Located _ (A.Escaped c) -> isSpaceTab c
  _ -> False

-- ------------------------------------------------------------------ figures, tables, listings

{- | The checks of a figure over the IR (golem-pdf ADR 0008, 0009,
golem-driver ADR 0034): the formats (G02074, G02073), the page (G02075),
the image files (as the caller finds them), the web image of a PDF
(G02029), then, when all those pass, wrap and rotate (G02087, G02031).
The steps are those @figure takes, in the same order; @figure reads its
arguments between them, so that a figure of the source reports what it
always did.
-}
checkFigure :: SrcSpan -> (Text -> M Bool) -> Figure -> M Bool
checkFigure sp exists f = do
  let fmts = figureFormatErrors sp (figSource f) (figWeb f)
  mapM_ report fmts
  pageOk <- case figPage f of
    Just n | not (isPdfFigure (figSource f)) || not (figurePageInRange (toInteger n)) -> report (figurePageError sp (tshow n)) >> pure False
    _ -> pure True
  files <- and <$> sequence [exists (figSource f), maybe (pure True) exists (figWeb f)]
  if figureNeedsWeb (figSource f) (figWeb f)
    then report (figureNeedsWebError sp) >> pure False
    else
      if not (null fmts && pageOk && files)
        then pure False
        else case figureLayoutError sp sp (figWrap f) (figRotate f) (figWidth f) of
          Just d -> report d >> pure False
          Nothing -> pure True

{- | 'checkFigure' of a figure of the IR, its files found as @figure finds
them: the diagnostics, and whether the figure passes.
-}
figureChecks :: EvalContext -> SrcSpan -> Figure -> ([Diagnostic], Bool)
figureChecks ctx sp f =
  let st0 = St Map.empty Map.empty Map.empty [] Set.empty Map.empty [] 0 0 0 [] Map.empty Map.empty [] [] [] [] Map.empty [] Set.empty Map.empty Map.empty [] Set.empty Set.empty Set.empty []
      (ok, st) = runState (checkFigure sp (fmap isJust . asset ctx sp) f) st0
   in (stDiags st, ok)

-- | G02029: a PDF figure without a web image.
figureNeedsWebError :: SrcSpan -> Diagnostic
figureNeedsWebError sp = diagnostic "G02029" Error sp "PDF の図版には web の代替画像が必要です"

-- | G02074 for an image that is not PDF, PNG, JPEG or SVG; G02073 for a web image that is not PNG, JPEG or SVG.
figureFormatErrors :: SrcSpan -> Text -> Maybe Text -> [Diagnostic]
figureFormatErrors sp path web =
  [diagnostic "G02074" Error sp ("図版の形式は PDF、PNG、JPEG、SVG です: " <> path) | figureExtension path `notElem` [".pdf", ".png", ".jpg", ".jpeg", ".svg"]]
    <> [diagnostic "G02073" Error sp ("web の代替画像は PNG、JPEG、SVG です: " <> w) | Just w <- [web], figureExtension w `notElem` [".png", ".jpg", ".jpeg", ".svg"]]

-- | G02075 with the page as written.
figurePageError :: SrcSpan -> Text -> Diagnostic
figurePageError sp p = diagnostic "G02075" Error sp ("page は PDF の図版のページを 1 から数えた整数で書きます: " <> p)

-- | The pages of a PDF figure: from 1, below 10^9.
figurePageInRange :: Integer -> Bool
figurePageInRange n = n >= 1 && n < 10 ^ (9 :: Int)

isPdfFigure :: Text -> Bool
isPdfFigure path = figureExtension path == ".pdf"

-- | A PDF figure needs a web image (G02029).
figureNeedsWeb :: Text -> Maybe Text -> Bool
figureNeedsWeb path web = isPdfFigure path && isNothing web

{- | G02087 for a figure both turned and wrapped, G02031 for a wrapped
figure without a width, G02133 at the width (@wsp@) for a width that is
neither a length nor a percentage of the measure, or 0 (docs/adr/0190).
-}
figureLayoutError :: SrcSpan -> SrcSpan -> Maybe Wrap -> Bool -> Maybe Text -> Maybe Diagnostic
figureLayoutError sp wsp wr rot width
  | rot && isJust wr = Just (diagnostic "G02087" Error sp "回して置く図版は回り込ませられません")
  | isJust wr && isNothing width = Just (diagnostic "G02031" Error sp "回り込む図版には width が必要です")
  | Just w <- width, isNothing (parseFigureWidth w) = Just (diagnostic "G02133" Error wsp ("図版の width が読めません。寸法（10zw、50mm など）か行長の割合（50% など）で書きます: " <> w))
  | otherwise = Nothing

-- | The extension of a path in lower case, with its dot.
figureExtension :: Text -> Text
figureExtension p = case T.breakOnEnd "." p of
  (before, after) | not (T.null before), not ("/" `T.isInfixOf` after) -> "." <> T.toLower after
  _ -> ""

figure :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
figure ctx sp args body = do
  kw <- keywords ctx args
  let pos = [v | A.Located _ (A.Positional v) <- args]
      look k = argText <$> lookup k kw
  case pos of
    [src] -> do
      let path = argText src
          web = look "web"
          ok = and <$> sequence [check path, maybe (pure True) check web]
          isPdf = isPdfFigure path
      -- the formats by the extension, the same for every output (golem-pdf ADR 0008, 0009)
      let fmts = figureFormatErrors sp path web
      mapM_ report fmts
      let formats = null fmts
          wrongPage p = report (figurePageError sp (argText p)) >> pure (Left ())
      page <- case keywordAt "page" args of
        Nothing -> pure (Right Nothing)
        Just lp@(A.Located _ p)
          | not isPdf -> wrongPage p
          | otherwise ->
              naturalArg ctx "@figure の page" sp lp >>= \case
                Right n | figurePageInRange (toInteger n) -> pure (Right (Just (fromIntegral n)))
                Left NaturalReported -> pure (Left ())
                _ -> wrongPage p
      fine <- (&& formats) <$> ok
      isBuiltin <- builtinBlockAt ctx
      bodyValues body (captionParagraphs =<< evalCaption . concat =<< mapM (unstyled isBuiltin) body) $ \caption -> do
        case look "alt" of
          Nothing -> err "G02028" sp "図版には alt の代替テキストが必要です" >> pure []
          Just alt
            | figureNeedsWeb path web -> report (figureNeedsWebError sp) >> pure []
            | not fine || isLeft page -> pure []
            | otherwise -> do
                wrap <- case look "wrap" of
                  Nothing -> pure (Right Nothing)
                  Just "start" -> pure (Right (Just WrapStart))
                  Just "end" -> pure (Right (Just WrapEnd))
                  Just w -> pure (Left w)
                -- a figure turned onto a page of its own in the PDF (golem-driver ADR 0034)
                let rotate = case look "rotate" of
                      Nothing -> Right False
                      Just "true" -> Right True
                      Just "false" -> Right False
                      Just r -> Left r
                case (wrap, rotate) of
                  (Left w, _) -> err "G02030" sp ("wrap は start か end です: " <> w) >> pure []
                  (_, Left r) -> err "G02087" sp ("rotate は true か false です: " <> r) >> pure []
                  (Right wr, Right rot) -> case figureLayoutError sp (maybe sp (\(A.Located wsp _) -> wsp) (keywordAt "width" args)) wr rot (look "width") of
                    Just d -> report d >> pure []
                    Nothing -> do
                      outline <- figureOutline wr
                      pure [block sp (FigureBlock (Figure path web alt wr (look "width") caption (fromRight Nothing page) rot False outline))]
    _ -> err "G02032" sp "@figure には画像のパスを一つ書きます" >> pure []
  where
    check p = isJust <$> asset ctx sp p
    {- the outline of a wrapped figure, at the argument (root ADR 0464): on a
    figure without wrap it is not used, G02286; a name style.toml does not
    have is G02285, and the figure is set by its rectangle -}
    figureOutline wr = case keywordAt "outline" args of
      Nothing -> pure Nothing
      Just (A.Located osp o)
        | isNothing wr -> Nothing <$ report (diagnostic "G02286" Warning osp "outline は wrap のある図版にだけ使います")
        | Map.notMember (argText o) (stOutlines (ctxStyle ctx)) -> Nothing <$ err "G02285" osp ("輪郭 " <> argText o <> " がありません")
        | otherwise -> pure (Just (argText o))
    {- the paragraphs of a caption by the line-breaks of caption (docs/adr/0367):
    with keep, each line of the source is a line, as in a paragraph of a style
    that keeps its lines; the paragraphs have no style of their own -}
    evalCaption bs
      | Map.lookup "caption" (ctxParaStyles ctx) == Just KeepLines = concat <$> mapM keptCaption bs
      | otherwise = evalBlocks ctx bs
    keptCaption = \case
      A.Located psp (A.Paragraph is) -> map unstyle <$> styledParagraph ctx psp (Just "caption") is
      other -> evalBlocks ctx [other]
    unstyle = \case
      Block bsp l g (Paragraph _ is) -> Block bsp l g (Paragraph Nothing is)
      other -> other
    -- a caption holds paragraphs only: G02118 at each other block, which is dropped (docs/adr/0144)
    captionParagraphs = fmap concat . mapM (\b -> maybe (pure [b]) (\k -> [] <$ err "G02118" (blockSpan b) ("図版のキャプションには段落だけを書けます: " <> k)) (notInCaption (blockBody b)))
    -- a forced break, a page control and blank lines are left to nestedBreaks (G02059, G02071, G02093)
    notInCaption = \case
      Paragraph _ _ -> Nothing
      ForcedBreak _ -> Nothing
      PageControl _ -> Nothing
      BlankLines _ -> Nothing
      Separator _ -> Nothing
      FigureBlock _ -> Just "図版"
      BulletList _ -> Just "箇条書き"
      OrderedList _ -> Just "番号付きリスト"
      DefList _ -> Just "定義リスト"
      TableBlock _ -> Just "表"
      CodeBlock _ -> Just "コードブロック"
      Heading {} -> Just "見出し"
      ChannelOutput _ -> Just "一覧の出力"
      FrameBlock _ _ -> Just "フレーム"
    -- a caption has no paragraph style of its own (docs/adr ADR 0005, golem-driver ADR 0010)
    noStyle csp = err "G02013" csp "@style は図版のキャプションには付けられません"
    -- the built-in @style alone (root ADR 0471)
    unstyled isBuiltin = \case
      A.Located asp (A.Attributed cs t) | any (isStyleCommand isBuiltin) cs -> do
        mapM_ (\(A.Located csp _) -> noStyle csp) (filter (isStyleCommand isBuiltin) cs)
        let rest = filter (not . isStyleCommand isBuiltin) cs
            t' = joinParagraph <$> t
        pure $ case rest of
          [] -> maybe [] pure t'
          _ -> [A.Located asp (A.Attributed rest t')]
      lb@(A.Located bsp (A.BlockCommand _ _ inner)) | isStyleCommand isBuiltin lb -> noStyle bsp >> pure (map joinParagraph inner)
      other -> pure [other]
    joinParagraph = \case
      A.Located psp (A.Paragraph is) -> A.Located psp (A.Paragraph (joinSoftBreaks is))
      other -> other

-- ------------------------------------------------------------------ tables (golem-eval ADR 0004)

{- | @table: a table of a CSV or a TSV file. The path is the first argument;
src= is G02252, and two paths are G02130 (ADR 0343).
The arguments are checked before the file is read: format= (G02080),
align= (G02081) and cells= (G02084); the number of align= values is
checked against the header row.
-}
csvTable :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> M [Block]
csvTable ctx sp args
  | Just asp <- listToMaybe legacy,
    null positional =
      err "G02252" asp "@table の src= は使えません。パスを最初の引数に移します" >> pure []
  | not (null legacy) && not (null positional) || length positional > 1 =
      err "G02130" sp "@table にはファイルのパスを一つ書きます" >> pure []
  | otherwise = csvTableValid ctx sp args
  where
    positional = [() | A.Located _ (A.Positional _) <- args]
    legacy = [asp | A.Located asp (A.Keyword (A.Located _ "src") _) <- args]

csvTableValid :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> M [Block]
csvTableValid ctx sp args = do
  kw <- keywords ctx args
  let arg k = listToMaybe [(asp, v) | A.Located asp (A.Keyword (A.Located _ k') v) <- args, k' == k]
      paths = [argText v | A.Located _ (A.Positional v) <- args] <> maybe [] (pure . argText) (lookup "src" kw)
      src = listToMaybe paths
  format <- case arg "format" of
    Nothing -> pure (Just (tableFormat Nothing (fromMaybe "" src)))
    Just (asp, v) -> case tableFormat (Just (argText v)) (fromMaybe "" src) of
      Left bad -> err "G02080" asp ("format は csv か tsv です: " <> bad) >> pure Nothing
      Right f -> pure (Just (Right f))
  align <- case arg "align" of
    Nothing -> pure (Just Nothing)
    Just (asp, v) -> case maybe (Left (AlignBadValue "[= ...]")) tableAlign (nameArg v) of
      Left (AlignBadValue bad) -> err "G02081" asp ("align の値は left、center、right、default のどれかです: " <> bad) >> pure Nothing
      Right al -> pure (Just (Just (asp, al)))
  cells <- case arg "cells" of
    Nothing -> pure True
    Just (asp, v) -> case cellReading (argText v) of
      Right CellsText -> pure True
      Right CellsMarkup -> err "G02084" asp "cells=markup はまだ実装していません" >> pure False
      Left bad -> err "G02084" asp ("cells は text です: " <> bad) >> pure False
  case paths of
    [] -> err "G02034" sp "@table にはファイルのパスが必要です" >> pure []
    _ : _ : _ -> err "G02130" sp "@table にはファイルのパスを一つ書きます" >> pure []
    [path] -> case (format, align) of
      (Just (Right fmt), Just al)
        | cells ->
            asset ctx sp path >>= \case
              Just (AssetText fid content) ->
                let (rows, cell) = case fmt of
                      TableCsv -> (parseCsv fid content, \t -> [Text sp t])
                      -- an empty cell of a TSV has no inlines, as in a | table
                      TableTsv -> (parseTsv fid content, \t -> [Text sp t | not (T.null t)])
                 in case rows of
                      Left e -> report (tableDiagnostic sp path e) >> pure []
                      Right [] -> pure []
                      Right (h : body) -> case al of
                        Nothing -> pure [table (map (const AlignDefault) h) cell h body]
                        Just (_, [a]) -> pure [table (map (const a) h) cell h body]
                        Just (asp, as)
                          | length as == length h -> pure [table as cell h body]
                          | otherwise -> err "G02081" asp ("align の値の数が表の列の数と違います（列は " <> tshow (length h) <> "、align は " <> tshow (length as) <> "）") >> pure []
              Just (AssetTableUnreadable _ _) -> pure []
              Just (AssetTableTooLarge n _) -> report (tableDiagnostic sp path (TableOverLimit (OverBytes n))) >> pure []
              Just _ -> missing sp path >> pure []
              Nothing -> pure []
      _ -> pure []
  where
    table as cell h body = block sp (TableBlock (plainTable as (map cell h) (map (map cell) body)))

-- | Why a table file gives no table.
data TableError
  = -- | G02082, G02083, G02085 or G02154, in the file
    TableInvalid !Diagnostic
  | -- | G02088 (docs/adr ADR 0043)
    TableOverLimit !TableLimit
  deriving stock (Eq, Show)

-- | The limit a table file goes over (docs/adr ADR 0043).
data TableLimit
  = -- | the size of the file, in bytes
    OverBytes !Integer
  | -- | the row that goes over the number of rows, counted from 1 with the header row
    OverRows !Int
  | -- | the row whose cells go over the number of cells, counted from 1
    OverCells !Int
  deriving stock (Eq, Show)

-- | The size of a table file, in bytes, at most 16 MiB (docs/adr ADR 0043).
tableMaxBytes :: Int
tableMaxBytes = 2 ^ (24 :: Int)

-- | The rows of a table file, the header row included (docs/adr ADR 0043).
tableMaxRows :: Int
tableMaxRows = 10000

-- | The cells of a row of a table file (docs/adr ADR 0043).
tableMaxCells :: Int
tableMaxCells = 256

{- | The diagnostic of a table error: one in the file as it is, G02088 at
the @table block, with the path as written.
-}
tableDiagnostic :: SrcSpan -> Text -> TableError -> Diagnostic
tableDiagnostic sp path = \case
  TableInvalid d -> d
  TableOverLimit l -> diagnostic "G02088" Error sp ("表のファイルが" <> what l <> ": " <> path <> "（" <> detail l <> "）")
  where
    what = \case
      OverBytes _ -> "大きさの上限を超えます"
      OverRows _ -> "行の数の上限を超えます"
      OverCells _ -> "セルの数の上限を超えます"
    detail = \case
      OverBytes n -> tshow n <> " バイト、上限は " <> tshow tableMaxBytes <> " バイト"
      OverRows r -> tshow r <> " 行目、上限は " <> tshow tableMaxRows <> " 行"
      OverCells r -> tshow r <> " 行目、上限は 1 行に " <> tshow tableMaxCells <> " 個"

-- | The format of a table file (golem-eval ADR 0004).
data TableFormat = TableCsv | TableTsv
  deriving stock (Eq, Show)

-- | the reserved cells= values; only CellsText is implemented (golem-eval ADR 0004)
data CellReading = CellsText | CellsMarkup
  deriving stock (Eq, Show)

-- | A value of align= that is not an alignment, as written (G02081).
newtype AlignError = AlignBadValue Text
  deriving stock (Eq, Show)

{- | The format of a table: format= when written (Left, the value, when it
is neither csv nor tsv), otherwise TSV for a path ending in .tsv in any
case, otherwise CSV.
-}
tableFormat :: Maybe Text -> Text -> Either Text TableFormat
tableFormat (Just "csv") _ = Right TableCsv
tableFormat (Just "tsv") _ = Right TableTsv
tableFormat (Just other) _ = Left other
tableFormat Nothing path
  | ".tsv" `T.isSuffixOf` T.toLower path = Right TableTsv
  | otherwise = Right TableCsv

{- | The alignments of align=, by column, separated by commas, with the
spaces around each value removed. One value is for every column; the
caller repeats it.
-}
tableAlign :: Text -> Either AlignError [Alignment]
tableAlign t = maybe (Left (AlignBadValue t)) Right (mapM (one . T.strip) (T.splitOn "," t))
  where
    one = \case
      "left" -> Just AlignLeft
      "center" -> Just AlignCenter
      "right" -> Just AlignRight
      "default" -> Just AlignDefault
      _ -> Nothing

-- | The value of cells=; Left is a value that is not reserved.
cellReading :: Text -> Either Text CellReading
cellReading = \case
  "text" -> Right CellsText
  "markup" -> Right CellsMarkup
  other -> Left other

{- | A TSV file as rows of cells (IANA text/tab-separated-values): LF or
CRLF ends a line, one line end at the end of the file is dropped, tabs
separate the cells and nothing else is special. Left is G02085 (an empty
file), G02154 (a row with another number of cells than the header), G02082, or
a limit the file goes over (docs/adr ADR 0043).
-}
parseTsv :: FileId -> Text -> Either TableError [[Text]]
parseTsv fid t0 = do
  withinBytes t0
  Bi.first TableInvalid (noLoneCr fid t0)
  let (base, t) = skipBom t0
      body = fromMaybe t (T.stripSuffix "\r\n" t <|> T.stripSuffix "\n" t)
  tableFileRows fid "TSV" (if T.null body then [] else tsvLines base (T.split (== '\n') body))
  where
    tsvLines _ [] = []
    tsvLines !off (l : ls) =
      let content = fromMaybe l (T.stripSuffix "\r" l)
       in Right (off, off + byteLen content, take (tableMaxCells + 1) (T.split (== '\t') content)) : tsvLines (off + byteLen l + 1) ls

{- | A CSV file as rows of cells (RFC 4180): comma-separated, double-quoted
fields with "" escapes, LF or CRLF ending a record; CRLF in quotes is LF
in the cell, and empty lines are dropped. Left is G02085, G02154, G02082, G02083
(a quote not closed), or a limit the file goes over (docs/adr ADR 0043).
The file is read as Text, a record at a time, by its UTF-8 bytes; a cell
is a slice of the file unless it has quotes or CRLF to undo.
-}
parseCsv :: FileId -> Text -> Either TableError [[Text]]
parseCsv fid t0@(TI.Text arr off0 len) = do
  withinBytes t0
  Bi.first TableInvalid (noLoneCr fid t0)
  tableFileRows fid "CSV" (filter (either (const True) (\(_, _, cs) -> cs /= [""])) (records (off0 + fst (skipBom t0))))
  where
    -- the bytes of the file are indexed in the array of the text; the special
    -- characters are ASCII, which no other character's UTF-8 bytes contain
    end = off0 + len
    byte = TA.unsafeIndex arr
    pos i = i - off0
    slice i j = TI.text arr i (j - i)
    isStop w = w == 0x2C || w == 0x0A || w == 0x0D
    records i
      | i >= end = []
      | otherwise = record i i (0 :: Int) []
    -- the cells of the record that starts at @start@; the record stops at the
    -- cell over the limit, which 'tableFileRows' reports, and nothing after it is read
    record !start !i !n acc = case field i of
      Left d -> [Left d]
      Right (cell, e)
        | n + 1 > tableMaxCells -> [row e]
        | e < end && byte e == 0x2C -> record start (e + 1) (n + 1) acc'
        | e < end && byte e == 0x0A -> row e : records (e + 1)
        | e + 1 < end && byte e == 0x0D -> row e : records (e + 2)
        | otherwise -> [row e]
        where
          acc' = cell : acc
          row e' = Right (pos start, pos e', reverse acc')
    -- a field from @i@, and where it ends
    field !i
      | i < end && byte i == 0x22 = quoted i (i + 1) False
      | otherwise = let e = plain i in Right (slice i e, e)
    plain !i
      | i < end && not (isStop (byte i)) = plain (i + 1)
      | otherwise = i
    -- the closing quote; doubled quotes and CRLF are undone only when there are any
    quoted !open !i !undo
      | i >= end = Left (diagnostic "G02083" Error (mkSpan fid (pos open) (pos open + 1)) "CSV の引用符が閉じていません")
      | byte i == 0x22 && i + 1 < end && byte (i + 1) == 0x22 = quoted open (i + 2) True
      | byte i == 0x22 =
          let e = plain (i + 1)
              inner = slice (open + 1) i
              inner' = if undo then T.replace "\r\n" "\n" (T.replace "\"\"" "\"" inner) else inner
           in Right (if e == i + 1 then inner' else inner' <> slice (i + 1) e, e)
      | byte i == 0x0D = quoted open (i + 1) True
      | otherwise = quoted open (i + 1) undo

{- | The rows of a table file with their spans, as a table, read in order
and no further than the first error: a row over 'tableMaxRows' or with
cells over 'tableMaxCells' (G02088, docs/adr ADR 0043), a reading error
(G02083), or a row whose cells differ in number from the header's (G02154);
G02085 also for no rows.
-}
tableFileRows :: FileId -> Text -> [Either Diagnostic (Int, Int, [Text])] -> Either TableError [[Text]]
tableFileRows fid name = \case
  [] -> Left (TableInvalid (diagnostic "G02085" Error (mkSpan fid 0 0) (name <> " が空です")))
  r0 : rest -> do
    (_, _, h) <- Bi.first TableInvalid r0
    withinCells 1 h
    (h :) <$> go 2 h rest
  where
    go :: Int -> [Text] -> [Either Diagnostic (Int, Int, [Text])] -> Either TableError [[Text]]
    go _ _ [] = Right []
    go n h (r : rs)
      | n > tableMaxRows = Left (TableOverLimit (OverRows n))
      | otherwise = do
          (s, e, cs) <- Bi.first TableInvalid r
          withinCells n cs
          unless (length cs == length h) $
            Left (TableInvalid (diagnostic "G02154" Error (mkSpan fid s e) (name <> " の行のセルの数が見出しの行と違います（見出しの行は " <> count h <> "、この行は " <> count cs <> "）")))
          (cs :) <$> go (n + 1) h rs
    withinCells n cs = unless (length cs <= tableMaxCells) (Left (TableOverLimit (OverCells n)))
    count = T.pack . show . length

-- | G02088 for a file over 'tableMaxBytes' (docs/adr ADR 0043).
withinBytes :: Text -> Either TableError ()
withinBytes t = unless (byteLen t <= tableMaxBytes) (Left (TableOverLimit (OverBytes (toInteger (byteLen t)))))

-- | G02082 for a lone CR, as the reading stage of a table file reports it.
noLoneCr :: FileId -> Text -> Either Diagnostic ()
noLoneCr fid t = maybe (Right ()) Left (listToMaybe (checkTableText fid t))

-- | A BOM at the start is skipped; positions still count its 3 bytes.
skipBom :: Text -> (Int, Text)
skipBom t = maybe (0, t) (3,) (T.stripPrefix "\xFEFF" t)

-- | The length of a text in UTF-8, in constant time.
byteLen :: Text -> Int
byteLen = lengthWord8

-- | The text of a file read as text, for a listing.
assetContent :: Asset -> Maybe Text
assetContent = \case
  AssetText _ t -> Just t
  AssetTableUnreadable _ t -> Just t
  AssetTableTooLarge _ t -> t
  _ -> Nothing

{- | The file a path refers to. A path that cannot be used is reported, and
gives nothing.
-}
asset :: EvalContext -> SrcSpan -> Text -> M (Maybe Asset)
asset ctx sp p = case Map.lookup (T.unpack p) (ctxAssets ctx) of
  Nothing -> missing sp p >> pure Nothing
  Just (AssetInvalid Missing) -> missing sp p >> pure Nothing
  -- G02060: a path that cannot be used, worded as G03003 (golem-eval ADR 0003)
  Just (AssetInvalid e) -> err "G02060" sp (T.pack (pathErrorMessage e) <> ": " <> p) >> pure Nothing
  Just a -> pure (Just a)

-- | G02033: a file that is not there.
missing :: SrcSpan -> Text -> M ()
missing sp p = err "G02033" sp ("ファイルがありません: " <> p)

listing :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> M [Block]
listing ctx sp args = do
  kw <- keywords ctx args
  let paths = [(asp, argText v) | A.Located asp (A.Positional v) <- args]
      legacy = [(asp, argText v) | A.Located asp (A.Keyword (A.Located _ "src") v) <- args]
      duplicates = [(asp, k) | (asp, k) <- repeatedKeys args, k == "src"]
  case (duplicates, paths, legacy) of
    (_ : _, _, _) -> do
      mapM_ (\(asp, k) -> err "G02077" asp ("同じキーを二度書いています: " <> k)) duplicates
      pure []
    ([], first : second : _, _) -> do
      err "G02253" (fst second) ("@listing のパスを二つ書いています: " <> snd first <> "、" <> snd second <> "。採用する一方だけを位置引数に残します")
      pure []
    ([], first : _, old : _) -> do
      err "G02253" (fst old) ("@listing のパスを二つ書いています: " <> snd first <> "、" <> snd old <> "。採用する一方だけを位置引数に残します")
      pure []
    ([], [], old : _) -> do
      err "G02250" (fst old) "@listing の src= は使えません。パスを最初の引数に移します"
      pure []
    ([], [], []) -> err "G02036" sp "@listing にはファイルのパスが必要です" >> pure []
    ([], [(_, p)], []) ->
      asset ctx sp p >>= \case
        Just found | Just content <- assetContent found -> do
          let ls = T.lines content
              numberedLines = zip [1 :: Int ..] ls
              -- the arguments of a code block, and lang (golem-driver ADR 0023)
              codeArgsOf = [a | a@(A.Located _ (A.Keyword (A.Located _ k) _)) <- args, k `notElem` ["src", "lines"]]
              code selected = do
                ca <- codeArgs ctx sp ["lang"] codeArgsOf
                -- the lines of a file are not in the source (docs/adr/0218)
                c <- codeOf sp ca (Just (map (toInteger . fst) selected)) (caLang ca) False [(sp, x) | (_, x) <- selected]
                pure [block sp (CodeBlock c)]
          -- the diagnostics of lines= are at the argument (docs/adr ADR 0113)
          let lsp = fromMaybe sp (listToMaybe [asp | A.Located asp (A.Keyword (A.Located _ "lines") _) <- args])
          linesArg <- traverse (lineRanges ctx "@listing の lines" lsp) (lookup "lines" kw)
          case linesArg of
            Nothing -> code numberedLines
            Just Nothing -> pure []
            Just (Just (r, rs)) -> case rs of
              _
                | all (\(LineRange a b) -> a >= 1 && b <= fromIntegral (length ls)) rs ->
                    code (concatMap (\(LineRange a b) -> take (fromIntegral (b - a + 1)) (drop (fromIntegral (a - 1)) numberedLines)) rs)
              _ -> err "G02037" lsp ("@listing の lines の範囲がファイルの行（1〜" <> tshow (length ls) <> "）を外れています: " <> r) >> pure []
        Just _ -> missing sp p >> pure []
        Nothing -> pure []

-- ------------------------------------------------------------------ code blocks (golem-driver ADR 0023)

-- | The arguments of a code block, as read.
data CodeArgs = CodeArgs
  { -- | true or false, or the number of the first line
    caNumbers :: !(Maybe (Either Bool Integer)),
    caFile :: !(Maybe Text),
    -- | the ranges of highlight=, and where the argument is
    caHighlight :: !(Maybe (SrcSpan, [(Integer, Integer)])),
    caDiff :: !Bool,
    caCallouts :: !Bool,
    -- | lang=, of @listing only
    caLang :: !(Maybe Text)
  }

-- | The keys a code block takes; @listing takes lang too.
codeKeys :: [Text]
codeKeys = ["numbers", "file", "highlight", "diff", "callouts"]

{- | The arguments of a code block (golem-driver ADR 0023): keyword
arguments of 'codeKeys' and @extra@. Another key, a wrong value and a
positional argument are G02069.
-}
codeArgs :: EvalContext -> SrcSpan -> [Text] -> [A.Located A.Argument] -> M CodeArgs
codeArgs ctx _ extra = foldl (\m a -> m >>= \acc -> step acc a) (pure (CodeArgs Nothing Nothing Nothing False False Nothing))
  where
    step acc (A.Located asp a) = case a of
      A.Keyword (A.Located _ k) v
        -- the natural numbers of numbers= (docs/adr ADR 0102) and the ranges of highlight= (docs/adr ADR 0113)
        | k == "numbers" -> maybe acc (\n -> acc {caNumbers = Just n}) <$> numbersArg ctx asp v
        | k == "highlight" ->
            maybe acc (\(_, rs) -> acc {caHighlight = Just (asp, [(toInteger x, toInteger y) | LineRange x y <- rs])})
              <$> lineRanges ctx "コードブロックの highlight" asp v
        | k `elem` codeKeys <> extra ->
            scalar asp v >>= \case
              -- the diagnostic of the expression is the one of its cause: no G02069 besides (the audit of 2026-11-04, F-14)
              Nothing -> pure acc
              Just t -> case t >>= reading k of
                Just f -> pure (f acc)
                Nothing -> err "G02069" asp (k <> " の値が正しくありません: " <> fromMaybe "" t) >> pure acc
        | otherwise -> err "G02069" asp ("コードブロックに書けないキーです: " <> k <> "。numbers、file、highlight、diff、callouts（@listing では lang も）を書けます") >> pure acc
      _ -> err "G02069" asp "コードブロックの開始の行には、言語の名前とキーワード引数だけを書けます" >> pure acc
    {- the text of a value: Just Nothing for a value that is no text, and
    Nothing for an expression whose diagnostic is reported (G02113 for a
    range, docs/adr ADR 0111; or the code of the expression) -}
    scalar vsp = \case
      A.Word t -> pure (Just (Just t))
      A.StringLit t -> pure (Just (Just t))
      v@(A.ExprArg _) ->
        plainArgValue ctx vsp (A.Located vsp v) >>= \case
          Right val | Just n <- intOf val -> pure (Just (Just (T.pack (show n))))
          Right (VString s) -> pure (Just (Just s))
          Right (VBool b) -> pure (Just (Just (if b then "true" else "false")))
          Right _ -> pure (Just Nothing)
          Left d -> report d >> pure Nothing
      A.CommandArg _ -> pure (Just Nothing)
    bool = \case
      "true" -> Just True
      "false" -> Just False
      _ -> Nothing
    reading k t = case k of
      "file" -> Just (\c -> c {caFile = Just t})
      "diff" -> (\b c -> c {caDiff = b}) <$> bool t
      "callouts" -> (\b c -> c {caCallouts = b}) <$> bool t
      "lang" | not (T.null t) -> Just (\c -> c {caLang = Just t})
      _ -> Nothing

{- | The code of lines with their spans (golem-driver ADR 0023): the diff
marks and the callouts taken off, each line numbered from the first
number, a removed line not counted, and the lines of highlight marked.
@start@ is the first line of lines= of @listing. A number of numbers=
that takes a line out of int64 is G02091 at the block @bsp@, and the lines
are numbered as without numbers= (golem-doc ADR 0006). With @inSource@,
the span of a line is its line in the source, and each 'CodeLine' keeps
where its text is: from after the diff mark to the end of the line
(docs/adr/0218); the text of a line is the end of its line in the
source, after the indent of the block.
-}
codeOf :: SrcSpan -> CodeArgs -> Maybe [Integer] -> Maybe Text -> Bool -> [(SrcSpan, Text)] -> M Code
codeOf bsp ca0 start lang inSource ls = do
  marked <- mapM diffOf ls
  withCallouts <- mapM calloutsOf marked
  let numberedFrom c = case (caNumbers c, start) of
        (Just (Right _), _) -> snd (mapAccumL number (firstOf c) withCallouts)
        (_, Just sourceNumbers)
          | not (and (zipWith (\a b -> b == a + 1) sourceNumbers (drop 1 sourceNumbers))) ->
              zipWith sourceNumber sourceNumbers withCallouts
        _ -> snd (mapAccumL number (firstOf c) withCallouts)
  ca <-
    if all inInt64 (firstOf ca0 : [toInteger n | CodeLine {clNumber = Just n} <- numberedFrom ca0])
      then pure ca0
      else outOfInt64 bsp >> pure ca0 {caNumbers = Nothing}
  let numbered = numberedFrom ca
      present = Set.fromList [toInteger n | CodeLine {clNumber = Just n} <- numbered]
  hl <- case caHighlight ca of
    Nothing -> pure Set.empty
    Just (asp, rs) -> do
      mapM_ (\n -> err "G02069" asp ("highlight の行 " <> T.pack (show n) <> " はこのコードにありません")) [n | (a, b) <- rs, n <- take 1 [x | x <- [a .. b], x `Set.notMember` present]]
      -- only the lines the code has, however wide a range is (docs/adr ADR 0035)
      pure (Set.filter (\n -> any (\(a, b) -> a <= n && n <= b) rs) present)
  pure
    Code
      { codeLang = lang,
        codeNumbers = fromLeft True <$> caNumbers ca,
        codeFile = caFile ca,
        codeCaption = Nothing,
        codeDiff = caDiff ca,
        codeLines = [l {clHighlight = maybe False ((`Set.member` hl) . toInteger) (clNumber l)} | l <- numbered],
        codeNoNumber = False
      }
  where
    firstOf c = case caNumbers c of
      Just (Right n) -> n
      _ -> maybe 1 (fromMaybe 1 . listToMaybe) start
    sourceNumber n (t, d, cs, tsp)
      | d == Just DiffRemoved = CodeLine t Nothing d False cs tsp
      | otherwise = CodeLine t (Just (fromInteger n)) d False cs tsp
    number n (t, d, cs, tsp)
      | d == Just DiffRemoved = (n, CodeLine t Nothing d False cs tsp)
      | otherwise = (n + 1, CodeLine t (Just (fromInteger n)) d False cs tsp)
    -- the text of a line in the source: the end of the line, the diff mark taken off
    textSpan lsp t = mkSpan (spanFile lsp) (max (spanStart lsp) (spanEnd lsp - lengthWord8 t)) (spanEnd lsp)
    afterMark tsp = tsp {spanStart = min (spanEnd tsp) (spanStart tsp + 1)}
    diffOf (lsp, t) =
      let tsp = if inSource then Just (textSpan lsp t) else Nothing
       in if not (caDiff ca0)
            then pure (lsp, t, Nothing, tsp)
            else case T.uncons t of
              Nothing -> pure (lsp, t, Just DiffContext, tsp)
              Just ('+', rest) -> pure (lsp, rest, Just DiffAdded, afterMark <$> tsp)
              Just ('-', rest) -> pure (lsp, rest, Just DiffRemoved, afterMark <$> tsp)
              Just (' ', rest) -> pure (lsp, rest, Just DiffContext, afterMark <$> tsp)
              Just _ -> err "G02069" lsp "diff=true のコードの行は +、-、空白のどれかで始めます" >> pure (lsp, t, Just DiffContext, tsp)
    calloutsOf (lsp, t, d, tsp)
      | not (caCallouts ca0) = pure (t, d, [], tsp)
      | otherwise = do
          let (t', ns) = lineCallouts t
              bad = [n | n <- ns, n < 1 || n > 50]
          mapM_ (\n -> err "G02069" lsp ("注釈の印の番号は 1 から 50 までです: " <> T.pack (show n))) bad
          pure (t', d, [fromInteger n | n <- ns, n >= 1, n <= 50], tsp)

{- | The callouts at the end of a line (golem-driver ADR 0023): each @<N>@
after the text, with the spaces before them taken off; a line without
one is left as it is.
-}
lineCallouts :: Text -> (Text, [Integer])
lineCallouts t = case go (T.dropWhileEnd isBlank t) [] of
  (_, []) -> (t, [])
  r -> r
  where
    isBlank c = c == ' ' || c == '\t'
    go s acc = case T.stripSuffix ">" s of
      Just s1 ->
        let (pre, digits) = T.breakOnEnd "<" s1
         in if T.null pre || T.null digits || not (T.all isDigit digits)
              then (s, acc)
              else go (T.dropWhileEnd isBlank (T.dropEnd 1 pre)) (read (T.unpack digits) : acc)
      Nothing -> (s, acc)

-- ------------------------------------------------------------------ inlines

noteRefs :: A.Located A.Expr -> M ()
noteRefs e = do
  let names = freeNames e
  modify' (\s -> s {stRefs = Set.union (stRefs s) (Set.fromList names)})
  let nsRefs = nsRefsOf e
  modify' (\s -> s {stNsRefs = Map.unionWith Set.union (stNsRefs s) nsRefs})
  -- the names listed by @import that the expression uses (G05003, root ADR 0451)
  modify' $ \s ->
    let listed = Map.keysSet (stListedVars s) <> Set.fromList [n | (ExprSpace, n) <- Map.keys (stListedFns s)]
     in s {stListedRefs = Set.union (stListedRefs s) (Set.intersection listed (Set.fromList (names <> callsOf e)))}
  where
    callsOf (A.Located _ x) = case x of
      A.ECall f xs | isNothing (splitNamespace f) -> f : concatMap callsOf xs
      A.ECall _ xs -> concatMap callsOf xs
      A.EArray xs -> concatMap callsOf xs
      A.EHash kvs -> concatMap (callsOf . snd) kvs
      A.EUnary _ a -> callsOf a
      A.EBinary _ a b -> callsOf a <> callsOf b
      A.ERange a b -> callsOf a <> callsOf b
      _ -> []
    nsRefsOf (A.Located _ x) = case x of
      A.EVar (ns : n : _) -> Map.singleton ns (Set.singleton n)
      A.EArray xs -> Map.unionsWith Set.union (map nsRefsOf xs)
      A.EHash kvs -> Map.unionsWith Set.union (map (nsRefsOf . snd) kvs)
      -- a function of a .emet uses its namespace (docs/adr/0162)
      A.ECall f xs | Just (ns, n) <- splitNamespace f -> Map.unionsWith Set.union (Map.singleton ns (Set.singleton n) : map nsRefsOf xs)
      A.ECall _ xs -> Map.unionsWith Set.union (map nsRefsOf xs)
      A.EUnary _ a -> nsRefsOf a
      A.EBinary _ a b -> Map.unionWith Set.union (nsRefsOf a) (nsRefsOf b)
      A.ERange a b -> Map.unionWith Set.union (nsRefsOf a) (nsRefsOf b)
      _ -> Map.empty

evalInlines :: EvalContext -> Bool -> [A.Located A.Inline] -> M [Inline]
evalInlines ctx inHeading is = mergeText . concat <$> mapM (evalInline ctx inHeading) (A.plainEscapes is)

mergeText :: [Inline] -> [Inline]
mergeText (Text a x : Text b y : rest) = mergeText (Text (mkSpan (spanFile a) (spanStart a) (spanEnd b)) (x <> y) : rest)
mergeText (x : rest) = x : mergeText rest
mergeText [] = []

-- | Whether an expression needs document structure (refers to doc).
usesDoc :: A.Located A.Expr -> Bool
usesDoc e = "doc" `elem` freeNames e

-- | Replace S0 names by their values so that only doc stays free.
substitute :: Env -> A.Located A.Expr -> A.Located A.Expr
substitute en le@(A.Located sp e) = case e of
  A.EVar ("doc" : _) -> le
  A.EVar _ -> either (const le) (valueToExpr le) (evalExpr en le)
  A.EArray xs -> A.Located sp (A.EArray (map (substitute en) xs))
  A.EHash kvs -> A.Located sp (A.EHash [(k, substitute en v) | (k, v) <- kvs])
  A.ECall f xs -> A.Located sp (A.ECall f (map (substitute en) xs))
  A.EUnary o a -> A.Located sp (A.EUnary o (substitute en a))
  A.EBinary o a b -> A.Located sp (A.EBinary o (substitute en a) (substitute en b))
  A.ERange a b -> A.Located sp (A.ERange (substitute en a) (substitute en b))
  _ -> le

evalInline :: EvalContext -> Bool -> A.Located A.Inline -> M [Inline]
evalInline ctx inHeading (A.Located sp i) = case i of
  A.Text t -> pure [Text sp t]
  -- evalInlines has made it text already; this is for safety (golem-parser ADR 0010)
  A.Escaped c -> pure [Text sp (T.singleton c)]
  A.SoftBreak -> pure []
  -- Both shorthand forms use the ordinary name resolution and arguments (golem-parser ADR 0014).
  A.NumberShorthand t -> case shorthandNumber t of
    Just (n, style) ->
      evalCommand
        ctx
        inHeading
        sp
        (A.Located sp "number-text")
        (A.Located sp (A.Positional (A.Word n)) : [A.Located sp (A.Keyword (A.Located sp "style") (A.Word name)) | name <- maybe [] pure style])
        []
    Nothing -> err "G02078" sp "## と ## のあいだには算用数字、または算用数字:表記名を書きます。本文の ## は \\## と書きます" >> pure []
  -- the hard breaks of a paragraph are split off before; this one is in a prose slot
  A.HardBreak -> err "G02056" sp "強制改行は段落の中にだけ書けます。コマンドの中では使えません" >> pure []
  A.ErrorInline -> pure []
  A.ProofComment t
    | ctxProfile ctx == Prod -> report (diagnostic "G02005" Warning sp "校正用のコメントが残っています") >> pure []
    | otherwise -> pure [ProofComment sp t]
  A.Expr e -> do
    noteRefs e
    en <- env
    -- the analysis before the evaluation (docs/adr ADR 0102): an expression
    -- with a diagnostic is not evaluated, nor deferred
    case analyse en e of
      Just d -> report d >> pure []
      Nothing -> exprInline en e
  A.Command n args slots -> prepareArgs args >>= maybe (pure []) (\args' -> evalCommand ctx inHeading sp n args' (codeSlots n args' slots))
  where
    exprInline en e =
      -- a function of a .emet runs at S0 alone, and doc is no value there (docs/adr/0162)
      if usesDoc e && not (callsFunction e)
        then
          if inHeading
            then err "G02014" sp "見出しの中では doc を参照できません" >> pure []
            else
              let e' = substitute en e
               in -- G02086: a literal past the limit of the evaluator (docs/adr ADR 0101);
                  -- G02091: an integer of the IR out of int64 (golem-doc ADR 0006)
                  if any overLimit (exprNumbers e')
                    then report (tooBigDiagnostic sp) >> pure []
                    else
                      if all (all inInt64 . ratioInts) (exprNumbers e')
                        then pure [Deferred sp (DeferredExpr e')]
                        else outOfInt64 sp >> pure []
        else case evalExpr en e >>= embedValue sp of
          Left d -> report d >> pure []
          Right t -> pure [Text sp t]

{- | The number and optional style argument of the shorthand (golem-parser ADR 0014).
The style is a syntactic name, not an enumeration of built-in number styles.
-}
shorthandNumber :: Text -> Maybe (Text, Maybe Text)
shorthandNumber t = do
  inner <- T.stripPrefix "##" t >>= T.stripSuffix "##"
  let (digits, suffix) = T.breakOn ":" inner
      validDigits =
        digits == "0" || case T.uncons digits of
          Just (c, _) -> c /= '0' && T.all (\x -> isAscii x && isDigit x) digits
          Nothing -> False
      validStyle name = case T.uncons name of
        Just (c, rest) -> isAsciiLower c && T.all (\x -> isAsciiLower x || (isAscii x && isDigit x) || x == '-') rest
        Nothing -> False
  if not validDigits
    then Nothing
    else
      if T.null suffix
        then Just (digits, Nothing)
        else let name = T.drop 1 suffix in if validStyle name then Just (digits, Just name) else Nothing

{- | The slots of [code: ...] and [style code: ...] with every ##…## made
the text it was written with (golem-parser ADR 0011), before the command
is resolved, so a plugin over code gets the text too.
-}
codeSlots :: A.Located A.Name -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> [[A.Located A.Inline]]
codeSlots (A.Located _ name) args slots
  | name == "code" || (name == "style" && isCode args) = map A.shorthandsAsText slots
  | otherwise = slots
  where
    isCode = \case
      (A.Located _ (A.Positional v) : _) -> nameArg v == Just "code"
      _ -> False

-- | An inline command, its repeated keys dropped (golem-parser ADR 0013).
evalCommand :: EvalContext -> Bool -> SrcSpan -> A.Located A.Name -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
evalCommand ctx inHeading sp (A.Located nsp name) args slots
  | Just o <- parsed, Just pc <- Map.lookup o (phOverrides (ctxPlugins ctx)) = plugin pc
  -- a built-in command a name listed by @import overrides (root ADR 0453, root ADR 0471)
  | Just b <- parsed = listedFunction InlineSpace name >>= maybe (builtin ctx inHeading sp b args slots) listed
  | Just pc <- pluginCommandName name >>= (`Map.lookup` phCommands (ctxPlugins ctx)) = plugin pc
  | Just (ns, n) <- splitNamespace name = functionInline ctx inHeading sp nsp ns n args slots
  | otherwise =
      -- an inline command listed by @import (root ADR 0451)
      listedFunction InlineSpace name >>= maybe (unknownName ctx name (diagnostic "G02022" Error nsp ("未知のコマンドです: " <> name)) >> pure []) listed
  where
    parsed = parseBuiltin name
    listed = \case
      Loaded fns | Just f <- Map.lookup name (fnInline fns) -> callInline ctx inHeading sp name f args slots
      Unloaded why -> unloadedCall why nsp name
      Loaded _ -> pure []
    plugin pc = do
      vals <- pluginArgs ctx sp args
      slots' <- mapM (evalInlines ctx inHeading) slots
      case sequence vals of
        Left d -> report d >> pure []
        -- G02091: the plugin is not called (golem-doc ADR 0006)
        Right vs | not (all (all inInt64 . valueInts . pluginArgValue) vs) -> outOfInt64 sp >> pure []
        Right vs -> case pcCall pc vs slots' sp of
          Left ds -> mapM_ report ds >> pure []
          Right (out, ds) -> mapM_ report ds >> pure out

{- | A built-in command. A command that takes no prose slot ('takesNoSlot',
golem-eval ADR 0003) reports a slot as G02038, before the arguments, and
after G02014 for a reference in a heading.
-}
builtin :: EvalContext -> Bool -> SrcSpan -> BuiltinInline -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
builtin ctx inHeading sp b args slots
  | inHeading && b `elem` [BRefNumber, BRefTitle, BRefPage] = err "G02014" sp "見出しの中では相互参照を使えません" >> pure []
  | takesNoSlot b && not (null slots) = err "G02038" sp (builtinName b <> " は散文スロットを取りません") >> pure []
  | otherwise = builtinWith ctx inHeading sp b args slots

builtinWith :: EvalContext -> Bool -> SrcSpan -> BuiltinInline -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
builtinWith ctx inHeading sp b args slots = do
  kw <- keywords ctx args
  let pos = [v | A.Located _ (A.Positional v) <- args]
      plainComposition constructor = oneSlot $ \xs ->
        if all isPlain xs
          then pure [constructor sp (T.concat [t | Text _ t <- xs])]
          else err "G02040" sp (builtinName b <> " の中身は地の文に限ります") >> pure []
      isPlain Text {} = True
      isPlain _ = False
      oneSlot k = case slots of
        [s] -> evalInlines ctx inHeading s >>= k
        _ -> err "G02038" sp (builtinName b <> " には散文スロットが一つ必要です") >> pure []
  case b of
    -- the built-in character styles (docs/adr ADR 0005)
    BStrong -> oneSlot (pure . pure . CharStyle sp "strong")
    BBold -> oneSlot (pure . pure . CharStyle sp "bold")
    BItalic -> oneSlot (pure . pure . CharStyle sp "italic")
    -- [code: ...] is [style code: ...] (golem-driver ADR 0017)
    BCode -> oneSlot (pure . pure . CharStyle sp "code")
    BKenten -> do
      let shape = argText <$> lookup "shape" kw
      case shape of
        Just s | s `notElem` kentenShapes -> err "G02039" sp ("未知の圏点の形です: " <> s) >> pure []
        -- without a shape, the default of style.toml (golem-driver ADR 0019)
        _ -> oneSlot (pure . pure . Kenten sp (Just (fromMaybe (ctxDefaultKenten ctx) shape)))
    BColor -> case pos of
      [v] | Just n <- nameArg v, n `Set.member` ctxSwatches ctx -> oneSlot (pure . pure . Color sp n)
      [v] | Just n <- nameArg v -> err "G02017" sp ("style.toml にないスウォッチです: " <> n) >> pure []
      _ -> err "G02017" sp "color にはスウォッチの名前を一つ書きます" >> pure []
    BStyle -> case pos of
      [v] | Just n <- nameArg v, n `Set.member` ctxCharStyles ctx -> oneSlot (pure . pure . CharStyle sp n)
      [v] | Just n <- nameArg v -> err "G02018" sp ("定義されていない文字スタイルです: " <> n) >> pure []
      _ -> err "G02018" sp "style には文字スタイルの名前を一つ書きます" >> pure []
    BWarichu -> plainComposition Warichu
    BUpright -> plainComposition Upright
    BTcy -> oneSlot $ \case
      [Text _ t]
        -- G02063: a number reads better as a number (golem-syntax ADR 0002)
        | not (T.null t) && T.all isDigit t && T.all isAscii t -> report (notice "G02063" sp ("数の縦中横は [number-text " <> t <> " style=tcy] でも書けます")) >> pure [Tcy sp t]
        | otherwise -> pure [Tcy sp t]
      [] -> pure []
      _ -> err "G02040" sp "縦中横の中身は地の文に限ります" >> pure []
    BNumberText -> case [A.Located asp v | A.Located asp (A.Positional v) <- args] of
      [lv] -> do
        val <- plainArgValue ctx sp lv
        let st = argText <$> lookup "style" kw
        case (val, st) of
          (Right v', _) | Just n <- intOf v', not (inInt64 n) -> outOfInt64 sp >> pure []
          (Right v', Nothing) | Just n <- intOf v' -> pure [Number sp n Nothing]
          (Right v', Just s)
            | Just n <- intOf v',
              Just ns <- lookup s [("kanji", StyleKanji), ("kanji-digits", StyleKanjiDigits), ("tcy", StyleTcy)] ->
                pure [Number sp n (Just ns)]
            | Just _ <- intOf v' -> err "G02019" sp ("style は kanji、kanji-digits、tcy のいずれかです: " <> s) >> pure []
          (Left d, _) -> report d >> pure []
          _ -> err "G02019" sp "number-text に渡せるのは整数だけです" >> pure []
      _ -> err "G02019" sp "number-text には整数を一つ書きます" >> pure []
    BRefNumber -> refTo RefNumber pos
    BRefTitle -> refTo RefTitle pos
    BRefPage -> refTo RefPage pos
    -- [note: body], or [note name] of the body of @note name (docs/adr/0263); label= gives it a label (root ADR 0422)
    BNote -> noteLabel $ \lbl rest -> case (rest, slots) of
      ([], [_]) -> oneSlot $ \body -> do
        n <- gets ((+ 1) . stNote)
        modify' (\s -> s {stNote = n})
        pure [Note sp n lbl (noteBody sp body)]
      (_ : _, _ : _) -> err "G02038" sp "note は名前を書くと散文スロットを取りません" >> pure []
      ([A.Located _ (A.Positional v)], [])
        | Just name <- nameArg v,
          validLabel name -> do
            n <- gets ((+ 1) . stNote)
            modify' (\s -> s {stNote = n, stNoteRefs = stNoteRefs s <> [(sp, name)]})
            pure [Note sp n lbl []]
      (_, []) -> err "G02142" sp noteNameMessage >> pure []
      _ -> err "G02038" sp (builtinName b <> " には散文スロットが一つ必要です") >> pure []
    -- [endnote: body], or [endnote name] of the body of @endnote name (root ADR 0412), a label as a note (root ADR 0422)
    BEndnote -> noteLabel $ \lbl rest -> case (rest, slots) of
      ([], [_]) -> oneSlot $ \body -> do
        n <- gets ((+ 1) . stEndnote)
        modify' (\s -> s {stEndnote = n})
        pure [Endnote sp n lbl (noteBody sp body)]
      (_ : _, _ : _) -> err "G02038" sp "endnote は名前を書くと散文スロットを取りません" >> pure []
      ([A.Located _ (A.Positional v)], [])
        | Just name <- nameArg v,
          validLabel name -> do
            n <- gets ((+ 1) . stEndnote)
            modify' (\s -> s {stEndnote = n, stEndnoteRefs = stEndnoteRefs s <> [(sp, name)]})
            pure [Endnote sp n lbl []]
      (_, []) -> err "G02142" sp noteNameMessage >> pure []
      _ -> err "G02038" sp (builtinName b <> " には散文スロットが一つ必要です") >> pure []
    BSidenote -> noteLabel $ \lbl _ -> oneSlot $ \body -> do
      n <- gets ((+ 1) . stSidenote)
      modify' (\s -> s {stSidenote = n})
      pure [Sidenote sp n lbl (noteBody sp body)]
    BIndex -> case slots of
      [s] -> do
        -- the levels are split at the / written in the slot (golem-parser ADR 0010)
        levels <- mapM (evalInlines ctx inHeading) (splitSlot '/' s)
        case (traverse plainText levels, argText <$> lookup "reading" kw) of
          (_, Nothing) -> err "G02020" sp "索引には reading が必要です" >> pure []
          (Nothing, _) -> err "G02041" sp "索引の語は地の文に限ります" >> pure []
          (Just ts, Just reading) ->
            let rs = T.splitOn "/" reading
             in if length ts > 2 || length ts /= length rs || any T.null (ts <> rs)
                  then err "G02042" sp "索引の語と読みの段の数が不正です" >> pure []
                  else case indexKindOf (argText <$> lookup "range" kw) (argText <$> lookup "see" kw) of
                    Right k -> pure [IndexMark sp (IndexEntry ts rs k)]
                    Left (code, m) -> err code sp m >> pure []
      _ -> err "G02038" sp "index には散文スロットが一つ必要です" >> pure []
    BCite -> cite ctx sp args
    BRuby
      | not (null pos) -> err "G02157" sp "ruby の指定はキーと値で書きます" >> pure []
      | otherwise -> case rubyOptions kw of
          Left message -> err "G02157" sp message >> pure []
          Right options
            | maybe True rubySizeInInt64 (roSize options) -> ruby ctx sp options slots
            | otherwise -> outOfInt64 sp >> pure []
    BAki -> aki sp args slots
    BLink -> link ctx inHeading sp args slots
    BLang -> langSpan ctx inHeading sp args slots
    -- a soft hyphen, as U+00AD written in the source (docs/adr ADR 0272)
    BShy -> case args of
      [] -> pure [Text sp "\xAD"]
      _ -> err "G02152" sp "shy は引数を取りません。[shy] とだけ書きます" >> pure []
  where
    refTo k = \case
      [v] | validLabel (argText v) -> pure [Ref sp k (argText v)]
      _ -> err "G02026" sp "参照にはラベルの名前を一つ書きます。名前は英小文字、数字、-、_ で書きます" >> pure []
    -- the label of a note, written label=, by the rule of the characters of @label (root ADR 0422); the other arguments
    noteLabel k = case partition isLabel args of
      ([], rest) -> k Nothing rest
      ([A.Located _ (A.Keyword _ v)], rest) | Just l <- nameArg v, validLabel l -> k (Just l) rest
      -- the note stays, without a label, so that the build reports what comes after it
      (_, rest) -> err "G02026" sp "注の label にはラベルの名前を一つ書きます。名前は英小文字、数字、-、_ で書きます" >> k Nothing rest
    isLabel = \case
      A.Located _ (A.Keyword (A.Located _ "label") _) -> True
      _ -> False

{- | @[aki 量]@ (docs/adr ADR 0019): one amount, an aki name, zw, a
percentage or an absolute dimension, and no prose slot; otherwise G02055.
-}
aki :: SrcSpan -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
aki sp args slots = case (args, slots) of
  (_, _ : _) -> wrong "aki は散文スロットを取りません"
  ([A.Located _ (A.Positional v)], []) -> case nameArg v of
    Just t
      | Just a <- amount t -> if akiInInt64 a then pure [Aki sp a] else outOfInt64 sp >> pure []
      | otherwise -> wrong ("アキの量を読めません: " <> t)
    Nothing -> wrong "aki には量を一つ書きます"
  _ -> wrong "aki には量を一つ書きます"
  where
    amount t = case (parseAki t, parseDim t) of
      (Just r, _) -> Just (AkiZw r)
      (_, Just (Abs x)) -> Just (AkiAbs x)
      _ -> Nothing
    wrong why = err "G02055" sp (why <> "。" <> akiAmounts) >> pure []
    -- the numerator and the denominator of zw, or sp (golem-doc ADR 0006)
    akiInInt64 = \case
      AkiZw r -> inInt64 (numerator r) && inInt64 (denominator r)
      AkiAbs x -> inInt64 (unSp x)

{- | @[link "URL": 文字]@ (docs/adr ADR 0182): one positional argument, a
string literal or an expression of a string, and no keyword argument;
otherwise G02124, with a hint to quote a URL written as a word before a
slot that starts with //. A URL that fails the checks is G02125, G02126
or G02127, and an element inside that is a link itself G02128; then no
link is made. Without a slot, the text is the URL in the character
style url.
-}
link :: EvalContext -> Bool -> SrcSpan -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
link ctx inHeading sp args slots = case (args, slots) of
  (_, _ : _ : _) -> err "G02038" sp "link の散文スロットは一つまでです" >> pure []
  ([A.Located _ (A.Positional v)], _) -> do
    url <- case v of
      A.StringLit t -> pure (Right t)
      A.ExprArg _ ->
        argValue ctx sp v >>= \case
          Right (VString t) -> pure (Right t)
          Right _ -> pure (Left Nothing)
          Left d -> pure (Left (Just d))
      _ -> pure (Left Nothing)
    case url of
      Left (Just d) -> report d >> pure []
      Left Nothing -> wrong
      Right u -> case checkUrl u of
        Just p -> err (problemCode p) sp (urlProblemMessage p u) >> pure []
        Nothing -> do
          body <- case slots of
            [s] -> evalInlines ctx inHeading s
            _ -> pure [CharStyle sp "url" [Text sp u]]
          case linkElements body of
            [] -> pure [Link sp u body]
            es -> mapM_ (\e -> err "G02128" sp ("リンクの中にリンクになる要素は置けません: " <> e)) es >> pure []
  _ -> wrong
  where
    wrong = err "G02124" sp ("link の引数が誤っています" <> hint) >> pure []
    -- [link https://...: ...]: the : after the scheme opened the slot
    hint = case (args, slots) of
      ([A.Located _ (A.Positional (A.Word _))], [A.Located _ (A.Text t) : _])
        | "//" `T.isPrefixOf` t -> "。URL は \"https://...\" のように引用符で囲みます"
      _ -> ""
    problemCode = \case
      UrlMalformed -> "G02125"
      UrlScheme -> "G02126"
      UrlHost -> "G02127"

-- | What the amount of an [aki] may be (the message of G02055).
akiAmounts :: Text
akiAmounts = "量には、ベタ、全角、二分、三分、四分、五分、六分、八分、二分四分のどれか、単位のない 0、0.2zw のような zw、25% のような百分率、1mm のような寸法のどれかを書きます"

plainText :: [Inline] -> Maybe Text
plainText is = T.concat <$> traverse (\case Text _ t -> Just t; _ -> Nothing) is

-- | Per-ruby overrides. Dimensions remain exact until the font size is known.
rubyReading :: [Inline] -> Maybe (Text, [Maybe Text])
rubyReading xs = do
  chunks <- traverse readPart xs
  let marks = concatMap snd chunks
  pure (T.concat (map fst chunks), if all (== Nothing) marks then [] else marks)
  where
    readPart (Text _ t) = Just (t, replicate (T.length t) Nothing)
    readPart (Kenten _ shape ys) = do
      t <- plainText ys
      pure (t, replicate (T.length t) (Just (fromMaybe "sesame" shape)))
    readPart _ = Nothing

-- | The dimensions cross the same int64 boundary as the rest of the IR.
rubySizeInInt64 :: RubySize -> Bool
rubySizeInInt64 = \case
  RubySizeAbsolute n -> inInt64 (unSp n)
  RubySizeRelative r -> all inInt64 (ratioInts r)

rubyOptions :: [(Text, A.ArgValue)] -> Either Text RubyOptions
rubyOptions kw = do
  case [k | (k, _) <- kw, k `notElem` ["side", "overhang-side", "size", "align"]] of
    k : _ -> Left ("ruby の未知の指定です: " <> k)
    [] -> pure ()
  side <- choice "side" RubyBefore [("before", RubyBefore), ("after", RubyAfter), ("both", RubyBoth)]
  overhang <- choice "overhang-side" RubyOverhangBoth [("none", RubyOverhangNone), ("start", RubyOverhangStart), ("end", RubyOverhangEnd), ("both", RubyOverhangBoth)]
  size <- case value "size" of
    Nothing -> Right Nothing
    Just t -> case parseDim t of
      Just (Abs n) | n > 0 -> Right (Just (RubySizeAbsolute n))
      Just (Zw n) | n > 0 -> Right (Just (RubySizeRelative n))
      _ -> Left "ruby の size は正の寸法です"
  align <- case value "align" of
    Nothing -> Right Nothing
    Just t | t `elem` ["center", "start", "1-2-1", "0-1-0"] -> Right (Just t)
    _ -> Left "ruby の align は center、start、1-2-1、0-1-0 のいずれかです"
  pure (RubyOptions side overhang size align [] [])
  where
    value k = argText <$> lookup k kw
    choice k def options = case value k of
      Nothing -> Right def
      Just t -> maybe (Left ("ruby の " <> k <> " の値が不正です: " <> t)) Right (lookup t options)

ruby :: EvalContext -> SrcSpan -> RubyOptions -> [[A.Located A.Inline]] -> M [Inline]
ruby ctx sp options slots
  | length slots /= expected = err "G02038" sp (if expected == 3 then "ruby side=both には散文スロットが三つ必要です" else "ruby には散文スロットが二つ必要です") >> pure []
  | otherwise = case slots of
      baseSlot : readingSlot : others -> do
        base <- mapM (evalInlines ctx False) (splitSlot '/' baseSlot)
        reading <- mapM (evalInlines ctx False) (splitSlot '/' readingSlot)
        second <- case others of
          [slot] -> mapM (evalInlines ctx False) (splitSlot '/' slot)
          _ -> pure []
        case (traverse (traverse noRuby) base, traverse rubyReading reading, traverse rubyReading second) of
          (Nothing, _, _) -> err "G02016" sp "ルビの中にルビは入れられません" >> pure []
          (_, Nothing, _) -> badReading
          (_, _, Nothing) -> badReading
          (Just baseSegs, Just readSegs, Just secondSegs)
            | length baseSegs /= length readSegs || (expected == 3 && length secondSegs /= length baseSegs) -> err "G02015" sp "モノルビの対象と読みのセグメントの数が一致しません" >> pure []
            | expected == 3 && any (T.null . fst) (readSegs <> secondSegs) -> err "G02157" sp "ruby side=both の両側には、空でない読みを書きます" >> pure []
            | otherwise ->
                let optional t = if T.null t then Nothing else Just t
                    make b (r, marks) other = (RubySegment b (if expected == 2 && length baseSegs == 1 then Just r else optional r)) {rsOtherReading = other >>= optional . fst, rsOptions = options {roReadingKenten = marks, roOtherKenten = maybe [] snd other}}
                    extras = if expected == 3 then map Just secondSegs else repeat Nothing
                 in pure [Ruby sp () (zipWith3 make baseSegs readSegs extras)]
      _ -> pure []
  where
    expected = if roSide options == RubyBoth then 3 else 2
    badReading = err "G02043" sp "ルビの読みは地の文に限ります" >> pure []

{- | A slot split at a character in its top-level text; escaped characters
and nested commands are not split (golem-parser ADR 0010). A piece keeps
the span of the text it was cut from.
-}
splitSlot :: Char -> [A.Located A.Inline] -> [[A.Located A.Inline]]
splitSlot c = foldr step [[]]
  where
    step (A.Located s (A.Text t)) (cur : rest) =
      let pieces = [[A.Located s (A.Text p) | not (T.null p)] | p <- T.split (== c) t]
       in init pieces <> [last pieces <> cur] <> rest
    step x (cur : rest) = (x : cur) : rest
    step _ [] = [[]]

-- ------------------------------------------------------------------ arguments

{- | G02077 for each keyword argument whose key a keyword argument before it
already has (golem-parser ADR 0013). A keyword splat is not expanded yet,
so it has no keys.
-}
duplicateKeys :: [A.Located A.Argument] -> [Diagnostic]
duplicateKeys args = [diagnostic "G02077" Error asp ("同じキーを二度書いています: " <> k) | (asp, k) <- repeatedKeys args]

-- | The keyword arguments whose key comes before them, with their keys.
repeatedKeys :: [A.Located A.Argument] -> [(SrcSpan, Text)]
repeatedKeys args = [(asp, k) | (i, (asp, k)) <- zip [0 :: Int ..] keyed, k `elem` map snd (take i keyed)]
  where
    keyed = [(asp, k) | A.Located asp (A.Keyword (A.Located _ k) _) <- args]

-- | Report every repeated keyword while retaining every occurrence (ADR 0351 I7).
uniqueKeys :: [A.Located A.Argument] -> M [A.Located A.Argument]
uniqueKeys args = do
  mapM_ report (duplicateKeys args)
  pure args

{- | The arguments of a command with *[式] and **[式] spread (docs/adr ADR 0112)
and the repeated keys reported ('uniqueKeys'). Each element of a spread is
the argument written as a literal: a string as a string literal, another
value as [= value]; the keys of a hash in code point order. A spread of
the wrong type is G02111 or G02112 at the spread; then, as for an error of
its expression, Nothing: the command is not run.
-}
prepareArgs :: [A.Located A.Argument] -> M (Maybe [A.Located A.Argument])
prepareArgs args = do
  spread <- mapM one args
  traverse (uniqueKeys . concat) (sequence spread)
  where
    one la@(A.Located asp a) = case a of
      A.SplatPositional e -> withValue e $ \case
        VArray xs -> Right [A.Located asp (A.Positional (literalArg e x)) | x <- xs]
        v -> Left (diagnostic "G02111" Error asp ("*[式] の値は配列でなければなりません: " <> typeName v))
      A.SplatKeyword e -> withValue e $ \case
        VHash m -> Right [A.Located asp (A.Keyword (A.Located asp k) (literalArg e x)) | (k, x) <- Map.toAscList m]
        v -> Left (diagnostic "G02112" Error asp ("**[式] の値は連想配列でなければなりません: " <> typeName v))
      _ -> pure (Just [la])
    withValue e k = do
      noteRefs e
      en <- env
      case evalAnalysed en e >>= k of
        Left d -> report d >> pure Nothing
        Right xs -> pure (Just xs)
    literalArg e = \case
      VString s -> A.StringLit s
      v -> A.ExprArg (valueToExpr e v)

-- | The spans of the arguments *[式] and **[式].
spreadsOf :: [A.Located A.Argument] -> [SrcSpan]
spreadsOf args = [asp | A.Located asp a <- args, isSpread a]
  where
    isSpread = \case
      A.SplatPositional _ -> True
      A.SplatKeyword _ -> True
      _ -> False

{- | G02114 for @style: whether its body keeps its lines is decided from
the name before the evaluation, so the name is not spread (docs/adr ADR
0112). One for each spread, in the order written (docs/adr ADR 0143).
-}
styleSpread :: SrcSpan -> Diagnostic
styleSpread sp = diagnostic "G02114" Error sp "@style は評価の前に読むので、*[式] と **[式] を書けません"

-- | 'prepareArgs' on the arguments of an attribute; Nothing drops the attribute.
uniqueAttrKeys :: A.Located A.Block -> M (Maybe (A.Located A.Block))
uniqueAttrKeys = \case
  A.Located _ (A.BlockCommand (A.Located _ "style") args _) | ssps@(_ : _) <- spreadsOf args -> mapM_ (report . styleSpread) ssps >> pure Nothing
  A.Located sp (A.BlockCommand n args body) -> fmap (\args' -> A.Located sp (A.BlockCommand n args' body)) <$> prepareArgs args
  other -> pure (Just other)

{- | A citation (docs/adr/0266): every positional argument a key of the
bibliography in the order written, and @page@ the page of the one key.
Each cause in the order written, and no citation when there is one:
G02150 for an argument that is no key, G02147 for a key written twice,
G02021 for a key the bibliography does not have, G02148 for a page that
is no page, G02149 for a page of two keys or more, G02151 for no key.
-}
cite :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> M [Inline]
cite ctx sp args = do
  -- a key is a name, or a string as written or as the value of [= ...]
  positional <- mapM (\(A.Located asp v) -> maybe (keyValue asp v) (pure . Right . Just) (nameArg v)) [A.Located asp v | A.Located asp (A.Positional v) <- args]
  let (keys, keyErrors) = foldl' key ([], []) positional
      key (ks, es) = \case
        Left d -> (ks, es <> [Left d])
        Right Nothing -> (ks, es <> [Right ("G02150", "cite のキーは名前か文字列で書きます")])
        Right (Just k)
          | k `elem` ks -> (ks, es <> [Right ("G02147", "一つの引用に同じキーを二度書いています: " <> k)])
          | not (Set.member k (ctxCiteKeys ctx)) -> (ks <> [k], es <> [Right ("G02021", "書誌データにないキーです: " <> k)])
          | otherwise -> (ks <> [k], es)
  pageValue <- traverse (\(A.Located asp v) -> argValue ctx asp v) (keywordAt "page" args)
  let (locator, pageErrors) = case pageValue of
        Nothing -> (Nothing, [])
        Just (Left d) -> (Nothing, [Left d])
        Just (Right v) -> case pageOf v of
          Just l -> (Just (Locator LocatorPage l), [])
          Nothing -> (Nothing, [Right ("G02148", "page には頁の数、範囲、文字列を書きます: " <> valueText v)])
      manyKeys = [Right ("G02149", "page は文献を一つだけ引く cite に書きます") | isJust pageValue, length keys >= 2]
      noKey = [Right ("G02151", "cite には書誌データのキーを書きます") | null positional]
      problems = keyErrors <> pageErrors <> manyKeys <> noKey
  mapM_ (either report (\(code, msg) -> err code sp msg)) problems
  pure [Cite sp [CiteItem k locator [] [] | k <- keys] | null problems]
  where
    keyValue asp v = fmap keyOf <$> argValue ctx asp v
    keyOf = \case
      VString k -> Just k
      _ -> Nothing
    pageOf = \case
      VNat n -> Just (LocNumber (toInteger n))
      VInt n | n >= 0 -> Just (LocNumber n)
      VRat q | denominator q == 1, q >= 0 -> Just (LocNumber (numerator q))
      VRange a b | a >= 0 -> Just (LocRange a b)
      VString t | not (T.null t) -> Just (LocText t)
      _ -> Nothing

-- | The first keyword argument @k@, at the position of the argument.
keywordAt :: Text -> [A.Located A.Argument] -> Maybe (A.Located A.ArgValue)
keywordAt k args = listToMaybe [A.Located asp v | A.Located asp (A.Keyword (A.Located _ k') v) <- args, k' == k]

keywords :: EvalContext -> [A.Located A.Argument] -> M [(Text, A.ArgValue)]
keywords _ args = pure [(k, v) | A.Located _ (A.Keyword (A.Located _ k) v) <- args]

-- | A name written as a word or a string literal.
nameArg :: A.ArgValue -> Maybe Text
nameArg = \case
  A.Word t -> Just t
  A.StringLit t -> Just t
  _ -> Nothing

{- | The kind of an index mark by its range and see (docs/adr/0265): a
point without either, an end of a range by range, a reference of one or
two levels by see; both, another range, or a target of another number of
levels or of an empty level are the codes of their causes.
-}
indexKindOf :: Maybe Text -> Maybe Text -> Either (Text, Text) IndexKind
indexKindOf range see = case (range, see) of
  (Just _, Just _) -> Left ("G02145", "一つの索引の印に see と range は書けません")
  (Just "begin", Nothing) -> Right IndexRangeBegin
  (Just "end", Nothing) -> Right IndexRangeEnd
  (Just r, Nothing) -> Left ("G02144", "range は begin か end です: " <> r)
  (Nothing, Just t)
    | let target = T.splitOn "/" t,
      length target <= 2,
      not (any T.null target) ->
        Right (IndexSee SeeAuto target)
    | otherwise -> Left ("G02146", "see の参照先の語は一段か二段で、空の段を持てません: " <> t)
  (Nothing, Nothing) -> Right IndexPoint

argText :: A.ArgValue -> Text
argText = \case
  A.Word t -> t
  A.StringLit t -> t
  _ -> ""

argValueRaw :: A.ArgValue -> Value
argValueRaw = \case
  A.Word t -> fromMaybe (VString t) (wordNumber t)
  A.StringLit t -> VString t
  _ -> VNil

{- | A word that is a number literal of the expression language, with one
leading - (docs/adr ADR 0111): the value of the same text in an expression,
of the same type (docs/adr ADR 0101). Digits are a natural number, -
and digits an integer, a decimal or an exponent a rational. Nothing for
another word, which stays a string.
-}
wordNumber :: Text -> Maybe Value
wordNumber t = case T.stripPrefix "-" t of
  Just rest -> negateNumber <$> unsigned rest
  Nothing -> unsigned t
  where
    unsigned u
      | T.null u || "-" `T.isPrefixOf` u = Nothing
      | T.all isDigit u = Just (VNat (read (T.unpack u)))
      | otherwise = VRat <$> A.numberWord u
    negateNumber = \case
      VNat n -> VInt (negate (toInteger n))
      VRat q -> VRat (negate q)
      v -> v

{- | The value of an argument. A word that is a number literal past the
limit of the evaluator is G02086 at @sp@, as the same literal in an
expression is (docs/adr ADR 0101; the audit of 2026-10-28, F-01;
docs/adr ADR 0111). A word of a closed range literal is the range of the
same text in an expression (docs/adr ADR 0113, ADR 0111): a place that
takes no range reads its arguments with 'plainArgValue'.
-}
argValue :: EvalContext -> SrcSpan -> A.ArgValue -> M (Either Diagnostic Value)
argValue _ sp = \case
  A.ExprArg e -> do
    noteRefs e
    en <- env
    pure (evalAnalysed en e)
  A.Word w | Just (a, b) <- rangeWord w -> case [q | Just (_, q) <- map numberOf [a, b], overLimit q] of
    _ : _ -> pure (Left (tooBigDiagnostic sp))
    [] -> do
      en <- env
      let lit = valueToExpr (A.Located sp A.ENil)
      pure (evalAnalysed en (A.Located sp (A.ERange (lit a) (lit b))))
  v ->
    pure
      ( case argValueRaw v of
          val | Just (_, q) <- numberOf val, overLimit q -> Left (tooBigDiagnostic sp)
          val -> Right val
      )

{- | The value of an argument where no range is taken (docs/adr ADR
0111): its 'argValue' at @sp@, and a range is G02113 at the argument
(the audit of 2026-11-04, F-16), with the text of a word as written. A
word of a closed range literal is first the range of
the same text in an expression, so one that is no range has the code of
that expression: G02104, G02106 or G02086 (docs/adr ADR 0135).
-}
plainArgValue :: EvalContext -> SrcSpan -> A.Located A.ArgValue -> M (Either Diagnostic Value)
plainArgValue ctx sp (A.Located asp v) =
  argValue ctx sp v >>= \case
    Right r@(VRange _ _) -> pure (Left (rangeDiagnostic asp (written r)))
    other -> pure other
  where
    written r = case v of
      A.Word w -> w
      _ -> valueText r

{- | The ends of a word of a closed range literal, @<number>...<number>@
with each end a number literal (docs/adr ADR 0113, ADR 0111). Nothing
for another word: @1...@, @a...3@ and @1...2...3@ are none.
-}
rangeWord :: Text -> Maybe (Value, Value)
rangeWord w = case T.breakOn "..." w of
  (a, rest) | not (T.null rest) -> (,) <$> wordNumber a <*> wordNumber (T.drop 3 rest)
  _ -> Nothing

-- | G02113: a range where the argument takes no range (docs/adr ADR 0111).
rangeDiagnostic :: SrcSpan -> Text -> Diagnostic
rangeDiagnostic sp w = diagnostic "G02113" Error sp ("範囲を受け取らない引数に範囲を書いています: " <> w)

-- | The evaluation of an expression after the analysis (docs/adr ADR 0102).
evalAnalysed :: Env -> A.Located A.Expr -> Either Diagnostic Value
evalAnalysed en e = maybe (evalExpr en e) Left (analyse en e)

-- | Why an argument is no natural number (docs/adr ADR 0102).
data NaturalError
  = -- | it is no number, nor a word read as one: the place reports it with its own code
    NotANumber
  | -- | its diagnostic is reported (G02103, G02104, or one of its expression)
    NaturalReported

{- | An argument at a place that takes a natural number (docs/adr ADR
0102): a word read as a number literal, a leading - allowed, or an
expression evaluated after the analysis. A negative number is G02103 and
one that is not an integer G02104, at @sp@; @what@ names the place. A
word of a closed range literal, as an expression, is read with
'plainArgValue' (docs/adr ADR 0135).
-}
naturalArg :: EvalContext -> Text -> SrcSpan -> A.Located A.ArgValue -> M (Either NaturalError Natural)
naturalArg ctx what sp lv@(A.Located _ v) = case v of
  A.Word w | Nothing <- rangeWord w -> maybe (pure (Left NotANumber)) check (A.numberWord w)
  A.Word _ -> fromValue
  A.ExprArg _ -> fromValue
  _ -> pure (Left NotANumber)
  where
    fromValue =
      plainArgValue ctx sp lv >>= \case
        Left d -> report d >> pure (Left NaturalReported)
        Right val -> maybe (pure (Left NotANumber)) (check . snd) (numberOf val)
    check q = case naturalOf what sp q of
      Left d -> report d >> pure (Left NaturalReported)
      Right n -> pure (Right n)

{- | A number at a place that takes a natural number: G02086 past the
limit of the evaluator, as the same literal in an expression is (docs/adr
ADR 0101; the audit of 2026-10-28, F-01), then G02103 or G02104 (docs/adr
ADR 0102).
-}
naturalOf :: Text -> SrcSpan -> Rational -> Either Diagnostic Natural
naturalOf what sp q
  | overLimit q = Left (tooBigDiagnostic sp)
  | Just d <- naturalDiagnostic what sp q = Left d
  | otherwise = Right (fromInteger (numerator q))

-- | A range of lines, both ends included; the first is not after the last (ADR 0342).
data LineRange = LineRange !Natural !Natural

-- | An item of a word or a string of ranges, with its ends as written.
data RangeItem
  = -- | one line, @3@
    ItemLine Rational
  | -- | the closed range @3...5@
    ItemRange Rational Rational
  | -- | the obsolete range @3-5@ (G02251), and its ends as written
    ItemDash Text Text Rational Rational

-- | Why an item is not read (docs/adr ADR 0113, ADR 0115).
data ItemError
  = -- | G02110: an end is missing or cannot be read
    ItemBadEnd
  | -- | G02103: the first end read from the start of the item is negative (root ADR 0419)
    ItemNegative Rational
  | -- | G01100: the reserved ..
    ItemReserved
  | -- | G02105: neither a line nor a range
    ItemNeither

{- | An argument of lines (lines= of @listing, highlight= of a code
block; docs/adr ADR 0113): Nothing when a diagnostic is reported, else
the text of the value, for the messages of the place, and the ranges in
the order written. @what@ names the place; @sp@ is the argument.

A word or a string is items separated by commas: a line @3@ or a range
@3...5@. The obsolete range @3-5@ is G02251 once per argument.
A written negative end is G02103, as an evaluated one (root ADR 0419). An expression is a range, a number
(one line), a string (read as a word), or an array of numbers and ranges.
Evaluated ends must be positive integers.
-}
lineRanges :: EvalContext -> Text -> SrcSpan -> A.ArgValue -> M (Maybe (Text, [LineRange]))
lineRanges ctx what sp = \case
  A.Word t -> ofText t
  A.StringLit t -> ofText t
  -- a range written in the argument: its ends are checked as natural numbers
  -- before its direction, as the ends of a word are (lines=[= 3...0 - 1] is G02103)
  A.ExprArg e@(A.Located esp (A.ERange a b)) -> do
    noteRefs e
    en <- env
    case analyse en e of
      Just d -> report d >> pure Nothing
      Nothing -> case (,) <$> evalExpr en a <*> evalExpr en b of
        Left d -> report d >> pure Nothing
        Right (x, y) -> case (numberOf x, numberOf y) of
          (Just (_, p), Just (_, q)) -> naturals [(p, q)] >>= maybe (pure Nothing) (done (rangeText p q))
          _ -> report (rangeEndDiagnostic esp (valueText (if isJust (numberOf x) then y else x))) >> pure Nothing
  v@(A.ExprArg _) ->
    argValue ctx sp v >>= \case
      Left d -> report d >> pure Nothing
      Right val -> ofValue val
  A.CommandArg _ -> neither ""
  where
    -- U+0020 spaces only after a comma (ADR 0342)
    ofText t = case traverse rangeItem (afterCommas (T.splitOn "," t)) of
      Left (ItemBadEnd, i) -> report (rangeEndDiagnostic sp i) >> pure Nothing
      Left (ItemNegative q, _) -> either report (const (pure ())) (naturalOf what sp q) >> pure Nothing
      Left (ItemReserved, _) -> err "G01100" sp "予約された記法です。今のバージョンでは使えません" >> pure Nothing
      Left (ItemNeither, i) -> neither i
      Right items -> case [(x, y) | ItemDash x y _ _ <- items] of
        (x, y) : _ -> err "G02251" sp ("- で区切った範囲は使えません。" <> x <> "..." <> y <> " のように両端を残して ... で区切ります") >> pure Nothing
        [] -> naturals (map ends items) >>= maybe (pure Nothing) (done t)
    ofValue = \case
      VString s -> ofText s
      VArray vs -> case traverse valueEnds vs of
        Just es -> naturals es >>= maybe (pure Nothing) (done (T.intercalate "," (map valueText vs)))
        Nothing -> neither (T.intercalate "," [valueText x | x <- vs, isNothing (valueEnds x)])
      val | Just es <- valueEnds val -> naturals [es] >>= maybe (pure Nothing) (done (valueText val))
      val -> neither (valueText val)
    valueEnds = \case
      VRange a b -> Just (fromInteger a, fromInteger b)
      val -> (\(_, q) -> (q, q)) <$> numberOf val
    ends = \case
      ItemLine q -> (q, q)
      ItemRange p q -> (p, q)
      ItemDash _ _ p q -> (p, q)
    -- the ends as natural numbers, then the direction
    naturals es = case traverse (\(p, q) -> (,) <$> naturalOf what sp p <*> naturalOf what sp q) es of
      Left d -> report d >> pure Nothing
      Right ns -> case [(a, b) | (a, b) <- ns, a > b] of
        (a, b) : _ -> err "G02106" sp ("範囲の始め " <> tshow a <> " が終わり " <> tshow b <> " より大きくなっています") >> pure Nothing
        [] -> pure (Just [LineRange a b | (a, b) <- ns])
    done t rs = pure (Just (t, rs))
    afterCommas = \case
      i : is -> i : map (T.dropWhile (== ' ')) is
      [] -> []
    rangeText p q = exactText p <> "..." <> exactText q
    neither v = err "G02105" sp (what <> " には行の番号か範囲を書きます: " <> v) >> pure Nothing

{- | An item of a word or a string of ranges (docs/adr ADR 0113), with
the item for the message when it is not read. The ends are read from the
start, and the first error is the one of the item: a negative end is
G02103 (root ADR 0419), and @-0@ is 0.
-}
rangeItem :: Text -> Either (ItemError, Text) RangeItem
rangeItem i
  | (a, rest) <- T.breakOn "..." i,
    not (T.null rest) =
      ItemRange <$> end a <*> end (T.drop 3 rest)
  | Just q <- rangeEndWord i = ItemLine <$> natural q
  | "-" `T.isPrefixOf` i = case rangeEnds i of
      -- the start is negative, or -0 of an obsolete range
      Just (a : _) | Just q <- rangeEndWord a -> natural q >> dash
      _ -> Left (ItemBadEnd, i)
  | otherwise = dash
  where
    dash
      | ".." `T.isInfixOf` i = Left (ItemReserved, i)
      | Just [a, b] <- rangeEnds i = case (rangeEndWord a, rangeEndWord b) of
          (Just p, Just q) -> ItemDash a b p <$> natural q
          _ | "-" `T.isPrefixOf` b -> Left (ItemBadEnd, i)
          _ -> Left (ItemNeither, i)
      | otherwise = Left (ItemNeither, i)
    end w = maybe (Left (ItemBadEnd, i)) natural (rangeEndWord w)
    natural q
      | q < 0 = Left (ItemNegative q, i)
      | otherwise = Right q

{- | An end of a range written in a word: a number literal. A dot is between digits, as in an
expression: @.2@ and @2.@ are no ends.
-}
rangeEndWord :: Text -> Maybe Rational
rangeEndWord w
  | any badDot (T.breakOnAll "." body) || "." `T.isPrefixOf` body = Nothing
  | otherwise = A.numberWord w
  where
    body = fromMaybe w (T.stripPrefix "-" w)
    badDot (_, after) = not (startsWithDigit (T.drop 1 after))
    startsWithDigit t = maybe False (isDigit . fst) (T.uncons t)

{- | The value of numbers= of a code block (docs/adr ADR 0113): true,
false or a natural number, as a word, a string or an expression. Another
value is G02069; a number that is no natural number is G02086, G02103 or
G02104.
-}
numbersArg :: EvalContext -> SrcSpan -> A.ArgValue -> M (Maybe (Either Bool Integer))
numbersArg ctx sp = \case
  A.Word t | Just b <- boolWord t -> pure (Just (Left b))
  A.StringLit t | Just b <- boolWord t -> pure (Just (Left b))
  A.StringLit t -> natural (A.Word t) t
  v@(A.ExprArg _) ->
    plainArgValue ctx sp (A.Located sp v) >>= \case
      Left d -> report d >> pure Nothing
      Right (VBool b) -> pure (Just (Left b))
      Right val | Just (_, q) <- numberOf val -> either (\d -> report d >> pure Nothing) (pure . Just . Right . toInteger) (naturalOf what sp q)
      Right val -> bad (valueText val)
  v -> natural v (argText v)
  where
    what = "コードブロックの numbers"
    boolWord = \case
      "true" -> Just True
      "false" -> Just False
      _ -> Nothing
    natural v t =
      naturalArg ctx what sp (A.Located sp v) >>= \case
        Right n -> pure (Just (Right (toInteger n)))
        Left NaturalReported -> pure Nothing
        Left NotANumber -> bad t
    bad t = err "G02069" sp ("numbers の値が正しくありません: " <> t) >> pure Nothing

{- | The ends of one range of - of an argument, @3@ or @3-5@, which is to
be retired (docs/adr ADR 0113): an end is a leading - and the text up to
the next - that does not follow an e (the exponent of @1e-3@). Nothing
for more than two ends, or an empty one.
-}
rangeEnds :: Text -> Maybe [Text]
rangeEnds t = case end t of
  (a, rest)
    | T.null a -> Nothing
    | T.null rest -> Just [a]
    | Just r <- T.stripPrefix "-" rest, (b, rest') <- end r, not (T.null b), T.null rest' -> Just [a, b]
    | otherwise -> Nothing
  where
    end s =
      let (sign, body) = maybe ("", s) ("-",) (T.stripPrefix "-" s)
          n = upTo 0 ' ' (T.unpack body)
       in (sign <> T.take n body, T.drop n body)
    upTo :: Int -> Char -> String -> Int
    upTo i prev = \case
      c : cs | c /= '-' || prev == 'e' -> upTo (i + 1) c cs
      _ -> i

{- | G02091: an integer out of int64 for a field of the IR (golem-doc ADR
0006).
-}
outOfInt64 :: SrcSpan -> M ()
outOfInt64 sp = err "G02091" sp outOfInt64Message

outOfInt64Message :: Text
outOfInt64Message = "数が意味論 IR に書ける範囲を超えています（整数と、分数の分子と分母は -2 の 63 乗以上、2 の 63 乗未満に限ります）"

-- | The number literals of an expression.
exprNumbers :: A.Located A.Expr -> [Rational]
exprNumbers (A.Located _ e) = case e of
  A.ENat n -> [toRational n]
  A.EInt i -> [fromInteger i]
  A.ERat q -> [q]
  A.EArray xs -> concatMap exprNumbers xs
  A.EHash kvs -> concatMap (exprNumbers . snd) kvs
  A.ECall _ xs -> concatMap exprNumbers xs
  A.EUnary _ a -> exprNumbers a
  A.EBinary _ a b -> exprNumbers a <> exprNumbers b
  A.ERange a b -> exprNumbers a <> exprNumbers b
  _ -> []

-- | The integers a number is written with in the IR: its numerator and denominator.
ratioInts :: Rational -> [Integer]
ratioInts q = [numerator q, denominator q]

-- | The integers of a value as a plugin gets it.
valueInts :: Value -> [Integer]
valueInts = \case
  VArray vs -> concatMap valueInts vs
  VRange a b -> [a, b]
  v -> maybe [] (ratioInts . snd) (numberOf v)

{- | The value of a number that is an integer, of any of the three types
(the narrowing of docs/adr ADR 0101).
-}
intOf :: Value -> Maybe Integer
intOf v = case numberOf v of
  Just (_, q) | denominator q == 1 -> Just (numerator q)
  _ -> Nothing
