{- | File evaluation, S0 (golem-eval ADR 0002): one source file and its
imports become semantic IR. Values that need the whole document (S1) or
the layout (S2) are left as 'Ref' and 'Deferred' inlines.
-}
module Golem.Eval.File
  ( EvalContext (..),
    Asset (..),
    PluginHook (..),
    PluginCommand (..),
    PluginBlockCommand (..),
    noPlugins,
    figureChecks,
    Usage (..),
    EvalResult (..),
    evalFile,
    builtinInlineCommands,
    overridableCommands,
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
import Control.Monad (forM, unless, when)
import Control.Monad.State.Strict
import Data.Bifunctor qualified as Bi
import Data.ByteString (ByteString)
import Data.Char (isAscii, isAsciiLower, isDigit)
import Data.Either (fromLeft, fromRight, isLeft)
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
import Golem.Eval.RegexStyle (applyRegexStyles, regexRules)
import Golem.Eval.Settings
import Golem.Eval.Value
import Golem.Parser.AST qualified as A
import Golem.Parser.Lower qualified as A (numberWord)
import Golem.Parser.Read (checkTableText)
import Golem.Parser.SourceSettings
import Golem.Project.Imports (ImportSite (..), importSite)
import Golem.Project.Paths (PathError (..), normalizeRelative, pathErrorMessage)
import Golem.Project.Style (Dim (..), LineBreaks (..), LocalStyles (..), Sp (..), Style, kentenShapeNames, noLocalStyles, paraLineBreaks, parseAki, parseDim, withLocalStyles)
import Golem.Syntax
import Golem.Syntax.LanguageTag (isLanguageTag)
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
  { phOverrides :: !(Map OverridableBuiltin PluginCommand),
    phCommands :: !(Map PluginCommandName PluginCommand),
    -- | the block commands of the plugins, by name (docs/adr/0122)
    phBlocks :: !(Map Text PluginBlockCommand),
    -- | the channels the plugins declare (golem-doc ADR 0007)
    phChannels :: !(Map Text ChannelDecl),
    phApplyFilters :: FilePath -> Document -> Either [Diagnostic] (Document, [Diagnostic]),
    -- | the names of the context of the book the plugins ask for, in order (docs/adr/0121)
    phContextNames :: ![Text]
  }

noPlugins :: PluginHook
noPlugins = PluginHook Map.empty Map.empty Map.empty Map.empty (\_ d -> Right (d, [])) []

data EvalContext = EvalContext
  { ctxFile :: !FileId,
    ctxPath :: !FilePath,
    ctxProfile :: !Profile,
    ctxMeta :: !(Map Text Value),
    -- | the namespace vars, the values of [vars] of manifest.toml (docs/adr/0185)
    ctxVars :: !(Map Text Value),
    ctxImports :: !(Map FilePath (Map Text Value)), -- exported variables by file
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
    -- | the functions of the .emet of the project (docs/adr/0162)
    ctxFunctions :: !FunctionTable
  }

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
    usageImports :: ![(Text, FilePath, SrcSpan)]
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
    stDiags :: ![Diagnostic],
    -- | the line of each @number by the span of its block (G04007)
    stNumberSites :: !(Map SrcSpan SrcSpan),
    -- | the images of the figures of plugins that passed the checks (docs/adr/0123)
    stImages :: !(Map Text ByteString),
    -- | each [note name] in order: its span and its name (docs/adr/0263)
    stNoteRefs :: ![(SrcSpan, Text)],
    -- | each @note in order: its name, its span and its body, Nothing for one of a name already defined (docs/adr/0263)
    stNoteDefs :: ![(Text, SrcSpan, [Block])]
  }

type M = State St

{- | A diagnostic of the file; one of a call through a namespace whose
.emet could not be loaded is not reported (docs/adr/0162).
-}
report :: Diagnostic -> M ()
report d
  | isUnloaded d = pure ()
  | otherwise = modify' (\s -> s {stDiags = stDiags s <> [d]})

err :: Text -> SrcSpan -> Text -> M ()
err code sp msg = report (diagnostic code Error sp msg)

builtinInlineCommands :: [Text]
builtinInlineCommands = map builtinName allBuiltins

-- | Built-in commands a plugin may override when the manifest says so.
overridableCommands :: [Text]
overridableCommands = [builtinName b | b@(Overridable _) <- allBuiltins]

attributeCommands :: [Text]
attributeCommands = ["label", "toc-title", "number", "nonumber", "notoc", "style", "caption", "lang", "column-widths"]

{- | The attributes that have a body form too: with a body, the command is
a block of its own (docs/adr ADR 0005, ADR 0187).
-}
bodyFormCommands :: [Text]
bodyFormCommands = ["style", "lang"]

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
      (local, styleDiags) = fileStyles (ctxStyle ctx0) header
      ctx = (withFileStyles local ctx0) {ctxSource = source}
      blocks = map normalizeBlock (splitLines (ctxSource ctx) (ctxParaStyles ctx) rest)
      -- meta and vars, which every file reads without @import (docs/adr/0185)
      st0 = St Map.empty (Map.fromList [("meta", ctxMeta ctx), ("vars", ctxVars ctx)]) Map.empty [] Set.empty Map.empty [] 0 0 (settingDiags <> styleDiags) Map.empty Map.empty [] []
      (bsEval, st) = runState (concat <$> mapM (evalBlock ctx) blocks) st0
      -- the notes written by name take their bodies (docs/adr/0263)
      (bs0, noteDiags) = namedNotes (stNoteRefs st) (stNoteDefs st) bsEval
      (bs, nestedDiags) = nestedBreaks bs0
      breakDiags = nestedDiags <> conflictingBreaks bs <> blankLinesInRow bs
      doc0 = Document fid bs
      (doc, filterDiags) = case phApplyFilters (ctxPlugins ctx) (ctxPath ctx) doc0 of
        Left ds -> (doc0, ds)
        Right (d, ws) -> (fillFilterKenten ctx d, ws <> unknownParaStyles ctx d <> functionFilterNames ctx d)
      -- the regex styles last, so that the text of filters is matched too (docs/adr ADR 0015)
      rules = regexRules (withLocalStyles (ctxStyle ctx0) local)
   in EvalResult
        { erDocument = applyRegexStyles rules doc,
          erExports = stVars st,
          erUsage = Usage (stDefined st) (stRefs st) (stNsRefs st) (stImports st),
          erDiagnostics = stDiags st <> noteDiags <> breakDiags <> filterDiags <> unwritableText (applyRegexStyles rules doc),
          erSource = ctxSource ctx,
          erStyles = local,
          erNumberSites = stNumberSites st,
          erImages = stImages st
        }

{- | The context with the styles of the file over those of style.toml
(docs/adr ADR 0014): its character styles added, and whether each
paragraph style keeps its lines resolved again, as an override may change
the styles based on it.
-}
withFileStyles :: LocalStyles -> EvalContext -> EvalContext
withFileStyles local ctx
  | local == noLocalStyles = ctx
  | otherwise =
      ctx
        { ctxCharStyles = Set.union (Map.keysSet (lsCharStyles local)) (ctxCharStyles ctx),
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
    inlines :: [InlineF r] -> [Diagnostic]
    inlines = concatMap inline
    inline :: InlineF r -> [Diagnostic]
    inline = \case
      Text sp t -> at sp t
      Ruby sp _ segs -> concat [inlines (rsBase g) <> maybe [] (at sp) (rsReading g) | g <- segs]
      Kenten _ _ xs -> inlines xs
      Color _ _ xs -> inlines xs
      CharStyle _ _ xs -> inlines xs
      Tcy sp t -> at sp t
      Note _ _ bs -> concatMap inlines (noteParagraphs bs)
      Sidenote _ _ bs -> concatMap inlines (noteParagraphs bs)
      IndexMark sp e -> concatMap (at sp) (ieTerms e <> ieReadings e)
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
paragraphs a paragraph style is given to (the body of @style and the
target of an attribute group with @style), which keep them at the top
level (docs/adr ADR 0005).
-}
normalizeBlock :: A.Located A.Block -> A.Located A.Block
normalizeBlock (A.Located sp b) = A.Located sp $ case b of
  A.Paragraph is -> A.Paragraph (joinSoftBreaks is)
  A.Heading l is -> A.Heading l (joinSoftBreaks is)
  A.BulletList items -> A.BulletList (map (map normalizeBlock) items)
  A.OrderedList items -> A.OrderedList (map (map normalizeBlock) items)
  A.DefList gs -> A.DefList [A.DefGroup (map joinSoftBreaks ts) (map (map normalizeBlock) ds) | A.DefGroup ts ds <- gs]
  A.Table al h rows -> A.Table al (map joinSoftBreaks h) (map (map joinSoftBreaks) rows)
  A.BlockCommand n@(A.Located _ "style") args body -> A.BlockCommand n (map normalizeArg args) (map styledBody body)
  A.BlockCommand n args body -> A.BlockCommand n (map normalizeArg args) (map normalizeBlock body)
  A.Attributed cs t
    | any isStyleCommand cs -> A.Attributed (map normalizeBlock cs) (styledBody <$> t)
    | otherwise -> A.Attributed (map normalizeBlock cs) (normalizeBlock <$> t)
  other -> other
  where
    styledBody = \case
      A.Located psp (A.Paragraph is) -> A.Located psp (A.Paragraph (map nestedInline is))
      other -> normalizeBlock other

isStyleCommand :: A.Located A.Block -> Bool
isStyleCommand = \case
  A.Located _ (A.BlockCommand (A.Located _ "style") _ _) -> True
  _ -> False

-- ------------------------------------------------------------------ the line style

{- | The line style (docs/adr ADR 0013): a paragraph is split at its
top-level 'A.SoftBreak' into paragraphs, one per line. An attribute goes
to the first of them. The paragraphs of a style that keeps its lines are
left alone, and so are headings, terms, tables and code. The blank-line
style changes nothing.
-}
splitLines :: SourceSettings -> Map Text LineBreaks -> [A.Located A.Block] -> [A.Located A.Block]
splitLines source paraStyles
  | ssParagraphSeparator source == BlankLineSeparated = id
  | otherwise = concatMap splitBlock
  where
    splitBlock lb@(A.Located sp b) = case b of
      A.Paragraph is -> splitParagraph is
      A.Attributed cmds (Just (A.Located _ (A.Paragraph is)))
        | any keepsLines cmds -> [lb]
        | otherwise -> case splitParagraph is of
            first@(A.Located fsp _) : rest -> A.Located (mkSpan (spanFile sp) (spanStart sp) (spanEnd fsp)) (A.Attributed (map inside cmds) (Just first)) : rest
            [] -> [A.Located sp (A.Attributed (map inside cmds) Nothing)]
      _ -> [inside lb]
    -- a block that is not split itself, with the blocks inside it split
    inside lb@(A.Located sp b) = A.Located sp $ case b of
      A.BulletList items -> A.BulletList (map (concatMap splitBlock) items)
      A.OrderedList items -> A.OrderedList (map (concatMap splitBlock) items)
      A.DefList gs -> A.DefList [A.DefGroup ts (map (concatMap splitBlock) ds) | A.DefGroup ts ds <- gs]
      A.BlockCommand n args body
        | keepsLines lb -> b
        | otherwise -> A.BlockCommand n args (concatMap splitBlock body)
      A.Attributed cmds t -> A.Attributed (map inside cmds) (inside <$> t)
      other -> other
    -- @style with the name of a style that keeps its lines
    keepsLines = \case
      A.Located _ (A.BlockCommand (A.Located _ "style") [A.Located _ (A.Positional v)] _) | Just n <- nameArg v -> Map.lookup n paraStyles == Just KeepLines
      _ -> False

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
env = gets (\s -> Env (stVars s) (stNamespaces s) (stFunctions s))

block :: SrcSpan -> BlockBody -> Block
block sp = Block sp Nothing Nothing

evalBlock :: EvalContext -> A.Located A.Block -> M [Block]
evalBlock ctx (A.Located sp b) = case b of
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
    -- @style is read before the evaluation for the lines of its body: G02114 at each spread (docs/adr ADR 0112, ADR 0143)
    | n == "style", ssps@(_ : _) <- spreadsOf args -> mapM_ (report . styleSpread) ssps >> pure []
    | otherwise -> prepareArgs args >>= maybe (pure []) (\args' -> standalone ctx sp name args' body)
  A.Attributed cmds target -> attributed ctx sp cmds target
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

-- A block command that is not an attribute of another block.
standalone :: EvalContext -> SrcSpan -> A.Located A.Name -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
standalone ctx sp (A.Located nsp name) args body = case name of
  "import" -> do
    -- the same check as the project's (golem-project ADR 0006); G02023 points at the namespace
    case (importSite sp (map A.locValue args), args) of
      (Right (ImportSite path ns _), [_, _, A.Located nssp _]) -> do
        if ns `elem` reservedNames
          then err "G02023" nssp ("予約語は名前空間に使えません: " <> ns)
          else
            if ".emet" `T.isSuffixOf` path
              then -- the functions of a .emet (docs/adr/0162)
                let table = ctxFunctions ctx
                    ref = case normalizeRelative (T.unpack path) >>= \p -> maybe (Left Missing) Right (Map.lookup p (ftFiles table)) of
                      Right fns | not (ftUnloaded table) -> Loaded fns
                      _ -> Unloaded
                 in modify' (\s -> s {stFunctions = Map.insert ns ref (stFunctions s), stImports = stImports s <> [(ns, T.unpack path, sp)]})
              else do
                let vals = fromMaybe Map.empty (Map.lookup (T.unpack path) (ctxImports ctx))
                modify' (\s -> s {stNamespaces = Map.insert ns vals (stNamespaces s), stImports = stImports s <> [(ns, T.unpack path, sp)]})
      (Left d, _) -> report d
      -- importSite accepts three arguments only
      (Right _, _) -> pure ()
    pure []
  "toc" -> do
    depth <- maybe (pure (Right 2)) (naturalArg ctx "@toc の depth" sp) (keywordAt "depth" args)
    case depth of
      Right d | d >= 1 && d <= 6 -> pure [block sp (ChannelOutput (TocOutput (fromIntegral d)))]
      Left NaturalReported -> pure []
      _ -> err "G02025" sp "@toc の depth は 1 から 6 の整数です" >> pure []
  -- the body of a note of more than one paragraph (docs/adr/0263)
  "note" -> noteDefinition ctx sp args body
  "index" -> pure [block sp (ChannelOutput IndexOutput)]
  "bibliography" -> pure [block sp (ChannelOutput BibliographyOutput)]
  "channel" -> channelBlock ctx sp args
  "printings" -> printingsBlock ctx sp args body
  "page-break" -> forcedBreak sp name args body
  "column-break" -> forcedBreak sp name args body
  "no-page-break" -> pageControl sp name args body
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
    | otherwise -> err "G02009" nsp ("未知のブロックコマンドです: @" <> name) >> pure []

{- | A block command of a plugin (docs/adr/0122): its arguments as a plugin
command's, its body evaluated as blocks. An argument beyond int64 is
G02091 and the plugin is not called.
-}
pluginBlock :: EvalContext -> SrcSpan -> PluginBlockCommand -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
pluginBlock ctx sp pb args body = do
  vals <- pluginArgs ctx sp args
  body' <- evalBlocks ctx body
  case sequence vals of
    Left d -> report d >> pure []
    Right vs | not (all (all inInt64 . valueInts . pluginArgValue) vs) -> outOfInt64 sp >> pure []
    Right vs -> case pbCall pb vs body' sp of
      Left ds -> mapM_ report ds >> pure []
      Right (out, imgs, ds) -> do
        mapM_ report ds
        concat <$> mapM (pluginFigure body' imgs) out
  where
    {- a figure the plugin made goes through the checks of @figure
    (checkFigure), its image found among the images of the answer; one that
    fails gives no block, as @figure, and its image is not kept. A paragraph
    style in its caption is G02013, and is dropped, as @figure does
    (docs/adr/0123) -}
    pluginFigure body' imgs b = case b of
      Block bsp lbl lang (FigureBlock f) | b `notElem` body' -> do
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

{- | The arguments of a call of a plugin: a keyword with its name
(docs/adr/0110). A spread is already expanded by 'prepareArgs'
(docs/adr/0112), so a plugin never gets one.
-}
pluginArgs :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> M [Either Diagnostic PluginArg]
pluginArgs ctx sp args = forM args $ \(A.Located _ a) -> case a of
  A.Positional v -> fmap PluginPositional <$> argValue ctx sp v
  A.Keyword (A.Located _ k) v -> fmap (PluginKeyword k) <$> argValue ctx sp v
  _ -> pure (Right (PluginPositional VNil))

-- ------------------------------------------------------------------ functions of .emet

{- | The namespace of a command of a .emet (docs/adr/0162): Left with the
diagnostic of a namespace the file has not imported, Nothing for one whose
.emet could not be loaded (nothing is reported), or its functions.
-}
functionNamespace :: Text -> SrcSpan -> Text -> Text -> M (Either Diagnostic (Maybe FunctionNamespace))
functionNamespace code nsp ns shown = do
  -- the namespace is used, for the lint of unused imports (G05003)
  modify' (\s -> s {stNsRefs = Map.insertWith Set.union ns (Set.singleton shown) (stNsRefs s)})
  refs <- gets stFunctions
  isVars <- gets (Map.member ns . stNamespaces)
  pure $ case Map.lookup ns refs of
    Just (Loaded fns) -> Right (Just fns)
    Just Unloaded -> Right Nothing
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
  case sequence vals of
    Left d -> report d >> pure Nothing
    Right vs -> do
      let known = map kpName (prKeywords ps)
          unknown = [(asp, k) | (A.Located asp (A.Keyword (A.Located _ k) _)) <- args, k `notElem` known]
      mapM_ (\(asp, k) -> err "G02119" asp ("シグネチャにないキーワード引数です: " <> k <> "（" <> name <> (if null known then " はキーワード引数を取りません）" else " のキーワード引数: " <> T.intercalate "、" known <> "）"))) unknown
      if not (null unknown)
        then pure Nothing
        else case positionalValues ps [v | (Nothing, v) <- vs] of
          Left e -> report (argErrorDiagnostic sp name e) >> pure Nothing
          Right pos -> do
            let given = [(k, v) | (Just k, v) <- vs]
                keyword kp = case lookup (kpName kp) given of
                  Nothing -> Right (kpDefault kp)
                  Just v -> maybe (Left (diagnostic "G02121" Error sp ("引数の型が合いません: " <> name <> " のキーワード引数 " <> kpName kp <> " は " <> argTypeText (kpType kp) <> " を求めますが、" <> typeName v <> "です"))) Right (fitValue (kpType kp) v)
            case mapM keyword (prKeywords ps) of
              Left d -> report d >> pure Nothing
              Right kws -> pure (Just (pos <> kws))
  where
    argOf (A.Located asp a) = case a of
      A.Positional v -> A.Located asp v
      A.Keyword _ v -> A.Located asp v
      _ -> A.Located asp (A.Word "")

-- | An inline command of a .emet (docs/adr/0162); after any error, the function is not called.
functionInline :: EvalContext -> Bool -> SrcSpan -> SrcSpan -> Text -> Text -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
functionInline ctx inHeading sp nsp ns n args slots =
  functionNamespace "G02022" nsp ns qualified >>= \case
    Left d -> report d >> pure []
    Right Nothing -> pure []
    Right (Just fns) -> case Map.lookup n (fnInline fns) of
      Nothing -> err "G02022" nsp ("名前空間 " <> ns <> " にないインラインのコマンドです: " <> qualified <> blockHint) >> pure []
        where
          blockHint = if Map.member n (fnBlock fns) then "（ブロックコマンドの @" <> qualified <> " はあります）" else ""
      Just f -> do
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
  where
    qualified = ns <> "." <> n

-- | A block command of a .emet (docs/adr/0162); after any error, the function is not called.
functionBlock :: EvalContext -> SrcSpan -> SrcSpan -> Text -> Text -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
functionBlock ctx sp nsp ns n args body =
  functionNamespace "G02009" nsp ns ("@" <> qualified) >>= \case
    Left d -> report d >> pure []
    Right Nothing -> pure []
    Right (Just fns) -> case Map.lookup n (fnBlock fns) of
      Nothing -> err "G02009" nsp ("名前空間 " <> ns <> " にないブロックコマンドです: @" <> qualified <> inlineHint) >> pure []
        where
          inlineHint = if Map.member n (fnInline fns) then "（インラインのコマンドの [" <> qualified <> "] はあります）" else ""
      Just f -> do
        vals <- functionArgs ctx sp qualified (bfParams f) args
        case vals of
          Nothing -> pure []
          Just vs
            | not (bfBody f) && not (null body) -> err "G02123" sp ("本体を受け取らない関数のブロックコマンドに本体があります: @" <> qualified) >> pure []
            | otherwise -> do
                body' <- evalBlocks ctx body
                case bfCall f vs body' sp of
                  Left ds -> mapM_ report ds >> pure []
                  Right out -> do
                    let out' = map (fillKentenBlock ctx) out
                    ok <- outputChecked ctx sp [] out'
                    pure (if ok then out' else [])
  where
    qualified = ns <> "." <> n

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
      Paragraph (Just x) _ -> [x]
      TableBlock Table {tableStyle = Just x} -> [x]
      _ -> []
    universeBlocks = concatMap (\b -> b : universeBlocks (innerBlocks b))
    innerBlocks (Block _ _ _ body) = case body of
      BulletList items -> concatMap itemBlocks items
      OrderedList items -> concatMap itemBlocks items
      DefList gs -> concat (concatMap dgDefs gs)
      FigureBlock f -> figCaption f
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
      Note _ _ nb -> concat (noteParagraphs nb)
      Sidenote _ _ nb -> concat (noteParagraphs nb)
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
  Note s n bs -> Note s n (mapNoteBody (map (fillKenten ctx)) bs)
  Sidenote s n bs -> Sidenote s n (mapNoteBody (map (fillKenten ctx)) bs)
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
  other -> other
  where
    f = fillKenten ctx

{- | An attribute group and the block it applies to. Without a block after
it, a last block command that is not an attribute (a figure, @style with a
body) is the target (docs/adr ADR 0005).
-}
attributed :: EvalContext -> SrcSpan -> [A.Located A.Block] -> Maybe (A.Located A.Block) -> M [Block]
attributed ctx sp cmds0 target
  -- a file setting inside an attribute group is out of place (docs/adr ADR 0014)
  | any isSettingCommand cmds0 = do
      mapM_ (misplacedSetting . A.locSpan) (filter isSettingCommand cmds0)
      case (filter (not . isSettingCommand) cmds0, target) of
        ([], Just t) -> evalBlock ctx t
        ([], Nothing) -> pure []
        (cmds, _) -> attributed ctx sp cmds target
  | otherwise = attributedWith ctx sp cmds0 target

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
      | otherwise -> err "G02090" sp ("宣言されていないチャネルです: " <> argText v) >> pure []
    _ -> err "G02090" sp "@channel にはチャネルの名前を一つ書きます" >> pure []

-- | G02049: @manifest or @style-def after the file settings (docs/adr ADR 0014).
misplacedSetting :: SrcSpan -> M ()
misplacedSetting sp = err "G02049" sp "@manifest と @style-def はファイルの最初に置きます"

attributedWith :: EvalContext -> SrcSpan -> [A.Located A.Block] -> Maybe (A.Located A.Block) -> M [Block]
attributedWith ctx sp cmds target
  -- the breaks of the group go before its target; the attributes skip them (docs/adr ADR 0017)
  | (breaks@(_ : _), rest) <- partition isBreakCommand cmds = do
      bs <- concat <$> mapM (evalBlock ctx) breaks
      others <- case (rest, target) of
        ([], Just t) -> evalBlock ctx t
        ([], Nothing) -> pure []
        _ -> attributedWith ctx sp rest target
      pure (bs <> others)
  | otherwise = attributedGroup ctx sp cmds target

isBreakCommand :: A.Located A.Block -> Bool
isBreakCommand = \case
  A.Located _ (A.BlockCommand (A.Located _ n) _ _) -> n `elem` ["page-break", "column-break", "no-page-break", "need-lines", "page-lines", "blank-line"]
  _ -> False

attributedGroup :: EvalContext -> SrcSpan -> [A.Located A.Block] -> Maybe (A.Located A.Block) -> M [Block]
attributedGroup ctx sp cmds target = case target of
  Nothing
    | (not . any isAttr) cmds -> concat <$> mapM (evalBlock ctx) cmds
    | (lastCmd : before) <- reverse cmds,
      not (isAttr lastCmd),
      isBlockCommand lastCmd,
      all isAttr before ->
        withAttrs (reverse before) lastCmd
    | not (isAttr (last cmds)) && isBlockCommand (last cmds) ->
        err "G02011" sp "属性のまとまりに属性でないコマンドがあります" >> concat <$> mapM (evalBlock ctx) (filter (not . isAttr) cmds)
    | otherwise -> err "G02010" sp "属性の後にブロックがありません" >> concat <$> mapM (evalBlock ctx) (filter (not . isAttr) cmds)
  -- the commands that are not attributes are evaluated as well, in order (golem-eval ADR 0003)
  Just t -> do
    let nonAttrs = filter (not . isAttr) cmds
    unless (null nonAttrs) $ err "G02011" sp "属性のまとまりに属性でないコマンドがあります"
    before <- concat <$> mapM (evalBlock ctx) nonAttrs
    (before <>) <$> withAttrs (filter isAttr cmds) t
  where
    isAttr (A.Located _ (A.BlockCommand (A.Located _ n) _ body)) = n `elem` attributeCommands && not (n `elem` bodyFormCommands && not (null body))
    isAttr _ = False
    isBlockCommand = \case
      A.Located _ (A.BlockCommand {}) -> True
      _ -> False
    foldM' f z = foldl (\acc x -> acc >>= \a -> f a x) (pure z)
    -- @note takes no attribute (docs/adr/0263)
    withAttrs attrs0 t@(A.Located _ (A.BlockCommand (A.Located _ "note") _ _)) = do
      mapM_ (\(A.Located asp c) -> case c of A.BlockCommand (A.Located _ n) _ _ -> err "G02013" asp ("@" <> n <> " は @note には付けられません"); _ -> pure ()) attrs0
      evalBlock ctx t
    withAttrs attrs0 t = do
      attrs <- catMaybes <$> mapM uniqueAttrKeys attrs0
      -- every line of an attribute already given (golem-eval ADR 0003)
      let named = [(n, asp) | A.Located asp (A.BlockCommand (A.Located _ n) _ _) <- attrs]
          repeated = [asp | (i, (n, asp)) <- zip [0 :: Int ..] named, n `elem` map fst (take i named)]
      mapM_ (\asp -> err "G02012" asp "同じ属性を二度書いています") repeated
      targetBlocks <- case (t, [c | c <- attrs, isStyleCommand c]) of
        (A.Located psp (A.Paragraph is), A.Located csp (A.BlockCommand _ args _) : _) -> styleName ctx csp args >>= \n -> styledParagraph ctx psp n is
        (A.Located tsp (A.Paragraph is), []) -> evalBlock ctx (A.Located tsp (A.Paragraph is))
        -- @style applies to every paragraph of @printings (docs/adr ADR 0033)
        (A.Located _ (A.BlockCommand (A.Located _ "printings") _ _), A.Located csp (A.BlockCommand _ args _) : _) -> do
          n <- styleName ctx csp args
          let styled b = case blockBody b of
                Paragraph _ is -> b {blockBody = Paragraph n is}
                _ -> b
          map styled <$> evalBlock ctx t
        (other, _) -> evalBlock ctx (joinTarget other)
      -- the language of @lang, the one written last (docs/adr ADR 0187)
      lang <- foldM' (\l (A.Located asp c) -> case c of A.BlockCommand (A.Located _ "lang") args _ -> maybe l Just <$> langTag asp args; _ -> pure l) Nothing attrs
      case targetBlocks of
        (Block bsp _ lang0 body : rest) -> do
          -- where G04007 points: the @number line (golem-syntax ADR 0002)
          case [asp | ("number", asp) <- named] of
            (asp : _) -> modify' (\s -> s {stNumberSites = Map.insert bsp asp (stNumberSites s)})
            [] -> pure ()
          (label, body') <- foldM' (applyAttr ctx) (Nothing, body) attrs
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
          {- the blocks of a block command without a language of their own
          take it; otherwise the block after the attributes (docs/adr ADR 0187) -}
          let rest' = if isCommandTarget t then map (withLang lang) rest else rest
          pure (withLang lang (Block bsp label lang0 body'') : rest')
        [] -> pure []
    isCommandTarget = \case
      A.Located _ (A.BlockCommand {}) -> True
      _ -> False
    -- a target that is not a paragraph keeps no newlines
    joinTarget = \case
      A.Located tsp (A.Paragraph is) -> A.Located tsp (A.Paragraph (joinSoftBreaks is))
      other -> other

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
    errors =
      [("G02096", sp, takesNoArguments "printings") | not (null args)]
        <> [("G02097", bsp, takesNoBody "printings") | A.Located bsp _ : _ <- [body]]
        <> [("G02076", sp, "@printings は日本語の本（language = \"ja\"）でだけ使えます") | Map.lookup "language" (ctxMeta ctx) /= Just (VString "ja")]
        <> [("G02098", sp, "マニフェストに [[metadata.printings]] がありません") | not printings]
    line = \case
      VHash h
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

{- | @no-page-break, @need-lines and @page-lines (docs/adr ADR 0030):
G02096 for an argument of @no-page-break, G02070 for a wrong argument of
@need-lines, G02099 for a wrong argument of @page-lines (docs/adr ADR 0060).
-}
pageControl :: SrcSpan -> Text -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
pageControl sp name args body = breakCommand sp name body . fmap PageControl $ case (name, map A.locValue args) of
  ("no-page-break", []) -> Right NoBreak
  ("no-page-break", _) -> Left ("G02096", takesNoArguments name)
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

{- | @blank-line and @blank-line N (docs/adr ADR 0046): one positional
natural number of 1 or more, G02092 otherwise; G02091 out of int64; a
negative number or one that is not an integer is G02103 or G02104
(docs/adr ADR 0102).
-}
blankLine :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
blankLine ctx sp args body
  | not (null body) = bad "@blank-line は本体を持てません"
  | otherwise = case args of
      [] -> ok 1
      [A.Located asp (A.Positional v)] ->
        naturalArg ctx "@blank-line の引数" sp (A.Located asp v) >>= \case
          Right n
            | n < 1 -> bad usage
            | inInt64 (toInteger n) -> ok (fromIntegral n)
            | otherwise -> outOfInt64 sp >> pure []
          Left NaturalReported -> pure []
          Left NotANumber -> bad usage
      _ -> bad usage
  where
    usage = "@blank-line の引数は 1 以上の整数を一つだけ書きます"
    ok n = pure [block sp (BlankLines n)]
    bad m = err "G02092" sp m >> pure []

{- | G02094 (docs/adr ADR 0046): blank lines written in a row, with only
need-lines, page-lines and no-page-break between them, at each one after
the first.
-}
blankLinesInRow :: [Block] -> [Diagnostic]
blankLinesInRow bs =
  [ notice "G02094" sp "続けて書いた @blank-line は @blank-line <N> にまとめて書けます"
  | (i, Block sp _ _ (BlankLines _)) <- zip [0 :: Int ..] bs,
    Block _ _ _ (BlankLines _) : _ <- [dropWhile control (reverse (take i bs))]
  ]
  where
    control b = case blockBody b of
      PageControl _ -> True
      _ -> False

{- | G02072: a no-break next to a page or column break, with only need-lines
and page-lines between them (docs/adr ADR 0030).
-}
conflictingBreaks :: [Block] -> [Diagnostic]
conflictingBreaks bs =
  [ diagnostic "G02072" Error sp ("@no-page-break と " <> breakName k <> " が同じ位置にあります")
  | (i, Block sp _ _ (PageControl NoBreak)) <- zip [0 :: Int ..] bs,
    side <- [reverse (take i bs), drop (i + 1) bs],
    Block _ _ _ (ForcedBreak k) : _ <- [dropWhile soft side]
  ]
  where
    soft b = case blockBody b of
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
them. A forced break, a page control and blank lines in the body are not
at the top of the document (G02059, G02071, G02093).
-}
langBody :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
langBody ctx sp args body = do
  tag <- langTag sp args
  bs <- evalBlocks ctx body
  let (ds, bs') = concat <$> traverse belowTop bs
  mapM_ report ds
  pure (map (withLang tag) bs')

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
    top b = case blockBody b of
      ForcedBreak _ -> ([], [b])
      PageControl _ -> ([], [b])
      BlankLines _ -> ([], [b])
      _ -> belowTop b

-- | The diagnostics and what is left of a block below the top of the document ('nestedBreaks').
belowTop :: Block -> ([Diagnostic], [Block])
belowTop = inner
  where
    inner :: Block -> ([Diagnostic], [Block])
    inner b@(Block sp lbl lang body) = case body of
      ForcedBreak _ -> ([diagnostic "G02059" Error sp "@page-break と @column-break は文書の最上位にだけ置けます"], [])
      PageControl _ -> ([diagnostic "G02071" Error sp "@no-page-break、@need-lines、@page-lines は文書の最上位にだけ置けます"], [])
      BlankLines _ -> ([diagnostic "G02093" Error sp "@blank-line は文書の最上位にだけ置けます"], [])
      BulletList items -> rebuild BulletList <$> traverse item items
      OrderedList items -> rebuild OrderedList <$> traverse item items
      DefList gs -> rebuild DefList <$> traverse (\(DefGroup ts ds) -> DefGroup ts <$> traverse nested ds) gs
      FigureBlock f -> rebuild (\c -> FigureBlock f {figCaption = c}) <$> nested (figCaption f)
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
        Just n
          | Map.notMember n (ctxParaStyles ctx) -> err "G02047" sp ("定義されていない段落スタイルです: " <> n) >> pure (label, body)
          | n == "table" -> pure (label, body)
          | otherwise -> pure (label, TableBlock t {tableStyle = Just n})
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

{- | @note name with its body (docs/adr/0263): the body evaluated here,
its paragraphs the body of the note; G02142 for a name not of one word,
G02140 for a name already defined (the first wins), G02141 at each block
of the body that is not a paragraph, which is dropped, G02143 for no body,
G02013 for @style on a paragraph of the body, whose style is dropped.
It puts out nothing where it is.
-}
noteDefinition :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
noteDefinition ctx sp args body = case args of
  [A.Located _ (A.Positional v)] | Just name <- nameArg v, validLabel name -> do
    defined <- gets (any (\(n, _, _) -> n == name) . stNoteDefs)
    when defined $ err "G02140" sp ("同じ名前の注の本文を二度書いています: " <> name)
    when (null body) $ err "G02143" sp ("@note に本文がありません: " <> name)
    bs <- concat <$> mapM inBody body
    unless defined $ modify' (\s -> s {stNoteDefs = stNoteDefs s <> [(name, sp, bs)]})
    pure []
  _ -> err "G02142" sp noteNameMessage >> pure []
  where
    inBody lb@(A.Located bsp b) = case b of
      A.Paragraph _ -> concatMap paragraphOf <$> evalBlock ctx lb
      A.Attributed cmds t@(Just (A.Located _ (A.Paragraph _))) | any isStyleCommand cmds -> do
        mapM_ (\(A.Located csp _) -> err "G02013" csp "@style は注の本文には付けられません") (filter isStyleCommand cmds)
        concatMap paragraphOf <$> evalBlock ctx (A.Located bsp (A.Attributed (filter (not . isStyleCommand) cmds) t))
      A.Attributed _ (Just (A.Located _ (A.Paragraph _))) -> concatMap paragraphOf <$> evalBlock ctx lb
      -- the body form of @style: G02013, its paragraphs without the style
      A.BlockCommand (A.Located _ "style") _ inner -> do
        err "G02013" bsp "@style は注の本文には付けられません"
        concat <$> mapM inBody [A.Located psp (A.Paragraph (joinSoftBreaks is)) | A.Located psp (A.Paragraph is) <- inner]
      A.ErrorBlock -> pure []
      _ -> err "G02141" bsp "注の本文には段落だけを書けます" >> pure []
    -- a paragraph with a style (a body form of @style) loses it with G02013
    paragraphOf = \case
      Block bsp l lang (Paragraph Nothing is) -> [Block bsp l lang (Paragraph Nothing is)]
      Block bsp l lang (Paragraph (Just _) is) -> [Block bsp l lang (Paragraph Nothing is)]
      _ -> []

{- | The notes written by name take the bodies of their @note
(docs/adr/0263): G02137 for a name no @note of the file defines, G02139
for a second [note] of the same name, which puts out nothing, as one of
a body left without a paragraph does; G02138 for a @note no [note]
names.
-}
namedNotes :: [(SrcSpan, Text)] -> [(Text, SrcSpan, [Block])] -> [Block] -> ([Block], [Diagnostic])
namedNotes refs defs bs
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
              | Map.lookup n firsts /= Just sp -> [diagnostic "G02139" Error sp ("一つの注の本文を二つ以上の [note] が指しています: " <> n)]
              | otherwise -> []
        | (sp, n) <- refs
        ]
    unused = [diagnostic "G02138" Error sp ("使われない注の本文です: " <> n) | (n, sp, _) <- defs, Map.notMember n firsts]
    names = Map.fromList refs
    fill = \case
      Note sp k []
        | Just n <- Map.lookup sp names ->
            case Map.lookup n bodies of
              Just body@(_ : _) | Map.lookup n firsts == Just sp -> [Note sp k body]
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

{- | The name of the paragraph style of @style; G02047 and body when it is
not one name. code is the style of code blocks: G02066 and body
(golem-driver ADR 0017).
-}
styleName :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> M (Maybe Text)
styleName _ sp = \case
  [A.Located _ (A.Positional v)] | nameArg v == Just "code" -> err "G02066" sp "code はコードブロックの段落スタイルです。コードは ``` か @listing で書きます" >> pure Nothing
  [A.Located _ (A.Positional v)] | Just n <- nameArg v -> pure (Just n)
  _ -> err "G02047" sp "@style には段落スタイルの名前を一つ書きます" >> pure Nothing

{- | The body form of @style (docs/adr ADR 0005): every paragraph of the
body in the style.
-}
styleBody :: EvalContext -> SrcSpan -> Int -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
styleBody ctx sp headerEnd args body
  -- no body at all, or a body of comments only (the command spans more than its line)
  | null body && spanEnd sp <= headerEnd + 1 = err "G02010" sp "@style の後にブロックがありません" >> pure []
  | null body = err "G02046" sp "@style の本体に段落がありません" >> pure []
  | not (null others) = mapM_ (\osp -> err "G02045" osp "@style の本体には段落だけを置けます。段落は空行で区切ります") others >> pure []
  | otherwise = do
      name <- styleName ctx sp args
      bs <- concat <$> mapM (\(psp, is) -> styledParagraph ctx psp name is) paragraphs
      case bs of
        [] -> err "G02046" sp "@style の本体に段落がありません" >> pure []
        _ -> pure bs
  where
    paragraphs = [(psp, is) | A.Located psp (A.Paragraph is) <- body]
    others = [bsp | A.Located bsp b <- body, not (isParagraph b), not (isErrorBlock b)]
    isParagraph = \case
      A.Paragraph _ -> True
      _ -> False
    isErrorBlock = \case
      A.ErrorBlock -> True
      _ -> False

{- | A paragraph in a paragraph style (docs/adr ADR 0005). An unknown style
is G02047 and the paragraph is body. With line-breaks = "keep" each line
of the source is a line, joined by 'LineBreak'; a paragraph with no line
left is dropped.
-}
styledParagraph :: EvalContext -> SrcSpan -> Maybe Text -> [A.Located A.Inline] -> M [Block]
styledParagraph ctx sp mname is = case mname of
  Nothing -> joined Nothing
  Just name -> case Map.lookup name (ctxParaStyles ctx) of
    Nothing -> err "G02047" sp ("定義されていない段落スタイルです: " <> name) >> joined Nothing
    Just JoinLines -> joined (styleOf name)
    Just KeepLines -> do
      mapM_ escapedIndent (linesOf Nothing is)
      mapM_ (escapedTrailing . snd) (linesOf Nothing is)
      ls <- filter (not . null . snd) <$> mapM (\(bsp, l) -> (bsp,) <$> evalInlines ctx False (A.plainEscapes (trimLine l))) (linesOf Nothing is)
      pure $ case ls of
        [] -> []
        ((_, first) : rest) -> [block sp (Paragraph (styleOf name) (first <> concat [LineBreak bsp : l | (bsp, l) <- rest]))]
  where
    styleOf n = if n == "body" then Nothing else Just n
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

-- | Paragraph styles a filter made up (docs/adr ADR 0005).
unknownParaStyles :: EvalContext -> Document -> [Diagnostic]
unknownParaStyles ctx (Document _ bs) = concatMap go bs
  where
    go (Block sp _ _ body) = case body of
      Paragraph (Just n) _ | Map.notMember n (ctxParaStyles ctx) -> [diagnostic "G02047" Error sp ("定義されていない段落スタイルです: " <> n)]
      TableBlock Table {tableStyle = Just n} | Map.notMember n (ctxParaStyles ctx) -> [diagnostic "G02047" Error sp ("定義されていない段落スタイルです: " <> n)]
      BulletList items -> concatMap (concatMap go . itemBlocks) items
      OrderedList items -> concatMap (concatMap go . itemBlocks) items
      DefList gs -> concatMap (concatMap (concatMap go) . dgDefs) gs
      FigureBlock f -> concatMap go (figCaption f)
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
  let st0 = St Map.empty Map.empty Map.empty [] Set.empty Map.empty [] 0 0 [] Map.empty Map.empty [] []
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
      caption <- captionParagraphs =<< evalBlocks ctx . concat =<< mapM unstyled body
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
                  Nothing -> pure [block sp (FigureBlock (Figure path web alt wr (look "width") caption (fromRight Nothing page) rot False))]
    _ -> err "G02032" sp "@figure には画像のパスを一つ書きます" >> pure []
  where
    check p = isJust <$> asset ctx sp p
    -- a caption holds paragraphs only: G02118 at each other block, which is dropped (docs/adr/0144)
    captionParagraphs = fmap concat . mapM (\b -> maybe (pure [b]) (\k -> [] <$ err "G02118" (blockSpan b) ("図版のキャプションには段落だけを書けます: " <> k)) (notInCaption (blockBody b)))
    -- a forced break, a page control and blank lines are left to nestedBreaks (G02059, G02071, G02093)
    notInCaption = \case
      Paragraph _ _ -> Nothing
      ForcedBreak _ -> Nothing
      PageControl _ -> Nothing
      BlankLines _ -> Nothing
      FigureBlock _ -> Just "図版"
      BulletList _ -> Just "箇条書き"
      OrderedList _ -> Just "番号付きリスト"
      DefList _ -> Just "定義リスト"
      TableBlock _ -> Just "表"
      CodeBlock _ -> Just "コードブロック"
      Heading {} -> Just "見出し"
      ChannelOutput _ -> Just "一覧の出力"
    -- a caption has no paragraph style of its own (docs/adr ADR 0005, golem-driver ADR 0010)
    noStyle csp = err "G02013" csp "@style は図版のキャプションには付けられません"
    unstyled = \case
      A.Located asp (A.Attributed cs t) | any isStyleCommand cs -> do
        mapM_ (\(A.Located csp _) -> noStyle csp) (filter isStyleCommand cs)
        let rest = filter (not . isStyleCommand) cs
            t' = joinParagraph <$> t
        pure $ case rest of
          [] -> maybe [] pure t'
          _ -> [A.Located asp (A.Attributed rest t')]
      A.Located bsp (A.BlockCommand (A.Located _ "style") _ inner) -> noStyle bsp >> pure (map joinParagraph inner)
      other -> pure [other]
    joinParagraph = \case
      A.Located psp (A.Paragraph is) -> A.Located psp (A.Paragraph (joinSoftBreaks is))
      other -> other

-- ------------------------------------------------------------------ tables (golem-eval ADR 0004)

{- | @table: a table of a CSV or a TSV file. The path is the first argument;
src= is to be retired (G02129), and two paths are G02130 (docs/adr/0184).
The arguments are checked before the file is read: format= (G02080),
align= (G02081) and cells= (G02084); the number of align= values is
checked against the header row.
-}
csvTable :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> M [Block]
csvTable ctx sp args = do
  kw <- keywords ctx args
  -- G02129: the path as src= is to be retired (docs/adr/0184)
  mapM_
    (\asp -> report (notice "G02129" asp "@table の src= は廃止予定です。パスを最初の引数に書きます"))
    [asp | A.Located asp (A.Keyword (A.Located _ "src") _) <- args]
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
  = -- | G02082, G02083 or G02085, in the file
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
file, or a row with another number of cells than the header), G02082, or
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
in the cell, and empty lines are dropped. Left is G02085, G02082, G02083
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
(G02083), or a row whose cells differ in number from the header's (G02085);
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
            Left (TableInvalid (diagnostic "G02085" Error (mkSpan fid s e) (name <> " の行のセルの数が見出しの行と違います（見出しの行は " <> count h <> "、この行は " <> count cs <> "）")))
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
  -- G02065: the path as src= is to be retired (golem-syntax ADR 0002)
  mapM_
    (\asp -> report (notice "G02065" asp "@listing の src= は廃止予定です。パスを最初の引数に書きます"))
    [asp | A.Located asp (A.Keyword (A.Located _ "src") _) <- args]
  let src = case [v | A.Located _ (A.Positional v) <- args] of
        (v : _) -> Just (argText v)
        [] -> argText <$> lookup "src" kw
  case src of
    Nothing -> err "G02036" sp "@listing にはファイルのパスが必要です" >> pure []
    Just p ->
      asset ctx sp p >>= \case
        Just found | Just content <- assetContent found -> do
          let ls = T.lines content
              -- the arguments of a code block, and lang (golem-driver ADR 0023)
              codeArgsOf = [a | a@(A.Located _ (A.Keyword (A.Located _ k) _)) <- args, k `notElem` ["src", "lines"]]
              code start xs = do
                ca <- codeArgs ctx sp ["lang"] codeArgsOf
                -- the lines of a file are not in the source (docs/adr/0218)
                c <- codeOf sp ca start (caLang ca) False [(sp, x) | x <- xs]
                pure [block sp (CodeBlock c)]
          -- the diagnostics of lines= are at the argument (docs/adr ADR 0113)
          let lsp = fromMaybe sp (listToMaybe [asp | A.Located asp (A.Keyword (A.Located _ "lines") _) <- args])
          linesArg <- traverse (lineRanges ctx OneRange "@listing の lines" lsp) (lookup "lines" kw)
          case linesArg of
            Nothing -> code Nothing ls
            Just Nothing -> pure []
            Just (Just (r, rs)) -> case rs of
              [LineRange a b]
                | a >= 1 && b <= fromIntegral (length ls) ->
                    code (Just (toInteger a)) (take (fromIntegral (b - a + 1)) (drop (fromIntegral (a - 1)) ls))
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
              <$> lineRanges ctx AnyRanges "コードブロックの highlight" asp v
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
codeOf :: SrcSpan -> CodeArgs -> Maybe Integer -> Maybe Text -> Bool -> [(SrcSpan, Text)] -> M Code
codeOf bsp ca0 start lang inSource ls = do
  marked <- mapM diffOf ls
  withCallouts <- mapM calloutsOf marked
  let numberedFrom c = snd (mapAccumL number (firstOf c) withCallouts)
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
      _ -> fromMaybe 1 start
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
  where
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
  -- ##N## is [number-text N] (golem-parser ADR 0011)
  A.NumberShorthand t -> case shorthandDigits t of
    Just n -> evalCommand ctx inHeading sp (A.Located sp "number-text") [A.Located sp (A.Positional (A.Word n))] []
    Nothing -> err "G02078" sp "## と ## のあいだには算用数字だけを書きます。本文の ## は \\## と書きます" >> pure []
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

{- | The digits of ##N##: ASCII digits between the two ##, without a
leading zero but 0 itself (golem-parser ADR 0011).
-}
shorthandDigits :: Text -> Maybe Text
shorthandDigits t = do
  inner <- T.stripPrefix "##" t >>= T.stripSuffix "##"
  case T.unpack inner of
    "0" -> Just inner
    (c : _) | c /= '0' && T.all isDigit inner && T.all isAscii inner -> Just inner
    _ -> Nothing

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
  | Just (Overridable o) <- parsed, Just pc <- Map.lookup o (phOverrides (ctxPlugins ctx)) = plugin pc
  | Just b <- parsed = builtin ctx inHeading sp b args slots
  | Just pc <- pluginCommandName name >>= (`Map.lookup` phCommands (ctxPlugins ctx)) = plugin pc
  | Just (ns, n) <- splitNamespace name = functionInline ctx inHeading sp nsp ns n args slots
  | otherwise = err "G02022" nsp ("未知のコマンドです: " <> name) >> pure []
  where
    parsed = parseBuiltin name
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
  | inHeading && b `elem` map Fixed [BRefNumber, BRefTitle, BRefPage] = err "G02014" sp "見出しの中では相互参照を使えません" >> pure []
  | takesNoSlot b && not (null slots) = err "G02038" sp (builtinName b <> " は散文スロットを取りません") >> pure []
  | otherwise = builtinWith ctx inHeading sp b args slots

builtinWith :: EvalContext -> Bool -> SrcSpan -> BuiltinInline -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
builtinWith ctx inHeading sp b args slots = do
  kw <- keywords ctx args
  let pos = [v | A.Located _ (A.Positional v) <- args]
      oneSlot k = case slots of
        [s] -> evalInlines ctx inHeading s >>= k
        _ -> err "G02038" sp (builtinName b <> " には散文スロットが一つ必要です") >> pure []
  case b of
    -- the built-in character styles (docs/adr ADR 0005)
    Overridable BStrong -> oneSlot (pure . pure . CharStyle sp "strong")
    Overridable BBold -> oneSlot (pure . pure . CharStyle sp "bold")
    Overridable BItalic -> oneSlot (pure . pure . CharStyle sp "italic")
    -- [code: ...] is [style code: ...] (golem-driver ADR 0017)
    Overridable BCode -> oneSlot (pure . pure . CharStyle sp "code")
    Overridable BKenten -> do
      let shape = argText <$> lookup "shape" kw
      case shape of
        Just s | s `notElem` kentenShapes -> err "G02039" sp ("未知の圏点の形です: " <> s) >> pure []
        -- without a shape, the default of style.toml (golem-driver ADR 0019)
        _ -> oneSlot (pure . pure . Kenten sp (Just (fromMaybe (ctxDefaultKenten ctx) shape)))
    Overridable BColor -> case pos of
      [v] | Just n <- nameArg v, n `Set.member` ctxSwatches ctx -> oneSlot (pure . pure . Color sp n)
      [v] | Just n <- nameArg v -> err "G02017" sp ("style.toml にないスウォッチです: " <> n) >> pure []
      _ -> err "G02017" sp "color にはスウォッチの名前を一つ書きます" >> pure []
    Overridable BStyle -> case pos of
      [v] | Just n <- nameArg v, n `Set.member` ctxCharStyles ctx -> oneSlot (pure . pure . CharStyle sp n)
      [v] | Just n <- nameArg v -> err "G02018" sp ("定義されていない文字スタイルです: " <> n) >> pure []
      _ -> err "G02018" sp "style には文字スタイルの名前を一つ書きます" >> pure []
    Overridable BTcy -> oneSlot $ \case
      [Text _ t]
        -- G02063: a number reads better as a number (golem-syntax ADR 0002)
        | not (T.null t) && T.all isDigit t && T.all isAscii t -> report (notice "G02063" sp ("数の縦中横は [number-text " <> t <> " style=tcy] でも書けます")) >> pure [Tcy sp t]
        | otherwise -> pure [Tcy sp t]
      [] -> pure []
      _ -> err "G02040" sp "縦中横の中身は地の文に限ります" >> pure []
    Overridable BNumberText -> case [A.Located asp v | A.Located asp (A.Positional v) <- args] of
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
    Fixed BRefNumber -> refTo RefNumber pos
    Fixed BRefTitle -> refTo RefTitle pos
    Fixed BRefPage -> refTo RefPage pos
    -- [note: body], or [note name] of the body of @note name (docs/adr/0263)
    Fixed BNote -> case (args, slots) of
      ([], [_]) -> oneSlot $ \body -> do
        n <- gets ((+ 1) . stNote)
        modify' (\s -> s {stNote = n})
        pure [Note sp n (noteBody sp body)]
      (_ : _, _ : _) -> err "G02038" sp "note は名前を書くと散文スロットを取りません" >> pure []
      ([A.Located _ (A.Positional v)], []) | Just name <- nameArg v, validLabel name -> do
        n <- gets ((+ 1) . stNote)
        modify' (\s -> s {stNote = n, stNoteRefs = stNoteRefs s <> [(sp, name)]})
        pure [Note sp n []]
      (_, []) -> err "G02142" sp noteNameMessage >> pure []
      _ -> err "G02038" sp (builtinName b <> " には散文スロットが一つ必要です") >> pure []
    Fixed BSidenote -> oneSlot $ \body -> do
      n <- gets ((+ 1) . stSidenote)
      modify' (\s -> s {stSidenote = n})
      pure [Sidenote sp n (noteBody sp body)]
    Fixed BIndex -> case slots of
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
                  else pure [IndexMark sp (IndexEntry ts rs)]
      _ -> err "G02038" sp "index には散文スロットが一つ必要です" >> pure []
    Fixed BCite -> cite ctx sp args
    Overridable BRuby -> ruby ctx sp slots
    Fixed BAki -> aki sp args slots
    Fixed BLink -> link ctx inHeading sp args slots
    Fixed BLang -> langSpan ctx inHeading sp args slots
  where
    refTo k = \case
      [v] | validLabel (argText v) -> pure [Ref sp k (argText v)]
      _ -> err "G02026" sp "参照にはラベルの名前を一つ書きます。名前は英小文字、数字、-、_ で書きます" >> pure []

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
akiAmounts = "量には、ベタ、全角、二分、三分、四分、五分、六分、八分、二分四分のどれか、0.2zw のような zw、25% のような百分率、1mm のような寸法のどれかを書きます"

plainText :: [Inline] -> Maybe Text
plainText is = T.concat <$> traverse (\case Text _ t -> Just t; _ -> Nothing) is

ruby :: EvalContext -> SrcSpan -> [[A.Located A.Inline]] -> M [Inline]
ruby ctx sp = \case
  [baseSlot, readingSlot] -> do
    -- the segments are split at the / written in the slots, before they
    -- are evaluated (golem-parser ADR 0010)
    base <- mapM (evalInlines ctx False) (splitSlot '/' baseSlot)
    reading <- mapM (evalInlines ctx False) (splitSlot '/' readingSlot)
    case (traverse (traverse noRuby) base, traverse plainText reading) of
      (Nothing, _) -> err "G02016" sp "ルビの中にルビは入れられません" >> pure []
      (_, Nothing) -> err "G02043" sp "ルビの読みは地の文に限ります" >> pure []
      (Just baseSegs, Just readSegs)
        -- a reading split by '/' needs a base split as many times (golem-eval ADR 0003)
        | length baseSegs /= length readSegs -> err "G02015" sp "モノルビの対象と読みのセグメントの数が一致しません" >> pure []
        | [nb] <- baseSegs, [r] <- readSegs -> pure [Ruby sp () [RubySegment nb (Just r)]]
        | otherwise -> pure [Ruby sp () [RubySegment b (if T.null rd then Nothing else Just rd) | (b, rd) <- zip baseSegs readSegs]]
  _ -> err "G02038" sp "ruby には散文スロットが二つ必要です" >> pure []

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

{- | The arguments with 'duplicateKeys' reported and every repeated keyword
argument dropped: the first of each key is used. The arguments are told
apart by their place, since the keywords of one **[式] share its span.
-}
uniqueKeys :: [A.Located A.Argument] -> M [A.Located A.Argument]
uniqueKeys args = do
  mapM_ report (duplicateKeys args)
  let keyed = [(i, k) | (i, A.Located _ (A.Keyword (A.Located _ k) _)) <- zip [0 :: Int ..] args]
      repeated = [i | (n, (i, k)) <- zip [0 :: Int ..] keyed, k `elem` map snd (take n keyed)]
  pure [a | (i, a) <- zip [0 :: Int ..] args, i `notElem` repeated]

{- | The arguments of a command with *[式] and **[式] spread (docs/adr ADR 0112)
and the repeated keys dropped ('uniqueKeys'). Each element of a spread is
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

-- | A range of lines, both ends included; the first is not after the last (docs/adr ADR 0113).
data LineRange = LineRange !Natural !Natural

-- | How many items a place takes: lines= one, highlight= any (docs/adr ADR 0113).
data RangeCount = OneRange | AnyRanges
  deriving stock (Eq)

-- | An item of a word or a string of ranges, with its ends as written.
data RangeItem
  = -- | one line, @3@
    ItemLine Rational
  | -- | the closed range @3...5@
    ItemRange Rational Rational
  | -- | the range @3-5@, to be retired (G02108), and its ends as written
    ItemDash Text Text Rational Rational

-- | Why an item is not read (docs/adr ADR 0113, ADR 0115).
data ItemError
  = -- | G02110: an end is missing or cannot be read
    ItemBadEnd
  | -- | G01100: the reserved ..
    ItemReserved
  | -- | G02105: neither a line nor a range
    ItemNeither

{- | An argument of lines (lines= of @listing, highlight= of a code
block; docs/adr ADR 0113): Nothing when a diagnostic is reported, else
the text of the value, for the messages of the place, and the ranges in
the order written. @what@ names the place; @sp@ is the argument.

A word or a string is items separated by commas: a line @3@, a range
@3...5@, or the range @3-5@ that is to be retired (G02108, once an
argument). An end is a number literal, a leading - allowed (docs/adr ADR
0102). An expression is a range, a number (one line), a string (read as
a word) or, where any number of items is taken, an array of numbers and
ranges. The ends are natural numbers: G02086, G02103 or G02104 otherwise.
-}
lineRanges :: EvalContext -> RangeCount -> Text -> SrcSpan -> A.ArgValue -> M (Maybe (Text, [LineRange]))
lineRanges ctx count what sp = \case
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
    ofText t = case traverse rangeItem (T.splitOn "," t) of
      Left (ItemBadEnd, i) -> report (rangeEndDiagnostic sp i) >> pure Nothing
      Left (ItemReserved, _) -> err "G01100" sp "予約された記法です。今のバージョンでは使えません" >> pure Nothing
      Left (ItemNeither, i) -> neither i
      Right items
        | count == OneRange && length items > 1 -> notOne t
        | otherwise -> do
            case [(x, y) | ItemDash x y _ _ <- items] of
              (x, y) : _ -> report (notice "G02108" sp ("- で区切った範囲は廃止予定です。" <> x <> "..." <> y <> " のように ... で区切ります"))
              [] -> pure ()
            naturals (map ends items) >>= maybe (pure Nothing) (done t)
    ofValue = \case
      VString s -> ofText s
      VArray vs
        | count == OneRange -> notOne (T.intercalate "," (map valueText vs))
        | otherwise -> case traverse valueEnds vs of
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
    rangeText p q = exactText p <> "..." <> exactText q
    neither v = err "G02105" sp (what <> " には行の番号か範囲を書きます: " <> v) >> pure Nothing
    notOne v = err "G02107" sp (what <> " には範囲を一つだけ書きます: " <> v) >> pure Nothing

{- | An item of a word or a string of ranges (docs/adr ADR 0113), with
the item for the message when it is not read.
-}
rangeItem :: Text -> Either (ItemError, Text) RangeItem
rangeItem i
  | (a, rest) <- T.breakOn "..." i,
    not (T.null rest) =
      case (rangeEndWord a, rangeEndWord (T.drop 3 rest)) of
        (Just p, Just q) -> Right (ItemRange p q)
        _ -> Left (ItemBadEnd, i)
  | ".." `T.isInfixOf` i = Left (ItemReserved, i)
  | Just q <- rangeEndWord i = Right (ItemLine q)
  | Just [a, b] <- rangeEnds i, Just p <- rangeEndWord a, Just q <- rangeEndWord b = Right (ItemDash a b p q)
  | otherwise = Left (ItemNeither, i)

{- | An end of a range written in a word: a number literal, a leading -
allowed (docs/adr ADR 0102). A dot is between digits, as in an
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
outOfInt64 sp = err "G02091" sp "数が意味論 IR に書ける範囲を超えています（整数と、分数の分子と分母は -2 の 63 乗以上、2 の 63 乗未満に限ります）"

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
